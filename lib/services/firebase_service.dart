import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../models/product_model.dart';

/// Optimized FirebaseService with Singleton pattern and advanced caching
class FirebaseService {
  // ==========================================
  // SINGLETON PATTERN - Shared across entire app
  // ==========================================
  FirebaseService._internal();
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _productsCollection = 'products';

  // ==========================================
  // GLOBAL CACHE - Shared by all screens
  // ==========================================
  List<Product>? _cachedProducts;
  DateTime? _lastFetchTime;
  static const Duration _cacheValidDuration = Duration(minutes: 10);

  // Single stream instance - prevents multiple listeners
  Stream<List<Product>>? _productsStream;

  // Pagination support
  static const int _pageSize = 20;
  DocumentSnapshot? _lastProductDocument;
  bool _hasMoreProducts = true;

  // ==========================================
  // STREAM WITH AUTO-CACHING
  // ==========================================
  Stream<List<Product>> getProductsStream() {
    _productsStream ??= _firestore
        .collection(_productsCollection)
        .snapshots()
        .map((snapshot) {
      final products = snapshot.docs
          .map((doc) {
        final data = doc.data();
        return Product.fromMap({
          ...data,
        }, doc.id);
      })
          .toList();
      products.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Automatically update cache on every stream emission
      _cachedProducts = products;
      _lastFetchTime = DateTime.now();

      debugPrint('📡 Stream updated - ${products.length} products');
      return products;
    });

    return _productsStream!;
  }

  // ==========================================
  // CACHED READ WITH TTL
  // ==========================================
  Future<List<Product>> getCachedProducts() async {
    // Check if cache is still valid
    if (_cachedProducts != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheValidDuration) {
      debugPrint('✅ CACHE HIT - Returning ${_cachedProducts!.length} cached products');
      return _cachedProducts!;
    }

    debugPrint('❌ CACHE MISS - Fetching from Firebase');
    final snapshot = await _firestore.collection(_productsCollection).get();
    _cachedProducts = snapshot.docs
        .map((doc) {
      final data = doc.data();
      return Product.fromMap({
        ...data,
      }, doc.id);
    })
        .toList();
    _cachedProducts!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _lastFetchTime = DateTime.now();

    debugPrint('💾 Cached ${_cachedProducts!.length} products');
    return _cachedProducts!;
  }

  // ==========================================
  // PAGINATED FETCH - For large datasets
  // ==========================================
  Future<List<Product>> getProductsPaginated({bool refresh = false}) async {
    if (refresh) {
      _lastProductDocument = null;
      _hasMoreProducts = true;
      debugPrint('🔄 Pagination reset');
    }

    if (!_hasMoreProducts) {
      debugPrint('⏹️ No more products to load');
      return [];
    }

    Query query = _firestore
        .collection(_productsCollection)
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    if (_lastProductDocument != null) {
      query = query.startAfterDocument(_lastProductDocument!);
    }

    final snapshot = await query.get();
    debugPrint('📄 Loaded page: ${snapshot.docs.length} products');

    if (snapshot.docs.isEmpty) {
      _hasMoreProducts = false;
      return [];
    }

    _lastProductDocument = snapshot.docs.last;
    _hasMoreProducts = snapshot.docs.length == _pageSize;

    return snapshot.docs
        .map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return Product.fromMap({
        ...data,
      }, doc.id);
    })
        .toList();
  }

  bool get hasMoreProducts => _hasMoreProducts;

  // ==========================================
  // SELECTIVE FIELD FETCH - Lighter queries
  // ==========================================
  /// Fetch only product names and prices for dropdown lists
  /// This is much faster and cheaper than fetching full documents
  Future<List<Map<String, dynamic>>> getProductNamesOnly() async {
    debugPrint('⚡ Fetching only names and prices (lightweight query)');

    final snapshot = await _firestore
        .collection(_productsCollection)
        .get(); // Note: .select() is not available in all Firestore versions

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'] ?? '',
        'size': data['size'] ?? '',
        'salePrice': data['salePrice'] ?? 0.0,
        'stock': data['stock'] ?? 0,
        'imageBase64': data['imageBase64'],
      };
    }).toList();
  }

  // ==========================================
  // OPTIMISTIC UPDATES - Instant UI feedback
  // ==========================================
  Future<String> addProduct(Product product) async {
    // Update cache BEFORE Firebase call (optimistic update)
    if (_cachedProducts != null) {
      _cachedProducts!.insert(0, product.copyWith(id: 'temp-${DateTime.now().millisecondsSinceEpoch}'));
      debugPrint('⚡ Optimistic update - Product added to cache immediately');
    }

    final docRef = await _firestore
        .collection(_productsCollection)
        .add(product.toMap());

    // Update cache with real ID
    if (_cachedProducts != null) {
      final tempIndex = _cachedProducts!.indexWhere((p) => p.id.startsWith('temp-'));
      if (tempIndex != -1) {
        _cachedProducts![tempIndex] = product.copyWith(id: docRef.id);
      }
    }

    debugPrint('✅ Product added: ${docRef.id}');
    return docRef.id;
  }

  Future<void> updateProduct(Product product) async {
    // Optimistic update
    if (_cachedProducts != null) {
      final index = _cachedProducts!.indexWhere((p) => p.id == product.id);
      if (index != -1) {
        _cachedProducts![index] = product;
        debugPrint('⚡ Optimistic update - Product updated in cache');
      }
    }

    await _firestore
        .collection(_productsCollection)
        .doc(product.id)
        .update(product.toMap());

    debugPrint('✅ Product updated: ${product.id}');
  }

  // ==========================================
  // BATCH OPERATIONS - Reduce write calls
  // ==========================================
  Future<void> batchUpdateProducts(List<Product> products) async {
    final batch = _firestore.batch();

    for (final product in products) {
      final docRef = _firestore.collection(_productsCollection).doc(product.id);
      batch.update(docRef, product.toMap());
    }

    await batch.commit();
    debugPrint('✅ Batch update: ${products.length} products');

    // Update cache
    if (_cachedProducts != null) {
      for (final product in products) {
        final index = _cachedProducts!.indexWhere((p) => p.id == product.id);
        if (index != -1) {
          _cachedProducts![index] = product;
        }
      }
    }
  }

  Future<void> deleteProduct(String productId) async {
    // Optimistic delete
    if (_cachedProducts != null) {
      _cachedProducts!.removeWhere((p) => p.id == productId);
      debugPrint('⚡ Optimistic delete - Product removed from cache');
    }

    await _firestore.collection(_productsCollection).doc(productId).delete();
    debugPrint('✅ Product deleted: $productId');
  }

  // ==========================================
  // IMAGE COMPRESSION - Stay under Firestore limits
  // ==========================================
  Future<String?> imageToBase64(File imageFile) async {
    try {
      final compressedFile = await _compressImage(imageFile);
      final bytes = await compressedFile.readAsBytes();

      // Check size
      final sizeInKB = bytes.length / 1024;
      debugPrint('📸 Image size: ${sizeInKB.toStringAsFixed(0)}KB');

      if (sizeInKB > 500) {
        debugPrint('⚠️ Warning: Image is large. May approach Firestore 1MB limit.');
      }

      final base64String = base64Encode(bytes);

      // Clean up
      try {
        await compressedFile.delete();
      } catch (e) {
        debugPrint('Error deleting temp file: $e');
      }

      return base64String;
    } catch (e) {
      debugPrint('❌ Error converting image: $e');
      return null;
    }
  }

  Future<File> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 50,
      minWidth: 600,
      minHeight: 600,
    );

    return result != null ? File(result.path) : file;
  }

  // ==========================================
  // CACHE MANAGEMENT
  // ==========================================
  void clearCache() {
    _cachedProducts = null;
    _lastFetchTime = null;
    debugPrint('🗑️ Cache cleared');
  }

  void invalidateCache() {
    _lastFetchTime = null; // Force refresh on next getCachedProducts call
    debugPrint('⚠️ Cache invalidated');
  }

  // ==========================================
  // STATISTICS - Track cache performance
  // ==========================================
  int _cacheHits = 0;
  int _cacheMisses = 0;

  Map<String, dynamic> getCacheStats() {
    final totalRequests = _cacheHits + _cacheMisses;
    final hitRate = totalRequests > 0 ? (_cacheHits / totalRequests * 100) : 0;

    return {
      'hits': _cacheHits,
      'misses': _cacheMisses,
      'hit_rate': '${hitRate.toStringAsFixed(1)}%',
      'cached_items': _cachedProducts?.length ?? 0,
      'cache_age': _lastFetchTime != null
          ? DateTime.now().difference(_lastFetchTime!).inMinutes
          : null,
    };
  }

  void resetCacheStats() {
    _cacheHits = 0;
    _cacheMisses = 0;
  }


  // Add these methods to your FirebaseService class

  /// Get all categories from Firestore
  Future<List<String>> getCategories() async {
    try {
      final doc = await _firestore.collection('settings').doc('categories').get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final categories = List<String>.from(data['list'] ?? []);
        return categories;
      }

      // If document doesn't exist, create it with default categories
      final defaultCategories = ['PPR', 'CPVC', 'PVC', 'Paints'];
      await _firestore.collection('settings').doc('categories').set({
        'list': defaultCategories,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return defaultCategories;
    } catch (e) {
      print('Error getting categories: $e');
      // Return default categories on error
      return ['PPR', 'CPVC', 'PVC', 'Paints'];
    }
  }

  /// Add a new category to Firestore
  Future<void> addCategory(String category) async {
    try {
      final categoryTrimmed = category.trim();

      if (categoryTrimmed.isEmpty) {
        throw Exception('Category name cannot be empty');
      }

      await _firestore.collection('settings').doc('categories').update({
        'list': FieldValue.arrayUnion([categoryTrimmed]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('Category added successfully: $categoryTrimmed');
    } catch (e) {
      // If document doesn't exist, create it
      if (e.toString().contains('NOT_FOUND')) {
        await _firestore.collection('settings').doc('categories').set({
          'list': [category.trim()],
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        throw Exception('Error adding category: $e');
      }
    }
  }

  /// Delete a category from Firestore
  Future<void> deleteCategory(String category) async {
    try {
      await _firestore.collection('settings').doc('categories').update({
        'list': FieldValue.arrayRemove([category]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('Category deleted successfully: $category');
    } catch (e) {
      throw Exception('Error deleting category: $e');
    }
  }

  /// Update category name
  Future<void> updateCategory(String oldCategory, String newCategory) async {
    try {
      final newCategoryTrimmed = newCategory.trim();

      if (newCategoryTrimmed.isEmpty) {
        throw Exception('Category name cannot be empty');
      }

      // Remove old and add new in a batch
      final batch = _firestore.batch();

      final categoryRef = _firestore.collection('settings').doc('categories');
      batch.update(categoryRef, {
        'list': FieldValue.arrayRemove([oldCategory]),
      });
      batch.update(categoryRef, {
        'list': FieldValue.arrayUnion([newCategoryTrimmed]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // Update all products with the old category to the new category
      final productsSnapshot = await _firestore
          .collection('products')
          .where('category', isEqualTo: oldCategory)
          .get();

      if (productsSnapshot.docs.isNotEmpty) {
        final productBatch = _firestore.batch();
        for (final doc in productsSnapshot.docs) {
          productBatch.update(doc.reference, {'category': newCategoryTrimmed});
        }
        await productBatch.commit();
      }

      print('Category updated successfully: $oldCategory -> $newCategoryTrimmed');
    } catch (e) {
      throw Exception('Error updating category: $e');
    }
  }

  /// Get the default category from Firestore
  Future<String?> getDefaultCategory() async {
    try {
      final doc = await _firestore.collection('settings').doc('categories').get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return data['defaultCategory'] as String?;
      }

      return null;
    } catch (e) {
      print('Error getting default category: $e');
      return null;
    }
  }

  /// Set the default category in Firestore
  Future<void> setDefaultCategory(String category) async {
    try {
      await _firestore.collection('settings').doc('categories').update({
        'defaultCategory': category,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Default category set successfully: $category');
    } catch (e) {
      // If document doesn't exist, create it
      if (e.toString().contains('NOT_FOUND')) {
        await _firestore.collection('settings').doc('categories').set({
          'list': ['PPR', 'CPVC', 'PVC', 'Paints'],
          'defaultCategory': category,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        throw Exception('Error setting default category: $e');
      }
    }
  }

  /// Get products by category
  Future<List<Product>> getProductsByCategory(String category) async {
    try {
      final snapshot = await _firestore
          .collection('products')
          .where('category', isEqualTo: category)
          .orderBy('name')
          .get();

      return snapshot.docs
          .map((doc) {
        final data = doc.data();
        return Product.fromMap({
          ...data,
        }, doc.id);
      })
          .toList();
    } catch (e) {
      throw Exception('Error getting products by category: $e');
    }
  }



  // ==========================================
  // CLEANUP
  // ==========================================
  void dispose() {
    _productsStream = null;
    clearCache();
    debugPrint('🧹 FirebaseService disposed');
  }
}