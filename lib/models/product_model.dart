// Updated Product Model with discount and margin fields

import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String id;
  final String name;
  final String size;
  final double purchasePrice;
  final double salePrice;
  final int stock;
  final String? imageBase64;
  final dynamic createdAt; // Can be DateTime or Timestamp
  final String category;
  final String? subcategory; // Optional subcategory within the category
  final double? gst; // GST percentage
  final double? discountReceived; // Discount received from supplier (%)
  final double? sellingDiscount; // Discount offered to customers (%)
  final double? margin; // Profit margin percentage
  final int totalSold;
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
      'stock': stock,
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
      'totalSold': totalSold,
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
      stock: map['stock'] ?? 0,
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
      totalSold: map['totalSold'] ?? 0,
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
    int? stock,
    String? imageBase64,
    dynamic createdAt,
    String? category,
    String? subcategory,
    double? gst,
    double? discountReceived,
    double? sellingDiscount,
    double? margin,
    int? totalSold,
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

  // Check if product is low in stock (less than 10)
  bool get isLowStock => stock < 10;

  // Get display price with rupee symbol
  String get displayPurchasePrice => '₹${purchasePrice.toStringAsFixed(2)}';
  String get displaySalePrice => '₹${salePrice.toStringAsFixed(2)}';

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

  int? get feetPerPipe =>
      pipeFeetPerUnit[category.toLowerCase()] ??
      (subcategory != null ? pipeFeetPerUnit[subcategory!.toLowerCase()] : null);
}