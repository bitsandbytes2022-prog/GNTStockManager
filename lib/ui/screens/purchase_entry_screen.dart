import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/party_model.dart';
import '../../models/product_model.dart';
import '../../services/firebase_service.dart';
import '../../services/ledger_service.dart';
import '../widgets/product_picker_dialog.dart';
import 'ledger_screen.dart';

/// A line on the purchase being entered. [product] is null for an item not
/// yet in the products list — it's created when the purchase is saved.
class _Line {
  Product? product;
  final String name;
  final String size;
  final String category;
  final double salePrice;
  int quantity;
  double rate;

  _Line.existing(Product this.product,
      {required this.quantity, required this.rate})
      : name = product.name,
        size = product.size,
        category = product.category,
        salePrice = product.salePrice;

  _Line.newProduct({
    required this.name,
    required this.size,
    required this.category,
    required this.salePrice,
    required this.quantity,
    required this.rate,
  });

  bool get isNew => product == null;
  double get total => quantity * rate;
}

/// Records a purchase from a supplier. Only the amount is required; items
/// are optional, and any listed are added to stock (new ones are created in
/// the products list).
class PurchaseEntryScreen extends StatefulWidget {
  final Party party;

  const PurchaseEntryScreen({super.key, required this.party});

  @override
  State<PurchaseEntryScreen> createState() => _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends State<PurchaseEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final List<_Line> _lines = [];
  DateTime _date = DateTime.now();
  bool _saving = false;

  /// Once the user types an amount themselves, stop overwriting it with the
  /// items total (the bill may include freight, rounding, etc.).
  bool _amountEdited = false;

  double get _itemsTotal => _lines.fold(0, (sum, l) => sum + l.total);

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _syncAmount() {
    if (_amountEdited) return;
    _amountController.text =
        _lines.isEmpty ? '' : _itemsTotal.toStringAsFixed(2);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day,
        _date.hour, _date.minute, _date.second));
  }

  Future<void> _addExistingItem() async {
    final product = await showProductPickerDialog(context,
        title: 'Add item from your products');
    if (product == null || !mounted) return;
    final result = await showDialog<_QtyRate>(
      context: context,
      builder: (_) => _QtyRateDialog(
        title: [product.name, if (product.size.isNotEmpty) product.size]
            .join(' · '),
        initialRate: product.purchasePrice,
      ),
    );
    if (result == null) return;
    setState(() {
      _lines.add(_Line.existing(product,
          quantity: result.quantity, rate: result.rate));
      _syncAmount();
    });
  }

  Future<void> _addNewItem() async {
    final line = await showDialog<_Line>(
      context: context,
      builder: (_) => const _NewItemDialog(),
    );
    if (line == null || !mounted) return;

    // Already in the products list? Use that product instead of making a
    // duplicate.
    final products = await FirebaseService().getCachedProducts();
    final match = products.where((p) =>
        p.name.trim().toLowerCase() == line.name.toLowerCase() &&
        p.size.trim().toLowerCase() == line.size.toLowerCase());
    if (match.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '"${line.name}" is already in your products — using it')));
      setState(() {
        _lines.add(_Line.existing(match.first,
            quantity: line.quantity, rate: line.rate));
        _syncAmount();
      });
      return;
    }
    setState(() {
      _lines.add(line);
      _syncAmount();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final firebase = FirebaseService();
      final items = <PurchaseItem>[];
      for (final line in _lines) {
        if (line.isNew) {
          final draft = Product(
            id: '',
            name: line.name,
            size: line.size,
            purchasePrice: line.rate,
            salePrice: line.salePrice,
            stock: 0, // The purchase below adds the quantity.
            imageBase64: null,
            createdAt: DateTime.now(),
            category: line.category,
            gst: 18,
            margin: line.rate > 0
                ? (line.salePrice - line.rate) / line.rate * 100
                : null,
          );
          final id = await firebase.addProduct(draft);
          // Remember it, so a retry after a later failure doesn't add it twice.
          line.product = draft.copyWith(id: id);
        }
        items.add(PurchaseItem(
          productId: line.product!.id,
          name: line.name,
          size: line.size,
          quantity: line.quantity,
          rate: line.rate,
        ));
      }

      await LedgerService().addBill(
        party: widget.party,
        amount: double.parse(_amountController.text),
        date: _date,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        items: items,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Purchase of ${formatLedgerAmount(double.parse(_amountController.text))} saved')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error saving purchase: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Purchase from ${widget.party.name}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                labelText: 'Bill amount',
                prefixText: '₹ ',
                prefixIcon: const Icon(Icons.receipt_long),
                helperText: _lines.isEmpty
                    ? 'Total of the supplier\'s bill'
                    : 'Items total: ${formatLedgerAmount(_itemsTotal)}'
                        '${_amountEdited ? ' · edited by you' : ''}',
              ),
              onChanged: (_) => _amountEdited = true,
              validator: (v) {
                final value = double.tryParse(v ?? '');
                if (value == null || value <= 0) return 'Enter the bill amount';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Short note (optional)',
                hintText: 'e.g. Bill no. 245, CPVC fittings',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(DateFormat('d MMM yyyy').format(_date)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('Items (optional)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Added to stock',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < _lines.length; i++)
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                      [_lines[i].name, if (_lines[i].size.isNotEmpty) _lines[i].size]
                          .join(' · ')),
                  subtitle: Text([
                    '${_lines[i].quantity} × ${formatLedgerAmount(_lines[i].rate)}',
                    if (_lines[i].isNew) 'NEW — will be added to products',
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatLedgerAmount(_lines[i].total),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Remove',
                        onPressed: () => setState(() {
                          _lines.removeAt(i);
                          _syncAmount();
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _addExistingItem,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Add from products'),
                ),
                OutlinedButton.icon(
                  onPressed: _addNewItem,
                  icon: const Icon(Icons.add),
                  label: const Text('New item'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Saving...' : 'Save Purchase'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyRate {
  final int quantity;
  final double rate;
  _QtyRate(this.quantity, this.rate);
}

/// Quantity + purchase rate for an existing product.
class _QtyRateDialog extends StatefulWidget {
  final String title;
  final double initialRate;

  const _QtyRateDialog({required this.title, required this.initialRate});

  @override
  State<_QtyRateDialog> createState() => _QtyRateDialogState();
}

class _QtyRateDialogState extends State<_QtyRateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController();
  late final _rate =
      TextEditingController(text: widget.initialRate.toStringAsFixed(2));

  @override
  void dispose() {
    _qty.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _qtyField(_qty, autofocus: true),
            _rateField(_rate, 'Purchase rate per unit'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context,
                _QtyRate(int.parse(_qty.text), double.parse(_rate.text)));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Details for an item that isn't in the products list yet.
class _NewItemDialog extends StatefulWidget {
  const _NewItemDialog();

  @override
  State<_NewItemDialog> createState() => _NewItemDialogState();
}

class _NewItemDialogState extends State<_NewItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _size = TextEditingController();
  final _qty = TextEditingController();
  final _rate = TextEditingController();
  final _salePrice = TextEditingController();
  late final Future<List<String>> _categories =
      FirebaseService().getCategories();
  String? _category;

  /// Sale price follows rate + 20% until the user types their own.
  bool _salePriceEdited = false;

  @override
  void initState() {
    super.initState();
    _rate.addListener(() {
      if (_salePriceEdited) return;
      final rate = double.tryParse(_rate.text);
      _salePrice.text = rate == null ? '' : (rate * 1.2).toStringAsFixed(2);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _size.dispose();
    _qty.dispose();
    _rate.dispose();
    _salePrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('New item'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Item name'),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Required' : null,
                ),
                FutureBuilder<List<String>>(
                  future: _categories,
                  builder: (context, snapshot) {
                    final categories = snapshot.data ?? const <String>[];
                    return DropdownButtonFormField<String>(
                      value: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: [
                        for (final c in categories)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _category = v),
                      validator: (v) => v == null ? 'Required' : null,
                    );
                  },
                ),
                TextFormField(
                  controller: _size,
                  decoration: const InputDecoration(
                      labelText: 'Size (optional)', hintText: 'e.g. 1 inch'),
                ),
                _qtyField(_qty),
                _rateField(_rate, 'Purchase rate per unit'),
                TextFormField(
                  controller: _salePrice,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Sale price',
                    prefixText: '₹ ',
                    helperText: 'Default: rate + 20%',
                  ),
                  onChanged: (_) => _salePriceEdited = true,
                  validator: (v) {
                    final value = double.tryParse(v ?? '');
                    if (value == null || value <= 0) return 'Enter a price';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _Line.newProduct(
                name: _name.text.trim(),
                size: _size.text.trim(),
                category: _category!,
                salePrice: double.parse(_salePrice.text),
                quantity: int.parse(_qty.text),
                rate: double.parse(_rate.text),
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

Widget _qtyField(TextEditingController controller, {bool autofocus = false}) {
  return TextFormField(
    controller: controller,
    autofocus: autofocus,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: const InputDecoration(labelText: 'Quantity'),
    validator: (v) {
      final value = int.tryParse(v ?? '');
      if (value == null || value <= 0) return 'Enter quantity';
      return null;
    },
  );
}

Widget _rateField(TextEditingController controller, String label) {
  return TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
    ],
    decoration: InputDecoration(labelText: label, prefixText: '₹ '),
    validator: (v) {
      final value = double.tryParse(v ?? '');
      if (value == null || value <= 0) return 'Enter rate';
      return null;
    },
  );
}
