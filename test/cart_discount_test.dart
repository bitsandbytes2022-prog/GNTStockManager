import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_manager/models/product_model.dart';
import 'package:inventory_manager/models/sale_model.dart';
import 'package:inventory_manager/utils/cart_discount.dart';

void main() {
  test('spreads a flat discount proportionally over eligible lines', () {
    // 2 × 100 + 1 × 300 eligible (500), PPR pipe 1 × 400 skipped.
    final prices = spreadCartDiscount(
      prices: [100, 300, 400],
      quantities: [2, 1, 1],
      eligible: [true, true, false],
      discount: 50,
    );
    expect(prices, [90, 270, 400]);
  });

  test('rounds rates to the paisa and caps at the eligible value', () {
    final p = spreadCartDiscount(
      prices: [85, 33],
      quantities: [3, 1],
      eligible: [true, true],
      discount: 10,
    );
    expect(p[0], closeTo(85 * (1 - 10 / 288), 0.005));
    expect(p[0] * 100, closeTo((p[0] * 100).roundToDouble(), 1e-6));

    final capped = spreadCartDiscount(
      prices: [10],
      quantities: [1],
      eligible: [true],
      discount: 999,
    );
    expect(capped, [0]);
  });

  test('no discount or nothing eligible leaves prices alone', () {
    expect(
        spreadCartDiscount(
            prices: [10, 20], quantities: [1, 1], eligible: [true, true], discount: 0),
        [10, 20]);
    expect(
        spreadCartDiscount(
            prices: [10], quantities: [1], eligible: [false], discount: 5),
        [10]);
  });

  Product product(String name, String category, {String? sub}) => Product(
        id: name,
        name: name,
        size: '20mm',
        purchasePrice: 10,
        salePrice: 20,
        stock: 5,
        imageBase64: null,
        createdAt: DateTime(2026),
        category: category,
        subcategory: sub,
      );

  test('PPR pipes are recognised, PPR fittings and other pipes are not', () {
    expect(product('PPR Pipe PN16', 'PPR').isPprPipe, isTrue);
    expect(product('Pipe', 'Sanitary', sub: 'PPR').isPprPipe, isTrue);
    expect(product('PPR Elbow', 'PPR').isPprPipe, isFalse);
    expect(product('CPVC Pipe', 'CPVC').isPprPipe, isFalse);
  });

  test('originalPrice round-trips and only counts when above the rate', () {
    final item = SaleItem(
      productId: 'p',
      productName: 'Tap',
      productSize: '1/2',
      purchasePrice: 50,
      salePrice: 90,
      quantity: 2,
      originalPrice: 100,
    );
    expect(item.isDiscounted, isTrue);
    expect(item.toMap()['originalPrice'], 100);
    expect(item.copyWith(quantity: 1).originalPrice, 100);
    expect(
        SaleItem(
                productId: 'p',
                productName: 'Tap',
                productSize: '1/2',
                purchasePrice: 50,
                salePrice: 100,
                quantity: 1)
            .toMap()
            .containsKey('originalPrice'),
        isFalse);
  });
}
