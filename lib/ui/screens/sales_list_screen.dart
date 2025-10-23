import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:inventory_manager/ui/screens/record_sale_screen.dart';

import '../../models/sale_model.dart';
import '../../services/sales_service.dart';

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
  bool _useStreamMode = true;
  TimeSpan _selectedTimeSpan = TimeSpan.allTime;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  Future<void> _deleteSale(Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sale'),
        content: const Text(
          'Are you sure you want to delete this sale? Stock will be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
            const SnackBar(content: Text('Sale deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting sale: $e')));
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

  // Get date range for selected time span
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

  // Filter sales by date range
  List<Sale> _filterSalesByDateRange(List<Sale> sales) {
    if (_selectedTimeSpan == TimeSpan.allTime) return sales;

    final range = _getDateRange();
    final startDate = range['start']!;
    final endDate = range['end']!;

    return sales.where((sale) {
      return sale.createdAt.isAfter(startDate) &&
          sale.createdAt.isBefore(endDate);
    }).toList();
  }

  // Calculate detailed statistics
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
        'startDate': null,
        'endDate': null,
        'daysCovered': 0,
      };
    }

    double totalRevenue = 0;
    double totalCost = 0;
    double totalProfit = 0;
    int itemsSold = 0;

    DateTime? earliestSale;
    DateTime? latestSale;

    for (final sale in sales) {
      totalRevenue += sale.totalAmount;

      for (final item in sale.items) {
        final cost = item.purchasePrice * item.quantity;
        final profit = (item.salePrice - item.purchasePrice) * item.quantity;

        totalCost += cost;
        totalProfit += profit;
        itemsSold += item.quantity;
      }

      if (earliestSale == null || sale.createdAt.isBefore(earliestSale)) {
        earliestSale = sale.createdAt;
      }
      if (latestSale == null || sale.createdAt.isAfter(latestSale)) {
        latestSale = sale.createdAt;
      }
    }

    final profitPercentage = totalCost > 0 ? (totalProfit / totalCost) * 100 : 0;
    final averageSaleValue = sales.isNotEmpty ? totalRevenue / sales.length : 0;
    final averageProfit = sales.isNotEmpty ? totalProfit / sales.length : 0;

    int daysCovered = 0;
    if (earliestSale != null && latestSale != null) {
      daysCovered = latestSale.difference(earliestSale).inDays + 1;
    }

    return {
      'totalSales': sales.length,
      'totalRevenue': totalRevenue,
      'totalProfit': totalProfit,
      'totalCost': totalCost,
      'profitPercentage': profitPercentage,
      'itemsSold': itemsSold,
      'averageSaleValue': averageSaleValue,
      'averageProfit': averageProfit,
      'startDate': earliestSale,
      'endDate': latestSale,
      'daysCovered': daysCovered,
    };
  }

  void _showDetailedStats(List<Sale> sales) {
    final filteredSales = _filterSalesByDateRange(sales);
    final stats = _calculateDetailedStats(filteredSales);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DetailedStatsBottomSheet(
        stats: stats,
        timeSpan: _selectedTimeSpan,
        customStartDate: _customStartDate,
        customEndDate: _customEndDate,
      ),
    );
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
      case TimeSpan.custom:
        if (_customStartDate != null && _customEndDate != null) {
          final format = DateFormat('MMM dd');
          return '${format.format(_customStartDate!)} - ${format.format(_customEndDate!)}';
        }
        return 'Custom Range';
      case TimeSpan.allTime:
        return 'All Time';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Time Span Filter
          if (_selectedTimeSpan != TimeSpan.allTime)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_list, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Filtering: ${_getTimeSpanLabel()}',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.orange.shade700, size: 18),
                    onPressed: () {
                      setState(() {
                        _selectedTimeSpan = TimeSpan.allTime;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // Stats Overview with More button
          Row(
            children: [
              Expanded(
                child: _useStreamMode
                    ? StreamBuilder<List<Sale>>(
                  stream: _salesService.getSalesStream(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    final filteredSales = _filterSalesByDateRange(snapshot.data!);
                    final stats = _calculateDetailedStats(filteredSales);

                    return _StatsOverviewCard(
                      stats: stats,
                      onMorePressed: () => _showDetailedStats(snapshot.data!),
                      onFilterPressed: _showTimeSpanPicker,
                    );
                  },
                )
                    : FutureBuilder<List<Sale>>(
                  future: _salesService.getCachedSales(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox.shrink();
                    }

                    final filteredSales = _filterSalesByDateRange(snapshot.data!);
                    final stats = _calculateDetailedStats(filteredSales);

                    return _StatsOverviewCard(
                      stats: stats,
                      onMorePressed: () => _showDetailedStats(snapshot.data!),
                      onFilterPressed: _showTimeSpanPicker,
                    );
                  },
                ),
              ),
              PopupMenuButton<String>(
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
                    child: Text(
                      _useStreamMode
                          ? 'Switch to Cached mode'
                          : 'Switch to Real-time mode',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Text('Refresh'),
                  ),
                ],
              ),
            ],
          ),
          Expanded(
            child: _useStreamMode ? _buildStreamView() : _buildCachedView(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToRecordSale,
        icon: const Icon(Icons.add),
        label: const Text('Record Sale'),
      ),
    );
  }

  Future<void> _navigateToRecordSale() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecordSaleScreen()),
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
        return _buildSalesList(filteredSales);
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
        return _buildSalesList(filteredSales);
      },
    );
  }

  Widget _buildSalesList(List<Sale> sales) {
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
              _selectedTimeSpan == TimeSpan.allTime
                  ? 'No sales recorded yet'
                  : 'No sales in selected period',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            if (_selectedTimeSpan != TimeSpan.allTime) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedTimeSpan = TimeSpan.allTime;
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear Filter'),
              ),
            ],
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sales.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, index) {
        final sale = sales[index];
        final profit = _calculateSaleProfit(sale);
        final profitPercentage = _calculateSaleProfitPercentage(sale);

        return _SaleCard(
          sale: sale,
          profit: profit,
          profitPercentage: profitPercentage,
          onTap: () => _showSaleDetails(sale),
          onDelete: () => _deleteSale(sale),
        );
      },
    );
  }
}

// Stats Overview Card with More button
class _StatsOverviewCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  final VoidCallback onMorePressed;
  final VoidCallback onFilterPressed;

  const _StatsOverviewCard({
    required this.stats,
    required this.onMorePressed,
    required this.onFilterPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade500],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  icon: Icons.receipt,
                  label: 'Sales',
                  value: stats['totalSales'].toString(),
                ),
                Container(width: 1, height: 40, color: Colors.white30),
                _StatItem(
                  icon: Icons.currency_rupee,
                  label: 'Revenue',
                  value: '₹${(stats['totalRevenue'] as double).toStringAsFixed(0)}',
                ),
                Container(width: 1, height: 40, color: Colors.white30),
                _StatItem(
                  icon: Icons.shopping_bag,
                  label: 'Items',
                  value: stats['itemsSold'].toString(),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onFilterPressed,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.date_range, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Time Period',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(width: 1, height: 30, color: Colors.white30),
                Expanded(
                  child: InkWell(
                    onTap: onMorePressed,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.analytics, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'More Stats',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Detailed Stats Bottom Sheet
class _DetailedStatsBottomSheet extends StatelessWidget {
  final Map<String, dynamic> stats;
  final TimeSpan timeSpan;
  final DateTime? customStartDate;
  final DateTime? customEndDate;

  const _DetailedStatsBottomSheet({
    required this.stats,
    required this.timeSpan,
    this.customStartDate,
    this.customEndDate,
  });

  String _getTimeSpanDescription() {
    if (stats['startDate'] == null || stats['endDate'] == null) {
      return 'No sales data available';
    }

    final format = DateFormat('MMM dd, yyyy');
    final start = format.format(stats['startDate']);
    final end = format.format(stats['endDate']);

    return '$start - $end (${stats['daysCovered']} days)';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detailed Statistics',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      if (stats['startDate'] != null)
                        Text(
                          _getTimeSpanDescription(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Stats Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Revenue & Profit Section
                  _StatSection(
                    title: 'Revenue & Profit',
                    icon: Icons.monetization_on,
                    iconColor: Colors.green,
                    children: [
                      _StatRow(
                        label: 'Total Revenue',
                        value: '₹${(stats['totalRevenue'] as double).toStringAsFixed(2)}',
                        icon: Icons.attach_money,
                        valueColor: Colors.green,
                      ),
                      _StatRow(
                        label: 'Total Cost',
                        value: '₹${(stats['totalCost'] as double).toStringAsFixed(2)}',
                        icon: Icons.shopping_cart,
                        valueColor: Colors.orange,
                      ),
                      _StatRow(
                        label: 'Total Profit',
                        value: '₹${(stats['totalProfit'] as double).toStringAsFixed(2)}',
                        icon: Icons.trending_up,
                        valueColor: Colors.blue,
                        isBold: true,
                      ),
                      _StatRow(
                        label: 'Profit Percentage',
                        value: '${(stats['profitPercentage'] as double).toStringAsFixed(2)}%',
                        icon: Icons.percent,
                        valueColor: (stats['profitPercentage'] as double) >= 30
                            ? Colors.green
                            : (stats['profitPercentage'] as double) >= 15
                            ? Colors.orange
                            : Colors.red,
                        isBold: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Sales Activity Section
                  _StatSection(
                    title: 'Sales Activity',
                    icon: Icons.shopping_bag,
                    iconColor: Colors.blue,
                    children: [
                      _StatRow(
                        label: 'Total Sales',
                        value: stats['totalSales'].toString(),
                        icon: Icons.receipt,
                      ),
                      _StatRow(
                        label: 'Items Sold',
                        value: stats['itemsSold'].toString(),
                        icon: Icons.inventory,
                      ),
                      _StatRow(
                        label: 'Avg Sale Value',
                        value: '₹${(stats['averageSaleValue'] as double).toStringAsFixed(2)}',
                        icon: Icons.calculate,
                      ),
                      _StatRow(
                        label: 'Avg Profit/Sale',
                        value: '₹${(stats['averageProfit'] as double).toStringAsFixed(2)}',
                        icon: Icons.star,
                        valueColor: Colors.green,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Performance Insights
                  if (stats['daysCovered'] > 0)
                    _StatSection(
                      title: 'Performance Insights',
                      icon: Icons.insights,
                      iconColor: Colors.purple,
                      children: [
                        _StatRow(
                          label: 'Days Covered',
                          value: '${stats['daysCovered']} days',
                          icon: Icons.calendar_today,
                        ),
                        _StatRow(
                          label: 'Avg Sales/Day',
                          value: (stats['totalSales'] / stats['daysCovered'])
                              .toStringAsFixed(2),
                          icon: Icons.speed,
                        ),
                        _StatRow(
                          label: 'Avg Revenue/Day',
                          value:
                          '₹${(stats['totalRevenue'] / stats['daysCovered']).toStringAsFixed(2)}',
                          icon: Icons.timeline,
                        ),
                        _StatRow(
                          label: 'Avg Profit/Day',
                          value:
                          '₹${(stats['totalProfit'] / stats['daysCovered']).toStringAsFixed(2)}',
                          icon: Icons.trending_up,
                          valueColor: Colors.green,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // Close Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                child: const Text('Close'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Time Span Picker Bottom Sheet
class _TimeSpanPickerBottomSheet extends StatefulWidget {
  final TimeSpan selectedTimeSpan;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final Function(TimeSpan, DateTime?, DateTime?) onTimeSpanSelected;

  const _TimeSpanPickerBottomSheet({
    required this.selectedTimeSpan,
    this.customStartDate,
    this.customEndDate,
    required this.onTimeSpanSelected,
  });

  @override
  State<_TimeSpanPickerBottomSheet> createState() =>
      _TimeSpanPickerBottomSheetState();
}

class _TimeSpanPickerBottomSheetState
    extends State<_TimeSpanPickerBottomSheet> {
  late TimeSpan _selectedTimeSpan;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _selectedTimeSpan = widget.selectedTimeSpan;
    _customStartDate = widget.customStartDate;
    _customEndDate = widget.customEndDate;
  }

  Future<void> _pickCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _selectedTimeSpan = TimeSpan.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.date_range, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                const Text(
                  'Select Time Period',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _TimeSpanOption(
                    title: 'Today',
                    icon: Icons.today,
                    isSelected: _selectedTimeSpan == TimeSpan.today,
                    onTap: () => widget.onTimeSpanSelected(TimeSpan.today, null, null),
                  ),
                  _TimeSpanOption(
                    title: 'Yesterday',
                    icon: Icons.calendar_today,
                    isSelected: _selectedTimeSpan == TimeSpan.yesterday,
                    onTap: () =>
                        widget.onTimeSpanSelected(TimeSpan.yesterday, null, null),
                  ),
                  _TimeSpanOption(
                    title: 'Last 7 Days',
                    icon: Icons.date_range,
                    isSelected: _selectedTimeSpan == TimeSpan.last7Days,
                    onTap: () =>
                        widget.onTimeSpanSelected(TimeSpan.last7Days, null, null),
                  ),
                  _TimeSpanOption(
                    title: 'Last 30 Days',
                    icon: Icons.date_range,
                    isSelected: _selectedTimeSpan == TimeSpan.last30Days,
                    onTap: () =>
                        widget.onTimeSpanSelected(TimeSpan.last30Days, null, null),
                  ),
                  const Divider(),
                  _TimeSpanOption(
                    title: 'This Month',
                    icon: Icons.calendar_month,
                    isSelected: _selectedTimeSpan == TimeSpan.thisMonth,
                    onTap: () =>
                        widget.onTimeSpanSelected(TimeSpan.thisMonth, null, null),
                  ),
                  _TimeSpanOption(
                    title: 'Last Month',
                    icon: Icons.calendar_month,
                    isSelected: _selectedTimeSpan == TimeSpan.lastMonth,
                    onTap: () =>
                        widget.onTimeSpanSelected(TimeSpan.lastMonth, null, null),
                  ),
                  _TimeSpanOption(
                    title: 'Last 3 Months',
                    icon: Icons.date_range,
                    isSelected: _selectedTimeSpan == TimeSpan.last3Months,
                    onTap: () =>
                        widget.onTimeSpanSelected(TimeSpan.last3Months, null, null),
                  ),
                  _TimeSpanOption(
                    title: 'Last 6 Months',
                    icon: Icons.date_range,
                    isSelected: _selectedTimeSpan == TimeSpan.last6Months,
                    onTap: () =>
                        widget.onTimeSpanSelected(TimeSpan.last6Months, null, null),
                  ),
                  const Divider(),
                  _TimeSpanOption(
                    title: 'This Year',
                    icon: Icons.calendar_month_outlined,
                    isSelected: _selectedTimeSpan == TimeSpan.thisYear,
                    onTap: () =>
                        widget.onTimeSpanSelected(TimeSpan.thisYear, null, null),
                  ),
                  _TimeSpanOption(
                    title: 'All Time',
                    icon: Icons.all_inclusive,
                    isSelected: _selectedTimeSpan == TimeSpan.allTime,
                    onTap: () =>
                        widget.onTimeSpanSelected(TimeSpan.allTime, null, null),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      Icons.edit_calendar,
                      color: _selectedTimeSpan == TimeSpan.custom
                          ? Colors.blue
                          : Colors.grey[600],
                    ),
                    title: Text(
                      _selectedTimeSpan == TimeSpan.custom &&
                          _customStartDate != null &&
                          _customEndDate != null
                          ? '${DateFormat('MMM dd').format(_customStartDate!)} - ${DateFormat('MMM dd').format(_customEndDate!)}'
                          : 'Custom Range',
                      style: TextStyle(
                        fontWeight: _selectedTimeSpan == TimeSpan.custom
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: _selectedTimeSpan == TimeSpan.custom
                            ? Colors.blue
                            : null,
                      ),
                    ),
                    trailing: Icon(
                      _selectedTimeSpan == TimeSpan.custom
                          ? Icons.check_circle
                          : Icons.chevron_right,
                      color: _selectedTimeSpan == TimeSpan.custom
                          ? Colors.blue
                          : Colors.grey[400],
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _pickCustomDateRange();
                      if (_customStartDate != null && _customEndDate != null) {
                        widget.onTimeSpanSelected(
                          TimeSpan.custom,
                          _customStartDate,
                          _customEndDate,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeSpanOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TimeSpanOption({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Colors.blue : Colors.grey[600],
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.blue : null,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.blue)
          : null,
      onTap: onTap,
    );
  }
}

class _StatSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _StatSection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final bool isBold;

  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _SaleCard extends StatelessWidget {
  final Sale sale;
  final double profit;
  final double profitPercentage;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SaleCard({
    required this.sale,
    required this.profit,
    required this.profitPercentage,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final timeFormat = DateFormat('hh:mm a');

    final previewImages = sale.items
        .where((item) => item.imageBase64 != null)
        .take(3)
        .map((item) => item.imageBase64!)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateFormat.format(sale.createdAt),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          timeFormat.format(sale.createdAt),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                    color: Colors.red,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              if (previewImages.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      ...previewImages.asMap().entries.map((entry) {
                        return Container(
                          width: 50,
                          height: 50,
                          margin: EdgeInsets.only(
                            right: entry.key < previewImages.length - 1 ? 4 : 0,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              base64Decode(entry.value),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.broken_image,
                                  size: 20,
                                  color: Colors.grey[400],
                                );
                              },
                            ),
                          ),
                        );
                      }),
                      if (sale.items.length > 3)
                        Container(
                          width: 50,
                          height: 50,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.blue.shade300,
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '+${sale.items.length - 3}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${sale.items.length} items',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  Text(
                    '₹${sale.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color:
                  profit >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: profit >= 0
                        ? Colors.green.shade200
                        : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          profit >= 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 16,
                          color: profit >= 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Profit',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${profit.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: profit >= 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                        Text(
                          '${profitPercentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: profit >= 0
                                ? Colors.green.shade600
                                : Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (sale.notes != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.note, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sale.notes!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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

class _SaleDetailsDialog extends StatelessWidget {
  final Sale sale;

  const _SaleDetailsDialog({required this.sale});

  double _calculateItemProfit(SaleItem item) {
    return (item.salePrice - item.purchasePrice) * item.quantity;
  }

  double _calculateItemProfitPercentage(SaleItem item) {
    if (item.purchasePrice == 0) return 0;
    return ((item.salePrice - item.purchasePrice) / item.purchasePrice) * 100;
  }

  double _calculateTotalProfit() {
    return sale.items
        .fold(0.0, (sum, item) => sum + _calculateItemProfit(item));
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy - hh:mm a');
    final totalProfit = _calculateTotalProfit();

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Sale Details',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateFormat.format(sale.createdAt),
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Items:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...sale.items.map((item) {
                      final profit = _calculateItemProfit(item);
                      final profitPercentage =
                      _calculateItemProfitPercentage(item);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: item.imageBase64 != null
                                    ? Image.memory(
                                  base64Decode(item.imageBase64!),
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (context, error, stackTrace) {
                                    return Icon(
                                      Icons.broken_image,
                                      size: 30,
                                      color: Colors.grey[400],
                                    );
                                  },
                                )
                                    : Icon(
                                  Icons.inventory_2,
                                  size: 30,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.productName} ${item.productSize}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Qty: ${item.quantity}',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            'Cost: ₹${item.purchasePrice.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            'Sale: ₹${item.salePrice.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '₹${item.total.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: profit >= 0
                                                  ? Colors.green.shade100
                                                  : Colors.red.shade100,
                                              borderRadius:
                                              BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '+₹${profit.toStringAsFixed(2)} (${profitPercentage.toStringAsFixed(1)}%)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: profit >= 0
                                                    ? Colors.green.shade700
                                                    : Colors.red.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Profit:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₹${totalProfit.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: totalProfit >= 0
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Amount:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₹${sale.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (sale.notes != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Notes:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          sale.notes!,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}