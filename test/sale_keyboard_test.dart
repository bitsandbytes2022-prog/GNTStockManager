import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_manager/models/product_model.dart';
import 'package:inventory_manager/ui/widgets/sale_keyboard.dart';

Product _p(String id) => Product(
      id: id,
      name: 'Item $id',
      size: '',
      purchasePrice: 1,
      salePrice: 2,
      stock: 10,
      imageBase64: null,
      createdAt: DateTime(2026),
    );

class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with SaleKeyboardMixin {
  final search = TextEditingController();
  final products = [_p('a'), _p('b'), _p('c')];
  final lines = ['l1', 'l2', 'l3'];
  final opened = <String>[];
  final edited = <String>[];
  int saves = 0;

  @override
  List<Product> get keyboardProducts => products;
  @override
  List<String> get keyboardCartLines => lines;
  @override
  TextEditingController get keyboardSearchController => search;
  @override
  Future<void> openProductFromKeyboard(Product product) async =>
      opened.add(product.id);
  @override
  Future<void> editCartLineFromKeyboard(String lineKey) async =>
      edited.add(lineKey);
  @override
  void removeCartLineFromKeyboard(String lineKey) =>
      setState(() => lines.remove(lineKey));

  @override
  void initState() {
    super.initState();
    initSaleKeyboard();
  }

  @override
  void dispose() {
    disposeSaleKeyboard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hi = highlightIndexFor(products.length);
    return CallbackShortcuts(
      bindings: shortcutBindings({
        ...cartLineBindings,
        ctrlOrCmd(LogicalKeyboardKey.keyS): () => saves++,
      }),
      child: FocusScope(
        child: Scaffold(
          body: Column(children: [
            CallbackShortcuts(
              bindings: searchFieldBindings,
              child: TextField(
                controller: search,
                focusNode: searchFocus,
                onEditingComplete: () {},
                onSubmitted: (_) => addHighlightedProduct(),
              ),
            ),
            Text('highlight:$hi pick:$cartPick'),
            const SizedBox(height: 20, child: Text('blank')),
          ]),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('keyboard drives search results and cart lines', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: _Harness()));
    await tester.pump();
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    // Search is focused on open, highlight on the first result.
    expect(state.searchFocus.hasFocus, isTrue);
    expect(find.text('highlight:0 pick:null'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'item');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // clamps at end
    await tester.pump();
    expect(find.text('highlight:2 pick:null'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(state.opened, ['b']);
    // Back in search with the text selected for the next item.
    expect(state.searchFocus.hasFocus, isTrue);
    expect(state.search.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4));

    // Esc clears the search.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(state.search.text, '');

    // Alt+↑ picks the last line, Alt+Enter edits it, Alt+Del removes it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(state.edited, ['l2']);
    expect(state.lines, ['l1', 'l3']);
    expect(state.cartPick, 'l3');

    // Shortcuts still work after focus leaves the search box.
    state.searchFocus.unfocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(state.saves, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    expect(state.searchFocus.hasFocus, isTrue);
  });
}
