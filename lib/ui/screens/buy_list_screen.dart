import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product_model.dart';
import '../../services/buy_list_service.dart';
import '../theme/app_theme.dart';
import 'add_product_screen.dart';
import 'add_product_web_screen.dart';

/// Products marked to restock on the next purchase run, grouped by
/// category, with each one's current stock. Ticking an item off removes it.
class BuyListScreen extends StatefulWidget {
  const BuyListScreen({super.key});

  @override
  State<BuyListScreen> createState() => _BuyListScreenState();
}

class _BuyListScreenState extends State<BuyListScreen> {
  final _service = BuyListService();
  late final Stream<List<BuyListItem>> _items = _service.watch();

  // Its own listener rather than FirebaseService's shared stream, which
  // doesn't replay the latest products to a late subscriber.
  late final Stream<List<Product>> _products = FirebaseFirestore.instance
      .collection('products')
      .snapshots()
      .map((s) => [for (final d in s.docs) Product.fromMap(d.data(), d.id)]);

  Map<String, List<BuyListItem>> _byCategory(List<BuyListItem> items) {
    final groups = <String, List<BuyListItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    return groups;
  }

  Future<void> _copy(List<BuyListItem> items) async {
    final buffer = StringBuffer('Buy list\n');
    for (final group in _byCategory(items).entries) {
      buffer.writeln('\n${group.key}');
      for (final item in group.value) {
        buffer.writeln(
            '- ${item.name}${item.size.isNotEmpty ? ' (${item.size})' : ''}');
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Buy list copied — paste it in WhatsApp')),
    );
  }

  Future<void> _markBought(BuyListItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    await _service.remove(item.productId);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('${item.name} ticked off'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _service.restore(item),
      ),
    ));
  }

  void _openProduct(Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => kIsWeb
            ? AddProductWebScreen(product: product)
            : AddProductScreen(product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BuyListItem>>(
      stream: _items,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <BuyListItem>[];
        return Scaffold(
          backgroundColor: AppColors.page,
          appBar: AppBar(
            title: Text(items.isEmpty ? 'Buy List' : 'Buy List (${items.length})'),
            actions: [
              if (items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: 'Copy list',
                  onPressed: () => _copy(items),
                ),
            ],
          ),
          body: !snapshot.hasData
              ? (snapshot.hasError
                  ? Center(child: Text('Error: ${snapshot.error}'))
                  : const Center(child: CircularProgressIndicator()))
              : items.isEmpty
                  ? const _EmptyState()
                  : StreamBuilder<List<Product>>(
                      stream: _products,
                      builder: (context, productSnap) {
                        final products = {
                          for (final p in productSnap.data ?? const <Product>[])
                            p.id: p,
                        };
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            for (final group in _byCategory(items).entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                                child: Text(
                                  group.key.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                              for (final item in group.value)
                                _BuyListTile(
                                  item: item,
                                  product: products[item.productId],
                                  onBought: () => _markBought(item),
                                  onOpen: products[item.productId] == null
                                      ? null
                                      : () => _openProduct(products[item.productId]!),
                                ),
                            ],
                          ],
                        );
                      },
                    ),
        );
      },
    );
  }
}

class _BuyListTile extends StatelessWidget {
  final BuyListItem item;

  /// The live product, for its current stock; null if it was deleted.
  final Product? product;
  final VoidCallback onBought;
  final VoidCallback? onOpen;

  const _BuyListTile({
    required this.item,
    required this.product,
    required this.onBought,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = product;
    final stockColor = p == null
        ? AppColors.textMuted
        : p.stock <= 0
            ? AppColors.stockOut
            : p.isLowStock
                ? AppColors.stockLow
                : AppColors.stockOk;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onOpen,
        leading: IconButton(
          icon: const Icon(Icons.check_circle_outline_rounded),
          color: AppColors.green,
          tooltip: 'Bought — tick off',
          onPressed: onBought,
        ),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (item.size.isNotEmpty) item.size,
          p == null
              ? 'Product deleted'
              : 'In stock: ${p.qtyLabel(p.stock)}',
        ].join(' • ')),
        trailing: p == null
            ? null
            : Icon(Icons.circle, size: 10, color: stockColor),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add_check_rounded,
                size: 56, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text(
              'Nothing to buy',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Open a product and tap "Add to buy list" to note it for '
              'your next purchase.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
