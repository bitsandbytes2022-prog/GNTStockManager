import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/quantity.dart';
import '../theme/app_theme.dart';

/// Colour code, tint units and tint charge for a tinted emulsion bucket in
/// the add-to-cart dialog, with the bucket + tint total. Typing the units
/// fills in the charge at the Tint product's rate; the charge can still be
/// changed by hand.
class TintingFields extends StatelessWidget {
  final TextEditingController colorCodeController;
  final TextEditingController unitsController;
  final TextEditingController tintController;
  final double bucketPrice;
  final VoidCallback onChanged;

  /// The Tint product's rate per unit for this sale (retail or wholesale),
  /// and what a unit costs the shop. Null when there's no Tint product.
  final double? ratePerUnit;
  final double? costPerUnit;

  /// What a tint charge costs the shop (see tintCostFor).
  final double Function(double tintPrice, double? units) tintCostOf;

  /// Enter in any field (adds the line, like the dialog's other fields).
  final VoidCallback? onSubmitted;

  const TintingFields({
    super.key,
    required this.colorCodeController,
    required this.unitsController,
    required this.tintController,
    required this.bucketPrice,
    required this.onChanged,
    required this.ratePerUnit,
    required this.costPerUnit,
    required this.tintCostOf,
    this.onSubmitted,
  });

  static String _money(double v) => '₹${v.toStringAsFixed(2)}';

  void _unitsChanged() {
    final units = parseQty(unitsController.text) ?? 0;
    if (ratePerUnit != null) {
      tintController.text =
          units > 0 ? (units * ratePerUnit!).toStringAsFixed(2) : '';
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final tint = double.tryParse(tintController.text) ?? 0;
    final units = parseQty(unitsController.text);
    final cost = tint > 0 || (units ?? 0) > 0 ? tintCostOf(tint, units) : 0.0;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(8));
    final muted = const TextStyle(fontSize: 12, color: AppColors.textMuted);

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
          TextField(
            controller: colorCodeController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Color code',
              hintText: 'e.g. 8203',
              isDense: true,
              border: border,
            ),
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSubmitted?.call(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: unitsController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}([.,]\d{0,2})?')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Tint units',
                    helperText: 'per bucket',
                    isDense: true,
                    border: border,
                  ),
                  onChanged: (_) => _unitsChanged(),
                  onSubmitted: (_) => onSubmitted?.call(),
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
                    helperText: 'per bucket',
                    prefixText: '₹',
                    isDense: true,
                    border: border,
                  ),
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSubmitted?.call(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Bucket ${_money(bucketPrice)} + Tint ${_money(tint)}'
            ' = ${_money(bucketPrice + tint)} per bucket',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (ratePerUnit == null)
            Text('No "Tint" product found — tint cost and stock aren\'t counted.',
                style: muted.copyWith(color: AppColors.stockLow))
          else ...[
            if (units != null && units > 0)
              Text(
                '${formatQty(units)} units × ${_money(costPerUnit!)} cost'
                ' = ${_money(cost)} · tint profit ${_money(tint - cost)}',
                style: muted,
              )
            else if (tint > 0)
              Text(
                'Enter the units used to count tint cost and stock '
                '(estimated cost ${_money(cost)}).',
                style: muted.copyWith(color: AppColors.stockLow),
              )
            else
              Text('Tint rate ${_money(ratePerUnit!)} per unit', style: muted),
          ],
        ],
      ),
    );
  }
}
