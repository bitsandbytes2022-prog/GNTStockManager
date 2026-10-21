import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'analytics_dashboard_screen.dart';
import 'category_settings_screen.dart';
import 'credit_sales_screen.dart';
import 'earnings_screen.dart';
import 'gst_calculator_screen.dart';
import 'profile_screen.dart';
import 'referrers_screen.dart';
import 'top_selling_screen.dart';

class _MoreEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final WidgetBuilder page;

  const _MoreEntry(this.title, this.subtitle, this.icon, this.gradient, this.page);
}

/// The phone's "More" tab: every section that doesn't get its own tab,
/// as colourful tiles grouped by what they're for.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static final _sections = <String, List<_MoreEntry>>{
    'Reports': [
      _MoreEntry('Earnings', 'Revenue & profit', Icons.savings_rounded,
          AppGradients.money, (_) => const EarningsScreen()),
      _MoreEntry('Analytics', 'Trends & stock', Icons.insights_rounded,
          AppGradients.ocean, (_) => const AnalyticsDashboardScreen()),
      _MoreEntry('Top Sellers', 'Best products', Icons.local_fire_department_rounded,
          AppGradients.gold, (_) => const TopSellingScreen()),
      _MoreEntry('Credit sales', 'Money to collect', Icons.hourglass_top_rounded,
          AppGradients.rose, (_) => const CreditSalesScreen()),
    ],
    'People': [
      _MoreEntry('Plumbers & Painters', 'Business & incentives',
          Icons.handyman_rounded, AppGradients.action,
          (_) => const ReferrersScreen()),
    ],
    'Tools': [
      _MoreEntry('GST calculator', 'Quick tax maths', Icons.calculate_rounded,
          AppGradients.primary, (_) => const GstCalculatorScreen()),
      _MoreEntry('Settings', 'Categories & app', Icons.tune_rounded,
          AppGradients.slate, (_) => const CategorySettingsScreen()),
      _MoreEntry('Profile', 'Your account', Icons.person_rounded,
          AppGradients.hero, (_) => const ProfileScreen()),
    ],
  };

  @override
  Widget build(BuildContext context) {
    var index = 0;
    return Scaffold(
      backgroundColor: AppColors.page,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const GradientHeader(
            title: 'More',
            subtitle: 'Reports, people and tools',
            padding: EdgeInsets.fromLTRB(20, 20, 20, 26),
          ),
          for (final section in _sections.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
              child: Text(
                section.key.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 600 ? 4 : 2;
                  final width =
                      (constraints.maxWidth - 12 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final entry in section.value)
                        SizedBox(
                          width: section.value.length == 1
                              ? constraints.maxWidth
                              : width,
                          child: FadeSlideIn(
                            delay: FadeSlideIn.stagger(index++),
                            child: _MoreTile(
                              entry: entry,
                              wide: section.value.length == 1,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final _MoreEntry entry;

  /// A full-width row instead of a grid tile.
  final bool wide;

  const _MoreTile({required this.entry, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final title = Text(
      entry.title,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: AppColors.navy,
        fontSize: 14.5,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final subtitle = Text(
      entry.subtitle,
      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final icon =
        GradientIconTile(icon: entry.icon, gradient: entry.gradient, size: 44);

    return HoverCard(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: entry.page),
      ),
      child: wide
          ? Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 2), subtitle],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: AppColors.textMuted),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                icon,
                const SizedBox(height: 12),
                title,
                const SizedBox(height: 2),
                subtitle,
              ],
            ),
    );
  }
}
