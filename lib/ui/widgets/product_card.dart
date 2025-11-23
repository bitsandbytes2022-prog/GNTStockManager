import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../models/product_model.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final bool showPurchasePrice;
  final bool showSalesInfo;

  const ProductCard({
    super.key,
    required this.product,
    required this.onDelete,
    required this.onTap,
    this.showPurchasePrice = false,
    this.showSalesInfo = false,
  });

  // Calculate profit margin percentage
  double get profitMargin {
    if (product.purchasePrice == 0) return 0;
    return ((product.salePrice - product.purchasePrice) / product.purchasePrice) * 100;
  }

  // Calculate profit amount
  double get profitAmount {
    return product.salePrice - product.purchasePrice;
  }

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
        return Colors.blueGrey.shade600; // Default color
    }
  }

  /// Get text color for category chip (ensures readability)
  Color getCategoryTextColor(String category) {
    switch (category.toLowerCase()) {
      case 'cpvc':
      case 'electrical':
        return Colors.black87; // Dark text for light backgrounds
      default:
        return Colors.white; // White text for most backgrounds
    }
  }

  /// Show image in fullscreen with zoom capabilities
  void _showImageZoom(BuildContext context) {
    if (product.imageBase64 == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => ImageZoomViewer(
          imageBase64: product.imageBase64!,
          productName: product.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLowStock = product.stock < 5;
    final bool isOutOfStock = product.stock == 0;

    return Card(
      elevation: kIsWeb ? 1 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOutOfStock
              ? Colors.red.shade100
              : isLowStock
              ? Colors.orange.shade100
              : Colors.grey.shade100,
          width: isOutOfStock || isLowStock ? 2 : 1,
        ),
      ),
      child: InkWell(
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
                  _buildImage(context),
                  _buildStockBadge(),
                  _buildCategoryChip(),
                  _buildDiscountChip(),
                  if (showSalesInfo && product.totalSold > 0)
                    _buildSalesBadge(),
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

                    // Prices and profit
                    Column(
                      children: [
                        if (showPurchasePrice) ...[
                          _buildPriceRow(
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
                        if (showPurchasePrice) ...[
                          const SizedBox(height: 4),
                          _buildProfitRow(),
                        ],
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

  Widget _buildImage(BuildContext context) {
    return GestureDetector(
      onTap: () => _showImageZoom(context),
      child: Container(
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
              ? Stack(
            children: [
              Image.memory(
                base64Decode(product.imageBase64!),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  return _buildPlaceholder();
                },
              ),
              // Zoom indicator overlay
              if (product.imageBase64 != null)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.zoom_in,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          )
              : _buildPlaceholder(),
        ),
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

  Widget _buildStockBadge() {
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: product.stock == 0
              ? Colors.red.shade500
              : product.stock < 5
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
              product.stock == 0 ? Icons.warning_rounded : Icons.inventory_2,
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

  /// Category chip displayed on the image
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
  Widget _buildDiscountChip() {


    return Positioned(
      top: 32,
      left:16,
      child: product.discountReceived!=null && product.sellingDiscount!=null?Row(
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
              product.discountReceived?.toString()??'',
              style: TextStyle(
                color:Colors.white ,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(width: 4,),
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
              product.sellingDiscount?.toString()??'',
              style: TextStyle(
                color:Colors.white ,
                fontWeight: FontWeight.bold,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ):Container(
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
          product.margin?.toString()??'',
          style: TextStyle(
            color:Colors.white ,
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

  Widget _buildProfitRow() {
    final isProfit = profitAmount >= 0;
    final color = isProfit ? Colors.teal.shade700 : Colors.red.shade700;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              isProfit ? Icons.trending_up : Icons.trending_down,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              'Profit',
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              '₹${profitAmount.abs().toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${profitMargin.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Fullscreen image viewer with pinch-to-zoom functionality
class ImageZoomViewer extends StatefulWidget {
  final String imageBase64;
  final String productName;

  const ImageZoomViewer({
    super.key,
    required this.imageBase64,
    required this.productName,
  });

  @override
  State<ImageZoomViewer> createState() => _ImageZoomViewerState();
}

class _ImageZoomViewerState extends State<ImageZoomViewer> {
  final TransformationController _transformationController =
  TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  /// Handle double tap to zoom in/out
  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      // Reset to original scale
      _transformationController.value = Matrix4.identity();
    } else {
      // Zoom to 2x at the tap position
      final position = _doubleTapDetails!.localPosition;
      _transformationController.value = Matrix4.identity()
        ..translate(-position.dx, -position.dy)
        ..scale(2.0);
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.productName,
          style: const TextStyle(fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_out_map),
            onPressed: () {
              _transformationController.value = Matrix4.identity();
            },
            tooltip: 'Reset Zoom',
          ),
        ],
      ),
      body: GestureDetector(
        onDoubleTapDown: _handleDoubleTapDown,
        onDoubleTap: _handleDoubleTap,
        child: Center(
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.5,
            maxScale: 4.0,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: Image.memory(
              base64Decode(widget.imageBase64),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.white,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Text(
            'Pinch to zoom • Double tap to zoom in/out',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}