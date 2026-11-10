import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product_model.dart';
import '../theme/app_theme.dart';

/// [key] with Ctrl, plus Cmd on a Mac keyboard.
List<ShortcutActivator> ctrlOrCmd(LogicalKeyboardKey key) => [
  SingleActivator(key, control: true),
  SingleActivator(key, meta: true),
];

/// Builds a [CallbackShortcuts] binding map where several activators run
/// the same callback.
Map<ShortcutActivator, VoidCallback> shortcutBindings(
  Map<List<ShortcutActivator>, VoidCallback> groups,
) => {
  for (final g in groups.entries)
    for (final activator in g.key) activator: g.value,
};

/// One row of the shortcuts help: the keys and what they do.
typedef ShortcutHelp = (String keys, String action);

Future<void> showSaleShortcutsHelp(
  BuildContext context,
  List<ShortcutHelp> rows,
) {
  return showDialog<void>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.keyboard_rounded, color: AppColors.blue),
              SizedBox(width: 8),
              Text('Keyboard shortcuts'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (keys, action) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 150,
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final k in keys.split(' / ')) _KeyCap(k),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(action),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ],
        ),
  );
}

class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

/// A thick outline marking the item the keyboard is on.
Widget keyboardHighlight({
  Key? key,
  required bool on,
  required Widget child,
  double radius = 14,
}) {
  return Container(
    key: key,
    foregroundDecoration:
        on
            ? BoxDecoration(
              border: Border.all(color: AppColors.blue, width: 3),
              borderRadius: BorderRadius.circular(radius),
            )
            : null,
    child: child,
  );
}

/// Keyboard control shared by Create Sale and Edit Sale: the search box
/// gets focus on wide screens, ↑/↓ walk the results and Enter adds the
/// highlighted one, then focus comes back to search for the next item.
/// Alt+↑/↓ pick a cart line to edit or remove.
mixin SaleKeyboardMixin<T extends StatefulWidget> on State<T> {
  final FocusNode searchFocus = FocusNode(debugLabel: 'Sale product search');
  final GlobalKey highlightKey = GlobalKey(debugLabel: 'Keyboard product');
  final GlobalKey cartPickKey = GlobalKey(debugLabel: 'Keyboard cart line');

  int _highlight = 0;

  /// The cart line Alt+↑/↓ moved to; null means the last line.
  String? cartPick;

  /// Products in the order they're shown.
  List<Product> get keyboardProducts;

  /// Cart line keys in the order they're shown.
  List<String> get keyboardCartLines;

  TextEditingController get keyboardSearchController;

  Future<void> openProductFromKeyboard(Product product);
  Future<void> editCartLineFromKeyboard(String lineKey);
  void removeCartLineFromKeyboard(String lineKey);

  /// Wide layouts are used with a keyboard; phones aren't, so they don't
  /// get search autofocus (it would pop the on-screen keyboard) or the
  /// highlight.
  bool get keyboardFirst => MediaQuery.sizeOf(context).width >= 768;

  /// Which of [count] shown products to draw the highlight on, or null
  /// when there's no highlight (search not focused, or a phone).
  int? highlightIndexFor(int count) =>
      keyboardFirst && searchFocus.hasFocus && count > 0
          ? _highlight.clamp(0, count - 1)
          : null;

  bool isCartPicked(String lineKey) => cartPick == lineKey;

  void initSaleKeyboard() {
    searchFocus.addListener(_onSearchFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && keyboardFirst) focusSearch();
    });
  }

  void disposeSaleKeyboard() {
    searchFocus.removeListener(_onSearchFocusChange);
    searchFocus.dispose();
  }

  void _onSearchFocusChange() {
    if (mounted) setState(() {});
  }

  /// Call when the results change (new search text), so the highlight
  /// starts on the best match again.
  void resetHighlight() => _highlight = 0;

  /// Puts the cursor in search with its text selected, so typing the next
  /// product replaces the last search.
  void focusSearch() {
    searchFocus.requestFocus();
    final c = keyboardSearchController;
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }

  void _scrollTo(GlobalKey key, bool forward) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 120),
        alignmentPolicy:
            forward
                ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
                : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  void moveHighlight(int delta) {
    final count = keyboardProducts.length;
    if (count == 0) return;
    setState(
      () =>
          _highlight = (_highlight.clamp(0, count - 1) + delta).clamp(
            0,
            count - 1,
          ),
    );
    _scrollTo(highlightKey, delta > 0);
  }

  Product? get highlightedProduct {
    final products = keyboardProducts;
    if (products.isEmpty) return null;
    return products[_highlight.clamp(0, products.length - 1)];
  }

  /// Enter in search: open the highlighted product's add dialog, then come
  /// back to search for the next one.
  Future<void> addHighlightedProduct() async {
    final product = highlightedProduct;
    if (product == null) return;
    await openProductFromKeyboard(product);
    if (mounted) focusSearch();
  }

  /// The picked cart line, or the last one when none is picked.
  String? get _pickedOrLast {
    final lines = keyboardCartLines;
    if (lines.isEmpty) return null;
    return lines.contains(cartPick) ? cartPick : lines.last;
  }

  void moveCartPick(int delta) {
    final lines = keyboardCartLines;
    if (lines.isEmpty) return;
    final current = lines.indexOf(cartPick ?? '');
    final next =
        current < 0
            ? (delta < 0 ? lines.length - 1 : 0)
            : (current + delta).clamp(0, lines.length - 1);
    setState(() => cartPick = lines[next]);
    _scrollTo(cartPickKey, delta > 0);
  }

  Future<void> editPickedCartLine() async {
    final key = _pickedOrLast;
    if (key == null) return;
    await editCartLineFromKeyboard(key);
    if (mounted) focusSearch();
  }

  void removePickedCartLine() {
    final lines = keyboardCartLines;
    final key = _pickedOrLast;
    if (key == null) return;
    final i = lines.indexOf(key);
    removeCartLineFromKeyboard(key);
    final left = [...lines]..remove(key);
    setState(
      () => cartPick = left.isEmpty ? null : left[i.clamp(0, left.length - 1)],
    );
  }

  /// Keys handled inside the search box.
  Map<ShortcutActivator, VoidCallback> get searchFieldBindings => {
    const SingleActivator(LogicalKeyboardKey.arrowDown): () => moveHighlight(1),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () => moveHighlight(-1),
    const SingleActivator(LogicalKeyboardKey.pageDown): () => moveHighlight(5),
    const SingleActivator(LogicalKeyboardKey.pageUp): () => moveHighlight(-5),
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (keyboardSearchController.text.isNotEmpty) {
        keyboardSearchController.clear();
      }
    },
  };

  /// Cart-line keys, shared by both sale screens.
  Map<List<ShortcutActivator>, VoidCallback> get cartLineBindings => {
    [const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true)]:
        () => moveCartPick(-1),
    [const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true)]:
        () => moveCartPick(1),
    [const SingleActivator(LogicalKeyboardKey.enter, alt: true)]:
        editPickedCartLine,
    [
      const SingleActivator(LogicalKeyboardKey.delete, alt: true),
      const SingleActivator(LogicalKeyboardKey.backspace, alt: true),
    ]: removePickedCartLine,
    [
      const SingleActivator(LogicalKeyboardKey.f2),
      ...ctrlOrCmd(LogicalKeyboardKey.keyF),
    ]: focusSearch,
  };

  /// Help rows for the keys this mixin handles.
  static const List<ShortcutHelp> commonHelp = [
    ('F2 / Ctrl+F', 'Go to product search'),
    ('↑ / ↓', 'Move through search results'),
    ('Enter', 'Add the highlighted product'),
    ('Esc', 'Clear the search'),
    ('Tab', 'Next field in the add dialog (qty → price → …)'),
    ('↑ / ↓', 'In quantity: one more / one less'),
    ('Enter', 'In the add dialog: add to cart'),
    ('Esc', 'In the add dialog: cancel'),
    ('Alt+↑ / Alt+↓', 'Pick a cart line'),
    ('Alt+Enter', 'Edit the picked (or last) cart line'),
    ('Alt+Del', 'Remove the picked (or last) cart line'),
  ];
}
