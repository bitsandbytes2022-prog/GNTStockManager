import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Colour code and tint charge for a tinted emulsion bucket in the
/// add-to-cart dialog, with the bucket + tint total.
class TintingFields extends StatelessWidget {
  final TextEditingController colorCodeController;
  final TextEditingController tintController;
  final double bucketPrice;
  final VoidCallback onChanged;

  /// What a tint charge costs the shop (see tintCostFor).
  final double Function(double tintPrice) tintCostOf;

  const TintingFields({
    super.key,
    required this.colorCodeController,
    required this.tintController,
    required this.bucketPrice,
    required this.onChanged,
    required this.tintCostOf,
  });

  @override
  Widget build(BuildContext context) {
    final tint = double.tryParse(tintController.text) ?? 0;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(8));
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.blueTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.blueLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.format_color_fill_rounded, size: 16, color: AppColors.blue),
              SizedBox(width: 6),
              Text(
                'Tinting',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: colorCodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Color code',
                    hintText: 'e.g. 8203',
                    isDense: true,
                    border: border,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: tintController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Tint price',
                    prefixText: '₹',
                    isDense: true,
                    border: border,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Bucket ₹${bucketPrice.toStringAsFixed(2)} + Tint ₹${tint.toStringAsFixed(2)}'
            ' = ₹${(bucketPrice + tint).toStringAsFixed(2)} per bucket',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (tint > 0)
            Text(
              'Tint cost: ₹${tintCostOf(tint).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}
