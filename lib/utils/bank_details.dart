import 'package:pdf/widgets.dart' as pw;

/// The shop's bank account, optionally printed on bills so customers (mostly
/// shopkeepers paying off credit) can pay by bank transfer. Whether it's
/// shown is a remembered choice — see SettingsService.getShowBankDetails.
class BankDetails {
  static const String accountName = 'Guru Nanak Traders';
  static const String accountNumber = '15060510011164';
  static const String accountType = 'CCA';
  static const String ifsc = 'UCBA0001506';
  static const String branch = 'Thathal';

  /// Label/value pairs, in the order they're printed.
  static const List<(String, String)> rows = [
    ('A/c Name', accountName),
    ('A/c No.', accountNumber),
    ('A/c Type', accountType),
    ('IFSC', ifsc),
    ('Branch', branch),
  ];
}

/// Bank details block for the A4 invoice, drawn inside [decoration] to match
/// the invoice's other bordered sections.
pw.Widget bankDetailsPdfSection(pw.BoxDecoration decoration) {
  return pw.Container(
    width: double.infinity,
    decoration: decoration,
    padding: const pw.EdgeInsets.all(8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Bank Details',
          style: pw.TextStyle(
            fontSize: 8,
            decoration: pw.TextDecoration.underline,
          ),
        ),
        pw.SizedBox(height: 2),
        for (final (label, value) in BankDetails.rows)
          pw.Row(
            children: [
              pw.SizedBox(
                width: 60,
                child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Text(
                ': $value',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
      ],
    ),
  );
}

/// Bank details lines for a thermal receipt — one short line each so they
/// fit even the narrow 57mm roll.
List<pw.Widget> bankDetailsThermalLines() => [
      pw.Text(
        'Bank Details',
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
      for (final (label, value) in BankDetails.rows)
        pw.Text('$label: $value', style: const pw.TextStyle(fontSize: 8)),
    ];
