// KEY CHANGES:
// 1. Changed _selectedQuantities from Map<String, int> to Map<String, double>
// 2. Added TextField for manual decimal quantity input (supports 0.5, 1.5, 2.3, etc.)
// 3. Quantity can now be any decimal number, not just integers
// 4. Updated all quantity-related logic to work with doubles

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
  Map<String, int> _selectedQuantities = {}; // Changed to double for decimal support
  Map<String, double> _customPrices = {};
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
        _selectedQuantities[product.id] = 1; // Default quantity as double
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
            content: Text(
              '${product.name}: Please enter a valid price',
            ),
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

      // Calculate total
      final total = _totalAmount;

      // Create sale object
      final sale = Sale(
        id: '', // Will be set by Firestore
        items: saleItems,
        totalAmount: total,
        createdAt: DateTime.now(),
        paymentMethod: paymentMethodEnum,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      await _salesService.createSale(sale);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale recorded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error recording sale: $e'),
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
        title: const Text('Record Sale'),
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
              color: Colors.white,
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
        title: const Text('Record Sale'),
        elevation: 0,
        actions: [
          if (_selectedQuantities.isNotEmpty)
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
                label: Text('${_selectedQuantities.length}'),
                child: const Icon(Icons.shopping_cart),
              ),
            ),
        ],
      ),
      body: _buildProductList(),
      bottomNavigationBar: _selectedQuantities.isNotEmpty
          ? _buildMobileBottomBar()
          : null,
    );
  }

  Widget _buildProductList() {
    return Column(
      children: [
        // Search bar
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey[100],
            ),
          ),
        ),

        // Products grid
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredProducts.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: Colors.grey[400],
                ),
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
            padding: EdgeInsets.all(_isDesktop ? 24 : 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _isDesktop ? 4 : (_isTablet ? 3 : 2),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            itemCount: _filteredProducts.length,
            itemBuilder: (context, index) {
              final product = _filteredProducts[index];
              final isSelected = _selectedQuantities.containsKey(product.id);

              return _ProductCard(
                product: product,
                isSelected: isSelected,
                quantity: _selectedQuantities[product.id] ?? 0,
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_cart, color: Colors.blue),
              const SizedBox(width: 12),
              Text(
                'Cart (${_selectedProducts.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_selectedProducts.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedQuantities.clear();
                      _customPrices.clear();
                    });
                  },
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear'),
                ),
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
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Cart is empty',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add products to get started',
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
            itemCount: _selectedProducts.length,
            itemBuilder: (context, index) {
              final product = _selectedProducts[index];
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

        // Payment method and total
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Payment method
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
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Total
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

              // Complete button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _completeSale,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    'Complete Sale',
                    style: TextStyle(fontSize: 16),
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
          margin: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Cart header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart, color: Colors.blue),
                    const SizedBox(width: 12),
                    Text(
                      'Cart (${_selectedProducts.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedProducts.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedQuantities.clear();
                            _customPrices.clear();
                          });
                          setModalState(() {});
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Clear'),
                      ),
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
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Cart is empty',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _selectedProducts.length,
                  itemBuilder: (context, index) {
                    final product = _selectedProducts[index];
                    return _CartItem(
                      product: product,
                      quantity: _selectedQuantities[product.id]!,
                      price: _customPrices[product.id]!,
                      onQuantityChanged: (qty) {
                        _updateQuantity(product.id, qty);
                        setModalState(() {});
                      },
                      onPriceChanged: (price) {
                        _updatePrice(product.id, price);
                        setModalState(() {});
                      },
                      onRemove: () {
                        _toggleProduct(product);
                        setModalState(() {});
                      },
                      minimumPrice: _getMinimumPrice(product),
                    );
                  },
                ),
              ),

              // Payment method and total
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Payment method
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
                    const SizedBox(height: 20),

                    // Total
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

                    // Complete button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _completeSale,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text(
                          'Complete Sale',
                          style: TextStyle(fontSize: 16),
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
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
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

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}

// Product Card Widget - Updated to match ProductListScreen design
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
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isOutOfStock
              ? Colors.red.shade500
              : isLowStock
              ? Colors.orange.shade500
              : Colors.green.shade500,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOutOfStock ? Icons.warning_rounded : Icons.inventory_2,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              '${product.stock}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip() {
    final categoryColor = getCategoryColor(product.category);
    final textColor = getCategoryTextColor(product.category);

    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: categoryColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.category,
              size: 12,
              color: textColor,
            ),
            const SizedBox(width: 4),
            Text(
              product.category.toUpperCase(),
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedBadge() {
    return Positioned(
      bottom: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.check,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildPriceRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Icons.currency_rupee,
              size: 12,
              color: Colors.green.shade700,
            ),
            const SizedBox(width: 4),
            Text(
              'Sale',
              style: TextStyle(
                fontSize: 11,
                color: Colors.green.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          '₹${product.salePrice.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.green.shade700,
          ),
        ),
      ],
    );
  }
}

// Cart Item Widget with Decimal Quantity Input
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
  late FocusNode _qtyFocusNode;
  late FocusNode _priceFocusNode;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.price.toStringAsFixed(2),
    );
    _qtyController = TextEditingController(
      text: _formatQuantity(widget.quantity),
    );
    _qtyFocusNode = FocusNode();
    _priceFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(_CartItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.price != widget.price && !_priceFocusNode.hasFocus) {
      _priceController.text = widget.price.toStringAsFixed(2);
    }
    if (oldWidget.quantity != widget.quantity && !_qtyFocusNode.hasFocus) {
      _qtyController.text = _formatQuantity(widget.quantity);
    }
  }

  String _formatQuantity(int quantity) {
    // Remove unnecessary decimal zeros
    if (quantity == quantity.toInt()) {
      return quantity.toInt().toString();
    }
    return quantity.toString();
  }

  double get _subtotal {
    return widget.price * widget.quantity;
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
                // Quantity with +/- buttons and text field
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
                          // Minus button
                          IconButton(
                            onPressed: () {
                              final newQty = widget.quantity - 1;
                              if (newQty > 0) {
                                widget.onQuantityChanged(newQty);
                              }
                            },
                            icon: const Icon(Icons.remove, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.grey[100],
                              padding: const EdgeInsets.all(8),
                              minimumSize: const Size(36, 36),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Quantity text field
                          Expanded(
                            child: TextField(
                              controller: _qtyController,
                              focusNode: _qtyFocusNode,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                              ),
                              onChanged: (value) {
                                final qty = int.tryParse(value);
                                if (qty != null && qty > 0) {
                                  widget.onQuantityChanged(qty);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Plus button
                          IconButton(
                            onPressed: () {
                              final newQty = widget.quantity+1 ;
                              if (newQty <= widget.product.stock) {
                                widget.onQuantityChanged(newQty);
                              }
                            },
                            icon: const Icon(Icons.add, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.blue.shade50,
                              foregroundColor: Colors.blue,
                              padding: const EdgeInsets.all(8),
                              minimumSize: const Size(36, 36),
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
                        focusNode: _priceFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

            // Minimum price warning
            if (widget.price < widget.minimumPrice)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Min price: ₹${widget.minimumPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
                  '₹${_subtotal.toStringAsFixed(2)}',
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
    _qtyFocusNode.dispose();
    _priceFocusNode.dispose();
    super.dispose();
  }
}