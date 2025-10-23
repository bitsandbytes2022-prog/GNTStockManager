import 'package:flutter/material.dart';
import 'package:inventory_manager/ui/screens/analytics_dashboard_screen.dart';
import 'package:inventory_manager/ui/screens/data_sync_screen.dart';
import 'package:inventory_manager/ui/screens/product_list_screen.dart';
import 'package:inventory_manager/ui/screens/sales_list_screen.dart';

class DashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: SafeArea(
        top: false,
        child: Scaffold(
          body: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    ClipOval(
                      clipBehavior: Clip.hardEdge,
                      child: Image.asset(
                        'assets/icons/ic_logo.png',
                        width: 36,
                        height: 36,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text('GNT Stock Manager'),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.analytics),
                    tooltip: 'Analytics',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AnalyticsDashboardScreen(),
                        ),
                      );
                    },
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'sync') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DataSyncScreen(),
                          ),
                        );
                      } else if (value == 'analytics') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AnalyticsDashboardScreen(),
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'analytics',
                        child: Row(
                          children: [
                            Icon(
                              Icons.analytics,
                              size: 20,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 12),
                            const Text('Analytics Dashboard'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'sync',
                        child: Row(
                          children: [
                            Icon(
                              Icons.sync,
                              size: 20,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 12),
                            const Text('Sync Data'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                bottom: const TabBar(
                  tabs: [
                    Tab(
                      icon: ImageIcon(
                        AssetImage('assets/icons/ic_product.png'),
                        size: 24,
                      ),
                      text: 'Products',
                    ),
                    Tab(
                      icon: ImageIcon(
                        AssetImage('assets/icons/ic_sales.png'),
                        size: 24,
                      ),
                      text: 'Sales',
                    ),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  ProductListScreen(),
                  const SalesListScreen(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}