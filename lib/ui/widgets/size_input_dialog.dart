import 'package:flutter/material.dart';

import '../../models/size_units.dart';

/// Shows the shared "Add Size" dialog and returns the composed size string
/// (e.g. "20 MM", "3/4 Inch", or a reducer like "1 × 3/4 Inch"), or null if
/// cancelled / empty.
Future<String?> showSizeInputDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const SizeInputDialog(),
  );
}

class SizeInputDialog extends StatefulWidget {
  const SizeInputDialog({super.key});

  @override
  State<SizeInputDialog> createState() => _SizeInputDialogState();
}

class _SizeInputDialogState extends State<SizeInputDialog> {
  final _value1 = TextEditingController();
  final _value2 = TextEditingController();
  String? _unit = sizeUnits.first;
  bool _isReducer = false;

  @override
  void dispose() {
    _value1.dispose();
    _value2.dispose();
    super.dispose();
  }

  String _composed() => _isReducer
      ? composeReducerSize(_value1.text, _value2.text, _unit)
      : composeSize(_value1.text, _unit);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add Size'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reducer toggle (e.g. 1" × 3/4")
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile(
              dense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              title: const Text('Reducer (two sizes)'),
              subtitle: const Text(
                'e.g. 1 × 3/4',
                style: TextStyle(fontSize: 12),
              ),
              value: _isReducer,
              onChanged: (v) => setState(() => _isReducer = v),
            ),
          ),
          const SizedBox(height: 14),
          // Value field(s)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _value1,
                  autofocus: true,
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    labelText: _isReducer ? 'Size 1' : 'Value',
                    hintText: 'e.g., 1',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_isReducer) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('×',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: TextField(
                    controller: _value2,
                    decoration: const InputDecoration(
                      labelText: 'Size 2',
                      hintText: 'e.g., 3/4',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _unit,
            decoration: const InputDecoration(
              labelText: 'Unit',
              border: OutlineInputBorder(),
            ),
            items: sizeUnits
                .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                .toList(),
            onChanged: (v) => setState(() => _unit = v),
          ),
          const SizedBox(height: 12),
          // Live preview
          Row(
            children: [
              const Text('Preview: ',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              Text(
                _composed().isEmpty ? '—' : _composed(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _composed()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
