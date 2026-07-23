import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/product_model.dart';
import '../../models/sale_model.dart';
import '../../services/firebase_service.dart';
import '../../services/sales_service.dart';

class EditSaleScreen extends StatefulWidget {
  final Sale sale;

  const EditSaleScreen({super.key, required this.sale});

  @override
  State<EditSaleScreen> createState() => _EditSaleScreenState();
}

class _EditSaleScreenState extends State<EditSaleScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final SalesService _salesService = SalesService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _cartSearchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  Map<String, int> _selectedQuantities = {};
  Map<String, double> _customPrices = {};
  Map<String, int> _originalQuantities = {}; // To track stock changes
  String _searchQuery = '';
  String _cartSearchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;
  String _paymentMethod = 'Cash';

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;
  bool get _isTablet => MediaQuery.of(context).size.width >= 768;

  @override
  void initState() {
    super.initState();
    _initializeFromSale();
    _loadProducts();
    _searchController.addListener(_filterProducts);
    _cartSearchController.addListener(_filterCartProducts);
  }

  void _filterCartProducts() {
    setState(() {
      _cartSearchQuery = _cartSearchController.text.toLowerCase();
    });
  }

  void _initializeFromSale() {
    // Initialize from existing sale
    _paymentMethod = widget.sale.paymentMethod?.label ?? 'Cash';
    _notesController.text = widget.sale.notes ?? '';

    // Populate selected items
    for (final item in widget.sale.items) {
      _selectedQuantities[item.productId] = item.quantity;
      _customPrices[item.productId] = item.salePrice;
      _originalQuantities[item.productId] = item.quantity;
    }
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
    return product.purchasePrice * 0.50;
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

  List<Product> get _filteredCartProducts {
    if (_cartSearchQuery.isEmpty) {
      return _selectedProducts;
    }

    final queryWords = _cartSearchQuery.split(' ').where((w) => w.isNotEmpty);

    return _selectedProducts.where((product) {
      final name = product.name.toLowerCase();
      final size = product.size.toLowerCase();

      return queryWords.every((word) => name.contains(word) || size.contains(word));
    }).toList();
  }

  Future<void> _updateSale() async {
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
              '${product.name}: Price must be at least ₹${minPrice.toStringAsFixed(2)}',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // Create updated sale items
      final updatedSaleItems = _selectedProducts.map((product) {
        return SaleItem(
          productId: product.id,
          productName: product.name,
          productSize: product.size,
          quantity: _selectedQuantities[product.id]!,
          salePrice: _customPrices[product.id]!,
          purchasePrice: product.purchasePrice,
          imageBase64: product.imageBase64,
        );
      }).toList();

      // Convert payment method string to enum
      PaymentMethod paymentMethodEnum;
      switch (_paymentMethod.toLowerCase()) {
        case 'cash':
          paymentMethodEnum = PaymentMethod.cash;
          break;
        case 'upi':
          paymentMethodEnum = PaymentMethod.upi;
          break;
        case 'card':
          paymentMethodEnum = PaymentMethod.card;
          break;
        default:
          paymentMethodEnum = PaymentMethod.other;
      }

      // Calculate total
      final total = updatedSaleItems.fold<double>(
        0.0,
            (sum, item) => sum + (item.salePrice * item.quantity),
      );

      // Create updated sale object
      final updatedSale = Sale(
        invoiceNumber: widget.sale.invoiceNumber,
        id: widget.sale.id,
        items: updatedSaleItems,
        totalAmount: total,
        createdAt: widget.sale.createdAt, // Keep original creation date
        paymentMethod: paymentMethodEnum,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        isMock: widget.sale.isMock, // Preserve mock flag through edits
      );

      // Update sale with stock adjustments
      await _salesService.updateSale(
        widget.sale,
        updatedSale,
        _originalQuantities,
      );

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating sale: $e'),
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

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return _buildDesktopLayout();
    } else {
      return _buildMobileLayout();
    }
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Sale'),
            Text(
              'Sale from ${DateFormat('MMM dd, yyyy hh:mm a').format(widget.sale.createdAt)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: Row(
        children: [
          // Left side - Product selection
          Expanded(
            flex: 3,
            child: _buildProductList(),
          ),

          // Right side - Cart
          Container(
            width: 400,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                left: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: _buildCart(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Sale'),
            Text(
              DateFormat('MMM dd, yyyy').format(widget.sale.createdAt),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: _buildProductList(),
      bottomSheet: _selectedQuantities.isNotEmpty
          ? _buildCartBottomSheet()
          : null,
    );
  }

  Widget _buildProductList() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search products...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),

        // Product grid
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredProducts.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No products found',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          )
              : GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _isDesktop ? 4 : (_isTablet ? 3 : 2),
              childAspectRatio: 0.75,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _filteredProducts.length,
            itemBuilder: (context, index) {
              final product = _filteredProducts[index];
              final isSelected = _selectedQuantities.containsKey(product.id);

              return _ProductCard(
                product: product,
                isSelected: isSelected,
                onTap: () => _toggleProduct(product),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCart() {
    return Column(
      children: [
        // Cart header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.shopping_cart, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Cart (${_selectedQuantities.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (_selectedQuantities.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _cartSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search cart...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _cartSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _cartSearchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Cart items
        Expanded(
          child: _selectedProducts.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No items selected',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          )
              : _filteredCartProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No items found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search term',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredCartProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredCartProducts[index];
                        return _CartItem(
                          product: product,
                          quantity: _selectedQuantities[product.id]!,
                          price: _customPrices[product.id]!,
                          onQuantityChanged: (qty) => _updateQuantity(product.id, qty),
                          onPriceChanged: (price) => _updatePrice(product.id, price),
                          onRemove: () => _toggleProduct(product),
                          minimumPrice: _getMinimumPrice(product),
                        );
                      },
                    ),
        ),

        // Payment method and notes
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Payment Method',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: ['Cash', 'UPI', 'Card', 'Other']
                    .map((method) => DropdownMenuItem(
                  value: method,
                  child: Text(method),
                ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _paymentMethod = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Notes (Optional)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Add any notes...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),

        // Total and complete button
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
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '₹${_totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving || _selectedQuantities.isEmpty
                      ? null
                      : _updateSale,
                  icon: _isSaving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.check),
                  label: Text(_isSaving ? 'Updating...' : 'Update Sale'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCartBottomSheet() {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.shopping_cart),
                  title: Text('${_selectedQuantities.length} items'),
                  trailing: Text(
                    '₹${_totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => _buildCartModal(),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving || _selectedQuantities.isEmpty
                          ? null
                          : _updateSale,
                      icon: _isSaving
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.check),
                      label: Text(_isSaving ? 'Updating...' : 'Update Sale'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCartModal() {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text(
                      'Cart Items',
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

              const Divider(height: 1),

              // Search bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _cartSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search cart...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _cartSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _cartSearchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),

              // Cart items
              Expanded(
                child: _filteredCartProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No items found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try a different search term',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredCartProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredCartProducts[index];
                          return _CartItem(
                            product: product,
                            quantity: _selectedQuantities[product.id]!,
                            price: _customPrices[product.id]!,
                            onQuantityChanged: (qty) {
                              setState(() => _updateQuantity(product.id, qty));
                            },
                            onPriceChanged: (price) {
                              setState(() => _updatePrice(product.id, price));
                            },
                            onRemove: () {
                              setState(() => _toggleProduct(product));
                            },
                            minimumPrice: _getMinimumPrice(product),
                          );
                        },
                      ),
              ),

              // Payment and notes section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      decoration: InputDecoration(
                        labelText: 'Payment Method',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: ['Cash', 'UPI', 'Card', 'Other']
                          .map((method) => DropdownMenuItem(
                        value: method,
                        child: Text(method),
                      ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _paymentMethod = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Notes (Optional)',
                        hintText: 'Add any notes...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Total and button
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
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '₹${_totalAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSaving || _selectedQuantities.isEmpty
                            ? null
                            : _updateSale,
                        icon: _isSaving
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(Icons.check),
                        label: Text(_isSaving ? 'Updating...' : 'Update Sale'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cartSearchController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}

// Product Card Widget
class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isSelected;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 8 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product image
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: product.imageBase64 != null
                        ? ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: Image.memory(
                        base64Decode(product.imageBase64!),
                        fit: BoxFit.cover,
                      ),
                    )
                        : Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                  ),
                ),

                // Product info
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product.size,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₹${product.salePrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Selected indicator
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Cart Item Widget (reusing from RecordSaleScreen)
class _CartItem extends StatefulWidget {
  final Product product;
  final int quantity;
  final double price;
  final Function(int) onQuantityChanged;
  final Function(double) onPriceChanged;
  final VoidCallback onRemove;
  final double minimumPrice;

  const _CartItem({
    required this.product,
    required this.quantity,
    required this.price,
    required this.onQuantityChanged,
    required this.onPriceChanged,
    required this.onRemove,
    required this.minimumPrice,
  });

  @override
  State<_CartItem> createState() => _CartItemState();
}

class _CartItemState extends State<_CartItem> {
  late TextEditingController _priceController;
  late TextEditingController _qtyController;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.price.toStringAsFixed(0),
    );
    _qtyController = TextEditingController(
      text: widget.quantity.toString(),
    );
  }

  @override
  void didUpdateWidget(_CartItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.price != widget.price) {
      _priceController.text = widget.price.toStringAsFixed(0);
    }
    if (oldWidget.quantity != widget.quantity) {
      _qtyController.text = widget.quantity.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Product image
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: widget.product.imageBase64 != null
                        ? Image.memory(
                      base64Decode(widget.product.imageBase64!),
                      fit: BoxFit.cover,
                    )
                        : Icon(
                      Icons.inventory_2_outlined,
                      color: Colors.grey[400],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Product info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        widget.product.size,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                // Remove button
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quantity and price controls
            Row(
              children: [
                // Quantity
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quantity',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              if (widget.quantity > 1) {
                                widget.onQuantityChanged(widget.quantity - 1);
                              }
                            },
                            icon: const Icon(Icons.remove, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.grey[100],
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${widget.quantity}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              if (widget.quantity < widget.product.stock) {
                                widget.onQuantityChanged(widget.quantity + 1);
                              }
                            },
                            icon: const Icon(Icons.add, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.blue.shade50,
                              foregroundColor: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Price
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Price',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixText: '₹',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) {
                          final price = double.tryParse(value);
                          if (price != null) {
                            widget.onPriceChanged(price);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Subtotal
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subtotal',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  '₹${(widget.price * widget.quantity).toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }
}