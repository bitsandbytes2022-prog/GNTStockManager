import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/referrer_model.dart';
import '../../models/sale_model.dart';
import '../../services/referrer_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../widgets/referrer_widgets.dart';
import 'ledger_screen.dart' show formatLedgerAmount;

/// A small label/value pair on the orange summary cards.
Widget _stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );

/// Year picker shared by the list and detail screens. Null means all time.
class _YearDropdown extends StatelessWidget {
  final List<int> years;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _YearDropdown({
    required this.years,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int?>(
        value: value,
        borderRadius: BorderRadius.circular(8),
        items: [
          for (final y in years)
            DropdownMenuItem(value: y, child: Text('Year $y')),
          const DropdownMenuItem(value: null, child: Text('All time')),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// Plumbers and painters who bring customers, with how much business each
/// brought in a year — used to decide their perks at year end.
class ReferrersScreen extends StatefulWidget {
  const ReferrersScreen({super.key});

  @override
  State<ReferrersScreen> createState() => _ReferrersScreenState();
}

class _ReferrersScreenState extends State<ReferrersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  late final Stream<ReferrerData> _stream = ReferrerService().watch();
  String _query = '';
  int? _year = DateTime.now().year;

  ReferrerType get _type => ReferrerType.values[_tabController.index];

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plumbers & Painters'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            for (final t in ReferrerType.values)
              Tab(icon: Icon(referrerIcon(t)), text: '${t.label}s'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showReferrerFormDialog(context, type: _type),
        icon: const Icon(Icons.person_add),
        label: Text('Add ${_type.label}'),
      ),
      body: StreamBuilder<ReferrerData>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const ShimmerBox(height: 110, radius: 14),
                const SizedBox(height: 16),
                for (var i = 0; i < 5; i++) ...[
                  const ShimmerBox(height: 64, radius: AppRadii.card),
                  const SizedBox(height: 8),
                ],
              ],
            );
          }
          return _buildTab(snapshot.data!);
        },
      ),
    );
  }

  Widget _buildTab(ReferrerData data) {
    final all = data.referrers.where((r) => r.type == _type).toList();
    final business = {
      for (final r in all)
        r.id: ReferrerBusiness.of(data.salesFor(r.id, year: _year)),
    };
    final total =
        business.values.fold<double>(0, (sum, b) => sum + b.amount);
    final profit =
        business.values.fold<double>(0, (sum, b) => sum + b.profit);
    final incentive =
        business.values.fold<double>(0, (sum, b) => sum + b.incentivePaid);

    final q = _query.toLowerCase().trim();
    final referrers = q.isEmpty
        ? all
        : all
            .where((r) =>
                r.name.toLowerCase().contains(q) ||
                (r.phone ?? '').contains(q))
            .toList();
    // Biggest business first — who has earned the best perks.
    referrers.sort(
        (a, b) => business[b.id]!.amount.compareTo(business[a.id]!.amount));

    final noun = _type.label.toLowerCase();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        FadeSlideIn(
          key: ValueKey(_type),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFC2410C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _year == null
                      ? 'Business from ${noun}s · all time'
                      : 'Business from ${noun}s in $_year',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                CountUpText(
                  value: total,
                  format: formatLedgerAmount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${all.length} $noun${all.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _stat('Your profit', formatLedgerAmount(profit)),
                    _stat('Incentive paid', formatLedgerAmount(incentive)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search by name or phone',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 12),
            _YearDropdown(
              years: data.years,
              value: _year,
              onChanged: (y) => setState(() => _year = y),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: const BoxDecoration(
                    color: AppColors.blueTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(referrerIcon(_type),
                      size: 48, color: AppColors.blue),
                ),
                const SizedBox(height: 12),
                Text(
                  'No ${noun}s yet.\nAdd one, then pick them when recording a sale.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < referrers.length; i++)
            FadeSlideIn(
              key: ValueKey('ref_${referrers[i].id}'),
              delay: FadeSlideIn.stagger(i),
              child: _ReferrerTile(
                referrer: referrers[i],
                business: business[referrers[i].id]!,
                rank: business[referrers[i].id]!.amount > 0 ? i + 1 : null,
                year: _year,
              ),
            ),
      ],
    );
  }
}

class _ReferrerTile extends StatelessWidget {
  final Referrer referrer;
  final ReferrerBusiness business;

  /// Position by business, shown only for those with some business.
  final int? rank;
  final int? year;

  const _ReferrerTile({
    required this.referrer,
    required this.business,
    required this.rank,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFC2410C);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HoverCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ReferrerDetailScreen(referrerId: referrer.id, initialYear: year),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Text(
                rank != null
                    ? '#$rank'
                    : (referrer.name.isEmpty
                        ? '?'
                        : referrer.name[0].toUpperCase()),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: accent, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    referrer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (referrer.phone?.isNotEmpty ?? false)
                    Text(
                      referrer.phone!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatLedgerAmount(business.amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Profit ${formatLedgerAmount(business.profit)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.green,
                  ),
                ),
                Text(
                  [
                    '${business.bills} bill${business.bills == 1 ? '' : 's'}',
                    if (business.incentivePaid > 0)
                      'paid ${formatLedgerAmount(business.incentivePaid)}',
                  ].join(' · '),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// One plumber/painter: their business for a year and the sales behind it.
class ReferrerDetailScreen extends StatefulWidget {
  final String referrerId;
  final int? initialYear;

  const ReferrerDetailScreen({
    super.key,
    required this.referrerId,
    this.initialYear,
  });

  @override
  State<ReferrerDetailScreen> createState() => _ReferrerDetailScreenState();
}

class _ReferrerDetailScreenState extends State<ReferrerDetailScreen> {
  late final Stream<ReferrerData> _stream = ReferrerService().watch();
  late int? _year = widget.initialYear;

  Future<void> _delete(Referrer referrer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${referrer.name}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.stockOut),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ReferrerService().deleteReferrer(referrer);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ReferrerData>(
      stream: _stream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final referrer = data?.referrers
            .where((r) => r.id == widget.referrerId)
            .firstOrNull;
        return Scaffold(
          appBar: AppBar(
            title: Text(referrer?.name ?? ''),
            actions: [
              if (referrer != null)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      showReferrerFormDialog(context, referrer: referrer);
                    } else if (v == 'delete') {
                      _delete(referrer);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          body: snapshot.hasError
              ? Center(child: Text('Error loading: ${snapshot.error}'))
              : data == null
                  ? const Center(child: CircularProgressIndicator())
                  : referrer == null
                      ? const Center(child: Text('Not found'))
                      : _buildBody(data, referrer),
        );
      },
    );
  }

  Widget _buildBody(ReferrerData data, Referrer referrer) {
    final sales = data.salesFor(referrer.id, year: _year);
    final business = ReferrerBusiness.of(sales);
    final dateFormat = DateFormat('dd MMM yyyy');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(referrerIcon(referrer.type), color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                [
                  referrer.type.label,
                  if (referrer.phone?.isNotEmpty ?? false) referrer.phone!,
                ].join(' · '),
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
            _YearDropdown(
              years: data.years,
              value: _year,
              onChanged: (y) => setState(() => _year = y),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFC2410C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _year == null ? 'Business · all time' : 'Business in $_year',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              CountUpText(
                value: business.amount,
                format: formatLedgerAmount,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _stat('Bills', '${business.bills}'),
                  _stat('Your profit', formatLedgerAmount(business.profit)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _stat('Incentive paid',
                      formatLedgerAmount(business.incentivePaid)),
                  _stat('Profit after incentive',
                      formatLedgerAmount(business.netProfit)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (sales.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Text(
              'No sales in this period.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
          )
        else
          for (final Sale sale in sales)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HoverCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invoice #${sale.invoiceNumber}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy,
                            ),
                          ),
                          Text(
                            [
                              dateFormat.format(sale.createdAt),
                              if (sale.buyerName?.isNotEmpty ?? false)
                                sale.buyerName!,
                            ].join(' · '),
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatLedgerAmount(sale.totalAmount),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        Text(
                          'Profit ${formatLedgerAmount(ReferrerBusiness.of([sale]).profit)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.green),
                        ),
                        if ((sale.referrerIncentive ?? 0) > 0)
                          Text(
                            'Incentive ${formatLedgerAmount(sale.referrerIncentive!)}',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFFC2410C)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
