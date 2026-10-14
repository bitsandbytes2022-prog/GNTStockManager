import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/party_model.dart';
import '../../models/sale_model.dart';
import '../../services/ledger_service.dart';
import '../../services/sales_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import 'ledger_screen.dart' show formatLedgerAmount;

enum _CreditFilter { all, pending, settled }

/// Every credit sale in one list — date, customer, total, paid and
/// pending — searchable by customer name. Mock sales are left out, the
/// same as everywhere money is counted.
class CreditSalesScreen extends StatefulWidget {
  const CreditSalesScreen({super.key});

  @override
  State<CreditSalesScreen> createState() => _CreditSalesScreenState();
}

class _CreditSalesScreenState extends State<CreditSalesScreen> {
  final SalesService _salesService = SalesService();
  final TextEditingController _searchController = TextEditingController();
  late final Stream<List<Sale>> _stream = _salesService.getSalesStream();

  /// Shopkeeper names by id, for sales linked to a ledger party without a
  /// typed buyer name.
  Map<String, String> _partyNames = {};
  String _query = '';
  _CreditFilter _filter = _CreditFilter.all;

  static final DateFormat _date = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadParties() async {
    try {
      final parties = await LedgerService().getParties(PartyType.customer);
      if (mounted) {
        setState(() => _partyNames = {for (final p in parties) p.id: p.name});
      }
    } catch (_) {
      // Names fall back to the buyer name or "Walk-in customer".
    }
  }

  String _customerName(Sale sale) {
    final buyer = sale.buyerName?.trim();
    if (buyer != null && buyer.isNotEmpty) return buyer;
    final party = sale.partyId != null ? _partyNames[sale.partyId] : null;
    return party ?? 'Walk-in customer';
  }

  List<Sale> _visible(List<Sale> sales) {
    final q = _query.trim().toLowerCase();
    return sales.where((s) {
      if (!s.isCredit || s.isMock) return false;
      if (_filter == _CreditFilter.pending && s.isFullyPaid) return false;
      if (_filter == _CreditFilter.settled && !s.isFullyPaid) return false;
      if (q.isEmpty) return true;
      return _customerName(s).toLowerCase().contains(q) ||
          (s.buyerPhone ?? '').contains(q);
    }).toList();
  }

  Future<void> _recordPayment(Sale sale) async {
    final amountController = TextEditingController(
      text: sale.amountDue.toStringAsFixed(2),
    );
    final noteController = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text('Payment from ${_customerName(sale)}'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bill #${sale.invoiceNumber} · Pending ${formatLedgerAmount(sale.amountDue)}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount received',
                      prefixText: '₹',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(amountController.text);
                  if (value == null || value <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter a valid amount')),
                    );
                    return;
                  }
                  Navigator.pop(context, value);
                },
                child: const Text('Record'),
              ),
            ],
          ),
    );
    final note = noteController.text.trim();
    amountController.dispose();
    noteController.dispose();
    if (amount == null) return;

    try {
      await _salesService.recordPayment(
        saleId: sale.id,
        amount: amount,
        note: note.isEmpty ? null : note,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment of ${formatLedgerAmount(amount)} recorded'),
            backgroundColor: AppColors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error recording payment: $e'),
            backgroundColor: AppColors.stockOut,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(title: const Text('Credit sales')),
      body: StreamBuilder<List<Sale>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const ShimmerBox(height: 80, radius: 14),
                const SizedBox(height: 16),
                for (var i = 0; i < 6; i++) ...[
                  const ShimmerBox(height: 56),
                  const SizedBox(height: 8),
                ],
              ],
            );
          }
          final sales = _visible(snapshot.data!);
          return Column(
            children: [
              _buildHeader(sales, isWide),
              if (isWide && sales.isNotEmpty) const _TableHeader(),
              Expanded(
                child:
                    sales.isEmpty
                        ? _buildEmpty()
                        : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            isWide ? 0 : 12,
                            16,
                            24,
                          ),
                          itemCount: sales.length,
                          separatorBuilder:
                              (_, __) => SizedBox(height: isWide ? 0 : 8),
                          itemBuilder: (context, i) {
                            final sale = sales[i];
                            final onTap =
                                sale.isFullyPaid
                                    ? null
                                    : () => _recordPayment(sale);
                            return isWide
                                ? _TableRow(
                                  date: _date.format(sale.createdAt),
                                  name: _customerName(sale),
                                  invoice: sale.invoiceNumber,
                                  sale: sale,
                                  striped: i.isOdd,
                                  onTap: onTap,
                                )
                                : _MobileRow(
                                  date: _date.format(sale.createdAt),
                                  name: _customerName(sale),
                                  invoice: sale.invoiceNumber,
                                  sale: sale,
                                  onTap: onTap,
                                );
                          },
                        ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(List<Sale> sales, bool isWide) {
    final total = sales.fold<double>(0, (s, e) => s + e.totalAmount);
    final pending = sales.fold<double>(0, (s, e) => s + e.amountDue);
    final paid = total - pending;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SummaryTile(label: 'Total', value: total, color: AppColors.navy),
              _SummaryTile(label: 'Paid', value: paid, color: AppColors.green),
              _SummaryTile(
                label: 'Pending',
                value: pending,
                color: AppColors.stockOut,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search by customer name',
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  _query.isEmpty
                      ? null
                      : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              filled: true,
              fillColor: AppColors.page,
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final f in _CreditFilter.values)
                ChoiceChip(
                  label: Text(switch (f) {
                    _CreditFilter.all => 'All',
                    _CreditFilter.pending => 'Pending',
                    _CreditFilter.settled => 'Fully paid',
                  }),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  '${sales.length} sale${sales.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              _query.isEmpty
                  ? 'No credit sales here'
                  : 'No credit sales for "$_query"',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatLedgerAmount(value),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _headerStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: AppColors.textMuted,
);

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('Sale date', style: _headerStyle)),
          Expanded(flex: 4, child: Text('Customer', style: _headerStyle)),
          Expanded(
            flex: 2,
            child: Text(
              'Total',
              textAlign: TextAlign.right,
              style: _headerStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Paid',
              textAlign: TextAlign.right,
              style: _headerStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Pending',
              textAlign: TextAlign.right,
              style: _headerStyle,
            ),
          ),
          SizedBox(width: 32),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final String date;
  final String name;
  final int invoice;
  final Sale sale;
  final bool striped;
  final VoidCallback? onTap;

  const _TableRow({
    required this.date,
    required this.name,
    required this.invoice,
    required this.sale,
    required this.striped,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final due = sale.amountDue;
    return Material(
      color: striped ? const Color(0xFFFAFBFC) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(flex: 2, child: Text(date)),
              Expanded(
                flex: 4,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: '  #$invoice',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatLedgerAmount(sale.totalAmount),
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  formatLedgerAmount(sale.amountPaid),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.green),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  due > 0 ? formatLedgerAmount(due) : 'Paid',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: due > 0 ? AppColors.stockOut : AppColors.textMuted,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                child:
                    onTap == null
                        ? null
                        : const Tooltip(
                          message: 'Record payment',
                          child: Icon(
                            Icons.payments_outlined,
                            size: 18,
                            color: AppColors.blue,
                          ),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileRow extends StatelessWidget {
  final String date;
  final String name;
  final int invoice;
  final Sale sale;
  final VoidCallback? onTap;

  const _MobileRow({
    required this.date,
    required this.name,
    required this.invoice,
    required this.sale,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final due = sale.amountDue;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    due > 0 ? formatLedgerAmount(due) : 'Paid',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: due > 0 ? AppColors.stockOut : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$date · #$invoice',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  if (due > 0)
                    const Text(
                      'pending',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Amount(label: 'Total', value: sale.totalAmount),
                  const SizedBox(width: 20),
                  _Amount(
                    label: 'Paid',
                    value: sale.amountPaid,
                    color: AppColors.green,
                  ),
                  const Spacer(),
                  if (onTap != null)
                    const Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 16,
                          color: AppColors.blue,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Record payment',
                          style: TextStyle(fontSize: 12, color: AppColors.blue),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;

  const _Amount({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          TextSpan(
            text: formatLedgerAmount(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
