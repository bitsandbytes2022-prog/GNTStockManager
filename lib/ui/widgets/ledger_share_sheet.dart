import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../models/party_model.dart';
import '../../services/ledger_service.dart';
import '../../utils/ledger_statement_pdf.dart';

enum _Period { all, thisMonth, last3Months }

/// Lets the user pick a period and share (or print) [party]'s account
/// statement as a PDF — e.g. to WhatsApp it to a shopkeeper after a sale.
Future<void> showShareLedgerSheet(BuildContext context, Party party) {
  return showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ShareLedgerSheet(partyId: party.id, partyName: party.name),
  );
}

class _ShareLedgerSheet extends StatefulWidget {
  final String partyId;
  final String partyName;

  const _ShareLedgerSheet({required this.partyId, required this.partyName});

  @override
  State<_ShareLedgerSheet> createState() => _ShareLedgerSheetState();
}

class _ShareLedgerSheetState extends State<_ShareLedgerSheet> {
  _Period _period = _Period.all;
  bool _busy = false;

  DateTime? get _from {
    final now = DateTime.now();
    switch (_period) {
      case _Period.all:
        return null;
      case _Period.thisMonth:
        return DateTime(now.year, now.month, 1);
      case _Period.last3Months:
        return DateTime(now.year, now.month - 2, 1);
    }
  }

  Future<void> _run({required bool print}) async {
    setState(() => _busy = true);
    try {
      // Load fresh, so a sale saved a moment ago is included.
      final data = await LedgerService().load();
      final party =
          data.parties.where((p) => p.id == widget.partyId).firstOrNull;
      if (party == null) throw Exception('Account not found');
      final pdf = await buildLedgerStatementPdf(
        party: party,
        rows: data.rowsFor(party),
        from: _from,
      );
      final bytes = await pdf.save();
      final safeName =
          party.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
      final fileName =
          'Statement_${safeName}_${DateFormat('dd-MM-yyyy').format(DateTime.now())}.pdf';
      if (print) {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not create statement: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share statement — ${widget.partyName}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('PDF with every sale, payment and the balance',
                style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final (period, label) in [
                  (_Period.all, 'All entries'),
                  (_Period.thisMonth, 'This month'),
                  (_Period.last3Months, 'Last 3 months'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _period == period,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _period = period),
                  ),
              ],
            ),
            if (_period != _Period.all)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Older entries are carried in as one "balance brought forward" line.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _run(print: false),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.share),
                    label: const Text('Share PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(print: true),
                    icon: const Icon(Icons.print),
                    label: const Text('Print'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
