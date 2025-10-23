import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../models/product_model.dart';
import '../../services/firebase_service.dart';
import '../widgets/product_card.dart';
import 'add_product_screen.dart';

enum ProductSortOption {
  newest,
  lowStock,
  highSelling,
}

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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
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
    if (_searchQuery.isEmpty) return products;

    final queryWords = _searchQuery.toLowerCase().split(' ').where((w) => w.isNotEmpty);

    return products.where((product) {
      final name = product.name.toLowerCase();
      final size = product.size.toLowerCase();
      return queryWords.every((word) => name.contains(word) || size.contains(word));
    }).toList();
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
      MaterialPageRoute(builder: (_) => const AddProductScreen()),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting product: $e')),
        );
      }
    }
  }

  Future<void> _refreshProducts() async {
    _firebaseService.clearCache();
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1200;

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

                    // Filter button
                    PopupMenuButton<String>(
                      icon: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.filter_list),
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
                              _currentSortOption = ProductSortOption.highSelling;
                            }
                          });
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          enabled: false,
                          child: Text(
                            'Sort By',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        _buildSortMenuItem('newest', ProductSortOption.newest),
                        _buildSortMenuItem('lowStock', ProductSortOption.lowStock),
                        _buildSortMenuItem('highSelling', ProductSortOption.highSelling),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'prices',
                          child: Row(
                            children: [
                              Icon(
                                showPurchasePrices
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 20,
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
                          value: 'refresh',
                          child: Row(
                            children: [
                              const Icon(Icons.refresh, size: 20),
                              const SizedBox(width: 12),
                              const Text('Refresh'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Active sort indicator
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(
                      avatar: Icon(
                        _getSortOptionIcon(_currentSortOption),
                        size: 16,
                      ),
                      label: Text(
                        _getSortOptionLabel(_currentSortOption),
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Colors.blue.shade50,
                      side: BorderSide(color: Colors.blue.shade200),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Product grid
          Expanded(
            child: _useStreamMode ? _buildStreamView() : _buildCachedView(),
          ),
        ],
      ),
      floatingActionButton: kIsWeb
          ? null // Hide on web
          : FloatingActionButton.extended(
        onPressed: _navigateToAddProduct,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  PopupMenuItem<String> _buildSortMenuItem(String value, ProductSortOption option) {
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
            Icon(
              Icons.inventory_2_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'No products yet' : 'No products found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            if (!kIsWeb && _searchQuery.isEmpty) ...[
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
        childAspectRatio: showPurchasePrices ? 0.65 : 0.70,
      ),
      itemBuilder: (context, index) {
        final product = products[index];
        return Dismissible(
          key: ValueKey(product.id),
          direction: kIsWeb ? DismissDirection.none : DismissDirection.startToEnd,
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
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
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
            onTap: kIsWeb
                ? () {} // View only on web
                : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddProductScreen(product: product),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}