import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/product_model.dart';
import '../../services/firebase_service.dart';

class BulkPriceUpdateScreen extends StatefulWidget {
  const BulkPriceUpdateScreen({super.key});

  @override
  State<BulkPriceUpdateScreen> createState() => _BulkPriceUpdateScreenState();
}

class _BulkPriceUpdateScreenState extends State<BulkPriceUpdateScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _searchController = TextEditingController();

  List<Product> _allProducts = [];
  List<String> _categories = [];
  String? _selectedCategory;
  bool _isLoading = true;
  bool _isSaving = false;
  String _searchQuery = '';

  // Track edited selling discounts
  Map<String, double?> _editedSellingDiscounts = {};
  Set<String> _modifiedProductIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
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
    var products = _allProducts;

    // Filter by category
    if (_selectedCategory != null) {
      products = products
          .where((p) => p.category.toLowerCase() == _selectedCategory!.toLowerCase())
          .toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      products = products.where((product) {
        final name = product.name.toLowerCase();
        final size = product.size.toLowerCase();
        return name.contains(_searchQuery) || size.contains(_searchQuery);
      }).toList();
    }

    return products;
  }

  double _calculateNewSalePrice(Product product, double? newSellingDiscount) {
    final sellingDiscount = newSellingDiscount ?? 0;

    // Base price is purchase price adjusted by discount received
    final discountReceived = product.discountReceived ?? 0;

    final basePriceAfterDiscount = product.purchasePrice * (1 - discountReceived / 100);

    // Apply selling discount
    final newSalePrice = basePriceAfterDiscount * (1 + sellingDiscount / 100);

    return newSalePrice;
  }

  Future<void> _saveChanges() async {
    if (_modifiedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No changes to save')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      for (final productId in _modifiedProductIds) {
        final product = _allProducts.firstWhere(
          (p) => p.id == productId,
          orElse: () => throw Exception('Product not found: $productId'),
        );
        final newSellingDiscount = _editedSellingDiscounts[productId];
        final newSalePrice = _calculateNewSalePrice(product, newSellingDiscount);

        // Update product
        final updatedProduct = product.copyWith(
          sellingDiscount: newSellingDiscount,
          salePrice: newSalePrice,
        );

        await _firebaseService.updateProduct(updatedProduct);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated ${_modifiedProductIds.length} products successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Reload data
        _editedSellingDiscounts.clear();
        _modifiedProductIds.clear();
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving changes: $e'),
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

  void _applyBulkDiscountToCategory(String category) {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text('Bulk Update - ${category.toUpperCase()}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter new selling discount (%) for all products in this category:'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: 'Selling Discount (%)',
                  hintText: 'e.g., 10 or -5',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  helperText: 'Positive for markup, negative for discount',
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
                final discountText = controller.text.trim();
                if (discountText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a value')),
                  );
                  return;
                }

                final discount = double.tryParse(discountText);
                if (discount == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid number')),
                  );
                  return;
                }

                Navigator.pop(context);

                // Apply to all products in category
                setState(() {
                  final categoryProducts = _allProducts.where(
                    (p) => p.category.toLowerCase() == category.toLowerCase(),
                  );

                  for (final product in categoryProducts) {
                    _editedSellingDiscounts[product.id] = discount;
                    _modifiedProductIds.add(product.id);
                  }
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Applied ${discount.toStringAsFixed(1)}% to ${category.toUpperCase()} category'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Bulk Price Update'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_modifiedProductIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_modifiedProductIds.length} modified',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search and filters
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
                      // Search bar
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search products...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Category filter
                      const Text(
                        'Filter by Category',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(category.toUpperCase()),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    onTap: () => _applyBulkDiscountToCategory(category),
                                    child: Icon(
                                      Icons.edit,
                                      size: 14,
                                      color: _selectedCategory == category
                                          ? Colors.white
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              selected: _selectedCategory == category,
                              onSelected: (_) {
                                setState(() {
                                  _selectedCategory = _selectedCategory == category
                                      ? null
                                      : category;
                                });
                              },
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tip: Click the edit icon on a category to apply bulk discount',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
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
                            final isModified = _modifiedProductIds.contains(product.id);
                            final currentSellingDiscount = _editedSellingDiscounts[product.id] ??
                                product.sellingDiscount;
                            final newSalePrice = isModified
                                ? _calculateNewSalePrice(product, currentSellingDiscount)
                                : product.salePrice;

                            return _ProductUpdateCard(
                              product: product,
                              sellingDiscount: currentSellingDiscount,
                              newSalePrice: newSalePrice,
                              isModified: isModified,
                              onSellingDiscountChanged: (value) {
                                setState(() {
                                  _editedSellingDiscounts[product.id] = value;
                                  if (value != product.sellingDiscount) {
                                    _modifiedProductIds.add(product.id);
                                  } else {
                                    _modifiedProductIds.remove(product.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),

                // Save button
                if (_modifiedProductIds.isNotEmpty)
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
                          onPressed: _isSaving ? null : _saveChanges,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            _isSaving
                                ? 'Saving...'
                                : 'Save ${_modifiedProductIds.length} Changes',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.green,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _ProductUpdateCard extends StatefulWidget {
  final Product product;
  final double? sellingDiscount;
  final double newSalePrice;
  final bool isModified;
  final Function(double?) onSellingDiscountChanged;

  const _ProductUpdateCard({
    required this.product,
    required this.sellingDiscount,
    required this.newSalePrice,
    required this.isModified,
    required this.onSellingDiscountChanged,
  });

  @override
  State<_ProductUpdateCard> createState() => _ProductUpdateCardState();
}

class _ProductUpdateCardState extends State<_ProductUpdateCard> {
  late TextEditingController _discountController;

  @override
  void initState() {
    super.initState();
    _discountController = TextEditingController(
      text: widget.sellingDiscount?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(_ProductUpdateCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sellingDiscount != widget.sellingDiscount) {
      _discountController.text = widget.sellingDiscount?.toString() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDiscountReceived = widget.product.discountReceived != null;
    final priceChange = widget.newSalePrice - widget.product.salePrice;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: widget.isModified ? Colors.orange.shade300 : Colors.grey.shade300,
          width: widget.isModified ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product name and category - single line
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.product.name} - ${widget.product.size}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    widget.product.category.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.isModified) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 14, color: Colors.orange.shade700),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Compact info row - all in one line
            Row(
              children: [
                // Purchase & Discount info
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Purchase: ₹${widget.product.purchasePrice.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        if (hasDiscountReceived)
                          Text(
                            'Disc Received: ${widget.product.discountReceived!.toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 9, color: Colors.green[700]),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Selling discount input
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _discountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: 'Markup %',
                      labelStyle: const TextStyle(fontSize: 10),
                      hintText: '0',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    onChanged: (value) {
                      widget.onSellingDiscountChanged(
                        value.isEmpty ? null : double.tryParse(value),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 6),

                // New sale price
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: widget.isModified
                          ? Colors.orange.shade50
                          : Colors.green.shade50,
                      border: Border.all(
                        color: widget.isModified
                            ? Colors.orange.shade300
                            : Colors.green.shade300,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Sale Price',
                          style: TextStyle(fontSize: 9, color: Colors.grey[700]),
                        ),
                        Text(
                          '₹${widget.newSalePrice.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: widget.isModified
                                ? Colors.orange.shade700
                                : Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Change indicator - only if modified
            if (widget.isModified) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: priceChange >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      priceChange >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 12,
                      color: priceChange >= 0 ? Colors.green[700] : Colors.red[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Was ₹${widget.product.salePrice.toStringAsFixed(0)} → Change: ₹${priceChange.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: priceChange >= 0 ? Colors.green[700] : Colors.red[700],
                        fontWeight: FontWeight.w600,
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
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }
}
