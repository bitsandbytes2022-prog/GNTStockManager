import 'package:flutter/material.dart';

import '../../services/settings_service.dart';
import '../../utils/thermal_print.dart';

/// Thermal receipt settings: the page length (for every roll size) and,
/// with [showOffset], a left/right nudge so a centred receipt lines up with
/// a narrow roll taped into a wider printer. Saves on "Save".
Future<void> showThermalOffsetDialog(
  BuildContext context, {
  bool showOffset = true,
}) async {
  final settings = SettingsService();
  var offset = await settings.getThermalOffsetMm();
  var pageLength = await settings.getThermalPageLengthMm();
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
          title: const Text('Receipt Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Page length',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'A long receipt prints as several pages. If items go '
                  'missing where one page ends, make this shorter — it must '
                  'not be longer than the paper length set for the printer.',
                  style: TextStyle(fontSize: 13),
                ),
                Center(
                  child: Text(
                    '${pageLength.round()} mm',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Slider(
                  value: pageLength,
                  min: thermalPageLengthMinMm,
                  max: thermalPageLengthMaxMm,
                  divisions:
                      ((thermalPageLengthMaxMm - thermalPageLengthMinMm) / 10)
                          .round(),
                  label: '${pageLength.round()} mm',
                  onChanged: (v) => setDialogState(() => pageLength = v),
                ),
                if (showOffset) ...[
                  const Divider(),
                  const Text('Position',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'If the receipt is cut off on the left edge of the paper, '
                    'move it right. If it is cut off on the right, move it left.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDialogState(() {
                if (showOffset) offset = 0;
                pageLength = thermalPageLengthDefaultMm;
              }),
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await settings.setThermalOffsetMm(offset);
                await settings.setThermalPageLengthMm(pageLength);
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
