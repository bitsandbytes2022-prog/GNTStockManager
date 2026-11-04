import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/sale_model.dart';
import 'amount_in_words.dart';
import 'bill_book_batching.dart';
import 'gst_rounding.dart';
import 'pdf_fonts.dart';
import 'pdf_logo.dart';
import 'thermal_print.dart';

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
/// all in whole rupees (see [roundedGstBreakup]), with a "Round off" line so
/// the customer-facing total never changes.
///
/// With [combine] on, the month's sales are first packed into as few bills
/// as possible, each with at most [maxItemsPerBill] lines — see
/// [combineSalesIntoBills]. [separateBuyers] keeps different customers'
/// sales on separate bills.
///
/// With [thermalSize] set, the book is laid out as one long receipt for that
/// roll width (bills one after another, split by dashed lines) instead of on
/// A4 — see [thermalPageFormat] for [thermalOffsetMm] and
/// [thermalPageLengthMm].
Future<pw.Document> buildMonthlyBillBookPdf({
  required List<Sale> sales,
  required DateTime month,
  double gstRate = 18,
  bool showGst = true,
  bool combine = false,
  int maxItemsPerBill = 15,
  bool separateBuyers = true,
  ThermalRollSize? thermalSize,
  double thermalOffsetMm = 0,
  double thermalPageLengthMm = thermalPageLengthDefaultMm,
}) async {
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(fontFallback: await loadUnicodeFallbackFonts()),
  );
  final logo = await loadShopLogo();

  final realSales = sales.where((s) => !s.isMock).toList()
    ..sort((a, b) {
      final byInvoice = a.invoiceNumber.compareTo(b.invoiceNumber);
      return byInvoice != 0 ? byInvoice : a.createdAt.compareTo(b.createdAt);
    });
  final ordered = combine
      ? combineSalesIntoBills(realSales,
          maxItems: maxItemsPerBill, separateBuyers: separateBuyers)
      : realSales.map(BookBill.fromSale).toList();

  final withGst = showGst && gstRate > 0;
  final breakups = {
    for (final b in ordered)
      b: withGst
          ? roundedGstBreakup(
              prices: [for (final i in b.items) i.salePrice],
              quantities: [for (final i in b.items) i.quantity],
              total: b.totalAmount,
              gstRate: gstRate)
          : null,
  };

  final halfRate = gstRate / 2;
  final halfRateLabel = halfRate == halfRate.roundToDouble()
      ? halfRate.toStringAsFixed(0)
      : halfRate.toStringAsFixed(1);

  final monthLabel = DateFormat('MMMM yyyy').format(month);
  final grandTotal = ordered.fold<double>(0, (s, x) => s + x.totalAmount);
  final grandTaxable =
      breakups.values.fold<double>(0, (s, g) => s + (g?.taxable ?? 0));
  final grandGst =
      breakups.values.fold<double>(0, (s, g) => s + (g?.halfGst ?? 0) * 2);

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
  List<pw.Widget> billChildren(BookBill sale) {
    final gst = breakups[sale];
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
                pw.Text('Bill No.  ${sale.number}',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    'Date  ${DateFormat('dd/MM/yyyy').format(sale.date)}',
                    style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Payment  ${sale.paymentLabel}',
                    style: const pw.TextStyle(fontSize: 9)),
                if (sale.isCombined)
                  pw.Text(
                      'Covers sales '
                      '${sale.sourceInvoices.map((n) => '#$n').join(', ')}',
                      style: const pw.TextStyle(
                          fontSize: 7, color: PdfColors.grey700)),
              ],
            ),
          ),
        ],
      )),

      if (sale.hasBuyer)
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
          for (var i = 0; i < sale.items.length; i++)
            () {
              final it = sale.items[i];
              final line = gst?.lines[i];
              final rate = line?.rate ?? it.salePrice;
              final amount = line?.amount ?? it.total;
              final qtyLabel =
                  it.qtyLabel;
              return pw.TableRow(children: [
                _cell('${it.productName} (${it.productSize})'),
                _cell(qtyLabel),
                _cell(formatRate(rate)),
                _cell(amount.toStringAsFixed(2)),
              ]);
            }(),
        ],
      ),

      // Totals
      boxed(pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (gst != null) ...[
            _amountRow('Taxable Value', gst.taxable),
            _amountRow('CGST @ $halfRateLabel%', gst.halfGst),
            _amountRow('SGST @ $halfRateLabel%', gst.halfGst),
            if (gst.hasRoundOff)
              _amountRow('Round off', gst.roundOff, signed: true),
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
          if (due > 0.005)
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

  if (thermalSize != null) {
    pw.Widget dashed() => pw.Center(
        child: pw.Text('--------------------------------',
            style: const pw.TextStyle(fontSize: 8)));
    pw.Widget row(String label, String value, {bool bold = false}) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: bold ? 10 : 8,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: bold ? 10 : 8,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        );
    const small = pw.TextStyle(fontSize: 8);

    List<pw.Widget> thermalBill(BookBill sale) {
      final gst = breakups[sale];
      final due = sale.amountDue;
      return [
        pw.SizedBox(height: 4),
        pw.Container(height: 1.2, color: PdfColors.black),
        pw.SizedBox(height: 2),
        pw.Text('${showGst ? 'Tax Invoice' : 'Bill'} #: ${sale.number}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text('Date: ${DateFormat('dd/MM/yyyy').format(sale.date)}', style: small),
        pw.Text('Payment: ${sale.paymentLabel}', style: small),
        if (sale.isCombined)
          pw.Text(
              'Covers sales ${sale.sourceInvoices.map((n) => '#$n').join(', ')}',
              style: const pw.TextStyle(fontSize: 7)),
        if (sale.hasBuyer) ...[
          pw.SizedBox(height: 2),
          pw.Text('BILL TO',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          if (sale.buyerName?.isNotEmpty ?? false)
            pw.Text(sale.buyerName!,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          if (sale.buyerPhone?.isNotEmpty ?? false)
            pw.Text(sale.buyerPhone!, style: small),
          if (sale.buyerAddress?.isNotEmpty ?? false)
            pw.Text(sale.buyerAddress!, style: small),
        ],
        pw.SizedBox(height: 2),
        dashed(),
        pw.SizedBox(height: 2),
        for (var i = 0; i < sale.items.length; i++)
          () {
            final it = sale.items[i];
            final line = gst?.lines[i];
            final rate = line?.rate ?? it.salePrice;
            final amount = line?.amount ?? it.total;
            // Inseparable: keeps an item's name and its qty x rate line on
            // the same page of the roll.
            return pw.Inseparable(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('${i + 1}. ${it.productName} (${it.productSize})',
                        style: pw.TextStyle(
                            fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    row('${it.qtyLabel} x ${formatRate(rate)}',
                        'INR ${amount.toStringAsFixed(2)}'),
                  ],
                ),
              ),
            );
          }(),
        dashed(),
        pw.SizedBox(height: 2),
        if (gst != null) ...[
          row('Taxable Value', 'INR ${gst.taxable.toStringAsFixed(2)}'),
          row('CGST @ $halfRateLabel%', 'INR ${gst.halfGst.toStringAsFixed(2)}'),
          row('SGST @ $halfRateLabel%', 'INR ${gst.halfGst.toStringAsFixed(2)}'),
          if (gst.hasRoundOff)
            row('Round off', 'INR ${formatRoundOff(gst.roundOff)}'),
          pw.SizedBox(height: 2),
        ],
        row('TOTAL', 'INR ${sale.totalAmount.toStringAsFixed(2)}', bold: true),
        if (due > 0.005)
          pw.Text('Due: INR ${due.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.Text('(${amountInWords(sale.totalAmount)})',
            style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic)),
        if (sale.notes?.isNotEmpty ?? false)
          pw.Text('Notes: ${sale.notes}', style: small),
      ];
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: thermalPageFormat(thermalSize,
            offsetMm: thermalOffsetMm, pageLengthMm: thermalPageLengthMm),
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        maxPages: 2000,
        build: (ctx) => [
          pw.Center(
            child: pw.Column(
              children: [
                if (logo != null)
                  pw.Container(
                    width: 32,
                    height: 32,
                    margin: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Image(logo),
                  ),
                pw.Text(_shopName,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(_shopAddress,
                    textAlign: pw.TextAlign.center, style: small),
                if (showGst)
                  pw.Text('GSTIN: $_shopGstin',
                      textAlign: pw.TextAlign.center, style: small),
                pw.Text(_shopContact,
                    textAlign: pw.TextAlign.center, style: small),
                pw.SizedBox(height: 4),
                pw.Text('Monthly Bill Book - $monthLabel',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          dashed(),
          row('Bills in month', '${ordered.length}'),
          if (combine) row('Combined from', '${realSales.length} sales'),
          if (ordered.isNotEmpty)
            row('Bill no.', '${ordered.first.number} to ${ordered.last.number}'),
          if (showGst) ...[
            row('Taxable value', 'INR ${grandTaxable.toStringAsFixed(2)}'),
            row('GST (CGST+SGST)', 'INR ${grandGst.toStringAsFixed(2)}'),
          ],
          row('Total sales', 'INR ${grandTotal.toStringAsFixed(2)}', bold: true),
          if (ordered.isEmpty) pw.Text('No sales recorded for $monthLabel.'),
          ...ordered.expand(thermalBill),
          pw.SizedBox(height: 10),
        ],
      ),
    );
    return pdf;
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
            if (combine)
              _summaryRow('Combined from',
                  '${realSales.length} sales (max $maxItemsPerBill items per bill)'),
            if (ordered.isNotEmpty)
              _summaryRow('Bill no. range',
                  '${ordered.first.number} to ${ordered.last.number}'),
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

pw.Widget _amountRow(String label, double amount, {bool signed = false}) =>
    pw.Padding(
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
            child: pw.Text(
                'INR ${signed && amount > 0 ? '+' : ''}'
                '${amount.toStringAsFixed(2)}',
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
