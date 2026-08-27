import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../../services/firebase_service.dart';
import '../widgets/product_card.dart';
import 'add_product_screen.dart';
import 'add_product_web_screen.dart';
import 'downloads_screen.dart';
import 'bulk_price_update_screen.dart';
import 'excel_export_screen.dart';
import 'gst_calculator_screen.dart';

enum ProductSortOption { newest, lowStock, highSelling }

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _searchQuery = '';
  bool _useStreamMode = true;
  bool showPurchasePrices = false;
  ProductSortOption _currentSortOption = ProductSortOption.newest;

  // Category filtering
  List<String> _categories = [];
  String? _selectedCategory; // null means "All Categories"
  bool _isLoadingCategories = true;

  // Subcategory filtering
  Map<String, List<String>> _subcategories = {};
  String? _selectedSubcategory; // null means "All" within the category

  // Quick category rail — same fast PPR/CPVC/PVC/GI narrowing used on the
  // record sale screen, for browsing without touching the general filters.
  static const List<String> _quickCategories = ['PPR', 'CPVC', 'PVC', 'GI'];
  String? _quickCategory;
  String? _quickGiType; // 'Fitting' or 'Nipple', only meaningful for GI
  String? _quickSize;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final categories = await _firebaseService.getCategories();
      final subcategories = await _firebaseService.getAllSubcategories();
      setState(() {
        _categories = categories;
        _subcategories = subcategories;
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

  // Responsive grid columns
  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (kIsWeb) {
      if (width > 1400) return 6;
      if (width > 1200) return 5;
      if (width > 900) return 4;
      if (width > 600) return 3;
      return 2;
    } else {
      return width > 600 ? 3 : 2;
    }
  }

  double _getGridSpacing(BuildContext context) {
    return kIsWeb ? 20 : 16;
  }

  List<Product> _filterProducts(List<Product> products) {
    var filtered = products;

    // Filter by category
    if (_selectedCategory != null) {
      filtered = filtered
          .where((p) => p.category.toLowerCase() == _selectedCategory!.toLowerCase())
          .toList();
    }

    // Filter by subcategory (only meaningful within a selected category)
    if (_selectedSubcategory != null) {
      filtered = filtered
          .where((p) =>
              (p.subcategory ?? '').toLowerCase() ==
              _selectedSubcategory!.toLowerCase())
          .toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final queryWords = _searchQuery
          .toLowerCase()
          .split(' ')
          .where((w) => w.isNotEmpty);

      filtered = filtered.where((product) {
        final name = product.name.toLowerCase();
        final size = product.size.toLowerCase();
        return queryWords.every(
              (word) => name.contains(word) || size.contains(word),
        );
      }).toList();
    }

    return filtered;
  }

  // Some products have PPR/CPVC/PVC/GI as the category directly, others as
  // a subcategory under "Sanitary" — so the quick rail matches either shape.
  bool _matchesQuickCategory(Product p, String target) {
    final category = p.category.toLowerCase();
    final t = target.toLowerCase();
    if (category == t) return true;
    return category == 'sanitary' && (p.subcategory?.toLowerCase() == t);
  }

  bool _isNippleProduct(Product p) =>
      (p.subcategory ?? '').toLowerCase().contains('nipple') ||
      p.name.toLowerCase().contains('nipple');

  // Only meaningful when browsing GI: splits fittings from nipples so the
  // two don't get mixed in the same size grid despite sharing diameter sizes.
  bool _matchesQuickGiType(Product p) {
    if (_quickCategory != 'GI') return true;
    return _isNippleProduct(p) == (_quickGiType == 'Nipple');
  }

  List<String> _quickAvailableSizes(List<Product> products) {
    if (_quickCategory == null) return [];
    final sizes = products
        .where((p) =>
            _matchesQuickCategory(p, _quickCategory!) && _matchesQuickGiType(p))
        .map((p) => p.size)
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList();
    sizes.sort();
    return sizes;
  }

  // With a size picked, shows that size's items; typing a search narrows
  // (or, with no size picked yet, searches the whole category directly).
  List<Product> _quickFilteredProducts(List<Product> products) {
    if (_quickCategory == null) return [];
    if (_quickSize == null && _searchQuery.isEmpty) return [];

    var filtered = products.where((p) =>
        _matchesQuickCategory(p, _quickCategory!) && _matchesQuickGiType(p));

    if (_quickSize != null) {
      filtered = filtered.where((p) => p.size == _quickSize);
    }

    if (_searchQuery.isNotEmpty) {
      final queryWords = _searchQuery.split(' ').where((w) => w.isNotEmpty);
      filtered = filtered.where((product) {
        final name = product.name.toLowerCase();
        final size = product.size.toLowerCase();
        return queryWords.every((word) => name.contains(word) || size.contains(word));
      });
    }

    return filtered.toList();
  }

  // Tapping the active category again exits quick mode. Switching category
  // drops the previously-selected size — sizes are scoped per category.
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

  Future<void> _navigateToAddProduct() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => kIsWeb ? AddProductWebScreen() : AddProductScreen(),
      ),
    );
  }

  Future<void> _deleteProduct(Product product) async {
    try {
      await _firebaseService.deleteProduct(product.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting product: $e')));
      }
    }
  }

  Future<void> _refreshProducts() async {
    _firebaseService.clearCache();
    await _loadCategories();
    setState(() {});
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
          setState(() {
            _selectedCategory = category;
            _selectedSubcategory = null;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1200;
    final isTablet = MediaQuery.of(context).size.width >= 600 &&
        MediaQuery.of(context).size.width < 1200;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Modern header with search and filters
          Container(
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
                        if (value == 'mode') {
                          setState(() {
                            _useStreamMode = !_useStreamMode;
                          });
                        } else if (value == 'refresh') {
                          _refreshProducts();
                        } else if (value == 'prices') {
                          setState(() {
                            showPurchasePrices = !showPurchasePrices;
                          });
                        } else if (value == 'print_list') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const PrintPriceListScreen(),
                            ),
                          );
                        } else if (value == 'bulk_update') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const BulkPriceUpdateScreen(),
                            ),
                          );
                        } else if (value == 'excel_export') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ExcelExportScreen(),
                            ),
                          );
                        } else if (value == 'gst_calculator') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const GstCalculatorScreen(),
                            ),
                          );
                        } else if (value.startsWith('sort_')) {
                          final sortOption = value.replaceFirst('sort_', '');
                          setState(() {
                            if (sortOption == 'newest') {
                              _currentSortOption = ProductSortOption.newest;
                            } else if (sortOption == 'lowStock') {
                              _currentSortOption = ProductSortOption.lowStock;
                            } else if (sortOption == 'highSelling') {
                              _currentSortOption =
                                  ProductSortOption.highSelling;
                            }
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
                        PopupMenuItem(
                          value: 'mode',
                          child: Row(
                            children: [
                              Icon(
                                _useStreamMode
                                    ? Icons.refresh
                                    : Icons.cloud_off,
                                size: 20,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _useStreamMode
                                    ? 'Use Cached Data'
                                    : 'Use Real-time Data',
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'refresh',
                          child: Row(
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 20,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 12),
                              const Text('Refresh Products'),
                            ],
                          ),
                        ),

                        const PopupMenuDivider(),

                        // Tools section
                        const PopupMenuItem(
                          enabled: false,
                          child: Text(
                            'TOOLS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'print_list',
                          child: Row(
                            children: [
                              Icon(
                                Icons.print,
                                size: 20,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 12),
                              const Text('Print Price List'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'bulk_update',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_note,
                                size: 20,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 12),
                              const Text('Bulk Price Update'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'gst_calculator',
                          child: Row(
                            children: [
                              Icon(
                                Icons.calculate_outlined,
                                size: 20,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 12),
                              const Text('GST Calculator'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'excel_export',
                          child: Row(
                            children: [
                              Icon(
                                Icons.table_chart,
                                size: 20,
                                color: Colors.green[700],
                              ),
                              const SizedBox(width: 12),
                              const Text('Export to Excel'),
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

                // Subcategory chips (any layout) — shown when the selected
                // category has subcategories defined.
                if (_subcategoryChipsVisible) ...[
                  const SizedBox(height: 12),
                  _buildSubcategoryChipsRow(),
                ],

                // Active filters row (Mobile)
                if (!isDesktop && !isTablet) ...[
                  const SizedBox(height: 12),
                  _buildActiveFiltersRow(),
                ],
              ],
            ),
          ),

          // Quick category bar (Mobile) — rail sits beside the grid instead
          // on wider layouts, see below.
          if (!isDesktop && !isTablet) _buildQuickCategoryBar(),

          // Product grid
          Expanded(
            child: Row(
              children: [
                if (isDesktop || isTablet) _buildQuickCategoryRail(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshProducts,
                    child:
                        _useStreamMode ? _buildStreamView() : _buildCachedView(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddProduct,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  bool get _subcategoryChipsVisible {
    final cat = _selectedCategory;
    if (cat == null) return false;
    final subs = _subcategories[cat];
    return subs != null && subs.isNotEmpty;
  }

  Widget _buildSubcategoryChipsRow() {
    final subs = _subcategories[_selectedCategory] ?? const [];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          selected: _selectedSubcategory == null,
          label: const Text('All'),
          onSelected: (_) {
            setState(() => _selectedSubcategory = null);
          },
          backgroundColor: Colors.grey[200],
          selectedColor: Colors.blue.withOpacity(0.2),
          checkmarkColor: Colors.blue,
          labelStyle: TextStyle(
            color: _selectedSubcategory == null ? Colors.blue : Colors.black87,
            fontWeight: _selectedSubcategory == null
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
        ...subs.map((sub) {
          final isSelected = _selectedSubcategory == sub;
          return FilterChip(
            selected: isSelected,
            label: Text(sub),
            avatar: Icon(
              Icons.account_tree_outlined,
              size: 16,
              color: isSelected ? Colors.blue : Colors.blue.withOpacity(0.7),
            ),
            onSelected: (_) {
              setState(() {
                _selectedSubcategory = isSelected ? null : sub;
              });
            },
            backgroundColor: Colors.blue.withOpacity(0.08),
            selectedColor: Colors.blue.withOpacity(0.2),
            checkmarkColor: Colors.blue,
            labelStyle: TextStyle(
              color: isSelected ? Colors.blue : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          );
        }),
      ],
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
              _selectedSubcategory = null;
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
                _selectedSubcategory = null;
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
                    _selectedSubcategory = null;
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

  Widget _buildStreamView() {
    return StreamBuilder<List<Product>>(
      stream: _firebaseService.getProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final products = snapshot.data ?? [];
        if (_quickCategory != null) {
          return _buildQuickGrid(products);
        }
        final filteredProducts = _filterProducts(products);
        final sortedProducts = _sortProducts(filteredProducts);
        return _buildProductGrid(sortedProducts);
      },
    );
  }

  Widget _buildCachedView() {
    return FutureBuilder<List<Product>>(
      future: _firebaseService.getCachedProducts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final products = snapshot.data ?? [];
        if (_quickCategory != null) {
          return _buildQuickGrid(products);
        }
        final filteredProducts = _filterProducts(products);
        final sortedProducts = _sortProducts(filteredProducts);
        return _buildProductGrid(sortedProducts);
      },
    );
  }

  // Replaces the normal grid while a quick category is active: a row of
  // sizes for that category, then matching items once a size is picked.
  Widget _buildQuickGrid(List<Product> products) {
    final sizes = _quickAvailableSizes(products);
    final quickProducts = _quickFilteredProducts(products);
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
                      fontWeight: _quickGiType == type
                          ? FontWeight.bold
                          : FontWeight.normal,
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
                  onSelected: (_) =>
                      _setQuickSize(_quickSize == size ? null : size),
                  selectedColor: color.withOpacity(0.2),
                  labelStyle: TextStyle(
                    color: _quickSize == size ? color : Colors.grey.shade800,
                    fontWeight:
                        _quickSize == size ? FontWeight.bold : FontWeight.normal,
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
              : quickProducts.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'No $label items match "${_searchController.text}"'
                            : 'No $label items in $_quickSize',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  : _buildProductGrid(_sortProducts(quickProducts)),
        ),
      ],
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

  // Same categories, laid out as a horizontal bar — used on mobile where
  // there isn't room for a permanent side rail.
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
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.plumbing,
                color: selected ? color : Colors.grey.shade500, size: 20),
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

  Widget _buildProductGrid(List<Product> products) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _selectedCategory != null
                  ? 'No products in ${_selectedCategory!.toUpperCase()}'
                  : _searchQuery.isEmpty
                  ? 'No products yet'
                  : 'No products found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            if (_selectedCategory != null || _searchQuery.isNotEmpty) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedCategory = null;
                    _selectedSubcategory = null;
                    _searchController.clear();
                  });
                },
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear Filters'),
              ),
            ],
            if (!kIsWeb && _searchQuery.isEmpty && _selectedCategory == null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _navigateToAddProduct,
                icon: const Icon(Icons.add),
                label: const Text('Add Your First Product'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final crossAxisCount = _getCrossAxisCount(context);
    final spacing = _getGridSpacing(context);

    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(spacing),
      itemCount: products.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: _calculatePreciseAspectRatio(context),
      ),
      itemBuilder: (context, index) {
        final product = products[index];
        return Dismissible(
          key: ValueKey(product.id),
          direction: DismissDirection.startToEnd,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('Delete Product'),
                  content: Text(
                    'Are you sure you want to delete ${product.name}?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Delete'),
                    ),
                  ],
                );
              },
            );
          },
          onDismissed: (direction) {
            _deleteProduct(product);
          },
          child: ProductCard(
            product: product,
            onDelete: () => _deleteProduct(product),
            showPurchasePrice: showPurchasePrices,
            showSalesInfo: _currentSortOption == ProductSortOption.highSelling,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => kIsWeb
                    ? AddProductWebScreen(
                        product: product,
                        products: products,
                        index: index,
                      )
                    : AddProductScreen(
                        product: product,
                        products: products,
                        index: index,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Calculates precise aspect ratio for grid items based on visible content
  double _calculatePreciseAspectRatio(BuildContext context) {
    const double imageHeight = 180.0;
    const double baseInfoHeight = 120.0;
    const double cardPadding = 8.0;

    double additionalHeight = 0;

    if (showPurchasePrices) {
      additionalHeight += 120.0;
    }

    if (_currentSortOption == ProductSortOption.highSelling) {
      additionalHeight += 20.0;
    }

    final totalHeight =
        imageHeight + baseInfoHeight + additionalHeight + cardPadding;

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = _getCrossAxisCount(context);
    final spacing = _getGridSpacing(context);

    final horizontalPadding = spacing * 2;
    final totalSpacing = spacing * (crossAxisCount - 1);
    final availableWidth = screenWidth - horizontalPadding - totalSpacing;
    final cardWidth = availableWidth / crossAxisCount;

    final aspectRatio = cardWidth / totalHeight;

    return aspectRatio;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
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