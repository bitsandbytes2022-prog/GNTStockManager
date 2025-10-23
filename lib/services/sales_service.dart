import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/sale_model.dart';

/// Optimized SalesService with Singleton pattern and counter tracking
class SalesService {
  // ==========================================
  // SINGLETON PATTERN
  // ==========================================
  SalesService._internal();
  static final SalesService _instance = SalesService._internal();
  factory SalesService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _salesCollection = 'sales';
  static const String _productsCollection = 'products';
  static const String _statsCollection = 'stats'; // NEW: For aggregated stats

  // ==========================================
  // GLOBAL CACHE
  // ==========================================
  List<Sale>? _cachedSales;
  DateTime? _lastFetchTime;
  static const Duration _cacheValidDuration = Duration(minutes: 10);
  Stream<List<Sale>>? _salesStream;

  // Pagination support
  static const int _pageSize = 50;
  DocumentSnapshot? _lastSaleDocument;
  bool _hasMoreSales = true;

  // ==========================================
  // CREATE SALE WITH COUNTER UPDATES
  // ==========================================
  /// Creates a sale and updates product stock + global stats counters
  /// This reduces the need to read all sales for analytics
  Future<String> createSale(Sale sale) async {
    final batch = _firestore.batch();

    // 1. Add sale document
    final saleRef = _firestore.collection(_salesCollection).doc();
    batch.set(saleRef, sale.toFirestore());

    // 2. Update stock and sales tracking for each product
    for (final item in sale.items) {
      final productRef = _firestore
          .collection(_productsCollection)
          .doc(item.productId);

      batch.update(productRef, {
        'stock': FieldValue.increment(-item.quantity),
        'totalSold': FieldValue.increment(item.quantity),
        'saleCount': FieldValue.increment(1),
        'lastSoldAt': FieldValue.serverTimestamp(),
      });
    }

    // 3. NEW: Update global revenue counter (for analytics optimization)
    final statsRef = _firestore.collection(_statsCollection).doc('revenue');
    batch.set(
      statsRef,
      {
        'totalRevenue': FieldValue.increment(sale.totalAmount),
        'totalSales': FieldValue.increment(1),
        'lastSaleDate': FieldValue.serverTimestamp(),
        // Add payment method tracking
        'paymentMethods.${sale.paymentMethod.value}': FieldValue.increment(sale.totalAmount),
      },
      SetOptions(merge: true),
    );

    // Calculate total profit for this sale
    double totalProfit = 0;
    double totalCost = 0;
    for (final item in sale.items) {
      final itemCost = item.purchasePrice * item.quantity;
      final itemProfit = (item.salePrice - item.purchasePrice) * item.quantity;
      totalCost += itemCost;
      totalProfit += itemProfit;
    }

    // 4. NEW: Update profit counter
    final profitStatsRef = _firestore.collection(_statsCollection).doc('profit');
    batch.set(
      profitStatsRef,
      {
        'totalProfit': FieldValue.increment(totalProfit),
        'totalCost': FieldValue.increment(totalCost),
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    // Update cache optimistically
    if (_cachedSales != null) {
      final newSale = Sale(
        id: saleRef.id,
        items: sale.items,
        totalAmount: sale.totalAmount,
        createdAt: sale.createdAt,
        notes: sale.notes,
        paymentMethod: sale.paymentMethod,
      );
      _cachedSales!.insert(0, newSale);
      debugPrint('⚡ Sale added to cache');
    }

    debugPrint('✅ Sale created: ${saleRef.id}, Revenue: ₹${sale.totalAmount}');
    return saleRef.id;
  }

  // ==========================================
  // STREAM WITH AUTO-CACHING
  // ==========================================
  Stream<List<Sale>> getSalesStream() {
    _salesStream ??= _firestore
        .collection(_salesCollection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final sales = snapshot.docs
          .map((doc) => Sale.fromFirestore(doc))
          .toList();

      // Auto-update cache
      _cachedSales = sales;
      _lastFetchTime = DateTime.now();

      debugPrint('📡 Sales stream updated - ${sales.length} sales');
      return sales;
    });

    return _salesStream!;
  }

  // ==========================================
  // CACHED READ
  // ==========================================
  Future<List<Sale>> getCachedSales() async {
    if (_cachedSales != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheValidDuration) {
      debugPrint('✅ CACHE HIT - ${_cachedSales!.length} cached sales');
      return _cachedSales!;
    }

    debugPrint('❌ CACHE MISS - Fetching sales from Firebase');
    final snapshot = await _firestore
        .collection(_salesCollection)
        .orderBy('createdAt', descending: true)
        .get();

    _cachedSales = snapshot.docs.map((doc) => Sale.fromFirestore(doc)).toList();
    _lastFetchTime = DateTime.now();

    return _cachedSales!;
  }

  // ==========================================
  // PAGINATED FETCH
  // ==========================================
  Future<List<Sale>> getSalesPaginated({bool refresh = false}) async {
    if (refresh) {
      _lastSaleDocument = null;
      _hasMoreSales = true;
    }

    if (!_hasMoreSales) return [];

    Query query = _firestore
        .collection(_salesCollection)
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    if (_lastSaleDocument != null) {
      query = query.startAfterDocument(_lastSaleDocument!);
    }

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) {
      _hasMoreSales = false;
      return [];
    }

    _lastSaleDocument = snapshot.docs.last;
    _hasMoreSales = snapshot.docs.length == _pageSize;

    return snapshot.docs.map((doc) => Sale.fromFirestore(doc)).toList();
  }

  bool get hasMoreSales => _hasMoreSales;

  // ==========================================
  // TIME-FILTERED SALES (Cached)
  // ==========================================
  /// Get sales for a specific date range without fetching everything
  Future<List<Sale>> getSalesInRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    debugPrint('📅 Fetching sales from ${startDate.toLocal()} to ${endDate.toLocal()}');

    final snapshot = await _firestore
        .collection(_salesCollection)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .orderBy('createdAt', descending: true)
        .get();

    debugPrint('✅ Found ${snapshot.docs.length} sales in range');
    return snapshot.docs.map((doc) => Sale.fromFirestore(doc)).toList();
  }

  // ==========================================
  // DELETE SALE WITH COUNTER UPDATES
  // ==========================================
  Future<void> deleteSale(String saleId, List<SaleItem> items) async {
    final batch = _firestore.batch();

    // Get the sale to restore counters
    final saleDoc = await _firestore.collection(_salesCollection).doc(saleId).get();
    final sale = Sale.fromFirestore(saleDoc);

    // 1. Delete sale document
    final saleRef = _firestore.collection(_salesCollection).doc(saleId);
    batch.delete(saleRef);

    // 2. Restore stock and adjust sales tracking
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

    // 3. Update global revenue counter (subtract)
    final statsRef = _firestore.collection(_statsCollection).doc('revenue');
    batch.set(
      statsRef,
      {
        'totalRevenue': FieldValue.increment(-sale.totalAmount),
        'totalSales': FieldValue.increment(-1),
        'paymentMethods.${sale.paymentMethod.value}': FieldValue.increment(-sale.totalAmount),
      },
      SetOptions(merge: true),
    );

    // 4. Update profit counter
    double totalProfit = 0;
    double totalCost = 0;
    for (final item in items) {
      final itemCost = item.purchasePrice * item.quantity;
      final itemProfit = (item.salePrice - item.purchasePrice) * item.quantity;
      totalCost += itemCost;
      totalProfit += itemProfit;
    }

    final profitStatsRef = _firestore.collection(_statsCollection).doc('profit');
    batch.set(
      profitStatsRef,
      {
        'totalProfit': FieldValue.increment(-totalProfit),
        'totalCost': FieldValue.increment(-totalCost),
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    // Update cache
    if (_cachedSales != null) {
      _cachedSales!.removeWhere((s) => s.id == saleId);
    }

    debugPrint('✅ Sale deleted: $saleId');
  }

  // ==========================================
  // OPTIMIZED STATISTICS - Use counters instead of reading all documents
  // ==========================================
  /// Get statistics from counter documents (no need to read all sales!)
  Future<Map<String, dynamic>> getQuickStats() async {
    debugPrint('⚡ Fetching quick stats from counters');

    final revenueDoc = await _firestore.collection(_statsCollection).doc('revenue').get();
    final profitDoc = await _firestore.collection(_statsCollection).doc('profit').get();

    final revenueData = revenueDoc.data() ?? {};
    final profitData = profitDoc.data() ?? {};

    return {
      'totalSales': revenueData['totalSales'] ?? 0,
      'totalRevenue': revenueData['totalRevenue'] ?? 0.0,
      'totalProfit': profitData['totalProfit'] ?? 0.0,
      'totalCost': profitData['totalCost'] ?? 0.0,
      'lastUpdated': revenueData['lastSaleDate'],
      'paymentMethods': revenueData['paymentMethods'] ?? {},
    };
  }

  // ==========================================
  // LEGACY METHOD - Still works but slower
  // ==========================================
  Future<Map<String, dynamic>> getSalesStatistics() async {
    debugPrint('⚠️ Using legacy statistics method (reads all sales)');
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

  // ==========================================
  // TOP SELLING PRODUCTS - Optimized query
  // ==========================================
  Future<List<Map<String, dynamic>>> getTopSellingProducts({int limit = 10}) async {
    debugPrint('🔥 Fetching top $limit selling products');

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
        'imageBase64': data['imageBase64'],
      };
    }).toList();
  }

  // ==========================================
  // CACHE MANAGEMENT
  // ==========================================
  void clearCache() {
    _cachedSales = null;
    _lastFetchTime = null;
    debugPrint('🗑️ Sales cache cleared');
  }

  void invalidateCache() {
    _lastFetchTime = null;
    debugPrint('⚠️ Sales cache invalidated');
  }

  Map<String, dynamic> getCacheStats() {
    return {
      'cached_sales': _cachedSales?.length ?? 0,
      'cache_age_minutes': _lastFetchTime != null
          ? DateTime.now().difference(_lastFetchTime!).inMinutes
          : null,
    };
  }

  void dispose() {
    _salesStream = null;
    clearCache();
    debugPrint('🧹 SalesService disposed');
  }
}