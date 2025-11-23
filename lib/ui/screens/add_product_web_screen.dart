import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product_model.dart';
import '../../services/firebase_service.dart';
import '../../services/settings_service.dart';

class AddProductWebScreen extends StatefulWidget {
  final Product? product;

  const AddProductWebScreen({super.key, this.product});

  @override
  State<AddProductWebScreen> createState() => _AddProductWebScreenState();
}

class _AddProductWebScreenState extends State<AddProductWebScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService();
  final SettingsService _settingsService = SettingsService();

  final _nameController = TextEditingController();
  final _sizeController = TextEditingController();
  final _billPriceController = TextEditingController();
  final _discountReceivedController = TextEditingController();
  final _sellingDiscountController = TextEditingController();
  final _marginController = TextEditingController(text: '20'); // Default 20% margin
  final _purchasePriceController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _stockController = TextEditingController();
  final _gstController = TextEditingController(text: '18'); // Default 18%

  File? _selectedImage;
  bool _isLoading = false;

  // Category management - Hardware as default
  String? _selectedCategory;
  List<String> _categories = ['Hardware', 'PPR', 'CPVC', 'PVC', 'Paints'];

  // Discount and Margin management
  bool _hasDiscount = false;

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();

    if (isEditing) {
      // When editing, populate all values including pricing details
      _nameController.text = widget.product!.name;
      _sizeController.text = widget.product!.size;
      _stockController.text = widget.product!.stock.toString();

      // Set category - default to 'CPVC' if not set or empty
      _selectedCategory =
      (widget.product!.category.isEmpty ||
          widget.product!.category == 'Uncategorized')
          ? 'CPVC'
          : widget.product!.category;

      // Populate GST
      if (widget.product!.gst != null) {
        _gstController.text = widget.product!.gst.toString();
      }

      // Populate discount and margin fields if available
      if (widget.product!.discountReceived != null && widget.product!.discountReceived! > 0) {
        _discountReceivedController.text = widget.product!.discountReceived.toString();
        _hasDiscount = true; // Enable discount mode if discount exists
      }
      if (widget.product!.sellingDiscount != null && widget.product!.sellingDiscount! > 0) {
        _sellingDiscountController.text = widget.product!.sellingDiscount.toString();
        _hasDiscount = true; // Enable discount mode if discount exists
      }
      if (widget.product!.margin != null && widget.product!.margin! > 0) {
        _marginController.text = widget.product!.margin.toString();
      }

      // Populate prices - these will be editable
      _purchasePriceController.text = widget.product!.purchasePrice.toString();
      _salePriceController.text = widget.product!.salePrice.toString();

      // Calculate bill price from purchase price if GST is available
      // This is a reverse calculation for editing
      if (widget.product!.gst != null && widget.product!.gst! > 0) {
        final gstRate = widget.product!.gst! / 100;
        if (_hasDiscount && widget.product!.discountReceived != null) {
          // Reverse: Bill = (Purchase / (1 + GST)) / (1 - Discount%)
          final basePrice = widget.product!.purchasePrice / (1 + gstRate);
          final billPrice = basePrice / (1 - (widget.product!.discountReceived! / 100));
          _billPriceController.text = billPrice.toStringAsFixed(2);
        } else {
          // Simple reverse: Bill = Purchase / (1 + GST)
          final billPrice = widget.product!.purchasePrice / (1 + gstRate);
          _billPriceController.text = billPrice.toStringAsFixed(2);
        }
      } else {
        // If no GST, bill price = purchase price
        _billPriceController.text = widget.product!.purchasePrice.toString();
      }

      // Setup listeners for editing mode too
      _billPriceController.addListener(_calculatePrices);
      _discountReceivedController.addListener(_calculatePrices);
      _sellingDiscountController.addListener(_calculatePrices);
      _marginController.addListener(_calculatePrices);
      _gstController.addListener(_calculatePrices);
    } else {
      // Setup auto-calculation listeners
      _billPriceController.addListener(_calculatePrices);
      _discountReceivedController.addListener(_calculatePrices);
      _sellingDiscountController.addListener(_calculatePrices);
      _marginController.addListener(_calculatePrices);
      _gstController.addListener(_calculatePrices);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _firebaseService.getCategories();

      // Load default category if adding a new product (not editing)
      String? defaultCategory;
      if (!isEditing) {
        defaultCategory = await _settingsService.getDefaultCategory();
      }

      setState(() {
        _categories = categories;
        // Ensure CPVC is in the list
        if (!_categories.contains('CPVC')) {
          _categories.insert(2, 'CPVC');
        }

        // Set default category only when adding new product
        if (!isEditing && defaultCategory != null && categories.contains(defaultCategory)) {
          _selectedCategory = defaultCategory;
        }
      });
    } catch (e) {
      // Use default categories if loading fails
      setState(() {
        _categories = ['Hardware', 'PPR', 'CPVC', 'PVC', 'Paints'];
      });
    }
  }

  void _calculatePrices() {
    final billPrice = double.tryParse(_billPriceController.text) ?? 0.0;
    final gstRate =
        (double.tryParse(_gstController.text) ?? 18.0) /
            100; // Convert % to decimal

    if (billPrice <= 0) {
      _purchasePriceController.text = '';
      _salePriceController.text = '';
      return;
    }

    if (_hasDiscount) {
      // DISCOUNT MODE: Use discount percentages
      final discountReceived =
          double.tryParse(_discountReceivedController.text) ?? 0.0;
      final sellingDiscount =
          double.tryParse(_sellingDiscountController.text) ?? 0.0;

      // Calculate Purchase Price: (Bill Price - Discount Received%) + GST
      final priceAfterDiscount =
          billPrice - (billPrice * discountReceived / 100);
      final purchasePrice = priceAfterDiscount + (priceAfterDiscount * gstRate);
      _purchasePriceController.text = purchasePrice.toStringAsFixed(2);

      // Calculate Sale Price: (Bill Price - Selling Discount%) + GST
      final priceAfterSellingDiscount =
          billPrice - (billPrice * sellingDiscount / 100);
      final salePrice =
          priceAfterSellingDiscount + (priceAfterSellingDiscount * gstRate);
      _salePriceController.text = salePrice.toStringAsFixed(2);
    } else {
      // MARGIN MODE: Use margin percentage
      final margin = double.tryParse(_marginController.text) ?? 20.0;

      // Purchase Price = Bill Price + GST
      final purchasePrice = billPrice + (billPrice * gstRate);
      _purchasePriceController.text = purchasePrice.toStringAsFixed(2);

      // Sale Price = Purchase Price + Margin%
      final salePrice = purchasePrice + (purchasePrice * margin / 100);
      _salePriceController.text = salePrice.toStringAsFixed(2);
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final TextEditingController categoryController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add New Category'),
        content: TextField(
          controller: categoryController,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            hintText: 'e.g., Adhesives',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (categoryController.text.trim().isNotEmpty) {
                Navigator.pop(context, categoryController.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await _firebaseService.addCategory(result);
        setState(() {
          _categories.add(result);
          _selectedCategory = result;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Category "$result" added successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error adding category: $e')));
        }
      }
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    // Set default category to Hardware if none selected
    final categoryToSave = _selectedCategory ?? 'CPVC';

    setState(() => _isLoading = true);

    try {
      final gstValue = double.tryParse(_gstController.text);
      final discountReceivedValue = double.tryParse(_discountReceivedController.text);
      final sellingDiscountValue = double.tryParse(_sellingDiscountController.text);
      final marginValue = double.tryParse(_marginController.text);

      final product = Product(
        id: isEditing ? widget.product!.id : '',
        name: _nameController.text.trim(),
        size: _sizeController.text.trim(),
        purchasePrice: double.parse(_purchasePriceController.text),
        salePrice: double.parse(_salePriceController.text),
        stock: int.tryParse(_stockController.text) ?? 0,
        imageBase64: isEditing ? widget.product?.imageBase64 : '',
        createdAt: isEditing ? widget.product!.createdAt : DateTime.now(),
        category: categoryToSave,
        gst: gstValue,
        discountReceived: discountReceivedValue,
        sellingDiscount: sellingDiscountValue,
        margin: marginValue,
        totalSold: isEditing ? widget.product!.totalSold : 0,
        saleCount: isEditing ? widget.product!.saleCount : 0,
        salesFrequency: isEditing ? widget.product!.salesFrequency : 0.0,
      );

      if (isEditing) {
        await _firebaseService.updateProduct(product);
      } else {
        await _firebaseService.addProduct(product);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? 'Product updated successfully'
                  : 'Product added successfully',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving product: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Product' : 'Add Product'),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Product Name
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      prefixIcon: Icon(Icons.inventory_2),
                    ),
                    validator: (value) =>
                    value?.isEmpty ?? true ? 'Required' : null,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _sizeController,
                    decoration: const InputDecoration(
                      labelText: 'Size',
                      prefixIcon: Icon(Icons.straighten),
                    ),
                    validator: (value) =>
                    value?.isEmpty ?? true ? 'Required' : null,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _stockController,
                    decoration: const InputDecoration(
                      labelText: 'Stock Quantity (Optional)',
                      prefixIcon: Icon(Icons.inventory),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),
            // Category Selection
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          decoration: InputDecoration(
                            labelText: 'Category',
                            prefixIcon: const Icon(Icons.category),
                            border: const OutlineInputBorder(),
                            helperText: 'Default: CPVC',
                            helperStyle: TextStyle(color: Colors.grey.shade600),
                          ),
                          items: _categories.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedCategory = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        onPressed: _showAddCategoryDialog,
                        icon: const Icon(Icons.add),
                        tooltip: 'Add New Category',
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(flex: 3, child: Container()),
              ],
            ),

            SizedBox(height: 24),
            // Pricing Section Header

            // ========================================
            // BOTH MODES: Same UI for adding and editing
            // ========================================
            // Discount/Margin Toggle Checkbox
            CheckboxListTile(
              value: _hasDiscount,
              onChanged: (value) {
                setState(() {
                  _hasDiscount = value ?? false;
                  // Recalculate prices when mode changes
                  _calculatePrices();
                });
              },
              title: const Text('Product has discount?'),
              subtitle: Text(
                _hasDiscount
                    ? 'Using discount percentages for pricing'
                    : 'Using margin percentage for pricing',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 16),

            // Bill Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pricing Details',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _billPriceController,
                        decoration: InputDecoration(
                          labelText: 'Bill Price (Base Price)',
                          prefixIcon: const Icon(Icons.receipt_long),
                          prefixText: '₹ ',
                          helperText: 'Enter the base price without GST',
                          helperStyle: TextStyle(
                            color: isEditing ? Colors.orange.shade700 : null,
                            fontWeight: isEditing ? FontWeight.w500 : null,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        validator: (value) {
                          if (value?.isEmpty ?? true) return 'Required';
                          if (double.tryParse(value!) == null)
                            return 'Invalid number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // GST Field (Optional)
                      TextFormField(
                        controller: _gstController,
                        decoration: InputDecoration(
                          labelText: 'GST (%)',
                          prefixIcon: const Icon(Icons.receipt),
                          suffixText: '%',
                          helperText: 'GST percentage (default: 18%)',
                          filled: true,
                          fillColor: Colors.blue.shade50,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        validator: (value) {
                          if (value?.isEmpty ?? true) return null; // Optional
                          final number = double.tryParse(value!);
                          if (number == null) return 'Invalid number';
                          if (number < 0 || number > 100)
                            return 'Must be 0-100%';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Conditional: Discount Received OR show nothing (margin on right side)
                      if (_hasDiscount) ...[
                        // Discount Received
                        TextFormField(
                          controller: _discountReceivedController,
                          decoration: const InputDecoration(
                            labelText: 'Discount Received (%)',
                            prefixIcon: Icon(Icons.local_offer),
                            suffixText: '%',
                            helperText: 'Discount received from supplier',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          validator: (value) {
                            if (value?.isEmpty ?? true) return null; // Optional
                            final number = double.tryParse(value!);
                            if (number == null) return 'Invalid number';
                            if (number < 0 || number > 100)
                              return 'Must be 0-100%';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Purchase Price (Auto-calculated)
                      TextFormField(
                        controller: _purchasePriceController,
                        decoration: InputDecoration(
                          labelText: _hasDiscount
                              ? 'Purchase Price (Auto-calculated)'
                              : 'Purchase Price (Bill Price + GST)',
                          prefixIcon: const Icon(Icons.shopping_cart),
                          prefixText: '₹ ',
                          helperText: _hasDiscount
                              ? 'Bill Price - Discount + GST'
                              : 'Bill Price + GST',
                          filled: true,
                          fillColor: Colors.grey.shade100,
                        ),
                        readOnly: true,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Selling Section
                      Text(
                        'Selling Details',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),

                      // Conditional: Selling Discount OR Margin
                      if (_hasDiscount) ...[
                        // Selling Discount
                        TextFormField(
                          controller: _sellingDiscountController,
                          decoration: const InputDecoration(
                            labelText: 'Selling Discount (%)',
                            prefixIcon: Icon(Icons.discount),
                            suffixText: '%',
                            helperText: 'Discount offered to customers',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          validator: (value) {
                            if (value?.isEmpty ?? true) return null; // Optional
                            final number = double.tryParse(value!);
                            if (number == null) return 'Invalid number';
                            if (number < 0 || number > 100)
                              return 'Must be 0-100%';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        // Margin Percentage
                        TextFormField(
                          controller: _marginController,
                          decoration: InputDecoration(
                            labelText: 'Profit Margin (%)',
                            prefixIcon: const Icon(Icons.trending_up),
                            suffixText: '%',
                            helperText: 'Profit margin on purchase price (default: 20%)',
                            filled: true,
                            fillColor: Colors.green.shade50,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          validator: (value) {
                            if (value?.isEmpty ?? true) return null; // Optional
                            final number = double.tryParse(value!);
                            if (number == null) return 'Invalid number';
                            if (number < 0) return 'Cannot be negative';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Sale Price (Auto-calculated)
                      TextFormField(
                        controller: _salePriceController,
                        decoration: InputDecoration(
                          labelText: 'Sale Price (Auto-calculated)',
                          prefixIcon: const Icon(Icons.currency_rupee),
                          prefixText: '₹ ',
                          helperText: _hasDiscount
                              ? 'Bill Price - Selling Discount + GST'
                              : 'Purchase Price + Margin%',
                          filled: true,
                          fillColor: Colors.grey.shade100,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),

            // Stock (Common for both modes)

            // Save Button
            FilledButton.icon(
              onPressed: _isLoading ? null : _saveProduct,
              icon: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.save),
              label: Text(
                _isLoading
                    ? 'Saving...'
                    : isEditing
                    ? 'Update Product'
                    : 'Save Product',
              ),
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sizeController.dispose();
    _billPriceController.dispose();
    _discountReceivedController.dispose();
    _sellingDiscountController.dispose();
    _marginController.dispose();
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    _stockController.dispose();
    _gstController.dispose();
    super.dispose();
  }
}