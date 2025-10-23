import 'package:flutter/material.dart';
import '../../services/data_sync_service.dart';

class DataSyncScreen extends StatefulWidget {
  const DataSyncScreen({super.key});

  @override
  State<DataSyncScreen> createState() => _DataSyncScreenState();
}

class _DataSyncScreenState extends State<DataSyncScreen> {
  final DataSyncService _syncService = DataSyncService();

  bool _isSyncing = false;
  String _progressMessage = '';
  SyncResult? _lastResult;

  Future<void> _syncAllData() async {
    setState(() {
      _isSyncing = true;
      _progressMessage = 'Starting sync...';
      _lastResult = null;
    });

    try {
      final result = await _syncService.syncAllData(
        onProgress: (message) {
          setState(() {
            _progressMessage = message;
          });
        },
      );

      setState(() {
        _lastResult = result;
        _isSyncing = false;
      });

      if (result.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Sync completed successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _progressMessage = 'Error: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _syncProductStatisticsOnly() async {
    setState(() {
      _isSyncing = true;
      _progressMessage = 'Starting statistics sync...';
      _lastResult = null;
    });

    try {
      final result = await _syncService.syncProductStatisticsOnly(
        onProgress: (message) {
          setState(() {
            _progressMessage = message;
          });
        },
      );

      setState(() {
        _lastResult = result;
        _isSyncing = false;
      });

      if (result.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Statistics sync completed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _progressMessage = 'Error: $e';
      });
    }
  }

  Future<void> _syncSaleImagesOnly() async {
    setState(() {
      _isSyncing = true;
      _progressMessage = 'Starting image sync...';
      _lastResult = null;
    });

    try {
      final result = await _syncService.syncSaleImagesOnly(
        onProgress: (message) {
          setState(() {
            _progressMessage = message;
          });
        },
      );

      setState(() {
        _lastResult = result;
        _isSyncing = false;
      });

      if (result.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Image sync completed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _progressMessage = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Sync'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info Card
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'About Data Sync',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This tool will sync your existing data:\n\n'
                          '• Update product sales statistics from all sales history\n'
                          '• Add missing product images to past sales\n'
                          '• Fix any inconsistencies in the database\n\n'
                          'You only need to run this once after updating the app.',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Full Sync Button
            _SyncOptionCard(
              title: 'Full Sync',
              subtitle: 'Sync everything (recommended)',
              icon: Icons.sync,
              iconColor: Colors.blue,
              onPressed: _isSyncing ? null : _syncAllData,
              details: [
                '✓ Update product sales statistics',
                '✓ Add images to past sales',
                '✓ Complete database sync',
              ],
            ),

            const SizedBox(height: 16),

            // Quick Options Header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Quick Options',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ),

            // Statistics Only Button
            _SyncOptionCard(
              title: 'Statistics Only',
              subtitle: 'Update product sales data',
              icon: Icons.bar_chart,
              iconColor: Colors.green,
              isCompact: true,
              onPressed: _isSyncing ? null : _syncProductStatisticsOnly,
              details: [
                '✓ Update totalSold, saleCount',
                '✗ Does not update images',
              ],
            ),

            const SizedBox(height: 12),

            // Images Only Button
            _SyncOptionCard(
              title: 'Images Only',
              subtitle: 'Add missing product images',
              icon: Icons.image,
              iconColor: Colors.orange,
              isCompact: true,
              onPressed: _isSyncing ? null : _syncSaleImagesOnly,
              details: [
                '✓ Add images to past sales',
                '✗ Does not update statistics',
              ],
            ),

            const SizedBox(height: 24),

            // Progress Card
            if (_isSyncing || _lastResult != null)
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_isSyncing)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          if (!_isSyncing && _lastResult != null)
                            Icon(
                              _lastResult!.success
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: _lastResult!.success
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _isSyncing ? 'Syncing...' : 'Sync Result',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_isSyncing)
                        Text(
                          _progressMessage,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      if (!_isSyncing && _lastResult != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _lastResult!.success
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _lastResult!.getSummary(),
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: _lastResult!.success
                                  ? Colors.green.shade900
                                  : Colors.red.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Warning Card
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Important Notes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• This process may take a few moments\n'
                          '• Internet connection required\n'
                          '• Safe to run multiple times\n'
                          '• No data will be lost',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onPressed;
  final List<String> details;
  final bool isCompact;

  const _SyncOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onPressed,
    required this.details,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 12.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onPressed != null)
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                ],
              ),
              if (!isCompact) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                ...details.map((detail) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Text(
                        detail,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}