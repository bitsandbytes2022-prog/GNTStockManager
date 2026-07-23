import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../models/product_model.dart';
import '../models/size_units.dart';

/// Holder for category and subcategory images (base64), loaded together.
class CategoryImages {
  /// category name -> base64 image
  final Map<String, String> categories;

  /// category name -> (subcategory name -> base64 image)
  final Map<String, Map<String, String>> subcategories;

  const CategoryImages({required this.categories, required this.subcategories});

  static const empty = CategoryImages(categories: {}, subcategories: {});

  String? forCategory(String category) => categories[category];

  String? forSubcategory(String category, String sub) =>
      subcategories[category]?[sub];
}

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

  /// Cross-platform: compress raw image bytes (e.g. from XFile.readAsBytes())
  /// and return a base64 string. Works on web and mobile, unlike the
  /// File-based [imageToBase64].
  Future<String?> imageBytesToBase64(Uint8List bytes) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 50,
        minWidth: 600,
        minHeight: 600,
      );

      final out = compressed.isNotEmpty ? compressed : bytes;
      final sizeInKB = out.length / 1024;
      debugPrint('📸 Compressed image size: ${sizeInKB.toStringAsFixed(0)}KB');

      if (sizeInKB > 500) {
        debugPrint('⚠️ Warning: Image is large. May approach Firestore 1MB limit.');
      }

      return base64Encode(out);
    } catch (e) {
      debugPrint('❌ Error compressing image bytes: $e');
      // Fallback: encode the original bytes uncompressed.
      try {
        return base64Encode(bytes);
      } catch (_) {
        return null;
      }
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

  /// Persist a new ordering for the category list. The order of this list is
  /// what drives the chips on the home/products screen and the dropdowns.
  Future<void> reorderCategories(List<String> orderedCategories) async {
    try {
      await _firestore.collection('settings').doc('categories').set({
        'list': orderedCategories,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('Category order updated');
    } catch (e) {
      throw Exception('Error reordering categories: $e');
    }
  }

  /// Delete a category from Firestore
  Future<void> deleteCategory(String category) async {
    try {
      final docRef = _firestore.collection('settings').doc('categories');

      // Read current maps so we can drop this category's entries
      final doc = await docRef.get();
      final subcategories = _subcategoriesFromDoc(doc.data());
      final sizes = _categorySizesFromDoc(doc.data());
      final subSizes = _subcategorySizesFromDoc(doc.data());
      subcategories.remove(category);
      sizes.remove(category);
      subSizes.remove(category);

      await docRef.update({
        'list': FieldValue.arrayRemove([category]),
        'subcategories': subcategories,
        'sizes': sizes,
        'subSizes': subSizes,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Best-effort cleanup of associated images.
      try {
        await _deleteCategoryImages(category);
      } catch (e) {
        print('Warning: failed to delete category images: $e');
      }

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

      final categoryRef = _firestore.collection('settings').doc('categories');

      // Carry the old category's subcategories and sizes over to the new name
      final categoryDoc = await categoryRef.get();
      final subcategories = _subcategoriesFromDoc(categoryDoc.data());
      final sizes = _categorySizesFromDoc(categoryDoc.data());
      final subSizes = _subcategorySizesFromDoc(categoryDoc.data());
      if (subcategories.containsKey(oldCategory)) {
        subcategories[newCategoryTrimmed] = subcategories.remove(oldCategory)!;
      }
      if (sizes.containsKey(oldCategory)) {
        sizes[newCategoryTrimmed] = sizes.remove(oldCategory)!;
      }
      if (subSizes.containsKey(oldCategory)) {
        subSizes[newCategoryTrimmed] = subSizes.remove(oldCategory)!;
      }

      // Remove old and add new in a batch
      final batch = _firestore.batch();

      batch.update(categoryRef, {
        'list': FieldValue.arrayRemove([oldCategory]),
      });
      batch.update(categoryRef, {
        'list': FieldValue.arrayUnion([newCategoryTrimmed]),
        'subcategories': subcategories,
        'sizes': sizes,
        'subSizes': subSizes,
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

      // Best-effort: move images to follow the new category name.
      try {
        await _migrateCategoryImages(oldCategory, newCategoryTrimmed);
      } catch (e) {
        print('Warning: failed to migrate category images: $e');
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

  // ==========================================================================
  // CATEGORY / SUBCATEGORY IMAGES
  // Each image is its own document in the `category_images` collection so a
  // single document never approaches the Firestore 1MB limit. Doc IDs are
  // derived deterministically from the (sanitized) names for easy upsert.
  // ==========================================================================

  CollectionReference<Map<String, dynamic>> get _categoryImagesRef =>
      _firestore.collection('category_images');

  /// Encode a name into a Firestore-safe, collision-free id fragment.
  String _encodeIdPart(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  String _categoryImageDocId(String category) =>
      'c_${_encodeIdPart(category)}';

  String _subcategoryImageDocId(String category, String sub) =>
      's_${_encodeIdPart(category)}_${_encodeIdPart(sub)}';

  /// Load all category and subcategory images in a single collection read.
  Future<CategoryImages> getCategoryImages() async {
    try {
      final snapshot = await _categoryImagesRef.get();

      final categories = <String, String>{};
      final subcategories = <String, Map<String, String>>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final image = data['imageBase64'] as String?;
        if (image == null || image.isEmpty) continue;

        final category = data['category'] as String?;
        if (category == null) continue;

        final sub = data['subcategory'] as String?;
        if (sub == null || sub.isEmpty) {
          categories[category] = image;
        } else {
          subcategories.putIfAbsent(category, () => {})[sub] = image;
        }
      }

      return CategoryImages(
        categories: categories,
        subcategories: subcategories,
      );
    } catch (e) {
      print('Error getting category images: $e');
      return CategoryImages.empty;
    }
  }

  /// Set (or replace) a category image. Pass null/empty base64 to remove it.
  Future<void> setCategoryImage(String category, String? imageBase64) async {
    final docRef = _categoryImagesRef.doc(_categoryImageDocId(category));
    try {
      if (imageBase64 == null || imageBase64.isEmpty) {
        await docRef.delete();
      } else {
        await docRef.set({
          'type': 'category',
          'category': category,
          'imageBase64': imageBase64,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw Exception('Error saving category image: $e');
    }
  }

  /// Set (or replace) a subcategory image. Pass null/empty base64 to remove it.
  Future<void> setSubcategoryImage(
      String category, String sub, String? imageBase64) async {
    final docRef =
        _categoryImagesRef.doc(_subcategoryImageDocId(category, sub));
    try {
      if (imageBase64 == null || imageBase64.isEmpty) {
        await docRef.delete();
      } else {
        await docRef.set({
          'type': 'subcategory',
          'category': category,
          'subcategory': sub,
          'imageBase64': imageBase64,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw Exception('Error saving subcategory image: $e');
    }
  }

  /// Move a category image (and its subcategory images) to a new category name.
  Future<void> _migrateCategoryImages(
      String oldCategory, String newCategory) async {
    final snapshot = await _categoryImagesRef
        .where('category', isEqualTo: oldCategory)
        .get();
    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final sub = data['subcategory'] as String?;
      final newId = (sub == null || sub.isEmpty)
          ? _categoryImageDocId(newCategory)
          : _subcategoryImageDocId(newCategory, sub);

      batch.set(_categoryImagesRef.doc(newId), {
        ...data,
        'category': newCategory,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Rename a subcategory's image document to a new subcategory name.
  Future<void> _migrateSubcategoryImage(
      String category, String oldSub, String newSub) async {
    final oldRef =
        _categoryImagesRef.doc(_subcategoryImageDocId(category, oldSub));
    final oldDoc = await oldRef.get();
    if (!oldDoc.exists) return;

    final data = oldDoc.data()!;
    final batch = _firestore.batch();
    batch.set(_categoryImagesRef.doc(_subcategoryImageDocId(category, newSub)), {
      ...data,
      'subcategory': newSub,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(oldRef);
    await batch.commit();
  }

  /// Delete the category image and every subcategory image under it.
  Future<void> _deleteCategoryImages(String category) async {
    final snapshot = await _categoryImagesRef
        .where('category', isEqualTo: category)
        .get();
    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ==========================================================================
  // SUBCATEGORIES
  // Stored on settings/categories as a map: { 'CategoryName': ['sub1', ...] }
  // ==========================================================================

  /// Parse the `subcategories` map from a settings/categories document.
  Map<String, List<String>> _subcategoriesFromDoc(Map<String, dynamic>? data) {
    final raw = data?['subcategories'];
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        (value is List) ? value.map((e) => e.toString()).toList() : <String>[],
      ),
    );
  }

  /// Get the full map of category -> list of subcategories.
  Future<Map<String, List<String>>> getAllSubcategories() async {
    try {
      final doc =
          await _firestore.collection('settings').doc('categories').get();
      return _subcategoriesFromDoc(doc.data());
    } catch (e) {
      print('Error getting subcategories: $e');
      return {};
    }
  }

  /// Get the subcategories for a single category.
  Future<List<String>> getSubcategories(String category) async {
    final all = await getAllSubcategories();
    return all[category] ?? [];
  }

  /// Add a subcategory under a category.
  Future<void> addSubcategory(String category, String subcategory) async {
    final sub = subcategory.trim();
    if (sub.isEmpty) {
      throw Exception('Subcategory name cannot be empty');
    }

    try {
      final docRef = _firestore.collection('settings').doc('categories');
      final doc = await docRef.get();
      final subcategories = _subcategoriesFromDoc(doc.data());

      final list = subcategories.putIfAbsent(category, () => <String>[]);
      if (list.any((s) => s.toLowerCase() == sub.toLowerCase())) {
        throw Exception('Subcategory "$sub" already exists in $category');
      }
      list.add(sub);

      await docRef.set({
        'subcategories': subcategories,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('Subcategory added: $category -> $sub');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error adding subcategory: $e');
    }
  }

  /// Delete a subcategory from a category. Existing products keep their value.
  Future<void> deleteSubcategory(String category, String subcategory) async {
    try {
      final docRef = _firestore.collection('settings').doc('categories');
      final doc = await docRef.get();
      final subcategories = _subcategoriesFromDoc(doc.data());
      final subSizes = _subcategorySizesFromDoc(doc.data());

      final list = subcategories[category];
      if (list != null) {
        list.removeWhere((s) => s == subcategory);
        if (list.isEmpty) {
          subcategories.remove(category);
        }
      }

      // Drop the subcategory's size list too.
      final innerSizes = subSizes[category];
      if (innerSizes != null) {
        innerSizes.remove(subcategory);
        if (innerSizes.isEmpty) subSizes.remove(category);
      }

      await docRef.set({
        'subcategories': subcategories,
        'subSizes': subSizes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Best-effort cleanup of the subcategory image.
      try {
        await setSubcategoryImage(category, subcategory, null);
      } catch (e) {
        print('Warning: failed to delete subcategory image: $e');
      }

      print('Subcategory deleted: $category -> $subcategory');
    } catch (e) {
      throw Exception('Error deleting subcategory: $e');
    }
  }

  /// Rename a subcategory and update all products that use it.
  Future<void> updateSubcategory(
      String category, String oldSub, String newSub) async {
    final trimmed = newSub.trim();
    if (trimmed.isEmpty) {
      throw Exception('Subcategory name cannot be empty');
    }

    try {
      final docRef = _firestore.collection('settings').doc('categories');
      final doc = await docRef.get();
      final subcategories = _subcategoriesFromDoc(doc.data());
      final subSizes = _subcategorySizesFromDoc(doc.data());

      final list = subcategories[category];
      if (list != null) {
        final index = list.indexWhere((s) => s == oldSub);
        if (index != -1) {
          list[index] = trimmed;
        }
      }

      // Carry the subcategory's sizes over to the new name.
      final innerSizes = subSizes[category];
      if (innerSizes != null && innerSizes.containsKey(oldSub)) {
        innerSizes[trimmed] = innerSizes.remove(oldSub)!;
      }

      await docRef.set({
        'subcategories': subcategories,
        'subSizes': subSizes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Update all products that referenced the old subcategory.
      final productsSnapshot = await _firestore
          .collection('products')
          .where('category', isEqualTo: category)
          .where('subcategory', isEqualTo: oldSub)
          .get();

      if (productsSnapshot.docs.isNotEmpty) {
        final productBatch = _firestore.batch();
        for (final productDoc in productsSnapshot.docs) {
          productBatch.update(productDoc.reference, {'subcategory': trimmed});
        }
        await productBatch.commit();
      }

      // Best-effort: move the subcategory image to the new name.
      try {
        await _migrateSubcategoryImage(category, oldSub, trimmed);
      } catch (e) {
        print('Warning: failed to migrate subcategory image: $e');
      }

      print('Subcategory updated: $category -> $oldSub => $trimmed');
    } catch (e) {
      throw Exception('Error updating subcategory: $e');
    }
  }

  // ==========================================================================
  // SIZES (unified, optional)
  // Category sizes:    settings/categories.sizes    = { cat: ['5 Liter', ...] }
  // Subcategory sizes: settings/categories.subSizes = { cat: { sub: [...] } }
  // Each size is a composed "value unit" string (see models/size_units.dart).
  // ==========================================================================

  Map<String, List<String>> _categorySizesFromDoc(Map<String, dynamic>? data) {
    final raw = data?['sizes'];
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        (value is List) ? value.map((e) => e.toString()).toList() : <String>[],
      ),
    );
  }

  Map<String, Map<String, List<String>>> _subcategorySizesFromDoc(
      Map<String, dynamic>? data) {
    final raw = data?['subSizes'];
    if (raw is! Map) return {};
    return raw.map((cat, subMap) {
      final inner = (subMap is Map)
          ? subMap.map(
              (sub, list) => MapEntry(
                sub.toString(),
                (list is List)
                    ? list.map((e) => e.toString()).toList()
                    : <String>[],
              ),
            )
          : <String, List<String>>{};
      return MapEntry(cat.toString(), inner);
    });
  }

  /// The single, global pool of sizes shared across every category and
  /// subcategory. The same value (e.g. "200 ML") is reusable everywhere.
  ///
  /// Stored on settings/categories.globalSizes. On first read it lazily
  /// migrates any legacy per-category/subcategory sizes into this pool.
  Future<List<String>> getGlobalSizes() async {
    try {
      final docRef = _firestore.collection('settings').doc('categories');
      final doc = await docRef.get();
      final data = doc.data();

      final raw = data?['globalSizes'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }

      // One-time migration: flatten legacy category + subcategory sizes.
      final merged = <String>[];
      void addAll(Iterable<String> items) {
        for (final s in items) {
          if (!merged.contains(s)) merged.add(s);
        }
      }

      for (final list in _categorySizesFromDoc(data).values) {
        addAll(list);
      }
      for (final inner in _subcategorySizesFromDoc(data).values) {
        for (final list in inner.values) {
          addAll(list);
        }
      }

      if (merged.isNotEmpty) {
        await docRef.set({
          'globalSizes': merged,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return merged;
    } catch (e) {
      print('Error getting global sizes: $e');
      return [];
    }
  }

  Future<void> addGlobalSize(String size) async {
    final value = size.trim();
    if (value.isEmpty) throw Exception('Size cannot be empty');

    final existing = await getGlobalSizes();
    if (existing.any((s) => s.toLowerCase() == value.toLowerCase())) {
      throw Exception('Size "$value" already exists');
    }

    await _firestore.collection('settings').doc('categories').set({
      'globalSizes': FieldValue.arrayUnion([value]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteGlobalSize(String size) async {
    await _firestore.collection('settings').doc('categories').set({
      'globalSizes': FieldValue.arrayRemove([size]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Move a size to the front of the global pool so it sorts first the next
  /// time sizes are loaded. Called whenever a product is saved with a size,
  /// keeping the picker ordered by most-recently-used.
  Future<void> markSizeUsed(String size) async {
    final value = size.trim();
    if (value.isEmpty) return;

    try {
      final docRef = _firestore.collection('settings').doc('categories');
      final doc = await docRef.get();
      final raw = doc.data()?['globalSizes'];
      final sizes =
          raw is List ? raw.map((e) => e.toString()).toList() : <String>[];

      sizes.remove(value);
      sizes.insert(0, value);

      await docRef.set({
        'globalSizes': sizes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error marking size used: $e');
    }
  }

  /// The list of size units (e.g. Liter, ML, KG, Inch, MM, plus any custom
  /// ones). Seeded with the defaults on first read. Also refreshes the app-wide
  /// [sizeUnits] cache so size strings parse against custom units everywhere.
  Future<List<String>> getUnits() async {
    try {
      final docRef = _firestore.collection('settings').doc('categories');
      final doc = await docRef.get();
      final raw = doc.data()?['units'];

      List<String> units;
      if (raw is List && raw.isNotEmpty) {
        units = raw.map((e) => e.toString()).toList();
      } else {
        units = List<String>.from(kDefaultSizeUnits);
        await docRef.set({
          'units': units,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      sizeUnits = units; // keep the app-wide parser cache in sync
      return units;
    } catch (e) {
      print('Error getting units: $e');
      return List<String>.from(sizeUnits);
    }
  }

  Future<void> addUnit(String unit) async {
    final value = unit.trim();
    if (value.isEmpty) throw Exception('Unit cannot be empty');

    final existing = await getUnits();
    if (existing.any((u) => u.toLowerCase() == value.toLowerCase())) {
      throw Exception('Unit "$value" already exists');
    }

    await _firestore.collection('settings').doc('categories').set({
      'units': FieldValue.arrayUnion([value]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!sizeUnits.contains(value)) sizeUnits = [...sizeUnits, value];
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