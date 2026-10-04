import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_manager/models/party_model.dart';
import 'package:inventory_manager/models/sale_model.dart';
import 'package:inventory_manager/services/ledger_service.dart';

Sale _sale({
  required String id,
  required double total,
  required DateTime at,
  PaymentMethod method = PaymentMethod.credit,
  double? amountPaid,
  List<Payment> payments = const [],
}) =>
    Sale(
      id: id,
      invoiceNumber: id.hashCode % 1000,
      items: const [],
      totalAmount: total,
      createdAt: at,
      paymentMethod: method,
      partyId: 'p1',
      amountPaid: amountPaid,
      payments: payments,
    );

void main() {
  final customer = Party(
    id: 'p1',
    name: 'Arun',
    type: PartyType.customer,
    openingBalance: 500,
    createdAt: DateTime(2026, 1, 1),
  );

  test('customer balance: opening + sales - every rupee received, once', () {
    // Credit sale of 10300, part-settled by a 3000 ledger payment.
    final s1 = _sale(
      id: 's1',
      total: 10300,
      at: DateTime(2026, 1, 5),
      amountPaid: 3000,
      payments: [
        Payment(amount: 3000, date: DateTime(2026, 1, 10), ledgerEntryId: 'e1'),
      ],
    );
    // Credit sale with 200 paid upfront and 100 recorded later on the bill.
    final s2 = _sale(
      id: 's2',
      total: 1000,
      at: DateTime(2026, 1, 6),
      amountPaid: 300,
      payments: [Payment(amount: 100, date: DateTime(2026, 1, 7))],
    );
    // Cash sale: fully paid at sale.
    final s3 = _sale(
      id: 's3',
      total: 400,
      at: DateTime(2026, 1, 8),
      method: PaymentMethod.cash,
    );
    // The ledger payment was 3500: 3000 went to s1, 500 is an advance.
    final payment = LedgerEntry(
      id: 'e1',
      partyId: 'p1',
      kind: LedgerEntryKind.payment,
      amount: 3500,
      date: DateTime(2026, 1, 10),
    );

    final rows = buildLedgerRows(customer, [s1, s2, s3], [payment]);

    // 500 + 10300 + 1000 + 400 - 200 - 100 - 400 - 3500
    expect(rows.last.balance, 8000);
    // The 3000 slice of the ledger payment is not shown a second time.
    expect(rows.where((r) => r.credit == 3000), isEmpty);
    // Cash sale nets to zero on the ledger.
    expect(rows.where((r) => r.sale == s3).map((r) => r.debit - r.credit).fold<double>(0, (a, b) => a + b), 0);
  });

  test('supplier balance: purchases raise, payments lower', () {
    final supplier = Party(
      id: 'p2',
      name: 'Supplier',
      type: PartyType.supplier,
      createdAt: DateTime(2026, 1, 1),
    );
    final rows = buildLedgerRows(supplier, const [], [
      LedgerEntry(
          id: 'a',
          partyId: 'p2',
          kind: LedgerEntryKind.bill,
          amount: 5000,
          date: DateTime(2026, 2, 1)),
      LedgerEntry(
          id: 'b',
          partyId: 'p2',
          kind: LedgerEntryKind.payment,
          amount: 2000,
          date: DateTime(2026, 2, 3)),
    ]);
    expect(rows.map((r) => r.balance), [5000, 3000]);
  });

  test('customer we also buy from: purchases lower, payments to them raise',
      () {
    final shop = Party(
      id: 'p3',
      name: 'Two-way',
      type: PartyType.customer,
      createdAt: DateTime(2026, 1, 1),
    );
    final sale = _sale(id: 'sx', total: 1000, at: DateTime(2026, 3, 1))
        .copyWith(partyId: 'p3');
    LedgerEntry e(String id, LedgerEntryKind kind, double amount, int day) =>
        LedgerEntry(
          id: id,
          partyId: 'p3',
          kind: kind,
          amount: amount,
          date: DateTime(2026, 3, day),
        );
    final rows = buildLedgerRows(shop, [sale], [
      e('b1', LedgerEntryKind.boughtFrom, 1500, 2),
      e('p1', LedgerEntryKind.paidTo, 300, 3),
    ]);
    // They owe 1000, the shop buys 1500 from them (shop now owes 500),
    // then pays them 300 (shop owes 200).
    expect(rows.map((r) => r.balance), [1000, -500, -200]);
    expect(rows[1].title, 'Bought from them');
    expect(rows[1].credit, 1500);
    expect(rows[2].title, 'Paid to them');
    expect(rows[2].debit, 300);
  });

  test('entry kinds round-trip by name, unknown falls back to bill', () {
    for (final k in LedgerEntryKind.values) {
      expect(LedgerEntryKind.fromName(k.name), k);
    }
    expect(LedgerEntryKind.fromName(null), LedgerEntryKind.bill);
    expect(LedgerEntryKind.fromName('something'), LedgerEntryKind.bill);
  });
}
