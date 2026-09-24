import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';

import '../../models/product_model.dart';
import '../../services/firebase_service.dart';
import '../../utils/product_excel_columns.dart';
import '../../utils/product_field_parsing.dart';

enum _RowStatus { changed, unchanged, notFound, error }

class _FieldDiff {
  final String key;
  final String label;
  final String oldText;
  final String newText;

  const _FieldDiff({
    required this.key,
    required this.label,
    required this.oldText,
    required this.newText,
  });
}

class _ImportRow {
  final int rowNumber; // 1-based, matches the row as it appears in Excel
  final String? id;
  final Product? original;
  final Product? merged;
  final List<_FieldDiff> diffs;
  final _RowStatus status;
  final String? message;

  const _ImportRow({
    required this.rowNumber,
    required this.status,
    this.id,
    this.original,
    this.merged,
    this.diffs = const [],
    this.message,
  });

  String get displayName =>
      original?.name ?? merged?.name ?? 'Row $rowNumber';
  String get displaySize => original?.size ?? merged?.size ?? '';
}

class ExcelImportScreen extends StatefulWidget {
  const ExcelImportScreen({super.key});

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  bool _isParsing = false;
  bool _isApplying = false;
  String? _fileName;
  String? _parseError;
  List<_ImportRow> _rows = [];
  Set<int> _selectedRowNumbers = {};

  List<_ImportRow> get _changedRows =>
      _rows.where((r) => r.status == _RowStatus.changed).toList();
  List<_ImportRow> get _unchangedRows =>
      _rows.where((r) => r.status == _RowStatus.unchanged).toList();
  List<_ImportRow> get _notFoundRows =>
      _rows.where((r) => r.status == _RowStatus.notFound).toList();
  List<_ImportRow> get _errorRows =>
      _rows.where((r) => r.status == _RowStatus.error).toList();

  // ── file selection & parsing ──────────────────────────────────────────

  Future<void> _pickAndParseFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    Uint8List? bytes = picked.bytes;
    if (bytes == null && !kIsWeb && picked.path != null) {
      bytes = await File(picked.path!).readAsBytes();
    }
    if (bytes == null) {
      setState(() => _parseError = 'Could not read the selected file.');
      return;
    }

    setState(() {
      _isParsing = true;
      _parseError = null;
      _rows = [];
      _selectedRowNumbers = {};
      _fileName = picked.name;
    });

    try {
      final parsed = await _parseWorkbook(bytes);
      setState(() {
        _rows = parsed;
        _selectedRowNumbers = parsed
            .where((r) => r.status == _RowStatus.changed)
            .map((r) => r.rowNumber)
            .toSet();
      });
    } catch (e) {
      setState(() => _parseError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  Future<List<_ImportRow>> _parseWorkbook(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw Exception('No sheets found in this file.');
    }
    final sheet = excel.tables['Products'] ?? excel.tables.values.first;
    final rows = sheet.rows;
    if (rows.isEmpty) {
      throw Exception('That sheet is empty.');
    }

    String cellText(List<Data?> row, int idx) {
      if (idx < 0 || idx >= row.length) return '';
      return row[idx]?.value?.toString().trim() ?? '';
    }

    final header = rows[0];
    final colKeyByIndex = <int, String>{};
    int? idColIndex;
    for (int c = 0; c < header.length; c++) {
      final text = cellText(header, c);
      if (text.isEmpty) continue;
      final lower = text.toLowerCase();
      if (lower == kProductIdColumnLabel.toLowerCase() ||
          lower.startsWith('product id')) {
        idColIndex = c;
        continue;
      }
      for (final col in kProductExcelColumns) {
        if (col['label']!.toLowerCase() == lower) {
          colKeyByIndex[c] = col['key']!;
          break;
        }
      }
    }

    if (idColIndex == null) {
      throw Exception(
        'This sheet is missing the "$kProductIdColumnLabel" column, so '
        'edits can\'t be matched back to products. Export a fresh copy '
        'from this app (with "Group by Size" off) and edit that file '
        'instead of a brand-new sheet.',
      );
    }
    final resolvedIdCol = idColIndex;

    if (colKeyByIndex.isEmpty) {
      throw Exception(
        'No recognizable product columns were found in the header row.',
      );
    }

    final products = await _firebaseService.getCachedProducts();
    final byId = {for (final p in products) p.id: p};

    final parsedRows = <_ImportRow>[];
    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      final id = cellText(row, resolvedIdCol);
      final anyContent = id.isNotEmpty ||
          colKeyByIndex.keys.any((c) => cellText(row, c).isNotEmpty);
      if (!anyContent) continue; // trailing blank row

      final rowNumber = r + 1;

      if (id.isEmpty) {
        parsedRows.add(_ImportRow(
          rowNumber: rowNumber,
          status: _RowStatus.error,
          message: 'Missing Product ID — row skipped',
        ));
        continue;
      }

      final product = byId[id];
      if (product == null) {
        parsedRows.add(_ImportRow(
          rowNumber: rowNumber,
          status: _RowStatus.notFound,
          id: id,
          message:
              'No product matches this ID (maybe deleted since export) — skipped',
        ));
        continue;
      }

      final fields = <String, dynamic>{};
      String? error;
      for (final entry in colKeyByIndex.entries) {
        final key = entry.value;
        if (!kImportableProductKeys.contains(key)) {
          continue; // derived/stat columns (margin, minSalePrice, totalSold, saleCount) are read-only
        }
        final raw = cellText(row, entry.key);
        switch (key) {
          case 'name':
          case 'size':
          case 'category':
            if (raw.isEmpty) {
              error = '${_labelFor(key)} can\'t be empty';
            }
            fields[key] = raw;
            break;
          case 'purchasePrice':
          case 'salePrice':
          case 'wholesalePrice':
            final v = parseRequiredDouble(raw);
            if (v == null) error = 'Invalid ${_labelFor(key)}: "$raw"';
            fields[key] = v ?? 0.0;
            break;
          case 'stock':
            final v = parseStock(raw);
            if (v == null) error = 'Invalid Stock: "$raw"';
            fields[key] = v ?? 0;
            break;
          case 'gst':
          case 'discountReceived':
          case 'sellingDiscount':
            final parsed = parseOptionalPercent(raw);
            if (!parsed.ok) error = 'Invalid ${_labelFor(key)}: "$raw"';
            fields[key] = parsed.value;
            break;
        }
        if (error != null) break;
      }

      if (error != null) {
        parsedRows.add(_ImportRow(
          rowNumber: rowNumber,
          status: _RowStatus.error,
          id: id,
          original: product,
          message: error,
        ));
        continue;
      }

      final merged = mergeProductFields(product, fields);
      final diffs = _computeDiffs(product, merged, fields.keys);
      parsedRows.add(_ImportRow(
        rowNumber: rowNumber,
        id: id,
        original: product,
        merged: merged,
        diffs: diffs,
        status: diffs.isEmpty ? _RowStatus.unchanged : _RowStatus.changed,
      ));
    }

    return parsedRows;
  }

  // ── parsing helpers ───────────────────────────────────────────────────

  String _labelFor(String key) =>
      kProductExcelColumns.firstWhere((c) => c['key'] == key)['label']!;

  List<_FieldDiff> _computeDiffs(
      Product original, Product merged, Iterable<String> touchedKeys) {
    final diffs = <_FieldDiff>[];
    for (final key in touchedKeys) {
      if (!kImportableProductKeys.contains(key)) continue;
      final oldText = _displayValue(key, original);
      final newText = _displayValue(key, merged);
      if (oldText != newText) {
        diffs.add(_FieldDiff(
          key: key,
          label: _labelFor(key),
          oldText: oldText,
          newText: newText,
        ));
      }
    }
    return diffs;
  }

  String _displayValue(String key, Product p) {
    switch (key) {
      case 'name':
        return p.name;
      case 'size':
        return p.size;
      case 'category':
        return p.category;
      case 'purchasePrice':
        return '₹${p.purchasePrice.toStringAsFixed(2)}';
      case 'salePrice':
        return '₹${p.salePrice.toStringAsFixed(2)}';
      case 'wholesalePrice':
        return '₹${p.effectiveWholesalePrice.toStringAsFixed(2)}';
      case 'stock':
        return p.stock.toString();
      case 'gst':
        return p.gst != null ? '${p.gst!.toStringAsFixed(1)}%' : '—';
      case 'discountReceived':
        return p.discountReceived != null
            ? '${p.discountReceived!.toStringAsFixed(1)}%'
            : '—';
      case 'sellingDiscount':
        return p.sellingDiscount != null
            ? '${p.sellingDiscount!.toStringAsFixed(1)}%'
            : '—';
      default:
        return '';
    }
  }

  // ── apply ──────────────────────────────────────────────────────────────

  Future<void> _applyChanges() async {
    final toApply = _changedRows
        .where((r) => _selectedRowNumbers.contains(r.rowNumber))
        .toList();
    if (toApply.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply bulk update?'),
        content: Text(
          'This will update ${toApply.length} product${toApply.length == 1 ? '' : 's'} '
          'in your inventory right away. Make sure you\'ve reviewed the '
          'changes below.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Apply ${toApply.length} update${toApply.length == 1 ? '' : 's'}'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isApplying = true);
    try {
      final updated = toApply.map((r) => r.merged!).toList();
      const chunkSize = 400; // stay well under Firestore's 500-write batch cap
      for (int i = 0; i < updated.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, updated.length);
        await _firebaseService.batchUpdateProducts(updated.sublist(i, end));
      }
      _firebaseService.invalidateCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Updated ${updated.length} product${updated.length == 1 ? '' : 's'}'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  void _toggleRow(int rowNumber, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedRowNumbers.add(rowNumber);
      } else {
        _selectedRowNumbers.remove(rowNumber);
      }
    });
  }

  void _toggleSelectAllChanged() {
    setState(() {
      final allSelected = _changedRows.isNotEmpty &&
          _changedRows.every((r) => _selectedRowNumbers.contains(r.rowNumber));
      if (allSelected) {
        _selectedRowNumbers.removeAll(_changedRows.map((r) => r.rowNumber));
      } else {
        _selectedRowNumbers.addAll(_changedRows.map((r) => r.rowNumber));
      }
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Import from Excel'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _rows.isEmpty && _parseError == null
          ? _buildIntro()
          : _buildReview(),
    );
  }

  Widget _buildIntro() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file_outlined, size: 64, color: Colors.blue.shade300),
            const SizedBox(height: 16),
            const Text(
              'Bulk-edit your products in Excel',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StepLine(number: '1', text: 'Export to Excel (with "Group by Size" off)'),
                  SizedBox(height: 8),
                  _StepLine(number: '2', text: 'Edit it in Excel, or upload it to Google Sheets and edit there'),
                  SizedBox(height: 8),
                  _StepLine(number: '3', text: 'Download it back as .xlsx and pick it below'),
                  SizedBox(height: 8),
                  _StepLine(number: '4', text: "Don't touch the \"Product ID\" column — that's what matches each row back to a product"),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_parseError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_parseError!,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: _isParsing ? null : _pickAndParseFile,
              icon: _isParsing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.folder_open),
              label: Text(_isParsing ? 'Reading file...' : 'Choose Excel File (.xlsx)'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReview() {
    final allChangedSelected = _changedRows.isNotEmpty &&
        _changedRows.every((r) => _selectedRowNumbers.contains(r.rowNumber));
    final selectedCount = _changedRows
        .where((r) => _selectedRowNumbers.contains(r.rowNumber))
        .length;

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.description_outlined, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_fileName ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(
                    onPressed: _isApplying ? null : _pickAndParseFile,
                    child: const Text('Change file'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CountChip(
                      label: '${_changedRows.length} changed',
                      color: Colors.blue,
                      icon: Icons.edit_outlined),
                  _CountChip(
                      label: '${_unchangedRows.length} unchanged',
                      color: Colors.grey,
                      icon: Icons.check_circle_outline),
                  if (_notFoundRows.isNotEmpty)
                    _CountChip(
                        label: '${_notFoundRows.length} not found',
                        color: Colors.orange,
                        icon: Icons.help_outline),
                  if (_errorRows.isNotEmpty)
                    _CountChip(
                        label: '${_errorRows.length} error${_errorRows.length == 1 ? '' : 's'}',
                        color: Colors.red,
                        icon: Icons.error_outline),
                ],
              ),
            ],
          ),
        ),
        if (_changedRows.isNotEmpty)
          Container(
            width: double.infinity,
            color: Colors.blue.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Checkbox(
                  value: allChangedSelected,
                  onChanged: (_) => _toggleSelectAllChanged(),
                ),
                const Text('Select all changed', style: TextStyle(fontSize: 13)),
                const Spacer(),
                Text('$selectedCount selected',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        Expanded(
          child: _rows.isEmpty
              ? const Center(child: Text('No data rows found in that sheet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  itemBuilder: (context, index) => _buildRowCard(_rows[index]),
                ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2)),
              ],
            ),
            child: FilledButton.icon(
              onPressed: (selectedCount == 0 || _isApplying) ? null : _applyChanges,
              icon: _isApplying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_isApplying
                  ? 'Applying...'
                  : selectedCount == 0
                      ? 'Select changes to apply'
                      : 'Apply $selectedCount update${selectedCount == 1 ? '' : 's'}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRowCard(_ImportRow row) {
    final Color accent;
    switch (row.status) {
      case _RowStatus.changed:
        accent = Colors.blue;
        break;
      case _RowStatus.unchanged:
        accent = Colors.grey;
        break;
      case _RowStatus.notFound:
        accent = Colors.orange;
        break;
      case _RowStatus.error:
        accent = Colors.red;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: accent.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (row.status == _RowStatus.changed)
              Checkbox(
                value: _selectedRowNumbers.contains(row.rowNumber),
                onChanged: (v) => _toggleRow(row.rowNumber, v),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 10, right: 4),
                child: Icon(
                  row.status == _RowStatus.unchanged
                      ? Icons.check_circle_outline
                      : row.status == _RowStatus.notFound
                          ? Icons.help_outline
                          : Icons.error_outline,
                  size: 20,
                  color: accent,
                ),
              ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.displaySize.isNotEmpty
                              ? '${row.displayName} (${row.displaySize})'
                              : row.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      Text('Row ${row.rowNumber}',
                          style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    ],
                  ),
                  if (row.message != null) ...[
                    const SizedBox(height: 4),
                    Text(row.message!, style: TextStyle(fontSize: 12, color: accent)),
                  ],
                  if (row.diffs.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: row.diffs.map((d) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${d.label}: ${d.oldText} → ${d.newText}',
                            style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  final String number;
  final String text;
  const _StepLine({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
            shape: BoxShape.circle,
          ),
          child: Text(number,
              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: Colors.blue.shade900)),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final MaterialColor color;
  final IconData icon;
  const _CountChip({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.shade700),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color.shade700, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
