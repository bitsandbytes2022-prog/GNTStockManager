import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/referrer_model.dart';
import '../../services/referrer_service.dart';
import '../theme/app_theme.dart';

IconData referrerIcon(ReferrerType type) =>
    type == ReferrerType.plumber ? Icons.plumbing : Icons.format_paint;

/// Optional "Plumber / Painter" field on Record sale and Edit sale.
class ReferrerSelector extends StatelessWidget {
  /// Name of the selected plumber/painter, or null when none.
  final String? name;
  final VoidCallback onTap;
  final VoidCallback onClear;

  /// Incentive paid to them on the spot for this sale; its field shows
  /// once someone is selected.
  final TextEditingController incentiveController;

  /// False on a credit bill — no incentive until the customer pays.
  final bool allowIncentive;

  const ReferrerSelector({
    super.key,
    required this.name,
    required this.onTap,
    required this.onClear,
    required this.incentiveController,
    this.allowIncentive = true,
  });

  @override
  Widget build(BuildContext context) {
    final selected = name != null;
    final tile = Container(
      decoration: BoxDecoration(
        color: selected ? Colors.orange.shade50 : AppColors.page,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? Colors.orange.shade200 : AppColors.border,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.handyman,
            color: selected ? Colors.orange.shade800 : AppColors.textMuted),
        title: Text(
          name ?? 'Plumber / Painter (optional)',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          selected
              ? 'Counts towards their business'
              : 'Tap to credit this sale to a plumber or painter',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: selected
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove plumber / painter',
                onPressed: onClear,
              )
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
    if (!selected) return tile;
    if (!allowIncentive) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tile,
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              'Credit bill — add the incentive from Plumbers & Painters once it is paid.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile,
        const SizedBox(height: 8),
        TextField(
          controller: incentiveController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: InputDecoration(
            labelText: 'Incentive paid now (optional)',
            helperText: 'Cash given to $name for this sale',
            prefixText: '₹',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

/// The incentive typed into [ReferrerSelector], or null when none.
double? parseIncentive(TextEditingController controller) {
  final value = double.tryParse(controller.text.trim()) ?? 0;
  return value > 0 ? value : null;
}

/// Bottom sheet to choose (or add) a plumber/painter.
Future<Referrer?> showReferrerPicker(BuildContext context) {
  return showModalBottomSheet<Referrer>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ReferrerPickerSheet(),
  );
}

class _ReferrerPickerSheet extends StatefulWidget {
  const _ReferrerPickerSheet();

  @override
  State<_ReferrerPickerSheet> createState() => _ReferrerPickerSheetState();
}

class _ReferrerPickerSheetState extends State<_ReferrerPickerSheet> {
  late final Future<List<Referrer>> _referrers =
      ReferrerService().getReferrers();
  String _query = '';

  /// Null shows both trades.
  ReferrerType? _type;

  Future<void> _addNew() async {
    final referrer = await showReferrerFormDialog(context,
        type: _type, initialName: _query.trim());
    if (referrer != null && mounted) Navigator.pop(context, referrer);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search plumber or painter',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final type in [null, ...ReferrerType.values])
                      ChoiceChip(
                        label: Text(type == null ? 'All' : '${type.label}s'),
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_add, color: Colors.orange),
                title: Text(_type == null
                    ? 'Add new plumber / painter'
                    : 'Add new ${_type!.label.toLowerCase()}'),
                onTap: _addNew,
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<Referrer>>(
                  future: _referrers,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final q = _query.toLowerCase().trim();
                    final referrers = snapshot.data!
                        .where((r) =>
                            (_type == null || r.type == _type) &&
                            (q.isEmpty ||
                                r.name.toLowerCase().contains(q) ||
                                (r.phone ?? '').contains(q)))
                        .toList();
                    if (referrers.isEmpty) {
                      return const Center(child: Text('No one found'));
                    }
                    return ListView.builder(
                      itemCount: referrers.length,
                      itemBuilder: (context, i) {
                        final r = referrers[i];
                        return ListTile(
                          leading: Icon(referrerIcon(r.type)),
                          title: Text(r.name),
                          subtitle: Text([
                            r.type.label,
                            if (r.phone?.isNotEmpty ?? false) r.phone!,
                          ].join(' · ')),
                          onTap: () => Navigator.pop(context, r),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add (when [referrer] is null) or edit a plumber/painter. Returns the
/// saved referrer.
Future<Referrer?> showReferrerFormDialog(
  BuildContext context, {
  Referrer? referrer,
  ReferrerType? type,
  String? initialName,
}) {
  return showDialog<Referrer>(
    context: context,
    builder: (_) => _ReferrerFormDialog(
      referrer: referrer,
      type: referrer?.type ?? type ?? ReferrerType.plumber,
      initialName: initialName,
    ),
  );
}

class _ReferrerFormDialog extends StatefulWidget {
  final Referrer? referrer;
  final ReferrerType type;
  final String? initialName;

  const _ReferrerFormDialog({
    required this.referrer,
    required this.type,
    this.initialName,
  });

  @override
  State<_ReferrerFormDialog> createState() => _ReferrerFormDialogState();
}

class _ReferrerFormDialogState extends State<_ReferrerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
      text: widget.referrer?.name ?? widget.initialName);
  late final _phone = TextEditingController(text: widget.referrer?.phone);
  late ReferrerType _type = widget.type;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final phone = _phone.text.trim();
      final service = ReferrerService();
      Referrer saved;
      if (widget.referrer == null) {
        saved = await service.addReferrer(Referrer(
          id: '',
          name: _name.text.trim(),
          phone: phone.isEmpty ? null : phone,
          type: _type,
        ));
      } else {
        saved = Referrer(
          id: widget.referrer!.id,
          name: _name.text.trim(),
          phone: phone.isEmpty ? null : phone,
          type: _type,
          createdAt: widget.referrer!.createdAt,
        );
        await service.updateReferrer(saved);
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
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.referrer == null
          ? 'Add ${_type.label}'
          : 'Edit ${_type.label}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<ReferrerType>(
                  segments: [
                    for (final t in ReferrerType.values)
                      ButtonSegment(
                        value: t,
                        icon: Icon(referrerIcon(t)),
                        label: Text(t.label),
                      ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _name,
                  autofocus: widget.referrer == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person),
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
