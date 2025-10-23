import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentMethod {
  cash,
  upi,
  card,
  other,
}

extension PaymentMethodExtension on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.other:
        return 'Other';
    }
  }

  String get value {
    return toString().split('.').last;
  }

  static PaymentMethod fromString(String value) {
    switch (value.toLowerCase()) {
      case 'cash':
        return PaymentMethod.cash;
      case 'upi':
        return PaymentMethod.upi;
      case 'card':
        return PaymentMethod.card;
      case 'other':
        return PaymentMethod.other;
      default:
        return PaymentMethod.cash;
    }
  }
}

class SaleItem {
  final String productId;
  final String productName;
  final String productSize;
  final double salePrice;
  final int quantity;
  final double total;
  final double purchasePrice;
  final String? imageBase64;

  SaleItem({
    required this.productId,
    required this.productName,
    required this.productSize,
    required this.purchasePrice,
    required this.salePrice,
    required this.quantity,
    this.imageBase64,
  }) : total = salePrice * quantity;

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'productSize': productSize,
    'salePrice': salePrice,
    'purchasePrice': purchasePrice,
    'quantity': quantity,
    'total': total,
    'imageBase64': imageBase64,
  };

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      productSize: map['productSize'] ?? '',
      purchasePrice: (map['purchasePrice'] ?? 0).toDouble(),
      salePrice: (map['salePrice'] ?? 0).toDouble(),
      quantity: map['quantity'] ?? 0,
      imageBase64: map['imageBase64'],
    );
  }
}

class Sale {
  final String id;
  final List<SaleItem> items;
  final double totalAmount;
  final DateTime createdAt;
  final String? notes;
  final PaymentMethod paymentMethod; // New field

  Sale({
    required this.id,
    required this.items,
    required this.totalAmount,
    DateTime? createdAt,
    this.notes,
    this.paymentMethod = PaymentMethod.cash, // Default to cash
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toFirestore() => {
    'items': items.map((item) => item.toMap()).toList(),
    'totalAmount': totalAmount,
    'createdAt': Timestamp.fromDate(createdAt),
    'notes': notes,
    'paymentMethod': paymentMethod.value, // Store as string
  };

  factory Sale.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Sale(
      id: doc.id,
      items: (data['items'] as List?)
          ?.map((item) => SaleItem.fromMap(item as Map<String, dynamic>))
          .toList() ??
          [],
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: data['notes'],
      paymentMethod: data['paymentMethod'] != null
          ? PaymentMethodExtension.fromString(data['paymentMethod'])
          : PaymentMethod.cash,
    );
  }
}