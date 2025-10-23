
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/product_model.dart';
import '../models/sale_model.dart';

class DataSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _salesCollection = 'sales';
  static const String _productsCollection = 'products';

  /// Sync existing sales data to update product statistics and add missing images
  ///
  /// This function will:
  /// 1. Calculate total sales for each product from all sales history
  /// 2. Update product documents with correct totalSold, saleCount, lastSoldAt
  /// 3. Add product images to sales that are missing them
  Future<SyncResult> syncAllData({
    required Function(String) onProgress,
  }) async {
    final result = SyncResult();

    try {
      onProgress('Starting sync...');

      // Step 1: Fetch all products
      onProgress('Fetching products...');
      final productsSnapshot = await _firestore
          .collection(_productsCollection)
          .get();

      final products = productsSnapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();

      result.totalProducts = products.length;
      onProgress('Found ${products.length} products');

      // Create a map for quick product lookup
      final productMap = {for (var p in products) p.id: p};

      // Step 2: Fetch all sales
      onProgress('Fetching sales history...');
      final salesSnapshot = await _firestore
          .collection(_salesCollection)
          .get();

      final sales = salesSnapshot.docs
          .map((doc) => Sale.fromFirestore(doc))
          .toList();

      result.totalSales = sales.length;
      onProgress('Found ${sales.length} sales to process');

      // Step 3: Calculate product statistics from sales
      onProgress('Calculating product statistics...');
      final productStats = <String, ProductSalesStats>{};

      for (final sale in sales) {
        for (final item in sale.items) {
          if (!productStats.containsKey(item.productId)) {
            productStats[item.productId] = ProductSalesStats(
              productId: item.productId,
              totalSold: 0,
              saleCount: 0,
              lastSoldAt: sale.createdAt,
            );
          }

          final stats = productStats[item.productId]!;
          stats.totalSold += item.quantity;
          stats.saleCount += 1;

          // Update lastSoldAt to the most recent sale
          if (sale.createdAt.isAfter(stats.lastSoldAt)) {
            stats.lastSoldAt = sale.createdAt;
          }
        }
      }

      onProgress('Calculated stats for ${productStats.length} products');

      // Step 4: Update products with correct statistics
      onProgress('Updating product statistics...');
      int productsUpdated = 0;

      // Use batches (Firestore allows max 500 operations per batch)
      final batches = <WriteBatch>[];
      WriteBatch currentBatch = _firestore.batch();
      int operationCount = 0;
      const maxBatchSize = 500;

      for (final product in products) {
        final stats = productStats[product.id];

        if (stats != null) {
          // Product has sales, update with calculated stats
          final productRef = _firestore
              .collection(_productsCollection)
              .doc(product.id);

          currentBatch.update(productRef, {
            'totalSold': stats.totalSold,
            'saleCount': stats.saleCount,
            'lastSoldAt': Timestamp.fromDate(stats.lastSoldAt),
          });

          productsUpdated++;
        } else {
          // Product has no sales, ensure stats are zero
          final productRef = _firestore
              .collection(_productsCollection)
              .doc(product.id);

          currentBatch.update(productRef, {
            'totalSold': 0,
            'saleCount': 0,
            'lastSoldAt': null,
          });
        }

        operationCount++;

        // If batch is full, start a new one
        if (operationCount >= maxBatchSize) {
          batches.add(currentBatch);
          currentBatch = _firestore.batch();
          operationCount = 0;
        }
      }

      // Add the last batch if it has operations
      if (operationCount > 0) {
        batches.add(currentBatch);
      }

      // Commit all batches
      for (int i = 0; i < batches.length; i++) {
        onProgress('Committing product updates (batch ${i + 1}/${batches.length})...');
        await batches[i].commit();
      }

      result.productsUpdated = productsUpdated;
      onProgress('Updated ${productsUpdated} products with sales data');

      // Step 5: Update sales with missing product images
      onProgress('Checking for sales missing product images...');
      int salesNeedingUpdate = 0;
      int salesUpdated = 0;

      final saleBatches = <WriteBatch>[];
      WriteBatch currentSaleBatch = _firestore.batch();
      int saleOperationCount = 0;

      for (final sale in sales) {
        bool needsUpdate = false;
        final updatedItems = <Map<String, dynamic>>[];

        for (final item in sale.items) {
          final itemMap = item.toMap();

          // Check if image is missing
          if (item.imageBase64 == null || item.imageBase64!.isEmpty) {
            // Try to get image from product
            final product = productMap[item.productId];
            if (product != null && product.imageBase64 != null) {
              itemMap['imageBase64'] = product.imageBase64;
              needsUpdate = true;
              salesNeedingUpdate++;
            }
          }

          updatedItems.add(itemMap);
        }

        if (needsUpdate) {
          final saleRef = _firestore
              .collection(_salesCollection)
              .doc(sale.id);

          currentSaleBatch.update(saleRef, {
            'items': updatedItems,
          });

          salesUpdated++;
          saleOperationCount++;

          // If batch is full, start a new one
          if (saleOperationCount >= maxBatchSize) {
            saleBatches.add(currentSaleBatch);
            currentSaleBatch = _firestore.batch();
            saleOperationCount = 0;
          }
        }
      }

      // Add the last batch if it has operations
      if (saleOperationCount > 0) {
        saleBatches.add(currentSaleBatch);
      }

      // Commit all sale batches
      for (int i = 0; i < saleBatches.length; i++) {
        onProgress('Committing sale updates (batch ${i + 1}/${saleBatches.length})...');
        await saleBatches[i].commit();
      }

      result.salesUpdated = salesUpdated;
      onProgress('Updated ${salesUpdated} sales with product images');

      // Final results
      result.success = true;
      onProgress('✅ Sync completed successfully!');

      return result;

    } catch (e, stackTrace) {
      debugPrint('Error during sync: $e');
      debugPrint('Stack trace: $stackTrace');
      result.success = false;
      result.errorMessage = e.toString();
      onProgress('❌ Sync failed: $e');
      return result;
    }
  }

  /// Sync only product statistics (faster, doesn't update images)
  Future<SyncResult> syncProductStatisticsOnly({
    required Function(String) onProgress,
  }) async {
    final result = SyncResult();

    try {
      onProgress('Starting product statistics sync...');

      // Fetch all products
      onProgress('Fetching products...');
      final productsSnapshot = await _firestore
          .collection(_productsCollection)
          .get();

      final products = productsSnapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();

      result.totalProducts = products.length;

      // Fetch all sales
      onProgress('Fetching sales history...');
      final salesSnapshot = await _firestore
          .collection(_salesCollection)
          .get();

      final sales = salesSnapshot.docs
          .map((doc) => Sale.fromFirestore(doc))
          .toList();

      result.totalSales = sales.length;

      // Calculate statistics
      onProgress('Calculating statistics...');
      final productStats = <String, ProductSalesStats>{};

      for (final sale in sales) {
        for (final item in sale.items) {
          if (!productStats.containsKey(item.productId)) {
            productStats[item.productId] = ProductSalesStats(
              productId: item.productId,
              totalSold: 0,
              saleCount: 0,
              lastSoldAt: sale.createdAt,
            );
          }

          final stats = productStats[item.productId]!;
          stats.totalSold += item.quantity;
          stats.saleCount += 1;

          if (sale.createdAt.isAfter(stats.lastSoldAt)) {
            stats.lastSoldAt = sale.createdAt;
          }
        }
      }

      // Update products
      onProgress('Updating products...');
      final batches = <WriteBatch>[];
      WriteBatch currentBatch = _firestore.batch();
      int operationCount = 0;
      const maxBatchSize = 500;
      int productsUpdated = 0;

      for (final product in products) {
        final stats = productStats[product.id];
        final productRef = _firestore
            .collection(_productsCollection)
            .doc(product.id);

        if (stats != null) {
          currentBatch.update(productRef, {
            'totalSold': stats.totalSold,
            'saleCount': stats.saleCount,
            'lastSoldAt': Timestamp.fromDate(stats.lastSoldAt),
          });
          productsUpdated++;
        } else {
          currentBatch.update(productRef, {
            'totalSold': 0,
            'saleCount': 0,
            'lastSoldAt': null,
          });
        }

        operationCount++;

        if (operationCount >= maxBatchSize) {
          batches.add(currentBatch);
          currentBatch = _firestore.batch();
          operationCount = 0;
        }
      }

      if (operationCount > 0) {
        batches.add(currentBatch);
      }

      for (int i = 0; i < batches.length; i++) {
        onProgress('Committing updates (${i + 1}/${batches.length})...');
        await batches[i].commit();
      }

      result.productsUpdated = productsUpdated;
      result.success = true;
      onProgress('✅ Statistics sync completed!');

      return result;

    } catch (e) {
      result.success = false;
      result.errorMessage = e.toString();
      onProgress('❌ Sync failed: $e');
      return result;
    }
  }

  /// Sync only sale images (faster, doesn't update statistics)
  Future<SyncResult> syncSaleImagesOnly({
    required Function(String) onProgress,
  }) async {
    final result = SyncResult();

    try {
      onProgress('Starting sale images sync...');

      // Fetch all products
      onProgress('Fetching products...');
      final productsSnapshot = await _firestore
          .collection(_productsCollection)
          .get();

      final products = productsSnapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();

      result.totalProducts = products.length;
      final productMap = {for (var p in products) p.id: p};

      // Fetch all sales
      onProgress('Fetching sales...');
      final salesSnapshot = await _firestore
          .collection(_salesCollection)
          .get();

      final sales = salesSnapshot.docs
          .map((doc) => Sale.fromFirestore(doc))
          .toList();

      result.totalSales = sales.length;

      // Update sales
      onProgress('Processing sales...');
      final batches = <WriteBatch>[];
      WriteBatch currentBatch = _firestore.batch();
      int operationCount = 0;
      const maxBatchSize = 500;
      int salesUpdated = 0;

      for (final sale in sales) {
        bool needsUpdate = false;
        final updatedItems = <Map<String, dynamic>>[];

        for (final item in sale.items) {
          final itemMap = item.toMap();

          if (item.imageBase64 == null || item.imageBase64!.isEmpty) {
            final product = productMap[item.productId];
            if (product != null && product.imageBase64 != null) {
              itemMap['imageBase64'] = product.imageBase64;
              needsUpdate = true;
            }
          }

          updatedItems.add(itemMap);
        }

        if (needsUpdate) {
          final saleRef = _firestore
              .collection(_salesCollection)
              .doc(sale.id);

          currentBatch.update(saleRef, {
            'items': updatedItems,
          });

          salesUpdated++;
          operationCount++;

          if (operationCount >= maxBatchSize) {
            batches.add(currentBatch);
            currentBatch = _firestore.batch();
            operationCount = 0;
          }
        }
      }

      if (operationCount > 0) {
        batches.add(currentBatch);
      }

      for (int i = 0; i < batches.length; i++) {
        onProgress('Committing updates (${i + 1}/${batches.length})...');
        await batches[i].commit();
      }

      result.salesUpdated = salesUpdated;
      result.success = true;
      onProgress('✅ Image sync completed!');

      return result;

    } catch (e) {
      result.success = false;
      result.errorMessage = e.toString();
      onProgress('❌ Sync failed: $e');
      return result;
    }
  }
}

/// Helper class to track product sales statistics
class ProductSalesStats {
  final String productId;
  int totalSold;
  int saleCount;
  DateTime lastSoldAt;

  ProductSalesStats({
    required this.productId,
    required this.totalSold,
    required this.saleCount,
    required this.lastSoldAt,
  });
}

/// Result of sync operation
class SyncResult {
  bool success = false;
  int totalProducts = 0;
  int totalSales = 0;
  int productsUpdated = 0;
  int salesUpdated = 0;
  String? errorMessage;

  String getSummary() {
    if (!success) {
      return 'Sync failed: ${errorMessage ?? "Unknown error"}';
    }

    return '''
✅ Sync Completed Successfully!

📦 Products: $totalProducts total
   └─ Updated: $productsUpdated with sales data

🛒 Sales: $totalSales total
   └─ Updated: $salesUpdated with images

The database is now in sync!
    ''';
  }
}