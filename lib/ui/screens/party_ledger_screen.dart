import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/party_model.dart';
import '../../models/sale_model.dart';
import '../../services/ledger_service.dart';
import 'edit_sales_screen.dart';
import 'ledger_screen.dart';
import 'purchase_entry_screen.dart';
import 'record_sale_screen.dart';
import '../widgets/ledger_share_sheet.dart';

/// One shopkeeper's / supplier's statement: every sale or purchase and
/// every payment, with the running balance.
class PartyLedgerScreen extends StatefulWidget {
  final String partyId;

  const PartyLedgerScreen({super.key, required this.partyId});

  @override
  State<PartyLedgerScreen> createState() => _PartyLedgerScreenState();
}

class _PartyLedgerScreenState extends State<PartyLedgerScreen> {
  late final Stream<LedgerData> _stream = LedgerService().watch();
  final _dateFormat = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LedgerData>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!;
        final party =
            data.parties.where((p) => p.id == widget.partyId).firstOrNull;
        if (party == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This account no longer exists')),
          );
        }
        return _buildScreen(party, data.rowsFor(party));
      },
    );
  }

  Widget _buildScreen(Party party, List<LedgerRow> rows) {
    final balance = rows.isEmpty ? party.openingBalance : rows.last.balance;
    final label = balanceLabel(party, balance);

    return Scaffold(
      appBar: AppBar(
        title: Text(party.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share statement (PDF)',
            onPressed: () => showShareLedgerSheet(context, party),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit details',
            onPressed: () =>
                showPartyFormDialog(context, type: party.type, party: party),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete',
            onPressed: () => _deleteParty(party),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: label.color.withOpacity(0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: label.color.withOpacity(0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.text,
                      style: TextStyle(color: label.color, fontSize: 14)),
                  Text(
                    formatLedgerAmount(balance.abs()),
                    style: TextStyle(
                      color: label.color,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (party.phone?.isNotEmpty ?? false)
                    Text(party.phone!,
                        style: TextStyle(color: Colors.grey.shade700)),
                  if (party.address?.isNotEmpty ?? false)
                    Text(party.address!,
                        style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: party.isCustomer
                ? [
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => RecordSaleScreen(party: party)),
                      ),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('New Sale'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          _showEntryDialog(party, LedgerEntryKind.payment),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Receive Payment'),
                    ),
                    // Dealing the other way round: buying from this
                    // shopkeeper and paying them.
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PurchaseEntryScreen(party: party)),
                      ),
                      icon: const Icon(Icons.shopping_basket_outlined),
                      label: const Text('Buy from them'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          _showEntryDialog(party, LedgerEntryKind.paidTo),
                      icon: const Icon(Icons.outbox_outlined),
                      label: const Text('Pay them'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showEntryDialog(party, LedgerEntryKind.bill),
                      icon: const Icon(Icons.note_add_outlined),
                      label: const Text('Add Bill (no items)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showShareLedgerSheet(context, party),
                      icon: const Icon(Icons.share),
                      label: const Text('Share Statement'),
                    ),
                  ]
                : [
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PurchaseEntryScreen(party: party)),
                      ),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Add Purchase'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          _showEntryDialog(party, LedgerEntryKind.payment),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Make Payment'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showShareLedgerSheet(context, party),
                      icon: const Icon(Icons.share),
                      label: const Text('Share Statement'),
                    ),
                  ],
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('No entries yet',
                    style: TextStyle(color: Colors.grey[600])),
              ),
            )
          else ...[
            Row(
              children: [
                Text('Statement',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800)),
                const Spacer(),
                Text('Newest first',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in rows.reversed) _buildRow(party, row),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(Party party, LedgerRow row) {
    final isDebit = row.debit > 0;
    final amount = isDebit ? row.debit : row.credit;
    final color = isDebit ? Colors.red.shade700 : Colors.green.shade700;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          isDebit ? Icons.arrow_upward : Icons.arrow_downward,
          color: color,
        ),
        title: Text(row.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            _dateFormat.format(row.date),
            if (row.subtitle?.isNotEmpty ?? false) row.subtitle!,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isDebit ? '+' : '−'} ${formatLedgerAmount(amount)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
            Text(
              'Bal ${formatLedgerAmount(row.balance)}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        onTap: () => _onRowTap(party, row),
      ),
    );
  }

  void _onRowTap(Party party, LedgerRow row) {
    switch (row.source) {
      case LedgerRowSource.opening:
        showPartyFormDialog(context, type: party.type, party: party);
      case LedgerRowSource.sale:
      case LedgerRowSource.salePayment:
        _showSale(row.sale!);
      case LedgerRowSource.entry:
        _showEntry(party, row.entry!);
    }
  }

  void _showSale(Sale sale) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Invoice #${sale.invoiceNumber}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(_dateFormat.format(sale.createdAt),
                  style: TextStyle(color: Colors.grey.shade600)),
              const Divider(),
              for (final item in sale.items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.productName),
                  subtitle: Text(
                      '${item.quantity} × ${formatLedgerAmount(item.salePrice)}'),
                  trailing: Text(
                      formatLedgerAmount(item.quantity * item.salePrice)),
                ),
              const Divider(),
              _summaryLine('Total', sale.totalAmount, bold: true),
              _summaryLine('Received', sale.amountPaid),
              _summaryLine('Due on this bill', sale.amountDue),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(
                        builder: (_) => EditSaleScreen(sale: sale)),
                  );
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit Sale'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryLine(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(formatLedgerAmount(value), style: style),
        ],
      ),
    );
  }

  void _showEntry(Party party, LedgerEntry entry) {
    final title = ledgerEntryTitle(party, entry.kind);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('$title · ${formatLedgerAmount(entry.amount)}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(_dateFormat.format(entry.date),
                  style: TextStyle(color: Colors.grey.shade600)),
              if (entry.note?.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(entry.note!),
              ],
              if (entry.items.isNotEmpty) ...[
                const Divider(),
                for (final item in entry.items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text([item.name, if (item.size.isNotEmpty) item.size]
                        .join(' · ')),
                    subtitle: Text(
                        '${item.quantity} × ${formatLedgerAmount(item.rate)} · added to stock'),
                    trailing: Text(formatLedgerAmount(item.total)),
                  ),
              ],
              if (entry.allocations.isNotEmpty) ...[
                const Divider(),
                Text(
                  'Applied to ${entry.allocations.length} unpaid bill${entry.allocations.length == 1 ? '' : 's'}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _editEntryDetails(entry);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit date / note'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _deleteEntry(entry);
                      },
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'To change the amount, delete this entry and add it again.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editEntryDetails(LedgerEntry entry) async {
    final result = await showDialog<_EntryFormResult>(
      context: context,
      builder: (_) => _EntryFormDialog(
        title: 'Edit entry',
        initialDate: entry.date,
        initialNote: entry.note,
        showAmount: false,
      ),
    );
    if (result == null) return;
    await _run(() => LedgerService()
        .updateEntryDetails(entry, date: result.date, note: result.note));
  }

  Future<void> _deleteEntry(LedgerEntry entry) async {
    final effects = [
      if (entry.allocations.isNotEmpty)
        'The bills it paid will show as unpaid again.',
      if (entry.items.isNotEmpty) 'Its items will be taken back out of stock.',
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text([
          'Delete this ${formatLedgerAmount(entry.amount)} entry?',
          ...effects,
        ].join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => LedgerService().deleteEntry(entry), done: 'Entry deleted');
  }

  Future<void> _showEntryDialog(Party party, LedgerEntryKind kind) async {
    final isPayment = kind == LedgerEntryKind.payment;
    final String title;
    final String? hint;
    if (kind == LedgerEntryKind.paidTo) {
      title = 'Pay ${party.name}';
      hint = 'Money you paid them, e.g. for goods bought from them. '
          'Their sale bills are not changed.';
    } else if (party.isCustomer) {
      title = isPayment ? 'Receive Payment' : 'Add Bill';
      hint = isPayment
          ? 'Settles their oldest unpaid bills first.'
          : 'For an amount owed without listing items, e.g. an old bill.';
    } else {
      title = 'Make Payment';
      hint = null;
    }
    final result = await showDialog<_EntryFormResult>(
      context: context,
      builder: (_) => _EntryFormDialog(title: title, hint: hint),
    );
    if (result == null) return;
    final service = LedgerService();
    final Future<void> Function() save;
    final String what;
    switch (kind) {
      case LedgerEntryKind.paidTo:
        what = 'Payment';
        save = () => service.addPaymentToCustomer(
              party: party,
              amount: result.amount!,
              date: result.date,
              note: result.note,
            );
      case LedgerEntryKind.payment:
        what = 'Payment';
        save = () => service.addPayment(
              party: party,
              amount: result.amount!,
              date: result.date,
              note: result.note,
            );
      case LedgerEntryKind.bill:
      case LedgerEntryKind.boughtFrom:
        what = 'Bill';
        save = () => service.addBill(
              party: party,
              amount: result.amount!,
              date: result.date,
              note: result.note,
            );
    }
    await _run(
      save,
      done: '$what of ${formatLedgerAmount(result.amount!)} saved',
    );
  }

  Future<void> _deleteParty(Party party) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${party.name}?'),
        content: const Text(
            'Only possible when there are no entries or sales in this ledger.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _run(() => LedgerService().deleteParty(party));
    if (ok && mounted) Navigator.pop(context);
  }

  /// Runs [action], reporting errors (and [done], if given) in a snackbar.
  Future<bool> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      if (mounted && done != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ));
      }
      return false;
    }
  }
}

class _EntryFormResult {
  final double? amount;
  final DateTime date;
  final String? note;
  _EntryFormResult(this.amount, this.date, this.note);
}

/// Amount + date + note form for payments and item-less bills.
class _EntryFormDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final bool showAmount;
  final DateTime? initialDate;
  final String? initialNote;

  const _EntryFormDialog({
    required this.title,
    this.hint,
    this.showAmount = true,
    this.initialDate,
    this.initialNote,
  });

  @override
  State<_EntryFormDialog> createState() => _EntryFormDialogState();
}

class _EntryFormDialogState extends State<_EntryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late final _note = TextEditingController(text: widget.initialNote);
  late DateTime _date = widget.initialDate ?? DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    // Keep the time of day so same-day entries stay in the order made.
    setState(() => _date = DateTime(picked.year, picked.month, picked.day,
        _date.hour, _date.minute, _date.second));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.hint != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(widget.hint!,
                      style: TextStyle(color: Colors.grey.shade700)),
                ),
              if (widget.showAmount)
                TextFormField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                  ),
                  validator: (v) {
                    final value = double.tryParse(v ?? '');
                    if (value == null || value <= 0) return 'Enter an amount';
                    return null;
                  },
                ),
              TextFormField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. UPI, cheque no., bill no.',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(DateFormat('d MMM yyyy').format(_date)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _EntryFormResult(
                double.tryParse(_amount.text),
                _date,
                _note.text.trim().isEmpty ? null : _note.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
