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
import '../../services/invoice_service.dart';
import '../../services/sales_service.dart';
import '../../services/settings_service.dart';
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
  final SettingsService _settingsService = SettingsService();
  final InvoiceService _invoiceService = InvoiceService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _cartSearchController = TextEditingController();
  final TextEditingController _buyerNameController = TextEditingController();
  final TextEditingController _buyerPhoneController = TextEditingController();
  final TextEditingController _buyerAddressController = TextEditingController();
  final TextEditingController _creditPaidController = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];

  // Changed to track order of items added
  Map<String, int> _selectedQuantities = {};
  Map<String, double> _customPrices = {};
  List<String> _cartItemOrder = []; // Track order of items added to cart

  // Pipe lines sold by the foot instead of by whole unit (see
  // Product.feetPerPipe) — keyed by productId, same as _customPrices. Stock
  // is deducted in whole pipes via _stockUnitsFor, not by the foot.
  Map<String, bool> _perFootItems = {};

  // Custom items (non-inventory items)
  Map<String, CustomItem> _customItems = {};
  List<String> _customItemOrder = []; // Track order of custom items

  // "Frequently bought together" suggestions for the most recently added
  // cart item, refreshed on every add-to-cart.
  String? _frequentlyBoughtSourceId;
  List<Product> _frequentlyBoughtProducts = [];

  String _searchQuery = '';
  String _cartSearchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;
  String _paymentMethod = 'Cash';

  // Category filtering
  List<String> _categories = [];
  String? _selectedCategory; // null means "All Categories"
  bool _isLoadingCategories = true;

  // Subcategory filtering (scoped to the selected category, same source data
  // used by the product-creation subcategory dropdown).
  Map<String, List<String>> _allSubcategories = {};
  String? _selectedSubcategory;

  // Size filtering (multi-select, ANDed with category)
  Set<String> _selectedSizes = {};

  // Stock filtering
  bool _inStockOnly = false;
  bool _lowStockOnly = false;

  // Recent search terms (persisted via SettingsService), shown as quick-tap
  // chips above the search field.
  List<String> _recentSearches = [];

  // Sort option
  ProductSortOption _currentSortOption = ProductSortOption.newest;

  // Show purchase prices and margin
  bool showPurchasePrices = true;

  // Mock sale: records the sale for profit review but does NOT deduct stock
  // and stays out of revenue/profit analytics.
  bool _isMockSale = false;

  // Margin & discount readout is hidden by default (it's internal-only, not
  // needed for a quick sale) — shown via a toggle when actually wanted.
  bool _showMarginSection = false;

  // Credit/buyer/mock-sale/notes card starts expanded (they're usually set
  // once per sale) — collapsible so it can be tucked away afterward.
  bool _showSaleDetails = true;

  // Blanket cart discount (0-100), applied against each item's list price
  // (product.salePrice), never printed on the bill — internal negotiating
  // tool only. The slider itself stops at breakeven (cost price) as a
  // sensible default, but manual per-item price entry has no floor at all —
  // some sales are intentionally done at a thin margin (or a loss) and
  // that's the shop owner's call, not a hardcoded rule.
  double _discountPercent = 0;

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;
  bool get _isTablet => MediaQuery.of(context).size.width >= 768;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadCategories();
    _loadRecentSearches();
    _searchController.addListener(_filterProducts);
    _cartSearchController.addListener(() {
      setState(() {
        _cartSearchQuery = _cartSearchController.text.toLowerCase();
      });
    });
  }

  Future<void> _loadRecentSearches() async {
    final searches = await _settingsService.getRecentSearches();
    if (!mounted) return;
    setState(() => _recentSearches = searches);
  }

  void _commitSearch(String term) {
    final value = term.trim();
    if (value.isEmpty) return;
    _settingsService.addRecentSearch(value);
    setState(() {
      _recentSearches.removeWhere((s) => s.toLowerCase() == value.toLowerCase());
      _recentSearches.insert(0, value);
      if (_recentSearches.length > 8) {
        _recentSearches = _recentSearches.take(8).toList();
      }
    });
  }

  void _applyRecentSearch(String term) {
    _searchController.text = term;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: _searchController.text.length),
    );
    _filterProducts();
  }

  void _removeRecentSearch(String term) {
    _settingsService.removeRecentSearch(term);
    setState(() {
      _recentSearches.removeWhere((s) => s.toLowerCase() == term.toLowerCase());
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
      final subcategories = await _firebaseService.getAllSubcategories();
      setState(() {
        _categories = categories;
        _allSubcategories = subcategories;
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

      // Filter by subcategory
      if (_selectedSubcategory != null) {
        filtered = filtered
            .where((p) => p.subcategory == _selectedSubcategory)
            .toList();
      }

      // Filter by size (multi-select, matches any selected size)
      if (_selectedSizes.isNotEmpty) {
        filtered = filtered.where((p) => _selectedSizes.contains(p.size)).toList();
      }

      // Filter by stock
      if (_inStockOnly) {
        filtered = filtered.where((p) => p.stock > 0).toList();
      }
      if (_lowStockOnly) {
        filtered = filtered.where((p) => p.stock > 0 && p.stock < 5).toList();
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

  int? _feetPerPipeFor(Product product) => product.feetPerPipe;

  // Whole stock units (pipes) a cart line should deduct: the feet requested
  // divided by feet-per-pipe, rounded up, for per-foot lines; the plain
  // quantity otherwise. Stock is allowed to go negative for per-foot sales —
  // cut-pipe remainders aren't tracked, so this never blocks the sale.
  int _stockUnitsFor(Product product, int quantity, bool isPerFoot) {
    if (!isPerFoot) return quantity;
    final feet = product.feetPerPipe;
    if (feet == null || feet <= 0) return quantity;
    return (quantity / feet).ceil();
  }

  // Distinct sizes present given a category+subcategory scope, used to
  // populate the Filters sheet's size chips.
  List<String> _availableSizesFor({String? category, String? subcategory}) {
    Iterable<Product> base = _allProducts;
    if (category != null) {
      base = base.where(
          (p) => p.category.toLowerCase() == category.toLowerCase());
    }
    if (subcategory != null) {
      base = base.where((p) => p.subcategory == subcategory);
    }
    final sizes = base
        .map((p) => p.size)
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList();
    sizes.sort();
    return sizes;
  }

  List<String> _availableSizes() => _availableSizesFor(
        category: _selectedCategory,
        subcategory: _selectedSubcategory,
      );

  // Changing category can make previously-selected sizes unavailable (and
  // invisible in the chip row), so drop any that no longer apply. Subcategory
  // is scoped to a category, so it's reset too.
  void _setCategory(String? category) {
    setState(() {
      _selectedCategory = category;
      _selectedSubcategory = null;
      final available = _availableSizes().toSet();
      _selectedSizes = _selectedSizes.intersection(available);
      _filterProducts();
    });
  }

  void _toggleSize(String size) {
    setState(() {
      if (!_selectedSizes.remove(size)) {
        _selectedSizes.add(size);
      }
      _filterProducts();
    });
  }

  // Applies a full filter selection from the Filters sheet in one shot
  // (the sheet manages its own local copy while open, then reports the
  // complete new state here on every change).
  void _applyFilters({
    required String? category,
    required String? subcategory,
    required Set<String> sizes,
    required bool inStockOnly,
    required bool lowStockOnly,
  }) {
    setState(() {
      _selectedCategory = category;
      _selectedSubcategory = subcategory;
      _selectedSizes = sizes;
      _inStockOnly = inStockOnly;
      _lowStockOnly = lowStockOnly;
      _filterProducts();
    });
  }

  int get _activeFilterCount {
    return (_selectedCategory != null ? 1 : 0) +
        (_selectedSubcategory != null ? 1 : 0) +
        _selectedSizes.length +
        (_inStockOnly ? 1 : 0) +
        (_lowStockOnly ? 1 : 0);
  }

  void _showFiltersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FiltersSheet(
        categories: _categories,
        allSubcategories: _allSubcategories,
        getCategoryColor: _getCategoryColor,
        initialCategory: _selectedCategory,
        initialSubcategory: _selectedSubcategory,
        initialSizes: _selectedSizes,
        initialInStockOnly: _inStockOnly,
        initialLowStockOnly: _lowStockOnly,
        getAvailableSizes: (category, subcategory) =>
            _availableSizesFor(category: category, subcategory: subcategory),
        onApply: _applyFilters,
      ),
    );
  }

  // New method to show quantity popup
  // Recalls how this product is typically sold (most common past quantity,
  // falling back to the last quantity it was sold in) instead of always
  // defaulting a fresh add-to-cart to 1.
  Future<int> _suggestedQuantity(String productId) async {
    final mode = await _salesService.getModeQuantity(productId);
    if (mode != null) return mode;
    final last = await _salesService.getLastQuantity(productId);
    return last ?? 1;
  }

  Future<void> _showQuantityDialog(Product product) async {
    final int? feetPerPipe = _feetPerPipeFor(product);

    // Check if product is already in cart
    bool isInCart = _selectedQuantities.containsKey(product.id);
    int currentQuantity = _selectedQuantities[product.id] ??
        await _suggestedQuantity(product.id);
    if (!mounted) return;
    bool sellPerFoot = _perFootItems[product.id] ?? false;
    double currentPrice = _customPrices[product.id] ??
        (sellPerFoot && feetPerPipe != null
            ? product.salePrice / feetPerPipe
            : product.salePrice);

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
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
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
              if (!sellPerFoot && qty > product.stock) {
                // Offer an inline stock fix instead of just blocking —
                // covers "forgot to update stock after a restock"
                // without losing anything already in the cart.
                final resolved = await _resolveInsufficientStock([product]);
                if (!resolved) return;
                if (mounted) setState(() {});
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

              Navigator.of(context).pop({
                'quantity': qty,
                'price': price,
                'isPerFoot': sellPerFoot,
              });
            }

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
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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

                    // Sell-per-foot toggle (pipe categories only)
                    if (feetPerPipe != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: sellPerFoot ? Colors.indigo.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: sellPerFoot ? Colors.indigo.shade200 : Colors.grey.shade300,
                          ),
                        ),
                        child: SwitchListTile(
                          value: sellPerFoot,
                          onChanged: (value) {
                            setDialogState(() {
                              sellPerFoot = value;
                              priceController.text = (value
                                      ? product.salePrice / feetPerPipe
                                      : product.salePrice)
                                  .toStringAsFixed(2);
                            });
                          },
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Sell per Foot',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Each pipe is $feetPerPipe ft — stock is not deducted for per-foot sales',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    Text(
                      sellPerFoot ? 'Feet' : 'Quantity',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),

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
                              hintText: sellPerFoot ? 'feet' : '1',
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            onSubmitted: (_) => submit(),
                          ),
                        ),

                        // Increase button
                        IconButton(
                          onPressed: () {
                            int currentVal = int.tryParse(qtyController.text) ?? 0;
                            if (sellPerFoot || currentVal < product.stock) {
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
                        if (!sellPerFoot && qty > product.stock) {
                          return const SizedBox.shrink();
                        }
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
                            Text(
                              sellPerFoot ? 'Price per foot' : 'Price per unit',
                              style: const TextStyle(
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
                              'Cost: ₹${product.purchasePrice.toStringAsFixed(2)}',
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
                  onPressed: submit,
                  icon: Icon(isInCart ? Icons.update : Icons.add_shopping_cart),
                  label: Text(isInCart ? 'Update' : 'Add to Cart'),
                ),
              ],
            );
          },
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
        _addToCartWithPrice(
          product,
          result['quantity'],
          result['price'],
          isPerFoot: result['isPerFoot'] == true,
        );
      }
    }
  }

  void _addToCartWithPrice(
    Product product,
    int quantity,
    double price, {
    bool isPerFoot = false,
  }) {
    setState(() {
      bool wasInCart = _selectedQuantities.containsKey(product.id);
      if (!wasInCart) {
        // New item - add to order list
        _cartItemOrder.add(product.id);
      }
      _selectedQuantities[product.id] = quantity;
      _customPrices[product.id] = price;
      _perFootItems[product.id] = isPerFoot;
    });

    _loadFrequentlyBoughtTogether(product.id);

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _selectedQuantities.containsKey(product.id)
              ? 'Updated: ${product.name} (Qty: $quantity${isPerFoot ? ' ft' : ''}, Price: ₹${price.toStringAsFixed(2)})'
              : 'Added: ${product.name} (Qty: $quantity${isPerFoot ? ' ft' : ''}, Price: ₹${price.toStringAsFixed(2)})',
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
      _perFootItems.remove(productId);
      _cartItemOrder.remove(productId);
      if (_cartItemOrder.isEmpty) {
        _frequentlyBoughtSourceId = null;
        _frequentlyBoughtProducts = [];
      }
    });
  }

  // Refreshes the "frequently bought together" strip for the item that was
  // just added, using SalesService's cached co-occurrence data (built from
  // recent sales history) rather than a fresh Firestore read every time.
  Future<void> _loadFrequentlyBoughtTogether(String productId) async {
    try {
      final related = await _salesService.getFrequentlyBoughtWith(productId, limit: 8);
      // The cart may have changed again (or moved on to a different item)
      // by the time this resolves — only apply if it's still relevant.
      if (!mounted || _cartItemOrder.isEmpty || _cartItemOrder.last != productId) {
        return;
      }

      final suggestions = <Product>[];
      for (final entry in related) {
        final product = _findProductById(entry.key);
        if (product != null && !_selectedQuantities.containsKey(product.id)) {
          suggestions.add(product);
        }
      }

      setState(() {
        _frequentlyBoughtSourceId = productId;
        _frequentlyBoughtProducts = suggestions;
      });
    } catch (e) {
      debugPrint('Error loading frequently bought together: $e');
    }
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

  // Breakeven reference price (0% margin) — used only as the quick-discount
  // slider's stopping point and as an informational "Cost" hint. There is no
  // enforced minimum margin: manual price entry can go below cost entirely
  // if that's a deliberate call (clearance, loss-leader, thin-margin deal).
  static const double _minMarginFraction = 0.0;

  double _getMinimumPrice(Product product) {
    return _effectiveUnitCost(product) / (1 - _minMarginFraction);
  }

  // Per-foot lines store feet in `quantity`, so cost/price must be scaled
  // down from the per-pipe values on Product before multiplying by quantity
  // — otherwise margin math compares a per-foot price against a per-pipe
  // cost and produces nonsense (e.g. a huge apparent loss).
  double _effectiveUnitCost(Product product) {
    if (_perFootItems[product.id] == true) {
      final feet = _feetPerPipeFor(product);
      if (feet != null && feet > 0) return product.purchasePrice / feet;
    }
    return product.purchasePrice;
  }

  double _effectiveListPrice(Product product) {
    if (_perFootItems[product.id] == true) {
      final feet = _feetPerPipeFor(product);
      if (feet != null && feet > 0) return product.salePrice / feet;
    }
    return product.salePrice;
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
      final product = _findProductById(entry.key);
      if (product == null) continue;
      profit += (price - _effectiveUnitCost(product)) * entry.value;
    }
    return profit;
  }

  /// Cart revenue at *current* (possibly discounted) prices, inventory items
  /// only — the denominator for the live blended margin %.
  double get _costBearingRevenue {
    double total = 0;
    for (final entry in _selectedQuantities.entries) {
      final product = _findProductById(entry.key);
      if (product == null) continue;
      final price = _customPrices[entry.key] ?? product.salePrice;
      total += price * entry.value;
    }
    return total;
  }

  /// Cart revenue/cost at *list* price (product.salePrice), before any
  /// discount — used to compute how much discount room is available.
  double get _listRevenue {
    double total = 0;
    for (final entry in _selectedQuantities.entries) {
      final product = _findProductById(entry.key);
      if (product == null) continue;
      total += _effectiveListPrice(product) * entry.value;
    }
    return total;
  }

  double get _listCost {
    double total = 0;
    for (final entry in _selectedQuantities.entries) {
      final product = _findProductById(entry.key);
      if (product == null) continue;
      total += _effectiveUnitCost(product) * entry.value;
    }
    return total;
  }

  /// Blended margin % across the cart at current prices: profit / revenue.
  double get _cartMarginPercent {
    final revenue = _costBearingRevenue;
    if (revenue <= 0) return 0;
    return (_totalProfit / revenue) * 100;
  }

  /// Highest discount % (off list price, uniformly) before the *blended*
  /// margin would reach breakeven (0%) — the slider's stopping point.
  /// Manual per-item price entry (the Add/Edit dialog, or completing a sale)
  /// has no such limit; this only bounds the quick-discount slider itself.
  double get _maxDiscountPercent {
    final revenue = _listRevenue;
    final cost = _listCost;
    if (revenue <= 0) return 0;
    final maxFraction = 1 - (cost / (revenue * (1 - _minMarginFraction)));
    return (maxFraction * 100).clamp(0, 100).toDouble();
  }

  /// Applies a uniform discount off each item's list price via the slider,
  /// stopping each item at its own breakeven (cost) price. This is just the
  /// slider's own ceiling for a sensible quick-discount UX — it does not
  /// restrict manual price entry elsewhere.
  void _applyDiscountPercent(double discountPercent) {
    setState(() {
      _discountPercent = discountPercent;
      for (final entry in _selectedQuantities.entries) {
        final product = _findProductById(entry.key);
        if (product == null) continue;
        final floor = _getMinimumPrice(product);
        final target = _effectiveListPrice(product) * (1 - discountPercent / 100);
        _customPrices[entry.key] = target < floor ? floor : target;
      }
    });
  }

  /// Toggle that marks the current sale as a mock (test) sale.
  /// [afterChange] lets a modal sheet refresh its own state too.
  /// Optional buyer contact fields (kept collapsed by default so a quick
  /// walk-in cash sale isn't slowed down) plus, when Credit is the selected
  /// payment method, an "amount received now" field for partial upfront
  /// payment. Shared between the desktop side panel and the mobile bottom
  /// sheet, same pattern as [_buildMockSaleTile].
  /// Lays cart item tiles out two-per-row. Uses a [Wrap] (not GridView) so
  /// each row's height follows its tallest tile instead of a fixed
  /// aspect-ratio guess — avoids clipping/overflow when a tile's content
  /// (e.g. the "PER FOOT" badge) makes it taller than usual.
  Widget _buildCartItemsGrid(List<Widget> tiles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 0,
          children: [
            for (final tile in tiles) SizedBox(width: itemWidth, child: tile),
          ],
        );
      },
    );
  }

  Widget _buildBuyerAndCreditSection({VoidCallback? afterChange}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text(
                'Buyer Details (optional)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'For future reference on the bill',
                style: TextStyle(fontSize: 11),
              ),
              children: [
                TextField(
                  controller: _buyerNameController,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _buyerPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _buyerAddressController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Address',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_paymentMethod == 'Credit') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _creditPaidController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount received now (optional)',
                hintText: '0',
                prefixText: '₹',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Every sale is Cash unless this is checked, in which case it's Credit.
  /// Replaces the old Cash/UPI/Card/Credit/Other picker — UPI/Card/Other are
  /// no longer offered here (still supported for editing older sales).
  Widget _buildCreditCheckbox({VoidCallback? afterChange}) {
    final isCredit = _paymentMethod == 'Credit';
    return CheckboxListTile(
      value: isCredit,
      onChanged: (value) {
        setState(() => _paymentMethod = (value ?? false) ? 'Credit' : 'Cash');
        afterChange?.call();
      },
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      visualDensity: VisualDensity.compact,
      title: const Text(
        'Credit sale (pay later)',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: const Text(
        'Unchecked = Cash',
        style: TextStyle(fontSize: 10),
      ),
    );
  }

  /// One-line summary shown when the sale-details card is collapsed, so the
  /// current state (payment method, buyer, mock) is still visible at a
  /// glance without expanding it back open.
  String get _saleDetailsSummary {
    final parts = <String>[_paymentMethod];
    final buyerName = _buyerNameController.text.trim();
    if (buyerName.isNotEmpty) parts.add(buyerName);
    if (_isMockSale) parts.add('Mock');
    return parts.join(' · ');
  }

  /// Credit checkbox + buyer details + mock sale + notes, all in one card
  /// that can be collapsed once set (they're usually set once per sale and
  /// then left alone while items are added/edited).
  Widget _buildSaleDetailsCard({
    required Color backgroundColor,
    VoidCallback? afterChange,
  }) {
    if (_totalItemsInCart == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() => _showSaleDetails = !_showSaleDetails);
              afterChange?.call();
            },
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sale Details',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (!_showSaleDetails)
                  Flexible(
                    child: Text(
                      _saleDetailsSummary,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                Icon(
                  _showSaleDetails ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Colors.grey.shade700,
                ),
              ],
            ),
          ),
          if (_showSaleDetails) ...[
            _buildCreditCheckbox(afterChange: afterChange),
            _buildBuyerAndCreditSection(afterChange: afterChange),
            _buildMockSaleTile(afterChange: afterChange),
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
        ],
      ),
    );
  }

  Widget _buildMockSaleTile({VoidCallback? afterChange}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Tooltip(
        message: "Don't deduct stock · kept out of analytics",
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: _isMockSale ? Colors.orange.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  _isMockSale ? Colors.orange.shade200 : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.science_outlined,
                size: 16,
                color: _isMockSale ? Colors.orange.shade700 : Colors.grey,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Mock sale',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: _isMockSale,
                  onChanged: (value) {
                    setState(() => _isMockSale = value);
                    afterChange?.call();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Internal-only margin readout + discount slider, shown under the total
  /// on every sale (mock or real) — never rendered on the printed bill,
  /// since bill_preview_screen only ever reads item name/size/qty/price.
  /// Collapsed by default — a compact toggle that reveals
  /// [_buildMarginDiscountSection] (margin readout + discount slider) only
  /// when tapped, so it doesn't eat space on a quick sale.
  Widget _buildMarginSectionToggle({VoidCallback? afterChange}) {
    if (_selectedQuantities.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() => _showMarginSection = !_showMarginSection);
            afterChange?.call();
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  _showMarginSection ? 'Hide Margin' : 'Show Margin',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                ),
                Icon(
                  _showMarginSection
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: Colors.blue.shade700,
                ),
              ],
            ),
          ),
        ),
        if (_showMarginSection) _buildMarginDiscountSection(afterChange: afterChange),
      ],
    );
  }

  Widget _buildMarginDiscountSection({VoidCallback? afterChange}) {
    if (_selectedQuantities.isEmpty) return const SizedBox.shrink();

    final marginPercent = _cartMarginPercent;
    final maxDiscount = _maxDiscountPercent;
    final sliderValue = _discountPercent.clamp(0, maxDiscount).toDouble();
    final marginColor = marginPercent < 0
        ? Colors.red.shade700
        : marginPercent >= 20
            ? Colors.green.shade700
            : Colors.orange.shade700;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your Margin',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              Text(
                '₹${_totalProfit.toStringAsFixed(2)} (${marginPercent.toStringAsFixed(1)}%)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: marginColor,
                ),
              ),
            ],
          ),
          if (maxDiscount >= 0.5) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Special Discount',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Row(
                  children: [
                    Text(
                      '${_discountPercent.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    if (_discountPercent > 0)
                      IconButton(
                        onPressed: () {
                          _applyDiscountPercent(0);
                          afterChange?.call();
                        },
                        icon: const Icon(Icons.replay, size: 16),
                        tooltip: 'Reset discount',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.only(left: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                min: 0,
                max: maxDiscount,
                divisions: maxDiscount.round().clamp(1, 100),
                value: sliderValue,
                label: '${sliderValue.toStringAsFixed(0)}%',
                onChanged: (value) {
                  _applyDiscountPercent(value);
                  afterChange?.call();
                },
              ),
            ),
            Text(
              'Slider stops at cost price — type a price below cost manually if needed. Never shown on the bill.',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
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
    }

    // _selectedProducts is _allProducts filtered down to cart productIds —
    // if a cart item's product can no longer be found there (deleted, or
    // _allProducts went stale), it would silently drop out of saleItems
    // below while _totalAmount (computed straight from the cart maps) still
    // includes its price. That saves a sale with a total that doesn't match
    // its item list — and an empty-looking bill if it happens to every item.
    // Fail loudly instead of saving a mismatched sale.
    if (_selectedProducts.length != _selectedQuantities.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Some cart items could not be found (they may have been deleted). '
            'Please remove them from the cart and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Create sale items from regular products, in cart order (not
      // _selectedProducts' catalog order) so the saved sale's item list
      // matches the order they were actually added.
      final saleItems = _selectedProductsOrdered.map((product) {
        final quantity = _selectedQuantities[product.id]!;
        final isPerFoot = _perFootItems[product.id] ?? false;
        return SaleItem(
          productId: product.id,
          productName: product.name,
          productSize: product.size,
          quantity: quantity,
          salePrice: _customPrices[product.id]!,
          purchasePrice: _effectiveUnitCost(product),
          imageBase64: product.imageBase64,
          isPerFoot: isPerFoot,
          stockUnits: _stockUnitsFor(product, quantity, isPerFoot),
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
        case 'credit':
          paymentMethodEnum = PaymentMethod.credit;
          break;
        default:
          paymentMethodEnum = PaymentMethod.other;
      }

      final invoiceNumber = await _invoiceService.getNextInvoiceNumber();

      final sale = Sale(
        id: '',
        invoiceNumber: invoiceNumber,
        items: saleItems,
        totalAmount: _totalAmount,
        paymentMethod: paymentMethodEnum,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        isMock: _isMockSale,
        buyerName: _buyerNameController.text.trim().isEmpty
            ? null
            : _buyerNameController.text.trim(),
        buyerPhone: _buyerPhoneController.text.trim().isEmpty
            ? null
            : _buyerPhoneController.text.trim(),
        buyerAddress: _buyerAddressController.text.trim().isEmpty
            ? null
            : _buyerAddressController.text.trim(),
        amountPaid: paymentMethodEnum == PaymentMethod.credit
            ? (double.tryParse(_creditPaidController.text) ?? 0)
            : null,
      );

      await _salesService.createSale(sale);

      if (mounted) {
        final wasMock = _isMockSale;

        // Clear form
        setState(() {
          _selectedQuantities.clear();
          _customPrices.clear();
          _perFootItems.clear();
          _cartItemOrder.clear();
          _customItems.clear();
          _customItemOrder.clear();
          _notesController.clear();
          _buyerNameController.clear();
          _buyerPhoneController.clear();
          _buyerAddressController.clear();
          _creditPaidController.clear();
          _searchController.clear();
          _cartSearchController.clear();
          _isMockSale = false;
          _discountPercent = 0;
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
    final Widget layout;
    if (_isDesktop) {
      layout = _buildDesktopLayout();
    } else if (_isTablet) {
      layout = _buildTabletLayout();
    } else {
      layout = _buildMobileLayout();
    }

    // Confirm before leaving if there's anything in the cart, so an
    // accidental back-press (or browser back on web) doesn't silently
    // discard an in-progress sale.
    return PopScope(
      canPop: _totalItemsInCart == 0,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirmed = await _confirmDiscardCart();
        if (confirmed && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: layout,
    );
  }

  Future<bool> _confirmDiscardCart() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Discard sale?'),
        content: Text(
          '$_totalItemsInCart item${_totalItemsInCart == 1 ? '' : 's'} in your cart '
          'will be lost if you go back now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
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
                  _buildSuggestionsSection(),
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
            _buildSuggestionsSection(),
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
          _buildSuggestionsSection(),
          Expanded(child: _buildProductGrid()),
          if (_totalItemsInCart > 0) _buildMobileBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDesktop = MediaQuery.of(context).size.width >= 1200;

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
          if (_searchQuery.isEmpty && _recentSearches.isNotEmpty) ...[
            _buildRecentSearchChips(),
            const SizedBox(height: 12),
          ],

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
                    onSubmitted: _commitSearch,
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

              // Filters button (category, subcategory, size, stock — all
              // live inside one sheet so this row never grows).
              IconButton(
                onPressed: _isLoadingCategories ? null : _showFiltersSheet,
                icon: Badge(
                  label: Text('$_activeFilterCount'),
                  isLabelVisible: _activeFilterCount > 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _activeFilterCount > 0
                          ? Colors.blue.withOpacity(0.15)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _isLoadingCategories
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.filter_list,
                            color: _activeFilterCount > 0
                                ? Colors.blue.shade700
                                : Colors.black87,
                          ),
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

          // Active filter chips — one compact row, same on every layout.
          // All the actual controls (category, subcategory, size, stock)
          // live in the Filters sheet so this never grows past one row.
          if (_activeFilterCount > 0) ...[
            const SizedBox(height: 12),
            _buildActiveFilterChips(),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentSearchChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _recentSearches.map((term) {
        return InputChip(
          avatar: const Icon(Icons.history, size: 16),
          label: Text(term),
          onPressed: () => _applyRecentSearch(term),
          onDeleted: () => _removeRecentSearch(term),
          deleteIcon: const Icon(Icons.close, size: 16),
          backgroundColor: Colors.grey[100],
          side: BorderSide.none,
        );
      }).toList(),
    );
  }

  // Compact, single-row summary of active filters (category, subcategory,
  // sizes, stock toggles) — each independently removable. Replaces what used
  // to be several always-visible chip rows/Wraps; the actual pickers now
  // live entirely inside the Filters sheet.
  Widget _buildActiveFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
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
                onDeleted: () => _setCategory(null),
                deleteIcon: const Icon(Icons.close, size: 16),
                backgroundColor: _getCategoryColor(_selectedCategory!)
                    .withOpacity(0.15),
                side: BorderSide.none,
              ),
            ),

          if (_selectedSubcategory != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: const Icon(Icons.label_outline, size: 16, color: Colors.indigo),
                label: Text(_selectedSubcategory!),
                onDeleted: () {
                  setState(() {
                    _selectedSubcategory = null;
                    _filterProducts();
                  });
                },
                deleteIcon: const Icon(Icons.close, size: 16),
                backgroundColor: Colors.indigo.withOpacity(0.15),
                side: BorderSide.none,
              ),
            ),

          ..._selectedSizes.map((size) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: const Icon(Icons.straighten, size: 16, color: Colors.blue),
                  label: Text(size),
                  onDeleted: () => _toggleSize(size),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  backgroundColor: Colors.blue.withOpacity(0.15),
                  side: BorderSide.none,
                ),
              )),

          if (_inStockOnly)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: const Icon(Icons.inventory_2_outlined, size: 16, color: Colors.green),
                label: const Text('In Stock Only'),
                onDeleted: () {
                  setState(() {
                    _inStockOnly = false;
                    _filterProducts();
                  });
                },
                deleteIcon: const Icon(Icons.close, size: 16),
                backgroundColor: Colors.green.withOpacity(0.15),
                side: BorderSide.none,
              ),
            ),

          if (_lowStockOnly)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                label: const Text('Low Stock'),
                onDeleted: () {
                  setState(() {
                    _lowStockOnly = false;
                    _filterProducts();
                  });
                },
                deleteIcon: const Icon(Icons.close, size: 16),
                backgroundColor: Colors.orange.withOpacity(0.15),
                side: BorderSide.none,
              ),
            ),
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

  // Finds a product by id in the currently loaded catalog, or null if it's
  // been removed/not yet loaded.
  Product? _findProductById(String id) {
    for (final p in _allProducts) {
      if (p.id == id) return p;
    }
    return null;
  }

  Product? get _lastAddedProduct {
    if (_cartItemOrder.isEmpty) return null;
    return _findProductById(_cartItemOrder.last);
  }

  // Combines both suggestion strips shown above the product grid. Kept as a
  // single insertion point so all three responsive layouts stay untouched.
  Widget _buildSuggestionsSection() {
    final strips = <Widget?>[
      _buildFrequentlyBoughtStrip(),
      _buildSimilarItemsStrip(),
    ].whereType<Widget>().toList();

    if (strips.isEmpty) return const SizedBox.shrink();
    return Column(children: strips);
  }

  // "Frequently Bought Together" — learned from past sales baskets via
  // SalesService's co-occurrence cache, keyed to the most recently added
  // cart item. Excludes anything already in the cart.
  Widget? _buildFrequentlyBoughtStrip() {
    final reference = _lastAddedProduct;
    if (reference == null || _frequentlyBoughtSourceId != reference.id) {
      return null;
    }
    if (_frequentlyBoughtProducts.isEmpty) return null;

    return _buildSuggestionStrip(
      title: 'Frequently Bought Together',
      icon: Icons.auto_awesome,
      products: _frequentlyBoughtProducts,
    );
  }

  // "More in <size> <category>" — same category+size as the most recently
  // added cart item, so a job that needs several fittings of one size is
  // fast to keep building without re-searching each time.
  Widget? _buildSimilarItemsStrip() {
    final reference = _lastAddedProduct;
    if (reference == null) return null;

    final similar = _allProducts.where((p) =>
        p.id != reference.id &&
        p.category.toLowerCase() == reference.category.toLowerCase() &&
        p.size == reference.size).toList();

    if (similar.isEmpty) return null;

    return _buildSuggestionStrip(
      title: 'More in ${reference.size} ${reference.category}',
      icon: Icons.category_outlined,
      products: similar,
    );
  }

  Widget _buildSuggestionStrip({
    required String title,
    required IconData icon,
    required List<Product> products,
  }) {
    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final product = products[index];
                return _SuggestionCard(
                  product: product,
                  isInCart: _selectedQuantities.containsKey(product.id),
                  onTap: () => _showQuantityDialog(product),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
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
        crossAxisCount: _isDesktop ? 6 : (_isTablet ? 4 : 3),
        childAspectRatio: 0.5,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
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
                      _perFootItems.clear();
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
                    _buildCartItemsGrid([
                      // Regular products
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
                          isPerFoot: _perFootItems[_filteredCartProducts[i].id] ?? false,
                          itemNumber: _selectedProductsOrdered.indexOf(_filteredCartProducts[i]) + 1,
                        ),
                      // Custom items
                      for (int i = 0; i < _customItemOrder.length; i++)
                        if (_customItems[_customItemOrder[i]] != null)
                          _CustomCartItem(
                            customItem: _customItems[_customItemOrder[i]]!,
                            itemNumber: _selectedProductsOrdered.length + i + 1,
                            onRemove: () => _removeCustomItem(_customItemOrder[i]),
                            onQuantityChanged: (qty) => _updateCustomItem(_customItemOrder[i], quantity: qty),
                            onAmountChanged: (amount) => _updateCustomItem(_customItemOrder[i], amount: amount),
                          ),
                    ]),
                    // Payment/buyer/mock/notes — scrolls together with the
                    // cart items instead of being pinned outside the
                    // Expanded, so an expanded margin/buyer section can't
                    // overflow past the bottom of the panel.
                    _buildSaleDetailsCard(backgroundColor: Colors.white),
                  ],
                ),
        ),

        // Total and action buttons — pinned footer, always visible
        if (_totalItemsInCart > 0) ...[
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
                _buildMarginSectionToggle(),
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
                              _buildCartItemsGrid([
                                // Regular products
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
                                    isPerFoot: _perFootItems[_filteredCartProducts[i].id] ?? false,
                                    itemNumber: _selectedProductsOrdered.indexOf(_filteredCartProducts[i]) + 1,
                                  ),
                                // Custom items
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
                              ]),
                              // Payment/buyer/mock/notes — scrolls with the
                              // cart items instead of being pinned outside
                              // the Expanded, so an expanded margin/buyer
                              // section can't overflow past the sheet.
                              _buildSaleDetailsCard(
                                backgroundColor: Colors.grey.shade50,
                                afterChange: () => setModalState(() {}),
                              ),
                            ],
                          ),
                  ),

                  // Total and action buttons — pinned footer, always visible
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
                        _buildMarginSectionToggle(
                          afterChange: () => setModalState(() {}),
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

  /// Shown when the cart has items whose quantity exceeds the product's
  /// recorded stock (typically because the real stock was never updated
  /// after a restock). Lets the user correct each product's stock right
  /// here — writing it to Firestore and to [_allProducts] — without losing
  /// the cart, then continue with whatever action triggered the check.
  /// Returns true once every product has been fixed, false if cancelled.
  Future<bool> _resolveInsufficientStock(List<Product> insufficientProducts) async {
    final controllers = {
      for (final product in insufficientProducts)
        product.id: TextEditingController(
          text: (_selectedQuantities[product.id] ?? product.stock).toString(),
        ),
    };
    bool isSaving = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Insufficient Stock'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Update the real stock below, then continue — your cart won't be lost.",
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    for (final product in insufficientProducts) ...[
                      Text(
                        '${product.name} (${product.size})',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        'Currently ${product.stock} in stock · cart needs ${_selectedQuantities[product.id]}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: controllers[product.id],
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'New stock',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            for (final product in insufficientProducts) {
                              final newStock = int.tryParse(controllers[product.id]!.text);
                              if (newStock == null || newStock < 0) {
                                throw Exception('Enter a valid stock number for ${product.name}');
                              }
                              final updated = product.copyWith(stock: newStock);
                              await _firebaseService.updateProduct(updated);
                              final index = _allProducts.indexWhere((p) => p.id == product.id);
                              if (index != -1) _allProducts[index] = updated;
                            }
                            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  icon: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(isSaving ? 'Saving...' : 'Save & Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }

    return result ?? false;
  }

  Future<void> _showBillPreview() async {
    if (_selectedQuantities.isEmpty && _customItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product or add a custom item')),
      );
      return;
    }

    // Validate stock — skipped for per-foot lines, since their quantity is
    // feet, not units, and doesn't compare against product.stock. Collect
    // every shortfall at once (not just the first) so the fix dialog below
    // can offer all of them together instead of one at a time.
    final insufficientProducts = <Product>[];
    for (final entry in _selectedQuantities.entries) {
      final productId = entry.key;
      final quantity = entry.value;
      final product = _allProducts.firstWhere((p) => p.id == productId);

      if (_perFootItems[productId] == true) continue;

      if (quantity > product.stock) {
        insufficientProducts.add(product);
      }
    }

    if (insufficientProducts.isNotEmpty) {
      final resolved = await _resolveInsufficientStock(insufficientProducts);
      if (!resolved || !mounted) return;
      setState(() {}); // refresh product grid with the corrected stock
    }

    // Prepare data for bill preview, in cart order — BillPreviewScreen
    // builds the saved sale's item list from this map's iteration order.
    final Map<String, Product> selectedProducts = {};
    final Map<String, double> unitCosts = {};
    final Map<String, int> stockUnitsMap = {};
    for (final product in _selectedProductsOrdered) {
      final productId = product.id;
      selectedProducts[productId] = product;
      unitCosts[productId] = _effectiveUnitCost(product);
      stockUnitsMap[productId] = _stockUnitsFor(
        product,
        _selectedQuantities[productId]!,
        _perFootItems[productId] ?? false,
      );
    }

    // Navigate to bill preview
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => BillPreviewScreen(
          products: selectedProducts,
          quantities: _selectedQuantities,
          prices: _customPrices,
          perFootItems: _perFootItems,
          unitCosts: unitCosts,
          stockUnitsMap: stockUnitsMap,
          paymentMethod: _paymentMethod,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          isMock: _isMockSale,
          buyerName: _buyerNameController.text.trim().isEmpty
              ? null
              : _buyerNameController.text.trim(),
          buyerPhone: _buyerPhoneController.text.trim().isEmpty
              ? null
              : _buyerPhoneController.text.trim(),
          buyerAddress: _buyerAddressController.text.trim().isEmpty
              ? null
              : _buyerAddressController.text.trim(),
          initialPayment: _paymentMethod == 'Credit'
              ? (double.tryParse(_creditPaidController.text) ?? 0)
              : 0,
        ),
      ),
    );

    // If sale was completed successfully, clear the form
    if (result == true && mounted) {
      setState(() {
        _selectedQuantities.clear();
        _customPrices.clear();
        _perFootItems.clear();
        _cartItemOrder.clear();
        _customItems.clear();
        _customItemOrder.clear();
        _notesController.clear();
        _searchController.clear();
        _cartSearchController.clear();
        _buyerNameController.clear();
        _buyerPhoneController.clear();
        _buyerAddressController.clear();
        _creditPaidController.clear();
        _isMockSale = false;
        _discountPercent = 0;
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
    _buyerNameController.dispose();
    _buyerPhoneController.dispose();
    _buyerAddressController.dispose();
    _creditPaidController.dispose();
    super.dispose();
  }
}

// Compact horizontal card used by suggestion strips (similar items,
// frequently bought together) — narrower than _ProductCard since it scrolls
// horizontally in a fixed-height row rather than sitting in the main grid.
class _SuggestionCard extends StatelessWidget {
  final Product product;
  final bool isInCart;
  final VoidCallback onTap;

  const _SuggestionCard({
    required this.product,
    required this.isInCart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOutOfStock = product.stock == 0;

    return SizedBox(
      width: 120,
      child: Card(
        elevation: isInCart ? 3 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isInCart ? Colors.blue : Colors.grey.shade200,
            width: isInCart ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  product.size,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isOutOfStock ? 'Out of stock' : '₹${product.salePrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isOutOfStock ? Colors.red : Colors.green.shade700,
                      ),
                    ),
                    if (isInCart)
                      const Icon(Icons.check_circle, size: 14, color: Colors.blue),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        // Tapping while out of stock still opens the quantity dialog —
        // it routes into the insufficient-stock fix flow instead of a dead tap.
        onTap: onTap,
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
                padding: const EdgeInsets.all(7),
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
                            fontSize: 9,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          product.size,
                          style: TextStyle(
                            fontSize: 9,
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
                          const SizedBox(height: 2),
                        ],
                        _buildPriceRow(
                          'Sale',
                          product.salePrice,
                          Colors.green.shade700,
                          Icons.currency_rupee,
                        ),
                        if (showSalesInfo && product.totalSold > 0) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.trending_up,
                                    size: 10,
                                    color: Colors.blue.shade700,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${product.totalSold} sold',
                                    style: TextStyle(
                                      fontSize: 9,
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
        size: 28,
        color: Colors.grey.shade400,
      ),
    );
  }

  Widget _buildStockBadge(bool isOutOfStock, bool isLowStock) {
    if (!isOutOfStock && !isLowStock) return const SizedBox.shrink();

    return Positioned(
      top: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isOutOfStock
              ? Colors.red.shade500
              : Colors.orange.shade500,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          isOutOfStock ? 'Out' : 'Low: ${product.stock}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip() {
    if (product.category.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: getCategoryColor(product.category),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          product.category.toUpperCase(),
          style: TextStyle(
            color: getCategoryTextColor(product.category),
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedBadge() {
    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
        child: Column(
          children: [
            const Icon(
              Icons.check,
              color: Colors.white,
              size: 12,
            ),
            if (quantity > 0) ...[
              Text(
                quantity.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
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
      top: 20,
      left: 4,
      child: product.discountReceived != null && product.sellingDiscount != null
          ? Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              product.discountReceived?.toString() ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 8,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              product.sellingDiscount?.toString() ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 8,
              ),
            ),
          ),
        ],
      )
          : Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.purple,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          product.margin?.toString() ?? '',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 8,
          ),
        ),
      ),
    );
  }

  Widget _buildSalesBadge() {
    return Positioned(
      bottom: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.shade700,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_fire_department,
              size: 9,
              color: Colors.white,
            ),
            const SizedBox(width: 2),
            Text(
              '${product.totalSold}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 8,
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
            fontSize: 10,
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
        Icon(icon, size: 9, color: color),
        Text(
          '₹${price.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 10,
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
  final bool isPerFoot;
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
    this.isPerFoot = false,
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
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with item number
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.itemNumber.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ),
                 // Product image
               const SizedBox(width: 8),
                // Product info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(
                            widget.product.size,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (widget.isPerFoot)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.indigo.shade200),
                              ),
                              child: Text(
                                'PER FOOT',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade700,
                                ),
                              ),
                            ),

                          IconButton(
                            onPressed: widget.onEdit,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(foregroundColor: Colors.blue),
                          ),
                          IconButton(
                            onPressed: widget.onRemove,
                            icon: const Icon(Icons.delete_outline, size: 16),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(foregroundColor: Colors.red),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Actions

              ],
            ),
            const SizedBox(height: 8),

            // Quantity control
            Text(
              widget.isPerFoot ? 'Feet' : 'Quantity',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
            const SizedBox(height: 3),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.isPerFoot
                      ? Colors.indigo.shade200
                      : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.quantity > 1
                        ? () => widget.onQuantityChanged(widget.quantity - 1)
                        : null,
                    icon: const Icon(Icons.remove, size: 16),
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                  ),
                  Expanded(
                    child: Text(
                      widget.isPerFoot
                          ? '${widget.quantity} ft'
                          : widget.quantity.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.isPerFoot ||
                            widget.quantity < widget.product.stock
                        ? () => widget.onQuantityChanged(widget.quantity + 1)
                        : null,
                    icon: const Icon(Icons.add, size: 16),
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Price control
            Text(
              'Price',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
            const SizedBox(height: 3),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: '₹',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (value) {
                final price = double.tryParse(value);
                if (price != null && price > 0) {
                  widget.onPriceChanged(price);
                }
              },
            ),

            // Subtotal
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                      fontSize: 11,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '₹${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
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
// Consolidated Filters sheet: category, subcategory, size, and stock all in
// one place, so the main screen only ever shows a single "Filters" trigger
// plus one row of active-filter chips instead of several stacked rows. Every
// change here is applied to the parent immediately via [onApply] — the sheet
// keeps its own local copy purely so its own UI (this modal route) rebuilds
// live, since a parent setState doesn't automatically rebuild a pushed route.
class _FiltersSheet extends StatefulWidget {
  final List<String> categories;
  final Map<String, List<String>> allSubcategories;
  final Color Function(String) getCategoryColor;
  final String? initialCategory;
  final String? initialSubcategory;
  final Set<String> initialSizes;
  final bool initialInStockOnly;
  final bool initialLowStockOnly;
  final List<String> Function(String? category, String? subcategory)
      getAvailableSizes;
  final void Function({
    required String? category,
    required String? subcategory,
    required Set<String> sizes,
    required bool inStockOnly,
    required bool lowStockOnly,
  }) onApply;

  const _FiltersSheet({
    required this.categories,
    required this.allSubcategories,
    required this.getCategoryColor,
    required this.initialCategory,
    required this.initialSubcategory,
    required this.initialSizes,
    required this.initialInStockOnly,
    required this.initialLowStockOnly,
    required this.getAvailableSizes,
    required this.onApply,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  final TextEditingController _categorySearchController =
      TextEditingController();
  List<String> _filteredCategories = [];

  late String? _category;
  late String? _subcategory;
  late Set<String> _sizes;
  late bool _inStockOnly;
  late bool _lowStockOnly;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _subcategory = widget.initialSubcategory;
    _sizes = Set.of(widget.initialSizes);
    _inStockOnly = widget.initialInStockOnly;
    _lowStockOnly = widget.initialLowStockOnly;
    _filteredCategories = widget.categories;
    _categorySearchController.addListener(_filterCategories);
  }

  void _filterCategories() {
    final query = _categorySearchController.text.toLowerCase();
    setState(() {
      _filteredCategories = query.isEmpty
          ? widget.categories
          : widget.categories
              .where((cat) => cat.toLowerCase().contains(query))
              .toList();
    });
  }

  @override
  void dispose() {
    _categorySearchController.dispose();
    super.dispose();
  }

  void _notifyParent() {
    widget.onApply(
      category: _category,
      subcategory: _subcategory,
      sizes: _sizes,
      inStockOnly: _inStockOnly,
      lowStockOnly: _lowStockOnly,
    );
  }

  void _selectCategory(String? category) {
    final available =
        widget.getAvailableSizes(category, null).toSet();
    setState(() {
      _category = category;
      _subcategory = null;
      _sizes = _sizes.intersection(available);
    });
    _notifyParent();
  }

  void _selectSubcategory(String sub) {
    setState(() => _subcategory = _subcategory == sub ? null : sub);
    _notifyParent();
  }

  void _toggleSize(String size) {
    setState(() {
      if (!_sizes.remove(size)) _sizes.add(size);
    });
    _notifyParent();
  }

  void _toggleInStock() {
    setState(() => _inStockOnly = !_inStockOnly);
    _notifyParent();
  }

  void _toggleLowStock() {
    setState(() => _lowStockOnly = !_lowStockOnly);
    _notifyParent();
  }

  void _clearAll() {
    setState(() {
      _category = null;
      _subcategory = null;
      _sizes = {};
      _inStockOnly = false;
      _lowStockOnly = false;
    });
    _notifyParent();
  }

  @override
  Widget build(BuildContext context) {
    final sizes = widget.getAvailableSizes(_category, _subcategory);
    final subcategories =
        _category != null ? (widget.allSubcategories[_category] ?? []) : const <String>[];
    final hasActiveFilters = _category != null ||
        _subcategory != null ||
        _sizes.isNotEmpty ||
        _inStockOnly ||
        _lowStockOnly;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
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
                    'Filters',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      if (hasActiveFilters)
                        TextButton(
                          onPressed: _clearAll,
                          child: const Text('Clear All'),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    const Text(
                      'CATEGORY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _categorySearchController,
                      decoration: InputDecoration(
                        hintText: 'Search categories...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _categorySearchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () =>
                                    _categorySearchController.clear(),
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
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        // Slightly taller than square: some category names
                        // (e.g. "Sanitary General") wrap to 2 lines and would
                        // overflow a perfectly square cell once the selected
                        // checkmark is also shown.
                        childAspectRatio: 0.85,
                      ),
                      itemCount: _filteredCategories.length + 1, // +1 for "All"
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _buildCategoryCard(
                            label: 'All',
                            icon: Icons.grid_view,
                            color: Colors.grey,
                            isSelected: _category == null,
                            onTap: () => _selectCategory(null),
                          );
                        }

                        final category = _filteredCategories[index - 1];
                        final isSelected =
                            _category?.toLowerCase() == category.toLowerCase();
                        final color = widget.getCategoryColor(category);

                        return _buildCategoryCard(
                          label: category,
                          icon: Icons.category,
                          color: color,
                          isSelected: isSelected,
                          onTap: () => _selectCategory(category),
                        );
                      },
                    ),

                    if (subcategories.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'SUBCATEGORY',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: subcategories.map((sub) {
                          final isSelected = _subcategory == sub;
                          return FilterChip(
                            selected: isSelected,
                            label: Text(sub),
                            avatar: Icon(
                              Icons.label_outline,
                              size: 16,
                              color: isSelected ? Colors.indigo : Colors.grey[600],
                            ),
                            onSelected: (_) => _selectSubcategory(sub),
                            backgroundColor: Colors.grey[100],
                            selectedColor: Colors.indigo.withOpacity(0.2),
                            checkmarkColor: Colors.indigo,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.indigo : Colors.black87,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    if (sizes.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'SIZE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: sizes.map((size) {
                          final isSelected = _sizes.contains(size);
                          return FilterChip(
                            selected: isSelected,
                            label: Text(size),
                            avatar: Icon(
                              Icons.straighten,
                              size: 16,
                              color: isSelected ? Colors.blue : Colors.grey[600],
                            ),
                            onSelected: (_) => _toggleSize(size),
                            backgroundColor: Colors.grey[100],
                            selectedColor: Colors.blue.withOpacity(0.2),
                            checkmarkColor: Colors.blue,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.blue : Colors.black87,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 24),
                    const Text(
                      'STOCK',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          selected: _inStockOnly,
                          label: const Text('In Stock Only'),
                          avatar: Icon(
                            Icons.inventory_2_outlined,
                            size: 16,
                            color: _inStockOnly ? Colors.green : Colors.grey[600],
                          ),
                          onSelected: (_) => _toggleInStock(),
                          backgroundColor: Colors.grey[100],
                          selectedColor: Colors.green.withOpacity(0.2),
                          checkmarkColor: Colors.green,
                          labelStyle: TextStyle(
                            color: _inStockOnly ? Colors.green : Colors.black87,
                            fontWeight:
                                _inStockOnly ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        FilterChip(
                          selected: _lowStockOnly,
                          label: const Text('Low Stock'),
                          avatar: Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: _lowStockOnly ? Colors.orange : Colors.grey[600],
                          ),
                          onSelected: (_) => _toggleLowStock(),
                          backgroundColor: Colors.grey[100],
                          selectedColor: Colors.orange.withOpacity(0.2),
                          checkmarkColor: Colors.orange,
                          labelStyle: TextStyle(
                            color: _lowStockOnly ? Colors.orange : Colors.black87,
                            fontWeight:
                                _lowStockOnly ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
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
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade200, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with item number
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.itemNumber.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Custom item icon
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.note_add,
                    color: Colors.orange.shade700,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),

                // Item info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.customItem.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'CUSTOM',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Remove button
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Quantity control
            Text(
              'Quantity',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
            const SizedBox(height: 3),
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
                    icon: const Icon(Icons.remove, size: 16),
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                  ),
                  Expanded(
                    child: Text(
                      widget.customItem.quantity.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => widget.onQuantityChanged(widget.customItem.quantity + 1),
                    icon: const Icon(Icons.add, size: 16),
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Amount control
            Text(
              'Amount',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
            const SizedBox(height: 3),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '₹',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (value) {
                final amount = double.tryParse(value);
                if (amount != null && amount > 0) {
                  widget.onAmountChanged(amount);
                }
              },
            ),

            // Subtotal
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                      fontSize: 11,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '₹${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
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