import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sale_model.dart';
import '../models/product_model.dart';

class AnalyticsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get sales timing analytics (hourly and daily patterns)
  Future<SalesTimingAnalytics> getSalesTimingAnalytics(
      List<Sale> sales) async {
    if (sales.isEmpty) {
      return SalesTimingAnalytics.empty();
    }

    // Hourly sales distribution
    final hourlySales = <int, HourStats>{};
    for (int i = 0; i < 24; i++) {
      hourlySales[i] = HourStats(hour: i, salesCount: 0, revenue: 0);
    }

    // Daily sales distribution (Monday = 1, Sunday = 7)
    final dailySales = <int, DayStats>{};
    for (int i = 1; i <= 7; i++) {
      dailySales[i] = DayStats(dayOfWeek: i, salesCount: 0, revenue: 0);
    }

    // Process all sales
    for (final sale in sales) {
      final hour = sale.createdAt.hour;
      final dayOfWeek = sale.createdAt.weekday;

      // Update hourly stats
      hourlySales[hour] = HourStats(
        hour: hour,
        salesCount: hourlySales[hour]!.salesCount + 1,
        revenue: hourlySales[hour]!.revenue + sale.totalAmount,
      );

      // Update daily stats
      dailySales[dayOfWeek] = DayStats(
        dayOfWeek: dayOfWeek,
        salesCount: dailySales[dayOfWeek]!.salesCount + 1,
        revenue: dailySales[dayOfWeek]!.revenue + sale.totalAmount,
      );
    }

    // Find peak hours and days
    int peakHour = 0;
    int maxHourlySales = 0;
    for (final entry in hourlySales.entries) {
      if (entry.value.salesCount > maxHourlySales) {
        maxHourlySales = entry.value.salesCount;
        peakHour = entry.key;
      }
    }

    int peakDay = 1;
    int maxDailySales = 0;
    for (final entry in dailySales.entries) {
      if (entry.value.salesCount > maxDailySales) {
        maxDailySales = entry.value.salesCount;
        peakDay = entry.key;
      }
    }

    // Find slowest hours and days
    int slowestHour = 0;
    int minHourlySales = sales.length;
    for (final entry in hourlySales.entries) {
      if (entry.value.salesCount > 0 &&
          entry.value.salesCount < minHourlySales) {
        minHourlySales = entry.value.salesCount;
        slowestHour = entry.key;
      }
    }

    int slowestDay = 1;
    int minDailySales = sales.length;
    for (final entry in dailySales.entries) {
      if (entry.value.salesCount > 0 &&
          entry.value.salesCount < minDailySales) {
        minDailySales = entry.value.salesCount;
        slowestDay = entry.key;
      }
    }

    return SalesTimingAnalytics(
      hourlySales: hourlySales,
      dailySales: dailySales,
      peakHour: peakHour,
      peakDay: peakDay,
      slowestHour: slowestHour,
      slowestDay: slowestDay,
    );
  }

  /// Get comparison metrics between two periods
  Future<ComparisonMetrics> getComparisonMetrics({
    required List<Sale> currentPeriodSales,
    required List<Sale> previousPeriodSales,
  }) async {
    final currentStats = _calculatePeriodStats(currentPeriodSales);
    final previousStats = _calculatePeriodStats(previousPeriodSales);

    return ComparisonMetrics(
      currentPeriod: currentStats,
      previousPeriod: previousStats,
      salesChange: _calculatePercentageChange(
        previousStats.totalSales.toDouble(),
        currentStats.totalSales.toDouble(),
      ),
      revenueChange: _calculatePercentageChange(
        previousStats.totalRevenue,
        currentStats.totalRevenue,
      ),
      profitChange: _calculatePercentageChange(
        previousStats.totalProfit,
        currentStats.totalProfit,
      ),
      itemsSoldChange: _calculatePercentageChange(
        previousStats.itemsSold.toDouble(),
        currentStats.itemsSold.toDouble(),
      ),
    );
  }

  PeriodStats _calculatePeriodStats(List<Sale> sales) {
    if (sales.isEmpty) {
      return PeriodStats(
        totalSales: 0,
        totalRevenue: 0,
        totalProfit: 0,
        totalCost: 0,
        itemsSold: 0,
        averageSaleValue: 0,
      );
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

    return PeriodStats(
      totalSales: sales.length,
      totalRevenue: totalRevenue,
      totalProfit: totalProfit,
      totalCost: totalCost,
      itemsSold: itemsSold,
      averageSaleValue: totalRevenue / sales.length,
    );
  }

  double _calculatePercentageChange(double oldValue, double newValue) {
    if (oldValue == 0) {
      return newValue > 0 ? 100 : 0;
    }
    return ((newValue - oldValue) / oldValue) * 100;
  }

  /// Get smart low stock products (>60% sold from original stock)
  Future<List<LowStockProduct>> getSmartLowStockProducts(
      List<Product> products) async {
    final lowStockProducts = <LowStockProduct>[];

    for (final product in products) {
      // Calculate total inventory (current stock + sold)
      final totalInventory = product.stock + product.totalSold;

      // Skip if no sales history
      if (totalInventory == 0) continue;

      // Calculate percentage sold
      final percentageSold = (product.totalSold / totalInventory) * 100;

      // Add to low stock if more than 60% sold
      if (percentageSold >= 60) {
        lowStockProducts.add(LowStockProduct(
          product: product,
          percentageSold: percentageSold,
          totalInventory: totalInventory,
          needsRestock: percentageSold >= 80, // Critical if 80%+ sold
        ));
      }
    }

    // Sort by percentage sold (highest first)
    lowStockProducts.sort((a, b) =>
        b.percentageSold.compareTo(a.percentageSold));

    return lowStockProducts;
  }

  /// Get payment method breakdown
  Future<PaymentMethodStats> getPaymentMethodStats(List<Sale> sales) async {
    final stats = <PaymentMethod, double>{
      PaymentMethod.cash: 0,
      PaymentMethod.upi: 0,
      PaymentMethod.card: 0,
      PaymentMethod.other: 0,
    };

    final counts = <PaymentMethod, int>{
      PaymentMethod.cash: 0,
      PaymentMethod.upi: 0,
      PaymentMethod.card: 0,
      PaymentMethod.other: 0,
    };

    for (final sale in sales) {
      stats[sale.paymentMethod] =
          (stats[sale.paymentMethod] ?? 0) + sale.totalAmount;
      counts[sale.paymentMethod] = (counts[sale.paymentMethod] ?? 0) + 1;
    }

    final totalRevenue = stats.values.fold(0.0, (sum, val) => sum + val);

    return PaymentMethodStats(
      cashAmount: stats[PaymentMethod.cash] ?? 0,
      upiAmount: stats[PaymentMethod.upi] ?? 0,
      cardAmount: stats[PaymentMethod.card] ?? 0,
      otherAmount: stats[PaymentMethod.other] ?? 0,
      cashCount: counts[PaymentMethod.cash] ?? 0,
      upiCount: counts[PaymentMethod.upi] ?? 0,
      cardCount: counts[PaymentMethod.card] ?? 0,
      otherCount: counts[PaymentMethod.other] ?? 0,
      totalRevenue: totalRevenue,
      cashPercentage: totalRevenue > 0
          ? ((stats[PaymentMethod.cash] ?? 0) / totalRevenue) * 100
          : 0,
      upiPercentage: totalRevenue > 0
          ? ((stats[PaymentMethod.upi] ?? 0) / totalRevenue) * 100
          : 0,
      cardPercentage: totalRevenue > 0
          ? ((stats[PaymentMethod.card] ?? 0) / totalRevenue) * 100
          : 0,
      otherPercentage: totalRevenue > 0
          ? ((stats[PaymentMethod.other] ?? 0) / totalRevenue) * 100
          : 0,
    );
  }
}

// Data models for analytics

class HourStats {
  final int hour;
  final int salesCount;
  final double revenue;

  HourStats({
    required this.hour,
    required this.salesCount,
    required this.revenue,
  });

  String get hourLabel {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }
}

class DayStats {
  final int dayOfWeek; // 1 = Monday, 7 = Sunday
  final int salesCount;
  final double revenue;

  DayStats({
    required this.dayOfWeek,
    required this.salesCount,
    required this.revenue,
  });

  String get dayName {
    switch (dayOfWeek) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return 'Unknown';
    }
  }

  String get dayShort {
    switch (dayOfWeek) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '???';
    }
  }
}

class SalesTimingAnalytics {
  final Map<int, HourStats> hourlySales;
  final Map<int, DayStats> dailySales;
  final int peakHour;
  final int peakDay;
  final int slowestHour;
  final int slowestDay;

  SalesTimingAnalytics({
    required this.hourlySales,
    required this.dailySales,
    required this.peakHour,
    required this.peakDay,
    required this.slowestHour,
    required this.slowestDay,
  });

  factory SalesTimingAnalytics.empty() {
    return SalesTimingAnalytics(
      hourlySales: {},
      dailySales: {},
      peakHour: 0,
      peakDay: 1,
      slowestHour: 0,
      slowestDay: 1,
    );
  }

  String get peakHourLabel {
    return HourStats(hour: peakHour, salesCount: 0, revenue: 0).hourLabel;
  }

  String get slowestHourLabel {
    return HourStats(hour: slowestHour, salesCount: 0, revenue: 0).hourLabel;
  }

  String get peakDayName {
    return DayStats(dayOfWeek: peakDay, salesCount: 0, revenue: 0).dayName;
  }

  String get slowestDayName {
    return DayStats(dayOfWeek: slowestDay, salesCount: 0, revenue: 0).dayName;
  }
}

class PeriodStats {
  final int totalSales;
  final double totalRevenue;
  final double totalProfit;
  final double totalCost;
  final int itemsSold;
  final double averageSaleValue;

  PeriodStats({
    required this.totalSales,
    required this.totalRevenue,
    required this.totalProfit,
    required this.totalCost,
    required this.itemsSold,
    required this.averageSaleValue,
  });
}

class ComparisonMetrics {
  final PeriodStats currentPeriod;
  final PeriodStats previousPeriod;
  final double salesChange; // Percentage
  final double revenueChange; // Percentage
  final double profitChange; // Percentage
  final double itemsSoldChange; // Percentage

  ComparisonMetrics({
    required this.currentPeriod,
    required this.previousPeriod,
    required this.salesChange,
    required this.revenueChange,
    required this.profitChange,
    required this.itemsSoldChange,
  });

  bool get isImproving => revenueChange > 0 && profitChange > 0;
  bool get isDeclining => revenueChange < 0 && profitChange < 0;
}

class LowStockProduct {
  final Product product;
  final double percentageSold;
  final int totalInventory;
  final bool needsRestock; // true if 80%+ sold

  LowStockProduct({
    required this.product,
    required this.percentageSold,
    required this.totalInventory,
    required this.needsRestock,
  });

  String get urgencyLevel {
    if (percentageSold >= 90) return 'Critical';
    if (percentageSold >= 80) return 'High';
    if (percentageSold >= 70) return 'Medium';
    return 'Low';
  }

  int get recommendedRestock {
    // Recommend restocking to 2x the amount already sold
    return (product.totalSold * 2 - product.stock).clamp(0, 999999);
  }
}

class PaymentMethodStats {
  final double cashAmount;
  final double upiAmount;
  final double cardAmount;
  final double otherAmount;
  final int cashCount;
  final int upiCount;
  final int cardCount;
  final int otherCount;
  final double totalRevenue;
  final double cashPercentage;
  final double upiPercentage;
  final double cardPercentage;
  final double otherPercentage;

  PaymentMethodStats({
    required this.cashAmount,
    required this.upiAmount,
    required this.cardAmount,
    required this.otherAmount,
    required this.cashCount,
    required this.upiCount,
    required this.cardCount,
    required this.otherCount,
    required this.totalRevenue,
    required this.cashPercentage,
    required this.upiPercentage,
    required this.cardPercentage,
    required this.otherPercentage,
  });
}