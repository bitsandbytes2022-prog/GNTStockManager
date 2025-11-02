import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:inventory_manager/ui/screens/add_product_screen.dart';
import 'package:inventory_manager/ui/screens/analytics_dashboard_screen.dart';
import 'package:inventory_manager/ui/screens/data_sync_screen.dart';
import 'package:inventory_manager/ui/screens/product_list_screen.dart';
import 'package:inventory_manager/ui/screens/record_sale_screen.dart';
import 'package:inventory_manager/ui/screens/sales_list_screen.dart';

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
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
      label: 'Analytics',
      page: const AnalyticsDashboardScreen(),
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
      page: const DataSyncScreen(),
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
    if (_isDesktop) {
      // Desktop: Sidebar navigation
      return Row(
        children: [
          _DesktopSidebar(
            selectedIndex: _selectedIndex,
            items: _navItems,
            onItemSelected: (index) {
              setState(() => _selectedIndex = index);
            },
          ),
          Expanded(child: _buildPage()),
        ],
      );
    } else if (_isTablet && kIsWeb) {
      // Tablet Web: Rail navigation
      return Row(
        children: [
          _TabletNavigationRail(
            selectedIndex: _selectedIndex,
            items: _navItems,
            onItemSelected: (index) {
              setState(() => _selectedIndex = index);
            },
          ),
          const VerticalDivider(width: 1),
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

  Widget _buildPage() {
    return Container(
      color: Colors.grey[50],
      child: _navItems[_selectedIndex].page,
    );
  }
}

// Desktop Sidebar
class _DesktopSidebar extends StatelessWidget {
  final int selectedIndex;
  final List<_NavItem> items;
  final Function(int) onItemSelected;

  const _DesktopSidebar({
    required this.selectedIndex,
    required this.items,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GNT Stock',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Manager',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Navigation items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = selectedIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: isSelected
                        ? Colors.blue.shade50
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => onItemSelected(index),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? item.selectedIcon : item.icon,
                              color: isSelected
                                  ? Colors.blue.shade700
                                  : Colors.grey.shade600,
                              size: 24,
                            ),
                            const SizedBox(width: 16),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Footer
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.grey.shade200,
                  child: Icon(Icons.person, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Admin User',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'View Profile',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {},
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Tablet Navigation Rail
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
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onItemSelected,
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.inventory_2, color: Colors.white),
        ),
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
