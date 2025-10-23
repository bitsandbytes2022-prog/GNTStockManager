import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final bool isSelected;
  final String id;
  final String name;
  final String size;
  final double purchasePrice;
  final double salePrice;
  final String? imageBase64;
  final int stock;
  final DateTime createdAt;
  final int totalSold; // Track total quantity sold
  final int saleCount; // Track number of times sold
  final DateTime? lastSoldAt; // Track when last sold

  Product({
    this.isSelected = false,
    required this.id,
    required this.name,
    required this.size,
    required this.purchasePrice,
    required this.salePrice,
    this.imageBase64,
    this.stock = 0,
    DateTime? createdAt,
    this.totalSold = 0,
    this.saleCount = 0,
    this.lastSoldAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get profitMargin => salePrice - purchasePrice;
  double get profitPercentage =>
      purchasePrice > 0 ? (profitMargin / purchasePrice) * 100 : 0;

  // Calculate sales frequency score (for sorting)
  double get salesFrequency {
    if (saleCount == 0) return 0;

    // Calculate days since creation
    final daysSinceCreation = DateTime.now().difference(createdAt).inDays;
    if (daysSinceCreation == 0) return saleCount.toDouble();

    // Average sales per day
    return saleCount / daysSinceCreation;
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'size': size,
    'purchasePrice': purchasePrice,
    'salePrice': salePrice,
    'imageBase64': imageBase64,
    'stock': stock,
    'createdAt': Timestamp.fromDate(createdAt),
    'totalSold': totalSold,
    'saleCount': saleCount,
    'lastSoldAt': lastSoldAt != null ? Timestamp.fromDate(lastSoldAt!) : null,
  };

  factory Product.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Product(
      id: doc.id,
      name: data['name'] ?? '',
      size: data['size'] ?? '',
      purchasePrice: (data['purchasePrice'] ?? 0).toDouble(),
      salePrice: (data['salePrice'] ?? 0).toDouble(),
      imageBase64: data['imageBase64'],
      stock: data['stock'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalSold: data['totalSold'] ?? 0,
      saleCount: data['saleCount'] ?? 0,
      lastSoldAt: (data['lastSoldAt'] as Timestamp?)?.toDate(),
    );
  }

  Product copyWith({
    String? id,
    String? name,
    String? size,
    double? purchasePrice,
    double? salePrice,
    String? imageBase64,
    int? stock,
    DateTime? createdAt,
    int? totalSold,
    int? saleCount,
    DateTime? lastSoldAt,
    bool? isSelected,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      size: size ?? this.size,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      salePrice: salePrice ?? this.salePrice,
      imageBase64: imageBase64 ?? this.imageBase64,
      stock: stock ?? this.stock,
      createdAt: createdAt ?? this.createdAt,
      totalSold: totalSold ?? this.totalSold,
      saleCount: saleCount ?? this.saleCount,
      lastSoldAt: lastSoldAt ?? this.lastSoldAt,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}