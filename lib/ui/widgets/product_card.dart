import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/product_model.dart';
import '../theme/app_theme.dart';

class ProductCard extends StatefulWidget {
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

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _hover = false;

  Product get product => widget.product;

  // Calculate profit margin percentage
  double get profitMargin {
    if (product.purchasePrice == 0) return 0;
    return ((product.salePrice - product.purchasePrice) / product.purchasePrice) * 100;
  }

  // Calculate profit amount
  double get profitAmount {
    return product.salePrice - product.purchasePrice;
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

  static const _radius = BorderRadius.all(Radius.circular(AppRadii.card));
  static const _topRadius = BorderRadius.only(
    topLeft: Radius.circular(AppRadii.card),
    topRight: Radius.circular(AppRadii.card),
  );

  @override
  Widget build(BuildContext context) {
    final bool isLowStock = product.stock < 5;
    final bool isOutOfStock = product.stock == 0;
    final Color borderColor = isOutOfStock
        ? AppColors.stockOut.withValues(alpha: 0.35)
        : isLowStock
            ? AppColors.stockLow.withValues(alpha: 0.35)
            : _hover
                ? AppColors.blue.withValues(alpha: 0.35)
                : AppColors.border;

    // Lifts a little with a deeper shadow on hover (web/desktop).
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: _radius,
          border: Border.all(
            color: borderColor,
            width: isOutOfStock || isLowStock ? 1.5 : 1,
          ),
          boxShadow: _hover ? AppShadows.raised : AppShadows.card,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: _radius,
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
                      if (widget.showSalesInfo && product.totalSold > 0)
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
                                fontSize: 11,
                                color: AppColors.navy,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              product.size,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (product.subcategory != null &&
                                product.subcategory!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.account_tree_outlined,
                                    size: 11,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      product.subcategory!,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),

                        // Prices and profit
                        Column(
                          children: [
                            if (widget.showPurchasePrice) ...[
                              _buildPriceRow(
                                'Cost',
                                product.purchasePrice,
                                AppColors.textMuted,
                                Icons.shopping_cart_outlined,
                              ),
                              const SizedBox(height: 4),
                            ],
                            _buildPriceRow(
                              'Sale',
                              product.salePrice,
                              AppColors.blue,
                              Icons.currency_rupee,
                            ),
                            if (widget.showPurchasePrice) ...[
                              const SizedBox(height: 4),
                              _buildPriceRow(
                                'Wholesale',
                                double.parse(product.effectiveWholesalePrice
                                    .toStringAsFixed(2)),
                                const Color(0xFF7C4DFF),
                                Icons.storefront,
                              ),
                              const SizedBox(height: 4),
                              _buildProfitRow(),
                            ],
                            if (widget.showSalesInfo && product.totalSold > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.trending_up,
                                    size: 14,
                                    color: AppColors.blue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${product.totalSold} sold',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.blue,
                                      fontWeight: FontWeight.w600,
                                    ),
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
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    return GestureDetector(
      onTap: () => _showImageZoom(context),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.page,
          borderRadius: _topRadius,
        ),
        child: ClipRRect(
          borderRadius: _topRadius,
          child: product.imageBase64 != null
              ? Stack(
                  children: [
                    // Image zooms in a touch on hover.
                    AnimatedScale(
                      scale: _hover ? 1.05 : 1,
                      duration: AppMotion.normal,
                      curve: AppMotion.curve,
                      child: Image.memory(
                        base64Decode(product.imageBase64!),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildPlaceholder();
                        },
                      ),
                    ),
                    // Zoom indicator overlay
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: AnimatedOpacity(
                        opacity: _hover ? 1 : 0.75,
                        duration: AppMotion.fast,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.65),
                            borderRadius:
                                BorderRadius.circular(AppRadii.control),
                          ),
                          child: const Icon(
                            Icons.zoom_in,
                            size: 16,
                            color: Colors.white,
                          ),
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
        size: 44,
        color: AppColors.textMuted.withValues(alpha: 0.4),
      ),
    );
  }

  /// A small rounded pill, shared by every badge on the image.
  Widget _pill({
    required Color color,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStockBadge() {
    final color = product.stock == 0
        ? AppColors.stockOut
        : product.stock < 5
            ? AppColors.stockLow
            : AppColors.stockOk;
    return Positioned(
      top: 8,
      right: 8,
      child: _pill(
        color: color,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              product.stock == 0 ? Icons.warning_rounded : Icons.inventory_2,
              size: 13,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              '${product.stock}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
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
    return Positioned(
      top: 8,
      left: 8,
      child: _pill(
        color: AppColors.category(product.category),
        child: Text(
          product.category.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  Widget _buildDiscountChip() {
    Widget chip(String text, Color color) => _pill(
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.4,
            ),
          ),
        );

    return Positioned(
      top: 34,
      left: 8,
      child: product.discountReceived != null && product.sellingDiscount != null
          ? Row(
              children: [
                chip(product.discountReceived.toString(), AppColors.green),
                const SizedBox(width: 4),
                chip(product.sellingDiscount.toString(), AppColors.coral),
              ],
            )
          : chip(product.margin?.toString() ?? '', const Color(0xFF7C4DFF)),
    );
  }

  Widget _buildSalesBadge() {
    return Positioned(
      bottom: 8,
      left: 8,
      child: _pill(
        color: AppColors.coral,
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
                fontWeight: FontWeight.w700,
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
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildProfitRow() {
    final isProfit = profitAmount >= 0;
    final color = isProfit ? AppColors.green : AppColors.stockOut;

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
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${profitMargin.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
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