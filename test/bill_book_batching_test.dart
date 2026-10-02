import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_manager/models/sale_model.dart';
import 'package:inventory_manager/utils/bill_book_batching.dart';

void main() {
  SaleItem item(String name, {int qty = 1, double price = 10}) => SaleItem(
        productId: 'p_$name',
        productName: name,
        productSize: '1/2"',
        purchasePrice: price * 0.7,
        salePrice: price,
        quantity: qty,
      );

  Sale sale(int no, int lines,
      {String prefix = 'x',
      int day = 1,
      String? buyer,
      PaymentMethod pay = PaymentMethod.cash}) {
    final items = [for (var i = 0; i < lines; i++) item('$prefix$no-$i')];
    return Sale(
      id: 's$no',
      invoiceNumber: no,
      items: items,
      totalAmount: items.fold(0, (s, i) => s + i.total),
      createdAt: DateTime(2026, 9, day),
      buyerName: buyer,
      paymentMethod: pay,
    );
  }

  double total(Iterable<dynamic> xs) =>
      xs.fold<double>(0, (s, x) => s + (x.totalAmount as double));

  test('packs 36 small sales into the minimum number of bills', () {
    // 36 sales, line counts cycling 1..10 → 192 lines → at least 13 bills.
    final sales = [
      for (var i = 0; i < 36; i++) sale(i + 1, i % 10 + 1, day: i % 28 + 1)
    ];
    final bills = combineSalesIntoBills(sales);
    final lines = sales.fold<int>(0, (s, x) => s + x.items.length);

    expect(bills.every((b) => b.items.length <= 15), isTrue);
    expect(bills.length, lessThanOrEqualTo((lines / 15).ceil() + 1));
    expect(total(bills), closeTo(total(sales), 0.001));
    final covered = bills.expand((b) => b.sourceInvoices).toSet();
    expect(covered.length, 36);
  });

  test('identical lines across sales merge into one line', () {
    final a = Sale(
        id: 'a',
        invoiceNumber: 1,
        items: [item('Elbow', qty: 2), item('Tee')],
        totalAmount: 30,
        createdAt: DateTime(2026, 9, 1));
    final b = Sale(
        id: 'b',
        invoiceNumber: 2,
        items: [item('Elbow', qty: 3)],
        totalAmount: 30,
        createdAt: DateTime(2026, 9, 2));
    final bills = combineSalesIntoBills([a, b]);
    expect(bills, hasLength(1));
    expect(bills.single.items, hasLength(2));
    expect(bills.single.items.first.quantity, 5);
    expect(bills.single.number, '2');
    expect(bills.single.date, DateTime(2026, 9, 2));
  });

  test('a sale with more than 15 lines is split', () {
    final bills = combineSalesIntoBills([sale(7, 32)]);
    expect(bills.map((b) => b.items.length), [15, 15, 2]);
    expect(bills.map((b) => b.number), ['7/1', '7/2', '7/3']);
    expect(total(bills), closeTo(320, 0.001));
  });

  test('different customers stay on separate bills unless allowed', () {
    final sales = [
      sale(1, 2, buyer: 'Ramesh'),
      sale(2, 2, buyer: 'Suresh'),
      sale(3, 2, buyer: 'ramesh '),
      sale(4, 2),
      sale(5, 2, pay: PaymentMethod.upi),
    ];
    final separate = combineSalesIntoBills(sales);
    expect(separate, hasLength(3));
    final walkIn = separate.firstWhere((b) => !b.hasBuyer);
    expect(walkIn.paymentLabel, 'Cash + UPI');

    expect(combineSalesIntoBills(sales, separateBuyers: false), hasLength(1));
  });

  test('credit due is carried onto the combined bill', () {
    final credit = sale(1, 3, pay: PaymentMethod.credit); // nothing paid
    final cash = sale(2, 3);
    final bill = combineSalesIntoBills([credit, cash]).single;
    expect(bill.amountDue, closeTo(30, 0.001));
    expect(bill.totalAmount, closeTo(60, 0.001));
  });
}
