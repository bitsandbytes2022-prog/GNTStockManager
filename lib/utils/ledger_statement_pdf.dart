import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/party_model.dart';
import '../services/ledger_service.dart';
import 'amount_in_words.dart';
import 'pdf_fonts.dart';
import 'pdf_logo.dart';

// Seller identity — kept in step with the bill layouts in
// bill_preview_screen.dart / sales_list_screen.dart / monthly_bill_book_pdf.dart.
const String _shopName = 'Guru Nanak Traders';
const String _shopAddress = 'Nandpur, Teh. Amb, Distt. Una (H.P.)';
const String _shopContact = 'Mobile: 7696379802';

final DateFormat _date = DateFormat('dd/MM/yyyy');

/// The built-in PDF font has no ₹ glyph, so amounts are plain numbers (the
/// same as the other PDFs in the app), with Indian digit grouping.
final NumberFormat _amount = NumberFormat('#,##,##0.00', 'en_IN');

String _money(double v) => _amount.format(v);

/// A shopkeeper's / supplier's account statement, to share with them.
///
/// [rows] is the full statement, oldest first. When [from] is set, only rows
/// on or after it are listed, with everything earlier carried in as one
/// "balance brought forward" line, so the closing balance is always the
/// real current balance.
Future<pw.Document> buildLedgerStatementPdf({
  required Party party,
  required List<LedgerRow> rows,
  DateTime? from,
}) async {
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(fontFallback: await loadUnicodeFallbackFonts()),
  );
  final logo = await loadShopLogo();

  final earlier =
      from == null ? <LedgerRow>[] : rows.where((r) => r.date.isBefore(from)).toList();
  final listed = from == null ? rows : rows.where((r) => !r.date.isBefore(from)).toList();
  final broughtForward = earlier.isEmpty ? 0.0 : earlier.last.balance;
  final closing = rows.isEmpty ? party.openingBalance : rows.last.balance;
  final totalDebit = listed.fold<double>(0, (s, r) => s + r.debit);
  final totalCredit = listed.fold<double>(0, (s, r) => s + r.credit);

  final isCustomer = party.isCustomer;
  final String closingLabel;
  if (closing.abs() < 0.01) {
    closingLabel = 'Settled';
  } else if (isCustomer) {
    closingLabel = closing > 0
        ? 'Balance due from ${party.name}'
        : 'Balance payable to ${party.name}';
  } else {
    closingLabel = closing > 0
        ? 'Balance payable to ${party.name}'
        : 'Advance paid to ${party.name}';
  }
  // A customer we've also bought from / paid gets wider column names.
  final twoWay = isCustomer &&
      rows.any((r) =>
          r.entry?.kind == LedgerEntryKind.boughtFrom ||
          r.entry?.kind == LedgerEntryKind.paidTo);
  final debitHeader =
      isCustomer ? (twoWay ? 'Sale / Paid' : 'Sale / Bill') : 'Purchase';
  final creditHeader = isCustomer
      ? (twoWay ? 'Received / Bought' : 'Received')
      : 'Paid';
  final period = from == null
      ? 'All entries'
      : '${_date.format(from)} to ${_date.format(DateTime.now())}';

  pw.Widget headerCell(String text, {bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Text(
          text,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      );

  pw.Widget cell(String text, {bool right = false, bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(
          text,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
              fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : null),
        ),
      );

  /// Particulars: the row title, plus each item on a sale so the shopkeeper
  /// can see what each bill was for.
  pw.Widget particulars(LedgerRow row) {
    final lines = <String>[];
    final sale = row.sale;
    if (row.source == LedgerRowSource.sale && sale != null) {
      for (final item in sale.items) {
        final size = item.productSize.isNotEmpty &&
                item.productSize != 'Custom Item'
            ? ' (${item.productSize})'
            : '';
        lines.add(
            '${item.productName}$size  ${item.quantity} x ${_money(item.salePrice)}');
      }
    } else if (row.entry != null && row.entry!.items.isNotEmpty) {
      for (final item in row.entry!.items) {
        final size = item.size.isNotEmpty ? ' (${item.size})' : '';
        lines.add('${item.name}$size  ${item.quantity} x ${_money(item.rate)}');
      }
      if (row.entry!.note?.isNotEmpty ?? false) lines.add(row.entry!.note!);
    } else if (row.subtitle?.isNotEmpty ?? false) {
      lines.add(row.subtitle!);
    }
    // The statement goes to the party itself, so name them rather than
    // saying "them".
    final title = switch (row.entry?.kind) {
      LedgerEntryKind.boughtFrom => 'Bought from ${party.name}',
      LedgerEntryKind.paidTo => 'Paid to ${party.name}',
      _ => row.title,
    };
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style:
                  pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
          for (final line in lines)
            pw.Text(line,
                style:
                    const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800)),
        ],
      ),
    );
  }

  final tableRows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        headerCell('Date'),
        headerCell('Particulars'),
        headerCell(debitHeader, right: true),
        headerCell(creditHeader, right: true),
        headerCell('Balance', right: true),
      ],
    ),
    if (from != null)
      pw.TableRow(children: [
        cell(_date.format(from)),
        cell('Balance brought forward', bold: true),
        cell(''),
        cell(''),
        cell(_money(broughtForward), right: true, bold: true),
      ]),
    for (final row in listed)
      pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        children: [
          cell(_date.format(row.date)),
          particulars(row),
          cell(row.debit > 0 ? _money(row.debit) : '', right: true),
          cell(row.credit > 0 ? _money(row.credit) : '', right: true),
          cell(_money(row.balance), right: true),
        ],
      ),
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        cell(''),
        cell('Total', bold: true),
        cell(_money(totalDebit), right: true, bold: true),
        cell(_money(totalCredit), right: true, bold: true),
        cell(_money(closing), right: true, bold: true),
      ],
    ),
  ];

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated on ${_date.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        ],
      ),
      build: (ctx) => [
        // Shop header
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
                  pw.Text(_shopAddress, style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(_shopContact, style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('ACCOUNT STATEMENT',
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(period, style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 1.2, color: PdfColors.black),
        pw.SizedBox(height: 8),

        // Party + closing balance
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(isCustomer ? 'Account of' : 'Supplier',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey700)),
                  pw.Text(party.name,
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  if (party.phone?.isNotEmpty ?? false)
                    pw.Text('Contact: ${party.phone}',
                        style: const pw.TextStyle(fontSize: 9)),
                  if (party.address?.isNotEmpty ?? false)
                    pw.Text(party.address!,
                        style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(closingLabel,
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('INR ${_money(closing.abs())}',
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text('as on ${_date.format(DateTime.now())}',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),

        if (listed.isEmpty && from == null)
          pw.Text('No entries yet.', style: const pw.TextStyle(fontSize: 10))
        else
          pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
            columnWidths: const {
              0: pw.FixedColumnWidth(58),
              1: pw.FlexColumnWidth(4),
              2: pw.FixedColumnWidth(68),
              3: pw.FixedColumnWidth(68),
              4: pw.FixedColumnWidth(72),
            },
            children: tableRows,
          ),

        pw.SizedBox(height: 10),
        if (closing.abs() >= 0.01)
          pw.Text(
            '$closingLabel: INR ${_money(closing.abs())} (${amountInWords(closing.abs())})',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${party.name}: please check and inform $_shopName of any '
          'difference. Thank you for the business.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  );
  return pdf;
}
