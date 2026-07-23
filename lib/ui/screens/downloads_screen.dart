import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/product_model.dart';
import '../../services/firebase_service.dart';

class PrintPriceListScreen extends StatefulWidget {
  const PrintPriceListScreen({super.key});

  @override
  State<PrintPriceListScreen> createState() => _PrintPriceListScreenState();
}

class _PrintPriceListScreenState extends State<PrintPriceListScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  List<Product> _allProducts = [];
  List<String> _categories = [];
  Set<String> _selectedProductIds = {};
  String? _selectedCategory;
  bool _isLoading = true;
  bool _selectAll = false;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _allProducts = await _firebaseService.getCachedProducts();
      _categories = await _firebaseService.getCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Product> get _filteredProducts {
    if (_selectedCategory == null) {
      return _allProducts;
    }
    return _allProducts
        .where((p) => p.category.toLowerCase() == _selectedCategory!.toLowerCase())
        .toList();
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedProductIds = _filteredProducts.map((p) => p.id).toSet();
      } else {
        _selectedProductIds.clear();
      }
    });
  }

  void _selectCategory(String? category) {
    setState(() {
      _selectedCategory = category;
      if (category != null) {
        // Select all products in this category
        final categoryProducts = _allProducts
            .where((p) => p.category.toLowerCase() == category.toLowerCase())
            .map((p) => p.id)
            .toSet();
        _selectedProductIds.addAll(categoryProducts);
      }
    });
  }

  Future<void> _printPriceList() async {
    if (_selectedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product')),
      );
      return;
    }

    final selectedProducts = _allProducts
        .where((p) => _selectedProductIds.contains(p.id))
        .toList();

    // Warn if too many products
    if (selectedProducts.length > 200) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Too Many Products'),
          content: Text(
            'You have selected ${selectedProducts.length} products.\n\n'
            'PDFs are limited to 200 products to prevent errors.\n\n'
            'Recommendation: Filter by category for better results.\n\n'
            'Continue with first 200 products?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (shouldContinue != true) return;
    }

    setState(() => _isPrinting = true);

    try {

      // Generate PDF
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          final pdf = await _generatePdf(selectedProducts, format);
          return pdf.save();
        },
        name: 'products_pricelist_${DateTime.now().toIso8601String()}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Print dialog opened'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error printing: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  Future<pw.Document> _generatePdf(List<Product> products, PdfPageFormat format) async {
    final pdf = pw.Document();

    if (products.isEmpty) {
      throw Exception('No products to print');
    }

    // Limit to prevent too many pages
    const int maxProductsPerPdf = 200;
    final limitedProducts = products.length > maxProductsPerPdf
        ? products.sublist(0, maxProductsPerPdf)
        : products;

    if (products.length > maxProductsPerPdf) {
      // Show warning but continue
      print('Warning: Limiting to first $maxProductsPerPdf products');
    }

    // Group products by category for better organization
    final productsByCategory = <String, List<Product>>{};
    for (final product in limitedProducts) {
      productsByCategory.putIfAbsent(product.category, () => []).add(product);
    }

    final categories = productsByCategory.keys.toList()..sort();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(32),
        maxPages: 100, // Prevent too many pages
        build: (context) => [
          // Header
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
                  'Generated on: ${DateTime.now().toString().split('.')[0]}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
                pw.Text(
                  products.length > maxProductsPerPdf
                      ? 'Showing $maxProductsPerPdf of ${products.length} products (limited for PDF size)'
                      : 'Total Products: ${limitedProducts.length}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 16),
                pw.Divider(thickness: 2),
              ],
            ),
          ),

          // Products by category
          ...categories.map((category) {
            final categoryProducts = productsByCategory[category]!;
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 16),
                pw.Text(
                  category.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800,
                  ),
                ),
                pw.SizedBox(height: 8),

                // Table for products
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(2),
                    2: const pw.FlexColumnWidth(1.5),
                    3: const pw.FlexColumnWidth(1.5),
                    4: const pw.FlexColumnWidth(1),
                    5: const pw.FlexColumnWidth(1.5),
                    6: const pw.FlexColumnWidth(1.5),
                  },
                  children: [
                    // Header row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _buildTableCell('Product Name', isHeader: true),
                        _buildTableCell('Size', isHeader: true),
                        _buildTableCell('Purchase\nPrice', isHeader: true),
                        _buildTableCell('Sale\nPrice', isHeader: true),
                        _buildTableCell('Stock', isHeader: true),
                        _buildTableCell('Disc.\nReceived', isHeader: true),
                        _buildTableCell('Selling\nDisc.', isHeader: true),
                      ],
                    ),

                    // Data rows
                    ...categoryProducts.map((product) {
                      return pw.TableRow(
                        children: [
                          _buildTableCell(product.name),
                          _buildTableCell(product.size),
                          _buildTableCell('Rs.${product.purchasePrice.toStringAsFixed(2)}'),
                          _buildTableCell('Rs.${product.salePrice.toStringAsFixed(2)}'),
                          _buildTableCell(product.stock.toString()),
                          _buildTableCell(
                            product.discountReceived != null
                                ? '${product.discountReceived!.toStringAsFixed(1)}%'
                                : '-',
                          ),
                          _buildTableCell(
                            product.sellingDiscount != null
                                ? '${product.sellingDiscount!.toStringAsFixed(1)}%'
                                : '-',
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ],
            );
          }),

          // Footer with totals
          pw.SizedBox(height: 24),
          pw.Divider(thickness: 2),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Products in this report: ${limitedProducts.length}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Total Stock: ${limitedProducts.fold<int>(0, (sum, p) => sum + p.stock)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          if (products.length > maxProductsPerPdf)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'Note: Only first $maxProductsPerPdf products shown. Please filter by category for complete lists.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.red),
              ),
            ),
        ],
      ),
    );

    return pdf;
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 9 : 8,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: isHeader ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Print Price List'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filters and actions
                Container(
                  padding: const EdgeInsets.all(16),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category filter
                      const Text(
                        'Filter by Category',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('All'),
                            selected: _selectedCategory == null,
                            onSelected: (_) {
                              setState(() => _selectedCategory = null);
                            },
                          ),
                          ..._categories.map((category) {
                            return FilterChip(
                              label: Text(category.toUpperCase()),
                              selected: _selectedCategory == category,
                              onSelected: (_) => _selectCategory(category),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Selection info and actions
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_selectedProductIds.length} of ${_filteredProducts.length} products selected',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _toggleSelectAll,
                            icon: Icon(
                              _selectAll ? Icons.deselect : Icons.select_all,
                              size: 18,
                            ),
                            label: Text(_selectAll ? 'Deselect All' : 'Select All'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Products list
                Expanded(
                  child: _filteredProducts.isEmpty
                      ? const Center(
                          child: Text('No products found'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            final isSelected = _selectedProductIds.contains(product.id);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: CheckboxListTile(
                                value: isSelected,
                                onChanged: (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _selectedProductIds.add(product.id);
                                    } else {
                                      _selectedProductIds.remove(product.id);
                                    }
                                    // Update select all state
                                    _selectAll = _selectedProductIds.length == _filteredProducts.length;
                                  });
                                },
                                title: Text(
                                  product.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(product.size),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            product.category.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.blue.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Sale: ₹${product.salePrice}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Stock: ${product.stock}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Print button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isPrinting ? null : _printPriceList,
                        icon: _isPrinting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.print),
                        label: Text(
                          _isPrinting ? 'Opening Print...' : 'Print Price List',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
