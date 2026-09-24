import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../../services/firebase_service.dart';
import '../../utils/product_field_parsing.dart';

/// One editable column in the grid — mirrors the safe-to-edit product
/// fields used by the Excel import flow (see kImportableProductKeys), so
/// both bulk-edit paths agree on what's editable.
class _ColumnDef {
  final String key;
  final String label;
  final double width;
  final bool numeric;
  final bool isInt;
  final bool percent; // optional percentage field (blank = clear)
  final bool required; // must be non-empty / a valid number

  const _ColumnDef({
    required this.key,
    required this.label,
    required this.width,
    this.numeric = false,
    this.isInt = false,
    this.percent = false,
    this.required = false,
  });
}

const List<_ColumnDef> _columns = [
  _ColumnDef(key: 'name', label: 'Product Name', width: 170, required: true),
  _ColumnDef(key: 'size', label: 'Size', width: 90, required: true),
  _ColumnDef(key: 'category', label: 'Category', width: 110, required: true),
  _ColumnDef(key: 'purchasePrice', label: 'Purchase ₹', width: 100, numeric: true, required: true),
  _ColumnDef(key: 'salePrice', label: 'Sale ₹', width: 100, numeric: true, required: true),
  _ColumnDef(key: 'wholesalePrice', label: 'Wholesale ₹', width: 108, numeric: true, required: true),
  _ColumnDef(key: 'stock', label: 'Stock', width: 80, numeric: true, isInt: true, required: true),
  _ColumnDef(key: 'gst', label: 'GST %', width: 80, numeric: true, percent: true),
  _ColumnDef(key: 'discountReceived', label: 'Disc. Recv %', width: 112, numeric: true, percent: true),
  _ColumnDef(key: 'sellingDiscount', label: 'Sell Disc %', width: 112, numeric: true, percent: true),
];

const double _kStatusColWidth = 32;

class BulkEditTableScreen extends StatefulWidget {
  const BulkEditTableScreen({super.key});

  @override
  State<BulkEditTableScreen> createState() => _BulkEditTableScreenState();
}

class _BulkEditTableScreenState extends State<BulkEditTableScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _searchController = TextEditingController();

  List<Product> _allProducts = [];
  List<String> _categories = [];
  String? _selectedCategory;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;

  // productId -> column key -> controller. Created lazily as rows are built
  // (ListView.builder only builds visible rows), kept for the screen's
  // lifetime so scrolling away and back doesn't lose in-progress edits.
  final Map<String, Map<String, TextEditingController>> _controllers = {};

  // productId -> column key -> parsed value, only present when it differs
  // from the product's current value and parsed without error.
  final Map<String, Map<String, dynamic>> _pendingValues = {};

  // productId -> column key -> error message, for a cell that doesn't
  // parse. A row with any error is excluded from Save entirely, even if
  // its other cells are validly edited — no partial-row writes.
  final Map<String, Map<String, String>> _cellErrors = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final byField in _controllers.values) {
      for (final c in byField.values) {
        c.dispose();
      }
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _allProducts = await _firebaseService.getCachedProducts();
      _categories = await _firebaseService.getCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Product> get _filteredProducts {
    var products = _allProducts;
    if (_selectedCategory != null) {
      products = products
          .where((p) => p.category.toLowerCase() == _selectedCategory!.toLowerCase())
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      products = products
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.size.toLowerCase().contains(q) ||
              p.category.toLowerCase().contains(q))
          .toList();
    }
    final sorted = List<Product>.from(products)
      ..sort((a, b) {
        final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return n != 0 ? n : a.size.toLowerCase().compareTo(b.size.toLowerCase());
      });
    return sorted;
  }

  // ── cell text <-> product value ─────────────────────────────────────────

  String _originalText(Product p, _ColumnDef col) {
    switch (col.key) {
      case 'name':
        return p.name;
      case 'size':
        return p.size;
      case 'category':
        return p.category;
      case 'purchasePrice':
        return p.purchasePrice.toStringAsFixed(2);
      case 'salePrice':
        return p.salePrice.toStringAsFixed(2);
      case 'wholesalePrice':
        return p.effectiveWholesalePrice.toStringAsFixed(2);
      case 'stock':
        return p.stock.toString();
      case 'gst':
        return p.gst != null ? p.gst!.toStringAsFixed(1) : '';
      case 'discountReceived':
        return p.discountReceived != null ? p.discountReceived!.toStringAsFixed(1) : '';
      case 'sellingDiscount':
        return p.sellingDiscount != null ? p.sellingDiscount!.toStringAsFixed(1) : '';
      default:
        return '';
    }
  }

  TextEditingController _controllerFor(Product p, _ColumnDef col) {
    final byField = _controllers.putIfAbsent(p.id, () => {});
    return byField.putIfAbsent(col.key, () => TextEditingController(text: _originalText(p, col)));
  }

  bool _valuesEqual(dynamic original, dynamic parsed) {
    if (original is double && parsed is double) return (original - parsed).abs() < 0.005;
    return original == parsed;
  }

  void _onCellChanged(Product p, _ColumnDef col, String raw) {
    final t = raw.trim();
    dynamic parsed;
    String? error;

    if (!col.numeric) {
      if (col.required && t.isEmpty) error = '${col.label} required';
      parsed = t;
    } else if (col.isInt) {
      final v = parseStock(t);
      if (v == null) error = 'Invalid number';
      parsed = v ?? 0;
    } else if (col.percent) {
      final r = parseOptionalPercent(t);
      if (!r.ok) error = 'Invalid %';
      parsed = r.value;
    } else {
      final v = parseRequiredDouble(t);
      if (v == null) error = 'Invalid number';
      parsed = v ?? 0.0;
    }

    setState(() {
      final errMap = _cellErrors.putIfAbsent(p.id, () => {});
      final pendMap = _pendingValues.putIfAbsent(p.id, () => {});

      if (error != null) {
        errMap[col.key] = error;
        pendMap.remove(col.key);
      } else {
        errMap.remove(col.key);
        dynamic original;
        switch (col.key) {
          case 'name':
            original = p.name;
            break;
          case 'size':
            original = p.size;
            break;
          case 'category':
            original = p.category;
            break;
          case 'purchasePrice':
            original = p.purchasePrice;
            break;
          case 'salePrice':
            original = p.salePrice;
            break;
          case 'wholesalePrice':
            original = p.effectiveWholesalePrice;
            break;
          case 'stock':
            original = p.stock;
            break;
          case 'gst':
            original = p.gst;
            break;
          case 'discountReceived':
            original = p.discountReceived;
            break;
          case 'sellingDiscount':
            original = p.sellingDiscount;
            break;
        }
        if (!_valuesEqual(original, parsed)) {
          pendMap[col.key] = parsed;
        } else {
          pendMap.remove(col.key);
        }
      }

      if (errMap.isEmpty) _cellErrors.remove(p.id);
      if (pendMap.isEmpty) _pendingValues.remove(p.id);
    });
  }

  // ── save ───────────────────────────────────────────────────────────────

  List<String> get _readyToSaveIds =>
      _pendingValues.keys.where((id) => !_cellErrors.containsKey(id)).toList();

  Future<void> _saveChanges() async {
    final readyIds = _readyToSaveIds;
    if (readyIds.isEmpty) return;

    final blockedCount = _cellErrors.keys.where((id) => _pendingValues.containsKey(id)).length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save changes?'),
        content: Text(
          'This will update ${readyIds.length} product${readyIds.length == 1 ? '' : 's'} '
          'in your inventory right away.'
          '${blockedCount > 0 ? '\n\n$blockedCount row${blockedCount == 1 ? '' : 's'} with errors will be skipped — fix the red cells and save again.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Save ${readyIds.length}'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final updates = <Product>[];
      for (final id in readyIds) {
        final product = _allProducts.firstWhere((p) => p.id == id);
        updates.add(mergeProductFields(product, _pendingValues[id]!));
      }

      const chunkSize = 400;
      for (int i = 0; i < updates.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, updates.length);
        await _firebaseService.batchUpdateProducts(updates.sublist(i, end));
      }
      _firebaseService.invalidateCache();

      setState(() {
        for (final updated in updates) {
          _pendingValues.remove(updated.id);
          final idx = _allProducts.indexWhere((p) => p.id == updated.id);
          if (idx != -1) _allProducts[idx] = updated;
          final byField = _controllers[updated.id];
          if (byField != null) {
            for (final col in _columns) {
              byField[col.key]?.text = _originalText(updated, col);
            }
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved ${updates.length} product${updates.length == 1 ? '' : 's'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _discardChanges() async {
    if (_pendingValues.isEmpty && _cellErrors.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text(
          'This will undo edits to ${{..._pendingValues.keys, ..._cellErrors.keys}.length} product row(s).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      final touchedIds = {..._pendingValues.keys, ..._cellErrors.keys};
      for (final id in touchedIds) {
        final product = _allProducts.firstWhere((p) => p.id == id, orElse: () => _allProducts.first);
        final byField = _controllers[id];
        if (byField != null) {
          for (final col in _columns) {
            byField[col.key]?.text = _originalText(product, col);
          }
        }
      }
      _pendingValues.clear();
      _cellErrors.clear();
    });
  }

  Future<bool> _confirmLeave() async {
    if (_pendingValues.isEmpty && _cellErrors.isEmpty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('You have unsaved edits. Leave without saving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dirtyCount = _pendingValues.length;

    return PopScope(
      canPop: _pendingValues.isEmpty && _cellErrors.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _confirmLeave();
        if (shouldLeave && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          title: const Text('Edit as Table'),
          backgroundColor: Colors.white,
          elevation: 0,
          actions: [
            if (dirtyCount > 0 || _cellErrors.isNotEmpty)
              TextButton(
                onPressed: _isSaving ? null : _discardChanges,
                child: const Text('Discard'),
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildFilters(),
                  Expanded(child: _buildTable()),
                  _buildSaveBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
                const SizedBox(width: 8),
                ..._categories.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(cat.toUpperCase()),
                        selected: _selectedCategory == cat,
                        onSelected: (_) => setState(
                            () => _selectedCategory = _selectedCategory == cat ? null : cat),
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap any cell to edit — swipe sideways to see more columns. Changes save only when you tap Save below.',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final products = _filteredProducts;
    final totalWidth = _kStatusColWidth + _columns.fold(0.0, (s, c) => s + c.width);

    if (products.isEmpty) {
      return Center(
        child: Text(
          _allProducts.isEmpty ? 'No products yet' : 'No products match this filter',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          children: [
            _buildHeaderRow(),
            Expanded(
              child: ListView.builder(
                itemCount: products.length,
                itemExtent: 56,
                itemBuilder: (context, index) => _buildRow(products[index], index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      color: Colors.blue.shade700,
      child: Row(
        children: [
          const SizedBox(width: _kStatusColWidth),
          for (final col in _columns)
            Container(
              width: col.width,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text(
                col.label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(Product p, int index) {
    final hasError = _cellErrors.containsKey(p.id);
    final isDirty = _pendingValues.containsKey(p.id);
    final rowColor = hasError
        ? Colors.red.shade50
        : isDirty
            ? Colors.amber.shade50
            : (index.isEven ? Colors.white : Colors.grey.shade50);

    return Container(
      color: rowColor,
      child: Row(
        children: [
          SizedBox(
            width: _kStatusColWidth,
            child: hasError
                ? const Icon(Icons.error_outline, size: 16, color: Colors.red)
                : isDirty
                    ? const Icon(Icons.edit, size: 14, color: Colors.amber)
                    : const SizedBox.shrink(),
          ),
          for (final col in _columns) _buildCell(p, col),
        ],
      ),
    );
  }

  Widget _buildCell(Product p, _ColumnDef col) {
    final controller = _controllerFor(p, col);
    final error = _cellErrors[p.id]?[col.key];
    final changed = _pendingValues[p.id]?.containsKey(col.key) ?? false;

    return Container(
      width: col.width,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType:
            col.numeric ? TextInputType.numberWithOptions(decimal: !col.isInt) : TextInputType.text,
        textAlign: col.numeric ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 12,
          fontWeight: changed ? FontWeight.bold : FontWeight.normal,
          color: changed ? Colors.blue.shade800 : Colors.black87,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          hintText: col.percent ? '—' : null,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: error != null ? Colors.red : Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: error != null ? Colors.red : Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: error != null ? Colors.red : Colors.blue, width: 1.5),
          ),
        ),
        onChanged: (v) => _onCellChanged(p, col, v),
      ),
    );
  }

  Widget _buildSaveBar() {
    final readyCount = _readyToSaveIds.length;
    final errorCount = _cellErrors.length;

    if (readyCount == 0 && errorCount == 0) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2)),
          ],
        ),
        child: Row(
          children: [
            if (errorCount > 0) ...[
              Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
              const SizedBox(width: 4),
              Text('$errorCount error${errorCount == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton.icon(
                onPressed: (readyCount == 0 || _isSaving) ? null : _saveChanges,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving
                    ? 'Saving...'
                    : readyCount == 0
                        ? 'No valid changes'
                        : 'Save $readyCount change${readyCount == 1 ? '' : 's'}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
