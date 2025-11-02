import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:inventory_manager/ui/screens/record_sale_screen.dart';

import '../../models/sale_model.dart';
import '../../services/sales_service.dart';
import 'package:inventory_manager/ui/screens/return_items_screen.dart';

import 'edit_sales_screen.dart';

enum TimeSpan {
  today,
  yesterday,
  last7Days,
  last30Days,
  thisMonth,
  lastMonth,
  last3Months,
  last6Months,
  thisYear,
  allTime,
  custom,
}

class SalesListScreen extends StatefulWidget {
  const SalesListScreen({super.key});

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  final SalesService _salesService = SalesService();
  final ScrollController _scrollController = ScrollController();

  bool _useStreamMode = true;
  TimeSpan _selectedTimeSpan = TimeSpan.allTime;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;
  bool get _isTablet => MediaQuery.of(context).size.width >= 768;

  // ==========================================
  // RESPONSIVE GRID CONFIGURATION
  // ==========================================

  Future<void> _editSale(Sale sale) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditSaleScreen(sale: sale),
      ),
    );

    if (result == true) {
      _refreshSales();
    }
  }


  /// Calculate number of columns based on screen width
  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (kIsWeb) {
      if (width > 1400) return 5;
      if (width > 1200) return 4;
      if (width > 900) return 3;
      if (width > 600) return 2;
      return 1;
    } else {
      return 2;
    }
  }

  /// Calculate spacing between grid items
  double _getGridSpacing(BuildContext context) {
    return kIsWeb ? 20 : 16;
  }

  /// Calculate aspect ratio for grid items
  /// Sales cards need to be taller than product cards to prevent overflow
  double _getChildAspectRatio(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // Very conservative ratios to ensure all content fits comfortably
    // Lower ratio = Taller cards = More space for content
    if (width > 1600) return 1.4;   // Very wide desktop
    if (width > 1400) return 1.3;   // Wide desktop
    if (width > 1200) return 1.2;   // Desktop
    if (width > 900) return 1.1;    // Small desktop/tablet
    if (width > 600) return 1.0;    // Large phone
    return 0.85;                    // Phone (taller than wide)
  }

  Future<void> _returnItems(Sale sale) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReturnItemsScreen(sale: sale),
      ),
    );

    if (result == true) {
      _refreshSales();
    }
  }

  Future<void> _deleteSale(Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Sale'),
        content: const Text(
          'Are you sure you want to delete this sale? Stock will be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _salesService.deleteSale(sale.id, sale.items);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sale deleted successfully'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting sale: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _showSaleDetails(Sale sale) async {
    await showDialog(
      context: context,
      builder: (context) => _SaleDetailsDialog(sale: sale),
    );
  }

  Future<void> _refreshSales() async {
    _salesService.clearCache();
    setState(() {});
  }

  double _calculateSaleProfit(Sale sale) {
    return sale.items.fold(0.0, (sum, item) {
      final profit = (item.salePrice - item.purchasePrice) * item.quantity;
      return sum + profit;
    });
  }

  double _calculateSaleProfitPercentage(Sale sale) {
    final totalCost = sale.items.fold(0.0, (sum, item) {
      return sum + (item.purchasePrice * item.quantity);
    });

    if (totalCost == 0) return 0;

    final profit = _calculateSaleProfit(sale);
    return (profit / totalCost) * 100;
  }

  Map<String, DateTime> _getDateRange() {
    final now = DateTime.now();
    DateTime startDate;
    DateTime endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_selectedTimeSpan) {
      case TimeSpan.today:
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case TimeSpan.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        startDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
        endDate = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
        break;
      case TimeSpan.last7Days:
        startDate = now.subtract(const Duration(days: 7));
        break;
      case TimeSpan.last30Days:
        startDate = now.subtract(const Duration(days: 30));
        break;
      case TimeSpan.thisMonth:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case TimeSpan.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        startDate = lastMonth;
        endDate = DateTime(now.year, now.month, 0, 23, 59, 59);
        break;
      case TimeSpan.last3Months:
        startDate = DateTime(now.year, now.month - 3, now.day);
        break;
      case TimeSpan.last6Months:
        startDate = DateTime(now.year, now.month - 6, now.day);
        break;
      case TimeSpan.thisYear:
        startDate = DateTime(now.year, 1, 1);
        break;
      case TimeSpan.custom:
        startDate = _customStartDate ?? DateTime(2000, 1, 1);
        endDate = _customEndDate ?? now;
        break;
      case TimeSpan.allTime:
        startDate = DateTime(2000, 1, 1);
        endDate = DateTime(2100, 12, 31);
        break;
    }

    return {'start': startDate, 'end': endDate};
  }

  List<Sale> _filterSalesByDateRange(List<Sale> sales) {
    if (_selectedTimeSpan == TimeSpan.allTime) return sales;

    final range = _getDateRange();
    final startDate = range['start']!;
    final endDate = range['end']!;

    return sales.where((sale) {
      return sale.createdAt.isAfter(startDate) && sale.createdAt.isBefore(endDate);
    }).toList();
  }

  Map<String, dynamic> _calculateDetailedStats(List<Sale> sales) {
    if (sales.isEmpty) {
      return {
        'totalSales': 0,
        'totalRevenue': 0.0,
        'totalProfit': 0.0,
        'totalCost': 0.0,
        'profitPercentage': 0.0,
        'itemsSold': 0,
        'averageSaleValue': 0.0,
        'averageProfit': 0.0,
      };
    }

    double totalRevenue = 0;
    double totalCost = 0;
    double totalProfit = 0;
    int itemsSold = 0;

    for (final sale in sales) {
      totalRevenue += sale.totalAmount;

      for (final item in sale.items) {
        final cost = item.purchasePrice * item.quantity;
        final profit = (item.salePrice - item.purchasePrice) * item.quantity;

        totalCost += cost;
        totalProfit += profit;
        itemsSold += item.quantity;
      }
    }

    final profitPercentage = totalCost > 0 ? (totalProfit / totalCost) * 100 : 0;
    final averageSaleValue = sales.isNotEmpty ? totalRevenue / sales.length : 0;
    final averageProfit = sales.isNotEmpty ? totalProfit / sales.length : 0;

    return {
      'totalSales': sales.length,
      'totalRevenue': totalRevenue,
      'totalProfit': totalProfit,
      'totalCost': totalCost,
      'profitPercentage': profitPercentage,
      'itemsSold': itemsSold,
      'averageSaleValue': averageSaleValue,
      'averageProfit': averageProfit,
    };
  }

  void _showTimeSpanPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TimeSpanPickerBottomSheet(
        selectedTimeSpan: _selectedTimeSpan,
        customStartDate: _customStartDate,
        customEndDate: _customEndDate,
        onTimeSpanSelected: (timeSpan, startDate, endDate) {
          setState(() {
            _selectedTimeSpan = timeSpan;
            _customStartDate = startDate;
            _customEndDate = endDate;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  String _getTimeSpanLabel() {
    switch (_selectedTimeSpan) {
      case TimeSpan.today:
        return 'Today';
      case TimeSpan.yesterday:
        return 'Yesterday';
      case TimeSpan.last7Days:
        return 'Last 7 Days';
      case TimeSpan.last30Days:
        return 'Last 30 Days';
      case TimeSpan.thisMonth:
        return 'This Month';
      case TimeSpan.lastMonth:
        return 'Last Month';
      case TimeSpan.last3Months:
        return 'Last 3 Months';
      case TimeSpan.last6Months:
        return 'Last 6 Months';
      case TimeSpan.thisYear:
        return 'This Year';
      case TimeSpan.allTime:
        return 'All Time';
      case TimeSpan.custom:
        return 'Custom Range';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Header with filters
          Container(
            padding: EdgeInsets.all(_isDesktop ? 24 : 16),
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
              children: [
                Row(
                  children: [
                    // Time period selector
                    Expanded(
                      child: InkWell(
                        onTap: _showTimeSpanPicker,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 20),
                              const SizedBox(width: 12),
                              Text(
                                _getTimeSpanLabel(),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              const Icon(Icons.keyboard_arrow_down, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Settings menu
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
                          _refreshSales();
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'mode',
                          child: Row(
                            children: [
                              Icon(
                                _useStreamMode ? Icons.stream : Icons.cached,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(_useStreamMode ? 'Real-time Mode' : 'Cached Mode'),
                              const Spacer(),
                              Icon(
                                _useStreamMode ? Icons.check : null,
                                size: 16,
                                color: Colors.green,
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
              ],
            ),
          ),

          // Sales grid
          Expanded(
            child: _useStreamMode ? _buildStreamView() : _buildCachedView(),
          ),
        ],
      ),
      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RecordSaleScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Record Sale'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildStreamView() {
    return StreamBuilder<List<Sale>>(
      stream: _salesService.getSalesStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final filteredSales = _filterSalesByDateRange(snapshot.data ?? []);
        return _buildSalesContent(filteredSales);
      },
    );
  }

  Widget _buildCachedView() {
    return FutureBuilder<List<Sale>>(
      future: _salesService.getCachedSales(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final filteredSales = _filterSalesByDateRange(snapshot.data ?? []);
        return _buildSalesContent(filteredSales);
      },
    );
  }

  Widget _buildSalesContent(List<Sale> sales) {
    if (sales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No sales yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecordSaleScreen()),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Record First Sale'),
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

    final stats = _calculateDetailedStats(sales);
    final crossAxisCount = _getCrossAxisCount(context);
    final spacing = _getGridSpacing(context);
    final aspectRatio = _getChildAspectRatio(context);

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Summary Card
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(spacing),
            child: _SummaryCard(stats: stats),
          ),
        ),

        // Sales Grid
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: spacing),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
            ),
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final sale = sales[index];
                return _SaleCard(
                  sale: sale,
                  onTap: () => _showSaleDetails(sale),
                  onEdit: () => _editSale(sale),
                  onDelete: () => _deleteSale(sale),
                  onReturn: () => _returnItems(sale),
                  profit: _calculateSaleProfit(sale),
                  profitPercentage: _calculateSaleProfitPercentage(sale),
                );
              },
              childCount: sales.length,
            ),
          ),
        ),

        // Bottom spacing
        SliverToBoxAdapter(
          child: SizedBox(height: spacing),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

// ==========================================
// SUMMARY CARD - Single comprehensive card
// ==========================================
class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _SummaryCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1200;
    final isTablet = MediaQuery.of(context).size.width >= 768;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(isDesktop ? 28 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.analytics_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sales Summary',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Overview of your performance',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Stats Grid
              if (isDesktop || isTablet)
              // Desktop/Tablet: 4 columns
                Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        icon: Icons.receipt_long,
                        label: 'Total Sales',
                        value: '${stats['totalSales']}',
                        iconColor: Colors.orange.shade300,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _StatItem(
                        icon: Icons.currency_rupee,
                        label: 'Revenue',
                        value: '₹${stats['totalRevenue'].toStringAsFixed(0)}',
                        iconColor: Colors.green.shade300,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _StatItem(
                        icon: Icons.trending_up,
                        label: 'Profit',
                        value: '₹${stats['totalProfit'].toStringAsFixed(0)}',
                        subtitle: '${stats['profitPercentage'].toStringAsFixed(1)}% margin',
                        iconColor: Colors.purple.shade300,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _StatItem(
                        icon: Icons.shopping_bag,
                        label: 'Items Sold',
                        value: '${stats['itemsSold']}',
                        iconColor: Colors.pink.shade300,
                      ),
                    ),
                  ],
                )
              else
              // Mobile: 2x2 grid
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _StatItem(
                            icon: Icons.receipt_long,
                            label: 'Total Sales',
                            value: '${stats['totalSales']}',
                            iconColor: Colors.orange.shade300,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _StatItem(
                            icon: Icons.currency_rupee,
                            label: 'Revenue',
                            value: '₹${stats['totalRevenue'].toStringAsFixed(0)}',
                            iconColor: Colors.green.shade300,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _StatItem(
                            icon: Icons.trending_up,
                            label: 'Profit',
                            value: '₹${stats['totalProfit'].toStringAsFixed(0)}',
                            subtitle: '${stats['profitPercentage'].toStringAsFixed(1)}%',
                            iconColor: Colors.purple.shade300,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _StatItem(
                            icon: Icons.shopping_bag,
                            label: 'Items Sold',
                            value: '${stats['itemsSold']}',
                            iconColor: Colors.pink.shade300,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Individual stat item
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color iconColor;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
              Column(children: [Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],],)
            ],
          ),


        ],
      ),
    );
  }
}

// ==========================================
// SALE CARD - Grid item
// ==========================================
class _SaleCard extends StatelessWidget {
  final Sale sale;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onReturn;
  final double profit;
  final double profitPercentage;

  const _SaleCard({
    required this.sale,
    required this.onTap,
    required this.onDelete,
    required this.onReturn,
    required this.onEdit,
    required this.profit,
    required this.profitPercentage,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = sale.items.fold(0, (sum, item) => sum + item.quantity);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with amount and actions
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '₹${sale.totalAmount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$itemCount item${itemCount != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Action buttons
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Edit Sales', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'return',
                        child: Row(
                          children: [
                            Icon(Icons.keyboard_return, size: 18),
                            SizedBox(width: 8),
                            Text('Return Items', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete Sale', style: TextStyle(color: Colors.red, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'return') {
                        onReturn();
                      } else if (value == 'delete') {
                        onDelete();
                      }else if (value == 'edit') {
                        onEdit();
                      }
                    },
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Profit badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: profit >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: profit >= 0
                        ? Colors.green.shade200
                        : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      profit >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 11,
                      color: profit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '₹${profit.abs().toStringAsFixed(0)} (${profitPercentage.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: profit >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Footer with date and payment
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.access_time, size: 11, color: Colors.grey[600]),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      DateFormat('MMM dd, hh:mm a').format(sale.createdAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),

              if (sale.paymentMethod != null) ...[
                const SizedBox(height: 4),
                _PaymentBadge(method: sale.paymentMethod!.label),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Payment Method Badge
class _PaymentBadge extends StatelessWidget {
  final String method;

  const _PaymentBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (method.toLowerCase()) {
      case 'cash':
        icon = Icons.money;
        color = Colors.green;
        break;
      case 'upi':
        icon = Icons.qr_code;
        color = Colors.purple;
        break;
      case 'card':
        icon = Icons.credit_card;
        color = Colors.blue;
        break;
      default:
        icon = Icons.payment;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 3),
          Text(
            method.toUpperCase(),
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// Time Span Picker Bottom Sheet
class _TimeSpanPickerBottomSheet extends StatelessWidget {
  final TimeSpan selectedTimeSpan;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final Function(TimeSpan, DateTime?, DateTime?) onTimeSpanSelected;

  const _TimeSpanPickerBottomSheet({
    required this.selectedTimeSpan,
    required this.customStartDate,
    required this.customEndDate,
    required this.onTimeSpanSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Text(
                  'Select Time Period',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              shrinkWrap: true,
              children: [
                _buildTimeSpanTile(context, TimeSpan.today, 'Today'),
                _buildTimeSpanTile(context, TimeSpan.yesterday, 'Yesterday'),
                _buildTimeSpanTile(context, TimeSpan.last7Days, 'Last 7 Days'),
                _buildTimeSpanTile(context, TimeSpan.last30Days, 'Last 30 Days'),
                _buildTimeSpanTile(context, TimeSpan.thisMonth, 'This Month'),
                _buildTimeSpanTile(context, TimeSpan.lastMonth, 'Last Month'),
                _buildTimeSpanTile(context, TimeSpan.last3Months, 'Last 3 Months'),
                _buildTimeSpanTile(context, TimeSpan.thisYear, 'This Year'),
                _buildTimeSpanTile(context, TimeSpan.allTime, 'All Time'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSpanTile(BuildContext context, TimeSpan span, String label) {
    final isSelected = selectedTimeSpan == span;
    return ListTile(
      title: Text(label),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
      selected: isSelected,
      onTap: () => onTimeSpanSelected(span, null, null),
    );
  }
}

// Sale Details Dialog
class _SaleDetailsDialog extends StatelessWidget {
  final Sale sale;

  const _SaleDetailsDialog({required this.sale});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Sale Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...sale.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${item.productName} (${item.productSize})'),
                  ),
                  Text('${item.quantity} × ₹${item.salePrice.toStringAsFixed(0)}'),
                ],
              ),
            )),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '₹${sale.totalAmount.toStringAsFixed(0)}',
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
    );
  }
}