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

enum ProductSortOption { newest, lowStock, highSelling }

// Custom item class for non-inventory items
class CustomItem {
  final String id;
  final String name;
  final double amount;
  final int quantity;

  CustomItem({
    required this.id,
    required this.name,
    required this.amount,
    this.quantity = 1,
  });

  CustomItem copyWith({
    String? id,
    String? name,
    double? amount,
    int? quantity,
  }) {
    return CustomItem(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      quantity: quantity ?? this.quantity,
    );
  }
}

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
  final TextEditingController _cartSearchController = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];

  // Changed to track order of items added
  Map<String, int> _selectedQuantities = {};
  Map<String, double> _customPrices = {};
  List<String> _cartItemOrder = []; // Track order of items added to cart

  // Custom items (non-inventory items)
  Map<String, CustomItem> _customItems = {};
  List<String> _customItemOrder = []; // Track order of custom items

  String _searchQuery = '';
  String _cartSearchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;
  String _paymentMethod = 'Cash';

  // Category filtering
  List<String> _categories = [];
  String? _selectedCategory; // null means "All Categories"
  bool _isLoadingCategories = true;

  // Sort option
  ProductSortOption _currentSortOption = ProductSortOption.newest;

  // Show purchase prices and margin
  bool showPurchasePrices = true;

  // Mock sale: records the sale for profit review but does NOT deduct stock
  // and stays out of revenue/profit analytics.
  bool _isMockSale = false;

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;
  bool get _isTablet => MediaQuery.of(context).size.width >= 768;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadCategories();
    _searchController.addListener(_filterProducts);
    _cartSearchController.addListener(() {
      setState(() {
        _cartSearchQuery = _cartSearchController.text.toLowerCase();
      });
    });
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      _allProducts = await _firebaseService.getCachedProducts();
      _filterProducts();
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

  Future<void> _loadCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final categories = await _firebaseService.getCategories();
      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() => _isLoadingCategories = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading categories: $e')),
        );
      }
    }
  }

  void _filterProducts() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      var filtered = _allProducts;

      // Filter by category
      if (_selectedCategory != null) {
        filtered = filtered
            .where((p) => p.category.toLowerCase() == _selectedCategory!.toLowerCase())
            .toList();
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final queryWords = _searchQuery.split(' ').where((w) => w.isNotEmpty);

        filtered = filtered.where((product) {
          final name = product.name.toLowerCase();
          final size = product.size.toLowerCase();

          return queryWords.every(
                (word) => name.contains(word) || size.contains(word),
          );
        }).toList();
      }

      // Sort products
      _filteredProducts = _sortProducts(filtered);
    });
  }

  List<Product> _sortProducts(List<Product> products) {
    final sortedList = List<Product>.from(products);

    switch (_currentSortOption) {
      case ProductSortOption.newest:
        sortedList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case ProductSortOption.lowStock:
        sortedList.sort((a, b) {
          final stockCompare = a.stock.compareTo(b.stock);
          if (stockCompare != 0) return stockCompare;
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
      case ProductSortOption.highSelling:
        sortedList.sort((a, b) {
          final soldCompare = b.totalSold.compareTo(a.totalSold);
          if (soldCompare != 0) return soldCompare;
          final countCompare = b.saleCount.compareTo(a.saleCount);
          if (countCompare != 0) return countCompare;
          return b.salesFrequency.compareTo(a.salesFrequency);
        });
        break;
    }

    return sortedList;
  }

  String _getSortOptionLabel(ProductSortOption option) {
    switch (option) {
      case ProductSortOption.newest:
        return 'Newest First';
      case ProductSortOption.lowStock:
        return 'Low Stock';
      case ProductSortOption.highSelling:
        return 'Best Sellers';
    }
  }

  IconData _getSortOptionIcon(ProductSortOption option) {
    switch (option) {
      case ProductSortOption.newest:
        return Icons.schedule;
      case ProductSortOption.lowStock:
        return Icons.trending_down;
      case ProductSortOption.highSelling:
        return Icons.trending_up;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'ppr':
        return Colors.green;
      case 'cpvc':
        return Colors.orange;
      case 'pvc':
        return Colors.lightBlue;
      case 'gi':
      case 'galvanized':
        return Colors.grey;
      case 'paints':
        return Colors.purple;
      case 'hardware':
        return Colors.deepOrange;
      case 'adhesives':
        return Colors.amber;
      case 'fittings':
        return Colors.teal;
      case 'electrical':
        return Colors.yellow;
      case 'plumbing':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }

  void _showCategoryFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CategoryFilterSheet(
        categories: _categories,
        selectedCategory: _selectedCategory,
        getCategoryColor: _getCategoryColor,
        onCategorySelected: (category) {
          setState(() => _selectedCategory = category);
          _filterProducts();
          Navigator.pop(context);
        },
      ),
    );
  }

  // New method to show quantity popup
  Future<void> _showQuantityDialog(Product product) async {
    // Check if product is already in cart
    bool isInCart = _selectedQuantities.containsKey(product.id);
    int currentQuantity = _selectedQuantities[product.id] ?? 1;
    double currentPrice = _customPrices[product.id] ?? product.salePrice;

    final TextEditingController qtyController = TextEditingController(
      text: currentQuantity.toString(),
    );
    final TextEditingController priceController = TextEditingController(
      text: currentPrice.toStringAsFixed(2),
    );

    // Focus node for auto-focus
    final FocusNode qtyFocusNode = FocusNode();

    final result = await showDialog<Map<String, dynamic>>(
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

              // Price input
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Price per unit',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Default: ₹${product.salePrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: '₹',
                      hintText: product.salePrice.toStringAsFixed(2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Min: ₹${_getMinimumPrice(product).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          actions: [
            // Remove from cart button (only if already in cart)
            if (isInCart)
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop({'remove': true}); // Indicates remove
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

                double? price = double.tryParse(priceController.text);
                if (price == null || price <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid price'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  return;
                }

                final minPrice = _getMinimumPrice(product);
                if (price < minPrice) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Price must be at least ₹${minPrice.toStringAsFixed(2)}',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  return;
                }

                Navigator.of(context).pop({
                  'quantity': qty,
                  'price': price,
                });
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
      if (result['remove'] == true) {
        // Remove from cart
        _removeFromCart(product.id);
      } else if (result['quantity'] != null && result['price'] != null) {
        // Add or update in cart with custom price
        _addToCartWithPrice(product, result['quantity'], result['price']);
      }
    }
  }

  void _addToCartWithPrice(Product product, int quantity, double price) {
    setState(() {
      bool wasInCart = _selectedQuantities.containsKey(product.id);
      if (!wasInCart) {
        // New item - add to order list
        _cartItemOrder.add(product.id);
      }
      _selectedQuantities[product.id] = quantity;
      _customPrices[product.id] = price;
    });

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _selectedQuantities.containsKey(product.id)
              ? 'Updated: ${product.name} (Qty: $quantity, Price: ₹${price.toStringAsFixed(2)})'
              : 'Added: ${product.name} (Qty: $quantity, Price: ₹${price.toStringAsFixed(2)})',
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

  // Show dialog to add custom item
  Future<void> _showAddCustomItemDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController amountController = TextEditingController();
    final TextEditingController quantityController = TextEditingController(text: '1');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Custom Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Item Name',
                  hintText: 'Enter item name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  hintText: 'Enter quantity',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText: 'Enter amount',
                  prefixText: '₹',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final name = nameController.text.trim();
                final amount = double.tryParse(amountController.text);
                final quantity = int.tryParse(quantityController.text) ?? 1;

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter item name'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  return;
                }

                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid amount'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  return;
                }

                if (quantity <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid quantity'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  return;
                }

                Navigator.of(context).pop({
                  'name': name,
                  'amount': amount,
                  'quantity': quantity,
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      _addCustomItem(
        result['name'],
        result['amount'],
        result['quantity'] ?? 1,
      );
    }
  }

  void _addCustomItem(String name, double amount, int quantity) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final customItem = CustomItem(
      id: id,
      name: name,
      amount: amount,
      quantity: quantity,
    );

    setState(() {
      _customItems[id] = customItem;
      _customItemOrder.add(id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added: $name (Qty: $quantity, Amount: ₹${amount.toStringAsFixed(2)})',
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _removeCustomItem(String customItemId) {
    setState(() {
      _customItems.remove(customItemId);
      _customItemOrder.remove(customItemId);
    });
  }

  void _updateCustomItem(String customItemId, {int? quantity, double? amount}) {
    final existingItem = _customItems[customItemId];
    if (existingItem != null) {
      setState(() {
        _customItems[customItemId] = existingItem.copyWith(
          quantity: quantity ?? existingItem.quantity,
          amount: amount ?? existingItem.amount,
        );
      });
    }
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
    // Add regular products
    for (final entry in _selectedQuantities.entries) {
      final price = _customPrices[entry.key] ?? 0;
      total += price * entry.value;
    }
    // Add custom items
    for (final customItem in _customItems.values) {
      total += customItem.amount * customItem.quantity;
    }
    return total;
  }

  int get _totalItemsInCart {
    return _selectedQuantities.length + _customItems.length;
  }

  /// Estimated profit for the current cart (regular products only; custom
  /// items have no known cost). Used to preview profit on a mock sale.
  double get _totalProfit {
    double profit = 0;
    for (final entry in _selectedQuantities.entries) {
      final price = _customPrices[entry.key] ?? 0;
      Product? product;
      for (final p in _allProducts) {
        if (p.id == entry.key) {
          product = p;
          break;
        }
      }
      if (product == null) continue;
      profit += (price - product.purchasePrice) * entry.value;
    }
    return profit;
  }

  /// Toggle that marks the current sale as a mock (test) sale.
  /// [afterChange] lets a modal sheet refresh its own state too.
  Widget _buildMockSaleTile({VoidCallback? afterChange}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: _isMockSale ? Colors.orange.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                _isMockSale ? Colors.orange.shade200 : Colors.grey.shade200,
          ),
        ),
        child: SwitchListTile(
          value: _isMockSale,
          onChanged: (value) {
            setState(() => _isMockSale = value);
            afterChange?.call();
          },
          dense: true,
          secondary: Icon(
            Icons.science_outlined,
            color: _isMockSale ? Colors.orange.shade700 : Colors.grey,
          ),
          title: const Text(
            'Mock sale',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            "Don't deduct stock · kept out of analytics",
            style: TextStyle(fontSize: 11),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }

  /// Estimated-profit row, shown under the total when in mock mode.
  Widget _buildEstProfitRow() {
    if (!_isMockSale) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Est. Profit',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            '₹${_totalProfit.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
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

  List<Product> get _filteredCartProducts {
    if (_cartSearchQuery.isEmpty) {
      return _selectedProductsOrdered;
    }

    return _selectedProductsOrdered.where((product) {
      final name = product.name.toLowerCase();
      final size = product.size.toLowerCase();
      return name.contains(_cartSearchQuery) || size.contains(_cartSearchQuery);
    }).toList();
  }

  List<Product> get _selectedProducts {
    return _allProducts
        .where((p) => _selectedQuantities.containsKey(p.id))
        .toList();
  }

  Future<void> _completeSale() async {
    if (_selectedQuantities.isEmpty && _customItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product or add a custom item')),
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
      // Create sale items from regular products
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

      // Add custom items to sale items
      for (final customItem in _customItems.values) {
        saleItems.add(
          SaleItem(
            productId: 'custom_${customItem.id}',
            productName: customItem.name,
            productSize: 'Custom Item',
            quantity: customItem.quantity,
            salePrice: customItem.amount,
            purchasePrice: 0, // Custom items don't have purchase price
            imageBase64: null,
          ),
        );
      }

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
        isMock: _isMockSale,
      );

      await _salesService.createSale(sale);

      if (mounted) {
        final wasMock = _isMockSale;

        // Clear form
        setState(() {
          _selectedQuantities.clear();
          _customPrices.clear();
          _cartItemOrder.clear();
          _customItems.clear();
          _customItemOrder.clear();
          _notesController.clear();
          _searchController.clear();
          _cartSearchController.clear();
          _isMockSale = false;
        });

        // Refresh products to get updated stock
        await _loadProducts();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasMock
                ? 'Mock sale saved (stock unchanged, excluded from analytics)'
                : 'Sale completed successfully!'),
            backgroundColor: wasMock ? Colors.orange.shade700 : Colors.green,
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
              label: Text(_totalItemsInCart.toString()),
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
          if (_totalItemsInCart > 0) _buildMobileBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDesktop = MediaQuery.of(context).size.width >= 1200;
    final isTablet = MediaQuery.of(context).size.width >= 600 &&
        MediaQuery.of(context).size.width < 1200;

    return Container(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
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
          // Search and Filter Row
          Row(
            children: [
              // Search bar
              Expanded(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 500 : double.infinity,
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      prefixIcon: const Icon(Icons.search, size: 22),
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
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Category Filter Button (Mobile)
              if (!isDesktop && !isTablet)
                IconButton(
                  onPressed: _showCategoryFilterSheet,
                  icon: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _selectedCategory != null
                          ? _getCategoryColor(_selectedCategory!)
                          .withOpacity(0.2)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.filter_list,
                      color: _selectedCategory != null
                          ? _getCategoryColor(_selectedCategory!)
                          : Colors.black87,
                    ),
                  ),
                ),

              // Settings Menu
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
                  if (value == 'prices') {
                    setState(() {
                      showPurchasePrices = !showPurchasePrices;
                    });
                  } else if (value.startsWith('sort_')) {
                    final sortOption = value.replaceFirst('sort_', '');
                    setState(() {
                      if (sortOption == 'newest') {
                        _currentSortOption = ProductSortOption.newest;
                      } else if (sortOption == 'lowStock') {
                        _currentSortOption = ProductSortOption.lowStock;
                      } else if (sortOption == 'highSelling') {
                        _currentSortOption = ProductSortOption.highSelling;
                      }
                      _filterProducts();
                    });
                  }
                },
                itemBuilder: (context) => [
                  // Sort options section
                  const PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'SORT BY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  _buildSortMenuItem('newest', ProductSortOption.newest),
                  _buildSortMenuItem(
                    'lowStock',
                    ProductSortOption.lowStock,
                  ),
                  _buildSortMenuItem(
                    'highSelling',
                    ProductSortOption.highSelling,
                  ),

                  const PopupMenuDivider(),

                  // Settings section
                  const PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'SETTINGS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'prices',
                    child: Row(
                      children: [
                        Icon(
                          showPurchasePrices
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 20,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          showPurchasePrices
                              ? 'Hide Purchase Prices'
                              : 'Show Purchase Prices',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Category Chips (Desktop & Tablet) + Active Filters
          if (isDesktop || isTablet) ...[
            const SizedBox(height: 16),
            _buildCategoryChipsRow(),
          ],

          // Active filters row (Mobile)
          if (!isDesktop && !isTablet) ...[
            const SizedBox(height: 12),
            _buildActiveFiltersRow(),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryChipsRow() {
    if (_isLoadingCategories) {
      return const Center(child: CircularProgressIndicator());
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // All Categories chip
        FilterChip(
          selected: _selectedCategory == null,
          label: const Text('All'),
          avatar: _selectedCategory == null
              ? null
              : const Icon(Icons.grid_view, size: 16),
          onSelected: (_) {
            setState(() {
              _selectedCategory = null;
              _filterProducts();
            });
          },
          backgroundColor: Colors.grey[200],
          selectedColor: Colors.blue.withOpacity(0.2),
          checkmarkColor: Colors.blue,
          labelStyle: TextStyle(
            color: _selectedCategory == null ? Colors.blue : Colors.black87,
            fontWeight: _selectedCategory == null
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),

        // Category chips
        ..._categories.map((category) {
          final isSelected = _selectedCategory?.toLowerCase() ==
              category.toLowerCase();
          final color = _getCategoryColor(category);

          return FilterChip(
            selected: isSelected,
            label: Text(category.toUpperCase()),
            avatar: Icon(
              Icons.category,
              size: 16,
              color: isSelected ? color : color.withOpacity(0.7),
            ),
            onSelected: (_) {
              setState(() {
                _selectedCategory = isSelected ? null : category;
                _filterProducts();
              });
            },
            backgroundColor: color.withOpacity(0.1),
            selectedColor: color.withOpacity(0.25),
            checkmarkColor: color,
            labelStyle: TextStyle(
              color: isSelected ? color : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActiveFiltersRow() {
    final hasFilters = _selectedCategory != null ||
        showPurchasePrices ||
        _currentSortOption != ProductSortOption.newest;

    if (!hasFilters) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Selected Category
          if (_selectedCategory != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: Icon(
                  Icons.category,
                  size: 16,
                  color: _getCategoryColor(_selectedCategory!),
                ),
                label: Text(_selectedCategory!.toUpperCase()),
                onDeleted: () {
                  setState(() {
                    _selectedCategory = null;
                    _filterProducts();
                  });
                },
                deleteIcon: const Icon(Icons.close, size: 16),
                backgroundColor: _getCategoryColor(_selectedCategory!)
                    .withOpacity(0.15),
                side: BorderSide.none,
              ),
            ),

          // Sort indicator
          Chip(
            avatar: Icon(
              _getSortOptionIcon(_currentSortOption),
              size: 16,
              color: Colors.blue,
            ),
            label: Text(
              _getSortOptionLabel(_currentSortOption),
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: Colors.blue.withOpacity(0.1),
            side: BorderSide.none,
          ),

          // Purchase prices indicator
          if (showPurchasePrices) ...[
            const SizedBox(width: 8),
            Chip(
              avatar: const Icon(
                Icons.currency_rupee,
                size: 16,
                color: Colors.green,
              ),
              label: const Text(
                'Purchase Prices',
                style: TextStyle(fontSize: 12),
              ),
              backgroundColor: Colors.green.withOpacity(0.1),
              side: BorderSide.none,
            ),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildSortMenuItem(
      String value,
      ProductSortOption option,
      ) {
    final isSelected = _currentSortOption == option;
    return PopupMenuItem(
      value: 'sort_$value',
      child: Row(
        children: [
          Icon(
            _getSortOptionIcon(option),
            size: 20,
            color: isSelected ? Colors.blue : Colors.grey[600],
          ),
          const SizedBox(width: 12),
          Text(
            _getSortOptionLabel(option),
            style: TextStyle(
              color: isSelected ? Colors.blue : null,
              fontWeight: isSelected ? FontWeight.bold : null,
            ),
          ),
        ],
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
          showPurchasePrice: showPurchasePrices,
          showSalesInfo: _currentSortOption == ProductSortOption.highSelling,
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
                'Cart ($_totalItemsInCart)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_totalItemsInCart > 0)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedQuantities.clear();
                      _customPrices.clear();
                      _cartItemOrder.clear();
                      _customItems.clear();
                      _customItemOrder.clear();
                      _cartSearchController.clear();
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

        // Add custom item button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showAddCustomItemDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Custom Item'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),

        // Cart search field
        if (_totalItemsInCart > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: TextField(
              controller: _cartSearchController,
              decoration: InputDecoration(
                hintText: 'Search in cart...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _cartSearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _cartSearchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
            ),
          ),

        // Cart items (in order)
        Expanded(
          child: _totalItemsInCart == 0
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
                  'Click on products or add custom items',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Regular products section
                    if (_filteredCartProducts.isNotEmpty) ...[
                      for (int i = 0; i < _filteredCartProducts.length; i++)
                        _CartItem(
                          product: _filteredCartProducts[i],
                          quantity: _selectedQuantities[_filteredCartProducts[i].id]!,
                          price: _customPrices[_filteredCartProducts[i].id]!,
                          onQuantityChanged: (qty) => _updateQuantity(_filteredCartProducts[i].id, qty),
                          onPriceChanged: (price) => _updatePrice(_filteredCartProducts[i].id, price),
                          onRemove: () => _removeFromCart(_filteredCartProducts[i].id),
                          onEdit: () => _showQuantityDialog(_filteredCartProducts[i]),
                          minimumPrice: _getMinimumPrice(_filteredCartProducts[i]),
                          itemNumber: _selectedProductsOrdered.indexOf(_filteredCartProducts[i]) + 1,
                        ),
                    ],
                    // Custom items section
                    if (_customItemOrder.isNotEmpty) ...[
                      for (int i = 0; i < _customItemOrder.length; i++)
                        if (_customItems[_customItemOrder[i]] != null)
                          _CustomCartItem(
                            customItem: _customItems[_customItemOrder[i]]!,
                            itemNumber: _selectedProductsOrdered.length + i + 1,
                            onRemove: () => _removeCustomItem(_customItemOrder[i]),
                            onQuantityChanged: (qty) => _updateCustomItem(_customItemOrder[i], quantity: qty),
                            onAmountChanged: (amount) => _updateCustomItem(_customItemOrder[i], amount: amount),
                          ),
                    ],
                  ],
                ),
        ),

        // Payment and notes
        if (_totalItemsInCart > 0) ...[
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
                _buildMockSaleTile(),
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
                _buildEstProfitRow(),
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
                          'Cart ($_totalItemsInCart items)',
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

                  // Add custom item button
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAddCustomItemDialog();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Custom Item'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),

                  // Cart search field
                  if (_totalItemsInCart > 0)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _cartSearchController,
                        decoration: InputDecoration(
                          hintText: 'Search in cart...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _cartSearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => _cartSearchController.clear(),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),

                  // Cart items
                  Expanded(
                    child: _totalItemsInCart == 0
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
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            children: [
                              // Regular products section
                              if (_filteredCartProducts.isNotEmpty) ...[
                                for (int i = 0; i < _filteredCartProducts.length; i++)
                                  _CartItem(
                                    product: _filteredCartProducts[i],
                                    quantity: _selectedQuantities[_filteredCartProducts[i].id]!,
                                    price: _customPrices[_filteredCartProducts[i].id]!,
                                    onQuantityChanged: (qty) {
                                      setState(() => _updateQuantity(_filteredCartProducts[i].id, qty));
                                      setModalState(() {});
                                    },
                                    onPriceChanged: (price) {
                                      setState(() => _updatePrice(_filteredCartProducts[i].id, price));
                                      setModalState(() {});
                                    },
                                    onRemove: () {
                                      setState(() => _removeFromCart(_filteredCartProducts[i].id));
                                      setModalState(() {});
                                    },
                                    onEdit: () {
                                      Navigator.pop(context);
                                      _showQuantityDialog(_filteredCartProducts[i]);
                                    },
                                    minimumPrice: _getMinimumPrice(_filteredCartProducts[i]),
                                    itemNumber: _selectedProductsOrdered.indexOf(_filteredCartProducts[i]) + 1,
                                  ),
                              ],
                              // Custom items section
                              if (_customItemOrder.isNotEmpty) ...[
                                for (int i = 0; i < _customItemOrder.length; i++)
                                  if (_customItems[_customItemOrder[i]] != null)
                                    _CustomCartItem(
                                      customItem: _customItems[_customItemOrder[i]]!,
                                      itemNumber: _selectedProductsOrdered.length + i + 1,
                                      onRemove: () {
                                        setState(() => _removeCustomItem(_customItemOrder[i]));
                                        setModalState(() {});
                                      },
                                      onQuantityChanged: (qty) {
                                        setState(() => _updateCustomItem(_customItemOrder[i], quantity: qty));
                                        setModalState(() {});
                                      },
                                      onAmountChanged: (amount) {
                                        setState(() => _updateCustomItem(_customItemOrder[i], amount: amount));
                                        setModalState(() {});
                                      },
                                    ),
                              ],
                            ],
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
                        _buildMockSaleTile(afterChange: () => setModalState(() {})),
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
                        _buildEstProfitRow(),
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
                    '$_totalItemsInCart items',
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
    if (_selectedQuantities.isEmpty && _customItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product or add a custom item')),
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
          isMock: _isMockSale,
        ),
      ),
    );

    // If sale was completed successfully, clear the form
    if (result == true && mounted) {
      setState(() {
        _selectedQuantities.clear();
        _customPrices.clear();
        _cartItemOrder.clear();
        _customItems.clear();
        _customItemOrder.clear();
        _notesController.clear();
        _searchController.clear();
        _cartSearchController.clear();
        _isMockSale = false;
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
    _cartSearchController.dispose();
    super.dispose();
  }
}

// Product Card Widget
class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isSelected;
  final int quantity;
  final VoidCallback onTap;
  final bool showPurchasePrice;
  final bool showSalesInfo;

  const _ProductCard({
    required this.product,
    required this.isSelected,
    required this.quantity,
    required this.onTap,
    this.showPurchasePrice = false,
    this.showSalesInfo = false,
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
                  _buildDiscountChip(),
                  if (showSalesInfo && product.totalSold > 0)
                    _buildSalesBadge(),
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
                            fontSize: 10,
                          ),
                          maxLines: 2,
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

                    // Prices
                    Column(
                      children: [
                        if (showPurchasePrice) ...[
                          _buildPriceRowWithFormat(
                            'Cost',
                            product.purchasePrice,
                            Colors.grey.shade700,
                            Icons.shopping_cart_outlined,
                          ),
                          const SizedBox(height: 4),
                        ],
                        _buildPriceRow(
                          'Sale',
                          product.salePrice,
                          Colors.green.shade700,
                          Icons.currency_rupee,
                        ),
                        if (showSalesInfo && product.totalSold > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.trending_up,
                                    size: 14,
                                    color: Colors.blue.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${product.totalSold} sold',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ],
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

  Widget _buildDiscountChip() {
    return Positioned(
      top: 32,
      left: 16,
      child: product.discountReceived != null && product.sellingDiscount != null
          ? Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              product.discountReceived?.toString() ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              product.sellingDiscount?.toString() ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      )
          : Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.purple,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          product.margin?.toString() ?? '',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSalesBadge() {
    return Positioned(
      bottom: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade700,
          borderRadius: BorderRadius.circular(12),
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
            const Icon(
              Icons.local_fire_department,
              size: 12,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              '${product.totalSold}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRowWithFormat(
      String label,
      double price,
      Color color,
      IconData icon,
      ) {
    final calculatedPrice = price / 9;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Row(
        //   children: [
        //     Icon(icon, size: 12, color: color),
        //     const SizedBox(width: 4),
        //     Text(
        //       label,
        //       style: TextStyle(
        //         fontSize: 11,
        //         color: color,
        //         fontWeight: FontWeight.w500,
        //       ),
        //     ),
        //   ],
        // ),
        Text(
          '${calculatedPrice.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow(
      String label,
      double price,
      Color color,
      IconData icon,
      ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          '₹${price.toString()}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
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

/// Mobile Category Filter Sheet with Grid Layout and Search
class _CategoryFilterSheet extends StatefulWidget {
  final List<String> categories;
  final String? selectedCategory;
  final Color Function(String) getCategoryColor;
  final Function(String?) onCategorySelected;

  const _CategoryFilterSheet({
    required this.categories,
    required this.selectedCategory,
    required this.getCategoryColor,
    required this.onCategorySelected,
  });

  @override
  State<_CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<_CategoryFilterSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredCategories = [];

  @override
  void initState() {
    super.initState();
    _filteredCategories = widget.categories;
    _searchController.addListener(_filterCategories);
  }

  void _filterCategories() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCategories = widget.categories;
      } else {
        _filteredCategories = widget.categories
            .where((cat) => cat.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filter by Category',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search categories...',
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
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // Grid of categories
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: _filteredCategories.length + 1, // +1 for "All"
                  itemBuilder: (context, index) {
                    // All Categories card
                    if (index == 0) {
                      final isSelected = widget.selectedCategory == null;
                      return _buildCategoryCard(
                        label: 'All',
                        icon: Icons.grid_view,
                        color: Colors.grey,
                        isSelected: isSelected,
                        onTap: () => widget.onCategorySelected(null),
                      );
                    }

                    // Individual category cards
                    final category = _filteredCategories[index - 1];
                    final isSelected = widget.selectedCategory?.toLowerCase() ==
                        category.toLowerCase();
                    final color = widget.getCategoryColor(category);

                    return _buildCategoryCard(
                      label: category,
                      icon: Icons.category,
                      color: color,
                      isSelected: isSelected,
                      onTap: () => widget.onCategorySelected(category),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryCard({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon with background
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.3) : color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),

            // Label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? color : Colors.black87,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Check indicator
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.check_circle,
                  color: color,
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Custom Cart Item Widget for non-inventory items
class _CustomCartItem extends StatefulWidget {
  final CustomItem customItem;
  final int itemNumber;
  final VoidCallback onRemove;
  final Function(int) onQuantityChanged;
  final Function(double) onAmountChanged;

  const _CustomCartItem({
    required this.customItem,
    required this.itemNumber,
    required this.onRemove,
    required this.onQuantityChanged,
    required this.onAmountChanged,
  });

  @override
  State<_CustomCartItem> createState() => _CustomCartItemState();
}

class _CustomCartItemState extends State<_CustomCartItem> {
  late TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.customItem.amount.toStringAsFixed(0),
    );
  }

  @override
  void didUpdateWidget(_CustomCartItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customItem.amount != widget.customItem.amount) {
      _amountController.text = widget.customItem.amount.toStringAsFixed(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = widget.customItem.amount * widget.customItem.quantity;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade200, width: 1.5),
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
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.itemNumber.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Custom item icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.note_add,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Item info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.customItem.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'CUSTOM',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Custom Item',
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
                  icon: const Icon(Icons.delete_outline, size: 18),
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quantity and amount controls
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
                              onPressed: widget.customItem.quantity > 1
                                  ? () => widget.onQuantityChanged(widget.customItem.quantity - 1)
                                  : null,
                              icon: const Icon(Icons.remove, size: 18),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                widget.customItem.quantity.toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => widget.onQuantityChanged(widget.customItem.quantity + 1),
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

                // Amount
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Amount',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                          final amount = double.tryParse(value);
                          if (amount != null && amount > 0) {
                            widget.onAmountChanged(amount);
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
                color: Colors.orange.shade50,
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
    _amountController.dispose();
    super.dispose();
  }
}