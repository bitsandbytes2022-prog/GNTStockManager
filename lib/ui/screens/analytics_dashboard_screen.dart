
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/sale_model.dart';
import '../../models/product_model.dart';
import '../../services/sales_service.dart';
import '../../services/firebase_service.dart';
import '../../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen>
    with SingleTickerProviderStateMixin {
  final SalesService _salesService = SalesService();
  final FirebaseService _firebaseService = FirebaseService();
  final AnalyticsService _analyticsService = AnalyticsService();

  late TabController _tabController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    // Data will be loaded via FutureBuilders
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.access_time), text: 'Timing'),
            Tab(icon: Icon(Icons.compare_arrows), text: 'Compare'),
            Tab(icon: Icon(Icons.inventory_2), text: 'Low Stock'),
            Tab(icon: Icon(Icons.payment), text: 'Payments'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _TimingAnalyticsTab(),
          _ComparisonAnalyticsTab(),
          _LowStockTab(),
          _PaymentMethodTab(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

// Tab 1: Sales Timing Analytics
class _TimingAnalyticsTab extends StatelessWidget {
  final SalesService _salesService = SalesService();
  final AnalyticsService _analyticsService = AnalyticsService();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Sale>>(
      future: _salesService.getCachedRealSales(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _AnalyticsLoading();
        }

        return FutureBuilder<SalesTimingAnalytics>(
          future: _analyticsService.getSalesTimingAnalytics(snapshot.data!),
          builder: (context, timingSnapshot) {
            if (!timingSnapshot.hasData) {
              return const _AnalyticsLoading();
            }

            final timing = timingSnapshot.data!;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick Insights Card
                  Card(
                    color: AppColors.blueTint,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lightbulb, color: AppColors.blue),
                              const SizedBox(width: 8),
                              Text(
                                'Quick Insights',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navy,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _InsightRow(
                            icon: Icons.trending_up,
                            label: 'Peak Hour',
                            value: timing.peakHourLabel,
                            color: AppColors.green,
                          ),
                          _InsightRow(
                            icon: Icons.event,
                            label: 'Busiest Day',
                            value: timing.peakDayName,
                            color: AppColors.green,
                          ),
                          _InsightRow(
                            icon: Icons.trending_down,
                            label: 'Slowest Hour',
                            value: timing.slowestHourLabel,
                            color: AppColors.stockLow,
                          ),
                          _InsightRow(
                            icon: Icons.event_busy,
                            label: 'Quietest Day',
                            value: timing.slowestDayName,
                            color: AppColors.stockLow,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Hourly Distribution
                  _SectionHeader(
                    icon: Icons.schedule,
                    title: 'Hourly Sales Pattern',
                    subtitle: 'When do most sales happen?',
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _HourlyChart(hourlySales: timing.hourlySales),
                          const SizedBox(height: 16),
                          _buildRecommendation(
                            Icons.info_outline,
                            'Best time for breaks',
                            'Consider taking breaks around ${timing.slowestHourLabel} when sales are typically slower.',
                            AppColors.blue,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Daily Distribution
                  _SectionHeader(
                    icon: Icons.calendar_today,
                    title: 'Weekly Sales Pattern',
                    subtitle: 'Which days are busiest?',
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _DailyChart(dailySales: timing.dailySales),
                          const SizedBox(height: 16),
                          _buildRecommendation(
                            Icons.info_outline,
                            'Staff scheduling tip',
                            '${timing.peakDayName} is your busiest day. Consider having extra staff available.',
                            AppColors.green,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRecommendation(
      IconData icon,
      String title,
      String message,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 12,
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

// Tab 2: Comparison Analytics
class _ComparisonAnalyticsTab extends StatefulWidget {
  @override
  State<_ComparisonAnalyticsTab> createState() =>
      _ComparisonAnalyticsTabState();
}

class _ComparisonAnalyticsTabState extends State<_ComparisonAnalyticsTab> {
  final SalesService _salesService = SalesService();
  final AnalyticsService _analyticsService = AnalyticsService();
  String _comparisonType = 'month'; // 'month', 'week', 'year'

  List<Sale> _filterSalesByPeriod(
      List<Sale> sales, DateTime start, DateTime end) {
    return sales
        .where((sale) =>
    sale.createdAt.isAfter(start) && sale.createdAt.isBefore(end))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Sale>>(
      future: _salesService.getCachedRealSales(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _AnalyticsLoading();
        }

        final now = DateTime.now();
        DateTime currentStart, currentEnd, previousStart, previousEnd;

        if (_comparisonType == 'month') {
          // This month vs last month
          currentStart = DateTime(now.year, now.month, 1);
          currentEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          previousStart = DateTime(now.year, now.month - 1, 1);
          previousEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
        } else if (_comparisonType == 'week') {
          // This week vs last week
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          currentStart = DateTime(
              startOfWeek.year, startOfWeek.month, startOfWeek.day);
          currentEnd = now;
          previousStart = currentStart.subtract(const Duration(days: 7));
          previousEnd = currentStart.subtract(const Duration(seconds: 1));
        } else {
          // This year vs last year
          currentStart = DateTime(now.year, 1, 1);
          currentEnd = now;
          previousStart = DateTime(now.year - 1, 1, 1);
          previousEnd = DateTime(now.year - 1, 12, 31, 23, 59, 59);
        }

        final currentSales =
        _filterSalesByPeriod(snapshot.data!, currentStart, currentEnd);
        final previousSales =
        _filterSalesByPeriod(snapshot.data!, previousStart, previousEnd);

        return FutureBuilder<ComparisonMetrics>(
          future: _analyticsService.getComparisonMetrics(
            currentPeriodSales: currentSales,
            previousPeriodSales: previousSales,
          ),
          builder: (context, metricsSnapshot) {
            if (!metricsSnapshot.hasData) {
              return const _AnalyticsLoading();
            }

            final metrics = metricsSnapshot.data!;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Comparison Type Selector
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ComparisonButton(
                              label: 'Week',
                              isSelected: _comparisonType == 'week',
                              onTap: () =>
                                  setState(() => _comparisonType = 'week'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ComparisonButton(
                              label: 'Month',
                              isSelected: _comparisonType == 'month',
                              onTap: () =>
                                  setState(() => _comparisonType = 'month'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ComparisonButton(
                              label: 'Year',
                              isSelected: _comparisonType == 'year',
                              onTap: () =>
                                  setState(() => _comparisonType = 'year'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Overall Status
                  Card(
                    color: metrics.isImproving
                        ? AppColors.green.withValues(alpha: 0.08)
                        : metrics.isDeclining
                        ? AppColors.stockOut.withValues(alpha: 0.08)
                        : AppColors.blueTint,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            metrics.isImproving
                                ? Icons.trending_up
                                : metrics.isDeclining
                                ? Icons.trending_down
                                : Icons.remove,
                            color: metrics.isImproving
                                ? AppColors.green
                                : metrics.isDeclining
                                ? AppColors.stockOut
                                : AppColors.blue,
                            size: 48,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  metrics.isImproving
                                      ? '📈 Business is Growing!'
                                      : metrics.isDeclining
                                      ? '📉 Sales Declining'
                                      : '➡️ Stable Performance',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  metrics.isImproving
                                      ? 'Keep up the great work!'
                                      : metrics.isDeclining
                                      ? 'Consider marketing strategies'
                                      : 'Maintain current performance',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Comparison Metrics
                  _ComparisonCard(
                    title: 'Total Sales',
                    icon: Icons.receipt,
                    currentValue: metrics.currentPeriod.totalSales.toString(),
                    previousValue:
                    metrics.previousPeriod.totalSales.toString(),
                    change: metrics.salesChange,
                  ),
                  const SizedBox(height: 12),
                  _ComparisonCard(
                    title: 'Revenue',
                    icon: Icons.currency_rupee,
                    currentValue:
                    '₹${metrics.currentPeriod.totalRevenue.toStringAsFixed(0)}',
                    previousValue:
                    '₹${metrics.previousPeriod.totalRevenue.toStringAsFixed(0)}',
                    change: metrics.revenueChange,
                  ),
                  const SizedBox(height: 12),
                  _ComparisonCard(
                    title: 'Profit',
                    icon: Icons.trending_up,
                    currentValue:
                    '₹${metrics.currentPeriod.totalProfit.toStringAsFixed(0)}',
                    previousValue:
                    '₹${metrics.previousPeriod.totalProfit.toStringAsFixed(0)}',
                    change: metrics.profitChange,
                  ),
                  const SizedBox(height: 12),
                  _ComparisonCard(
                    title: 'Items Sold',
                    icon: Icons.shopping_bag,
                    currentValue: metrics.currentPeriod.itemsSold.toString(),
                    previousValue:
                    metrics.previousPeriod.itemsSold.toString(),
                    change: metrics.itemsSoldChange,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// Tab 3: Smart Low Stock
class _LowStockTab extends StatelessWidget {
  final FirebaseService _firebaseService = FirebaseService();
  final AnalyticsService _analyticsService = AnalyticsService();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: _firebaseService.getCachedProducts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _AnalyticsLoading();
        }

        return FutureBuilder<List<LowStockProduct>>(
          future: _analyticsService.getSmartLowStockProducts(snapshot.data!),
          builder: (context, lowStockSnapshot) {
            if (!lowStockSnapshot.hasData) {
              return const _AnalyticsLoading();
            }

            final lowStockProducts = lowStockSnapshot.data!;

            if (lowStockProducts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 80, color: AppColors.green),
                    const SizedBox(height: 16),
                    Text(
                      'All products well stocked! ✅',
                      style: TextStyle(fontSize: 18, color: AppColors.textMuted),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                // Info Banner
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.blueTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.blue),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Showing items with 60%+ of stock sold',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Low Stock List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: lowStockProducts.length,
                    itemBuilder: (context, index) {
                      final item = lowStockProducts[index];
                      return _LowStockCard(item: item);
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// Tab 4: Payment Methods
class _PaymentMethodTab extends StatelessWidget {
  final SalesService _salesService = SalesService();
  final AnalyticsService _analyticsService = AnalyticsService();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Sale>>(
      future: _salesService.getCachedRealSales(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _AnalyticsLoading();
        }

        return FutureBuilder<PaymentMethodStats>(
          future: _analyticsService.getPaymentMethodStats(snapshot.data!),
          builder: (context, statsSnapshot) {
            if (!statsSnapshot.hasData) {
              return const _AnalyticsLoading();
            }

            final stats = statsSnapshot.data!;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Total Revenue Card
                  Card(
                    color: AppColors.blueTint,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet,
                              color: AppColors.blue, size: 40),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Revenue',
                                  style: TextStyle(
                                    color: AppColors.blue,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '₹${stats.totalRevenue.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: AppColors.navy,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Payment Method Breakdown
                  _PaymentMethodCard(
                    method: PaymentMethod.cash,
                    amount: stats.cashAmount,
                    count: stats.cashCount,
                    percentage: stats.cashPercentage,
                    icon: Icons.money,
                    color: AppColors.green,
                  ),
                  const SizedBox(height: 12),
                  _PaymentMethodCard(
                    method: PaymentMethod.upi,
                    amount: stats.upiAmount,
                    count: stats.upiCount,
                    percentage: stats.upiPercentage,
                    icon: Icons.qr_code_scanner,
                    color: Colors.purple,
                  ),
                  const SizedBox(height: 12),
                  _PaymentMethodCard(
                    method: PaymentMethod.card,
                    amount: stats.cardAmount,
                    count: stats.cardCount,
                    percentage: stats.cardPercentage,
                    icon: Icons.credit_card,
                    color: AppColors.blue,
                  ),
                  if (stats.otherAmount > 0) ...[
                    const SizedBox(height: 12),
                    _PaymentMethodCard(
                      method: PaymentMethod.other,
                      amount: stats.otherAmount,
                      count: stats.otherCount,
                      percentage: stats.otherPercentage,
                      icon: Icons.more_horiz,
                      color: AppColors.stockLow,
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Quick Insights
                  Card(
                    color: Colors.amber.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lightbulb,
                                  color: Colors.amber.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Cash on Hand',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'You should have approximately ₹${stats.cashAmount.toStringAsFixed(2)} in cash from ${stats.cashCount} transactions.',
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// Reusable Widgets

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InsightRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _HourlyChart extends StatelessWidget {
  final Map<int, HourStats> hourlySales;

  const _HourlyChart({required this.hourlySales});

  @override
  Widget build(BuildContext context) {
    final maxSales = hourlySales.values
        .map((h) => h.salesCount)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      children: hourlySales.entries.where((e) => e.value.salesCount > 0).map((entry) {
        final hour = entry.value;
        final percentage = maxSales > 0 ? hour.salesCount / maxSales : 0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  hour.hourLabel,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.page,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    // Bars grow from the left when the chart appears.
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: percentage.toDouble()),
                      duration: AppMotion.slow * 2,
                      curve: AppMotion.curve,
                      builder: (context, w, child) =>
                          FractionallySizedBox(widthFactor: w, child: child),
                      child: Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 30,
                child: Text(
                  '${hour.salesCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DailyChart extends StatelessWidget {
  final Map<int, DayStats> dailySales;

  const _DailyChart({required this.dailySales});

  @override
  Widget build(BuildContext context) {
    final maxSales = dailySales.values
        .map((d) => d.salesCount)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      children: dailySales.values.map((day) {
        final percentage = maxSales > 0 ? day.salesCount / maxSales : 0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  day.dayName,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    // Bars grow from the left when the chart appears.
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: percentage.toDouble()),
                      duration: AppMotion.slow * 2,
                      curve: AppMotion.curve,
                      builder: (context, w, child) =>
                          FractionallySizedBox(widthFactor: w, child: child),
                      child: Container(
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 30,
                child: Text(
                  '${day.salesCount}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ComparisonButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ComparisonButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textMuted,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String currentValue;
  final String previousValue;
  final double change;

  const _ComparisonCard({
    required this.title,
    required this.icon,
    required this.currentValue,
    required this.previousValue,
    required this.change,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = change >= 0;
    final changeColor = isPositive ? AppColors.green : AppColors.stockOut;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.blue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    Text(
                      currentValue,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  color: changeColor,
                  size: 32,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Previous',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    Text(
                      previousValue,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: changeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: changeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  final LowStockProduct item;

  const _LowStockCard({required this.item});

  @override
  Widget build(BuildContext context) {
    Color urgencyColor;
    if (item.percentageSold >= 90) {
      urgencyColor = AppColors.stockOut;
    } else if (item.percentageSold >= 80) {
      urgencyColor = AppColors.stockLow;
    } else if (item.percentageSold >= 70) {
      urgencyColor = Colors.amber;
    } else {
      urgencyColor = AppColors.blue;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.product.name} ${item.product.size}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.percentageSold.toStringAsFixed(1)}% sold from total inventory',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: urgencyColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: urgencyColor),
                  ),
                  child: Text(
                    item.urgencyLevel,
                    style: TextStyle(
                      color: urgencyColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: item.percentageSold / 100,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(urgencyColor),
              minHeight: 8,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StockInfo(
                  label: 'Current Stock',
                  value: item.product.stock.toString(),
                  icon: Icons.inventory,
                ),
                _StockInfo(
                  label: 'Total Sold',
                  value: item.product.totalSold.toString(),
                  icon: Icons.trending_up,
                ),
                _StockInfo(
                  label: 'Recommend',
                  value: '+${item.recommendedRestock}',
                  icon: Icons.add_shopping_cart,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StockInfo extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StockInfo({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.textMuted),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final PaymentMethod method;
  final double amount;
  final int count;
  final double percentage;
  final IconData icon;
  final Color color;

  const _PaymentMethodCard({
    required this.method,
    required this.amount,
    required this.count,
    required this.percentage,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$count transactions',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer placeholders shown while an analytics tab loads.
class _AnalyticsLoading extends StatelessWidget {
  const _AnalyticsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const [
        ShimmerBox(height: 150, radius: AppRadii.card),
        SizedBox(height: 16),
        ShimmerBox(width: 180, height: 16),
        SizedBox(height: 10),
        ShimmerBox(height: 220, radius: AppRadii.card),
      ],
    );
  }
}
