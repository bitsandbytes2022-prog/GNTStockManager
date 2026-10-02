/// One bill line with its GST-exclusive rate and amount.
class GstLine {
  final double rate;
  final double amount;
  const GstLine(this.rate, this.amount);
}

/// A bill's GST split, rounded the way it is printed on bills: whole-rupee
/// rates, line amounts, taxable value and CGST/SGST, plus the [roundOff]
/// that brings taxable + GST back to the actual bill total.
class GstBreakup {
  final List<GstLine> lines;
  final double taxable;
  final double halfGst; // CGST, and equally SGST
  final double roundOff;
  const GstBreakup(this.lines, this.taxable, this.halfGst, this.roundOff);

  bool get hasRoundOff => roundOff.abs() >= 0.005;
}

/// Splits a GST-inclusive bill — lines of [prices] (GST-inclusive, per
/// unit) × [quantities], totalling [total] — at [gstRate]%.
///
/// Sale prices are GST-inclusive throughout the app, so the customer's total
/// never changes; this only reverse-computes the breakup baked into it.
///
/// Each line's rate is rounded to the whole rupee. On a cheap item sold in
/// bulk that could throw the line off by rupees (₹2 screws: 1.69 → 2, ×100
/// = ₹31 too much), so a line whose rounding would move its amount by more
/// than ₹1 keeps its rate in paise and rounds only the amount.
GstBreakup roundedGstBreakup({
  required List<double> prices,
  required List<int> quantities,
  required double total,
  required double gstRate,
}) {
  assert(prices.length == quantities.length);
  final factor = 1 + gstRate / 100;
  final lines = <GstLine>[];
  for (var i = 0; i < prices.length; i++) {
    final qty = quantities[i];
    final exact = prices[i] / factor;
    final whole = exact.roundToDouble();
    if ((whole - exact).abs() * qty <= 1) {
      lines.add(GstLine(whole, whole * qty));
    } else {
      final paise = (exact * 100).roundToDouble() / 100;
      lines.add(GstLine(paise, (paise * qty).roundToDouble()));
    }
  }
  final taxable = lines.fold<double>(0, (s, l) => s + l.amount);
  final half = (taxable * gstRate / 200).roundToDouble();
  final roundOff = ((total - taxable - 2 * half) * 100).roundToDouble() / 100;
  return GstBreakup(lines, taxable, half, roundOff);
}

/// Whole rupees without decimals, anything else to the paisa.
String formatRate(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// A round-off amount with its sign, e.g. `+0.42` / `-1.00`.
String formatRoundOff(double v) =>
    '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}';
