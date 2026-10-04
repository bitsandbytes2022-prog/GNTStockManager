import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:inventory_manager/ui/screens/add_product_screen.dart';
import 'package:inventory_manager/ui/screens/analytics_dashboard_screen.dart';
import 'package:inventory_manager/ui/screens/category_settings_screen.dart';
import 'package:inventory_manager/ui/screens/earnings_screen.dart';
import 'package:inventory_manager/ui/screens/ledger_screen.dart';
 import 'package:inventory_manager/ui/screens/product_list_screen.dart';
import 'package:inventory_manager/ui/screens/profile_screen.dart';
import 'package:inventory_manager/ui/screens/record_sale_screen.dart';
import 'package:inventory_manager/ui/screens/sales_list_screen.dart';
import 'package:inventory_manager/ui/screens/top_selling_screen.dart';
import 'package:inventory_manager/ui/theme/app_theme.dart';
import 'package:inventory_manager/ui/theme/motion.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<_NavItem> _navItems = [
    _NavItem(
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      label: 'Products',
      page: ProductListScreen(),
    ),
    _NavItem(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: 'Sales',
      page: const SalesListScreen(),
    ),
    _NavItem(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: 'Ledger',
      page: const LedgerScreen(),
    ),
    _NavItem(
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      label: 'Earnings',
      page: const EarningsScreen(),
    ),
    _NavItem(
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
      label: 'Analytics',
      page: const AnalyticsDashboardScreen(),
    ),
    _NavItem(
      icon: Icons.leaderboard_outlined,
      selectedIcon: Icons.leaderboard,
      label: 'Top Sellers',
      page: const TopSellingScreen(),
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
      page: const CategorySettingsScreen(),
    ),
  ];

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;

  bool get _isTablet =>
      MediaQuery.of(context).size.width >= 768 &&
      MediaQuery.of(context).size.width < 1200;

  bool get _isMobile => MediaQuery.of(context).size.width < 768;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: SafeArea(
        top: !kIsWeb, // No safe area on web
        child: Scaffold(body: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    void select(int index) => setState(() => _selectedIndex = index);

    if (_isDesktop) {
      return Row(
        children: [
          _DesktopSidebar(
            selectedIndex: _selectedIndex,
            items: _navItems,
            onItemSelected: select,
          ),
          Expanded(child: _buildPage()),
        ],
      );
    } else if (_isTablet && kIsWeb) {
      return Row(
        children: [
          _TabletNavigationRail(
            selectedIndex: _selectedIndex,
            items: _navItems,
            onItemSelected: select,
          ),
          Expanded(child: _buildPage()),
        ],
      );
    } else {
      // Mobile: Bottom navigation
      return Scaffold(
        body: _buildPage(),
        bottomNavigationBar: _buildBottomNav(),
        floatingActionButton: _buildFAB(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      );
    }
  }

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      // Seven sections don't fit seven labels on a phone — label only the
      // selected one, the rest stay recognisable by icon.
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      onDestinationSelected: (index) {
        setState(() => _selectedIndex = index);
      },
      destinations: _navItems
          .map(
            (item) => NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
          )
          .toList(),
    );
  }

  Widget? _buildFAB() {
    if (_selectedIndex == 0 && !kIsWeb) {
      // Show FAB only on Products tab and not on web
      return null; // FAB is handled in ProductListScreen
    }

    return null;
  }

  /// The selected section, cross-faded with a short upward slide when the
  /// section changes. The brand stripe runs along the top of the content.
  Widget _buildPage() {
    return ColoredBox(
      color: AppColors.page,
      child: Column(
        children: [
          const BrandStripe(),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.normal,
              switchInCurve: AppMotion.curve,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.015),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_selectedIndex),
                child: _navItems[_selectedIndex].page,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's mark: the shop logo on a white tile.
class _BrandMark extends StatelessWidget {
  static const double size = 44;
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.card,
      ),
      child: Image.asset(
        'assets/icons/ic_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.inventory_2, color: AppColors.blue),
      ),
    );
  }
}

// Desktop Sidebar — deep navy, with a blue highlight that slides to the
// selected item.
class _DesktopSidebar extends StatelessWidget {
  final int selectedIndex;
  final List<_NavItem> items;
  final Function(int) onItemSelected;

  static const double _itemHeight = 46;
  static const double _itemGap = 4;

  const _DesktopSidebar({
    required this.selectedIndex,
    required this.items,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 256,
      color: AppColors.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandStripe(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Row(
              children: [
                const _BrandMark(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GNT Stock',
                        style: textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Manager',
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text(
              'MENU',
              style: textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.45),
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Navigation items over a highlight that slides between them.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: AppMotion.normal,
                    curve: AppMotion.curve,
                    top: selectedIndex * (_itemHeight + _itemGap),
                    left: 0,
                    right: 0,
                    height: _itemHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.blue,
                        borderRadius:
                            BorderRadius.circular(AppRadii.control),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.blue.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _itemGap),
                          child: _SidebarItem(
                            item: items[i],
                            selected: i == selectedIndex,
                            height: _itemHeight,
                            onTap: () => onItemSelected(i),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Footer
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.navyLight,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Admin User',
                          style: textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'View Profile',
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: Colors.white.withValues(alpha: 0.6)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One sidebar row: transparent so the sliding highlight shows through
/// when selected, with a faint hover wash otherwise.
class _SidebarItem extends StatefulWidget {
  final _NavItem item;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.selected
        ? Colors.white
        : Colors.white.withValues(alpha: _hover ? 0.95 : 0.72);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: !widget.selected && _hover
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: AppMotion.fast,
                child: Icon(
                  widget.selected ? widget.item.selectedIcon : widget.item.icon,
                  key: ValueKey(widget.selected),
                  color: fg,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                widget.item.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: fg,
                      fontWeight:
                          widget.selected ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Tablet Navigation Rail — same navy look in a compact rail.
class _TabletNavigationRail extends StatelessWidget {
  final int selectedIndex;
  final List<_NavItem> items;
  final Function(int) onItemSelected;

  const _TabletNavigationRail({
    required this.selectedIndex,
    required this.items,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(width: 88, child: BrandStripe()),
        Expanded(
          child: NavigationRail(
            backgroundColor: AppColors.navy,
            selectedIndex: selectedIndex,
            onDestinationSelected: onItemSelected,
            labelType: NavigationRailLabelType.all,
            indicatorColor: AppColors.blue,
            selectedIconTheme: const IconThemeData(color: Colors.white),
            unselectedIconTheme:
                IconThemeData(color: Colors.white.withValues(alpha: 0.7)),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            unselectedLabelTextStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: _BrandMark(),
            ),
            destinations: items
                .map(
                  (item) => NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.label),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

// Navigation item model
class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget page;

  _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.page,
  });
}
