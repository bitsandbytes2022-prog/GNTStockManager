/// Spreads a flat cart [discount] (₹) over the lines marked [eligible], in
/// proportion to each line's value, and returns every line's new per-unit
/// price (ineligible lines come back unchanged).
///
/// Every eligible line gets the same percentage off, rounded to the paisa,
/// so the rupees actually taken off can differ from [discount] by a few
/// paise — callers show the real figure from the returned prices. A
/// discount larger than the eligible lines' value is capped at it.
List<double> spreadCartDiscount({
  required List<double> prices,
  required List<int> quantities,
  required List<bool> eligible,
  required double discount,
}) {
  assert(prices.length == quantities.length && prices.length == eligible.length);
  var base = 0.0;
  for (var i = 0; i < prices.length; i++) {
    if (eligible[i]) base += prices[i] * quantities[i];
  }
  if (discount <= 0 || base <= 0) return List.of(prices);
  final factor = 1 - (discount > base ? base : discount) / base;
  return [
    for (var i = 0; i < prices.length; i++)
      eligible[i] ? (prices[i] * factor * 100).roundToDouble() / 100 : prices[i],
  ];
}
