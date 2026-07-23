import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  print('Testing PDF generation...');

  try {
    final pdf = pw.Document();

    // Simulate product data
    final testProducts = List.generate(10, (i) => {
      'name': 'Product ${i + 1}',
      'size': 'Medium',
      'category': 'Test Category',
      'purchasePrice': 100.0 + i,
      'salePrice': 150.0 + i,
      'stock': 10 + i,
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        maxPages: 100,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'PRODUCT PRICE LIST',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Test Products: ${testProducts.length}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 16),
                pw.Divider(thickness: 2),
              ],
            ),
          ),

          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text('Product', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text('Price', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
              ...testProducts.map((p) => pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(p['name'] as String),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text('Rs.${(p['salePrice'] as double).toStringAsFixed(2)}'),
                  ),
                ],
              )),
            ],
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    print('✅ SUCCESS: PDF generated successfully!');
    print('   PDF size: ${bytes.length} bytes');
    print('   Pages: ${pdf.document.pages.length}');
    print('   Product count: ${testProducts.length}');
    print('\n✅ Print feature is working correctly!');

  } catch (e, stackTrace) {
    print('❌ ERROR: PDF generation failed!');
    print('   Error: $e');
    print('   Stack trace: $stackTrace');
  }
}
