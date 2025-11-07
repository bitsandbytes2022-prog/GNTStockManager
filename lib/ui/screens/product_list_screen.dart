import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../../services/firebase_service.dart';
import '../widgets/product_card.dart';
import 'add_product_screen.dart';
import 'add_product_web_screen.dart';

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
          setState(() => _selectedCategory = category);
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
          ),

          // Product grid
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshProducts,
              child: _useStreamMode ? _buildStreamView() : _buildCachedView(),
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
            setState(() => _selectedCategory = null);
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
                  setState(() => _selectedCategory = null);
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

        final filteredProducts = _filterProducts(snapshot.data ?? []);
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

        final filteredProducts = _filterProducts(snapshot.data ?? []);
        final sortedProducts = _sortProducts(filteredProducts);
        return _buildProductGrid(sortedProducts);
      },
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
                    ? AddProductWebScreen(product: product)
                    : AddProductScreen(product: product),
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