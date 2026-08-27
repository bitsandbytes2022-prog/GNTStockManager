import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/product_model.dart';
import '../../models/sale_model.dart';
import '../../services/firebase_service.dart';
import '../../services/sales_service.dart';
import '../../services/settings_service.dart';
import 'add_product_screen.dart';
import 'add_product_web_screen.dart';
import 'bill_preview_screen.dart';

enum ProductSortOption { newest, lowStock, highSelling }

// Custom item class for non-inventory items. Mirrors RecordSaleScreen's
// CustomItem so a sale saved from either screen round-trips the same way.
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

/// One resolved, independent cart line. The same product can appear as more
/// than one _CartLine (e.g. the original sale already had it twice, or the
/// editor adds another line for it) — each keeps its own quantity/price/
/// per-foot flag rather than merging into a shared total. Mirrors
/// RecordSaleScreen's _CartLine so edit and record stay consistent.
class _CartLine {
  final String lineKey;
  final Product product;
  final int quantity;
  final double price;
  final bool isPerFoot;

  const _CartLine({
    required this.lineKey,
    required this.product,
    required this.quantity,
    required this.price,
    required this.isPerFoot,
  });
}

class EditSaleScreen extends StatefulWidget {
  final Sale sale;

  const EditSaleScreen({super.key, required this.sale});

  @override
  State<EditSaleScreen> createState() => _EditSaleScreenState();
}

class _EditSaleScreenState extends State<EditSaleScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final SalesService _salesService = SalesService();
  final SettingsService _settingsService = SettingsService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _cartSearchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _buyerNameController = TextEditingController();
  final TextEditingController _buyerPhoneController = TextEditingController();
  final TextEditingController _buyerAddressController = TextEditingController();
  final TextEditingController _amountPaidController = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];

  // The cart holds independent *lines*, not one slot per product — the same
  // product can appear more than once (already true of the original sale in
  // some cases, and now also possible by adding it again during editing).
  // Every map below is keyed by a synthetic lineKey (see _newLineKey), not
  // by productId; _lineProductId resolves a lineKey back to the real
  // product. Mirrors RecordSaleScreen's cart model.
  Map<String, int> _selectedQuantities = {};
  Map<String, double> _customPrices = {};

  /// lineKey -> sold-by-length (pipes cut to feet). Quantity for these
  /// products is feet, not units — see Product.feetPerPipe.
  Map<String, bool> _perFootItems = {};

  /// Tracks line order (original sale order, then append-on-add) so the
  /// saved sale's item list isn't silently reshuffled into product-catalog
  /// order — see _cartLines below.
  List<String> _cartItemOrder = [];
  Map<String, String> _lineProductId = {}; // lineKey -> productId
  int _lineKeyCounter = 0;

  // Custom (non-inventory) items — a SaleItem with productId 'custom_<id>'
  // round-trips back into one of these on load; see sales_service.dart's
  // unitsByProduct, which already skips these for stock purposes.
  Map<String, CustomItem> _customItems = {};
  List<String> _customItemOrder = [];

  String _searchQuery = '';
  String _cartSearchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;
  String _paymentMethod = 'Cash';

  // Category filtering
  List<String> _categories = [];
  String? _selectedCategory;
  bool _isLoadingCategories = true;

  // Subcategory filtering (scoped to the selected category).
  Map<String, List<String>> _allSubcategories = {};
  String? _selectedSubcategory;

  // Size filtering (multi-select, ANDed with category)
  Set<String> _selectedSizes = {};

  // Quick category picker (left-side rail: PPR / CPVC / PVC / GI).
  static const List<String> _quickCategories = ['PPR', 'CPVC', 'PVC', 'GI'];
  String? _quickCategory;
  String? _quickGiType;
  String? _quickSize;

  // Stock filtering
  bool _inStockOnly = false;
  bool _lowStockOnly = false;

  // Recent search terms (persisted via SettingsService).
  List<String> _recentSearches = [];

  ProductSortOption _currentSortOption = ProductSortOption.newest;

  bool showPurchasePrices = true;

  // Mock sale: records the sale for profit review but does NOT deduct stock
  // and stays out of revenue/profit analytics. Seeded from the original
  // sale, but — unlike record_sale_screen — editable here too, since fixing
  // a sale that was wrongly marked mock (or vice versa) is a legitimate edit.
  bool _isMockSale = false;

  bool _showMarginSection = false;
  bool _showSaleDetails = true;

  // Blanket cart discount (0-100), applied against each item's list price.
  // See _minMarginFraction below — there is no enforced minimum margin.
  double _discountPercent = 0;

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;
  bool get _isTablet => MediaQuery.of(context).size.width >= 768;

  // ==========================================
  // CART LINE HELPERS
  // ==========================================
  String _newLineKey(String productId) => '${productId}_L${_lineKeyCounter++}';

  bool _isProductInCart(String productId) =>
      _lineProductId.values.contains(productId);

  int _cartQuantityForProduct(String productId) {
    var total = 0;
    for (final key in _cartItemOrder) {
      if (_lineProductId[key] == productId) {
        total += _selectedQuantities[key] ?? 0;
      }
    }
    return total;
  }

  double? _lastPriceForProduct(String productId) {
    for (final key in _cartItemOrder.reversed) {
      if (_lineProductId[key] == productId) return _customPrices[key];
    }
    return null;
  }

  bool _lastPerFootForProduct(String productId) {
    for (final key in _cartItemOrder.reversed) {
      if (_lineProductId[key] == productId) return _perFootItems[key] ?? false;
    }
    return false;
  }

  // ==========================================
  // STOCK-CEILING ADJUSTMENT (edit-specific — see class doc comment below)
  // ==========================================
  // product.stock already reflects what THIS sale originally deducted (it
  // was deducted when the sale was first created), so it understates true
  // headroom when re-editing a line that was already part of this sale.
  // SalesService.updateSale itself is delta-based (old items vs new items)
  // and is unaffected by this — this is purely so the UI's own guardrails
  // and displays don't falsely block/flag a valid re-edit of a product this
  // same sale already holds most (or all) of the stock for.
  late final Map<String, int> _originalStockUnitsByProduct = () {
    final totals = <String, int>{};
    for (final item in widget.sale.items) {
      if (item.productId.startsWith('custom_')) continue;
      totals[item.productId] =
          (totals[item.productId] ?? 0) + item.effectiveStockUnits;
    }
    return totals;
  }();

  int _effectiveStock(Product product) =>
      product.stock + (_originalStockUnitsByProduct[product.id] ?? 0);

  @override
  void initState() {
    super.initState();
    _initializeFromSale();
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

  void _initializeFromSale() {
    _paymentMethod = widget.sale.paymentMethod.label;
    _notesController.text = widget.sale.notes ?? '';
    _buyerNameController.text = widget.sale.buyerName ?? '';
    _buyerPhoneController.text = widget.sale.buyerPhone ?? '';
    _buyerAddressController.text = widget.sale.buyerAddress ?? '';
    _amountPaidController.text = widget.sale.amountPaid.toStringAsFixed(2);
    _isMockSale = widget.sale.isMock;

    // Populate selected items, preserving the original sale's item order.
    // Each sale item becomes its own cart line — if the original sale
    // already had a product on more than one line, that must stay intact
    // rather than collapsing into one combined entry. Custom (non-catalog)
    // items are routed into _customItems instead of a product line.
    for (final item in widget.sale.items) {
      if (item.productId.startsWith('custom_')) {
        final id = item.productId.substring('custom_'.length);
        _customItemOrder.add(id);
        _customItems[id] = CustomItem(
          id: id,
          name: item.productName,
          amount: item.salePrice,
          quantity: item.quantity,
        );
        continue;
      }
      final lineKey = _newLineKey(item.productId);
      _cartItemOrder.add(lineKey);
      _lineProductId[lineKey] = item.productId;
      _selectedQuantities[lineKey] = item.quantity;
      _customPrices[lineKey] = item.salePrice;
      _perFootItems[lineKey] = item.isPerFoot;
    }
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

  /// Lets a product missing from the catalog be added without losing the
  /// edit in progress.
  Future<void> _navigateToAddProduct() async {
    final result = await Navigator.push<Product>(
      context,
      MaterialPageRoute(
        builder: (_) => kIsWeb ? AddProductWebScreen() : AddProductScreen(),
      ),
    );
    if (result == null || !mounted) return;
    await _loadProducts();
    if (!mounted) return;
    await _showQuantityDialog(result);
  }

  void _filterProducts() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      var filtered = _allProducts;

      if (_selectedCategory != null) {
        filtered = filtered
            .where((p) => p.category.toLowerCase() == _selectedCategory!.toLowerCase())
            .toList();
      }

      if (_selectedSubcategory != null) {
        filtered = filtered.where((p) => p.subcategory == _selectedSubcategory).toList();
      }

      if (_selectedSizes.isNotEmpty) {
        filtered = filtered.where((p) => _selectedSizes.contains(p.size)).toList();
      }

      if (_inStockOnly) {
        filtered = filtered.where((p) => p.stock > 0).toList();
      }
      if (_lowStockOnly) {
        filtered = filtered.where((p) => p.stock > 0 && p.stock < 5).toList();
      }

      if (_searchQuery.isNotEmpty) {
        final queryWords = _searchQuery.split(' ').where((w) => w.isNotEmpty);
        filtered = filtered.where((product) {
          final name = product.name.toLowerCase();
          final size = product.size.toLowerCase();
          return queryWords.every((word) => name.contains(word) || size.contains(word));
        }).toList();
      }

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

  int _stockUnitsFor(Product product, int quantity, bool isPerFoot) {
    if (!isPerFoot) return quantity;
    final feet = product.feetPerPipe;
    if (feet == null || feet <= 0) return quantity;
    return (quantity / feet).ceil();
  }

  List<String> _availableSizesFor({String? category, String? subcategory}) {
    Iterable<Product> base = _allProducts;
    if (category != null) {
      base = base.where((p) => p.category.toLowerCase() == category.toLowerCase());
    }
    if (subcategory != null) {
      base = base.where((p) => p.subcategory == subcategory);
    }
    final sizes = base.map((p) => p.size).where((s) => s.trim().isNotEmpty).toSet().toList();
    sizes.sort();
    return sizes;
  }

  List<String> _availableSizes() => _availableSizesFor(
        category: _selectedCategory,
        subcategory: _selectedSubcategory,
      );

  bool _matchesQuickCategory(Product p, String target) {
    final category = p.category.toLowerCase();
    final t = target.toLowerCase();
    if (category == t) return true;
    return category == 'sanitary' && (p.subcategory?.toLowerCase() == t);
  }

  bool _isNippleProduct(Product p) =>
      (p.subcategory ?? '').toLowerCase().contains('nipple') ||
      p.name.toLowerCase().contains('nipple');

  bool _matchesQuickGiType(Product p) {
    if (_quickCategory != 'GI') return true;
    return _isNippleProduct(p) == (_quickGiType == 'Nipple');
  }

  List<String> _quickAvailableSizes() {
    if (_quickCategory == null) return [];
    final sizes = _allProducts
        .where((p) => _matchesQuickCategory(p, _quickCategory!) && _matchesQuickGiType(p))
        .map((p) => p.size)
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList();
    sizes.sort();
    return sizes;
  }

  List<Product> _quickFilteredProducts() {
    if (_quickCategory == null) return [];
    if (_quickSize == null && _searchQuery.isEmpty) return [];

    var products = _allProducts.where((p) =>
        _matchesQuickCategory(p, _quickCategory!) && _matchesQuickGiType(p));

    if (_quickSize != null) {
      products = products.where((p) => p.size == _quickSize);
    }

    if (_searchQuery.isNotEmpty) {
      final queryWords = _searchQuery.split(' ').where((w) => w.isNotEmpty);
      products = products.where((product) {
        final name = product.name.toLowerCase();
        final size = product.size.toLowerCase();
        return queryWords.every((word) => name.contains(word) || size.contains(word));
      });
    }

    return products.toList();
  }

  void _setQuickCategory(String category) {
    setState(() {
      if (_quickCategory == category) {
        _quickCategory = null;
        _quickGiType = null;
      } else {
        _quickCategory = category;
        _quickGiType = category == 'GI' ? 'Fitting' : null;
      }
      _quickSize = null;
    });
  }

  void _setQuickGiType(String type) {
    setState(() {
      _quickGiType = type;
      _quickSize = null;
    });
  }

  void _setQuickSize(String? size) {
    setState(() => _quickSize = size);
  }

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

  // Finds a product by id in the currently loaded catalog, or null if it's
  // been removed/not yet loaded.
  Product? _findProductById(String id) {
    for (final p in _allProducts) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Tapping a product in the browse grid always adds a fresh cart line.
  Future<void> _showQuantityDialog(Product product) =>
      _showAddOrEditLineDialog(product);

  /// Editing/removing one specific existing cart line, opened from the cart
  /// panel itself rather than the browse grid.
  Future<void> _showEditLineDialog(String lineKey) {
    final productId = _lineProductId[lineKey];
    final product = productId != null ? _findProductById(productId) : null;
    if (product == null) {
      _removeFromCart(lineKey);
      return Future.value();
    }
    return _showAddOrEditLineDialog(product, editingLineKey: lineKey);
  }

  Future<void> _showAddOrEditLineDialog(
    Product product, {
    String? editingLineKey,
  }) async {
    final int? feetPerPipe = _feetPerPipeFor(product);
    final bool isEditingExisting = editingLineKey != null;
    final int availableStock = _effectiveStock(product);

    final int alreadyElsewhere = _cartQuantityForProduct(product.id) -
        (isEditingExisting ? (_selectedQuantities[editingLineKey] ?? 0) : 0);

    int currentQuantity = isEditingExisting ? _selectedQuantities[editingLineKey]! : 1;
    if (!mounted) return;
    bool sellPerFoot = isEditingExisting
        ? (_perFootItems[editingLineKey] ?? false)
        : _lastPerFootForProduct(product.id);
    double currentPrice = isEditingExisting
        ? _customPrices[editingLineKey]!
        : (_lastPriceForProduct(product.id) ??
            (sellPerFoot && feetPerPipe != null
                ? product.salePrice / feetPerPipe
                : product.salePrice));

    final TextEditingController qtyController =
        TextEditingController(text: currentQuantity.toString());
    final TextEditingController priceController =
        TextEditingController(text: currentPrice.toStringAsFixed(2));
    final FocusNode qtyFocusNode = FocusNode();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final remainingStock =
                (availableStock - alreadyElsewhere).clamp(0, availableStock);

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
              if (!sellPerFoot && (alreadyElsewhere + qty) > availableStock) {
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
                    isEditingExisting
                        ? 'Edit Item'
                        : (alreadyElsewhere > 0 ? 'Add More' : 'Add to Cart'),
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: availableStock < 5 ? Colors.orange.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: availableStock < 5
                              ? Colors.orange.shade200
                              : Colors.green.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 16,
                            color: availableStock < 5 ? Colors.orange : Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Available Stock: $availableStock',
                                  style: TextStyle(
                                    color: availableStock < 5
                                        ? Colors.orange.shade700
                                        : Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (alreadyElsewhere > 0)
                                  Text(
                                    'Already $alreadyElsewhere in cart from earlier',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
                    Row(
                      children: [
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
                        Expanded(
                          child: TextField(
                            controller: qtyController,
                            focusNode: qtyFocusNode,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              hintText: sellPerFoot ? 'feet' : '1',
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            onSubmitted: (_) => submit(),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            int currentVal = int.tryParse(qtyController.text) ?? 0;
                            if (sellPerFoot || currentVal < remainingStock) {
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
                    Wrap(
                      spacing: 8,
                      children: [1, 5, 10, 25, 50].map((qty) {
                        if (!sellPerFoot && qty > remainingStock) {
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
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              sellPerFoot ? 'Price per foot' : 'Price per unit',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Default: ₹${product.salePrice.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              'Cost: ₹${product.purchasePrice.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                if (isEditingExisting)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop({'remove': true});
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Remove', style: TextStyle(color: Colors.red)),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: submit,
                  icon: Icon(isEditingExisting ? Icons.update : Icons.add_shopping_cart),
                  label: Text(isEditingExisting ? 'Update' : 'Add to Cart'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      qtyFocusNode.requestFocus();
      qtyController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: qtyController.text.length,
      );
    });

    if (result != null) {
      if (result['remove'] == true) {
        if (editingLineKey != null) _removeFromCart(editingLineKey);
      } else if (result['quantity'] != null && result['price'] != null) {
        _addToCartWithPrice(
          product,
          result['quantity'],
          result['price'],
          isPerFoot: result['isPerFoot'] == true,
          editLineKey: editingLineKey,
        );
      }
    }
  }

  void _addToCartWithPrice(
    Product product,
    int quantity,
    double price, {
    bool isPerFoot = false,
    String? editLineKey,
  }) {
    setState(() {
      final lineKey = editLineKey ?? _newLineKey(product.id);
      if (editLineKey == null) {
        _cartItemOrder.add(lineKey);
        _lineProductId[lineKey] = product.id;
      }
      _selectedQuantities[lineKey] = quantity;
      _customPrices[lineKey] = price;
      _perFootItems[lineKey] = isPerFoot;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          editLineKey != null
              ? 'Updated: ${product.name} (Qty: $quantity${isPerFoot ? ' ft' : ''}, Price: ₹${price.toStringAsFixed(2)})'
              : 'Added: ${product.name} (Qty: $quantity${isPerFoot ? ' ft' : ''}, Price: ₹${price.toStringAsFixed(2)})',
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _removeFromCart(String lineKey) {
    setState(() {
      _selectedQuantities.remove(lineKey);
      _customPrices.remove(lineKey);
      _perFootItems.remove(lineKey);
      _lineProductId.remove(lineKey);
      _cartItemOrder.remove(lineKey);
    });
  }

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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText: 'Enter amount',
                  prefixText: '₹',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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

                Navigator.of(context).pop({'name': name, 'amount': amount, 'quantity': quantity});
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      _addCustomItem(result['name'], result['amount'], result['quantity'] ?? 1);
    }
  }

  void _addCustomItem(String name, double amount, int quantity) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final customItem = CustomItem(id: id, name: name, amount: amount, quantity: quantity);

    setState(() {
      _customItems[id] = customItem;
      _customItemOrder.add(id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added: $name (Qty: $quantity, Amount: ₹${amount.toStringAsFixed(2)})'),
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

  void _updateQuantity(String lineKey, int quantity) {
    if (quantity <= 0) {
      _removeFromCart(lineKey);
    } else {
      setState(() {
        _selectedQuantities[lineKey] = quantity;
      });
    }
  }

  void _updatePrice(String lineKey, double price) {
    setState(() {
      _customPrices[lineKey] = price;
    });
  }

  // Breakeven reference price (0% margin) — used only as the quick-discount
  // slider's stopping point and as an informational "Cost" hint. There is no
  // enforced minimum margin: manual price entry can go below cost entirely
  // if that's a deliberate call (clearance, loss-leader, thin-margin deal).
  // Matches record_sale_screen's current policy — see project memory
  // project_margin_policy.md (an earlier 15% floor was deliberately reversed).
  static const double _minMarginFraction = 0.0;

  double _getMinimumPrice(Product product, bool isPerFoot) {
    return _effectiveUnitCost(product, isPerFoot) / (1 - _minMarginFraction);
  }

  double _effectiveUnitCost(Product product, bool isPerFoot) {
    if (isPerFoot) {
      final feet = _feetPerPipeFor(product);
      if (feet != null && feet > 0) return product.purchasePrice / feet;
    }
    return product.purchasePrice;
  }

  double _effectiveListPrice(Product product, bool isPerFoot) {
    if (isPerFoot) {
      final feet = _feetPerPipeFor(product);
      if (feet != null && feet > 0) return product.salePrice / feet;
    }
    return product.salePrice;
  }

  double get _totalAmount {
    double total = 0;
    for (final line in _cartLines) {
      total += line.price * line.quantity;
    }
    for (final customItem in _customItems.values) {
      total += customItem.amount * customItem.quantity;
    }
    return total;
  }

  int get _totalItemsInCart => _selectedQuantities.length + _customItems.length;

  double get _totalProfit {
    double profit = 0;
    for (final line in _cartLines) {
      profit += (line.price - _effectiveUnitCost(line.product, line.isPerFoot)) * line.quantity;
    }
    return profit;
  }

  double get _costBearingRevenue {
    double total = 0;
    for (final line in _cartLines) {
      total += line.price * line.quantity;
    }
    return total;
  }

  double get _listRevenue {
    double total = 0;
    for (final line in _cartLines) {
      total += _effectiveListPrice(line.product, line.isPerFoot) * line.quantity;
    }
    return total;
  }

  double get _listCost {
    double total = 0;
    for (final line in _cartLines) {
      total += _effectiveUnitCost(line.product, line.isPerFoot) * line.quantity;
    }
    return total;
  }

  double get _cartMarginPercent {
    final revenue = _costBearingRevenue;
    if (revenue <= 0) return 0;
    return (_totalProfit / revenue) * 100;
  }

  double get _maxDiscountPercent {
    final revenue = _listRevenue;
    final cost = _listCost;
    if (revenue <= 0) return 0;
    final maxFraction = 1 - (cost / (revenue * (1 - _minMarginFraction)));
    return (maxFraction * 100).clamp(0, 100).toDouble();
  }

  void _applyDiscountPercent(double discountPercent) {
    setState(() {
      _discountPercent = discountPercent;
      for (final line in _cartLines) {
        final floor = _getMinimumPrice(line.product, line.isPerFoot);
        final target =
            _effectiveListPrice(line.product, line.isPerFoot) * (1 - discountPercent / 100);
        _customPrices[line.lineKey] = target < floor ? floor : target;
      }
    });
  }

  /// Lays cart item tiles out two-per-row, matching RecordSaleScreen.
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

  /// Buyer name/phone/address plus, when Payment Method is Credit, an
  /// editable "amount received so far" field — needed for fixing a sale
  /// that was logged under the wrong payment method or partially settled
  /// since. Unlike RecordSaleScreen's amount field (which starts at 0 and
  /// represents a *new* incremental payment), this edits the sale's running
  /// total amountPaid directly — the right semantics for correcting an
  /// existing sale rather than recording a fresh one.
  Widget _buildBuyerAndCreditFields({VoidCallback? afterChange}) {
    return Column(
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (_) => afterChange?.call(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _buyerPhoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _buyerAddressController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Address',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        if (_paymentMethod == 'Credit') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _amountPaidController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount received so far',
              helperText: 'Set to 0 if nothing has been received yet',
              prefixText: '₹',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ],
    );
  }

  /// Full Cash/UPI/Card/Credit/Other picker — kept as a dropdown (rather
  /// than RecordSaleScreen's binary Cash/Credit checkbox) so editing an
  /// older sale that used UPI/Card/Other doesn't silently collapse its
  /// payment method down to Cash or Credit on save.
  Widget _buildPaymentMethodDropdown({VoidCallback? afterChange}) {
    return DropdownButtonFormField<String>(
      value: _paymentMethod,
      decoration: InputDecoration(
        labelText: 'Payment Method',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: ['Cash', 'UPI', 'Card', 'Credit', 'Other']
          .map((method) => DropdownMenuItem(value: method, child: Text(method)))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _paymentMethod = value);
          afterChange?.call();
        }
      },
    );
  }

  /// One-line summary shown when the sale-details card is collapsed.
  String get _saleDetailsSummary {
    final parts = <String>[_paymentMethod];
    final buyerName = _buyerNameController.text.trim();
    if (buyerName.isNotEmpty) parts.add(buyerName);
    if (_isMockSale) parts.add('Mock');
    return parts.join(' · ');
  }

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
            const SizedBox(height: 8),
            _buildPaymentMethodDropdown(afterChange: afterChange),
            const SizedBox(height: 12),
            _buildBuyerAndCreditFields(afterChange: afterChange),
            _buildMockSaleTile(afterChange: afterChange),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Notes (Optional)',
                hintText: 'Add any notes...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
              color: _isMockSale ? Colors.orange.shade200 : Colors.grey.shade200,
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
                  _showMarginSection ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: marginColor),
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

  List<_CartLine> get _cartLines {
    final lines = <_CartLine>[];
    for (final key in _cartItemOrder) {
      final productId = _lineProductId[key];
      if (productId == null) continue;
      final product = _findProductById(productId);
      if (product == null) continue; // Product no longer in the catalog.
      final quantity = _selectedQuantities[key];
      final price = _customPrices[key];
      if (quantity == null || price == null) continue;
      lines.add(_CartLine(
        lineKey: key,
        product: product,
        quantity: quantity,
        price: price,
        isPerFoot: _perFootItems[key] ?? false,
      ));
    }
    return lines;
  }

  List<_CartLine> get _filteredCartLines {
    if (_cartSearchQuery.isEmpty) return _cartLines;
    final queryWords = _cartSearchQuery.split(' ').where((w) => w.isNotEmpty);
    return _cartLines.where((line) {
      final name = line.product.name.toLowerCase();
      final size = line.product.size.toLowerCase();
      return queryWords.every((word) => name.contains(word) || size.contains(word));
    }).toList();
  }

  Future<void> _updateSale() async {
    if (_selectedQuantities.isEmpty && _customItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product or add a custom item')),
      );
      return;
    }

    // _cartLines resolves each cart line's product from _allProducts — if a
    // line's product can no longer be found there, it silently drops out of
    // updatedSaleItems below while the sale's total still reflects it. Fail
    // loudly instead of saving a sale whose items no longer match its total.
    if (_cartLines.length != _cartItemOrder.length) {
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
      final updatedSaleItems = _cartLines.map((line) {
        final product = line.product;
        final isPerFoot = line.isPerFoot;
        return SaleItem(
          productId: product.id,
          productName: product.name,
          productSize: product.size,
          quantity: line.quantity,
          salePrice: line.price,
          purchasePrice: _effectiveUnitCost(product, isPerFoot),
          imageBase64: product.imageBase64,
          isPerFoot: isPerFoot,
          stockUnits: _stockUnitsFor(product, line.quantity, isPerFoot),
        );
      }).toList();

      // Fold custom items back in, same convention as RecordSaleScreen
      // (and the same one _initializeFromSale reads back on load).
      for (final customItem in _customItems.values) {
        updatedSaleItems.add(
          SaleItem(
            productId: 'custom_${customItem.id}',
            productName: customItem.name,
            productSize: 'Custom Item',
            quantity: customItem.quantity,
            salePrice: customItem.amount,
            purchasePrice: 0,
            imageBase64: null,
          ),
        );
      }

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

      final total = updatedSaleItems.fold<double>(
        0.0,
        (sum, item) => sum + (item.salePrice * item.quantity),
      );

      final amountPaid = paymentMethodEnum == PaymentMethod.credit
          ? (double.tryParse(_amountPaidController.text) ?? widget.sale.amountPaid)
          : null;

      final updatedSale = Sale(
        invoiceNumber: widget.sale.invoiceNumber,
        id: widget.sale.id,
        items: updatedSaleItems,
        totalAmount: total,
        createdAt: widget.sale.createdAt, // Keep original creation date
        paymentMethod: paymentMethodEnum,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        isMock: _isMockSale,
        buyerName:
            _buyerNameController.text.trim().isEmpty ? null : _buyerNameController.text.trim(),
        buyerPhone:
            _buyerPhoneController.text.trim().isEmpty ? null : _buyerPhoneController.text.trim(),
        buyerAddress: _buyerAddressController.text.trim().isEmpty
            ? null
            : _buyerAddressController.text.trim(),
        amountPaid: amountPaid,
        payments: widget.sale.payments,
      );

      await _salesService.updateSale(widget.sale, updatedSale, const {});

      if (mounted) {
        Navigator.pop(context, true);
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
          SnackBar(content: Text('Error updating sale: $e'), backgroundColor: Colors.red),
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

  String get _appBarSubtitle =>
      'Sale from ${DateFormat('MMM dd, yyyy hh:mm a').format(widget.sale.createdAt)}';

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Sale'),
            Text(_appBarSubtitle, style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _navigateToAddProduct,
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Add missing product',
          ),
        ],
      ),
      body: Row(
        children: [
          _buildQuickCategoryRail(),
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
          Container(
            width: 400,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(left: BorderSide(color: Colors.grey.shade200)),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Sale'),
            Text(_appBarSubtitle, style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _navigateToAddProduct,
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Add missing product',
          ),
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
      body: Row(
        children: [
          _buildQuickCategoryRail(),
          Expanded(
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  _buildSearchBar(),
                  Expanded(child: _buildProductGrid()),
                  if (_totalItemsInCart > 0) _buildMobileBottomBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Sale'),
            Text(DateFormat('MMM dd, yyyy').format(widget.sale.createdAt),
                style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _navigateToAddProduct,
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Add missing product',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildQuickCategoryBar(),
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
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_searchQuery.isEmpty && _recentSearches.isNotEmpty) ...[
            _buildRecentSearchChips(),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: Container(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 500 : double.infinity),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _isLoadingCategories ? null : _showFiltersSheet,
                icon: Badge(
                  label: Text('$_activeFilterCount'),
                  isLabelVisible: _activeFilterCount > 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _activeFilterCount > 0 ? Colors.blue.withOpacity(0.15) : Colors.grey[100],
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
                            color: _activeFilterCount > 0 ? Colors.blue.shade700 : Colors.black87,
                          ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.more_vert),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (value) {
                  if (value == 'prices') {
                    setState(() => showPurchasePrices = !showPurchasePrices);
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
                  const PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'SORT BY',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                  _buildSortMenuItem('newest', ProductSortOption.newest),
                  _buildSortMenuItem('lowStock', ProductSortOption.lowStock),
                  _buildSortMenuItem('highSelling', ProductSortOption.highSelling),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'SETTINGS',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'prices',
                    child: Row(
                      children: [
                        Icon(
                          showPurchasePrices ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 12),
                        Text(showPurchasePrices ? 'Hide Purchase Prices' : 'Show Purchase Prices'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
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

  Widget _buildActiveFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (_selectedCategory != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: Icon(Icons.category, size: 16, color: _getCategoryColor(_selectedCategory!)),
                label: Text(_selectedCategory!.toUpperCase()),
                onDeleted: () => _setCategory(null),
                deleteIcon: const Icon(Icons.close, size: 16),
                backgroundColor: _getCategoryColor(_selectedCategory!).withOpacity(0.15),
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

  PopupMenuItem<String> _buildSortMenuItem(String value, ProductSortOption option) {
    final isSelected = _currentSortOption == option;
    return PopupMenuItem(
      value: 'sort_$value',
      child: Row(
        children: [
          Icon(_getSortOptionIcon(option), size: 20, color: isSelected ? Colors.blue : Colors.grey[600]),
          const SizedBox(width: 12),
          Text(
            _getSortOptionLabel(option),
            style: TextStyle(color: isSelected ? Colors.blue : null, fontWeight: isSelected ? FontWeight.bold : null),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickCategoryRail() {
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          for (final category in _quickCategories) ...[
            _buildQuickCategoryButton(category),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickCategoryBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          for (final category in _quickCategories) ...[
            Expanded(child: _buildQuickCategoryButton(category)),
            if (category != _quickCategories.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickCategoryButton(String category) {
    final color = _getCategoryColor(category);
    final selected = _quickCategory == category;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _setQuickCategory(category),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : Colors.grey.shade300, width: selected ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.plumbing, color: selected ? color : Colors.grey.shade500, size: 20),
            const SizedBox(height: 4),
            Text(
              category,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? color : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickGrid() {
    final sizes = _quickAvailableSizes();
    final products = _quickFilteredProducts();
    final color = _getCategoryColor(_quickCategory!);
    final label = _quickCategory == 'GI' && _quickGiType != null
        ? '$_quickCategory $_quickGiType'
        : _quickCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_quickCategory == 'GI')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                for (final type in const ['Fitting', 'Nipple']) ...[
                  ChoiceChip(
                    label: Text(type),
                    selected: _quickGiType == type,
                    onSelected: (_) => _setQuickGiType(type),
                    selectedColor: color.withOpacity(0.2),
                    labelStyle: TextStyle(
                      color: _quickGiType == type ? color : Colors.grey.shade800,
                      fontWeight: _quickGiType == type ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final size in sizes)
                ChoiceChip(
                  label: Text(size),
                  selected: _quickSize == size,
                  onSelected: (_) => _setQuickSize(_quickSize == size ? null : size),
                  selectedColor: color.withOpacity(0.2),
                  labelStyle: TextStyle(
                    color: _quickSize == size ? color : Colors.grey.shade800,
                    fontWeight: _quickSize == size ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: (_quickSize == null && _searchQuery.isEmpty)
              ? Center(
                  child: Text(
                    'Pick a size or search to see $label items',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : products.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'No $label items match "${_searchController.text}"'
                            : 'No $label items in $_quickSize',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _isDesktop ? 8 : (_isTablet ? 6 : 4),
                        childAspectRatio: 0.85,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return _QuickProductCell(
                          product: product,
                          effectiveStock: _effectiveStock(product),
                          isInCart: _isProductInCart(product.id),
                          quantity: _cartQuantityForProduct(product.id),
                          onTap: () => _showQuantityDialog(product),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildProductGrid() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_quickCategory != null) {
      return _buildQuickGrid();
    }

    if (_filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No products found', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
            if (_searchQuery.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _searchController.clear(),
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
        final isSelected = _isProductInCart(product.id);
        final quantity = _cartQuantityForProduct(product.id);

        return _ProductCard(
          product: product,
          effectiveStock: _effectiveStock(product),
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_cart, size: 20),
              const SizedBox(width: 8),
              Text('Cart ($_totalItemsInCart)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_totalItemsInCart > 0)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedQuantities.clear();
                      _customPrices.clear();
                      _perFootItems.clear();
                      _cartItemOrder.clear();
                      _lineProductId.clear();
                      _customItems.clear();
                      _customItemOrder.clear();
                      _cartSearchController.clear();
                    });
                  },
                  child: const Text('Clear All', style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showAddCustomItemDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Custom Item'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ),
        if (_totalItemsInCart > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: TextField(
              controller: _cartSearchController,
              decoration: InputDecoration(
                hintText: 'Search in cart...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _cartSearchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _cartSearchController.clear())
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
          ),
        Expanded(
          child: _totalItemsInCart == 0
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('Cart is empty', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      Text('Click on products or add custom items', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildCartItemsGrid([
                      for (int i = 0; i < _filteredCartLines.length; i++)
                        _CartItem(
                          product: _filteredCartLines[i].product,
                          effectiveStock: _effectiveStock(_filteredCartLines[i].product),
                          quantity: _filteredCartLines[i].quantity,
                          price: _filteredCartLines[i].price,
                          onQuantityChanged: (qty) => _updateQuantity(_filteredCartLines[i].lineKey, qty),
                          onPriceChanged: (price) => _updatePrice(_filteredCartLines[i].lineKey, price),
                          onRemove: () => _removeFromCart(_filteredCartLines[i].lineKey),
                          onEdit: () => _showEditLineDialog(_filteredCartLines[i].lineKey),
                          minimumPrice: _getMinimumPrice(_filteredCartLines[i].product, _filteredCartLines[i].isPerFoot),
                          isPerFoot: _filteredCartLines[i].isPerFoot,
                          itemNumber: i + 1,
                        ),
                      for (int i = 0; i < _customItemOrder.length; i++)
                        if (_customItems[_customItemOrder[i]] != null)
                          _CustomCartItem(
                            customItem: _customItems[_customItemOrder[i]]!,
                            itemNumber: _filteredCartLines.length + i + 1,
                            onRemove: () => _removeCustomItem(_customItemOrder[i]),
                            onQuantityChanged: (qty) => _updateCustomItem(_customItemOrder[i], quantity: qty),
                            onAmountChanged: (amount) => _updateCustomItem(_customItemOrder[i], amount: amount),
                          ),
                    ]),
                    _buildSaleDetailsCard(backgroundColor: Colors.white),
                  ],
                ),
        ),
        if (_totalItemsInCart > 0) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(
                      '₹${_totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
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
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _updateSale,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check),
                        label: Text(_isSaving ? 'Updating...' : 'Update Sale'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.all(12), backgroundColor: Colors.green),
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
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Cart ($_totalItemsInCart items)', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
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
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      ),
                    ),
                  ),
                  if (_totalItemsInCart > 0)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _cartSearchController,
                        decoration: InputDecoration(
                          hintText: 'Search in cart...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _cartSearchController.text.isNotEmpty
                              ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _cartSearchController.clear())
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _totalItemsInCart == 0
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text('Cart is empty', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                              ],
                            ),
                          )
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            children: [
                              _buildCartItemsGrid([
                                for (int i = 0; i < _filteredCartLines.length; i++)
                                  _CartItem(
                                    product: _filteredCartLines[i].product,
                                    effectiveStock: _effectiveStock(_filteredCartLines[i].product),
                                    quantity: _filteredCartLines[i].quantity,
                                    price: _filteredCartLines[i].price,
                                    onQuantityChanged: (qty) {
                                      setState(() => _updateQuantity(_filteredCartLines[i].lineKey, qty));
                                      setModalState(() {});
                                    },
                                    onPriceChanged: (price) {
                                      setState(() => _updatePrice(_filteredCartLines[i].lineKey, price));
                                      setModalState(() {});
                                    },
                                    onRemove: () {
                                      setState(() => _removeFromCart(_filteredCartLines[i].lineKey));
                                      setModalState(() {});
                                    },
                                    onEdit: () {
                                      final lineKey = _filteredCartLines[i].lineKey;
                                      Navigator.pop(context);
                                      _showEditLineDialog(lineKey);
                                    },
                                    minimumPrice: _getMinimumPrice(_filteredCartLines[i].product, _filteredCartLines[i].isPerFoot),
                                    isPerFoot: _filteredCartLines[i].isPerFoot,
                                    itemNumber: i + 1,
                                  ),
                                for (int i = 0; i < _customItemOrder.length; i++)
                                  if (_customItems[_customItemOrder[i]] != null)
                                    _CustomCartItem(
                                      customItem: _customItems[_customItemOrder[i]]!,
                                      itemNumber: _filteredCartLines.length + i + 1,
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
                              _buildSaleDetailsCard(
                                backgroundColor: Colors.grey.shade50,
                                afterChange: () => setModalState(() {}),
                              ),
                            ],
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            Text(
                              '₹${_totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ],
                        ),
                        _buildMarginSectionToggle(afterChange: () => setModalState(() {})),
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
                                style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(12)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: _isSaving
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        _updateSale();
                                      },
                                icon: _isSaving
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.check),
                                label: Text(_isSaving ? 'Updating...' : 'Update Sale'),
                                style: FilledButton.styleFrom(padding: const EdgeInsets.all(12), backgroundColor: Colors.green),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$_totalItemsInCart items', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  Text('₹${_totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
  /// effective (edit-aware) stock. Lets the user correct each product's
  /// real catalog stock right here, then continue.
  Future<bool> _resolveInsufficientStock(List<Product> insufficientProducts) async {
    final controllers = {
      for (final product in insufficientProducts)
        product.id: TextEditingController(text: _cartQuantityForProduct(product.id).toString()),
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
                      Text('${product.name} (${product.size})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(
                        'Currently ${product.stock} in stock · cart needs ${_cartQuantityForProduct(product.id)}',
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
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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

  /// Print/view-only preview of the current cart — unlike RecordSaleScreen,
  /// this never lets BillPreviewScreen "complete" the sale (that would
  /// always create a brand-new sale via SalesService.createSale). Saving an
  /// edit only ever happens through _updateSale, via the Update Sale button.
  Future<void> _showBillPreview() async {
    if (_selectedQuantities.isEmpty && _customItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product or add a custom item')),
      );
      return;
    }

    final lineItems = _cartLines
        .map((line) => BillLineItem(
              product: line.product,
              quantity: line.quantity,
              price: line.price,
              isPerFoot: line.isPerFoot,
              unitCost: _effectiveUnitCost(line.product, line.isPerFoot),
              stockUnits: _stockUnitsFor(line.product, line.quantity, line.isPerFoot),
            ))
        .toList();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BillPreviewScreen(
          lineItems: lineItems,
          paymentMethod: _paymentMethod,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          isMock: _isMockSale,
          buyerName: _buyerNameController.text.trim().isEmpty ? null : _buyerNameController.text.trim(),
          buyerPhone: _buyerPhoneController.text.trim().isEmpty ? null : _buyerPhoneController.text.trim(),
          buyerAddress: _buyerAddressController.text.trim().isEmpty ? null : _buyerAddressController.text.trim(),
          initialPayment: _paymentMethod == 'Credit' ? (double.tryParse(_amountPaidController.text) ?? 0) : 0,
          readOnly: true,
          existingInvoiceNumber: widget.sale.invoiceNumber,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cartSearchController.dispose();
    _notesController.dispose();
    _buyerNameController.dispose();
    _buyerPhoneController.dispose();
    _buyerAddressController.dispose();
    _amountPaidController.dispose();
    super.dispose();
  }
}

// Compact grid cell for the quick category picker. Mirrors
// RecordSaleScreen's _QuickProductCell, but takes an edit-aware
// [effectiveStock] instead of reading product.stock directly.
class _QuickProductCell extends StatelessWidget {
  final Product product;
  final int effectiveStock;
  final bool isInCart;
  final int quantity;
  final VoidCallback onTap;

  const _QuickProductCell({
    required this.product,
    required this.effectiveStock,
    required this.isInCart,
    required this.quantity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOutOfStock = effectiveStock == 0;

    return Card(
      elevation: isInCart ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isInCart ? Colors.blue : Colors.grey.shade200, width: isInCart ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildThumbnail()),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          isOutOfStock ? 'Out of stock' : '₹${product.salePrice.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isOutOfStock ? Colors.red : Colors.green.shade700,
                          ),
                        ),
                      ),
                      if (isInCart)
                        Text('×$quantity', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
        child: product.imageBase64 != null
            ? Image.memory(
                base64Decode(product.imageBase64!),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) =>
                    Center(child: Icon(Icons.inventory_2_outlined, size: 22, color: Colors.grey.shade400)),
              )
            : Center(child: Icon(Icons.inventory_2_outlined, size: 22, color: Colors.grey.shade400)),
      ),
    );
  }
}

// Product Card Widget. Mirrors RecordSaleScreen's _ProductCard, but takes an
// edit-aware [effectiveStock] instead of reading product.stock directly for
// the out-of-stock/low-stock badge and coloring.
//
// Known pre-existing issue (also present in RecordSaleScreen's copy, not
// introduced here): this card can overflow ~10px at the bottom in some
// narrow layouts — see project memory project_known_bugs.md.
class _ProductCard extends StatelessWidget {
  final Product product;
  final int effectiveStock;
  final bool isSelected;
  final int quantity;
  final VoidCallback onTap;
  final bool showPurchasePrice;
  final bool showSalesInfo;

  const _ProductCard({
    required this.product,
    required this.effectiveStock,
    required this.isSelected,
    required this.quantity,
    required this.onTap,
    this.showPurchasePrice = false,
    this.showSalesInfo = false,
  });

  Color getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'ppr':
        return Colors.green.shade700;
      case 'cpvc':
        return const Color(0xFFF5DEB3);
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
    final isOutOfStock = effectiveStock == 0;
    final isLowStock = effectiveStock < 5 && effectiveStock > 0;

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
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  _buildImage(),
                  _buildStockBadge(isOutOfStock, isLowStock),
                  _buildCategoryChip(),
                  _buildDiscountChip(),
                  if (showSalesInfo && product.totalSold > 0) _buildSalesBadge(),
                  if (isSelected) _buildSelectedBadge(),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 9),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          product.size,
                          style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        if (showPurchasePrice) ...[
                          _buildPriceRowWithFormat('Cost', product.purchasePrice, Colors.grey.shade700, Icons.shopping_cart_outlined),
                          const SizedBox(height: 2),
                        ],
                        _buildPriceRow('Sale', product.salePrice, Colors.green.shade700, Icons.currency_rupee),
                        if (showSalesInfo && product.totalSold > 0) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.trending_up, size: 10, color: Colors.blue.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${product.totalSold} sold',
                                    style: TextStyle(fontSize: 9, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
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
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
        child: product.imageBase64 != null
            ? Image.memory(
                base64Decode(product.imageBase64!),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(child: Icon(Icons.inventory_2_outlined, size: 28, color: Colors.grey.shade400));
  }

  Widget _buildStockBadge(bool isOutOfStock, bool isLowStock) {
    if (!isOutOfStock && !isLowStock) return const SizedBox.shrink();

    return Positioned(
      top: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isOutOfStock ? Colors.red.shade500 : Colors.orange.shade500,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          isOutOfStock ? 'Out' : 'Low: $effectiveStock',
          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
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
        decoration: BoxDecoration(color: getCategoryColor(product.category), borderRadius: BorderRadius.circular(6)),
        child: Text(
          product.category.toUpperCase(),
          style: TextStyle(color: getCategoryTextColor(product.category), fontSize: 8, fontWeight: FontWeight.bold),
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
        decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
        child: Column(
          children: [
            const Icon(Icons.check, color: Colors.white, size: 12),
            if (quantity > 0) ...[
              Text(quantity.toString(), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
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
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 2, offset: const Offset(0, 1))],
                  ),
                  child: Text(
                    product.discountReceived?.toString() ?? '',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8),
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 2, offset: const Offset(0, 1))],
                  ),
                  child: Text(
                    product.sellingDiscount?.toString() ?? '',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8),
                  ),
                ),
              ],
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.purple,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 2, offset: const Offset(0, 1))],
              ),
              child: Text(
                product.margin?.toString() ?? '',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 2, offset: const Offset(0, 1))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department, size: 9, color: Colors.white),
            const SizedBox(width: 2),
            Text('${product.totalSold}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRowWithFormat(String label, double price, Color color, IconData icon) {
    final calculatedPrice = price / 9;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(calculatedPrice.toStringAsFixed(0), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildPriceRow(String label, double price, Color color, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(icon, size: 9, color: color),
        Text('₹${price.toStringAsFixed(0)}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

// Cart Item Widget with improved controls. Mirrors RecordSaleScreen's
// _CartItem, but takes an edit-aware [effectiveStock] instead of reading
// product.stock directly for the quantity "+" ceiling.
class _CartItem extends StatefulWidget {
  final Product product;
  final int effectiveStock;
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
    required this.effectiveStock,
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
    _priceController = TextEditingController(text: widget.price.toStringAsFixed(0));
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      widget.itemNumber.toString(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          Text(widget.product.size, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
                                style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.indigo.shade700),
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
              ],
            ),
            const SizedBox(height: 8),
            Text(widget.isPerFoot ? 'Feet' : 'Quantity', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            const SizedBox(height: 3),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: widget.isPerFoot ? Colors.indigo.shade200 : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.quantity > 1 ? () => widget.onQuantityChanged(widget.quantity - 1) : null,
                    icon: const Icon(Icons.remove, size: 16),
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                  ),
                  Expanded(
                    child: Text(
                      widget.isPerFoot ? '${widget.quantity} ft' : widget.quantity.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.isPerFoot || widget.quantity < widget.effectiveStock
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
            Text('Price', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            const SizedBox(height: 3),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: '₹',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Subtotal', style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500)),
                  Text('₹${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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

// Consolidated Filters sheet: category, subcategory, size, and stock all in
// one place. Straight port of RecordSaleScreen's _FiltersSheet.
class _FiltersSheet extends StatefulWidget {
  final List<String> categories;
  final Map<String, List<String>> allSubcategories;
  final Color Function(String) getCategoryColor;
  final String? initialCategory;
  final String? initialSubcategory;
  final Set<String> initialSizes;
  final bool initialInStockOnly;
  final bool initialLowStockOnly;
  final List<String> Function(String? category, String? subcategory) getAvailableSizes;
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
  final TextEditingController _categorySearchController = TextEditingController();
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
          : widget.categories.where((cat) => cat.toLowerCase().contains(query)).toList();
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
    final available = widget.getAvailableSizes(category, null).toSet();
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
    final subcategories = _category != null ? (widget.allSubcategories[_category] ?? []) : const <String>[];
    final hasActiveFilters =
        _category != null || _subcategory != null || _sizes.isNotEmpty || _inStockOnly || _lowStockOnly;

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      if (hasActiveFilters) TextButton(onPressed: _clearAll, child: const Text('Clear All')),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    const Text('CATEGORY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _categorySearchController,
                      decoration: InputDecoration(
                        hintText: 'Search categories...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _categorySearchController.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () => _categorySearchController.clear())
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: _filteredCategories.length + 1,
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
                        final isSelected = _category?.toLowerCase() == category.toLowerCase();
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
                      const Text('SUBCATEGORY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: subcategories.map((sub) {
                          final isSelected = _subcategory == sub;
                          return FilterChip(
                            selected: isSelected,
                            label: Text(sub),
                            avatar: Icon(Icons.label_outline, size: 16, color: isSelected ? Colors.indigo : Colors.grey[600]),
                            onSelected: (_) => _selectSubcategory(sub),
                            backgroundColor: Colors.grey[100],
                            selectedColor: Colors.indigo.withOpacity(0.2),
                            checkmarkColor: Colors.indigo,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.indigo : Colors.black87,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (sizes.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text('SIZE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: sizes.map((size) {
                          final isSelected = _sizes.contains(size);
                          return FilterChip(
                            selected: isSelected,
                            label: Text(size),
                            avatar: Icon(Icons.straighten, size: 16, color: isSelected ? Colors.blue : Colors.grey[600]),
                            onSelected: (_) => _toggleSize(size),
                            backgroundColor: Colors.grey[100],
                            selectedColor: Colors.blue.withOpacity(0.2),
                            checkmarkColor: Colors.blue,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.blue : Colors.black87,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text('STOCK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          selected: _inStockOnly,
                          label: const Text('In Stock Only'),
                          avatar: Icon(Icons.inventory_2_outlined, size: 16, color: _inStockOnly ? Colors.green : Colors.grey[600]),
                          onSelected: (_) => _toggleInStock(),
                          backgroundColor: Colors.grey[100],
                          selectedColor: Colors.green.withOpacity(0.2),
                          checkmarkColor: Colors.green,
                          labelStyle: TextStyle(
                            color: _inStockOnly ? Colors.green : Colors.black87,
                            fontWeight: _inStockOnly ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        FilterChip(
                          selected: _lowStockOnly,
                          label: const Text('Low Stock'),
                          avatar: Icon(Icons.warning_amber_rounded, size: 16, color: _lowStockOnly ? Colors.orange : Colors.grey[600]),
                          onSelected: (_) => _toggleLowStock(),
                          backgroundColor: Colors.grey[100],
                          selectedColor: Colors.orange.withOpacity(0.2),
                          checkmarkColor: Colors.orange,
                          labelStyle: TextStyle(
                            color: _lowStockOnly ? Colors.orange : Colors.black87,
                            fontWeight: _lowStockOnly ? FontWeight.bold : FontWeight.normal,
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
          border: Border.all(color: isSelected ? color : Colors.grey.shade300, width: isSelected ? 2.5 : 1),
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
              child: Icon(icon, color: color, size: 28),
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
                child: Icon(Icons.check_circle, color: color, size: 16),
              ),
          ],
        ),
      ),
    );
  }
}

// Custom Cart Item Widget for non-inventory items. Straight port of
// RecordSaleScreen's _CustomCartItem.
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
    _amountController = TextEditingController(text: widget.customItem.amount.toStringAsFixed(0));
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.orange.shade200, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      widget.itemNumber.toString(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade700),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.note_add, color: Colors.orange.shade700, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.customItem.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          'CUSTOM',
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.orange.shade700),
                        ),
                      ),
                    ],
                  ),
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
            const SizedBox(height: 8),
            Text('Quantity', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            const SizedBox(height: 3),
            Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  IconButton(
                    onPressed:
                        widget.customItem.quantity > 1 ? () => widget.onQuantityChanged(widget.customItem.quantity - 1) : null,
                    icon: const Icon(Icons.remove, size: 16),
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                  ),
                  Expanded(
                    child: Text(
                      widget.customItem.quantity.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
            Text('Amount', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            const SizedBox(height: 3),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '₹',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Subtotal', style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500)),
                  Text('₹${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
