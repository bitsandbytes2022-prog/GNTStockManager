import '../models/product_model.dart';

/// The shop's "Tint" product — tinted buckets take their tint from it.
Product? findTintProduct(Iterable<Product> products) {
  for (final p in products) {
    if (p.name.trim().toLowerCase() == 'tint') return p;
  }
  return null;
}

/// What a bucket's tint cost the shop. With [units] (how much of the Tint
/// product went in) it's those units at the Tint product's purchase price,
/// whatever was charged for them. Lines saved before tint was counted in
/// units only have the ₹ charge, so those fall back to the Tint product's
/// cost-to-price ratio. 0 when there's no Tint product.
double tintCostFor(
  double tintPrice,
  Iterable<Product> products, {
  double? units,
}) {
  final tint = findTintProduct(products);
  if (tint == null) return 0;
  if (units != null && units > 0) return units * tint.purchasePrice;
  if (tintPrice <= 0 || tint.salePrice <= 0) return 0;
  return tintPrice * tint.purchasePrice / tint.salePrice;
}
