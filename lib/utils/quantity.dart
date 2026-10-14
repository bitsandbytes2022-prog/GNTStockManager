import 'package:flutter/services.dart';

// Quantities and stock are doubles so items sold by weight (e.g. 4.6 KG)
// can hold fractions. Everything else still deals in whole numbers, so
// these helpers keep whole values looking (and stored) like integers.

/// Rounds away floating-point noise (4.6 - 1.2 = 3.3999999999999995) —
/// three decimals is gram precision for KG items.
double roundQty(num q) => (q * 1000).roundToDouble() / 1000;

/// "5" for whole quantities, "4.6" / "0.25" for fractional ones.
String formatQty(num q) {
  final r = roundQty(q);
  if (r == r.truncateToDouble()) return r.toInt().toString();
  return r
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// The value to write to Firestore: an int when whole, so products and
/// sale lines that never use fractions keep integer fields.
num storeQty(num q) {
  final r = roundQty(q);
  return r == r.truncateToDouble() ? r.toInt() : r;
}

/// Reads a quantity/stock field that may be stored as int or double.
double readQty(dynamic v) => v is num ? v.toDouble() : 0;

/// Parses user-typed quantity text, accepting "4.6" (and "4,6").
double? parseQty(String raw) {
  final t = raw.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  return v == null ? null : roundQty(v);
}

/// Keyboard for a quantity field — decimal only where fractions are allowed.
TextInputType qtyKeyboard(bool fractional) => fractional
    ? const TextInputType.numberWithOptions(decimal: true)
    : TextInputType.number;

/// Input filter for a quantity field: whole numbers, or up to three
/// decimals (grams) where fractions are allowed.
List<TextInputFormatter> qtyInputFormatters(bool fractional) => fractional
    ? [
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,5}([.,]\d{0,3})?')),
      ]
    : [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ];
