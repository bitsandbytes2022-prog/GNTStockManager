import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inventory_manager/ui/screens/analytics_dashboard_screen.dart';
import 'package:inventory_manager/ui/screens/category_settings_screen.dart';
import 'package:inventory_manager/ui/screens/earnings_screen.dart';
import 'package:inventory_manager/ui/screens/ledger_screen.dart';
import 'package:inventory_manager/ui/screens/more_screen.dart';
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
      selectedIcon: Icons.inventory_2_rounded,
      label: 'Products',
      page: ProductListScreen(),
    ),
    _NavItem(
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Sales',
      page: const SalesListScreen(),
    ),
    _NavItem(
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories_rounded,
      label: 'Ledger',
      page: const LedgerScreen(),
    ),
    _NavItem(
      icon: Icons.savings_outlined,
      selectedIcon: Icons.savings_rounded,
      label: 'Earnings',
      page: const EarningsScreen(),
    ),
    _NavItem(
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights_rounded,
      label: 'Analytics',
      page: const AnalyticsDashboardScreen(),
    ),
    _NavItem(
      icon: Icons.local_fire_department_outlined,
      selectedIcon: Icons.local_fire_department_rounded,
      label: 'Top Sellers',
      page: const TopSellingScreen(),
    ),
    _NavItem(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune_rounded,
      label: 'Settings',
      page: const CategorySettingsScreen(),
    ),
  ];

  /// Mobile tab: 0 Products, 1 Sales, 2 Ledger, 3 More. Phones get four
  /// tabs plus a New Sale button instead of all seven sections; the rest
  /// live on the More page.
  int _mobileIndex = 0;

  late final List<_NavItem> _mobileItems = [
    _navItems[0],
    _navItems[1],
    _navItems[2],
    _NavItem(
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
      label: 'More',
      page: const MoreScreen(),
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
      // Mobile: four tabs and a New Sale button.
      return Scaffold(
        body: _buildPage(mobile: true),
        bottomNavigationBar: _MobileNavBar(
          items: _mobileItems,
          selectedIndex: _mobileIndex,
          onItemSelected: (i) => setState(() => _mobileIndex = i),
          onNewSale: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RecordSaleScreen()),
          ),
        ),
      );
    }
  }

  /// The selected section, cross-faded with a short upward slide when the
  /// section changes. The brand stripe runs along the top of the content.
  Widget _buildPage({bool mobile = false}) {
    final index = mobile ? _mobileIndex : _selectedIndex;
    final items = mobile ? _mobileItems : _navItems;
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
                key: ValueKey('${mobile ? 'm' : 'd'}$index'),
                child: items[index].page,
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
      decoration: const BoxDecoration(gradient: AppGradients.sidebar),
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
                        gradient: AppGradients.primary,
                        borderRadius:
                            BorderRadius.circular(AppRadii.control),
                        boxShadow: AppShadows.glow(AppColors.blue),
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

/// Phone bottom bar: a white floating panel with four tabs around a
/// gradient New Sale button. The selected tab's icon sits on a gradient
/// pill that pops in with a little bounce.
class _MobileNavBar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onNewSale;

  const _MobileNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onNewSale,
  });

  @override
  Widget build(BuildContext context) {
    Widget tab(int i) => Expanded(
          child: _MobileNavTab(
            item: items[i],
            selected: i == selectedIndex,
            onTap: () {
              if (i != selectedIndex) HapticFeedback.selectionClick();
              onItemSelected(i);
            },
          ),
        );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F2E1065),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              tab(0),
              tab(1),
              _NewSaleButton(onTap: onNewSale),
              tab(2),
              tab(3),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileNavTab extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _MobileNavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      haptic: false,
      pressedScale: 0.88,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            width: selected ? 52 : 40,
            height: 32,
            decoration: BoxDecoration(
              gradient: selected ? AppGradients.primary : null,
              borderRadius: BorderRadius.circular(16),
              boxShadow: selected ? AppShadows.glow(AppColors.blue) : null,
            ),
            child: TweenAnimationBuilder<double>(
              // Re-keyed on selection so the icon pops each time.
              key: ValueKey(selected),
              tween: Tween(begin: selected ? 0.6 : 1, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.elasticOut,
              builder: (context, v, child) =>
                  Transform.scale(scale: v, child: child),
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 22,
                color: selected ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: AppMotion.fast,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.blue : AppColors.textMuted,
            ),
            child: Text(item.label),
          ),
        ],
      ),
    );
  }
}

/// The big round gradient button in the middle of the phone bar.
class _NewSaleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NewSaleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: 'New sale',
        child: Pressable(
          onTap: onTap,
          pressedScale: 0.86,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: AppGradients.action,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: AppShadows.glow(AppColors.coral),
            ),
            child: const Icon(Icons.add_shopping_cart_rounded,
                color: Colors.white, size: 26),
          ),
        ),
      ),
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
