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

  /// True when this line was sold by length (e.g. a pipe cut to a number of
  /// feet) rather than by whole unit. [quantity] holds feet in that case.
  final bool isPerFoot;

  /// Whole stock units (e.g. pipes) this line should deduct from stock.
  /// For ordinary lines this equals [quantity]. For per-foot lines it's the
  /// number of whole pipes consumed (feet / feet-per-pipe, rounded up),
  /// computed at sale-creation time since [Product] isn't available later.
  /// Null on older records — see [effectiveStockUnits].
  final int? stockUnits;

  SaleItem({
    required this.productId,
    required this.productName,
    required this.productSize,
    required this.purchasePrice,
    required this.salePrice,
    required this.quantity,
    this.imageBase64,
    this.isPerFoot = false,
    this.stockUnits,
  }) : total = salePrice * quantity;

  /// Stock units to apply for this line. Falls back to [quantity] for
  /// ordinary lines and 0 for per-foot lines saved before [stockUnits]
  /// existed, matching how those older records already behaved (per-foot
  /// sales never touched stock until stockUnits was introduced).
  int get effectiveStockUnits => stockUnits ?? (isPerFoot ? 0 : quantity);

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'productName': productName,
    'productSize': productSize,
    'salePrice': salePrice,
    'purchasePrice': purchasePrice,
    'quantity': quantity,
    'total': total,
    'imageBase64': imageBase64,
    'isPerFoot': isPerFoot,
    'stockUnits': stockUnits,
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
      isPerFoot: map['isPerFoot'] == true,
      stockUnits: map['stockUnits'] as int?,
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
    bool? isPerFoot,
    int? stockUnits,
  }) {
    return SaleItem(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSize: productSize ?? this.productSize,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      salePrice: salePrice ?? this.salePrice,
      quantity: quantity ?? this.quantity,
      imageBase64: imageBase64 ?? this.imageBase64,
      isPerFoot: isPerFoot ?? this.isPerFoot,
      stockUnits: stockUnits ?? this.stockUnits,
    );
  }
}

/// A single payment received against a sale, used to build up [Sale.amountPaid]
/// over time for credit sales that are settled in installments.
class Payment {
  final double amount;
  final DateTime date;
  final String? note;

  Payment({required this.amount, DateTime? date, this.note})
      : date = date ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'amount': amount,
    'date': Timestamp.fromDate(date),
    'note': note,
  };

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      amount: (map['amount'] ?? 0).toDouble(),
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: map['note'],
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

  // Optional buyer details, recorded for future reference on the bill.
  final String? buyerName;
  final String? buyerPhone;
  final String? buyerAddress;

  /// How much of [totalAmount] has actually been received so far. Defaults
  /// to the full amount for every payment method except Credit, where it
  /// defaults to 0 (nothing received yet) unless an initial amount is given.
  final double amountPaid;

  /// History of payments recorded against this sale (used for Credit sales
  /// settled across multiple visits).
  final List<Payment> payments;

  Sale({
    required this.id,
    required this.invoiceNumber,
    required this.items,
    required this.totalAmount,
    DateTime? createdAt,
    this.notes,
    this.paymentMethod = PaymentMethod.cash,
    this.isMock = false,
    this.buyerName,
    this.buyerPhone,
    this.buyerAddress,
    double? amountPaid,
    List<Payment>? payments,
  })  : createdAt = createdAt ?? DateTime.now(),
        amountPaid =
            amountPaid ?? (paymentMethod == PaymentMethod.credit ? 0 : totalAmount),
        payments = payments ?? const [];

  double get amountDue => (totalAmount - amountPaid).clamp(0, double.infinity);
  bool get isFullyPaid => amountDue <= 0.001;
  bool get isCredit => paymentMethod == PaymentMethod.credit;

  Map<String, dynamic> toFirestore() => {
    'invoiceNumber': invoiceNumber,
    'items': items.map((item) => item.toMap()).toList(),
    'totalAmount': totalAmount,
    'createdAt': Timestamp.fromDate(createdAt),
    'notes': notes,
    'paymentMethod': paymentMethod.value,
    'isMock': isMock,
    'buyerName': buyerName,
    'buyerPhone': buyerPhone,
    'buyerAddress': buyerAddress,
    'amountPaid': amountPaid,
    'payments': payments.map((p) => p.toMap()).toList(),
  };

  factory Sale.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final totalAmount = (data['totalAmount'] ?? 0).toDouble();
    return Sale(
      id: doc.id,
      invoiceNumber: data['invoiceNumber']??0,
      items: (data['items'] as List?)
          ?.map((item) => SaleItem.fromMap(item as Map<String, dynamic>))
          .toList() ??
          [],
      totalAmount: totalAmount,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: data['notes'],
      paymentMethod: data['paymentMethod'] != null
          ? PaymentMethodExtension.fromString(data['paymentMethod'])
          : PaymentMethod.cash,
      isMock: data['isMock'] == true,
      buyerName: data['buyerName'],
      buyerPhone: data['buyerPhone'],
      buyerAddress: data['buyerAddress'],
      // Older records predate amountPaid — they were always paid in full.
      amountPaid: data['amountPaid'] != null
          ? (data['amountPaid'] as num).toDouble()
          : totalAmount,
      payments: (data['payments'] as List?)
          ?.map((p) => Payment.fromMap(p as Map<String, dynamic>))
          .toList() ??
          const [],
    );
  }

  // Added copyWith method for Sale
  Sale copyWith({
    String? id,
    int? invoiceNumber,
    List<SaleItem>? items,
    double? totalAmount,
    DateTime? createdAt,
    String? notes,
    PaymentMethod? paymentMethod,
    bool? isMock,
    String? buyerName,
    String? buyerPhone,
    String? buyerAddress,
    double? amountPaid,
    List<Payment>? payments,
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
      buyerName: buyerName ?? this.buyerName,
      buyerPhone: buyerPhone ?? this.buyerPhone,
      buyerAddress: buyerAddress ?? this.buyerAddress,
      amountPaid: amountPaid ?? this.amountPaid,
      payments: payments ?? this.payments,
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