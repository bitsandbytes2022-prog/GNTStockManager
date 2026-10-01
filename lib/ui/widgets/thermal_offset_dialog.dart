import 'package:flutter/material.dart';

import '../../services/settings_service.dart';
import '../../utils/thermal_print.dart';

/// Lets the user nudge a centred thermal receipt left/right so it lines up
/// with a narrow roll taped into a wider printer. Saves on "Save".
Future<void> showThermalOffsetDialog(BuildContext context) async {
  final settings = SettingsService();
  var offset = await settings.getThermalOffsetMm();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final String position;
        if (offset == 0) {
          position = 'Centred';
        } else {
          position =
              '${offset.abs().toStringAsFixed(1)} mm ${offset > 0 ? 'right' : 'left'}';
        }
        return AlertDialog(
          title: const Text('Adjust Receipt Position'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'If the receipt is cut off on the left edge of the paper, '
                'move it right. If it is cut off on the right, move it left.',
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  position,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: [
                  const Text('Left'),
                  Expanded(
                    child: Slider(
                      value: offset,
                      min: -thermalOffsetLimitMm,
                      max: thermalOffsetLimitMm,
                      divisions: (thermalOffsetLimitMm * 4).round(),
                      label: position,
                      onChanged: (v) => setDialogState(() => offset = v),
                    ),
                  ),
                  const Text('Right'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => setDialogState(() => offset = 0),
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await settings.setThermalOffsetMm(offset);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
