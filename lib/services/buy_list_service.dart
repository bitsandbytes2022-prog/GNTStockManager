import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_model.dart';

/// A product marked as needing to be bought on the next purchase run.
class BuyListItem {
  final String productId;
  final String name;
  final String size;
  final String category;
  final DateTime addedAt;

  BuyListItem({
    required this.productId,
    required this.name,
    required this.size,
    required this.category,
    required this.addedAt,
  });

  factory BuyListItem.fromMap(String productId, Map<String, dynamic> map) {
    final added = map['addedAt'];
    return BuyListItem(
      productId: productId,
      name: map['name'] ?? '',
      size: map['size'] ?? '',
      category: map['category'] ?? 'Uncategorized',
      addedAt: added is Timestamp ? added.toDate() : DateTime.now(),
    );
  }
}

/// The shop's "next buy" list, shared across devices. Stored as one
/// document (`settings/buy_list`) holding a map keyed by product id, so a
/// product can only be on the list once and adding/removing is a single
/// field write.
class BuyListService {
  BuyListService._internal();
  static final BuyListService _instance = BuyListService._internal();
  factory BuyListService() => _instance;

  final DocumentReference<Map<String, dynamic>> _doc =
      FirebaseFirestore.instance.collection('settings').doc('buy_list');

  /// Every item on the list, oldest first. Each call is its own listener
  /// (Firestore shares the underlying one), so hold on to the stream rather
  /// than calling this in build.
  Stream<List<BuyListItem>> watch() => _doc.snapshots().map((snap) {
        final items = (snap.data()?['items'] as Map<String, dynamic>?) ?? {};
        return [
          for (final e in items.entries)
            BuyListItem.fromMap(e.key, Map<String, dynamic>.from(e.value)),
        ]..sort((a, b) => a.addedAt.compareTo(b.addedAt));
      });

  Future<void> add(Product product) => _doc.set({
        'items': {
          product.id: {
            'name': product.name,
            'size': product.size,
            'category': product.category,
            'addedAt': FieldValue.serverTimestamp(),
          },
        },
      }, SetOptions(merge: true));

  Future<void> remove(String productId) =>
      _doc.update({'items.$productId': FieldValue.delete()});

  /// Puts a removed item back as it was (for "Undo").
  Future<void> restore(BuyListItem item) => _doc.set({
        'items': {
          item.productId: {
            'name': item.name,
            'size': item.size,
            'category': item.category,
            'addedAt': Timestamp.fromDate(item.addedAt),
          },
        },
      }, SetOptions(merge: true));
}
