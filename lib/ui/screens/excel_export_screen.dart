import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../../models/product_model.dart';
import '../../services/firebase_service.dart';

// Web-only import
// ignore: avoid_web_libraries_in_flutter
import 'excel_export_web_stub.dart'
    if (dart.library.html) 'excel_export_web_helper.dart';

class ExcelExportScreen extends StatefulWidget {
  const ExcelExportScreen({super.key});

  @override
  State<ExcelExportScreen> createState() => _ExcelExportScreenState();
}

// All available export columns
const List<Map<String, String>> _kAvailableColumns = [
  {'key': 'name', 'label': 'Product Name'},
  {'key': 'size', 'label': 'Size'},
  {'key': 'category', 'label': 'Category'},
  {'key': 'purchasePrice', 'label': 'Purchase Price (₹)'},
  {'key': 'margin', 'label': 'Margin (%)'},
  {'key': 'salePrice', 'label': 'Sale Price (₹)'},
  {'key': 'minSalePrice', 'label': 'Min Sale Price (₹)'},
  {'key': 'stock', 'label': 'Stock'},
  {'key': 'gst', 'label': 'GST (%)'},
  {'key': 'discountReceived', 'label': 'Discount Received (%)'},
  {'key': 'sellingDiscount', 'label': 'Selling Discount (%)'},
  {'key': 'totalSold', 'label': 'Total Sold'},
  {'key': 'saleCount', 'label': 'Sale Count'},
];

enum _AdjustMode { setTo, adjustBy }
enum _AdjustType { margin, discount }
enum _SortOption { none, byName, byNameSize }

// Default columns (same as previous behaviour)
const Set<String> _kDefaultColumns = {
  'name', 'size', 'category', 'purchasePrice', 'margin', 'salePrice', 'minSalePrice',
};

class _ExcelExportScreenState extends State<ExcelExportScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  List<Product> _allProducts = [];
  List<String> _categories = [];
  Set<String> _selectedProductIds = {};
  String? _selectedCategory;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isExporting = false;
  bool _selectAll = false;

  // Selected export columns
  Set<String> _selectedColumns = Set.from(_kDefaultColumns);

  // Pivot mode: group by name, one column group per size
  bool _pivotBySize = false;

  // Keys that vary per size variant (become sub-columns in pivot mode)
  static const _perSizeKeys = {
    'purchasePrice', 'margin', 'salePrice', 'minSalePrice',
    'stock', 'gst', 'discountReceived', 'sellingDiscount',
  };

  // Keys that are the same across size variants (one cell per name row)
  static const _perProductKeys = {'category', 'totalSold', 'saleCount'};

  // Custom row ordering
  bool _reorderMode = false;
  List<Product> _reorderedProducts = []; // empty = use default filtered order
  _SortOption _sortOption = _SortOption.none;

  // Price adjustment
  bool _adjustEnabled = false;
  _AdjustType _adjustType = _AdjustType.margin; // auto-detected after load
  _AdjustMode _adjustMode = _AdjustMode.setTo;
  double _adjustValue = 20.0; // target % (setTo) or delta % (adjustBy)

  // Minimum margin floor
  bool _minMarginEnabled = false;
  double _minMarginValue = 15.0;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _adjustController = TextEditingController(text: '20');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _adjustController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _allProducts = await _firebaseService.getCachedProducts();
      _categories = await _firebaseService.getCategories();
      _autoDetectAdjustType(_allProducts);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _autoDetectAdjustType(List<Product> products) {
    if (products.isEmpty) return;
    final discountCount = products
        .where((p) => (p.sellingDiscount ?? 0) > 0)
        .length;
    final detected = discountCount > products.length / 2
        ? _AdjustType.discount
        : _AdjustType.margin;
    // Only reset adjustValue default to something sensible for the detected type
    final defaultValue = detected == _AdjustType.discount ? 10.0 : 20.0;
    setState(() {
      _adjustType = detected;
      _adjustValue = defaultValue;
      _adjustController.text = defaultValue.toStringAsFixed(1);
    });
  }

  List<Product> get _filteredProducts {
    var products = _allProducts;

    if (_selectedCategory != null) {
      products = products
          .where((p) =>
              p.category.toLowerCase() == _selectedCategory!.toLowerCase())
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      products = products
          .where((p) =>
              p.name.toLowerCase().contains(query) ||
              p.size.toLowerCase().contains(query) ||
              p.category.toLowerCase().contains(query))
          .toList();
    }

    return products;
  }

  List<Product> get _displayProducts =>
      _reorderMode ? _reorderedProducts : _reorderedProducts.isNotEmpty ? _reorderedProducts : _filteredProducts;

  void _toggleReorderMode() {
    setState(() {
      if (!_reorderMode) {
        _reorderedProducts = List.from(_filteredProducts);
      }
      _reorderMode = !_reorderMode;
    });
  }

  void _resetOrder() {
    setState(() {
      _reorderedProducts = [];
      _reorderMode = false;
      _sortOption = _SortOption.none;
    });
  }

  /// Converts pipe/fitting size strings to a numeric value for natural sorting.
  /// Handles: "1/2\"" → 0.5 · "3/4\"" → 0.75 · "1 1/2\"" → 1.5 · "2\"" → 2
  double _parseSizeValue(String size) {
    final s = size.replaceAll('"', '').replaceAll("'", '').trim();
    // Plain number
    final plain = double.tryParse(s);
    if (plain != null) return plain;
    // Mixed: "1 1/2"
    final mixed = RegExp(r'^(\d+)\s+(\d+)/(\d+)$').firstMatch(s);
    if (mixed != null) {
      return int.parse(mixed.group(1)!) +
          int.parse(mixed.group(2)!) / int.parse(mixed.group(3)!);
    }
    // Simple fraction: "1/2"
    final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(s);
    if (frac != null) {
      final den = int.parse(frac.group(2)!);
      return den > 0 ? int.parse(frac.group(1)!) / den : double.maxFinite;
    }
    return double.maxFinite; // unparseable → sort to end
  }

  void _applySort(_SortOption option) {
    if (option == _SortOption.none) {
      _resetOrder();
      return;
    }
    final sorted = List<Product>.from(_filteredProducts)
      ..sort((a, b) {
        final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (n != 0 || option == _SortOption.byName) return n;
        // Same name → sort by size numerically
        final aV = _parseSizeValue(a.size);
        final bV = _parseSizeValue(b.size);
        if (aV != double.maxFinite || bV != double.maxFinite) {
          return aV.compareTo(bV);
        }
        return a.size.toLowerCase().compareTo(b.size.toLowerCase());
      });
    setState(() {
      _sortOption = option;
      _reorderedProducts = sorted;
      _reorderMode = false;
    });
  }

  void _toggleSelectAll() {
    final list = _displayProducts;
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedProductIds = list.map((p) => p.id).toSet();
      } else {
        _selectedProductIds.clear();
      }
    });
  }

  void _toggleProduct(String id, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedProductIds.add(id);
      } else {
        _selectedProductIds.remove(id);
      }
      _selectAll = _selectedProductIds.length == _filteredProducts.length &&
          _filteredProducts.isNotEmpty;
    });
  }

  double _getMargin(Product p) {
    if (p.margin != null) return p.margin!;
    if (p.purchasePrice > 0) {
      return ((p.salePrice - p.purchasePrice) / p.purchasePrice) * 100;
    }
    return 0;
  }

  // Effective values — respect adjustment when enabled

  double _effectiveSellingDiscount(Product p) {
    if (!_adjustEnabled || _adjustType != _AdjustType.discount) {
      return p.sellingDiscount ?? 0;
    }
    if (_adjustMode == _AdjustMode.setTo) return _adjustValue;
    return ((p.sellingDiscount ?? 0) + _adjustValue).clamp(0, 99);
  }

  double _effectiveSalePrice(Product p) {
    double price;
    if (!_adjustEnabled) {
      price = p.salePrice;
    } else if (_adjustType == _AdjustType.discount) {
      final disc = _effectiveSellingDiscount(p);
      price = p.salePrice * (1 - disc / 100);
    } else {
      // Margin mode
      if (p.purchasePrice <= 0) return p.salePrice;
      if (_adjustMode == _AdjustMode.setTo) {
        price = p.purchasePrice * (1 + _adjustValue / 100);
      } else {
        final newMargin = _getMargin(p) + _adjustValue;
        price = p.purchasePrice * (1 + newMargin / 100);
      }
    }
    // Clamp to minimum margin floor
    if (_minMarginEnabled && p.purchasePrice > 0) {
      final floor = p.purchasePrice * (1 + _minMarginValue / 100);
      if (price < floor) price = floor;
    }
    return price;
  }

  /// Price after adjustment but BEFORE the min-margin floor is applied.
  double _rawAdjustedPrice(Product p) {
    if (!_adjustEnabled) return p.salePrice;
    if (_adjustType == _AdjustType.discount) {
      return p.salePrice * (1 - _effectiveSellingDiscount(p) / 100);
    }
    if (p.purchasePrice <= 0) return p.salePrice;
    if (_adjustMode == _AdjustMode.setTo) return p.purchasePrice * (1 + _adjustValue / 100);
    return p.purchasePrice * (1 + (_getMargin(p) + _adjustValue) / 100);
  }

  /// True when the min-margin floor is actively raising this product's price.
  bool _isFloorActive(Product p) =>
      _minMarginEnabled &&
      p.purchasePrice > 0 &&
      (_effectiveSalePrice(p) - p.purchasePrice * (1 + _minMarginValue / 100)).abs() < 0.01 &&
      (_effectiveSalePrice(p) > (_adjustEnabled ? _rawAdjustedPrice(p) : p.salePrice));

  double _effectiveMargin(Product p) {
    if (!_adjustEnabled) return _getMargin(p);
    if (_adjustType == _AdjustType.discount) {
      // Derive margin from the discounted price vs purchase price
      final sale = _effectiveSalePrice(p);
      if (p.purchasePrice <= 0) return _getMargin(p);
      return ((sale - p.purchasePrice) / p.purchasePrice) * 100;
    }
    if (p.purchasePrice <= 0) return _getMargin(p);
    if (_adjustMode == _AdjustMode.setTo) return _adjustValue;
    return _getMargin(p) + _adjustValue;
  }

  double _effectiveMinSalePrice(Product p) => _effectiveSalePrice(p) * 0.90;

  Widget _buildProductTile({
    Key? key,
    required Product product,
    required int index,
    bool showDragHandle = false,
  }) {
    final isSelected = _selectedProductIds.contains(product.id);
    final margin = _effectiveMargin(product);
    final salePrice = _effectiveSalePrice(product);
    final minPrice = _effectiveMinSalePrice(product);
    final priceChanged = _adjustEnabled && (salePrice - product.salePrice).abs() > 0.01;
    final floorActive = _isFloorActive(product); // min-margin floor is clamping this price

    return Container(
      key: key,
      color: isSelected
          ? Colors.blue.shade50
          : (index % 2 == 0 ? Colors.white : Colors.grey.shade50),
      child: InkWell(
        onTap: showDragHandle ? null : () => _toggleProduct(product.id, !isSelected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (val) => _toggleProduct(product.id, val),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    Text(product.category.toUpperCase(),
                        style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(product.size,
                    style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                flex: 2,
                child: Text('₹${product.purchasePrice.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12), textAlign: TextAlign.right),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (priceChanged && !floorActive)
                      Text('₹${product.salePrice.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade400,
                              decoration: TextDecoration.lineThrough)),
                    if (floorActive)
                      Text('₹${_rawAdjustedPrice(product).toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 10, color: Colors.red.shade300,
                              decoration: TextDecoration.lineThrough)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (floorActive)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: Icon(Icons.arrow_upward, size: 10, color: Colors.amber.shade700),
                          ),
                        Text('₹${salePrice.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: floorActive
                                  ? Colors.amber.shade800
                                  : priceChanged
                                      ? Colors.blue.shade700
                                      : Colors.green,
                              fontWeight: (priceChanged || floorActive) ? FontWeight.bold : FontWeight.normal,
                            )),
                      ],
                    ),
                    Text('${margin.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 10,
                            color: floorActive
                                ? Colors.amber.shade700
                                : priceChanged
                                    ? Colors.blue.shade400
                                    : Colors.grey.shade600)),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text('₹${minPrice.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade700,
                        fontWeight: FontWeight.w500),
                    textAlign: TextAlign.right),
              ),
              if (showDragHandle)
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.drag_handle, size: 22, color: Colors.grey.shade400),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildAdjustHint() {
    final v = _adjustValue.toStringAsFixed(1);
    final sign = _adjustValue >= 0 ? '+' : '';
    if (_adjustType == _AdjustType.margin) {
      return _adjustMode == _AdjustMode.setTo
          ? 'Sale price = purchase price × (1 + $v%)'
          : 'Each product\'s margin ${sign}$v% → new sale price calculated';
    } else {
      return _adjustMode == _AdjustMode.setTo
          ? 'Customer price = list price × (1 − $v%)'
          : 'Each product\'s discount ${sign}$v% → customer price updated';
    }
  }

  Future<void> _showColumnSelectionDialog() async {
    // Work on a copy so cancel doesn't apply changes
    final tempSelected = Set<String>.from(_selectedColumns);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Columns to Export'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Select all / none row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${tempSelected.length} of ${_kAvailableColumns.length} selected',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              if (tempSelected.length == _kAvailableColumns.length) {
                                tempSelected.clear();
                              } else {
                                for (final col in _kAvailableColumns) {
                                  tempSelected.add(col['key']!);
                                }
                              }
                            });
                          },
                          child: Text(
                            tempSelected.length == _kAvailableColumns.length
                                ? 'Deselect All'
                                : 'Select All',
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    ..._kAvailableColumns.map((col) {
                      final key = col['key']!;
                      final label = col['label']!;
                      final isChecked = tempSelected.contains(key);
                      return CheckboxListTile(
                        value: isChecked,
                        title: Text(label),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              tempSelected.add(key);
                            } else {
                              tempSelected.remove(key);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: tempSelected.isEmpty
                      ? null
                      : () {
                          setState(() => _selectedColumns = Set.from(tempSelected));
                          Navigator.pop(context);
                        },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static const _colWidths = <String, double>{
    'name': 30, 'size': 15, 'category': 18,
    'purchasePrice': 18, 'margin': 14, 'salePrice': 16,
    'minSalePrice': 20, 'stock': 12, 'gst': 12,
    'discountReceived': 20, 'sellingDiscount': 20,
    'totalSold': 14, 'saleCount': 14,
  };

  CellValue _cellValueFor(String key, Product p) {
    final margin = _effectiveMargin(p);
    final salePrice = _effectiveSalePrice(p);
    final minSale = _effectiveMinSalePrice(p);
    switch (key) {
      case 'name':           return TextCellValue(p.name);
      case 'size':           return TextCellValue(p.size);
      case 'category':       return TextCellValue(p.category);
      case 'purchasePrice':  return DoubleCellValue(p.purchasePrice);
      case 'margin':         return TextCellValue('${margin.toStringAsFixed(2)}%');
      case 'salePrice':      return DoubleCellValue(double.parse(salePrice.toStringAsFixed(2)));
      case 'minSalePrice':   return DoubleCellValue(double.parse(minSale.toStringAsFixed(2)));
      case 'stock':          return IntCellValue(p.stock);
      case 'gst':            return p.gst != null ? TextCellValue('${p.gst!.toStringAsFixed(1)}%') : TextCellValue('-');
      case 'discountReceived': return p.discountReceived != null ? TextCellValue('${p.discountReceived!.toStringAsFixed(1)}%') : TextCellValue('-');
      case 'sellingDiscount':
        final disc = _effectiveSellingDiscount(p);
        return disc > 0 ? TextCellValue('${disc.toStringAsFixed(1)}%') : TextCellValue('-');
      case 'totalSold':      return IntCellValue(p.totalSold);
      case 'saleCount':      return IntCellValue(p.saleCount);
      default:               return TextCellValue('');
    }
  }

  bool _isNumericKey(String key) =>
      key != 'name' && key != 'size' && key != 'category' &&
      key != 'margin' && key != 'gst' && key != 'discountReceived' &&
      key != 'sellingDiscount';

  // ── flat export ───────────────────────────────────────────────────────────

  void _writeFlatSheet(Sheet sheet, List<Product> products, CellStyle headerStyle) {
    final orderedColumns = _kAvailableColumns
        .where((c) => _selectedColumns.contains(c['key']))
        .toList();

    for (int col = 0; col < orderedColumns.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(orderedColumns[col]['label']!);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(col, _colWidths[orderedColumns[col]['key']] ?? 18);
    }

    for (int i = 0; i < products.length; i++) {
      final product = products[i];
      final rowIndex = i + 1;
      final rowBg = i % 2 == 0
          ? ExcelColor.fromHexString('#F5F5F5')
          : ExcelColor.fromHexString('#FFFFFF');
      final numStyle = CellStyle(
        backgroundColorHex: rowBg,
        numberFormat: NumFormat.defaultNumeric,
        horizontalAlign: HorizontalAlign.Right,
      );
      final rightStyle = CellStyle(backgroundColorHex: rowBg, horizontalAlign: HorizontalAlign.Right);
      final baseStyle = CellStyle(backgroundColorHex: rowBg);

      for (int col = 0; col < orderedColumns.length; col++) {
        final key = orderedColumns[col]['key']!;
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex));
        cell.value = _cellValueFor(key, product);
        cell.cellStyle = _isNumericKey(key) ? numStyle : (key == 'margin' || key == 'gst' || key == 'discountReceived' || key == 'sellingDiscount' ? rightStyle : baseStyle);
      }
    }

    _writeSummary(sheet, products.length, products.length + 2);
  }

  // ── pivot export ──────────────────────────────────────────────────────────

  void _writePivotSheet(Sheet sheet, List<Product> products, CellStyle headerStyle) {
    final orderedColumns = _kAvailableColumns
        .where((c) => _selectedColumns.contains(c['key']))
        .toList();

    final perProductCols = orderedColumns.where((c) => _perProductKeys.contains(c['key'])).toList();
    final perSizeCols    = orderedColumns.where((c) => _perSizeKeys.contains(c['key'])).toList();

    // Collect unique sizes in first-appearance order
    final sizes = <String>[];
    for (final p in products) {
      if (!sizes.contains(p.size)) sizes.add(p.size);
    }

    final int sizeBlockStart = 1 + perProductCols.length;
    final int sizeBlockWidth = perSizeCols.isEmpty ? 1 : perSizeCols.length;

    final fieldHeaderStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1E88E5'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    // Row 0: "Product Name" merged over 2 rows
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
    );
    final nameHdr = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    nameHdr.value = TextCellValue('Product Name');
    nameHdr.cellStyle = headerStyle;
    sheet.setColumnWidth(0, 30);

    // Per-product columns: merged over 2 rows
    for (int i = 0; i < perProductCols.length; i++) {
      final col = 1 + i;
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1),
      );
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(perProductCols[i]['label']!);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(col, _colWidths[perProductCols[i]['key']] ?? 18);
    }

    // Size column groups: row 0 = size label (merged), row 1 = field labels
    for (int s = 0; s < sizes.length; s++) {
      final startCol = sizeBlockStart + s * sizeBlockWidth;
      final endCol   = startCol + sizeBlockWidth - 1;

      if (sizeBlockWidth > 1) {
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: 0),
          CellIndex.indexByColumnRow(columnIndex: endCol,   rowIndex: 0),
        );
      }
      final sizeCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: startCol, rowIndex: 0));
      sizeCell.value = TextCellValue(sizes[s]);
      sizeCell.cellStyle = headerStyle;

      for (int f = 0; f < perSizeCols.length; f++) {
        final col = startCol + f;
        final fieldCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1));
        fieldCell.value = TextCellValue(perSizeCols[f]['label']!);
        fieldCell.cellStyle = fieldHeaderStyle;
        sheet.setColumnWidth(col, _colWidths[perSizeCols[f]['key']] ?? 16);
      }
    }

    // Group products by name (preserve first-appearance order)
    final Map<String, List<Product>> byName = {};
    for (final p in products) {
      byName.putIfAbsent(p.name, () => []).add(p);
    }
    final nameOrder = byName.keys.toList();

    // Data rows start at row 2
    for (int i = 0; i < nameOrder.length; i++) {
      final name = nameOrder[i];
      final variants = byName[name]!;
      final rowIndex = i + 2;
      final rowBg = i % 2 == 0
          ? ExcelColor.fromHexString('#F5F5F5')
          : ExcelColor.fromHexString('#FFFFFF');
      final numStyle   = CellStyle(backgroundColorHex: rowBg, numberFormat: NumFormat.defaultNumeric, horizontalAlign: HorizontalAlign.Right);
      final rightStyle = CellStyle(backgroundColorHex: rowBg, horizontalAlign: HorizontalAlign.Right);
      final baseStyle  = CellStyle(backgroundColorHex: rowBg);

      void setCell(int col, CellValue value, [CellStyle? style]) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex));
        cell.value = value;
        cell.cellStyle = style ?? baseStyle;
      }

      // Product name
      setCell(0, TextCellValue(name));

      // Per-product fields (aggregate totals where applicable, else from first variant)
      final first = variants.first;
      for (int f = 0; f < perProductCols.length; f++) {
        final key = perProductCols[f]['key']!;
        final col = 1 + f;
        if (key == 'totalSold') {
          setCell(col, IntCellValue(variants.fold(0, (s, p) => s + p.totalSold)), numStyle);
        } else if (key == 'saleCount') {
          setCell(col, IntCellValue(variants.fold(0, (s, p) => s + p.saleCount)), numStyle);
        } else {
          setCell(col, _cellValueFor(key, first), baseStyle);
        }
      }

      // Per-size columns
      for (int s = 0; s < sizes.length; s++) {
        final startCol = sizeBlockStart + s * sizeBlockWidth;
        Product? variant;
        try { variant = variants.firstWhere((p) => p.size == sizes[s]); } catch (_) {}

        for (int f = 0; f < perSizeCols.length; f++) {
          final key = perSizeCols[f]['key']!;
          final col = startCol + f;
          if (variant == null) {
            setCell(col, TextCellValue('-'), rightStyle);
          } else {
            final val = _cellValueFor(key, variant);
            setCell(col, val, _isNumericKey(key) ? numStyle : rightStyle);
          }
        }
      }
    }

    _writeSummary(sheet, products.length, nameOrder.length + 3);
  }

  // ── shared summary row ────────────────────────────────────────────────────

  void _writeSummary(Sheet sheet, int productCount, int rowIndex) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex));
    cell.value = TextCellValue(
      'Total Products: $productCount   |   Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
    );
    cell.cellStyle = CellStyle(bold: true, italic: true, fontColorHex: ExcelColor.fromHexString('#555555'));
  }

  // ── main export entry point ───────────────────────────────────────────────

  Future<void> _exportToExcel() async {
    if (_selectedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product')),
      );
      return;
    }

    // Respect custom row order if the user has rearranged
    final sourceList = _reorderedProducts.isNotEmpty ? _reorderedProducts : _allProducts;
    final selectedProducts = sourceList
        .where((p) => _selectedProductIds.contains(p.id))
        .toList();

    // Pivot mode requires at least one per-size column selected
    if (_pivotBySize) {
      final hasPerSizeCols = _selectedColumns.any(_perSizeKeys.contains);
      if (!hasPerSizeCols) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one per-size column (e.g. Sale Price) to use pivot mode')),
        );
        return;
      }
    }

    setState(() => _isExporting = true);

    try {
      final excel = Excel.createExcel();
      final sheet = excel['Products'];
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1565C0'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      if (_pivotBySize) {
        _writePivotSheet(sheet, selectedProducts, headerStyle);
      } else {
        _writeFlatSheet(sheet, selectedProducts, headerStyle);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to encode Excel file');

      final fileName =
          'products_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

      if (kIsWeb) {
        downloadExcelOnWeb(bytes, fileName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel file downloaded'), backgroundColor: Colors.green),
          );
        }
      } else {
        Directory? dir;
        if (Platform.isAndroid) {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) dir = await getApplicationDocumentsDirectory();
        } else {
          dir = await getApplicationDocumentsDirectory();
        }
        final filePath = '${dir.path}/$fileName';
        await File(filePath).writeAsBytes(bytes);
        if (mounted) _showSaveSuccessDialog(filePath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showSaveSuccessDialog(String filePath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Export Successful'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Excel file saved to:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                filePath,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayList = _displayProducts;     // what's actually shown in the list
    final selectedCount = _selectedProductIds.length;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Export to Excel'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Controls panel
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search bar
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name, size or category...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                            _selectAll =
                                _selectedProductIds.length ==
                                    _filteredProducts.length &&
                                _filteredProducts.isNotEmpty;
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      // Category chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              label: const Text('All'),
                              selected: _selectedCategory == null,
                              onSelected: (_) {
                                setState(() => _selectedCategory = null);
                              },
                            ),
                            const SizedBox(width: 8),
                            ..._categories.map((cat) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(cat.toUpperCase()),
                                    selected: _selectedCategory == cat,
                                    onSelected: (_) {
                                      setState(() {
                                        _selectedCategory =
                                            _selectedCategory == cat
                                                ? null
                                                : cat;
                                      });
                                    },
                                  ),
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Sort row
                      Row(
                        children: [
                          Text('Sort:',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600],
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          _SortChip(
                            label: 'Default',
                            icon: Icons.restore,
                            selected: _sortOption == _SortOption.none,
                            onTap: () => _applySort(_SortOption.none),
                          ),
                          const SizedBox(width: 6),
                          _SortChip(
                            label: 'Name A→Z',
                            icon: Icons.sort_by_alpha,
                            selected: _sortOption == _SortOption.byName,
                            onTap: () => _applySort(_SortOption.byName),
                          ),
                          const SizedBox(width: 6),
                          _SortChip(
                            label: 'Name + Size',
                            icon: Icons.straighten,
                            selected: _sortOption == _SortOption.byNameSize,
                            onTap: () => _applySort(_SortOption.byNameSize),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Selection row
                      Row(
                        children: [
                          Text(
                            '$selectedCount of ${displayList.length} selected',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: _showColumnSelectionDialog,
                            icon: const Icon(Icons.view_column_outlined, size: 18),
                            label: Text('Columns (${_selectedColumns.length})'),
                          ),
                          const SizedBox(width: 8),
                          // Sort / reorder toggle
                          OutlinedButton.icon(
                            onPressed: displayList.isEmpty && !_reorderMode ? null : _toggleReorderMode,
                            style: _reorderMode
                                ? OutlinedButton.styleFrom(
                                    foregroundColor: Colors.purple.shade700,
                                    side: BorderSide(color: Colors.purple.shade400),
                                    backgroundColor: Colors.purple.shade50,
                                  )
                                : _reorderedProducts.isNotEmpty
                                    ? OutlinedButton.styleFrom(
                                        foregroundColor: Colors.purple.shade500,
                                        side: BorderSide(color: Colors.purple.shade200),
                                      )
                                    : null,
                            icon: Icon(
                              _reorderMode ? Icons.check_rounded : Icons.swap_vert,
                              size: 18,
                            ),
                            label: Text(_reorderMode
                                ? 'Done'
                                : _reorderedProducts.isNotEmpty
                                    ? 'Reordered'
                                    : 'Sort'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: displayList.isEmpty ? null : _toggleSelectAll,
                            icon: Icon(
                              _selectAll ? Icons.deselect : Icons.select_all,
                              size: 18,
                            ),
                            label: Text(_selectAll ? 'Deselect All' : 'Select All'),
                          ),
                        ],
                      ),
                      // "Reset order" row shown when custom order is active
                      if (_reorderedProducts.isNotEmpty && !_reorderMode) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.swap_vert, size: 14, color: Colors.purple.shade400),
                            const SizedBox(width: 4),
                            Text('Custom order active — export will use this order',
                                style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                            const Spacer(),
                            GestureDetector(
                              onTap: _resetOrder,
                              child: Text('Reset',
                                  style: TextStyle(fontSize: 11, color: Colors.purple.shade700,
                                      fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),

                      // Pivot toggle
                      InkWell(
                        onTap: () => setState(() => _pivotBySize = !_pivotBySize),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _pivotBySize ? Colors.blue.shade50 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _pivotBySize ? Colors.blue.shade300 : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.pivot_table_chart,
                                size: 18,
                                color: _pivotBySize ? Colors.blue.shade700 : Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Group by Size (Pivot)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _pivotBySize ? Colors.blue.shade700 : Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      _pivotBySize
                                          ? 'One row per product name — sizes become column groups'
                                          : 'Each product variant on its own row (default)',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _pivotBySize,
                                onChanged: (v) => setState(() => _pivotBySize = v),
                                activeThumbColor: Colors.blue.shade700,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Price adjustment card
                      Container(
                        decoration: BoxDecoration(
                          color: _adjustEnabled ? Colors.orange.shade50 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _adjustEnabled ? Colors.orange.shade300 : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header row with toggle
                            InkWell(
                              onTap: () => setState(() => _adjustEnabled = !_adjustEnabled),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.percent, size: 18,
                                      color: _adjustEnabled ? Colors.orange.shade700 : Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Price Adjustment',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: _adjustEnabled ? Colors.orange.shade700 : Colors.black87,
                                            ),
                                          ),
                                          Text(
                                            _adjustEnabled
                                                ? (_adjustType == _AdjustType.margin
                                                    ? (_adjustMode == _AdjustMode.setTo
                                                        ? 'Margin set to ${_adjustValue.toStringAsFixed(1)}%'
                                                        : 'Margin ${_adjustValue >= 0 ? '+' : ''}${_adjustValue.toStringAsFixed(1)}% on each product')
                                                    : (_adjustMode == _AdjustMode.setTo
                                                        ? 'Discount set to ${_adjustValue.toStringAsFixed(1)}%'
                                                        : 'Discount ${_adjustValue >= 0 ? '+' : ''}${_adjustValue.toStringAsFixed(1)}% on each product'))
                                                : 'Override prices with custom margin or discount',
                                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _adjustEnabled,
                                      onChanged: (v) => setState(() => _adjustEnabled = v),
                                      activeThumbColor: Colors.orange.shade700,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            if (_adjustEnabled) ...[
                              Divider(height: 1, color: Colors.orange.shade200),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Type selector: Margin vs Discount ──
                                    Row(
                                      children: [
                                        Text('Type:', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _SegmentButton(
                                            leftLabel: 'Margin',
                                            rightLabel: 'Discount',
                                            leftSelected: _adjustType == _AdjustType.margin,
                                            color: Colors.orange.shade700,
                                            onLeft: () {
                                              setState(() {
                                                _adjustType = _AdjustType.margin;
                                                _adjustValue = 20.0;
                                                _adjustController.text = '20.0';
                                              });
                                            },
                                            onRight: () {
                                              setState(() {
                                                _adjustType = _AdjustType.discount;
                                                _adjustValue = 10.0;
                                                _adjustController.text = '10.0';
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Auto-detect chip
                                        GestureDetector(
                                          onTap: () => _autoDetectAdjustType(_allProducts),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.orange.shade300),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.auto_fix_high, size: 12, color: Colors.orange.shade700),
                                                const SizedBox(width: 3),
                                                Text('Auto', style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // ── Set-to vs Adjust-by ──
                                    _SegmentButton(
                                      leftLabel: _adjustType == _AdjustType.margin ? 'Set margin to' : 'Set discount to',
                                      rightLabel: 'Adjust by ±',
                                      leftSelected: _adjustMode == _AdjustMode.setTo,
                                      color: Colors.orange.shade700,
                                      onLeft:  () => setState(() => _adjustMode = _AdjustMode.setTo),
                                      onRight: () => setState(() => _adjustMode = _AdjustMode.adjustBy),
                                    ),
                                    const SizedBox(height: 10),

                                    // ── Value input ──
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        _MarginStepButton(
                                          icon: Icons.remove,
                                          onTap: () => setState(() {
                                            _adjustValue -= 1;
                                            _adjustController.text = _adjustValue.toStringAsFixed(1);
                                          }),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 90,
                                          child: TextField(
                                            controller: _adjustController,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                            textAlign: TextAlign.center,
                                            decoration: InputDecoration(
                                              suffixText: '%',
                                              filled: true,
                                              fillColor: Colors.white,
                                              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(color: Colors.orange.shade300),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(color: Colors.orange.shade600),
                                              ),
                                            ),
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                            onChanged: (val) {
                                              final parsed = double.tryParse(val);
                                              if (parsed != null) setState(() => _adjustValue = parsed);
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _MarginStepButton(
                                          icon: Icons.add,
                                          onTap: () => setState(() {
                                            _adjustValue += 1;
                                            _adjustController.text = _adjustValue.toStringAsFixed(1);
                                          }),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),

                                    // ── Description hint ──
                                    Center(
                                      child: Text(
                                        _buildAdjustHint(),
                                        style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Minimum margin floor card
                      Container(
                        decoration: BoxDecoration(
                          color: _minMarginEnabled ? Colors.amber.shade50 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _minMarginEnabled ? Colors.amber.shade400 : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () => setState(() => _minMarginEnabled = !_minMarginEnabled),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.shield_outlined, size: 18,
                                        color: _minMarginEnabled ? Colors.amber.shade800 : Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Minimum Sale Margin',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: _minMarginEnabled ? Colors.amber.shade800 : Colors.black87,
                                              )),
                                          Text(
                                            _minMarginEnabled
                                                ? 'Price floor: cost × (1 + ${_minMarginValue.toStringAsFixed(1)}%) — no product sells below this'
                                                : 'Set a floor so no price ever drops below minimum margin',
                                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _minMarginEnabled,
                                      onChanged: (v) => setState(() => _minMarginEnabled = v),
                                      activeThumbColor: Colors.amber.shade700,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_minMarginEnabled) ...[
                              Divider(height: 1, color: Colors.amber.shade200),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        _MarginStepButton(
                                          icon: Icons.remove,
                                          onTap: () => setState(() => _minMarginValue = (_minMarginValue - 1).clamp(0, 100)),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 90,
                                          child: TextField(
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            textAlign: TextAlign.center,
                                            controller: TextEditingController(
                                                text: _minMarginValue.toStringAsFixed(1))
                                              ..selection = TextSelection.collapsed(
                                                  offset: _minMarginValue.toStringAsFixed(1).length),
                                            decoration: InputDecoration(
                                              suffixText: '%',
                                              filled: true,
                                              fillColor: Colors.white,
                                              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(color: Colors.amber.shade400),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(color: Colors.amber.shade600),
                                              ),
                                            ),
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                            onChanged: (val) {
                                              final parsed = double.tryParse(val);
                                              if (parsed != null) setState(() => _minMarginValue = parsed.clamp(0, 100));
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _MarginStepButton(
                                          icon: Icons.add,
                                          onTap: () => setState(() => _minMarginValue = (_minMarginValue + 1).clamp(0, 100)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Builder(builder: (context) {
                                      // Count products where min-margin floor kicks in
                                      final clamped = _displayProducts.where(_isFloorActive).length;
                                      if (clamped == 0) {
                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade600),
                                            const SizedBox(width: 4),
                                            Text('All products are above the floor',
                                                style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                                          ],
                                        );
                                      }
                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.arrow_upward, size: 14, color: Colors.amber.shade700),
                                          const SizedBox(width: 4),
                                          Text('$clamped product${clamped > 1 ? 's' : ''} raised to meet floor',
                                              style: TextStyle(fontSize: 11, color: Colors.amber.shade800,
                                                  fontWeight: FontWeight.w600)),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Column headers preview
                Container(
                  color: Colors.blue.shade700,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: const [
                      SizedBox(width: 48), // checkbox space
                      Expanded(
                          flex: 3,
                          child: Text('Name',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12))),
                      Expanded(
                          flex: 2,
                          child: Text('Size',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12))),
                      Expanded(
                          flex: 2,
                          child: Text('Purchase ₹',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                              textAlign: TextAlign.right)),
                      Expanded(
                          flex: 2,
                          child: Text('Sale ₹',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                              textAlign: TextAlign.right)),
                      Expanded(
                          flex: 2,
                          child: Text('Min ₹ (-10%)',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                              textAlign: TextAlign.right)),
                    ],
                  ),
                ),

                // Reorder mode banner
                if (_reorderMode)
                  Container(
                    color: Colors.purple.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.drag_indicator, size: 16, color: Colors.purple.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Drag rows to reorder. Tap "Done" when finished.',
                            style: TextStyle(fontSize: 12, color: Colors.purple.shade700),
                          ),
                        ),
                        TextButton(
                          onPressed: _resetOrder,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.purple.shade600,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Reset', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),

                // Product list
                Expanded(
                  child: displayList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text('No products found',
                                  style: TextStyle(color: Colors.grey.shade500)),
                            ],
                          ),
                        )
                      : _reorderMode
                          ? ReorderableListView.builder(
                              itemCount: _reorderedProducts.length,
                              onReorder: (oldIndex, newIndex) {
                                setState(() {
                                  if (newIndex > oldIndex) newIndex--;
                                  final item = _reorderedProducts.removeAt(oldIndex);
                                  _reorderedProducts.insert(newIndex, item);
                                });
                              },
                              proxyDecorator: (child, index, animation) => Material(
                                elevation: 6,
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                child: child,
                              ),
                              itemBuilder: (context, index) {
                                final product = _reorderedProducts[index];
                                return _buildProductTile(
                                  key: ValueKey(product.id),
                                  product: product,
                                  index: index,
                                  showDragHandle: true,
                                );
                              },
                            )
                          : ListView.builder(
                              itemCount: displayList.length,
                              itemBuilder: (context, index) {
                                return _buildProductTile(
                                  product: displayList[index],
                                  index: index,
                                );
                              },
                            ),
                ),

                // Export button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isExporting ? null : _exportToExcel,
                        icon: _isExporting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.table_chart),
                        label: Text(
                          _isExporting
                              ? 'Exporting...'
                              : 'Export ${selectedCount > 0 ? "$selectedCount Products" : ""} to Excel',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.indigo.shade600 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.indigo.shade600 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13,
                color: selected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? Colors.white : Colors.grey.shade700,
                )),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final bool leftSelected;
  final Color color;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _SegmentButton({
    required this.leftLabel,
    required this.rightLabel,
    required this.leftSelected,
    required this.color,
    required this.onLeft,
    required this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: leftSelected ? color : Colors.white,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                border: Border.all(color: color.withOpacity(0.6)),
              ),
              child: Text(
                leftLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: leftSelected ? Colors.white : color,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onRight,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: !leftSelected ? color : Colors.white,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                border: Border.all(color: color.withOpacity(0.6)),
              ),
              child: Text(
                rightLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: !leftSelected ? Colors.white : color,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MarginStepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MarginStepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Icon(icon, size: 20, color: Colors.orange.shade700),
      ),
    );
  }
}
