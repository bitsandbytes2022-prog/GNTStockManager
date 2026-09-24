// Shared parsing/merge logic for anything that bulk-edits Product fields
// from free-text input — the Excel importer and the in-app table editor
// both funnel through here so a value like "12%" or "-" is interpreted the
// same way regardless of which screen it came from.

import '../models/product_model.dart';

/// Result of parsing an optional percentage field (GST, discounts): `ok` is
/// false when the text isn't blank/'-' and also isn't a valid number, so the
/// caller can tell "cleared" apart from "typo".
class OptionalDoubleParse {
  final double? value;
  final bool ok;
  const OptionalDoubleParse(this.value, this.ok);
}

double? parseRequiredDouble(String raw) {
  final t = raw.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

int? parseStock(String raw) {
  final t = raw.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  final asInt = int.tryParse(t);
  if (asInt != null) return asInt;
  final asDouble = double.tryParse(t);
  if (asDouble != null) return asDouble.round();
  return null;
}

OptionalDoubleParse parseOptionalPercent(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t == '-' || t == '—') return const OptionalDoubleParse(null, true);
  final cleaned = t.endsWith('%') ? t.substring(0, t.length - 1).trim() : t;
  final v = double.tryParse(cleaned);
  if (v == null) return const OptionalDoubleParse(null, false);
  return OptionalDoubleParse(v, true);
}

/// Builds a new Product with only the given fields overridden — everything
/// else (image, createdAt, sales stats, ...) carries over untouched from
/// the existing product. Built directly rather than via Product.copyWith so
/// a nullable percentage field can be explicitly cleared to null, which
/// copyWith's `??` pattern can't express.
///
/// [fields] keys are: name, size, category, purchasePrice, salePrice,
/// wholesalePrice, stock, gst, discountReceived, sellingDiscount. A key that
/// isn't present leaves that field untouched.
Product mergeProductFields(Product original, Map<String, dynamic> fields) {
  final purchasePrice = fields.containsKey('purchasePrice')
      ? fields['purchasePrice'] as double
      : original.purchasePrice;
  final wholesalePrice = fields.containsKey('wholesalePrice')
      ? fields['wholesalePrice'] as double
      : original.wholesalePrice;
  // Keep the saved wholesale margin in step with a price that was set or
  // re-based on a new purchase price.
  final wholesaleTouched = fields.containsKey('wholesalePrice') ||
      fields.containsKey('purchasePrice');
  final wholesaleMargin =
      wholesaleTouched && wholesalePrice != null && purchasePrice > 0
          ? (wholesalePrice - purchasePrice) / purchasePrice * 100
          : original.wholesaleMargin;

  return Product(
    id: original.id,
    name: fields.containsKey('name') ? fields['name'] as String : original.name,
    size: fields.containsKey('size') ? fields['size'] as String : original.size,
    purchasePrice: purchasePrice,
    salePrice:
        fields.containsKey('salePrice') ? fields['salePrice'] as double : original.salePrice,
    stock: fields.containsKey('stock') ? fields['stock'] as int : original.stock,
    imageBase64: original.imageBase64,
    createdAt: original.createdAt,
    category: fields.containsKey('category') ? fields['category'] as String : original.category,
    subcategory: original.subcategory,
    gst: fields.containsKey('gst') ? fields['gst'] as double? : original.gst,
    discountReceived: fields.containsKey('discountReceived')
        ? fields['discountReceived'] as double?
        : original.discountReceived,
    sellingDiscount: fields.containsKey('sellingDiscount')
        ? fields['sellingDiscount'] as double?
        : original.sellingDiscount,
    margin: original.margin,
    wholesaleMargin: wholesaleMargin,
    wholesalePrice: wholesalePrice,
    totalSold: original.totalSold,
    saleCount: original.saleCount,
    salesFrequency: original.salesFrequency,
  );
}
