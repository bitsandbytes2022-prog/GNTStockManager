import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../../services/firebase_service.dart';

/// Searchable list of existing products. Returns the chosen product, or null
/// if dismissed. Used by Add Product's "Copy from existing" to clone a
/// product's details into a new variant.
Future<Product?> showProductPickerDialog(
  BuildContext context, {
  String title = 'Copy from existing product',
}) {
  return showDialog<Product>(
    context: context,
    builder: (_) => _ProductPickerDialog(title: title),
  );
}

class _ProductPickerDialog extends StatefulWidget {
  final String title;

  const _ProductPickerDialog({required this.title});

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  late final Future<List<Product>> _productsFuture =
      FirebaseService().getCachedProducts();
  String _query = '';

  List<Product> _filter(List<Product> products) {
    final words = _query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return products;
    return products.where((p) {
      final haystack = '${p.name} ${p.size} ${p.category} ${p.subcategory ?? ''}'
          .toLowerCase();
      return words.every(haystack.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search by name, size or category',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Product>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                        child: Text('Error loading products: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final products = _filter(snapshot.data!);
                  if (products.isEmpty) {
                    return const Center(child: Text('No matching products'));
                  }
                  return ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = products[i];
                      final details = [
                        if (p.size.isNotEmpty) p.size,
                        p.category,
                        if (p.subcategory?.isNotEmpty ?? false) p.subcategory!,
                      ].join(' · ');
                      return ListTile(
                        dense: true,
                        title: Text(p.name),
                        subtitle: Text(details),
                        trailing: Text(
                          p.displaySalePrice,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
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
