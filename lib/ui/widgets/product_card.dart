import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/product_model.dart';

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
    required this.showPurchasePrice,
    this.showSalesInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    final profitColor = product.profitMargin >= 0 ? Colors.green : Colors.red;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Container(
                width: double.infinity,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: product.imageBase64 != null
                      ? GestureDetector(
                    onTap: () {
                      showDialog(
                        builder: (c) {
                          return Dialog(
                            child: Image.memory(
                              base64Decode(product.imageBase64!),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.broken_image,
                                  size: 40,
                                  color: Colors.grey[400],
                                );
                              },
                            ),
                          );
                        },
                        barrierDismissible: true,
                        context: context,
                      );
                    },
                    child: Image.memory(
                      base64Decode(product.imageBase64!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.broken_image,
                          size: 40,
                          color: Colors.grey[400],
                        );
                      },
                    ),
                  )
                      : Icon(
                    Icons.inventory_2,
                    size: 40,
                    color: Colors.grey[400],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Product Name and Size
              Text(
                "${product.name} ${product.size}",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Stock info
              Row(
                children: [
                  Icon(
                    Icons.inventory,
                    size: 14,
                    color: product.stock < 10 ? Colors.red : Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Stock: ${product.stock}',
                    style: TextStyle(
                      color: product.stock < 10 ? Colors.red : Colors.grey[600],
                      fontSize: 12,
                      fontWeight: product.stock < 10 ? FontWeight.bold : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Sales info (when sorting by best sellers)
              if (showSalesInfo && product.totalSold > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 12,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Sold: ${product.totalSold} (${product.saleCount}x)',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],

              const Spacer(),

              // Price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (showPurchasePrice)
                    _InfoChip(
                      label: '',
                      value: '₹${product.purchasePrice.toStringAsFixed(0)}',
                      color: Colors.orange,
                      fontSize: 11,
                    ),
                  _InfoChip(
                    label: '',
                    value: '₹${product.salePrice.toStringAsFixed(0)}',
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ],
              ),

              // Profit margin (when showing purchase prices)
              if (showPurchasePrice) ...[
                const SizedBox(height: 4),
                Text(
                  '₹${product.profitMargin.toStringAsFixed(0)} (${product.profitPercentage.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    color: profitColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final double fontSize;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.color,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}