import '../models/product_model.dart';

/// What a tint charge of [tintPrice] costs the shop, going by the "Tint"
/// product's cost-to-price ratio (e.g. cost ₹45.50 for ₹100 of tint → 45.5%).
/// 0 when there's no Tint product or it has no sale price.
double tintCostFor(double tintPrice, Iterable<Product> products) {
  if (tintPrice <= 0) return 0;
  for (final p in products) {
    if (p.name.trim().toLowerCase() == 'tint') {
      return p.salePrice > 0 ? tintPrice * p.purchasePrice / p.salePrice : 0;
    }
  }
  return 0;
}
