import 'package:cloud_firestore/cloud_firestore.dart';

/// Who a ledger is kept with: a shopkeeper who buys from the shop
/// (customer), or one the shop buys from (supplier).
enum PartyType { customer, supplier }

/// A shopkeeper with a running account (ledger).
///
/// Balance sign convention, for both types: positive means money is still
/// owed on the account — the customer owes the shop, or the shop owes the
/// supplier. Negative means an advance.
class Party {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final PartyType type;

  /// Balance carried over from before the ledger was kept in the app.
  final double openingBalance;
  final DateTime createdAt;

  Party({
    required this.id,
    required this.name,
    required this.type,
    this.phone,
    this.address,
    this.openingBalance = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isCustomer => type == PartyType.customer;

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'phone': phone,
        'address': address,
        'type': type.name,
        'openingBalance': openingBalance,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory Party.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Party(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'],
      address: data['address'],
      type: data['type'] == PartyType.supplier.name
          ? PartyType.supplier
          : PartyType.customer,
      openingBalance: (data['openingBalance'] ?? 0).toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Party copyWith({
    String? name,
    String? phone,
    String? address,
    double? openingBalance,
  }) {
    return Party(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      type: type,
      openingBalance: openingBalance ?? this.openingBalance,
      createdAt: createdAt,
    );
  }
}

/// [bill] raises the balance (a purchase from a supplier, or a manual bill /
/// old due for a customer); [payment] lowers it.
enum LedgerEntryKind { bill, payment }

/// One item on a supplier purchase bill. Its quantity was added to the
/// product's stock when the purchase was saved.
class PurchaseItem {
  final String productId;
  final String name;
  final String size;
  final int quantity;

  /// Purchase rate per unit.
  final double rate;

  PurchaseItem({
    required this.productId,
    required this.name,
    required this.size,
    required this.quantity,
    required this.rate,
  });

  double get total => rate * quantity;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'size': size,
        'quantity': quantity,
        'rate': rate,
      };

  factory PurchaseItem.fromMap(Map<String, dynamic> map) => PurchaseItem(
        productId: map['productId'] ?? '',
        name: map['name'] ?? '',
        size: map['size'] ?? '',
        quantity: (map['quantity'] ?? 0) as int,
        rate: (map['rate'] ?? 0).toDouble(),
      );
}

/// Part of a customer ledger payment applied to one unpaid sale. [payment]
/// is the exact map added to that sale's `payments` array, kept so deleting
/// the ledger payment can remove it again.
class PaymentAllocation {
  final String saleId;
  final double amount;
  final Map<String, dynamic> payment;

  PaymentAllocation({
    required this.saleId,
    required this.amount,
    required this.payment,
  });

  Map<String, dynamic> toMap() => {
        'saleId': saleId,
        'amount': amount,
        'payment': payment,
      };

  factory PaymentAllocation.fromMap(Map<String, dynamic> map) =>
      PaymentAllocation(
        saleId: map['saleId'] ?? '',
        amount: (map['amount'] ?? 0).toDouble(),
        payment: Map<String, dynamic>.from(map['payment'] ?? const {}),
      );
}

/// A manual ledger entry. Sales made through Record Sale are not stored
/// here — they're read from the sales collection by their `partyId`.
class LedgerEntry {
  final String id;
  final String partyId;
  final LedgerEntryKind kind;
  final double amount;
  final DateTime date;
  final String? note;
  final List<PurchaseItem> items;
  final List<PaymentAllocation> allocations;

  LedgerEntry({
    required this.id,
    required this.partyId,
    required this.kind,
    required this.amount,
    required this.date,
    this.note,
    this.items = const [],
    this.allocations = const [],
  });

  Map<String, dynamic> toFirestore() => {
        'partyId': partyId,
        'kind': kind.name,
        'amount': amount,
        'date': Timestamp.fromDate(date),
        'note': note,
        'items': items.map((i) => i.toMap()).toList(),
        'allocations': allocations.map((a) => a.toMap()).toList(),
      };

  factory LedgerEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LedgerEntry(
      id: doc.id,
      partyId: data['partyId'] ?? '',
      kind: data['kind'] == LedgerEntryKind.payment.name
          ? LedgerEntryKind.payment
          : LedgerEntryKind.bill,
      amount: (data['amount'] ?? 0).toDouble(),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: data['note'],
      items: (data['items'] as List?)
              ?.map((i) => PurchaseItem.fromMap(Map<String, dynamic>.from(i)))
              .toList() ??
          const [],
      allocations: (data['allocations'] as List?)
              ?.map((a) =>
                  PaymentAllocation.fromMap(Map<String, dynamic>.from(a)))
              .toList() ??
          const [],
    );
  }
}
