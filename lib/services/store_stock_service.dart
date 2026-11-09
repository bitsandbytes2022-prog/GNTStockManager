import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_model.dart';
import '../utils/quantity.dart';

/// Stock of a product kept in the store (godown), apart from the shop's
/// own stock on the product.
class StoreStockItem {
  final String productId;
  final String name;
  final String size;
  final String category;
  final double qty;
  final DateTime updatedAt;

  StoreStockItem({
    required this.productId,
    required this.name,
    required this.size,
    required this.category,
    required this.qty,
    required this.updatedAt,
  });

  factory StoreStockItem.fromMap(String productId, Map<String, dynamic> map) {
    final updated = map['updatedAt'];
    return StoreStockItem(
      productId: productId,
      name: map['name'] ?? '',
      size: map['size'] ?? '',
      category: map['category'] ?? 'Uncategorized',
      qty: readQty(map['qty']),
      updatedAt: updated is Timestamp ? updated.toDate() : DateTime.now(),
    );
  }
}

/// What's kept in the store, shared across devices. Like the buy list it's
/// one document (`settings/store_stock`) holding a map keyed by product id,
/// so product saves (which write the whole product) never touch it and
/// sales keep taking stock from the shop only.
class StoreStockService {
  StoreStockService._internal();
  static final StoreStockService _instance = StoreStockService._internal();
  factory StoreStockService() => _instance;

  final DocumentReference<Map<String, dynamic>> _doc =
      FirebaseFirestore.instance.collection('settings').doc('store_stock');

  /// Every item in the store, by name. Each call is its own listener
  /// (Firestore shares the underlying one), so hold on to the stream rather
  /// than calling this in build.
  Stream<List<StoreStockItem>> watch() => _doc.snapshots().map((snap) {
        final items = (snap.data()?['items'] as Map<String, dynamic>?) ?? {};
        return [
          for (final e in items.entries)
            StoreStockItem.fromMap(e.key, Map<String, dynamic>.from(e.value)),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });

  Map<String, dynamic> _entry(Product product, Object qty) => {
        'name': product.name,
        'size': product.size,
        'category': product.category,
        'qty': qty,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Sets how much of [product] is in the store; zero takes it off.
  Future<void> setQty(Product product, double qty) => qty <= 0
      ? remove(product.id)
      : _doc.set({
          'items': {product.id: _entry(product, storeQty(qty))},
        }, SetOptions(merge: true));

  Future<void> remove(String productId) =>
      _doc.update({'items.$productId': FieldValue.delete()});

  /// Brings [qty] of [product] from the store into the shop: the store
  /// goes down and the product's stock goes up, together. Moving all of it
  /// takes the item off the store list.
  Future<void> moveToShop(Product product, double qty, double inStore) {
    final batch = FirebaseFirestore.instance.batch();
    final left = roundQty(inStore - qty);
    batch.update(_doc, {
      'items.${product.id}': left <= 0
          ? FieldValue.delete()
          : _entry(product, storeQty(left)),
    });
    batch.update(
      FirebaseFirestore.instance.collection('products').doc(product.id),
      {'stock': FieldValue.increment(storeQty(qty))},
    );
    return batch.commit();
  }
}
