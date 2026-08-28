import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:inventory_manager/ui/screens/record_sale_screen.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/sale_model.dart';
import '../../services/sales_service.dart';
import '../../utils/amount_in_words.dart';
import '../../utils/pdf_fonts.dart';
import '../../utils/pdf_logo.dart';
import 'package:inventory_manager/ui/screens/return_items_screen.dart';

import 'edit_sales_screen.dart';

enum TimeSpan {
  today,
  yesterday,
  last7Days,
  last30Days,
  thisMonth,
  lastMonth,
  last3Months,
  last6Months,
  thisYear,
  allTime,
  custom,
}

/// The physical thermal roll sizes the shop prints on. `printableWidthMm`
/// is the actual printable width, not the nominal roll width — e.g. an
/// "80mm" roll only prints ~72mm wide, and a "57mm" roll ~48mm, once the
/// printer's own side margins are accounted for. Matches
/// bill_preview_screen.dart's identical enum.
enum _ThermalRollSize {
  mm80(printableWidthMm: 72, label: 'Thermal Receipt (3" / 80mm)'),
  mm57(printableWidthMm: 48, label: 'Thermal Receipt (2" / 57mm)');

  const _ThermalRollSize({required this.printableWidthMm, required this.label});

  final double printableWidthMm;
  final String label;
}

class SalesListScreen extends StatefulWidget {
  const SalesListScreen({super.key});

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  final SalesService _salesService = SalesService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _useStreamMode = true;
  TimeSpan _selectedTimeSpan = TimeSpan.allTime;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String _searchQuery = '';
  bool _creditDueOnly = false;

  // Merge-sales selection mode. `_lastLoadedSales` is refreshed (without
  // setState) every time `_buildSalesContent` builds, so the merge action
  // always has the currently-visible `Sale` objects behind the selected ids
  // without needing its own separate fetch.
  bool _selectionMode = false;
  Set<String> _selectedSaleIds = {};
  List<Sale> _lastLoadedSales = [];

  static const String _shopGstin = '02FDUPK4649R1ZK';
  static const String _dealerTagline1 =
      'Authorised Dealer of Nerolac Paints & Prakash Surya PVC Pipes';
  static const String _dealerTagline2 =
      'Your One-Stop Shop for Hardware, Sanitary Ware & Hand Tools';
  // Reprinted invoices don't have an interactive rate picker (unlike the
  // new-sale bill preview), so use the same 18% default there is.
  static const double _gstRate = 18;

  PdfPageFormat _thermalPageFormat(_ThermalRollSize size) => PdfPageFormat(
        size.printableWidthMm * PdfPageFormat.mm,
        double.infinity,
        marginAll: 5 * PdfPageFormat.mm,
      );

  // A long thermal receipt is built as several fixed-height chunks rather
  // than one arbitrarily tall auto-sized page — see the comment where this
  // is used in _generateThermalInvoicePdf for why.
  static const double _thermalPageChunkHeight = 297 * PdfPageFormat.mm;

  double _taxableValue(double total) => total / (1 + _gstRate / 100);
  double _cgstAmount(double total) => (total - _taxableValue(total)) / 2;
  double _sgstAmount(double total) => _cgstAmount(total);
  String get _halfRateLabel {
    const half = _gstRate / 2;
    return half == half.roundToDouble()
        ? half.toStringAsFixed(0)
        : half.toStringAsFixed(1);
  }

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;
  bool get _isTablet => MediaQuery.of(context).size.width >= 768;

  // ==========================================
  // RESPONSIVE GRID CONFIGURATION
  // ==========================================

  Future<void> _editSale(Sale sale) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditSaleScreen(sale: sale),
      ),
    );

    if (result == true) {
      _refreshSales();
    }
  }

  void _enterSelectionMode(Sale sale) {
    setState(() {
      _selectionMode = true;
      _selectedSaleIds = {sale.id};
    });
  }

  void _toggleSelection(Sale sale) {
    setState(() {
      if (_selectedSaleIds.contains(sale.id)) {
        _selectedSaleIds.remove(sale.id);
        if (_selectedSaleIds.isEmpty) _selectionMode = false;
      } else {
        _selectedSaleIds.add(sale.id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedSaleIds = {};
    });
  }

  Future<void> _confirmMergeSelected() async {
    final selected = _lastLoadedSales
        .where((s) => _selectedSaleIds.contains(s.id))
        .toList();
    if (selected.length < 2) return;

    if (selected.map((s) => s.isMock).toSet().length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot merge a mock (test) sale with a real sale'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final sorted = [...selected]
      ..sort((a, b) => a.invoiceNumber.compareTo(b.invoiceNumber));
    final survivor = sorted.first;
    final others = sorted.skip(1).toList();
    final newTotal = sorted.fold(0.0, (sum, s) => sum + s.totalAmount);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Merge Sales'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invoice #${survivor.invoiceNumber} '
              '(${DateFormat('dd MMM yyyy').format(survivor.createdAt)}) '
              'stays as the main sale.',
            ),
            const SizedBox(height: 12),
            const Text(
              'These will be added into it, then removed:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (final other in others)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '#${other.invoiceNumber} '
                  '(${DateFormat('dd MMM yyyy').format(other.createdAt)}) '
                  '— ₹${other.totalAmount.toStringAsFixed(0)}',
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'New total: ₹${newTotal.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _salesService.mergeSales(selected);
      if (mounted) {
        _exitSelectionMode();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sales merged'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _refreshSales();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error merging sales: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Calculate number of columns based on screen width
  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (kIsWeb) {
      if (width > 1400) return 5;
      if (width > 1200) return 4;
      if (width > 900) return 3;
      if (width > 600) return 2;
      return 1;
    } else {
      return 2;
    }
  }

  /// Calculate spacing between grid items
  double _getGridSpacing(BuildContext context) {
    return kIsWeb ? 20 : 16;
  }

  /// Calculate aspect ratio for grid items
  /// Sales cards need to be taller than product cards to prevent overflow
  double _getChildAspectRatio(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // Very conservative ratios to ensure all content fits comfortably
    // Lower ratio = Taller cards = More space for content
    if (width > 1600) return 1.4;   // Very wide desktop
    if (width > 1400) return 1.3;   // Wide desktop
    if (width > 1200) return 1.2;   // Desktop
    if (width > 900) return 1.1;    // Small desktop/tablet
    if (width > 600) return 1.0;    // Large phone
    return 0.85;                    // Phone (taller than wide)
  }

  Future<void> _returnItems(Sale sale) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReturnItemsScreen(sale: sale),
      ),
    );

    if (result == true) {
      _refreshSales();
    }
  }

  Future<void> _deleteSale(Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Sale'),
        content: const Text(
          'Are you sure you want to delete this sale? Stock will be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _salesService.deleteSale(sale.id, sale.items);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sale deleted successfully'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting sale: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _recordPayment(Sale sale) async {
    final amountController = TextEditingController(
      text: sale.amountDue.toStringAsFixed(2),
    );
    final noteController = TextEditingController();

    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Record Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Amount due: ₹${sale.amountDue.toStringAsFixed(2)}',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount received',
                prefixText: '₹',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(amountController.text);
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid amount')),
                );
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );

    if (amount == null) return;

    try {
      await _salesService.recordPayment(
        saleId: sale.id,
        amount: amount,
        note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment of ₹${amount.toStringAsFixed(2)} recorded'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _refreshSales();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error recording payment: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showSaleDetails(Sale sale) async {
    await showDialog(
      context: context,
      builder: (context) => _SaleDetailsDialog(sale: sale),
    );
  }

  Future<void> _showPrintOptions(Sale sale) async {
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
                  _printInvoice(sale, thermalSize: null);
                },
              ),
              for (final size in _ThermalRollSize.values)
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(size.label),
                  subtitle: const Text('Thermal roll printer'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _printInvoice(sale, thermalSize: size);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _printInvoice(Sale sale, {required _ThermalRollSize? thermalSize}) async {
    try {
      final initialFormat =
          thermalSize != null ? _thermalPageFormat(thermalSize) : PdfPageFormat.a4;
      await Printing.layoutPdf(
        format: initialFormat,
        // Ignore the negotiated `format` entirely — same reasoning as the
        // thermal branch: the OS/browser print dialog's reported paper size
        // is unreliable (e.g. it can reflect a different previously-used
        // printer's paper instead of what was actually picked in the
        // "Print As" sheet), so an A4 choice here could otherwise get
        // silently rendered at some other printer's narrow width instead
        // of true A4.
        onLayout: (PdfPageFormat format) async {
          final pdf = thermalSize != null
              ? await _generateThermalInvoicePdf(sale, thermalSize)
              : await _generateInvoicePdf(sale);
          return pdf.save();
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error printing invoice: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  bool _hasBuyerInfo(Sale sale) =>
      (sale.buyerName?.isNotEmpty ?? false) ||
      (sale.buyerPhone?.isNotEmpty ?? false) ||
      (sale.buyerAddress?.isNotEmpty ?? false);

  /// True once a sale has items from more than one calendar day — i.e. it
  /// was produced by "Merge Sales" — so print/detail views know to show
  /// each item's date instead of rendering as an ordinary single-date sale.
  bool _isMergedSale(Sale sale) => sale.items
          .map((item) {
            final d = item.effectiveDate(sale);
            return DateTime(d.year, d.month, d.day);
          })
          .toSet()
          .length >
      1;

  /// Groups a sale's items by calendar day (oldest first), so a merged
  /// sale's print/detail views can show the date once per batch instead of
  /// repeating it on every line.
  List<MapEntry<DateTime, List<SaleItem>>> _groupItemsByDate(Sale sale) {
    final groups = <DateTime, List<SaleItem>>{};
    for (final item in sale.items) {
      final d = item.effectiveDate(sale);
      groups.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(item);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  Future<pw.Document> _generateInvoicePdf(Sale sale) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(fontFallback: await loadUnicodeFallbackFonts()),
    );
    final logoImage = await loadShopLogo();
    final due = sale.amountDue;
    final merged = _isMergedSale(sale);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 50,
        build: (context) {
          return [
            pw.Center(
              child: pw.Text(
                'Tax Invoice',
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
                          _invoiceMetaRow('Invoice No.', '${sale.invoiceNumber}'),
                          pw.SizedBox(height: 4),
                          _invoiceMetaRow(
                              'Dated', DateFormat('dd/MM/yyyy').format(sale.createdAt)),
                          pw.SizedBox(height: 4),
                          _invoiceMetaRow('Mode of Payment', sale.paymentMethod.label),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_hasBuyerInfo(sale))
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
                    if (sale.buyerName?.isNotEmpty ?? false)
                      pw.Text(sale.buyerName!,
                          style: pw.TextStyle(
                              fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    if (sale.buyerPhone?.isNotEmpty ?? false)
                      pw.Text('Contact: ${sale.buyerPhone}',
                          style: const pw.TextStyle(fontSize: 9)),
                    if (sale.buyerAddress?.isNotEmpty ?? false)
                      pw.Text(sale.buyerAddress!,
                          style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),

            // Items table(s) — a plain Table can span across pages on its
            // own, unlike a Container, so a long item list no longer
            // silently fails to render when it doesn't fit on one page. A
            // merged sale gets one table per original purchase date, each
            // preceded by a date label shown once for that whole batch
            // rather than repeated on every line.
            if (merged)
              ..._groupItemsByDate(sale).expand((group) => [
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 8, bottom: 3),
                      child: pw.Text(
                        'Added: ${DateFormat('dd MMM yyyy').format(group.key)}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    _itemsTable(group.value),
                  ])
            else
              _itemsTable(sale.items),

            // Totals
            pw.Container(
              width: double.infinity,
              decoration: _sectionBorder(),
              padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _plainTotalRow('Taxable Value', _taxableValue(sale.totalAmount)),
                  _plainTotalRow(
                      'CGST @ $_halfRateLabel%', _cgstAmount(sale.totalAmount)),
                  _plainTotalRow(
                      'SGST @ $_halfRateLabel%', _sgstAmount(sale.totalAmount)),
                  pw.SizedBox(height: 4),
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
                        pw.Text('INR ${sale.totalAmount.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                                fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  if (sale.isCredit && due > 0) ...[
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
                    amountInWords(sale.totalAmount),
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  if (sale.notes != null && sale.notes!.isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    pw.Text('Notes: ${sale.notes}',
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

  Future<pw.Document> _generateThermalInvoicePdf(
    Sale sale,
    _ThermalRollSize thermalSize,
  ) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(fontFallback: await loadUnicodeFallbackFonts()),
    );
    final logoImage = await loadShopLogo();
    final due = sale.amountDue;
    final merged = _isMergedSale(sale);

    pw.Widget dashedDivider() => pw.Text(
          '--------------------------------',
          style: const pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        );

    // Width is always the true physical printable width for the chosen
    // roll size — thermal/POS drivers often misreport it (see
    // bill_preview_screen.dart's identical branch). Height used to be one
    // single pw.Page auto-grown
    // to fit the entire invoice, however tall — that produces a complete,
    // correct PDF, but a long invoice still printed (and even *previewed*
    // in the browser's own print dialog) with items silently missing past
    // some point, and relying on the OS/driver's negotiated page height
    // didn't fix it either. Something in the browser's own PDF rendering/
    // print pipeline can't handle one extremely tall page, so this is
    // built as several fixed-height chunks via MultiPage instead — a
    // continuous-roll printer prints sequential same-width pages
    // back-to-back with no real gap, so it still reads as one unbroken
    // invoice regardless of how many chunks it takes.
    final children = [
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
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
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

              pw.Text(
                'Tax Invoice #: ${sale.invoiceNumber}',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Date: ${DateFormat('dd/MM/yyyy').format(sale.createdAt)}  '
                'Time: ${DateFormat('hh:mm a').format(sale.createdAt)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.SizedBox(height: 4),
              if (_hasBuyerInfo(sale)) ...[
                pw.Text(
                  'BILL TO',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                ),
                if (sale.buyerName?.isNotEmpty ?? false)
                  pw.Text(sale.buyerName!,
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                if (sale.buyerPhone?.isNotEmpty ?? false)
                  pw.Text(sale.buyerPhone!, style: const pw.TextStyle(fontSize: 8)),
                if (sale.buyerAddress?.isNotEmpty ?? false)
                  pw.Text(sale.buyerAddress!, style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 4),
                dashedDivider(),
                pw.SizedBox(height: 4),
              ],

              // A merged sale shows the date once per batch, right before
              // that batch's items, rather than repeating it on every line.
              ..._groupItemsByDate(sale).expand((group) => [
                    if (merged) ...[
                      pw.Text(
                        'Added: ${DateFormat('dd MMM yyyy').format(group.key)}',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                    ],
                    ...group.value.map((item) {
                      final displayPrice = _taxableValue(item.salePrice);
                      final amount = item.quantity * displayPrice;
                      final qtyLabel =
                          item.isPerFoot ? '${item.quantity} ft' : '${item.quantity}';
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              '${item.productName} (${item.productSize})',
                              style:
                                  pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                            ),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('$qtyLabel x ${displayPrice.toStringAsFixed(2)}',
                                    style: const pw.TextStyle(fontSize: 8)),
                                pw.Text('INR ${amount.toStringAsFixed(2)}',
                                    style: const pw.TextStyle(fontSize: 8)),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ]),

              dashedDivider(),
              pw.SizedBox(height: 4),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Taxable Value', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('INR ${_taxableValue(sale.totalAmount).toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CGST @ $_halfRateLabel%', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('INR ${_cgstAmount(sale.totalAmount).toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('SGST @ $_halfRateLabel%', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('INR ${_sgstAmount(sale.totalAmount).toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 4),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text('INR ${sale.totalAmount.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 4),
              dashedDivider(),
              pw.SizedBox(height: 4),

              pw.Text(
                'Payment: ${sale.paymentMethod.label}',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              ),
              if (sale.isCredit && due > 0) ...[
                pw.Text(
                  'Due: INR ${due.toStringAsFixed(2)}',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                ),
              ],

              if (sale.notes != null && sale.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text('Notes: ${sale.notes}', style: const pw.TextStyle(fontSize: 8)),
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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          _thermalPageFormat(thermalSize).width,
          _thermalPageChunkHeight,
          marginAll: 5 * PdfPageFormat.mm,
        ),
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        maxPages: 200,
        build: (context) => children,
      ),
    );

    return pdf;
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
                textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.SizedBox(width: 12),
          pw.SizedBox(
            width: 90,
            child: pw.Text('INR ${amount.toStringAsFixed(2)}',
                textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  /// The standard Description/Qty/Rate/Amount items table used on the A4
  /// invoice, built once per date batch for a merged sale or once for the
  /// whole sale otherwise.
  pw.Widget _itemsTable(List<SaleItem> items) {
    return pw.Table(
      border: pw.TableBorder(
        top: const pw.BorderSide(color: PdfColors.black, width: 0.8),
        bottom: const pw.BorderSide(color: PdfColors.black, width: 0.8),
        left: const pw.BorderSide(color: PdfColors.black, width: 0.8),
        right: const pw.BorderSide(color: PdfColors.black, width: 0.8),
        horizontalInside: const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        verticalInside: const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
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
            _buildPdfTableCell('Description of Goods', bold: true),
            _buildPdfTableCell('Qty', bold: true),
            _buildPdfTableCell('Rate (Excl. GST)', bold: true),
            _buildPdfTableCell('Amount', bold: true),
          ],
        ),
        ...items.map((item) {
          // Item rows show the tax-exclusive rate/amount, so the Amount
          // column sums to the Taxable Value shown below.
          final displayPrice = _taxableValue(item.salePrice);
          final amount = item.quantity * displayPrice;
          return pw.TableRow(
            children: [
              _buildPdfTableCell('${item.productName} (${item.productSize})'),
              _buildPdfTableCell(
                  item.isPerFoot ? '${item.quantity} ft' : '${item.quantity}'),
              _buildPdfTableCell('INR ${displayPrice.toStringAsFixed(2)}'),
              _buildPdfTableCell('INR ${amount.toStringAsFixed(2)}'),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _buildPdfTableCell(String text, {bool bold = false}) {
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

  Future<void> _refreshSales() async {
    _salesService.clearCache();
    setState(() {});
  }

  Map<String, DateTime> _getDateRange() {
    final now = DateTime.now();
    DateTime startDate;
    DateTime endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_selectedTimeSpan) {
      case TimeSpan.today:
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case TimeSpan.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
        endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
        break;
      case TimeSpan.last7Days:
        startDate = now.subtract(const Duration(days: 7));
        break;
      case TimeSpan.last30Days:
        startDate = now.subtract(const Duration(days: 30));
        break;
      case TimeSpan.thisMonth:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case TimeSpan.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        startDate = lastMonth;
        endDate = DateTime(now.year, now.month, 0, 23, 59, 59);
        break;
      case TimeSpan.last3Months:
        startDate = DateTime(now.year, now.month - 3, now.day);
        break;
      case TimeSpan.last6Months:
        startDate = DateTime(now.year, now.month - 6, now.day);
        break;
      case TimeSpan.thisYear:
        startDate = DateTime(now.year, 1, 1);
        break;
      case TimeSpan.custom:
        startDate = _customStartDate ?? DateTime(2000, 1, 1);
        endDate = _customEndDate ?? now;
        break;
      case TimeSpan.allTime:
        startDate = DateTime(2000, 1, 1);
        endDate = DateTime(2100, 12, 31);
        break;
    }

    return {'start': startDate, 'end': endDate};
  }

  List<Sale> _filterSalesByDateRange(List<Sale> sales) {
    if (_selectedTimeSpan == TimeSpan.allTime) return sales;

    final range = _getDateRange();
    final startDate = range['start']!;
    final endDate = range['end']!;

    return sales.where((sale) {
      return sale.createdAt.isAfter(startDate) && sale.createdAt.isBefore(endDate);
    }).toList();
  }

  List<Sale> _filterSalesBySearch(List<Sale> sales) {
    if (_searchQuery.isEmpty) return sales;

    final query = _searchQuery.toLowerCase();
    return sales.where((sale) {
      if (sale.buyerName != null &&
          sale.buyerName!.toLowerCase().contains(query)) {
        return true;
      }
      // Check if any item in the sale contains the search query
      return sale.items.any((item) =>
          item.productName.toLowerCase().contains(query) ||
          item.productSize.toLowerCase().contains(query));
    }).toList();
  }

  List<Sale> _filterSalesByCreditDue(List<Sale> sales) {
    if (!_creditDueOnly) return sales;
    return sales.where((sale) => sale.isCredit && !sale.isFullyPaid).toList();
  }

  Map<String, dynamic> _calculateDetailedStats(List<Sale> sales) {
    if (sales.isEmpty) {
      return {
        'totalSales': 0,
        'totalRevenue': 0.0,
        'totalProfit': 0.0,
        'totalCost': 0.0,
        'profitPercentage': 0.0,
        'itemsSold': 0,
        'averageSaleValue': 0.0,
        'averageProfit': 0.0,
      };
    }

    double totalRevenue = 0;
    double totalCost = 0;
    double totalProfit = 0;
    int itemsSold = 0;

    for (final sale in sales) {
      totalRevenue += sale.totalAmount;

      for (final item in sale.items) {
        final cost = item.purchasePrice * item.quantity;
        final profit = (item.salePrice - item.purchasePrice) * item.quantity;

        totalCost += cost;
        totalProfit += profit;
        itemsSold += item.quantity;
      }
    }

    final profitPercentage = totalCost > 0 ? (totalProfit / totalCost) * 100 : 0;
    final averageSaleValue = sales.isNotEmpty ? totalRevenue / sales.length : 0;
    final averageProfit = sales.isNotEmpty ? totalProfit / sales.length : 0;

    return {
      'totalSales': sales.length,
      'totalRevenue': totalRevenue,
      'totalProfit': totalProfit,
      'totalCost': totalCost,
      'profitPercentage': profitPercentage,
      'itemsSold': itemsSold,
      'averageSaleValue': averageSaleValue,
      'averageProfit': averageProfit,
    };
  }

  void _showTimeSpanPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TimeSpanPickerBottomSheet(
        selectedTimeSpan: _selectedTimeSpan,
        customStartDate: _customStartDate,
        customEndDate: _customEndDate,
        onTimeSpanSelected: (timeSpan, startDate, endDate) {
          setState(() {
            _selectedTimeSpan = timeSpan;
            _customStartDate = startDate;
            _customEndDate = endDate;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  String _getTimeSpanLabel() {
    switch (_selectedTimeSpan) {
      case TimeSpan.today:
        return 'Today';
      case TimeSpan.yesterday:
        return 'Yesterday';
      case TimeSpan.last7Days:
        return 'Last 7 Days';
      case TimeSpan.last30Days:
        return 'Last 30 Days';
      case TimeSpan.thisMonth:
        return 'This Month';
      case TimeSpan.lastMonth:
        return 'Last Month';
      case TimeSpan.last3Months:
        return 'Last 3 Months';
      case TimeSpan.last6Months:
        return 'Last 6 Months';
      case TimeSpan.thisYear:
        return 'This Year';
      case TimeSpan.allTime:
        return 'All Time';
      case TimeSpan.custom:
        return 'Custom Range';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header with filters — replaced by a selection toolbar while
          // picking sales to merge.
          if (_selectionMode)
            _buildSelectionBar()
          else
          Container(
            padding: EdgeInsets.all(_isDesktop ? 24 : 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Time period selector
                    Expanded(
                      child: InkWell(
                        onTap: _showTimeSpanPicker,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                _getTimeSpanLabel(),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              const Icon(Icons.keyboard_arrow_down, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Settings menu
                    PopupMenuButton<String>(
                      icon: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.more_vert),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) {
                        if (value == 'mode') {
                          setState(() {
                            _useStreamMode = !_useStreamMode;
                          });
                        } else if (value == 'refresh') {
                          _refreshSales();
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'mode',
                          child: Row(
                            children: [
                              Icon(
                                _useStreamMode ? Icons.stream : Icons.cached,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(_useStreamMode ? 'Real-time Mode' : 'Cached Mode'),
                              const Spacer(),
                              Icon(
                                _useStreamMode ? Icons.check : null,
                                size: 16,
                                color: Colors.green,
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'refresh',
                          child: Row(
                            children: [
                              const Icon(Icons.refresh, size: 20),
                              const SizedBox(width: 12),
                              const Text('Refresh'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Search bar
                TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search products or buyer name...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: const Text('Credit due'),
                    avatar: Icon(
                      Icons.schedule,
                      size: 18,
                      color: _creditDueOnly ? Colors.white : Colors.red.shade700,
                    ),
                    selected: _creditDueOnly,
                    selectedColor: Colors.red.shade600,
                    labelStyle: TextStyle(
                      color: _creditDueOnly ? Colors.white : null,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (value) {
                      setState(() => _creditDueOnly = value);
                    },
                  ),
                ),
              ],
            ),
          ),

          // Sales grid
          Expanded(
            child: _useStreamMode ? _buildStreamView() : _buildCachedView(),
          ),
        ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RecordSaleScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Record Sale'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildSelectionBar() {
    final selectedCount = _selectedSaleIds.length;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _isDesktop ? 24 : 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: _exitSelectionMode,
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
            ),
            Text(
              selectedCount == 0
                  ? 'Select sales to merge'
                  : '$selectedCount selected',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: selectedCount >= 2 ? _confirmMergeSelected : null,
              icon: const Icon(Icons.call_merge, size: 18),
              label: const Text('Merge'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamView() {
    return StreamBuilder<List<Sale>>(
      stream: _salesService.getSalesStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var filteredSales = _filterSalesByDateRange(snapshot.data ?? []);
        filteredSales = _filterSalesBySearch(filteredSales);
        filteredSales = _filterSalesByCreditDue(filteredSales);
        return _buildSalesContent(filteredSales);
      },
    );
  }

  Widget _buildCachedView() {
    return FutureBuilder<List<Sale>>(
      future: _salesService.getCachedSales(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var filteredSales = _filterSalesByDateRange(snapshot.data ?? []);
        filteredSales = _filterSalesBySearch(filteredSales);
        filteredSales = _filterSalesByCreditDue(filteredSales);
        return _buildSalesContent(filteredSales);
      },
    );
  }

  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEEE, d MMM yyyy').format(that);
  }

  /// Groups sales by calendar day. Relies on [sales] already being sorted
  /// newest-first — a plain [Map] preserves insertion order, so grouping in
  /// a single pass keeps day sections in the same newest-first order.
  Map<String, List<Sale>> _groupSalesByDay(List<Sale> sales) {
    final grouped = <String, List<Sale>>{};
    for (final sale in sales) {
      grouped.putIfAbsent(_dayLabel(sale.createdAt), () => []).add(sale);
    }
    return grouped;
  }

  Widget _buildSalesContent(List<Sale> sales) {
    _lastLoadedSales = sales;
    if (sales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isNotEmpty
                  ? Icons.search_off
                  : Icons.receipt_long_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No sales found for "$_searchQuery"'
                  : 'No sales yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            if (_searchQuery.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Try searching for a different product',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ] else if (!kIsWeb) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecordSaleScreen()),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Record First Sale'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Mock sales stay in the list (badged) but must not skew the summary
    // totals, so compute stats from real sales only.
    final stats =
        _calculateDetailedStats(sales.where((s) => !s.isMock).toList());
    final crossAxisCount = _getCrossAxisCount(context);
    final spacing = _getGridSpacing(context);
    final aspectRatio = _getChildAspectRatio(context);
    final groupedByDay = _groupSalesByDay(sales);

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Summary Card
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(spacing),
            child: _SummaryCard(stats: stats),
          ),
        ),

        // One day-header + grid per calendar day, newest day first.
        for (final entry in groupedByDay.entries) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(spacing, 0, spacing, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  const SizedBox(width: 10),
                  Text(
                    '${entry.value.length} sale${entry.value.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: spacing),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: aspectRatio,
              ),
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final sale = entry.value[index];
                  return _SaleCard(
                    sale: sale,
                    selectionMode: _selectionMode,
                    selected: _selectedSaleIds.contains(sale.id),
                    onTap: () {
                      if (_selectionMode) {
                        _toggleSelection(sale);
                      } else {
                        _showSaleDetails(sale);
                      }
                    },
                    onLongPress: () {
                      if (_selectionMode) {
                        _toggleSelection(sale);
                      } else {
                        _enterSelectionMode(sale);
                      }
                    },
                    onEdit: () => _editSale(sale),
                    onDelete: () => _deleteSale(sale),
                    onReturn: () => _returnItems(sale),
                    onPrint: () => _showPrintOptions(sale),
                    onRecordPayment: () => _recordPayment(sale),
                  );
                },
                childCount: entry.value.length,
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: spacing)),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}

// ==========================================
// SUMMARY CARD - Single comprehensive card
// ==========================================
class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _SummaryCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1200;
    final isTablet = MediaQuery.of(context).size.width >= 768;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(isDesktop ? 28 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.analytics_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sales Summary',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Overview of your performance',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Stats Grid
              if (isDesktop || isTablet)
              // Desktop/Tablet: 4 columns
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        icon: Icons.receipt_long,
                        label: 'Total Sales',
                        value: '${stats['totalSales']}',
                        iconColor: Colors.orange.shade300,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _StatItem(
                        icon: Icons.currency_rupee,
                        label: 'Revenue',
                        value: '₹${stats['totalRevenue'].toStringAsFixed(0)}',
                        iconColor: Colors.green.shade300,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _StatItem(
                        icon: Icons.trending_up,
                        label: 'Profit',
                        value: '₹${stats['totalProfit'].toStringAsFixed(0)}',
                        subtitle: '${stats['profitPercentage'].toStringAsFixed(1)}% margin',
                        iconColor: Colors.purple.shade300,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _StatItem(
                        icon: Icons.shopping_bag,
                        label: 'Items Sold',
                        value: '${stats['itemsSold']}',
                        iconColor: Colors.pink.shade300,
                      ),
                    ),
                  ],
                )
              else
              // Mobile: 2x2 grid
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _StatItem(
                            icon: Icons.receipt_long,
                            label: 'Total Sales',
                            value: '${stats['totalSales']}',
                            iconColor: Colors.orange.shade300,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _StatItem(
                            icon: Icons.currency_rupee,
                            label: 'Revenue',
                            value: '₹${stats['totalRevenue'].toStringAsFixed(0)}',
                            iconColor: Colors.green.shade300,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _StatItem(
                            icon: Icons.trending_up,
                            label: 'Profit',
                            value: '₹${stats['totalProfit'].toStringAsFixed(0)}',
                            subtitle: '${stats['profitPercentage'].toStringAsFixed(1)}%',
                            iconColor: Colors.purple.shade300,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _StatItem(
                            icon: Icons.shopping_bag,
                            label: 'Items Sold',
                            value: '${stats['itemsSold']}',
                            iconColor: Colors.pink.shade300,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Individual stat item
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color iconColor;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
              Column(children: [Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],],)
            ],
          ),


        ],
      ),
    );
  }
}

// ==========================================
// SALE CARD - Grid item
// ==========================================
class _SaleCard extends StatelessWidget {
  final Sale sale;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onReturn;
  final VoidCallback onPrint;
  final VoidCallback onRecordPayment;
  final bool selectionMode;
  final bool selected;

  const _SaleCard({
    required this.sale,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onReturn,
    required this.onEdit,
    required this.onPrint,
    required this.onRecordPayment,
    this.selectionMode = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = sale.items.fold(0, (sum, item) => sum + item.quantity);

    return Card(
      elevation: selected ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? const BorderSide(color: Colors.blue, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with amount and actions
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '₹${sale.totalAmount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$itemCount item${itemCount != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        if (sale.buyerName?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.person_outline,
                                  size: 12, color: Colors.grey[600]),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  sale.buyerName!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[700],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (sale.isMock) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border:
                                  Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.science_outlined,
                                    size: 11, color: Colors.orange.shade800),
                                const SizedBox(width: 3),
                                Text(
                                  'MOCK',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Action buttons — swapped for a selection indicator while
                  // picking sales to merge.
                  if (selectionMode)
                    Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? Colors.blue : Colors.grey.shade400,
                      size: 24,
                    )
                  else
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'print',
                        child: Row(
                          children: [
                            Icon(Icons.print, size: 18, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Print Invoice', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      if (sale.isCredit && !sale.isFullyPaid)
                        const PopupMenuItem(
                          value: 'recordPayment',
                          child: Row(
                            children: [
                              Icon(Icons.payments_outlined, size: 18, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Record Payment', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit Sales', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'return',
                        child: Row(
                          children: [
                            Icon(Icons.keyboard_return, size: 18),
                            SizedBox(width: 8),
                            Text('Return Items', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete Sale', style: TextStyle(color: Colors.red, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'print') {
                        onPrint();
                      } else if (value == 'return') {
                        onReturn();
                      } else if (value == 'delete') {
                        onDelete();
                      } else if (value == 'edit') {
                        onEdit();
                      } else if (value == 'recordPayment') {
                        onRecordPayment();
                      }
                    },
                  ),
                ],
              ),

              const Spacer(),

              // Footer with date and payment
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.access_time, size: 11, color: Colors.grey[600]),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      DateFormat('MMM dd, hh:mm a').format(sale.createdAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),

              if (sale.paymentMethod != null) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _PaymentBadge(method: sale.paymentMethod!.label),
                    if (sale.isCredit && !sale.isFullyPaid)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          'Due ₹${sale.amountDue.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Payment Method Badge
class _PaymentBadge extends StatelessWidget {
  final String method;

  const _PaymentBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    MaterialColor color;

    switch (method.toLowerCase()) {
      case 'cash':
        icon = Icons.money;
        color = Colors.green;
        break;
      case 'upi':
        icon = Icons.qr_code;
        color = Colors.purple;
        break;
      case 'card':
        icon = Icons.credit_card;
        color = Colors.blue;
        break;
      case 'credit':
        icon = Icons.schedule;
        color = Colors.deepOrange;
        break;
      default:
        icon = Icons.payment;
        color = Colors.blueGrey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.shade700,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            method.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// Time Span Picker Bottom Sheet
class _TimeSpanPickerBottomSheet extends StatelessWidget {
  final TimeSpan selectedTimeSpan;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final Function(TimeSpan, DateTime?, DateTime?) onTimeSpanSelected;

  const _TimeSpanPickerBottomSheet({
    required this.selectedTimeSpan,
    required this.customStartDate,
    required this.customEndDate,
    required this.onTimeSpanSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Text(
                  'Select Time Period',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              shrinkWrap: true,
              children: [
                _buildTimeSpanTile(context, TimeSpan.today, 'Today'),
                _buildTimeSpanTile(context, TimeSpan.yesterday, 'Yesterday'),
                _buildTimeSpanTile(context, TimeSpan.last7Days, 'Last 7 Days'),
                _buildTimeSpanTile(context, TimeSpan.last30Days, 'Last 30 Days'),
                _buildTimeSpanTile(context, TimeSpan.thisMonth, 'This Month'),
                _buildTimeSpanTile(context, TimeSpan.lastMonth, 'Last Month'),
                _buildTimeSpanTile(context, TimeSpan.last3Months, 'Last 3 Months'),
                _buildTimeSpanTile(context, TimeSpan.thisYear, 'This Year'),
                _buildTimeSpanTile(context, TimeSpan.allTime, 'All Time'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSpanTile(BuildContext context, TimeSpan span, String label) {
    final isSelected = selectedTimeSpan == span;
    return ListTile(
      title: Text(label),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
      selected: isSelected,
      onTap: () => onTimeSpanSelected(span, null, null),
    );
  }
}

// Sale Details Dialog
class _SaleDetailsDialog extends StatefulWidget {
  final Sale sale;

  const _SaleDetailsDialog({required this.sale});

  @override
  State<_SaleDetailsDialog> createState() => _SaleDetailsDialogState();
}

class _SaleDetailsDialogState extends State<_SaleDetailsDialog> {
  bool _showProfitDetails = false;

  Sale get sale => widget.sale;

  double _calculateItemProfit(item) {
    return (item.salePrice - item.purchasePrice) * item.quantity;
  }

  double _calculateTotalProfit() {
    return sale.items.fold(0.0, (sum, item) {
      return sum + _calculateItemProfit(item);
    });
  }

  double _calculateTotalCost() {
    return sale.items.fold(0.0, (sum, item) {
      return sum + item.purchasePrice * item.quantity;
    });
  }

  DateTime _dayOf(SaleItem item) {
    final d = item.effectiveDate(sale);
    return DateTime(d.year, d.month, d.day);
  }

  /// True once this sale has items from more than one calendar day, i.e.
  /// it was produced by "Merge Sales" rather than a single checkout.
  bool get _isMerged =>
      sale.items.map(_dayOf).toSet().length > 1;

  /// Items grouped by day, oldest first, for a merged sale's detail view.
  List<MapEntry<DateTime, List<SaleItem>>> _groupedItems() {
    final groups = <DateTime, List<SaleItem>>{};
    for (final item in sale.items) {
      groups.putIfAbsent(_dayOf(item), () => []).add(item);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final totalProfit = _calculateTotalProfit();
    final totalCost = _calculateTotalCost();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fixed Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  const Text(
                    'Sale Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((sale.buyerName?.isNotEmpty ?? false) ||
                        (sale.buyerPhone?.isNotEmpty ?? false)) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BUYER',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (sale.buyerName?.isNotEmpty ?? false)
                              Text(sale.buyerName!,
                                  style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w600)),
                            if (sale.buyerPhone?.isNotEmpty ?? false)
                              Text(sale.buyerPhone!, style: const TextStyle(fontSize: 13)),
                            if (sale.buyerAddress?.isNotEmpty ?? false)
                              Text(sale.buyerAddress!, style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                    if (sale.isCredit) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: sale.isFullyPaid
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: sale.isFullyPaid
                                ? Colors.green.shade100
                                : Colors.red.shade100,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Amount Paid: ₹${sale.amountPaid.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              sale.isFullyPaid
                                  ? 'Fully Paid'
                                  : 'Due: ₹${sale.amountDue.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: sale.isFullyPaid
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (sale.notes?.isNotEmpty ?? false) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NOTES',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(sale.notes!, style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                    for (final group in _groupedItems()) ...[
                      if (_isMerged)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 12, color: Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat('EEEE, d MMM yyyy').format(group.key),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ...group.value.map((item) {
                      final itemProfit = _calculateItemProfit(item);
                      final itemTotal = item.quantity * item.salePrice;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.productName} (${item.productSize})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '₹${itemTotal.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    '${item.quantity} × ₹${item.salePrice.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              if (_showProfitDetails) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: itemProfit >= 0
                                        ? Colors.green.shade50
                                        : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: itemProfit >= 0
                                          ? Colors.green.shade200
                                          : Colors.red.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        itemProfit >= 0
                                            ? Icons.trending_up
                                            : Icons.trending_down,
                                        size: 12,
                                        color: itemProfit >= 0
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Profit: ₹${itemProfit.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: itemProfit >= 0
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                    ],
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '₹${sale.totalAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_showProfitDetails) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                totalProfit >= 0
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                size: 18,
                                color: totalProfit >= 0
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Total Profit',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: totalProfit >= 0
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '₹${totalProfit.toStringAsFixed(0)} (${totalCost > 0 ? (totalProfit / totalCost * 100).toStringAsFixed(1) : '0.0'}%)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: totalProfit >= 0
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _showProfitDetails = false),
                          icon: const Icon(Icons.visibility_off, size: 16),
                          label: const Text('Hide'),
                        ),
                      ),
                    ] else
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _showProfitDetails = true),
                          icon: const Icon(Icons.expand_more, size: 18),
                          label: const Text('See More'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}