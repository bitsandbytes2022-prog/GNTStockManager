import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/party_model.dart';
import '../../services/ledger_service.dart';
import 'party_ledger_screen.dart';

final NumberFormat _rupees =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Formats a ledger amount, showing paise only when there are any.
String formatLedgerAmount(double value) {
  final rounded = (value * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return _rupees.format(rounded);
  return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)
      .format(rounded);
}

/// Running accounts with shopkeepers: those who buy from the shop
/// (Shopkeepers tab) and those the shop buys from (Suppliers tab).
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  late final Stream<LedgerData> _stream = LedgerService().watch();
  String _query = '';

  PartyType get _type =>
      _tabController.index == 0 ? PartyType.customer : PartyType.supplier;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.storefront), text: 'Shopkeepers'),
            Tab(icon: Icon(Icons.local_shipping), text: 'Suppliers'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showPartyFormDialog(context, type: _type),
        icon: const Icon(Icons.person_add),
        label: Text(_type == PartyType.customer ? 'Add Shopkeeper' : 'Add Supplier'),
      ),
      body: StreamBuilder<LedgerData>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading ledger: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildTab(snapshot.data!);
        },
      ),
    );
  }

  Widget _buildTab(LedgerData data) {
    final isCustomer = _type == PartyType.customer;
    final all = data.parties.where((p) => p.type == _type).toList();
    final balances = {for (final p in all) p.id: data.balanceOf(p)};
    final total = balances.values.fold<double>(
        0, (sum, b) => sum + (b > 0 ? b : 0));

    final q = _query.toLowerCase().trim();
    final parties = q.isEmpty
        ? all
        : all
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                (p.phone ?? '').contains(q))
            .toList();
    // Biggest balance first — who to collect from / pay first.
    parties.sort((a, b) => balances[b.id]!.compareTo(balances[a.id]!));

    final color = isCustomer ? Colors.green : Colors.red;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.shade600, color.shade800],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCustomer ? 'Total to receive' : 'Total to pay',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                formatLedgerAmount(total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isCustomer
                    ? '${all.length} shopkeeper${all.length == 1 ? '' : 's'} who buy from you'
                    : '${all.length} supplier${all.length == 1 ? '' : 's'} you buy from',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            hintText: 'Search by name or phone',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  isCustomer
                      ? 'No shopkeepers yet.\nAdd one to track their purchases and payments.'
                      : 'No suppliers yet.\nAdd one to track your purchases and payments.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          )
        else
          for (final party in parties)
            _PartyTile(party: party, balance: balances[party.id]!),
      ],
    );
  }
}

class _PartyTile extends StatelessWidget {
  final Party party;
  final double balance;

  const _PartyTile({required this.party, required this.balance});

  @override
  Widget build(BuildContext context) {
    final label = balanceLabel(party, balance);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: party.isCustomer
              ? Colors.green.shade50
              : Colors.red.shade50,
          child: Text(
            party.name.isEmpty ? '?' : party.name[0].toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: party.isCustomer
                  ? Colors.green.shade800
                  : Colors.red.shade800,
            ),
          ),
        ),
        title: Text(party.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: party.phone?.isNotEmpty ?? false ? Text(party.phone!) : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatLedgerAmount(balance.abs()),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: label.color,
              ),
            ),
            Text(label.text,
                style: TextStyle(fontSize: 11, color: label.color)),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PartyLedgerScreen(partyId: party.id)),
        ),
      ),
    );
  }
}

class BalanceLabel {
  final String text;
  final Color color;
  const BalanceLabel(this.text, this.color);
}

/// Plain-words meaning of a balance: who owes whom.
BalanceLabel balanceLabel(Party party, double balance) {
  if (balance.abs() < 0.01) return BalanceLabel('Settled', Colors.grey.shade600);
  if (party.isCustomer) {
    return balance > 0
        ? BalanceLabel('To receive', Colors.green.shade700)
        : BalanceLabel('Advance received', Colors.orange.shade800);
  }
  return balance > 0
      ? BalanceLabel('To pay', Colors.red.shade700)
      : BalanceLabel('Advance paid', Colors.orange.shade800);
}

/// Add (when [party] is null) or edit a shopkeeper/supplier. Returns the
/// saved party.
Future<Party?> showPartyFormDialog(
  BuildContext context, {
  required PartyType type,
  Party? party,
  String? initialName,
}) {
  return showDialog<Party>(
    context: context,
    builder: (_) =>
        _PartyFormDialog(type: type, party: party, initialName: initialName),
  );
}

class _PartyFormDialog extends StatefulWidget {
  final PartyType type;
  final Party? party;
  final String? initialName;

  const _PartyFormDialog({required this.type, this.party, this.initialName});

  @override
  State<_PartyFormDialog> createState() => _PartyFormDialogState();
}

class _PartyFormDialogState extends State<_PartyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: widget.party?.name ?? widget.initialName);
  late final _phone = TextEditingController(text: widget.party?.phone);
  late final _address = TextEditingController(text: widget.party?.address);
  late final _opening = TextEditingController(
      text: (widget.party?.openingBalance ?? 0) == 0
          ? ''
          : widget.party!.openingBalance.toStringAsFixed(2));
  bool _saving = false;

  bool get _isCustomer => widget.type == PartyType.customer;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _opening.dispose();
    super.dispose();
  }

  String? _trimmed(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final opening = double.tryParse(_opening.text.trim()) ?? 0;
      final service = LedgerService();
      Party saved;
      if (widget.party == null) {
        saved = await service.addParty(Party(
          id: '',
          name: _name.text.trim(),
          phone: _trimmed(_phone),
          address: _trimmed(_address),
          type: widget.type,
          openingBalance: opening,
        ));
      } else {
        saved = Party(
          id: widget.party!.id,
          name: _name.text.trim(),
          phone: _trimmed(_phone),
          address: _trimmed(_address),
          type: widget.type,
          openingBalance: opening,
          createdAt: widget.party!.createdAt,
        );
        await service.updateParty(saved);
      }
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final noun = _isCustomer ? 'Shopkeeper' : 'Supplier';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.party == null ? 'Add $noun' : 'Edit $noun'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: widget.party == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name / Shop name',
                    prefixIcon: Icon(Icons.store),
                  ),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Required' : null,
                ),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                TextFormField(
                  controller: _address,
                  maxLines: 2,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Address (optional)',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                TextFormField(
                  controller: _opening,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Opening balance (optional)',
                    prefixText: '₹ ',
                    helperText: _isCustomer
                        ? 'Old amount they already owe you'
                        : 'Old amount you already owe them',
                    helperMaxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}
