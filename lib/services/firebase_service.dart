
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../models/product_model.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _productsCollection = 'products';

  // Cache for products to minimize reads
  List<Product>? _cachedProducts;
  DateTime? _lastFetchTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  // Single listener to minimize real-time listeners
  Stream<List<Product>>? _productsStream;

  // Get products stream (reuses single stream)
  Stream<List<Product>> getProductsStream() {
    _productsStream ??= _firestore
        .collection(_productsCollection)
        .snapshots()
        .map((snapshot) {
      final products = snapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();
      products.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Update cache
      _cachedProducts = products;
      _lastFetchTime = DateTime.now();

      return products;
    });

    return _productsStream!;
  }

  // Get cached products (no Firebase call if cache is valid)
  Future<List<Product>> getCachedProducts() async {
    if (_cachedProducts != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheValidDuration) {
      return _cachedProducts!;
    }

    // Cache expired or doesn't exist, fetch from Firebase
    final snapshot = await _firestore.collection(_productsCollection).get();
    _cachedProducts = snapshot.docs
        .map((doc) => Product.fromFirestore(doc))
        .toList();
    _cachedProducts!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _lastFetchTime = DateTime.now();

    return _cachedProducts!;
  }

  // Add product with optimistic update
  Future<String> addProduct(Product product) async {
    final docRef = await _firestore
        .collection(_productsCollection)
        .add(product.toFirestore());

    // Update cache immediately
    if (_cachedProducts != null) {
      _cachedProducts!.insert(0, product.copyWith(id: docRef.id));
    }

    return docRef.id;
  }

  // Update product with optimistic update
  Future<void> updateProduct(Product product) async {
    await _firestore
        .collection(_productsCollection)
        .doc(product.id)
        .update(product.toFirestore());

    // Update cache immediately
    if (_cachedProducts != null) {
      final index = _cachedProducts!.indexWhere((p) => p.id == product.id);
      if (index != -1) {
        _cachedProducts![index] = product;
      }
    }
  }

  // Batch update multiple products (reduces writes)
  Future<void> batchUpdateProducts(List<Product> products) async {
    final batch = _firestore.batch();

    for (final product in products) {
      final docRef = _firestore.collection(_productsCollection).doc(product.id);
      batch.update(docRef, product.toFirestore());
    }

    await batch.commit();

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

  // Delete product with optimistic update
  Future<void> deleteProduct(String productId) async {
    // Delete from cache immediately
    if (_cachedProducts != null) {
      _cachedProducts!.removeWhere((p) => p.id == productId);
    }

    // Delete product document
    await _firestore.collection(_productsCollection).doc(productId).delete();
  }

  // Convert image to base64 with compression
  Future<String?> imageToBase64(File imageFile) async {
    try {
      // Compress image aggressively to stay under Firestore limits
      final compressedFile = await _compressImage(imageFile);

      // Read file as bytes
      final bytes = await compressedFile.readAsBytes();

      // Check size (warn if over 500KB as base64 will be ~33% larger)
      final sizeInKB = bytes.length / 1024;
      if (sizeInKB > 500) {
        debugPrint('Warning: Image is ${sizeInKB.toStringAsFixed(0)}KB. May approach Firestore 1MB limit.');
      }

      // Convert to base64
      final base64String = base64Encode(bytes);

      // Clean up compressed file
      try {
        await compressedFile.delete();
      } catch (e) {
        debugPrint('Error deleting temp file: $e');
      }

      return base64String;
    } catch (e) {
      debugPrint('Error converting image to base64: $e');
      return null;
    }
  }

  // Compress image aggressively to stay under Firestore limits
  Future<File> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 50, // More aggressive compression for base64 storage
      minWidth: 600, // Smaller dimensions
      minHeight: 600,
    );

    return result != null ? File(result.path) : file;
  }

  // Clear cache (useful for manual refresh)
  void clearCache() {
    _cachedProducts = null;
    _lastFetchTime = null;
  }

  // Dispose stream
  void dispose() {
    _productsStream = null;
  }
}