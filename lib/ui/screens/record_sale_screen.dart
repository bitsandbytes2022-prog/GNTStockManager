// KEY IMPROVEMENTS:
// 1. Added quantity popup when selecting a product
// 2. Cart items maintain the order they were added
// 3. Improved user experience with quick quantity entry

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product_model.dart';
import '../../models/sale_model.dart';
import '../../services/firebase_service.dart';
import '../../services/sales_service.dart';
import '../screens/bill_preview_screen.dart';

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

  // Changed to track order of items added
  Map<String, int> _selectedQuantities = {};
  Map<String, double> _customPrices = {};
  List<String> _cartItemOrder = []; // Track order of items added to cart

  String _searchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;
  String _paymentMethod = 'Cash';

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;
  bool get _isTablet => MediaQuery.of(context).size.width >= 768;

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

          return queryWords.every(
                (word) => name.contains(word) || size.contains(word),
          );
        }).toList();
      }
    });
  }

  // New method to show quantity popup
  Future<void> _showQuantityDialog(Product product) async {
    // Check if product is already in cart
    bool isInCart = _selectedQuantities.containsKey(product.id);
    int currentQuantity = _selectedQuantities[product.id] ?? 1;

    final TextEditingController qtyController = TextEditingController(
      text: currentQuantity.toString(),
    );

    // Focus node for auto-focus
    final FocusNode qtyFocusNode = FocusNode();

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isInCart ? 'Update Quantity' : 'Add to Cart',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                product.size,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Stock info
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: product.stock < 5
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: product.stock < 5
                        ? Colors.orange.shade200
                        : Colors.green.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: product.stock < 5 ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Available Stock: ${product.stock}',
                      style: TextStyle(
                        color: product.stock < 5
                            ? Colors.orange.shade700
                            : Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Quantity input with buttons
              Row(
                children: [
                  // Decrease button
                  IconButton(
                    onPressed: () {
                      int currentVal = int.tryParse(qtyController.text) ?? 1;
                      if (currentVal > 1) {
                        qtyController.text = (currentVal - 1).toString();
                        qtyController.selection = TextSelection.fromPosition(
                          TextPosition(offset: qtyController.text.length),
                        );
                      }
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                    iconSize: 32,
                    color: Colors.blue,
                  ),

                  // Quantity input field
                  Expanded(
                    child: TextField(
                      controller: qtyController,
                      focusNode: qtyFocusNode,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        hintText: '1',
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      onSubmitted: (value) {
                        int? qty = int.tryParse(value);
                        if (qty != null && qty > 0 && qty <= product.stock) {
                          Navigator.of(context).pop(qty);
                        }
                      },
                    ),
                  ),

                  // Increase button
                  IconButton(
                    onPressed: () {
                      int currentVal = int.tryParse(qtyController.text) ?? 0;
                      if (currentVal < product.stock) {
                        qtyController.text = (currentVal + 1).toString();
                        qtyController.selection = TextSelection.fromPosition(
                          TextPosition(offset: qtyController.text.length),
                        );
                      }
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    iconSize: 32,
                    color: Colors.blue,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Quick quantity buttons
              Wrap(
                spacing: 8,
                children: [1, 5, 10, 25, 50].map((qty) {
                  if (qty > product.stock) return const SizedBox.shrink();
                  return ActionChip(
                    label: Text(qty.toString()),
                    onPressed: () {
                      qtyController.text = qty.toString();
                      qtyController.selection = TextSelection.fromPosition(
                        TextPosition(offset: qtyController.text.length),
                      );
                    },
                  );
                }).toList(),
              ),

              // Price info
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Price per unit:'),
                    Text(
                      '₹${product.salePrice.toStringAsFixed(2)}',
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
          actions: [
            // Remove from cart button (only if already in cart)
            if (isInCart)
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(-1); // -1 indicates remove
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),

            // Cancel button
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),

            // Add/Update button
            FilledButton.icon(
              onPressed: () {
                int? qty = int.tryParse(qtyController.text);
                if (qty == null || qty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid quantity'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  return;
                }
                if (qty > product.stock) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Maximum available: ${product.stock}'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                  return;
                }
                Navigator.of(context).pop(qty);
              },
              icon: Icon(isInCart ? Icons.update : Icons.add_shopping_cart),
              label: Text(isInCart ? 'Update' : 'Add to Cart'),
            ),
          ],
        );
      },
    );

    // Auto-focus and select all text when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      qtyFocusNode.requestFocus();
      qtyController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: qtyController.text.length,
      );
    });

    // Handle the result
    if (result != null) {
      if (result == -1) {
        // Remove from cart
        _removeFromCart(product.id);
      } else if (result > 0) {
        // Add or update in cart
        _addToCart(product, result);
      }
    }
  }

  void _addToCart(Product product, int quantity) {
    setState(() {
      if (!_selectedQuantities.containsKey(product.id)) {
        // New item - add to order list
        _cartItemOrder.add(product.id);
        _customPrices[product.id] = product.salePrice;
      }
      _selectedQuantities[product.id] = quantity;
    });

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _cartItemOrder.contains(product.id)
              ? 'Updated: ${product.name} (Qty: $quantity)'
              : 'Added: ${product.name} (Qty: $quantity)',
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _removeFromCart(String productId) {
    setState(() {
      _selectedQuantities.remove(productId);
      _customPrices.remove(productId);
      _cartItemOrder.remove(productId);
    });
  }

  void _updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      _removeFromCart(productId);
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

  List<Product> get _selectedProductsOrdered {
    // Return products in the order they were added to cart
    final List<Product> orderedProducts = [];
    for (final productId in _cartItemOrder) {
      try {
        final product = _allProducts.firstWhere((p) => p.id == productId);
        orderedProducts.add(product);
      } catch (e) {
        // Product not found, skip it
        continue;
      }
    }
    return orderedProducts;
  }

  List<Product> get _selectedProducts {
    return _allProducts
        .where((p) => _selectedQuantities.containsKey(p.id))
        .toList();
  }

  Future<void> _completeSale() async {
    if (_selectedQuantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product')),
      );
      return;
    }

    // Validate quantities
    for (final entry in _selectedQuantities.entries) {
      if (entry.value <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quantity must be greater than 0'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Validate prices
    for (final product in _selectedProducts) {
      final currentPrice = _customPrices[product.id];
      if (currentPrice == null || currentPrice <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name}: Please enter a valid price'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

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
      final saleItems = _selectedProducts.map((product) {
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

      final sale = Sale(
        id: '',
        invoiceNumber: 0, // Will be set by the service
        items: saleItems,
        totalAmount: _totalAmount,
        paymentMethod: paymentMethodEnum,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      await _salesService.createSale(sale);

      if (mounted) {
        // Clear form
        setState(() {
          _selectedQuantities.clear();
          _customPrices.clear();
          _cartItemOrder.clear();
          _notesController.clear();
          _searchController.clear();
        });

        // Refresh products to get updated stock
        await _loadProducts();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error completing sale: $e'),
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
    } else if (_isTablet) {
      return _buildTabletLayout();
    } else {
      return _buildMobileLayout();
    }
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: const Text('Record Sale'),
        backgroundColor: Colors.white,
      ),
      body: Row(
        children: [
          // Product Grid
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  _buildSearchBar(),
                  Expanded(child: _buildProductGrid()),
                ],
              ),
            ),
          ),

          // Cart
          Container(
            width: 400,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                left: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: _buildDesktopCart(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: const Text('Record Sale'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _buildCartBottomSheet(),
              );
            },
            icon: Badge(
              label: Text(_selectedQuantities.length.toString()),
              child: const Icon(Icons.shopping_cart),
            ),
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: _buildProductGrid()),
            if (_selectedQuantities.isNotEmpty) _buildMobileBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        title: const Text('Record Sale'),
        backgroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildProductGrid()),
          if (_selectedQuantities.isNotEmpty) _buildMobileBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search products...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
            },
          )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No products found',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            if (_searchQuery.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                },
                child: const Text('Clear search'),
              ),
            ],
          ],
        ),
      );
    }

    return GridView.builder(
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
        final quantity = _selectedQuantities[product.id] ?? 0;

        return _ProductCard(
          product: product,
          isSelected: isSelected,
          quantity: quantity,
          onTap: () => _showQuantityDialog(product),
        );
      },
    );
  }

  Widget _buildDesktopCart() {
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
          child: Row(
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
              const Spacer(),
              if (_selectedQuantities.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedQuantities.clear();
                      _customPrices.clear();
                      _cartItemOrder.clear();
                    });
                  },
                  child: const Text(
                    'Clear All',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),

        // Cart items (in order)
        Expanded(
          child: _selectedProductsOrdered.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined,
                    size: 64,
                    color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Cart is empty',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Click on products to add them',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _selectedProductsOrdered.length,
            itemBuilder: (context, index) {
              final product = _selectedProductsOrdered[index];
              return _CartItem(
                product: product,
                quantity: _selectedQuantities[product.id]!,
                price: _customPrices[product.id]!,
                onQuantityChanged: (qty) => _updateQuantity(product.id, qty),
                onPriceChanged: (price) => _updatePrice(product.id, price),
                onRemove: () => _removeFromCart(product.id),
                onEdit: () => _showQuantityDialog(product),
                minimumPrice: _getMinimumPrice(product),
                itemNumber: index + 1, // Show item number
              );
            },
          ),
        ),

        // Payment and notes
        if (_selectedQuantities.isNotEmpty) ...[
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
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['Cash', 'UPI', 'Card', 'Other'].map((method) {
                    return ChoiceChip(
                      label: Text(method),
                      selected: _paymentMethod == method,
                      onSelected: (_) => setState(() => _paymentMethod = method),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Notes (Optional)',
                    hintText: 'Add any notes...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Total and action buttons
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
                      '₹${_totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showBillPreview,
                        icon: const Icon(Icons.receipt_long),
                        label: const Text('Preview'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
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
                            : const Icon(Icons.check),
                        label: Text(_isSaving ? 'Processing...' : 'Complete Sale'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCartBottomSheet() {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) {
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
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cart (${_selectedQuantities.length} items)',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Cart items
                  Expanded(
                    child: _selectedProductsOrdered.isEmpty
                        ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_cart_outlined,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Cart is empty',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                        : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _selectedProductsOrdered.length,
                      itemBuilder: (context, index) {
                        final product = _selectedProductsOrdered[index];
                        return _CartItem(
                          product: product,
                          quantity: _selectedQuantities[product.id]!,
                          price: _customPrices[product.id]!,
                          onQuantityChanged: (qty) {
                            setState(() => _updateQuantity(product.id, qty));
                            setModalState(() {});
                          },
                          onPriceChanged: (price) {
                            setState(() => _updatePrice(product.id, price));
                            setModalState(() {});
                          },
                          onRemove: () {
                            setState(() => _removeFromCart(product.id));
                            setModalState(() {});
                          },
                          onEdit: () {
                            Navigator.pop(context);
                            _showQuantityDialog(product);
                          },
                          minimumPrice: _getMinimumPrice(product),
                          itemNumber: index + 1,
                        );
                      },
                    ),
                  ),

                  // Payment method and notes
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: ['Cash', 'UPI', 'Card', 'Other'].map((method) {
                            final isSelected = _paymentMethod == method;
                            return ChoiceChip(
                              label: Text(method),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() => _paymentMethod = method);
                                setModalState(() {});
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Notes (Optional)',
                            hintText: 'Add any notes...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Total and action buttons
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
                              '₹${_totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showBillPreview();
                                },
                                icon: const Icon(Icons.receipt_long),
                                label: const Text('Preview'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: _isSaving ? null : () {
                                  Navigator.pop(context);
                                  _completeSale();
                                },
                                icon: _isSaving
                                    ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                    : const Icon(Icons.check),
                                label: Text(_isSaving ? 'Processing...' : 'Complete Sale'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.all(12),
                                ),
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
          },
        );
      },
    );
  }

  Widget _buildMobileBottomBar() {
    return Container(
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
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selectedQuantities.length} items',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  Text(
                    '₹${_totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _buildCartBottomSheet(),
                );
              },
              child: const Text('View Cart'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBillPreview() async {
    if (_selectedQuantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product')),
      );
      return;
    }

    // Validate stock
    for (final entry in _selectedQuantities.entries) {
      final productId = entry.key;
      final quantity = entry.value;
      final product = _allProducts.firstWhere((p) => p.id == productId);

      if (quantity > product.stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${product.name} has insufficient stock. Available: ${product.stock}',
            ),
          ),
        );
        return;
      }
    }

    // Prepare data for bill preview
    final Map<String, Product> selectedProducts = {};
    for (final productId in _selectedQuantities.keys) {
      final product = _allProducts.firstWhere((p) => p.id == productId);
      selectedProducts[productId] = product;
    }

    // Navigate to bill preview
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => BillPreviewScreen(
          products: selectedProducts,
          quantities: _selectedQuantities,
          prices: _customPrices,
          paymentMethod: _paymentMethod,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        ),
      ),
    );

    // If sale was completed successfully, clear the form
    if (result == true && mounted) {
      setState(() {
        _selectedQuantities.clear();
        _customPrices.clear();
        _cartItemOrder.clear();
        _notesController.clear();
        _searchController.clear();
      });

      // Refresh products to get updated stock
      await _loadProducts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sale completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}

// Product Card Widget
class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isSelected;
  final int quantity;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.isSelected,
    required this.quantity,
    required this.onTap,
  });

  /// Get category color based on category name
  Color getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'ppr':
        return Colors.green.shade700;
      case 'cpvc':
        return const Color(0xFFF5DEB3); // Wheat/Cream color
      case 'pvc':
        return Colors.lightBlue.shade400;
      case 'gi':
      case 'galvanized':
        return Colors.grey.shade500;
      case 'paints':
        return Colors.purple.shade400;
      case 'hardware':
        return Colors.orange.shade700;
      case 'adhesives':
        return Colors.amber.shade700;
      case 'fittings':
        return Colors.teal.shade600;
      case 'electrical':
        return Colors.yellow.shade700;
      case 'plumbing':
        return Colors.blue.shade800;
      default:
        return Colors.blueGrey.shade600;
    }
  }

  /// Get text color for category chip
  Color getCategoryTextColor(String category) {
    switch (category.toLowerCase()) {
      case 'cpvc':
      case 'electrical':
        return Colors.black87;
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOutOfStock = product.stock == 0;
    final isLowStock = product.stock < 5 && product.stock > 0;

    return Card(
      elevation: isSelected ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? Colors.blue
              : isOutOfStock
              ? Colors.red.shade100
              : isLowStock
              ? Colors.orange.shade100
              : Colors.grey.shade100,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: isOutOfStock ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image section
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  _buildImage(),
                  _buildStockBadge(isOutOfStock, isLowStock),
                  _buildCategoryChip(),
                  if (isSelected) _buildSelectedBadge(),
                ],
              ),
            ),

            // Info section
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Name and size
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.size,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),

                    // Price row
                    _buildPriceRow(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        child: product.imageBase64 != null
            ? Image.memory(
          base64Decode(product.imageBase64!),
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            return _buildPlaceholder();
          },
        )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        Icons.inventory_2_outlined,
        size: 48,
        color: Colors.grey.shade400,
      ),
    );
  }

  Widget _buildStockBadge(bool isOutOfStock, bool isLowStock) {
    if (!isOutOfStock && !isLowStock) return const SizedBox.shrink();

    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isOutOfStock
              ? Colors.red.shade500
              : Colors.orange.shade500,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          isOutOfStock ? 'Out of Stock' : 'Low Stock: ${product.stock}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip() {
    if (product.category.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: getCategoryColor(product.category),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          product.category.toUpperCase(),
          style: TextStyle(
            color: getCategoryTextColor(product.category),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedBadge() {
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
        child: Column(
          children: [
            const Icon(
              Icons.check,
              color: Colors.white,
              size: 16,
            ),
            if (quantity > 0) ...[
              const SizedBox(height: 2),
              Text(
                quantity.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '₹${product.salePrice.toStringAsFixed(0)}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Stock: ${product.stock}',
            style: TextStyle(
              fontSize: 11,
              color: product.stock < 5
                  ? Colors.orange
                  : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// Cart Item Widget with improved controls
class _CartItem extends StatefulWidget {
  final Product product;
  final int quantity;
  final double price;
  final Function(int) onQuantityChanged;
  final Function(double) onPriceChanged;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final double minimumPrice;
  final int itemNumber;

  const _CartItem({
    required this.product,
    required this.quantity,
    required this.price,
    required this.onQuantityChanged,
    required this.onPriceChanged,
    required this.onRemove,
    required this.onEdit,
    required this.minimumPrice,
    required this.itemNumber,
  });

  @override
  State<_CartItem> createState() => _CartItemState();
}

class _CartItemState extends State<_CartItem> {
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.price.toStringAsFixed(0),
    );
  }

  @override
  void didUpdateWidget(_CartItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.price != widget.price) {
      _priceController.text = widget.price.toStringAsFixed(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = widget.price * widget.quantity;

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
            // Header with item number
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.itemNumber.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Product image
                Container(
                  width: 40,
                  height: 40,
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
                      size: 20,
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

                // Actions
                Row(
                  children: [
                    IconButton(
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.blue,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onRemove,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ],
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
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: widget.quantity > 1
                                  ? () => widget.onQuantityChanged(widget.quantity - 1)
                                  : null,
                              icon: const Icon(Icons.remove, size: 18),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                widget.quantity.toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: widget.quantity < widget.product.stock
                                  ? () => widget.onQuantityChanged(widget.quantity + 1)
                                  : null,
                              icon: const Icon(Icons.add, size: 18),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

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
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 14),
                        onChanged: (value) {
                          final price = double.tryParse(value);
                          if (price != null && price > 0) {
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
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Subtotal',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '₹${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
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

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }
}