import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../../services/store_stock_service.dart';
import '../../utils/quantity.dart';
import '../theme/app_theme.dart';

void _showError(ScaffoldMessengerState? messenger, Object e) {
  messenger?.showSnackBar(SnackBar(
    content: Text('Could not update store stock: $e'),
    backgroundColor: AppColors.stockOut,
  ));
}

/// Asks how much of [product] is in the store and saves it. Offers
/// "Move to shop" when some is already there.
Future<void> showStoreStockEditor(
    BuildContext context, Product product, double inStore) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final controller =
      TextEditingController(text: inStore > 0 ? formatQty(inStore) : '');
  final fractional = product.isSoldByWeight;

  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${product.name} in store'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (product.size.isNotEmpty)
            Text(product.size, style: const TextStyle(color: AppColors.textMuted)),
          Text('In shop: ${product.qtyLabel(product.stock)}',
              style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: qtyKeyboard(fractional),
            inputFormatters: qtyInputFormatters(fractional),
            decoration: InputDecoration(
              labelText: 'Quantity in store',
              suffixText: product.qtyUnit,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.pop(ctx, 'save'),
          ),
        ],
      ),
      actions: [
        if (inStore > 0)
          TextButton.icon(
            icon: const Icon(Icons.storefront_rounded),
            label: const Text('Move to shop'),
            onPressed: () => Navigator.pop(ctx, 'move'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'save'),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (action == 'move') {
    if (context.mounted) await showMoveToShopDialog(context, product, inStore);
    return;
  }
  if (action != 'save') return;

  final qty = parseQty(controller.text) ?? 0;
  try {
    await StoreStockService().setQty(product, qty);
    messenger?.showSnackBar(SnackBar(
      content: Text(qty <= 0
          ? '${product.name} taken off store stock'
          : '${product.name}: ${product.qtyLabel(qty)} in store'),
      duration: const Duration(seconds: 2),
    ));
  } catch (e) {
    _showError(messenger, e);
  }
}

/// Moves some of [product] from the store into the shop's stock.
Future<void> showMoveToShopDialog(
    BuildContext context, Product product, double inStore) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final controller = TextEditingController(text: formatQty(inStore));
  final fractional = product.isSoldByWeight;

  final qty = await showDialog<double>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setState) {
          void submit() {
            final q = parseQty(controller.text);
            if (q == null || q <= 0) {
              setState(() => error = 'Enter a quantity');
            } else if (q > inStore) {
              setState(() =>
                  error = 'Only ${product.qtyLabel(inStore)} in store');
            } else {
              Navigator.pop(ctx, q);
            }
          }

          return AlertDialog(
            title: const Text('Move to shop'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  'Store: ${product.qtyLabel(inStore)} • '
                  'Shop: ${product.qtyLabel(product.stock)}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: qtyKeyboard(fractional),
                  inputFormatters: qtyInputFormatters(fractional),
                  decoration: InputDecoration(
                    labelText: 'Quantity to move',
                    suffixText: product.qtyUnit,
                    errorText: error,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: submit, child: const Text('Move')),
            ],
          );
        },
      );
    },
  );
  if (qty == null) return;

  try {
    await StoreStockService().moveToShop(product, qty, inStore);
    messenger?.showSnackBar(SnackBar(
      content: Text('Moved ${product.qtyLabel(qty)} ${product.name} to shop'),
      duration: const Duration(seconds: 2),
    ));
  } catch (e) {
    _showError(messenger, e);
  }
}

/// Shows how much of [product] is in the store, live; tapping it edits
/// the store quantity or moves some to the shop.
class StoreStockButton extends StatefulWidget {
  final Product product;

  /// A compact icon button (for app bars) instead of a labelled chip.
  final bool iconOnly;

  const StoreStockButton(
      {super.key, required this.product, this.iconOnly = false});

  @override
  State<StoreStockButton> createState() => _StoreStockButtonState();
}

class _StoreStockButtonState extends State<StoreStockButton> {
  late final Stream<List<StoreStockItem>> _items = StoreStockService().watch();

  Product get product => widget.product;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoreStockItem>>(
      stream: _items,
      builder: (context, snapshot) {
        final inStore = snapshot.data
                ?.where((i) => i.productId == product.id)
                .firstOrNull
                ?.qty ??
            0;
        final onTap = snapshot.hasData
            ? () => showStoreStockEditor(context, product, inStore)
            : null;

        if (widget.iconOnly) {
          return IconButton(
            icon: Badge(
              isLabelVisible: inStore > 0,
              label: Text(formatQty(inStore)),
              backgroundColor: AppColors.green,
              child: const Icon(Icons.warehouse_outlined),
            ),
            tooltip: inStore > 0
                ? 'In store: ${product.qtyLabel(inStore)}'
                : 'Add to store stock',
            onPressed: onTap,
          );
        }

        return ActionChip(
          avatar: Icon(Icons.warehouse_outlined,
              size: 18, color: inStore > 0 ? AppColors.green : AppColors.blue),
          label: Text(inStore > 0
              ? 'In store: ${product.qtyLabel(inStore)}'
              : 'Store stock'),
          backgroundColor: inStore > 0
              ? AppColors.green.withValues(alpha: 0.1)
              : AppColors.blueTint,
          side: BorderSide(
              color: inStore > 0 ? AppColors.green : AppColors.blueLight),
          onPressed: onTap,
        );
      },
    );
  }
}
