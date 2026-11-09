import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product_model.dart';
import '../../services/store_stock_service.dart';
import '../../utils/quantity.dart';
import '../theme/app_theme.dart';
import '../widgets/store_stock_button.dart';

/// Everything kept in the store (godown), grouped by category, with the
/// shop's stock beside it so it's clear what to bring over.
class StoreStockScreen extends StatefulWidget {
  const StoreStockScreen({super.key});

  @override
  State<StoreStockScreen> createState() => _StoreStockScreenState();
}

class _StoreStockScreenState extends State<StoreStockScreen> {
  late final Stream<List<StoreStockItem>> _items = StoreStockService().watch();

  // Its own listener rather than FirebaseService's shared stream, which
  // doesn't replay the latest products to a late subscriber.
  late final Stream<List<Product>> _products = FirebaseFirestore.instance
      .collection('products')
      .snapshots()
      .map((s) => [for (final d in s.docs) Product.fromMap(d.data(), d.id)]);

  String _search = '';

  bool _matches(String name, String size) {
    final q = _search.trim().toLowerCase();
    return q.isEmpty || '$name $size'.toLowerCase().contains(q);
  }

  Map<String, List<StoreStockItem>> _byCategory(List<StoreStockItem> items) {
    final groups = <String, List<StoreStockItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    return Map.fromEntries(
        groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  Future<void> _copy(List<StoreStockItem> items) async {
    final buffer = StringBuffer('Store stock\n');
    for (final group in _byCategory(items).entries) {
      buffer.writeln('\n${group.key}');
      for (final item in group.value) {
        buffer.writeln('- ${item.name}'
            '${item.size.isNotEmpty ? ' (${item.size})' : ''}: '
            '${formatQty(item.qty)}');
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Store stock copied')),
    );
  }

  Future<void> _addItem(List<Product> products, Set<String> inStore) async {
    final product = await showDialog<Product>(
      context: context,
      builder: (_) => _ProductPicker(products: products, inStore: inStore),
    );
    if (product == null || !mounted) return;
    await showStoreStockEditor(context, product, 0);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: _products,
      builder: (context, productSnap) {
        final productList = productSnap.data ?? const <Product>[];
        final products = {for (final p in productList) p.id: p};
        return StreamBuilder<List<StoreStockItem>>(
          stream: _items,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <StoreStockItem>[];
            final shown =
                items.where((i) => _matches(i.name, i.size)).toList();
            final value = items.fold<double>(
                0,
                (total, i) =>
                    total + i.qty * (products[i.productId]?.purchasePrice ?? 0));
            return Scaffold(
              backgroundColor: AppColors.page,
              appBar: AppBar(
                title: Text(items.isEmpty
                    ? 'Store Stock'
                    : 'Store Stock (${items.length})'),
                actions: [
                  if (items.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: 'Copy list',
                      onPressed: () => _copy(items),
                    ),
                ],
              ),
              floatingActionButton: productSnap.hasData
                  ? FloatingActionButton.extended(
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add item'),
                      onPressed: () => _addItem(
                          productList, {for (final i in items) i.productId}),
                    )
                  : null,
              body: !snapshot.hasData
                  ? (snapshot.hasError
                      ? Center(child: Text('Error: ${snapshot.error}'))
                      : const Center(child: CircularProgressIndicator()))
                  : items.isEmpty
                      ? const _EmptyState()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          children: [
                            TextField(
                              decoration: const InputDecoration(
                                hintText: 'Search store stock',
                                prefixIcon: Icon(Icons.search_rounded),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() => _search = v),
                            ),
                            if (value > 0)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                                child: Text(
                                  'Worth ₹${value.toStringAsFixed(0)} at cost',
                                  style: const TextStyle(
                                      color: AppColors.textMuted),
                                ),
                              ),
                            for (final group in _byCategory(shown).entries) ...[
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
                                _StoreStockTile(
                                  item: item,
                                  product: products[item.productId],
                                ),
                            ],
                          ],
                        ),
            );
          },
        );
      },
    );
  }
}

class _StoreStockTile extends StatelessWidget {
  final StoreStockItem item;

  /// The live product, for its shop stock; null if it was deleted.
  final Product? product;

  const _StoreStockTile({required this.item, required this.product});

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: p == null
            ? null
            : () => showStoreStockEditor(context, p, item.qty),
        title: Text(item.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          if (item.size.isNotEmpty) item.size,
          'Store: ${p?.qtyLabel(item.qty) ?? formatQty(item.qty)}',
          p == null ? 'Product deleted' : 'Shop: ${p.qtyLabel(p.stock)}',
        ].join(' • ')),
        trailing: p == null
            ? IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove',
                onPressed: () => StoreStockService().remove(item.productId),
              )
            : TextButton.icon(
                icon: const Icon(Icons.storefront_rounded, size: 18),
                label: const Text('To shop'),
                onPressed: () => showMoveToShopDialog(context, p, item.qty),
              ),
      ),
    );
  }
}

/// Picks a product to put in store stock.
class _ProductPicker extends StatefulWidget {
  final List<Product> products;
  final Set<String> inStore;

  const _ProductPicker({required this.products, required this.inStore});

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final matches = widget.products
        .where((p) =>
            q.isEmpty ||
            '${p.name} ${p.size} ${p.category}'.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return AlertDialog(
      title: const Text('Add to store stock'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search products',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, i) {
                  final p = matches[i];
                  return ListTile(
                    dense: true,
                    title: Text(p.name),
                    subtitle: Text([
                      if (p.size.isNotEmpty) p.size,
                      p.category,
                    ].join(' • ')),
                    trailing: widget.inStore.contains(p.id)
                        ? const Icon(Icons.warehouse_rounded,
                            size: 18, color: AppColors.green)
                        : null,
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
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
            Icon(Icons.warehouse_outlined, size: 56, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text(
              'Nothing in store yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              'Tap "Add item", or open a product and tap the store icon, to '
              'note what you keep in the store.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
