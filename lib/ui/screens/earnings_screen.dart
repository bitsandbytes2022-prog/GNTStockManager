import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/sale_model.dart';
import '../../services/sales_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

enum TimePeriod { today, week, month, custom }

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  final SalesService _salesService = SalesService();

  TimePeriod _selectedPeriod = TimePeriod.today;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  List<Sale> _sales = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);
    try {
      // Exclude mock sales — they are for profit-checking only and must not
      // affect earnings analytics.
      final allSales = (await _salesService.getCachedSales())
          .where((s) => !s.isMock)
          .toList();
      setState(() {
        _sales = _filterSalesByPeriod(allSales);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sales: $e')),
        );
      }
    }
  }

  List<Sale> _filterSalesByPeriod(List<Sale> allSales) {
    final now = DateTime.now();
    DateTime startDate;
    DateTime endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_selectedPeriod) {
      case TimePeriod.today:
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case TimePeriod.week:
        // Start from Monday of current week
        final weekday = now.weekday;
        startDate = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weekday - 1));
        break;
      case TimePeriod.month:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case TimePeriod.custom:
        if (_customStartDate == null || _customEndDate == null) {
          return [];
        }
        startDate = _customStartDate!;
        endDate = DateTime(_customEndDate!.year, _customEndDate!.month,
            _customEndDate!.day, 23, 59, 59);
        break;
    }

    return allSales.where((sale) {
      return sale.createdAt.isAfter(startDate) &&
          sale.createdAt.isBefore(endDate.add(const Duration(seconds: 1)));
    }).toList();
  }

  double get _totalRevenue {
    return _sales.fold(0, (sum, sale) => sum + sale.totalAmount);
  }

  double get _totalProfit {
    return _sales.fold(0, (sum, sale) {
      final saleProfit = sale.items.fold(0.0, (itemSum, item) {
        final profit = (item.salePrice - item.purchasePrice) * item.quantity;
        return itemSum + profit;
      });
      return sum + saleProfit;
    });
  }

  double get _totalCost {
    return _sales.fold(0, (sum, sale) {
      final saleCost = sale.items.fold(0.0, (itemSum, item) {
        return itemSum + (item.purchasePrice * item.quantity);
      });
      return sum + saleCost;
    });
  }

  int get _totalTransactions {
    return _sales.length;
  }

  int get _totalItemsSold {
    return _sales.fold(0, (sum, sale) {
      final itemCount = sale.items.fold(0, (itemSum, item) => itemSum + item.quantity);
      return sum + itemCount;
    });
  }

  Map<String, double> get _paymentMethodBreakdown {
    final breakdown = <String, double>{};
    for (final sale in _sales) {
      final method = sale.paymentMethod.toString().split('.').last;
      breakdown[method] = (breakdown[method] ?? 0) + sale.totalAmount;
    }
    return breakdown;
  }

  String _getPeriodLabel() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case TimePeriod.today:
        return 'Today - ${DateFormat('MMM dd, yyyy').format(now)}';
      case TimePeriod.week:
        final weekday = now.weekday;
        final monday = now.subtract(Duration(days: weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        return 'This Week - ${DateFormat('MMM dd').format(monday)} to ${DateFormat('MMM dd, yyyy').format(sunday)}';
      case TimePeriod.month:
        return 'This Month - ${DateFormat('MMMM yyyy').format(now)}';
      case TimePeriod.custom:
        if (_customStartDate == null || _customEndDate == null) {
          return 'Select Date Range';
        }
        return '${DateFormat('MMM dd').format(_customStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_customEndDate!)}';
    }
  }

  Future<void> _selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customStartDate != null && _customEndDate != null
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _selectedPeriod = TimePeriod.custom;
      });
      _loadSales();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        elevation: 0,
        title: const Text('Earnings'),
        backgroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Time period selector
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getPeriodLabel(),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPeriodChip('Today', TimePeriod.today, Icons.today),
                      const SizedBox(width: 8),
                      _buildPeriodChip('This Week', TimePeriod.week, Icons.calendar_view_week),
                      const SizedBox(width: 8),
                      _buildPeriodChip('This Month', TimePeriod.month, Icons.calendar_month),
                      const SizedBox(width: 8),
                      _buildPeriodChip('Custom', TimePeriod.custom, Icons.date_range,
                          onTap: _selectCustomDateRange),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? _buildLoading()
                : _sales.isEmpty
                    ? _buildEmptyState()
                    : _buildEarningsContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String label, TimePeriod period, IconData icon,
      {VoidCallback? onTap}) {
    final isSelected = _selectedPeriod == period;
    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.blueTint : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppColors.blue : AppColors.border,
          width: isSelected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (period == TimePeriod.custom) {
            onTap?.call();
          } else {
            setState(() => _selectedPeriod = period);
            _loadSales();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: isSelected ? AppColors.blue : AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? AppColors.blue : AppColors.text,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shimmer placeholders for the stat cards while the period loads.
  Widget _buildLoading() {
    Widget row() => const Row(
          children: [
            Expanded(child: ShimmerBox(height: 96, radius: AppRadii.card)),
            SizedBox(width: 12),
            Expanded(child: ShimmerBox(height: 96, radius: AppRadii.card)),
          ],
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        row(),
        const SizedBox(height: 12),
        row(),
        const SizedBox(height: 12),
        const ShimmerBox(height: 84, radius: AppRadii.card),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.blueTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_outlined,
                size: 56, color: AppColors.blue),
          ),
          const SizedBox(height: 16),
          const Text(
            'No sales in this period',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.navy,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedPeriod == TimePeriod.custom
                ? 'Try selecting a different date range'
                : 'Try selecting a different time period',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsContent() {
    return RefreshIndicator(
      onRefresh: _loadSales,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary Cards
            FadeSlideIn(child: _buildSummaryCards()),
            const SizedBox(height: 24),

            // Payment Method Breakdown
            if (_paymentMethodBreakdown.isNotEmpty) ...[
              _buildSectionHeader('Payment Methods'),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: FadeSlideIn.stagger(3),
                child: _buildPaymentMethodBreakdown(),
              ),
              const SizedBox(height: 24),
            ],

            // Sales List
            _buildSectionHeader('Transactions (${_totalTransactions})'),
            const SizedBox(height: 12),
            _buildSalesList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        // Revenue and Profit Row
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Revenue',
                _totalRevenue,
                _rupees,
                Icons.currency_rupee,
                AppColors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Total Profit',
                _totalProfit,
                _rupees,
                Icons.trending_up,
                AppColors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Transactions and Items Row
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Transactions',
                _totalTransactions.toDouble(),
                _count,
                Icons.receipt,
                AppColors.coral,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Items Sold',
                _totalItemsSold.toDouble(),
                _count,
                Icons.shopping_cart,
                const Color(0xFF7C4DFF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Profit Margin Card
        _buildProfitMarginCard(),
      ],
    );
  }

  static String _rupees(double v) => '₹${v.toStringAsFixed(2)}';
  static String _count(double v) => v.round().toString();

  Widget _buildStatCard(String label, double value,
      String Function(double) format, IconData icon, Color color) {
    return HoverCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CountUpText(
              value: value,
              format: format,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitMarginCard() {
    final profitMargin = _totalRevenue > 0
        ? ((_totalProfit / _totalRevenue) * 100)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.blue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.percent,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profit Margin',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    CountUpText(
                      value: profitMargin,
                      format: (v) => '${v.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(₹${_totalCost.toStringAsFixed(0)} cost)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.navy,
      ),
    );
  }

  Widget _buildPaymentMethodBreakdown() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: _paymentMethodBreakdown.entries.map((entry) {
          final percentage = (_totalRevenue > 0)
              ? (entry.value / _totalRevenue * 100)
              : 0.0;
          final color = _getPaymentMethodColor(entry.key);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(_getPaymentMethodIcon(entry.key),
                            size: 20, color: color),
                        const SizedBox(width: 8),
                        Text(
                          entry.key.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '₹${entry.value.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getPaymentMethodColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return AppColors.green;
      // Same colours as the Sales list's payment badges.
      case 'upi':
        return AppColors.blue;
      case 'card':
        return AppColors.navy;
      case 'credit':
        return const Color(0xFFD97706);
      default:
        return AppColors.textMuted;
    }
  }

  IconData _getPaymentMethodIcon(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Icons.money;
      case 'upi':
        return Icons.qr_code_2;
      case 'card':
        return Icons.credit_card;
      default:
        return Icons.payment;
    }
  }

  Widget _buildSalesList() {
    // Sort sales by most recent first
    final sortedSales = List<Sale>.from(_sales)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedSales.length,
      itemBuilder: (context, index) {
        final sale = sortedSales[index];
        final profit = sale.items.fold(0.0, (sum, item) {
          return sum + ((item.salePrice - item.purchasePrice) * item.quantity);
        });
        final itemCount =
            sale.items.fold(0, (sum, item) => sum + item.quantity);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.receipt,
                            color: AppColors.blue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Invoice #${sale.invoiceNumber}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('MMM dd, yyyy - hh:mm a')
                                  .format(sale.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${sale.totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.blue,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Profit: ₹${profit.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildSaleDetailChip(
                      Icons.shopping_cart,
                      '$itemCount items',
                      const Color(0xFF7C4DFF),
                    ),
                    const SizedBox(width: 8),
                    _buildSaleDetailChip(
                      _getPaymentMethodIcon(
                          sale.paymentMethod.toString().split('.').last),
                      sale.paymentMethod
                          .toString()
                          .split('.')
                          .last
                          .toUpperCase(),
                      _getPaymentMethodColor(
                          sale.paymentMethod.toString().split('.').last),
                    ),
                  ],
                ),
                if (sale.notes != null && sale.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.page,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.note, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            sale.notes!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
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
      },
    );
  }

  Widget _buildSaleDetailChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
