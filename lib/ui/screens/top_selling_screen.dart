import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/sale_model.dart';
import '../../services/sales_service.dart';

enum _Period { today, week, month, custom }

class _ProductStats {
  final String productId;
  final String productName;
  final String productSize;
  final String? imageBase64;
  int totalQuantity = 0;
  double totalRevenue = 0;
  double totalProfit = 0;
  int transactionCount = 0;

  _ProductStats({
    required this.productId,
    required this.productName,
    required this.productSize,
    this.imageBase64,
  });

  void addItem(SaleItem item) {
    totalQuantity += item.quantity;
    totalRevenue += item.salePrice * item.quantity;
    totalProfit += (item.salePrice - item.purchasePrice) * item.quantity;
    transactionCount++;
  }
}

class TopSellingScreen extends StatefulWidget {
  const TopSellingScreen({super.key});

  @override
  State<TopSellingScreen> createState() => _TopSellingScreenState();
}

class _TopSellingScreenState extends State<TopSellingScreen> {
  final SalesService _salesService = SalesService();

  _Period _selectedPeriod = _Period.week;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _isLoading = false;
  List<_ProductStats> _topProducts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  (DateTime, DateTime) _getDateRange() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _Period.today:
        return (
          DateTime(now.year, now.month, now.day),
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case _Period.week:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return (
          DateTime(monday.year, monday.month, monday.day),
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case _Period.month:
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case _Period.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return (
            DateTime(
                _customStartDate!.year, _customStartDate!.month, _customStartDate!.day),
            DateTime(
                _customEndDate!.year, _customEndDate!.month, _customEndDate!.day, 23, 59, 59),
          );
        }
        return (DateTime(now.year, now.month, 1), now);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final (start, end) = _getDateRange();
      // Exclude mock sales — they must not affect best-seller rankings.
      final sales =
          (await _salesService.getSalesInRange(startDate: start, endDate: end))
              .where((s) => !s.isMock)
              .toList();

      final Map<String, _ProductStats> statsMap = {};
      for (final sale in sales) {
        for (final item in sale.items) {
          if (!statsMap.containsKey(item.productId)) {
            statsMap[item.productId] = _ProductStats(
              productId: item.productId,
              productName: item.productName,
              productSize: item.productSize,
              imageBase64: item.imageBase64,
            );
          }
          statsMap[item.productId]!.addItem(item);
        }
      }

      final sorted = statsMap.values.toList()
        ..sort((a, b) => b.totalQuantity.compareTo(a.totalQuantity));

      setState(() {
        _topProducts = sorted;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Colors.orange,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _customStartDate = range.start;
        _customEndDate = range.end;
        _selectedPeriod = _Period.custom;
      });
      _loadData();
    }
  }

  String _periodLabel() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _Period.today:
        return 'Today — ${DateFormat('MMM dd, yyyy').format(now)}';
      case _Period.week:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return '${DateFormat('MMM dd').format(monday)} – ${DateFormat('MMM dd, yyyy').format(now)}';
      case _Period.month:
        return DateFormat('MMMM yyyy').format(now);
      case _Period.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return '${DateFormat('MMM dd').format(_customStartDate!)} – ${DateFormat('MMM dd, yyyy').format(_customEndDate!)}';
        }
        return 'Select a date range';
    }
  }

  void _selectPeriod(_Period period) {
    if (period == _Period.custom) {
      _pickCustomRange();
    } else {
      setState(() => _selectedPeriod = period);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Top Selling Items'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Period selector ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _periodLabel(),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _PeriodChip(
                        label: 'Today',
                        icon: Icons.today,
                        selected: _selectedPeriod == _Period.today,
                        onTap: () => _selectPeriod(_Period.today),
                      ),
                      const SizedBox(width: 8),
                      _PeriodChip(
                        label: 'This Week',
                        icon: Icons.calendar_view_week,
                        selected: _selectedPeriod == _Period.week,
                        onTap: () => _selectPeriod(_Period.week),
                      ),
                      const SizedBox(width: 8),
                      _PeriodChip(
                        label: 'This Month',
                        icon: Icons.calendar_month,
                        selected: _selectedPeriod == _Period.month,
                        onTap: () => _selectPeriod(_Period.month),
                      ),
                      const SizedBox(width: 8),
                      _PeriodChip(
                        label: 'Custom',
                        icon: Icons.date_range,
                        selected: _selectedPeriod == _Period.custom,
                        onTap: () => _selectPeriod(_Period.custom),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _topProducts.isEmpty
                    ? _buildEmpty()
                    : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No sales in this period',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Try selecting a different time range',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _pickCustomRange,
            icon: const Icon(Icons.date_range),
            label: const Text('Pick custom range'),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final maxQty = _topProducts.first.totalQuantity;
    final totalUnitsSold =
        _topProducts.fold(0, (sum, p) => sum + p.totalQuantity);
    final totalRevenue =
        _topProducts.fold(0.0, (sum, p) => sum + p.totalRevenue);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _topProducts.length + 1, // +1 for summary header
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildSummaryHeader(
              productCount: _topProducts.length,
              totalUnits: totalUnitsSold,
              totalRevenue: totalRevenue,
            );
          }
          final product = _topProducts[index - 1];
          return _ProductRankCard(
            rank: index,
            product: product,
            maxQuantity: maxQty,
          );
        },
      ),
    );
  }

  Widget _buildSummaryHeader({
    required int productCount,
    required int totalUnits,
    required double totalRevenue,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryChip(
            label: 'Products',
            value: '$productCount',
            icon: Icons.inventory_2,
          ),
          _SummaryChip(
            label: 'Units Sold',
            value: '$totalUnits',
            icon: Icons.shopping_bag,
          ),
          _SummaryChip(
            label: 'Revenue',
            value: '₹${totalRevenue.toStringAsFixed(0)}',
            icon: Icons.currency_rupee,
          ),
        ],
      ),
    );
  }
}

// ── Reusable Widgets ─────────────────────────────────────────────────────────

class _PeriodChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
      onSelected: (_) => onTap(),
      backgroundColor: Colors.grey[200],
      selectedColor: Colors.orange.withOpacity(0.18),
      checkmarkColor: Colors.orange[800],
      labelStyle: TextStyle(
        color: selected ? Colors.orange[800] : Colors.black87,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _ProductRankCard extends StatelessWidget {
  final int rank;
  final _ProductStats product;
  final int maxQuantity;

  const _ProductRankCard({
    required this.rank,
    required this.product,
    required this.maxQuantity,
  });

  Color get _rankColor {
    if (rank == 1) return Colors.amber.shade600;
    if (rank == 2) return Colors.blueGrey.shade400;
    if (rank == 3) return Colors.brown.shade400;
    return Colors.grey.shade500;
  }

  Color get _barColor {
    if (rank == 1) return Colors.amber.shade500;
    if (rank == 2) return Colors.blueGrey.shade400;
    if (rank == 3) return Colors.brown.shade300;
    return Colors.blue.shade300;
  }

  @override
  Widget build(BuildContext context) {
    final fillPercent =
        maxQuantity > 0 ? product.totalQuantity / maxQuantity : 0.0;
    final profitMargin = product.totalRevenue > 0
        ? (product.totalProfit / product.totalRevenue * 100)
        : 0.0;
    final isMedal = rank <= 3;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isMedal ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isMedal ? _rankColor.withOpacity(0.4) : Colors.grey.shade200,
          width: isMedal ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: rank + image + name + qty ───────────────────────
            Row(
              children: [
                // Rank badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _rankColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: isMedal
                      ? Icon(Icons.emoji_events, color: _rankColor, size: 24)
                      : Center(
                          child: Text(
                            '#$rank',
                            style: TextStyle(
                              color: _rankColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),

                // Product image
                _ProductImage(imageBase64: product.imageBase64),
                const SizedBox(width: 12),

                // Name + size
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (product.productSize.isNotEmpty)
                        Text(
                          product.productSize,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),

                // Units sold (big number)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${product.totalQuantity}',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: isMedal ? _rankColor : Colors.black87,
                      ),
                    ),
                    Text(
                      'units',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Progress bar ──────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fillPercent,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(_barColor),
                minHeight: 6,
              ),
            ),

            const SizedBox(height: 14),

            // ── Stats row ─────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatCell(
                  icon: Icons.currency_rupee,
                  value: '₹${product.totalRevenue.toStringAsFixed(0)}',
                  label: 'Revenue',
                  color: Colors.blue,
                ),
                _StatCell(
                  icon: Icons.trending_up,
                  value: '₹${product.totalProfit.toStringAsFixed(0)}',
                  label: 'Profit',
                  color: Colors.green,
                ),
                _StatCell(
                  icon: Icons.receipt_long,
                  value: '${product.transactionCount}',
                  label: 'Sales',
                  color: Colors.purple,
                ),
                _StatCell(
                  icon: Icons.percent,
                  value: '${profitMargin.toStringAsFixed(1)}%',
                  label: 'Margin',
                  color: Colors.teal,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String? imageBase64;

  const _ProductImage({this.imageBase64});

  @override
  Widget build(BuildContext context) {
    if (imageBase64 != null && imageBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(imageBase64!);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
        );
      } catch (_) {
        return _placeholder();
      }
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.inventory_2_outlined, color: Colors.grey[400], size: 24),
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCell({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
      ],
    );
  }
}
