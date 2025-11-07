import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String id;
  final String name;
  final String size;
  final double purchasePrice;
  final double salePrice;
  final int stock;
  final String? imageBase64;
  final DateTime createdAt;
  final int totalSold;
  final String category;        // Required: PPR, CPVC, PVC, Paints, etc.
  final double? gst;            // Optional: GST percentage (e.g., 18.0 for 18%)
  final int saleCount;          // Number of times this product was sold (transaction count)
  final double salesFrequency;  // Sales frequency metric (e.g., sales per day/week)

  Product({
    required this.id,
    required this.name,
    required this.size,
    required this.purchasePrice,
    required this.salePrice,
    required this.stock,
    this.imageBase64,
    required this.createdAt,
    this.totalSold = 0,
    required this.category,
    this.gst,
    this.saleCount = 0,
    this.salesFrequency = 0.0,
  });

  /// Convert Product to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'size': size,
      'purchasePrice': purchasePrice,
      'salePrice': salePrice,
      'stock': stock,
      'imageBase64': imageBase64,
      'createdAt': createdAt.toIso8601String(),
      'totalSold': totalSold,
      'category': category,
      'gst': gst,
      'saleCount': saleCount,
      'salesFrequency': salesFrequency,
    };
  }

  /// Create Product from Map
  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      size: map['size'] ?? '',
      purchasePrice: (map['purchasePrice'] ?? 0).toDouble(),
      salePrice: (map['salePrice'] ?? 0).toDouble(),
      stock: map['stock'] ?? 0,
      imageBase64: map['imageBase64'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      totalSold: map['totalSold'] ?? 0,
      category: map['category'] ?? 'Uncategorized',
      gst: map['gst']?.toDouble(),
      saleCount: map['saleCount'] ?? 0,
      salesFrequency: (map['salesFrequency'] ?? 0.0).toDouble(),
    );
  }

  /// Create Product from Firestore DocumentSnapshot
  factory Product.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Product(
      id: doc.id,
      name: data['name'] ?? '',
      size: data['size'] ?? '',
      purchasePrice: (data['purchasePrice'] ?? 0).toDouble(),
      salePrice: (data['salePrice'] ?? 0).toDouble(),
      stock: data['stock'] ?? 0,
      imageBase64: data['imageBase64'],
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.parse(data['createdAt']))
          : DateTime.now(),
      totalSold: data['totalSold'] ?? 0,
      category: data['category'] ?? 'Uncategorized',
      gst: data['gst']?.toDouble(),
      saleCount: data['saleCount'] ?? 0,
      salesFrequency: (data['salesFrequency'] ?? 0.0).toDouble(),
    );
  }

  /// Create Product from Firestore QueryDocumentSnapshot
  factory Product.fromFirestoreQuery(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Product(
      id: doc.id,
      name: data['name'] ?? '',
      size: data['size'] ?? '',
      purchasePrice: (data['purchasePrice'] ?? 0).toDouble(),
      salePrice: (data['salePrice'] ?? 0).toDouble(),
      stock: data['stock'] ?? 0,
      imageBase64: data['imageBase64'],
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.parse(data['createdAt']))
          : DateTime.now(),
      totalSold: data['totalSold'] ?? 0,
      category: data['category'] ?? 'Uncategorized',
      gst: data['gst']?.toDouble(),
      saleCount: data['saleCount'] ?? 0,
      salesFrequency: (data['salesFrequency'] ?? 0.0).toDouble(),
    );
  }

  /// Copy with method for creating modified copies
  Product copyWith({
    String? id,
    String? name,
    String? size,
    double? purchasePrice,
    double? salePrice,
    int? stock,
    String? imageBase64,
    DateTime? createdAt,
    int? totalSold,
    String? category,
    double? gst,
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
      totalSold: totalSold ?? this.totalSold,
      category: category ?? this.category,
      gst: gst ?? this.gst,
      saleCount: saleCount ?? this.saleCount,
      salesFrequency: salesFrequency ?? this.salesFrequency,
    );
  }

  /// Calculate sales frequency based on product age
  /// Returns sales per day
  double calculateSalesFrequency() {
    final now = DateTime.now();
    final daysSinceCreation = now.difference(createdAt).inDays;

    if (daysSinceCreation == 0) {
      return totalSold.toDouble(); // Same day sales
    }

    return totalSold / daysSinceCreation;
  }

  /// Convert to JSON string
  String toJson() {
    return '''
    {
      "id": "$id",
      "name": "$name",
      "size": "$size",
      "purchasePrice": $purchasePrice,
      "salePrice": $salePrice,
      "stock": $stock,
      "imageBase64": ${imageBase64 != null ? '"$imageBase64"' : 'null'},
      "createdAt": "${createdAt.toIso8601String()}",
      "totalSold": $totalSold,
      "category": "$category",
      "gst": ${gst ?? 'null'},
      "saleCount": $saleCount,
      "salesFrequency": $salesFrequency
    }
    ''';
  }

  @override
  String toString() {
    return 'Product(id: $id, name: $name, size: $size, category: $category, purchasePrice: $purchasePrice, salePrice: $salePrice, stock: $stock, totalSold: $totalSold, saleCount: $saleCount, salesFrequency: $salesFrequency, gst: $gst)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Product && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}