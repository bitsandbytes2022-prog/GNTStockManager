import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/product_model.dart';
import '../../models/sale_model.dart';
import '../../services/invoice_service.dart';
import '../../services/sales_service.dart';
import '../../utils/amount_in_words.dart';
import '../../utils/pdf_fonts.dart';

/// One line on the bill — a product plus the quantity/price/per-foot flag
/// for that specific line. A product can appear more than once (e.g. a
/// customer buys 5, then comes back later the same day for 3 more): each
/// addition is its own BillLineItem rather than being merged into a single
/// combined quantity, so the printed bill shows exactly what was bought and
/// when it was added to the cart.
class BillLineItem {
  final Product product;
  final int quantity;
  final double price;
  final bool isPerFoot;

  /// Effective purchase cost to record on the SaleItem: the full per-pipe
  /// cost for ordinary lines, or the per-foot cost for per-foot lines.
  final double unitCost;

  /// Whole stock units (pipes) to deduct for this line.
  final int stockUnits;

  const BillLineItem({
    required this.product,
    required this.quantity,
    required this.price,
    this.isPerFoot = false,
    required this.unitCost,
    required this.stockUnits,
  });
}

/// The physical thermal roll sizes the shop prints on. `printableWidthMm`
/// is the actual printable width, not the nominal roll width — e.g. an
/// "80mm" roll only prints ~72mm wide, and a "57mm" roll ~48mm, once the
/// printer's own side margins are accounted for.
enum _ThermalRollSize {
  mm80(printableWidthMm: 72, label: 'Thermal Receipt (3" / 80mm)'),
  mm57(printableWidthMm: 48, label: 'Thermal Receipt (2" / 57mm)');

  const _ThermalRollSize({required this.printableWidthMm, required this.label});

  final double printableWidthMm;
  final String label;
}

class BillPreviewScreen extends StatefulWidget {
  final List<BillLineItem> lineItems;
  final String paymentMethod;
  final String? notes;

  /// When true, completing from this preview records a mock sale (no stock
  /// deduction, excluded from analytics).
  final bool isMock;

  // Optional buyer details, recorded for future reference on the bill.
  final String? buyerName;
  final String? buyerPhone;
  final String? buyerAddress;

  /// Amount received now, used as the initial `amountPaid` when
  /// [paymentMethod] is Credit (0 means nothing received yet).
  final double initialPayment;

  const BillPreviewScreen({
    super.key,
    required this.lineItems,
    required this.paymentMethod,
    this.notes,
    this.isMock = false,
    this.buyerName,
    this.buyerPhone,
    this.buyerAddress,
    this.initialPayment = 0,
  });

  @override
  State<BillPreviewScreen> createState() => _BillPreviewScreenState();
}

class _BillPreviewScreenState extends State<BillPreviewScreen> {
  final GlobalKey _billKey = GlobalKey();
  final InvoiceService _invoiceService = InvoiceService();
  final SalesService _salesService = SalesService();

  static const String _shopGstin = '02FDUPK4649R1ZK';
  static const String _dealerTagline1 =
      'Authorised Dealer of Nerolac Paints & Prakash Surya PVC Pipes';
  static const String _dealerTagline2 =
      'Your One-Stop Shop for Hardware, Sanitary Ware & Hand Tools';

  PdfPageFormat _thermalPageFormat(_ThermalRollSize size) => PdfPageFormat(
        size.printableWidthMm * PdfPageFormat.mm,
        double.infinity,
        marginAll: 5 * PdfPageFormat.mm,
      );

  // A long thermal receipt is built as several fixed-height chunks rather
  // than one arbitrarily tall auto-sized page — see the comment where this
  // is used in _generatePdf for why. A4's height is a safe, universally
  // supported page length to chunk at.
  static const double _thermalPageChunkHeight = 297 * PdfPageFormat.mm;

  int? _invoiceNumber;
  bool _isLoading = true;
  bool _isSaving = false;
  Uint8List? _logoBytes;

  // GST breakup shown on the bill. Sale prices are treated as GST-inclusive
  // (same assumption used elsewhere in the app — see GstCalculatorScreen and
  // add_product_screen's bill-price math), so the customer's total never
  // changes: this just reverse-calculates the taxable value + CGST/SGST
  // split baked into that total.
  bool _gstEnabled = true;
  final TextEditingController _gstRateController =
      TextEditingController(text: '18');

  double get _gstRate => double.tryParse(_gstRateController.text) ?? 0;

  double _taxableValue(double total) =>
      _gstEnabled && _gstRate > 0 ? total / (1 + _gstRate / 100) : total;

  double _cgstAmount(double total) =>
      _gstEnabled && _gstRate > 0 ? (total - _taxableValue(total)) / 2 : 0;

  double _sgstAmount(double total) => _cgstAmount(total);

  String get _halfRateLabel {
    final half = _gstRate / 2;
    return half == half.roundToDouble()
        ? half.toStringAsFixed(0)
        : half.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _gstRateController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    try {
      // Get next invoice number (but don't commit it yet)
      final nextNumber = await _invoiceService.getCurrentInvoiceNumber();

      // Load logo from assets
      try {
        final ByteData data = await rootBundle.load('assets/icons/ic_logo.png');
        _logoBytes = data.buffer.asUint8List();
      } catch (e) {
        debugPrint('Logo not found: $e');
      }

      setState(() {
        _invoiceNumber = nextNumber + 1; // Preview the next number
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error initializing: $e');
      setState(() => _isLoading = false);
    }
  }

  double _calculateSubtotal() {
    return widget.lineItems.fold(
        0.0, (sum, line) => sum + (line.quantity * line.price));
  }

  double _calculateTotalProfit() {
    return widget.lineItems.fold(0.0, (sum, line) {
      final profit = (line.price - line.product.purchasePrice) * line.quantity;
      return sum + profit;
    });
  }

  Future<void> _completeSale() async {
    setState(() => _isSaving = true);

    try {
      // Get the actual next invoice number (this will increment the counter)
      final invoiceNumber = await _invoiceService.getNextInvoiceNumber();

      final paymentMethodEnum = PaymentMethod.values.firstWhere(
        (e) => e.label == widget.paymentMethod,
        orElse: () => PaymentMethod.cash,
      );

      // Create sale items — one per cart line, so a product bought in more
      // than one line is saved as separate lines on the invoice.
      final saleItems = widget.lineItems.map((line) {
        return SaleItem(
          productId: line.product.id,
          productName: line.product.name,
          productSize: line.product.size,
          quantity: line.quantity,
          salePrice: line.price,
          purchasePrice: line.unitCost,
          isPerFoot: line.isPerFoot,
          stockUnits: line.stockUnits,
        );
      }).toList();

      // Create sale with invoice number
      final sale = Sale(
        id: '',
        items: saleItems,
        totalAmount: _calculateSubtotal(),
        createdAt: DateTime.now(),
        paymentMethod: paymentMethodEnum,
        notes: widget.notes,
        invoiceNumber: invoiceNumber, // Add invoice number to sale
        isMock: widget.isMock,
        buyerName: widget.buyerName,
        buyerPhone: widget.buyerPhone,
        buyerAddress: widget.buyerAddress,
        amountPaid: paymentMethodEnum == PaymentMethod.credit
            ? widget.initialPayment
            : null,
      );

      // Save to Firebase
      await _salesService.createSale(sale);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Sale completed! Invoice #$invoiceNumber'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showPrintOptions() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Print As',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Standard (A4)'),
                subtitle: const Text('Full-page printer'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _printBill(thermalSize: null);
                },
              ),
              for (final size in _ThermalRollSize.values)
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(size.label),
                  subtitle: const Text('Thermal roll printer'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _printBill(thermalSize: size);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _printBill({required _ThermalRollSize? thermalSize}) async {
    try {
      final initialFormat =
          thermalSize != null ? _thermalPageFormat(thermalSize) : PdfPageFormat.a4;
      await Printing.layoutPdf(
        format: initialFormat,
        onLayout: (PdfPageFormat format) async {
          final pdf = await _generatePdf(format: format, thermalSize: thermalSize);
          return pdf.save();
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing: $e')),
        );
      }
    }
  }

  Future<pw.Document> _generatePdf({
    PdfPageFormat? format,
    _ThermalRollSize? thermalSize,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(fontFallback: await loadUnicodeFallbackFonts()),
    );

    pw.ImageProvider? logoImage;
    if (_logoBytes != null) {
      try {
        logoImage = pw.MemoryImage(_logoBytes!);
      } catch (e) {
        debugPrint('Error loading logo for PDF: $e');
      }
    }

    if (thermalSize != null) {
      // Width is always the true physical printable width for the chosen
      // roll size (narrower than its nominal roll width) — thermal/POS
      // printer drivers are unreliable about reporting the actual paper
      // size via the OS print dialog (often falling back to a much wider
      // standard paper size), so trusting the negotiated `format` for
      // width causes right-side content to be laid out past what the
      // printer can actually print and get cut off.
      //
      // Height used to be one single pw.Page auto-grown to fit the entire
      // receipt, however tall that ended up being. That produces a
      // complete, correct PDF — but a long item list still printed (and
      // even *previewed* in the browser's own print dialog) with items
      // silently missing past some point. That rules out a driver-side
      // paper-length limit specifically: relying on the OS/driver to
      // report a trustworthy finite page height back through `format`
      // didn't fix it either (confirmed by testing — the single giant
      // page still got clipped even when nothing about paper length
      // should have mattered for on-screen preview), so something in the
      // browser's own PDF rendering/print pipeline can't handle one
      // extremely tall page. Splitting into fixed-height chunks via
      // MultiPage avoids that entirely: a continuous-roll printer prints
      // sequential same-width pages back-to-back with no real gap, so
      // this reads as one unbroken receipt regardless of how many chunks
      // it takes.
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat(
            _thermalPageFormat(thermalSize).width,
            _thermalPageChunkHeight,
            marginAll: 5 * PdfPageFormat.mm,
          ),
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          maxPages: 200,
          build: (context) => _buildThermalContentChildren(logoImage),
        ),
      );
      return pdf;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format ?? PdfPageFormat.a4,
        maxPages: 50,
        build: (context) {
          final subtotal = _calculateSubtotal();
          final showGst = _gstEnabled && _gstRate > 0;
          final taxable = _taxableValue(subtotal);
          final cgst = _cgstAmount(subtotal);
          final sgst = _sgstAmount(subtotal);
          final due = subtotal - widget.initialPayment;

          return [
            pw.Center(
              child: pw.Text(
                showGst ? 'Tax Invoice' : 'Estimate',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 8),

            // Header: seller details + invoice meta. Kept as its own bordered
            // box (rather than one giant box wrapping the whole invoice) so a
            // long items table below can flow across pages on its own — a
            // Container isn't spannable, so anything nested inside one giant
            // Container silently fails to render if it doesn't fit one page.
            pw.Container(
              width: double.infinity,
              decoration: _sectionBorder(),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          right: pw.BorderSide(color: PdfColors.black, width: 0.8),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (logoImage != null)
                            pw.Container(
                              width: 36,
                              height: 36,
                              margin: const pw.EdgeInsets.only(bottom: 4),
                              child: pw.Image(logoImage),
                            ),
                          pw.Text(
                            'Guru Nanak Traders',
                            style: pw.TextStyle(
                              fontSize: 15,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'Nandpur, Teh. Amb, Distt. Una (H.P.)',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                          if (showGst)
                            pw.Text(
                              'GSTIN/UIN: $_shopGstin',
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          pw.Text(
                            'State Name: Himachal Pradesh, Code: 02',
                            style: pw.TextStyle(fontSize: 9),
                          ),
                          pw.Text(
                            'Contact: +91-7696379802',
                            style: pw.TextStyle(fontSize: 9),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            _dealerTagline1,
                            style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
                          ),
                          pw.Text(
                            _dealerTagline2,
                            style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _invoiceMetaRow('Invoice No.', '${_invoiceNumber ?? 'N/A'}'),
                          pw.SizedBox(height: 4),
                          _invoiceMetaRow(
                              'Dated', DateFormat('dd/MM/yyyy').format(DateTime.now())),
                          pw.SizedBox(height: 4),
                          _invoiceMetaRow('Mode of Payment', widget.paymentMethod),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_hasBuyerInfo)
              pw.Container(
                width: double.infinity,
                decoration: _sectionBorder(),
                padding: const pw.EdgeInsets.all(8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Buyer (Bill To)',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    if (widget.buyerName?.isNotEmpty ?? false)
                      pw.Text(widget.buyerName!,
                          style: pw.TextStyle(
                              fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    if (widget.buyerPhone?.isNotEmpty ?? false)
                      pw.Text('Contact: ${widget.buyerPhone}',
                          style: const pw.TextStyle(fontSize: 9)),
                    if (widget.buyerAddress?.isNotEmpty ?? false)
                      pw.Text(widget.buyerAddress!,
                          style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),

            // Items table — a plain Table can span across pages on its own,
            // unlike a Container, so a long item list no longer silently
            // fails to render when it doesn't fit on one page.
            pw.Table(
              border: pw.TableBorder(
                top: const pw.BorderSide(color: PdfColors.black, width: 0.8),
                bottom: const pw.BorderSide(color: PdfColors.black, width: 0.8),
                left: const pw.BorderSide(color: PdfColors.black, width: 0.8),
                right: const pw.BorderSide(color: PdfColors.black, width: 0.8),
                horizontalInside:
                    const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                verticalInside:
                    const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.5),
                3: pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _buildTableCell('Description of Goods', bold: true),
                    _buildTableCell('Qty', bold: true),
                    _buildTableCell(showGst ? 'Rate (Excl. GST)' : 'Rate', bold: true),
                    _buildTableCell('Amount', bold: true),
                  ],
                ),
                ...widget.lineItems.map((line) {
                  final product = line.product;
                  final qty = line.quantity;
                  final price = line.price;
                  // Item rows show the tax-exclusive rate/amount, so the
                  // Amount column sums to the Taxable Value shown below.
                  final displayPrice = showGst ? _taxableValue(price) : price;
                  final amount = qty * displayPrice;
                  final isPerFoot = line.isPerFoot;

                  return pw.TableRow(
                    children: [
                      _buildTableCell('${product.name} (${product.size})'),
                      _buildTableCell(isPerFoot ? '$qty ft' : qty.toString()),
                      _buildTableCell('INR ${displayPrice.toStringAsFixed(2)}'),
                      _buildTableCell('INR ${amount.toStringAsFixed(2)}'),
                    ],
                  );
                }),
              ],
            ),

            // Totals
            pw.Container(
              width: double.infinity,
              decoration: _sectionBorder(),
              padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (showGst) ...[
                    _plainTotalRow('Taxable Value', taxable),
                    _plainTotalRow('CGST @ $_halfRateLabel%', cgst),
                    _plainTotalRow('SGST @ $_halfRateLabel%', sgst),
                    pw.SizedBox(height: 4),
                  ],
                  pw.Container(
                    width: 260,
                    padding: const pw.EdgeInsets.only(top: 4),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(color: PdfColors.black, width: 0.8),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total',
                            style: pw.TextStyle(
                                fontSize: 13, fontWeight: pw.FontWeight.bold)),
                        pw.Text('INR ${subtotal.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                                fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  if (widget.paymentMethod == 'Credit' && due > 0) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Amount Due: INR ${due.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red700,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Amount in words
            pw.Container(
              width: double.infinity,
              decoration: _sectionBorder(),
              padding: const pw.EdgeInsets.all(8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Amount Chargeable (in words)',
                    style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    amountInWords(subtotal),
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  if (widget.notes != null && widget.notes!.isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    pw.Text('Notes: ${widget.notes}',
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ],
              ),
            ),

            // Declaration + signature
            pw.Container(
              width: double.infinity,
              decoration: _sectionBorder(),
              padding: const pw.EdgeInsets.all(8),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Declaration',
                          style: pw.TextStyle(
                            fontSize: 8,
                            decoration: pw.TextDecoration.underline,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'We declare that this invoice shows the actual '
                          'price of the goods described and that all '
                          'particulars are true and correct.',
                          style: pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'for Guru Nanak Traders',
                          style:
                              pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 28),
                        pw.Text('Authorised Signatory', style: pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                'This is a Computer Generated Invoice',
                style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
              ),
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  /// The thermal receipt's content as a flat list of top-level blocks
  /// (rather than one pw.Widget tree) so it can feed either a single
  /// auto-sized pw.Page or a pw.MultiPage that spans multiple physical
  /// pages — see the pageFormat selection in _generatePdf.
  List<pw.Widget> _buildThermalContentChildren(pw.ImageProvider? logoImage) {
    final subtotal = _calculateSubtotal();
    final showGst = _gstEnabled && _gstRate > 0;
    pw.Widget dashedDivider() => pw.Text(
          '--------------------------------',
          style: const pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        );

    return [
        // Header
        pw.Center(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null)
                pw.Container(
                  width: 36,
                  height: 36,
                  margin: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Image(logoImage),
                ),
              pw.Text(
                'Guru Nanak Traders',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Mobile: 7696379802',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Nandpur, Teh. Amb, Distt. Una (H.P.)',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 8),
              ),
              if (_gstEnabled)
                pw.Text(
                  'GSTIN: $_shopGstin',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              pw.Text(
                _dealerTagline1,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
              ),
              pw.Text(
                _dealerTagline2,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        dashedDivider(),
        pw.SizedBox(height: 4),

        // Invoice details
        pw.Text(
          '${_gstEnabled ? 'Tax Invoice' : 'Estimate'} #: ${_invoiceNumber ?? 'N/A'}',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}  Time: ${DateFormat('hh:mm a').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 4),
        if (_hasBuyerInfo) ...[
          pw.Text(
            'BILL TO',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
          if (widget.buyerName?.isNotEmpty ?? false)
            pw.Text(widget.buyerName!,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
          if (widget.buyerPhone?.isNotEmpty ?? false)
            pw.Text(widget.buyerPhone!, style: const pw.TextStyle(fontSize: 8)),
          if (widget.buyerAddress?.isNotEmpty ?? false)
            pw.Text(widget.buyerAddress!, style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 4),
          dashedDivider(),
          pw.SizedBox(height: 4),
        ],

        // Items
        ...widget.lineItems.map((line) {
          final product = line.product;
          final qty = line.quantity;
          final price = line.price;
          // Item rows show the tax-exclusive rate/amount, so the sum
          // matches the Taxable Value shown below; GST is added once at
          // the end rather than embedded in each line.
          final displayPrice = showGst ? _taxableValue(price) : price;
          final amount = qty * displayPrice;
          final isPerFoot = line.isPerFoot;
          final qtyLabel = isPerFoot ? '$qty ft' : qty.toString();

          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${product.name} (${product.size})',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '$qtyLabel x ${displayPrice.toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.Text(
                      'INR ${amount.toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),

        dashedDivider(),
        pw.SizedBox(height: 4),

        if (_gstEnabled && _gstRate > 0) ...[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Taxable Value', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('INR ${_taxableValue(subtotal).toStringAsFixed(2)}',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('CGST @ $_halfRateLabel%',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Text('INR ${_cgstAmount(subtotal).toStringAsFixed(2)}',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('SGST @ $_halfRateLabel%',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Text('INR ${_sgstAmount(subtotal).toStringAsFixed(2)}',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 4),
        ],

        // Total
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'TOTAL',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'INR ${subtotal.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        dashedDivider(),
        pw.SizedBox(height: 4),

        pw.Text(
          'Payment: ${widget.paymentMethod}',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        if (widget.paymentMethod == 'Credit' &&
            (subtotal - widget.initialPayment) > 0) ...[
          pw.Text(
            'Due: INR ${(subtotal - widget.initialPayment).toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ],

        if (widget.notes != null && widget.notes!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text('Notes: ${widget.notes}', style: const pw.TextStyle(fontSize: 8)),
        ],

        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(
            'Thank you for your business!',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
          ),
        ),
        pw.SizedBox(height: 10),
      ];
  }

  pw.Widget _buildTableCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.BoxDecoration _sectionBorder() => pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      );

  pw.Widget _invoiceMetaRow(String label, String value) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 70,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        ),
        pw.Expanded(
          child: pw.Text(value,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    );
  }

  pw.Widget _plainTotalRow(String label, double amount) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 150,
            child: pw.Text(label,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.SizedBox(width: 12),
          pw.SizedBox(
            width: 90,
            child: pw.Text('INR ${amount.toStringAsFixed(2)}',
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  String _formatQuantity(double qty) {
    if (qty == qty.toInt()) {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bill Preview')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final subtotal = _calculateSubtotal();
    final profit = _calculateTotalProfit();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Preview'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: _billKey,
                child: _buildBillContent(subtotal, profit),
              ),
            ),
          ),
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildBillContent(double subtotal, double profit) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 600),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),
          const Divider(height: 1, thickness: 2),
          _buildBuyerInfo(),

          // Items
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ITEMS',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                ...widget.lineItems.map(_buildItemRow),
              ],
            ),
          ),

          const Divider(height: 1),

          _buildGstControl(),

          // Totals
          _buildTotals(subtotal, profit),

          // Payment method
          _buildPaymentInfo(),

          // Footer
          _buildFooter(),
        ],
      ),
    );
  }

  bool get _hasBuyerInfo =>
      (widget.buyerName?.isNotEmpty ?? false) ||
      (widget.buyerPhone?.isNotEmpty ?? false) ||
      (widget.buyerAddress?.isNotEmpty ?? false);

  Widget _buildBuyerInfo() {
    if (!_hasBuyerInfo) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BILL TO',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          if (widget.buyerName?.isNotEmpty ?? false)
            Text(widget.buyerName!,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          if (widget.buyerPhone?.isNotEmpty ?? false)
            Text(widget.buyerPhone!, style: const TextStyle(fontSize: 13)),
          if (widget.buyerAddress?.isNotEmpty ?? false)
            Text(widget.buyerAddress!, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade500],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo placeholder
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _logoBytes != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _logoBytes!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.store, size: 30, color: Colors.blue);
                },
              ),
            )
                : const Icon(Icons.store, size: 30, color: Colors.blue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Guru Nanak Traders',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Mobile: 7696379802',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
                const Text(
                  'Nandpur, Teh. Amb, Distt. Una (H.P.)',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
                if (_gstEnabled)
                  const Text(
                    'GSTIN: $_shopGstin',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                const SizedBox(height: 4),
                Text(
                  _dealerTagline1,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.9),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Text(
                  _dealerTagline2,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.9),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _gstEnabled ? 'TAX INVOICE' : 'ESTIMATE',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '#: ${_invoiceNumber ?? 'N/A'}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              Text(
                'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                style: TextStyle(fontSize: 13, color: Colors.white),
              ),
              Text(
                'Time: ${DateFormat('hh:mm a').format(DateTime.now())}',
                style: TextStyle(fontSize: 13, color: Colors.white),
              ),
            ],
          ),)
        ],
      ),
    );
  }

  Widget _buildInvoiceDetails() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'ESTIMATE #: ${_invoiceNumber ?? 'N/A'}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              Text(
                'Time: ${DateFormat('hh:mm a').format(DateTime.now())}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(BillLineItem line) {
    final product = line.product;
    final qty = line.quantity;
    final price = line.price;
    final showGst = _gstEnabled && _gstRate > 0;
    final displayPrice = showGst ? _taxableValue(price) : price;
    final amount = qty * displayPrice;
    final isPerFoot = line.isPerFoot;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  product.size,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              isPerFoot ? '$qty ft' : qty.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'INR ${displayPrice.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'INR ${amount.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGstControl() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          children: [
            Checkbox(
              value: _gstEnabled,
              onChanged: (v) => setState(() => _gstEnabled = v ?? true),
            ),
            const Text(
              'Show GST (CGST + SGST)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (_gstEnabled) ...[
              const Text('Rate:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              SizedBox(
                width: 56,
                child: TextField(
                  controller: _gstRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: '%',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTotals(double subtotal, double profit) {
    final showGst = _gstEnabled && _gstRate > 0;
    final taxable = _taxableValue(subtotal);
    final cgst = _cgstAmount(subtotal);
    final sgst = _sgstAmount(subtotal);

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(showGst ? 'Taxable Value:' : 'Subtotal:',
                  style: const TextStyle(fontSize: 14)),
              Text(
                'INR ${taxable.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          if (showGst) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('CGST @ $_halfRateLabel%:',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                Text('INR ${cgst.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SGST @ $_halfRateLabel%:',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                Text('INR ${sgst.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              ],
            ),
          ],
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'INR ${subtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          // const SizedBox(height: 8),
          // Row(
          //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //   children: [
          //     Text(
          //       'Profit:',
          //       style: TextStyle(
          //         fontSize: 13,
          //         color: Colors.grey[600],
          //       ),
          //     ),
          //     Text(
          //       'INR ${profit.toStringAsFixed(2)}',
          //       style: TextStyle(
          //         fontSize: 13,
          //         color: Colors.green[700],
          //         fontWeight: FontWeight.w600,
          //       ),
          //     ),
          //   ],
          // ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo() {
    final isCredit = widget.paymentMethod == 'Credit';
    final due = _calculateSubtotal() - widget.initialPayment;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.paymentMethod == 'Cash'
                    ? Icons.money
                    : widget.paymentMethod == 'Card'
                    ? Icons.credit_card
                    : isCredit
                    ? Icons.schedule
                    : Icons.account_balance,
                size: 20,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                'Payment Method: ${widget.paymentMethod}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (isCredit && due > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Due: ₹${due.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: const Center(
        child: Text(
          'Thank you for your business!',
          style: TextStyle(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: Colors.blue,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _showPrintOptions,
              icon: const Icon(Icons.print),
              label: const Text('Print Bill'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _completeSale,
              icon: _isSaving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.check_circle),
              label: Text(_isSaving ? 'Processing...' : 'Complete Sale'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}