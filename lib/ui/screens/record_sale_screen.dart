import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product_model.dart';
import '../../models/sale_model.dart';
import '../../services/firebase_service.dart';
import '../../services/sales_service.dart';

class RecordSaleScreen extends StatefulWidget {
  const RecordSaleScreen({super.key});

  @override
  State<RecordSaleScreen> createState() => _RecordSaleScreenState();
}

class _RecordSaleScreenState extends State<RecordSaleScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final SalesService _salesService = SalesService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  Map<String, int> _selectedQuantities = {}; // productId -> quantity
  Map<String, double> _customPrices = {}; // productId -> custom price
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchController.addListener(_filterProducts);
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      _allProducts = await _firebaseService.getCachedProducts();
      _filteredProducts = List.from(_allProducts);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading products: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterProducts() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();

      if (_searchQuery.isEmpty) {
        _filteredProducts = List.from(_allProducts);
      } else {
        final queryWords = _searchQuery.split(' ').where((w) => w.isNotEmpty);

        _filteredProducts = _allProducts.where((product) {
          final name = product.name.toLowerCase();
          final size = product.size.toLowerCase();

          return queryWords.every((word) => name.contains(word) || size.contains(word));
        }).toList();
      }
    });
  }

  void _toggleProduct(Product product) {
    setState(() {
      if (_selectedQuantities.containsKey(product.id)) {
        _selectedQuantities.remove(product.id);
        _customPrices.remove(product.id);
      } else {
        _selectedQuantities[product.id] = 1;
        _customPrices[product.id] = product.salePrice;
      }
    });
  }

  void _updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      setState(() {
        _selectedQuantities.remove(productId);
        _customPrices.remove(productId);
      });
    } else {
      setState(() {
        _selectedQuantities[productId] = quantity;
      });
    }
  }

  void _updatePrice(String productId, double price) {
    setState(() {
      _customPrices[productId] = price;
    });
  }

  double _getMinimumPrice(Product product) {
    return product.purchasePrice * 1.10;
  }

  double get _totalAmount {
    double total = 0;
    for (final entry in _selectedQuantities.entries) {
      final price = _customPrices[entry.key] ?? 0;
      total += price * entry.value;
    }
    return total;
  }

  List<Product> get _selectedProducts {
    return _allProducts
        .where((p) => _selectedQuantities.containsKey(p.id))
        .toList();
  }

  Future<void> _showBillPreview() async {
    if (_selectedQuantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product')),
      );
      return;
    }

    // Validate prices
    for (final product in _selectedProducts) {
      final currentPrice = _customPrices[product.id]!;
      final minPrice = _getMinimumPrice(product);

      if (currentPrice < minPrice) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${product.name}: Price must be at least ₹${minPrice.toStringAsFixed(2)} (Cost + 10%)',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    // Check stock availability
    for (final product in _selectedProducts) {
      final quantity = _selectedQuantities[product.id]!;
      if (quantity > product.stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${product.name} has insufficient stock (Available: ${product.stock})',
            ),
          ),
        );
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _BillPreviewDialog(
        products: _selectedProducts,
        quantities: _selectedQuantities,
        prices: _customPrices,
        totalAmount: _totalAmount,
        notes: _notesController.text,
      ),
    );

    if (confirmed == true) {
      await _saveSale();
    }
  }

  Future<void> _saveSale() async {
    setState(() => _isSaving = true);

    try {
      final saleItems = _selectedProducts.map((product) {
        return SaleItem(
          productId: product.id,
          productName: product.name,
          productSize: product.size,
          purchasePrice: product.purchasePrice,
          salePrice: _customPrices[product.id]!,
          quantity: _selectedQuantities[product.id]!,
          imageBase64: product.imageBase64, // Include product image
        );
      }).toList();

      final sale = Sale(
        id: '',
        items: saleItems,
        totalAmount: _totalAmount,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      await _salesService.createSale(sale);

      _firebaseService.clearCache();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sale recorded successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving sale: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Sale'),
        elevation: 0,
        actions: [
          if (_selectedQuantities.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear selection',
              onPressed: () {
                setState(() {
                  _selectedQuantities.clear();
                  _customPrices.clear();
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                )
                    : null,
              ),
            ),
          ),
          if (_selectedQuantities.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedQuantities.length} items selected',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Total: ₹${_totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                ? Center(
              child: Text(
                _searchQuery.isEmpty
                    ? 'No products available'
                    : 'No products found',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredProducts.length,
              itemBuilder: (context, index) {
                final product = _filteredProducts[index];
                final isSelected =
                _selectedQuantities.containsKey(product.id);
                final quantity = _selectedQuantities[product.id] ?? 1;
                final price =
                    _customPrices[product.id] ?? product.salePrice;

                return _ProductSelectionCard(
                  product: product,
                  isSelected: isSelected,
                  quantity: quantity,
                  price: price,
                  minimumPrice: _getMinimumPrice(product),
                  onToggle: () => _toggleProduct(product),
                  onQuantityChanged: (q) =>
                      _updateQuantity(product.id, q),
                  onPriceChanged: (p) => _updatePrice(product.id, p),
                );
              },
            ),
          ),
          if (_selectedQuantities.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () {
                          setState(() {
                            _selectedQuantities.clear();
                            _customPrices.clear();
                            _notesController.clear();
                          });
                        },
                        icon: const Icon(Icons.cancel),
                        label: const Text('Cancel'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _showBillPreview,
                        icon: _isSaving
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(Icons.receipt_long),
                        label: Text(_isSaving ? 'Saving...' : 'Preview Bill'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ],
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
    _notesController.dispose();
    super.dispose();
  }
}

class _ProductSelectionCard extends StatefulWidget {
  final Product product;
  final bool isSelected;
  final int quantity;
  final double price;
  final double minimumPrice;
  final VoidCallback onToggle;
  final Function(int) onQuantityChanged;
  final Function(double) onPriceChanged;

  const _ProductSelectionCard({
    required this.product,
    required this.isSelected,
    required this.quantity,
    required this.price,
    required this.minimumPrice,
    required this.onToggle,
    required this.onQuantityChanged,
    required this.onPriceChanged,
  });

  @override
  State<_ProductSelectionCard> createState() => _ProductSelectionCardState();
}

class _ProductSelectionCardState extends State<_ProductSelectionCard> {
  final TextEditingController _priceController = TextEditingController();
  String? _priceError;

  @override
  void initState() {
    super.initState();
    _priceController.text = widget.price.toStringAsFixed(2);
  }

  @override
  void didUpdateWidget(_ProductSelectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.price != widget.price) {
      _priceController.text = widget.price.toStringAsFixed(2);
    }
  }

  void _validateAndUpdatePrice(String value) {
    final newPrice = double.tryParse(value);

    if (newPrice == null) {
      setState(() {
        _priceError = 'Invalid price';
      });
      return;
    }

    if (newPrice < widget.minimumPrice) {
      setState(() {
        _priceError = 'Min: ₹${widget.minimumPrice.toStringAsFixed(2)}';
      });
    } else {
      setState(() {
        _priceError = null;
      });
      widget.onPriceChanged(newPrice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profitPercentage = widget.product.purchasePrice > 0
        ? ((widget.price - widget.product.purchasePrice) /
        widget.product.purchasePrice) *
        100
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: widget.isSelected ? 4 : 1,
      color: widget.isSelected ? Colors.blue.shade50 : Colors.white,
      child: InkWell(
        onTap: widget.onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                children: [
                  Checkbox(
                    value: widget.isSelected,
                    onChanged: (_) => widget.onToggle(),
                  ),
                  // Product Image
                  Container(
                    width: 60,
                    height: 60,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: widget.product.imageBase64 != null
                          ? Image.memory(
                        base64Decode(widget.product.imageBase64!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.broken_image,
                            size: 30,
                            color: Colors.grey[400],
                          );
                        },
                      )
                          : Icon(
                        Icons.inventory_2,
                        size: 30,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.product.name} ${widget.product.size}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: widget.isSelected
                                ? Colors.blue.shade900
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.inventory,
                              size: 14,
                              color: widget.product.stock < 10
                                  ? Colors.red
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Stock: ${widget.product.stock}',
                              style: TextStyle(
                                color: widget.product.stock < 10
                                    ? Colors.red
                                    : Colors.grey[600],
                                fontSize: 13,
                                fontWeight: widget.product.stock < 10
                                    ? FontWeight.bold
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Cost: ₹${widget.product.purchasePrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${widget.product.salePrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              if (widget.isSelected) ...[
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            'Qty: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: widget.quantity > 1
                                ? () => widget
                                .onQuantityChanged(widget.quantity - 1)
                                : null,
                            iconSize: 28,
                          ),
                          Container(
                            width: 50,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.quantity.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: widget.quantity < widget.product.stock
                                ? () => widget
                                .onQuantityChanged(widget.quantity + 1)
                                : null,
                            iconSize: 28,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        controller: _priceController,
                        decoration: InputDecoration(
                          labelText: 'Price',
                          prefixText: '₹',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          errorText: _priceError,
                          errorStyle: const TextStyle(fontSize: 10),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        onChanged: _validateAndUpdatePrice,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _priceError == null
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _priceError == null
                              ? 'Profit: ${profitPercentage.toStringAsFixed(1)}%'
                              : 'Below minimum',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _priceError == null
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const Text(
                            'Subtotal: ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '₹${(widget.price * widget.quantity).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }
}

class _BillPreviewDialog extends StatelessWidget {
  final List<Product> products;
  final Map<String, int> quantities;
  final Map<String, double> prices;
  final double totalAmount;
  final String notes;

  const _BillPreviewDialog({
    required this.products,
    required this.quantities,
    required this.prices,
    required this.totalAmount,
    required this.notes,
  });

  double _calculateProfit(Product product) {
    final qty = quantities[product.id]!;
    final salePrice = prices[product.id]!;
    return (salePrice - product.purchasePrice) * qty;
  }

  double _calculateTotalProfit() {
    return products.fold(
        0.0, (sum, product) => sum + _calculateProfit(product));
  }

  @override
  Widget build(BuildContext context) {
    final totalProfit = _calculateTotalProfit();

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Bill Preview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Date: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        Text(
                          'Time: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Items:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...products.map((product) {
                      final qty = quantities[product.id]!;
                      final price = prices[product.id]!;
                      final subtotal = price * qty;
                      final profit = _calculateProfit(product);
                      final profitPercent = product.purchasePrice > 0
                          ? ((price - product.purchasePrice) /
                          product.purchasePrice) *
                          100
                          : 0.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Product Image
                            Container(
                              width: 50,
                              height: 50,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: product.imageBase64 != null
                                    ? Image.memory(
                                  base64Decode(product.imageBase64!),
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (context, error, stackTrace) {
                                    return Icon(
                                      Icons.broken_image,
                                      size: 25,
                                      color: Colors.grey[400],
                                    );
                                  },
                                )
                                    : Icon(
                                  Icons.inventory_2,
                                  size: 25,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${product.name} ${product.size}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$qty × ₹${price.toStringAsFixed(2)}',
                                            style: TextStyle(
                                                color: Colors.grey[600]),
                                          ),
                                          Text(
                                            'Profit: ₹${profit.toStringAsFixed(2)} (${profitPercent.toStringAsFixed(1)}%)',
                                            style: TextStyle(
                                              color: Colors.green.shade700,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '₹${subtotal.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Profit:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₹${totalProfit.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '₹${totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    if (notes.isNotEmpty) ...[
                      const Divider(height: 24),
                      const Text(
                        'Notes:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notes,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Confirm & Save'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}