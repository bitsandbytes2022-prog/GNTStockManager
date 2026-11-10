import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_manager/models/product_model.dart';
import 'package:inventory_manager/models/sale_model.dart';
import 'package:inventory_manager/utils/tint_cost.dart';

Product _product(String id, String name, double buy, double sell) => Product(
      id: id,
      name: name,
      size: '1',
      purchasePrice: buy,
      salePrice: sell,
      stock: 100,
      imageBase64: null,
      createdAt: DateTime(2026),
    );

void main() {
  final products = [
    _product('b', 'Suraksha Sheen', 3150, 3800),
    _product('t', 'Tint', 45.5, 100),
  ];

  test('tint cost is units at the Tint purchase price, whatever was charged', () {
    expect(tintCostFor(1600, products, units: 16), closeTo(728, 1e-9));
    // A cheaper tint charge doesn't make the tint itself cost less.
    expect(tintCostFor(800, products, units: 16), closeTo(728, 1e-9));
  });

  test('lines without units fall back to the cost ratio', () {
    expect(tintCostFor(100, products), closeTo(45.5, 1e-9));
  });

  test('no Tint product means no tint cost', () {
    expect(tintCostFor(100, [products.first], units: 4), 0);
  });

  test('a tinted line takes its units from the Tint product, per bucket', () {
    final item = SaleItem(
      productId: 'b',
      productName: 'Suraksha Sheen (8203)',
      productSize: '20 Liter',
      purchasePrice: 3150 + 728,
      salePrice: 3800 + 1600,
      quantity: 2,
      tintPrice: 1600,
      tintCost: 728,
      tintUnits: 16,
      tintProductId: 't',
    );
    expect(item.tintStockUnits, 32);
    final back = SaleItem.fromMap(item.toMap());
    expect(back.tintUnits, 16);
    expect(back.tintProductId, 't');
    expect(back.tintStockUnits, 32);
    expect(back.copyWith(quantity: 1).tintStockUnits, 16);
  });
}
