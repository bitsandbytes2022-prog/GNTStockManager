import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/sale_model.dart';
import 'amount_in_words.dart';
import 'pdf_fonts.dart';
import 'pdf_logo.dart';

// Seller identity — kept in step with the single-bill layouts in
// bill_preview_screen.dart / sales_list_screen.dart.
const String _shopName = 'Guru Nanak Traders';
const String _shopAddress = 'Nandpur, Teh. Amb, Distt. Una (H.P.)';
const String _shopContact = 'Mobile: 7696379802';
const String _shopGstin = '02FDUPK4649R1ZK';

/// Builds one PDF holding every sale in [month], one after another, each laid
/// out as a compact tax-invoice — a "bill book" for the month, meant to be
/// hand-copied into the physical books submitted to the CA rather than filed
/// as-is.
///
/// [sales] is whatever was fetched for the month; mock (test) sales are
/// dropped here, and the rest are ordered by bill (invoice) number, oldest
/// first, so the printout runs in the same order as the paper book.
///
/// Sale prices are treated as GST-inclusive (the same assumption the rest of
/// the app makes): when [showGst] is on, each bill reverse-computes the
/// taxable value and the CGST/SGST split baked into its total at [gstRate]%,
/// so the customer-facing total never changes.
Future<pw.Document> buildMonthlyBillBookPdf({
  required List<Sale> sales,
  required DateTime month,
  double gstRate = 18,
  bool showGst = true,
}) async {
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(fontFallback: await loadUnicodeFallbackFonts()),
  );
  final logo = await loadShopLogo();

  final ordered = sales.where((s) => !s.isMock).toList()
    ..sort((a, b) {
      final byInvoice = a.invoiceNumber.compareTo(b.invoiceNumber);
      return byInvoice != 0 ? byInvoice : a.createdAt.compareTo(b.createdAt);
    });

  double taxable(double total) =>
      showGst && gstRate > 0 ? total / (1 + gstRate / 100) : total;
  double halfGst(double total) =>
      showGst && gstRate > 0 ? (total - taxable(total)) / 2 : 0;

  final halfRate = gstRate / 2;
  final halfRateLabel = halfRate == halfRate.roundToDouble()
      ? halfRate.toStringAsFixed(0)
      : halfRate.toStringAsFixed(1);

  final monthLabel = DateFormat('MMMM yyyy').format(month);
  final grandTotal = ordered.fold<double>(0, (s, x) => s + x.totalAmount);
  final grandTaxable =
      ordered.fold<double>(0, (s, x) => s + taxable(x.totalAmount));
  final grandGst =
      ordered.fold<double>(0, (s, x) => s + halfGst(x.totalAmount) * 2);

  pw.Widget boxed(pw.Widget child) => pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
        padding: const pw.EdgeInsets.all(6),
        child: child,
      );

  // Each bill is emitted as a flat list of top-level MultiPage children
  // (not one wrapped Column): the items table can then span a page break on
  // its own, and each bordered box stays small enough to never be silently
  // dropped for not fitting a page — the same constraint the A4 single-bill
  // layout works around.
  List<pw.Widget> billChildren(Sale sale) {
    final t = taxable(sale.totalAmount);
    final half = halfGst(sale.totalAmount);
    final due = sale.amountDue;

    return [
      pw.SizedBox(height: 12),
      pw.Container(height: 1.5, color: PdfColors.black),
      pw.SizedBox(height: 6),

      // Seller + bill meta
      boxed(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_shopName,
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(_shopAddress, style: const pw.TextStyle(fontSize: 8)),
                if (showGst)
                  pw.Text('GSTIN: $_shopGstin',
                      style: const pw.TextStyle(fontSize: 8)),
                pw.Text(_shopContact, style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Bill No.  ${sale.invoiceNumber}',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    'Date  ${DateFormat('dd/MM/yyyy').format(sale.createdAt)}',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Payment  ${sale.paymentMethod.label}',
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ],
      )),

      if (_hasBuyer(sale))
        boxed(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Bill To',
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700)),
            if (sale.buyerName?.isNotEmpty ?? false)
              pw.Text(sale.buyerName!,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            if (sale.buyerPhone?.isNotEmpty ?? false)
              pw.Text('Contact: ${sale.buyerPhone}',
                  style: const pw.TextStyle(fontSize: 8)),
            if (sale.buyerAddress?.isNotEmpty ?? false)
              pw.Text(sale.buyerAddress!,
                  style: const pw.TextStyle(fontSize: 8)),
          ],
        )),

      // Items — a plain Table spans across pages on its own.
      pw.Table(
        border: pw.TableBorder.all(width: 0.6, color: PdfColors.grey600),
        columnWidths: const {
          0: pw.FlexColumnWidth(4),
          1: pw.FlexColumnWidth(1.2),
          2: pw.FlexColumnWidth(1.6),
          3: pw.FlexColumnWidth(1.8),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              _cell('Description of Goods', bold: true),
              _cell('Qty', bold: true),
              _cell(showGst ? 'Rate (Excl. GST)' : 'Rate', bold: true),
              _cell('Amount', bold: true),
            ],
          ),
          ...sale.items.map((it) {
            final rate = showGst ? taxable(it.salePrice) : it.salePrice;
            final amount = rate * it.quantity;
            final qtyLabel =
                it.isPerFoot ? '${it.quantity} ft' : '${it.quantity}';
            return pw.TableRow(children: [
              _cell('${it.productName} (${it.productSize})'),
              _cell(qtyLabel),
              _cell(rate.toStringAsFixed(2)),
              _cell(amount.toStringAsFixed(2)),
            ]);
          }),
        ],
      ),

      // Totals
      boxed(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (showGst) ...[
            _amountRow('Taxable Value', t),
            _amountRow('CGST @ $halfRateLabel%', half),
            _amountRow('SGST @ $halfRateLabel%', half),
            pw.SizedBox(height: 2),
          ],
          pw.Container(
            width: 230,
            padding: const pw.EdgeInsets.only(top: 3),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL',
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text('INR ${sale.totalAmount.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          if (sale.isCredit && due > 0)
            pw.Text('Amount Due: INR ${due.toStringAsFixed(2)}',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700)),
          pw.SizedBox(height: 2),
          pw.Text('(${amountInWords(sale.totalAmount)})',
              style:
                  pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
        ],
      )),

      if (sale.notes?.isNotEmpty ?? false)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text('Notes: ${sale.notes}',
              style: const pw.TextStyle(fontSize: 8)),
        ),
    ];
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      maxPages: 1000,
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Bill Book $monthLabel   -   Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (ctx) => [
        // Month summary
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null)
              pw.Container(
                width: 40,
                height: 40,
                margin: const pw.EdgeInsets.only(right: 10),
                child: pw.Image(logo),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_shopName,
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Monthly Bill Book  -  $monthLabel',
                      style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        boxed(pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _summaryRow('Bills in month', '${ordered.length}'),
            if (ordered.isNotEmpty)
              _summaryRow('Bill no. range',
                  '${ordered.first.invoiceNumber} to ${ordered.last.invoiceNumber}'),
            if (showGst) ...[
              _summaryRow('Total taxable value',
                  'INR ${grandTaxable.toStringAsFixed(2)}'),
              _summaryRow('Total GST (CGST + SGST)',
                  'INR ${grandGst.toStringAsFixed(2)}'),
            ],
            _summaryRow(
                'Total sales value', 'INR ${grandTotal.toStringAsFixed(2)}'),
          ],
        )),
        if (ordered.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 24),
            child: pw.Text('No sales recorded for $monthLabel.'),
          ),
        ...ordered.expand(billChildren),
      ],
    ),
  );

  return pdf;
}

bool _hasBuyer(Sale s) =>
    (s.buyerName?.isNotEmpty ?? false) ||
    (s.buyerPhone?.isNotEmpty ?? false) ||
    (s.buyerAddress?.isNotEmpty ?? false);

pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );

pw.Widget _amountRow(String label, double amount) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.SizedBox(
            width: 130,
            child: pw.Text(label,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.SizedBox(width: 10),
          pw.SizedBox(
            width: 90,
            child: pw.Text('INR ${amount.toStringAsFixed(2)}',
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      ),
    );

pw.Widget _summaryRow(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
