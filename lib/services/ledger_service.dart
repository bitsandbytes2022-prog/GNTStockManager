import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/party_model.dart';
import '../models/sale_model.dart';
import 'firebase_service.dart';
import 'sales_service.dart';

/// Everything the ledger screens need, delivered together so balances are
/// always computed from a consistent set of parties, entries and sales.
class LedgerData {
  final List<Party> parties;
  final List<LedgerEntry> entries;

  /// Non-mock sales linked to a party.
  final List<Sale> partySales;

  LedgerData({
    required this.parties,
    required this.entries,
    required this.partySales,
  });

  List<LedgerEntry> entriesFor(String partyId) =>
      entries.where((e) => e.partyId == partyId).toList();

  List<Sale> salesFor(String partyId) =>
      partySales.where((s) => s.partyId == partyId).toList();

  List<LedgerRow> rowsFor(Party party) =>
      buildLedgerRows(party, salesFor(party.id), entriesFor(party.id));

  double balanceOf(Party party) {
    final rows = rowsFor(party);
    return rows.isEmpty ? party.openingBalance : rows.last.balance;
  }
}

enum LedgerRowSource { opening, sale, salePayment, entry }

/// One line of a party's statement, oldest first, with the running balance
/// after it.
class LedgerRow {
  final DateTime date;
  final String title;
  final String? subtitle;

  /// Raises the balance (sale / purchase / bill).
  final double debit;

  /// Lowers the balance (payment).
  final double credit;
  double balance = 0;

  final LedgerRowSource source;
  final Sale? sale;
  final LedgerEntry? entry;

  LedgerRow({
    required this.date,
    required this.title,
    required this.source,
    this.subtitle,
    this.debit = 0,
    this.credit = 0,
    this.sale,
    this.entry,
  });
}

/// Builds a party's statement.
///
/// For a customer, each linked sale is a debit of its total. Money received
/// against it shows as credits: what was paid at the time of sale, each
/// payment recorded on that bill from the Sales list, and each lump-sum
/// ledger payment (shown once, as its own entry — the per-bill slices it was
/// spread into via [Payment.ledgerEntryId] are not shown again).
List<LedgerRow> buildLedgerRows(
  Party party,
  List<Sale> sales,
  List<LedgerEntry> entries,
) {
  final rows = <LedgerRow>[];
  final isCustomer = party.isCustomer;

  if (party.openingBalance != 0) {
    rows.add(LedgerRow(
      date: party.createdAt,
      title: 'Opening balance',
      source: LedgerRowSource.opening,
      debit: party.openingBalance > 0 ? party.openingBalance : 0,
      credit: party.openingBalance < 0 ? -party.openingBalance : 0,
    ));
  }

  for (final sale in sales) {
    rows.add(LedgerRow(
      date: sale.createdAt,
      title: 'Sale · Invoice #${sale.invoiceNumber}',
      subtitle: _itemsSummary(sale.items.map((i) => i.productName)),
      source: LedgerRowSource.sale,
      debit: sale.totalAmount,
      sale: sale,
    ));

    final paymentsTotal =
        sale.payments.fold<double>(0, (sum, p) => sum + p.amount);
    final paidAtSale = sale.amountPaid - paymentsTotal;
    if (paidAtSale > 0.001) {
      rows.add(LedgerRow(
        date: sale.createdAt,
        title: 'Paid at sale (${sale.paymentMethod.label})',
        subtitle: 'Invoice #${sale.invoiceNumber}',
        source: LedgerRowSource.salePayment,
        credit: paidAtSale,
        sale: sale,
      ));
    }
    for (final payment in sale.payments) {
      if (payment.ledgerEntryId != null) continue;
      rows.add(LedgerRow(
        date: payment.date,
        title: 'Payment received',
        subtitle: [
          'Invoice #${sale.invoiceNumber}',
          if (payment.note?.isNotEmpty ?? false) payment.note!,
        ].join(' · '),
        source: LedgerRowSource.salePayment,
        credit: payment.amount,
        sale: sale,
      ));
    }
  }

  for (final entry in entries) {
    final isBill = entry.kind == LedgerEntryKind.bill;
    final String title;
    if (isBill) {
      title = isCustomer ? 'Bill' : 'Purchase';
    } else {
      title = isCustomer ? 'Payment received' : 'Payment made';
    }
    final details = [
      if (entry.note?.isNotEmpty ?? false) entry.note!,
      if (entry.items.isNotEmpty) _itemsSummary(entry.items.map((i) => i.name)),
    ];
    rows.add(LedgerRow(
      date: entry.date,
      title: title,
      subtitle: details.isEmpty ? null : details.join(' · '),
      source: LedgerRowSource.entry,
      debit: isBill ? entry.amount : 0,
      credit: isBill ? 0 : entry.amount,
      entry: entry,
    ));
  }

  // Oldest first; on the same moment, debits before credits so a bill paid
  // at sale never shows a dip below zero.
  rows.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    if (a.source == LedgerRowSource.opening) return -1;
    if (b.source == LedgerRowSource.opening) return 1;
    return (b.debit > 0 ? 1 : 0).compareTo(a.debit > 0 ? 1 : 0);
  });

  double running = 0;
  for (final row in rows) {
    running += row.debit - row.credit;
    row.balance = running;
  }
  return rows;
}

String _itemsSummary(Iterable<String> names) {
  final list = names.toList();
  if (list.isEmpty) return '';
  if (list.length <= 2) return list.join(', ');
  return '${list.take(2).join(', ')} +${list.length - 2} more';
}

class LedgerService {
  LedgerService._internal();
  static final LedgerService _instance = LedgerService._internal();
  factory LedgerService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _partiesCollection = 'parties';
  static const String _entriesCollection = 'ledger_entries';
  static const String _salesCollection = 'sales';
  static const String _productsCollection = 'products';

  CollectionReference<Map<String, dynamic>> get _parties =>
      _firestore.collection(_partiesCollection);
  CollectionReference<Map<String, dynamic>> get _entries =>
      _firestore.collection(_entriesCollection);

  // ==========================================
  // LIVE DATA
  // ==========================================
  /// Parties, ledger entries and party-linked sales, re-emitted whenever any
  /// of them changes.
  Stream<LedgerData> watch() {
    late StreamController<LedgerData> controller;
    final subs = <StreamSubscription>[];
    List<Party>? parties;
    List<LedgerEntry>? entries;
    List<Sale>? sales;

    void emit() {
      if (parties == null || entries == null || sales == null) return;
      controller.add(LedgerData(
        parties: parties!,
        entries: entries!,
        partySales: sales!,
      ));
    }

    controller = StreamController<LedgerData>(
      onListen: () {
        subs.add(_parties.snapshots().listen((snap) {
          parties = snap.docs.map(Party.fromFirestore).toList()
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          emit();
        }, onError: controller.addError));
        subs.add(_entries.snapshots().listen((snap) {
          entries = snap.docs.map(LedgerEntry.fromFirestore).toList();
          emit();
        }, onError: controller.addError));
        subs.add(_firestore
            .collection(_salesCollection)
            .where('partyId', isGreaterThan: '')
            .snapshots()
            .listen((snap) {
          sales = snap.docs
              .map(Sale.fromFirestore)
              .where((s) => !s.isMock)
              .toList();
          emit();
        }, onError: controller.addError));
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }

  Future<List<Party>> getParties(PartyType type) async {
    final snap =
        await _parties.where('type', isEqualTo: type.name).get();
    return snap.docs.map(Party.fromFirestore).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // ==========================================
  // PARTIES
  // ==========================================
  Future<Party> addParty(Party party) async {
    final ref = await _parties.add(party.toFirestore());
    return Party(
      id: ref.id,
      name: party.name,
      phone: party.phone,
      address: party.address,
      type: party.type,
      openingBalance: party.openingBalance,
      createdAt: party.createdAt,
    );
  }

  Future<void> updateParty(Party party) =>
      _parties.doc(party.id).update(party.toFirestore());

  /// Deletes a party only when nothing is recorded against it, so no
  /// history is lost by accident.
  Future<void> deleteParty(Party party) async {
    final entries =
        await _entries.where('partyId', isEqualTo: party.id).limit(1).get();
    final sales = await _firestore
        .collection(_salesCollection)
        .where('partyId', isEqualTo: party.id)
        .limit(1)
        .get();
    if (entries.docs.isNotEmpty || sales.docs.isNotEmpty) {
      throw Exception(
          '${party.name} has entries in the ledger. Delete those first.');
    }
    await _parties.doc(party.id).delete();
  }

  // ==========================================
  // ENTRIES
  // ==========================================
  /// A supplier purchase or a manual customer bill. Each item's quantity is
  /// added to that product's stock.
  Future<void> addBill({
    required Party party,
    required double amount,
    required DateTime date,
    String? note,
    List<PurchaseItem> items = const [],
  }) async {
    final batch = _firestore.batch();
    final ref = _entries.doc();
    batch.set(
      ref,
      LedgerEntry(
        id: ref.id,
        partyId: party.id,
        kind: LedgerEntryKind.bill,
        amount: amount,
        date: date,
        note: note,
        items: items,
      ).toFirestore(),
    );
    for (final item in items) {
      batch.update(_firestore.collection(_productsCollection).doc(item.productId),
          {'stock': FieldValue.increment(item.quantity)});
    }
    await batch.commit();
    if (items.isNotEmpty) FirebaseService().clearCache();
  }

  /// Records a payment. For a customer, the amount is also applied to their
  /// unpaid bills, oldest first, so each sale's amount due (and the Sales
  /// list's Credit due filter) stays in step with the ledger. Anything left
  /// over stays on the ledger as an advance.
  Future<void> addPayment({
    required Party party,
    required double amount,
    required DateTime date,
    String? note,
  }) async {
    final ref = _entries.doc();
    final allocations = <PaymentAllocation>[];
    final batch = _firestore.batch();

    if (party.isCustomer) {
      final salesSnap = await _firestore
          .collection(_salesCollection)
          .where('partyId', isEqualTo: party.id)
          .get();
      final unpaid = salesSnap.docs
          .map(Sale.fromFirestore)
          .where((s) => !s.isMock && s.amountDue > 0.001)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      var remaining = amount;
      for (final sale in unpaid) {
        if (remaining <= 0.001) break;
        final applied = remaining < sale.amountDue ? remaining : sale.amountDue;
        final payment = Payment(
          amount: applied,
          date: date,
          note: note?.isNotEmpty ?? false ? note : 'Ledger payment',
          ledgerEntryId: ref.id,
        ).toMap();
        allocations.add(PaymentAllocation(
            saleId: sale.id, amount: applied, payment: payment));
        batch.update(_firestore.collection(_salesCollection).doc(sale.id), {
          'amountPaid': FieldValue.increment(applied),
          'payments': FieldValue.arrayUnion([payment]),
        });
        remaining -= applied;
      }
    }

    batch.set(
      ref,
      LedgerEntry(
        id: ref.id,
        partyId: party.id,
        kind: LedgerEntryKind.payment,
        amount: amount,
        date: date,
        note: note,
        allocations: allocations,
      ).toFirestore(),
    );
    await batch.commit();
    if (allocations.isNotEmpty) SalesService().clearCache();
  }

  /// Deletes an entry and undoes its side effects: a payment comes back off
  /// the bills it was applied to, and a purchase's items come back out of
  /// stock. Sales or products deleted since are skipped.
  Future<void> deleteEntry(LedgerEntry entry) async {
    final batch = _firestore.batch();
    for (final allocation in entry.allocations) {
      final saleRef =
          _firestore.collection(_salesCollection).doc(allocation.saleId);
      if (!(await saleRef.get()).exists) continue;
      batch.update(saleRef, {
        'amountPaid': FieldValue.increment(-allocation.amount),
        'payments': FieldValue.arrayRemove([allocation.payment]),
      });
    }
    for (final item in entry.items) {
      final productRef =
          _firestore.collection(_productsCollection).doc(item.productId);
      if (!(await productRef.get()).exists) continue;
      batch.update(productRef, {'stock': FieldValue.increment(-item.quantity)});
    }
    batch.delete(_entries.doc(entry.id));
    await batch.commit();
    if (entry.allocations.isNotEmpty) SalesService().clearCache();
    if (entry.items.isNotEmpty) FirebaseService().clearCache();
  }

  /// Changes an entry's date and note. Amounts are changed by deleting and
  /// re-adding, so allocations and stock are redone correctly.
  Future<void> updateEntryDetails(
    LedgerEntry entry, {
    required DateTime date,
    String? note,
  }) =>
      _entries.doc(entry.id).update({
        'date': Timestamp.fromDate(date),
        'note': note,
      });
}
