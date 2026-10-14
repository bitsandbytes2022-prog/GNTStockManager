// Updated Product Model with discount and margin fields

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/quantity.dart';
import 'size_units.dart';

class Product {
  final String id;
  final String name;
  final String size;
  final double purchasePrice;
  final double salePrice;
  final double stock;
  final String? imageBase64;
  final dynamic createdAt; // Can be DateTime or Timestamp
  final String category;
  final String? subcategory; // Optional subcategory within the category
  final double? gst; // GST percentage
  final double? discountReceived; // Discount received from supplier (%)
  final double? sellingDiscount; // Discount offered to customers (%)
  final double? margin; // Profit margin percentage
  final double? wholesaleMargin; // Margin (%) over purchase price for shopkeeper buyers
  final double? wholesalePrice; // Price charged to shopkeepers (lower margin than retail)
  final double totalSold;
  final int saleCount;
  final double salesFrequency;

  Product({
    required this.id,
    required this.name,
    required this.size,
    required this.purchasePrice,
    required this.salePrice,
    required this.stock,
    required this.imageBase64,
    required this.createdAt,
    this.category = 'Uncategorized',
    this.subcategory,
    this.gst,
    this.discountReceived,
    this.sellingDiscount,
    this.margin,
    this.wholesaleMargin,
    this.wholesalePrice,
    this.totalSold = 0,
    this.saleCount = 0,
    this.salesFrequency = 0.0,
  });

  // Convert Product to Map for Firebase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'size': size,
      'purchasePrice': purchasePrice,
      'salePrice': salePrice,
      'stock': storeQty(stock),
      'imageBase64': imageBase64,
      'createdAt': createdAt is DateTime
          ? Timestamp.fromDate(createdAt as DateTime)
          : createdAt, // Already a Timestamp
      'category': category,
      'subcategory': subcategory,
      'gst': gst,
      'discountReceived': discountReceived,
      'sellingDiscount': sellingDiscount,
      'margin': margin,
      'wholesaleMargin': wholesaleMargin,
      'wholesalePrice': wholesalePrice,
      'totalSold': storeQty(totalSold),
      'saleCount': saleCount,
      'salesFrequency': salesFrequency,
    };
  }

  // Create Product from Firebase Map
  factory Product.fromMap(Map<String, dynamic> map, String documentId) {
    // Handle createdAt which can be Timestamp, String, or null
    dynamic createdAtValue;
    if (map['createdAt'] is Timestamp) {
      createdAtValue = (map['createdAt'] as Timestamp).toDate();
    } else if (map['createdAt'] is String) {
      createdAtValue = DateTime.parse(map['createdAt']);
    } else {
      createdAtValue = DateTime.now();
    }

    return Product(
      id: documentId,
      name: map['name'] ?? '',
      size: map['size'] ?? '',
      purchasePrice: (map['purchasePrice'] ?? 0).toDouble(),
      salePrice: (map['salePrice'] ?? 0).toDouble(),
      stock: readQty(map['stock']),
      imageBase64: map['imageBase64'],
      createdAt: createdAtValue,
      category: map['category'] ?? 'Uncategorized',
      subcategory: (map['subcategory'] as String?)?.isNotEmpty == true
          ? map['subcategory'] as String
          : null,
      gst: map['gst'] != null ? (map['gst'] as num).toDouble() : null,
      discountReceived: map['discountReceived'] != null
          ? (map['discountReceived'] as num).toDouble()
          : null,
      sellingDiscount: map['sellingDiscount'] != null
          ? (map['sellingDiscount'] as num).toDouble()
          : null,
      margin: map['margin'] != null
          ? (map['margin'] as num).toDouble()
          : null,
      wholesaleMargin: map['wholesaleMargin'] != null
          ? (map['wholesaleMargin'] as num).toDouble()
          : null,
      wholesalePrice: map['wholesalePrice'] != null
          ? (map['wholesalePrice'] as num).toDouble()
          : null,
      totalSold: readQty(map['totalSold']),
      saleCount: map['saleCount'] ?? 0,
      salesFrequency: (map['salesFrequency'] ?? 0.0).toDouble(),
    );
  }

  // Copy with method for easy updates
  Product copyWith({
    String? id,
    String? name,
    String? size,
    double? purchasePrice,
    double? salePrice,
    double? stock,
    String? imageBase64,
    dynamic createdAt,
    String? category,
    String? subcategory,
    double? gst,
    double? discountReceived,
    double? sellingDiscount,
    double? margin,
    double? wholesaleMargin,
    double? wholesalePrice,
    double? totalSold,
    int? saleCount,
    double? salesFrequency,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      size: size ?? this.size,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      salePrice: salePrice ?? this.salePrice,
      stock: stock ?? this.stock,
      imageBase64: imageBase64 ?? this.imageBase64,
      createdAt: createdAt ?? this.createdAt,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      gst: gst ?? this.gst,
      discountReceived: discountReceived ?? this.discountReceived,
      sellingDiscount: sellingDiscount ?? this.sellingDiscount,
      margin: margin ?? this.margin,
      wholesaleMargin: wholesaleMargin ?? this.wholesaleMargin,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      totalSold: totalSold ?? this.totalSold,
      saleCount: saleCount ?? this.saleCount,
      salesFrequency: salesFrequency ?? this.salesFrequency,
    );
  }

  // Get DateTime from createdAt (handles both Timestamp and DateTime)
  DateTime get createdAtDateTime {
    if (createdAt is Timestamp) {
      return (createdAt as Timestamp).toDate();
    } else if (createdAt is DateTime) {
      return createdAt as DateTime;
    } else if (createdAt is String) {
      return DateTime.parse(createdAt as String);
    }
    return DateTime.now();
  }

  // Calculate profit per unit
  double get profitPerUnit => salePrice - purchasePrice;

  // Calculate profit percentage
  double get profitPercentage =>
      purchasePrice > 0 ? ((profitPerUnit / purchasePrice) * 100) : 0;

  // Default margin for shopkeeper (wholesale) buyers, used until a product
  // has its own wholesale price saved.
  static const double defaultWholesaleMargin = 5.0;

  /// Wholesale price to charge — the saved one, or purchase price plus the
  /// wholesale margin for products saved before wholesale pricing existed.
  double get effectiveWholesalePrice =>
      wholesalePrice ??
      purchasePrice *
          (1 + (wholesaleMargin ?? defaultWholesaleMargin) / 100);

  // Check if product is low in stock (less than 10)
  bool get isLowStock => stock < 10;

  // Get display price with rupee symbol
  String get displayPurchasePrice => '₹${purchasePrice.toStringAsFixed(2)}';
  String get displaySalePrice => '₹${salePrice.toStringAsFixed(2)}';
  String get displayWholesalePrice =>
      '₹${effectiveWholesalePrice.toStringAsFixed(2)}';

  // Standard pipe length (feet) per pipe type — lets pipes be sold by the
  // foot instead of by whole unit (e.g. cutting 12ft off a 20ft PVC pipe).
  // The pipe type is usually a subcategory (e.g. category "Sanitary" /
  // subcategory "PVC"), but some shops may use it as the category directly,
  // so both are checked.
  static const Map<String, int> pipeFeetPerUnit = {
    'ppr': 10,
    'cpvc': 10,
    'pvc': 20,
  };

  /// A PPR pipe (not a PPR fitting) — these are never discounted. PPR is
  /// either the category itself or a subcategory under Sanitary, and pipes
  /// are told apart from fittings by "pipe" in the name or subcategory.
  bool get isPprPipe {
    final cat = category.toLowerCase().trim();
    final sub = (subcategory ?? '').toLowerCase();
    final isPpr = cat == 'ppr' || sub.contains('ppr');
    return isPpr &&
        (name.toLowerCase().contains('pipe') || sub.contains('pipe'));
  }

  /// Sold by weight — size is in KG (e.g. "1 KG"), so quantity and stock
  /// can be fractional, like 4.6 KG.
  bool get isSoldByWeight => isWeightSize(size);

  /// Unit to show after a quantity of this product ("kg"), or null.
  String? get qtyUnit => qtyUnitForSize(size);

  /// [q] as shown on carts and bills: "4.6 kg", "12 ft", "3".
  String qtyLabel(num q, {bool perFoot = false}) =>
      formatQtyWithUnit(q, size, perFoot: perFoot);

  /// Whether a size string is in KG. Size strings are messy ("1 KG",
  /// "1kg", "2 Kgs"), so the unit is matched loosely.
  static bool isWeightSize(String size) {
    final unit = unitOf(size);
    if (unit != null) return unit.toLowerCase() == 'kg';
    return RegExp(r'(^|[\d\s])(kg|kilo|kilogram)s?\.?$', caseSensitive: false)
        .hasMatch(size.trim());
  }

  /// "kg" for loose KG items ("1 KG" or just "KG"), where quantity is the
  /// weight sold. Null otherwise — including packs like "5 KG", where
  /// quantity counts packs.
  static String? qtyUnitForSize(String size) {
    if (!isWeightSize(size)) return null;
    final v = valueOf(size).replaceAll(RegExp(r'[a-zA-Z.]'), '').trim();
    return (v.isEmpty || double.tryParse(v) == 1) ? 'kg' : null;
  }

  /// A quantity with its unit, for a product of [size].
  static String formatQtyWithUnit(num q, String size, {bool perFoot = false}) {
    if (perFoot) return '${formatQty(q)} ft';
    final unit = qtyUnitForSize(size);
    return unit == null ? formatQty(q) : '${formatQty(q)} $unit';
  }

  int? get feetPerPipe =>
      pipeFeetPerUnit[category.toLowerCase()] ??
      (subcategory != null ? pipeFeetPerUnit[subcategory!.toLowerCase()] : null);
}