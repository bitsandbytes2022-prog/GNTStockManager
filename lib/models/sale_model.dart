import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentMethod {
  cash,
  upi,
  card,
  credit,
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
      case PaymentMethod.credit:
        return 'Credit';
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
      case 'credit':
        return PaymentMethod.credit;
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

  // Added copyWith for SaleItem
  SaleItem copyWith({
    String? productId,
    String? productName,
    String? productSize,
    double? salePrice,
    int? quantity,
    double? purchasePrice,
    String? imageBase64,
  }) {
    return SaleItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSize: productSize ?? this.productSize,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      salePrice: salePrice ?? this.salePrice,
      quantity: quantity ?? this.quantity,
      imageBase64: imageBase64 ?? this.imageBase64,
    );
  }
}

class Sale {
  final String id;
  final int invoiceNumber;
  final List<SaleItem> items;
  final double totalAmount;
  final DateTime createdAt;
  final String? notes;
  final PaymentMethod paymentMethod;

  /// A mock (test) sale: stock is NOT deducted and it is kept out of all
  /// revenue/profit analytics. Used to check profit on a hypothetical sale.
  final bool isMock;

  Sale({
    required this.id,
    required this.invoiceNumber,
    required this.items,
    required this.totalAmount,
    DateTime? createdAt,
    this.notes,
    this.paymentMethod = PaymentMethod.cash,
    this.isMock = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toFirestore() => {
    'items': items.map((item) => item.toMap()).toList(),
    'totalAmount': totalAmount,
    'createdAt': Timestamp.fromDate(createdAt),
    'notes': notes,
    'paymentMethod': paymentMethod.value,
    'isMock': isMock,
  };

  factory Sale.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Sale(
      id: doc.id,
      invoiceNumber: data['invoiceNumber']??0,
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
      isMock: data['isMock'] == true,
    );
  }

  // Added copyWith method for Sale
  Sale copyWith({
    String? id,
    List<SaleItem>? items,
    double? totalAmount,
    DateTime? createdAt,
    String? notes,
    PaymentMethod? paymentMethod,
    bool? isMock,
  }) {
    return Sale(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isMock: isMock ?? this.isMock,
    );
  }
}

// Add this extension to your sale_model.dart file

extension SaleItemExtension on SaleItem {
  /// Create a copy of this SaleItem with some fields replaced
  SaleItem copyWith({
    String? productId,
    String? productName,
    String? productSize,
    int? quantity,
    double? salePrice,
    double? purchasePrice,
    String? imageBase64,
  }) {
    return SaleItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSize: productSize ?? this.productSize,
      quantity: quantity ?? this.quantity,
      salePrice: salePrice ?? this.salePrice,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      imageBase64: imageBase64 ?? this.imageBase64,
    );
  }
}