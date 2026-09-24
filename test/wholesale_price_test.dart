import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_manager/models/product_model.dart';
import 'package:inventory_manager/utils/product_field_parsing.dart';

void main() {
  Product product({
    double purchase = 100,
    double? wholesaleMargin,
    double? wholesalePrice,
  }) =>
      Product(
        id: 'p1',
        name: 'Elbow',
        size: '1 inch',
        purchasePrice: purchase,
        salePrice: 130,
        stock: 10,
        imageBase64: null,
        createdAt: DateTime(2026),
        wholesaleMargin: wholesaleMargin,
        wholesalePrice: wholesalePrice,
      );

  group('effectiveWholesalePrice', () {
    test('defaults to purchase + 5% for products saved before wholesale', () {
      expect(product().effectiveWholesalePrice, closeTo(105, 0.001));
    });

    test('uses the saved margin when no price is saved', () {
      expect(product(wholesaleMargin: 8).effectiveWholesalePrice,
          closeTo(108, 0.001));
    });

    test('a saved price wins over the margin', () {
      expect(
          product(wholesaleMargin: 5, wholesalePrice: 111)
              .effectiveWholesalePrice,
          111);
    });
  });

  test('toMap/fromMap round-trips the wholesale fields', () {
    final p = product(wholesaleMargin: 6, wholesalePrice: 106);
    final back = Product.fromMap(p.toMap(), p.id);
    expect(back.wholesaleMargin, 6);
    expect(back.wholesalePrice, 106);
  });

  test('fromMap leaves wholesale fields null on old documents', () {
    final map = product().toMap()
      ..remove('wholesaleMargin')
      ..remove('wholesalePrice');
    final back = Product.fromMap(map, 'p1');
    expect(back.wholesalePrice, isNull);
    expect(back.effectiveWholesalePrice, closeTo(105, 0.001));
  });

  group('mergeProductFields', () {
    test('editing the wholesale price back-calculates its margin', () {
      final merged =
          mergeProductFields(product(), {'wholesalePrice': 110.0});
      expect(merged.wholesalePrice, 110);
      expect(merged.wholesaleMargin, closeTo(10, 0.001));
    });

    test('a new purchase price re-bases the margin of a saved price', () {
      final merged = mergeProductFields(
          product(wholesaleMargin: 5, wholesalePrice: 105),
          {'purchasePrice': 100.0 * 105 / 110});
      expect(merged.wholesalePrice, 105);
      expect(merged.wholesaleMargin, closeTo(10, 0.001));
    });

    test('untouched wholesale fields carry over', () {
      final merged = mergeProductFields(
          product(wholesaleMargin: 7, wholesalePrice: 107), {'stock': 3});
      expect(merged.wholesaleMargin, 7);
      expect(merged.wholesalePrice, 107);
    });
  });
}
