import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../../services/buy_list_service.dart';
import '../theme/app_theme.dart';

/// Adds [product] to (or takes it off) the next buy list. Shows whether
/// it's already on the list, live.
class BuyListButton extends StatefulWidget {
  final Product product;

  /// A compact icon button (for app bars) instead of a labelled chip.
  final bool iconOnly;

  const BuyListButton({super.key, required this.product, this.iconOnly = false});

  @override
  State<BuyListButton> createState() => _BuyListButtonState();
}

class _BuyListButtonState extends State<BuyListButton> {
  late final Stream<List<BuyListItem>> _items = BuyListService().watch();

  Product get product => widget.product;

  Future<void> _toggle(BuildContext context, bool onList) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (onList) {
        await BuyListService().remove(product.id);
      } else {
        await BuyListService().add(product);
      }
      messenger?.showSnackBar(SnackBar(
        content: Text(onList
            ? '${product.name} removed from buy list'
            : '${product.name} added to buy list'),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
        content: Text('Could not update buy list: $e'),
        backgroundColor: AppColors.stockOut,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BuyListItem>>(
      stream: _items,
      builder: (context, snapshot) {
        final onList =
            snapshot.data?.any((i) => i.productId == product.id) ?? false;
        final icon = onList
            ? Icons.playlist_add_check_rounded
            : Icons.playlist_add_rounded;

        if (widget.iconOnly) {
          return IconButton(
            icon: Icon(icon, color: onList ? AppColors.green : null),
            tooltip: onList ? 'On buy list (tap to remove)' : 'Add to buy list',
            onPressed: snapshot.hasData ? () => _toggle(context, onList) : null,
          );
        }

        return ActionChip(
          avatar: Icon(icon,
              size: 18, color: onList ? AppColors.green : AppColors.blue),
          label: Text(onList ? 'On buy list' : 'Add to buy list'),
          backgroundColor:
              onList ? AppColors.green.withValues(alpha: 0.1) : AppColors.blueTint,
          side: BorderSide(
              color: onList ? AppColors.green : AppColors.blueLight),
          onPressed: snapshot.hasData ? () => _toggle(context, onList) : null,
        );
      },
    );
  }
}
