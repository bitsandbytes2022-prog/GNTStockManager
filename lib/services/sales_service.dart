import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/sale_model.dart';

class SalesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _salesCollection = 'sales';
  static const String _productsCollection = 'products';

  // Cache for sales
  List<Sale>? _cachedSales;
  DateTime? _lastFetchTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);
  Stream<List<Sale>>? _salesStream;

  // Create a sale and update stock + sales tracking
  Future<String> createSale(Sale sale) async {
    final batch = _firestore.batch();

    // Add sale document
    final saleRef = _firestore.collection(_salesCollection).doc();
    batch.set(saleRef, sale.toFirestore());

    // Update stock and sales tracking for each product
    for (final item in sale.items) {
      final productRef = _firestore
          .collection(_productsCollection)
          .doc(item.productId);

      batch.update(productRef, {
        'stock': FieldValue.increment(-item.quantity),
        'totalSold': FieldValue.increment(item.quantity), // Track total quantity sold
        'saleCount': FieldValue.increment(1), // Track number of sales
        'lastSoldAt': FieldValue.serverTimestamp(), // Track last sale date
      });
    }

    await batch.commit();

    // Update cache
    if (_cachedSales != null) {
      _cachedSales!.insert(0, sale);
    }

    return saleRef.id;
  }

  // Get sales stream
  Stream<List<Sale>> getSalesStream() {
    _salesStream ??= _firestore
        .collection(_salesCollection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final sales = snapshot.docs
          .map((doc) => Sale.fromFirestore(doc))
          .toList();

      // Update cache
      _cachedSales = sales;
      _lastFetchTime = DateTime.now();

      return sales;
    });

    return _salesStream!;
  }

  // Get cached sales
  Future<List<Sale>> getCachedSales() async {
    if (_cachedSales != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheValidDuration) {
      return _cachedSales!;
    }

    final snapshot = await _firestore
        .collection(_salesCollection)
        .orderBy('createdAt', descending: true)
        .get();

    _cachedSales = snapshot.docs.map((doc) => Sale.fromFirestore(doc)).toList();
    _lastFetchTime = DateTime.now();

    return _cachedSales!;
  }

  // Delete sale (restores stock and adjusts sales tracking)
  Future<void> deleteSale(String saleId, List<SaleItem> items) async {
    final batch = _firestore.batch();

    // Delete sale document
    final saleRef = _firestore.collection(_salesCollection).doc(saleId);
    batch.delete(saleRef);

    // Restore stock and adjust sales tracking
    for (final item in items) {
      final productRef = _firestore
          .collection(_productsCollection)
          .doc(item.productId);

      batch.update(productRef, {
        'stock': FieldValue.increment(item.quantity),
        'totalSold': FieldValue.increment(-item.quantity),
        'saleCount': FieldValue.increment(-1),
      });
    }

    await batch.commit();

    // Update cache
    if (_cachedSales != null) {
      _cachedSales!.removeWhere((s) => s.id == saleId);
    }
  }

  // Clear cache
  void clearCache() {
    _cachedSales = null;
    _lastFetchTime = null;
  }

  // Get sales statistics
  Future<Map<String, dynamic>> getSalesStatistics() async {
    final sales = await getCachedSales();

    if (sales.isEmpty) {
      return {'totalSales': 0, 'totalRevenue': 0.0, 'totalItems': 0};
    }

    final totalRevenue = sales.fold<double>(
      0,
          (sum, sale) => sum + sale.totalAmount,
    );

    final totalItems = sales.fold<int>(
      0,
          (sum, sale) =>
      sum +
          sale.items.fold<int>(0, (itemSum, item) => itemSum + item.quantity),
    );

    return {
      'totalSales': sales.length,
      'totalRevenue': totalRevenue,
      'totalItems': totalItems,
    };
  }

  // Get top selling products
  Future<List<Map<String, dynamic>>> getTopSellingProducts({int limit = 10}) async {
    final snapshot = await _firestore
        .collection(_productsCollection)
        .orderBy('totalSold', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'] ?? '',
        'size': data['size'] ?? '',
        'totalSold': data['totalSold'] ?? 0,
        'saleCount': data['saleCount'] ?? 0,
      };
    }).toList();
  }
}