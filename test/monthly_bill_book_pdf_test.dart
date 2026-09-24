import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_manager/models/sale_model.dart';
import 'package:inventory_manager/utils/monthly_bill_book_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SaleItem item(String name, {int qty = 2, double price = 100, bool perFoot = false}) =>
      SaleItem(
        productId: 'p_$name',
        productName: name,
        productSize: '1 inch',
        purchasePrice: price * 0.7,
        salePrice: price,
        quantity: qty,
        isPerFoot: perFoot,
      );

  Sale sale(int invoice, DateTime date, List<SaleItem> items, {String? buyer}) {
    final total = items.fold<double>(0, (s, i) => s + i.total);
    return Sale(
      id: 's$invoice',
      invoiceNumber: invoice,
      items: items,
      totalAmount: total,
      createdAt: date,
      buyerName: buyer,
    );
  }

  test('builds a non-empty PDF for a month of sales', () async {
    final month = DateTime(2026, 8, 1);
    final sales = [
      sale(12, DateTime(2026, 8, 3), [item('GI Pipe'), item('Elbow', qty: 5)],
          buyer: 'Ramesh Kumar'),
      sale(13, DateTime(2026, 8, 17),
          [item('PVC Pipe', qty: 10, price: 55, perFoot: true)]),
      sale(11, DateTime(2026, 8, 1), [item('Tap', qty: 1, price: 320)]),
    ];

    final doc = await buildMonthlyBillBookPdf(
      sales: sales,
      month: month,
      showGst: true,
      gstRate: 18,
    );
    final bytes = await doc.save();

    expect(bytes.lengthInBytes, greaterThan(1000));
    expect(bytes.sublist(0, 4), equals('%PDF'.codeUnits));
  });

  test('handles an empty month and a GST-off run without throwing', () async {
    final empty = await buildMonthlyBillBookPdf(
      sales: const [],
      month: DateTime(2026, 7, 1),
    );
    expect((await empty.save()).lengthInBytes, greaterThan(500));

    final noGst = await buildMonthlyBillBookPdf(
      sales: [sale(1, DateTime(2026, 7, 9), [item('Screw', qty: 100, price: 2)])],
      month: DateTime(2026, 7, 1),
      showGst: false,
    );
    expect((await noGst.save()).lengthInBytes, greaterThan(1000));
  });
}
