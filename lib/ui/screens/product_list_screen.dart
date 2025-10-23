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
  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _searchController = TextEditingController();
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

  List<Product> _filterProducts(List<Product> products) {
    if (_searchQuery.isEmpty) return products;

    final queryWords = _searchQuery.toLowerCase().split(' ').where((w) => w.isNotEmpty);

    return products.where((product) {
      final name = product.name.toLowerCase();
      final size = product.size.toLowerCase();

      // Check if every word exists in either name or size
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
          // First sort by stock (ascending)
          final stockCompare = a.stock.compareTo(b.stock);
          if (stockCompare != 0) return stockCompare;
          // If stock is equal, sort by newest
          return b.createdAt.compareTo(a.createdAt);
        });
        break;

      case ProductSortOption.highSelling:
        sortedList.sort((a, b) {
          // First sort by total sold (descending)
          final soldCompare = b.totalSold.compareTo(a.totalSold);
          if (soldCompare != 0) return soldCompare;
          // If total sold is equal, sort by sale count (descending)
          final countCompare = b.saleCount.compareTo(a.saleCount);
          if (countCompare != 0) return countCompare;
          // If still equal, sort by sales frequency (descending)
          return b.salesFrequency.compareTo(a.salesFrequency);
        });
        break;
    }

    return sortedList;
  }

  Future<void> _navigateToAddProduct() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddProductScreen()),
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
    setState(() {});
  }

  String _getSortOptionLabel(ProductSortOption option) {
    switch (option) {
      case ProductSortOption.newest:
        return 'Sort: Newest First';
      case ProductSortOption.lowStock:
        return 'Sort: Low Stock';
      case ProductSortOption.highSelling:
        return 'Sort: Best Sellers';
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
    return Scaffold(
      body: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
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
              ),
              PopupMenuButton<String>(
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
                  // Sort options section
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'Sort By',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                        fontSize: 12,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sort_newest',
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 20,
                          color: _currentSortOption == ProductSortOption.newest
                              ? Colors.blue
                              : Colors.grey[600],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Newest First',
                          style: TextStyle(
                            color: _currentSortOption == ProductSortOption.newest
                                ? Colors.blue
                                : null,
                            fontWeight:
                            _currentSortOption == ProductSortOption.newest
                                ? FontWeight.bold
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sort_lowStock',
                    child: Row(
                      children: [
                        Icon(
                          Icons.trending_down,
                          size: 20,
                          color: _currentSortOption == ProductSortOption.lowStock
                              ? Colors.blue
                              : Colors.grey[600],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Low Stock',
                          style: TextStyle(
                            color: _currentSortOption == ProductSortOption.lowStock
                                ? Colors.blue
                                : null,
                            fontWeight:
                            _currentSortOption == ProductSortOption.lowStock
                                ? FontWeight.bold
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sort_highSelling',
                    child: Row(
                      children: [
                        Icon(
                          Icons.trending_up,
                          size: 20,
                          color:
                          _currentSortOption == ProductSortOption.highSelling
                              ? Colors.blue
                              : Colors.grey[600],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Best Sellers',
                          style: TextStyle(
                            color:
                            _currentSortOption == ProductSortOption.highSelling
                                ? Colors.blue
                                : null,
                            fontWeight:
                            _currentSortOption == ProductSortOption.highSelling
                                ? FontWeight.bold
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  // Other options
                  PopupMenuItem(
                    value: 'mode',
                    child: Row(
                      children: [
                        Icon(Icons.sync, size: 20, color: Colors.grey[600]),
                        const SizedBox(width: 12),
                        Text(
                          _useStreamMode
                              ? 'Switch to Cached mode'
                              : 'Switch to Real-time mode',
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        Icon(Icons.refresh, size: 20, color: Colors.grey[600]),
                        const SizedBox(width: 12),
                        const Text('Refresh'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'prices',
                    child: Row(
                      children: [
                        Icon(
                          !showPurchasePrices
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 20,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 12),
                        Text(
                          !showPurchasePrices
                              ? 'Show Purchase Prices'
                              : 'Hide Purchase Prices',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Sort indicator chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getSortOptionIcon(_currentSortOption),
                        size: 16,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _getSortOptionLabel(_currentSortOption),
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _useStreamMode ? _buildStreamView() : _buildCachedView(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddProduct,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
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
        return _buildProductList(sortedProducts);
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
        return _buildProductList(sortedProducts);
      },
    );
  }

  Widget _buildProductList(List<Product> products) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'No products yet' : 'No products found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding:   EdgeInsets.all(16),
      itemCount: products.length,
      gridDelegate:   SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio:showPurchasePrices?0.65:  0.70,
      ),
      itemBuilder: (context, index) {
        final product = products[index];
        return Dismissible(
          key: ValueKey(product.id),
          direction: DismissDirection.startToEnd,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            color: Colors.red,
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
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
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
    super.dispose();
  }
}