import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/sale_model.dart';
import '../../services/sales_service.dart';

/// Screen to handle item returns and partial refunds
class ReturnItemsScreen extends StatefulWidget {
  final Sale sale;

  const ReturnItemsScreen({super.key, required this.sale});

  @override
  State<ReturnItemsScreen> createState() => _ReturnItemsScreenState();
}

class _ReturnItemsScreenState extends State<ReturnItemsScreen> {
  final SalesService _salesService = SalesService();
  final TextEditingController _reasonController = TextEditingController();

  // Track which items are being returned and how many
  final Map<String, int> _returnQuantities = {};
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Initialize with 0 returns for all items
    for (final item in widget.sale.items) {
      _returnQuantities[item.productId] = 0;
    }
  }

  double get _refundAmount {
    double total = 0;
    for (final item in widget.sale.items) {
      final returnQty = _returnQuantities[item.productId] ?? 0;
      total += item.salePrice * returnQty;
    }
    return total;
  }

  int get _totalItemsReturning {
    return _returnQuantities.values.fold(0, (sum, qty) => sum + qty);
  }

  bool get _hasItemsToReturn => _totalItemsReturning > 0;

  Future<void> _processReturn() async {
    if (!_hasItemsToReturn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select items to return')),
      );
      return;
    }

    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Return'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Return $_totalItemsReturning item(s)?'),
            const SizedBox(height: 8),
            Text(
              'Refund Amount: ₹${_refundAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This will:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text('• Update the sale record'),
            const Text('• Restore stock quantities'),
            const Text('• Update revenue counters'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm Return'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);

    try {
      await _salesService.processReturn(
        saleId: widget.sale.id,
        returnQuantities: _returnQuantities,
        reason: _reasonController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Return processed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing return: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Return Items'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Sale info header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sale #${widget.sale.id.substring(0, 8)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.sale.paymentMethod.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat('MMM dd, yyyy • hh:mm a')
                      .format(widget.sale.createdAt),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Original Amount:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '₹${widget.sale.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.sale.items.length,
              itemBuilder: (context, index) {
                final item = widget.sale.items[index];
                final returnQty = _returnQuantities[item.productId] ?? 0;

                return _ReturnItemCard(
                  item: item,
                  returnQuantity: returnQty,
                  onQuantityChanged: (newQty) {
                    setState(() {
                      _returnQuantities[item.productId] = newQty;
                    });
                  },
                );
              },
            ),
          ),

          // Return reason
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'Return Reason (Optional)',
                hintText: 'e.g., Defective, Wrong size, Customer request',
                prefixIcon: const Icon(Icons.note_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 2,
            ),
          ),

          // Bottom summary and action
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
            child: SafeArea(
              child: Column(
                children: [
                  // Summary
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Items Returning:',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '$_totalItemsReturning',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Refund Amount:',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '₹${_refundAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Process button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                      _isProcessing || !_hasItemsToReturn ? null : _processReturn,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.orange,
                      ),
                      icon: _isProcessing
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.keyboard_return),
                      label: Text(
                        _isProcessing
                            ? 'Processing...'
                            : 'Process Return',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }
}

class _ReturnItemCard extends StatelessWidget {
  final SaleItem item;
  final int returnQuantity;
  final Function(int) onQuantityChanged;

  const _ReturnItemCard({
    required this.item,
    required this.returnQuantity,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isReturning = returnQuantity > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isReturning ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isReturning ? Colors.orange : Colors.grey.shade200,
          width: isReturning ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Product info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.productSize,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${item.salePrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'each',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quantity selector
            Row(
              children: [
                Text(
                  'Purchased: ${item.quantity}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  'Return:',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),

                // Decrease button
                IconButton(
                  onPressed: returnQuantity > 0
                      ? () => onQuantityChanged(returnQuantity - 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  iconSize: 28,
                  color: Colors.orange,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.orange.shade50,
                  ),
                ),

                // Quantity display
                Container(
                  width: 50,
                  alignment: Alignment.center,
                  child: Text(
                    '$returnQuantity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isReturning ? Colors.orange : Colors.grey,
                    ),
                  ),
                ),

                // Increase button
                IconButton(
                  onPressed: returnQuantity < item.quantity
                      ? () => onQuantityChanged(returnQuantity + 1)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                  iconSize: 28,
                  color: Colors.orange,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.orange.shade50,
                  ),
                ),
              ],
            ),

            // Refund amount for this item
            if (isReturning) ...[
              const SizedBox(height: 8),
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
                      'Refund for this item:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '₹${(item.salePrice * returnQuantity).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}