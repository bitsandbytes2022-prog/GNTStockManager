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

class BillPreviewScreen extends StatefulWidget {
  final Map<String, Product> products;
  final Map<String, int> quantities;
  final Map<String, double> prices;
  final String paymentMethod;
  final String? notes;

  /// productId -> sold-by-length (pipes cut to feet). Quantity for these
  /// products is feet, not units, and stock is never deducted for them.
  final Map<String, bool> perFootItems;

  /// When true, completing from this preview records a mock sale (no stock
  /// deduction, excluded from analytics).
  final bool isMock;

  const BillPreviewScreen({
    super.key,
    required this.products,
    required this.quantities,
    required this.prices,
    required this.paymentMethod,
    this.notes,
    this.perFootItems = const {},
    this.isMock = false,
  });

  @override
  State<BillPreviewScreen> createState() => _BillPreviewScreenState();
}

class _BillPreviewScreenState extends State<BillPreviewScreen> {
  final GlobalKey _billKey = GlobalKey();
  final InvoiceService _invoiceService = InvoiceService();
  final SalesService _salesService = SalesService();

  int? _invoiceNumber;
  bool _isLoading = true;
  bool _isSaving = false;
  Uint8List? _logoBytes;

  @override
  void initState() {
    super.initState();
    _initialize();
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
    return widget.products.entries.fold(0.0, (sum, entry) {
      final productId = entry.key;
      final qty = widget.quantities[productId] ?? 0;
      final price = widget.prices[productId] ?? 0;
      return sum + (qty * price);
    });
  }

  double _calculateTotalProfit() {
    return widget.products.entries.fold(0.0, (sum, entry) {
      final productId = entry.key;
      final product = entry.value;
      final qty = widget.quantities[productId] ?? 0;
      final salePrice = widget.prices[productId] ?? 0;
      final profit = (salePrice - product.purchasePrice) * qty;
      return sum + profit;
    });
  }

  Future<void> _completeSale() async {
    setState(() => _isSaving = true);

    try {
      // Get the actual next invoice number (this will increment the counter)
      final invoiceNumber = await _invoiceService.getNextInvoiceNumber();

      // Create sale items
      final saleItems = widget.products.entries.map((entry) {
        final product = entry.value;
        final qty = widget.quantities[product.id]!;
        final price = widget.prices[product.id]!;

        return SaleItem(
          productId: product.id,
          productName: product.name,
          productSize: product.size,
          quantity: qty,
          salePrice: price,
          purchasePrice: product.purchasePrice,
          isPerFoot: widget.perFootItems[product.id] ?? false,
        );
      }).toList();

      // Create sale with invoice number
      final sale = Sale(
        id: '',
        items: saleItems,
        totalAmount: _calculateSubtotal(),
        createdAt: DateTime.now(),
        paymentMethod: PaymentMethod.values.firstWhere(
              (e) => e.value == widget.paymentMethod,
          orElse: () => PaymentMethod.cash,
        ),
        notes: widget.notes,
        invoiceNumber: invoiceNumber, // Add invoice number to sale
        isMock: widget.isMock,
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

  Future<void> _printBill() async {
    try {
      final pdf = await _generatePdf();
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing: $e')),
        );
      }
    }
  }

  Future<pw.Document> _generatePdf() async {
    final pdf = pw.Document();

    pw.ImageProvider? logoImage;
    if (_logoBytes != null) {
      try {
        logoImage = pw.MemoryImage(_logoBytes!);
      } catch (e) {
        debugPrint('Error loading logo for PDF: $e');
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header with logo and shop details
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      width: 60,
                      height: 60,
                      child: pw.Image(logoImage),
                    ),
                  if (logoImage != null) pw.SizedBox(width: 16),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Guru Nanak Traders',
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Mobile: 7696379802',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          'Nandpur, Teh. Amb, Distt. Una (H.P.)',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          'Deals in: All type of hardware, Sanitary & Paints etc.',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.Expanded(
                    flex: 1,
                    child:   pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Estimate',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                      pw.Text(
                        'Time: ${DateFormat('hh:mm a').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),)


                ],
              ),

              pw.Divider(thickness: 2),
              pw.SizedBox(height: 12),



              // Items table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  // Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _buildTableCell('Item', bold: true),
                      _buildTableCell('Qty', bold: true),
                      _buildTableCell('Rate', bold: true),
                      _buildTableCell('Amount', bold: true),
                    ],
                  ),
                  // Items
                  ...widget.products.entries.map((entry) {
                    final product = entry.value;
                    final qty = widget.quantities[product.id]!;
                    final price = widget.prices[product.id]!;
                    final amount = qty * price;
                    final isPerFoot = widget.perFootItems[product.id] ?? false;

                    return pw.TableRow(
                      children: [
                        _buildTableCell('${product.name} (${product.size})'),
                        _buildTableCell(isPerFoot ? '$qty ft' : qty.toString()),
                        _buildTableCell('INR ${price.toStringAsFixed(2)}'),
                        _buildTableCell('INR ${amount.toStringAsFixed(2)}'),
                      ],
                    );
                  }).toList(),
                ],
              ),

              pw.SizedBox(height: 16),

              // Totals
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 200,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      color: PdfColors.grey200,
                    ),
                    child: pw.Column(
                      children: [
                        // _buildTotalRow('Subtotal:', _calculateSubtotal()),
                        _buildTotalRow('Total:', _calculateSubtotal(), bold: true),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 12),

              // Payment method
              pw.Text(
                'Payment Method: ${widget.paymentMethod}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),

              if (widget.notes != null && widget.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text('Notes: ${widget.notes}'),
              ],

              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.Center(
                child: pw.Text(
                  'Thank you for your business!',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
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

  pw.Widget _buildTotalRow(String label, double amount, {bool bold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: bold ? 12 : 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          'INR ${amount.toStringAsFixed(2)}',
          style: pw.TextStyle(
            fontSize: bold ? 12 : 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
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
                ...widget.products.entries.map((entry) {
                  return _buildItemRow(entry.value);
                }).toList(),
              ],
            ),
          ),

          const Divider(height: 1),

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
                const SizedBox(height: 4),
                Text(
                  'Deals in: All type of hardware, Sanitary & Paints etc.',
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
                'ESTIMATE #: ${_invoiceNumber ?? 'N/A'}',
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

  Widget _buildItemRow(Product product) {
    final qty = widget.quantities[product.id]!;
    final price = widget.prices[product.id]!;
    final amount = qty * price;
    final isPerFoot = widget.perFootItems[product.id] ?? false;

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
              'INR ${price.toStringAsFixed(2)}',
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

  Widget _buildTotals(double subtotal, double profit) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal:', style: TextStyle(fontSize: 14)),
              Text(
                'INR ${subtotal.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            widget.paymentMethod == 'Cash'
                ? Icons.money
                : widget.paymentMethod == 'Card'
                ? Icons.credit_card
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
              onPressed: _isSaving ? null : _printBill,
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