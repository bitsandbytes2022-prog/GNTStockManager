import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_manager/models/product_model.dart';
import 'package:inventory_manager/models/sale_model.dart';
import 'package:inventory_manager/utils/quantity.dart';

void main() {
  Product product(String size) => Product(
        id: 'p',
        name: 'Nails',
        size: size,
        purchasePrice: 80,
        salePrice: 100,
        stock: 10,
        imageBase64: null,
        createdAt: DateTime(2026),
      );

  test('formatQty hides .0 and float noise', () {
    expect(formatQty(5.0), '5');
    expect(formatQty(4.6), '4.6');
    expect(formatQty(0.25), '0.25');
    expect(formatQty(4.6 - 1.2), '3.4');
  });

  test('storeQty keeps whole values as ints', () {
    expect(storeQty(5.0), isA<int>());
    expect(storeQty(4.6), 4.6);
    expect(storeQty(-1.0), -1);
  });

  test('parseQty accepts dot or comma decimals', () {
    expect(parseQty('4.6'), 4.6);
    expect(parseQty('4,6'), 4.6);
    expect(parseQty(''), isNull);
    expect(parseQty('abc'), isNull);
  });

  test('KG sizes are sold by weight, messy spellings included', () {
    for (final s in ['1 KG', 'KG', '1kg', '2 Kgs', '1 kilo']) {
      expect(product(s).isSoldByWeight, isTrue, reason: s);
    }
    for (final s in ['1 Inch', '20 MM', '5 Liter', '']) {
      expect(product(s).isSoldByWeight, isFalse, reason: s);
    }
  });

  test('loose KG items show kg; packs like "5 KG" do not', () {
    expect(product('1 KG').qtyLabel(4.6), '4.6 kg');
    expect(product('KG').qtyLabel(2), '2 kg');
    expect(product('5 KG').qtyLabel(2), '2');
    expect(product('1 Inch').qtyLabel(3), '3');
    expect(product('1 Inch').qtyLabel(12, perFoot: true), '12 ft');
  });

  test('a fractional sale line round-trips through Firestore maps', () {
    final item = SaleItem(
      productId: 'p',
      productName: 'Nails',
      productSize: '1 KG',
      purchasePrice: 80,
      salePrice: 100,
      quantity: 4.6,
      stockUnits: 4.6,
    );
    expect(item.total, closeTo(460, 1e-9));
    final back = SaleItem.fromMap(item.toMap());
    expect(back.quantity, 4.6);
    expect(back.effectiveStockUnits, 4.6);
    expect(back.qtyLabel, '4.6 kg');

    // Older records stored whole quantities as ints.
    final legacy = SaleItem.fromMap({'quantity': 3, 'stockUnits': 3});
    expect(legacy.quantity, 3.0);
    expect(SaleItem.fromMap(legacy.toMap()).toMap()['quantity'], isA<int>());
  });
}
