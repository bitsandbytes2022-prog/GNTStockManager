// Shared column definitions between the Excel export and import screens —
// keeping one source of truth means an exported header always matches what
// the importer looks for, and a bulk-edit round trip can't silently drift.

/// Every column the export screen can show, in a stable order. Import only
/// recognizes columns whose label matches one of these (case-insensitively,
/// trimmed) — anything else in the sheet is ignored rather than guessed at.
const List<Map<String, String>> kProductExcelColumns = [
  {'key': 'name', 'label': 'Product Name'},
  {'key': 'size', 'label': 'Size'},
  {'key': 'category', 'label': 'Category'},
  {'key': 'purchasePrice', 'label': 'Purchase Price (₹)'},
  {'key': 'margin', 'label': 'Margin (%)'},
  {'key': 'salePrice', 'label': 'Sale Price (₹)'},
  {'key': 'minSalePrice', 'label': 'Min Sale Price (₹)'},
  {'key': 'wholesalePrice', 'label': 'Wholesale Price (₹)'},
  {'key': 'stock', 'label': 'Stock'},
  {'key': 'gst', 'label': 'GST (%)'},
  {'key': 'discountReceived', 'label': 'Discount Received (%)'},
  {'key': 'sellingDiscount', 'label': 'Selling Discount (%)'},
  {'key': 'totalSold', 'label': 'Total Sold'},
  {'key': 'saleCount', 'label': 'Sale Count'},
];

/// The hidden-in-plain-sight column every flat (non-pivot) export carries so
/// an edited copy can be matched back to the right product on import,
/// regardless of which display columns were selected for export.
const String kProductIdColumnLabel = 'Product ID (do not edit)';

/// Columns safe to write back to Firestore from an imported sheet. Deliberately
/// excludes 'margin' and 'minSalePrice' (derived/advisory, not stored fields
/// the rest of the app treats as authoritative) and 'totalSold'/'saleCount'
/// (sales history — editing these from a spreadsheet would desync analytics
/// from the actual recorded sales).
const Set<String> kImportableProductKeys = {
  'name',
  'size',
  'category',
  'purchasePrice',
  'salePrice',
  'wholesalePrice',
  'stock',
  'gst',
  'discountReceived',
  'sellingDiscount',
};
