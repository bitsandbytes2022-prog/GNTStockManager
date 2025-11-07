import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product_model.dart';
import '../../services/firebase_service.dart';

class AddProductWebScreen extends StatefulWidget {
  final Product? product;

  const AddProductWebScreen({super.key, this.product});

  @override
  State<AddProductWebScreen> createState() => _AddProductWebScreenState();
}

class _AddProductWebScreenState extends State<AddProductWebScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService();

  final _nameController = TextEditingController();
  final _sizeController = TextEditingController();
  final _billPriceController = TextEditingController();
  final _discountReceivedController = TextEditingController();
  final _sellingDiscountController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _stockController = TextEditingController();
  final _gstController = TextEditingController(text: '18'); // Default 18%

  File? _selectedImage;
  bool _isLoading = false;

  // Category management - Hardware as default
  String? _selectedCategory;
  List<String> _categories = ['Hardware', 'PPR', 'CPVC', 'PVC', 'Paints'];

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();

    if (isEditing) {
      // When editing, populate direct values
      _nameController.text = widget.product!.name;
      _sizeController.text = widget.product!.size;
      _purchasePriceController.text = widget.product!.purchasePrice.toString();
      _salePriceController.text = widget.product!.salePrice.toString();
      _stockController.text = widget.product!.stock.toString();

      // Set category - default to 'Hardware' if not set or empty
      _selectedCategory = (widget.product!.category.isEmpty || widget.product!.category == 'Uncategorized')
          ? 'CPVC'
          : widget.product!.category;

      // If product has GST value, populate it
      if (widget.product!.gst != null) {
        _gstController.text = widget.product!.gst.toString();
      }
    } else {
      // When adding new product, set default category to Hardware
      _selectedCategory = 'CPVC';

      // Setup auto-calculation listeners
      _billPriceController.addListener(_calculatePrices);
      _discountReceivedController.addListener(_calculatePrices);
      _sellingDiscountController.addListener(_calculatePrices);
      _gstController.addListener(_calculatePrices);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _firebaseService.getCategories();
      setState(() {
        _categories = categories;
        // Ensure Hardware is in the list
        if (!_categories.contains('CPVC')) {
          _categories.insert(2, 'CPVC');
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
    final discountReceived = double.tryParse(_discountReceivedController.text) ?? 0.0;
    final sellingDiscount = double.tryParse(_sellingDiscountController.text) ?? 0.0;
    final gstRate = (double.tryParse(_gstController.text) ?? 18.0) / 100; // Convert % to decimal

    // Calculate Purchase Price: (Bill Price - Discount Received%) + GST
    if (billPrice > 0) {
      final priceAfterDiscount = billPrice - (billPrice * discountReceived / 100);
      final purchasePrice = priceAfterDiscount + (priceAfterDiscount * gstRate);
      _purchasePriceController.text = purchasePrice.toStringAsFixed(2);

      // Calculate Sale Price: (Bill Price - Selling Discount%) + GST
      final priceAfterSellingDiscount = billPrice - (billPrice * sellingDiscount / 100);
      final salePrice = priceAfterSellingDiscount + (priceAfterSellingDiscount * gstRate);
      _salePriceController.text = salePrice.toStringAsFixed(2);
    } else {
      _purchasePriceController.text = '';
      _salePriceController.text = '';
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding category: $e')),
          );
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

      final product = Product(
        id: isEditing ? widget.product!.id : '',
        name: _nameController.text.trim(),
        size: _sizeController.text.trim(),
        purchasePrice: double.parse(_purchasePriceController.text),
        salePrice: double.parse(_salePriceController.text),
        stock: int.tryParse(_stockController.text) ?? 0,
        imageBase64: isEditing?widget.product?.imageBase64:'',
        createdAt: isEditing ? widget.product!.createdAt : DateTime.now(),
        category: categoryToSave,
        gst: gstValue,
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
            content: Text(isEditing
                ? 'Product updated successfully'
                : 'Product added successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving product: $e')),
        );
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
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Product Name',
                prefixIcon: Icon(Icons.inventory_2),
              ),
              validator: (value) =>
              value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Size
            TextFormField(
              controller: _sizeController,
              decoration: const InputDecoration(
                labelText: 'Size',
                prefixIcon: Icon(Icons.straighten),
              ),
              validator: (value) =>
              value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Category Selection
            Row(
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
            const SizedBox(height: 24),

            // Pricing Section Header
            Text(
              'Pricing Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // ========================================
            // ADDING MODE: Advanced pricing with auto-calculation
            // ========================================
            if (!isEditing) ...[
              // Bill Price
              TextFormField(
                controller: _billPriceController,
                decoration: const InputDecoration(
                  labelText: 'Bill Price (Base Price)',
                  prefixIcon: Icon(Icons.receipt_long),
                  prefixText: '₹ ',
                  helperText: 'Enter the base price without GST',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid number';
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
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return null; // Optional
                  final number = double.tryParse(value!);
                  if (number == null) return 'Invalid number';
                  if (number < 0 || number > 100) return 'Must be 0-100%';
                  return null;
                },
              ),
              const SizedBox(height: 16),

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
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return null; // Optional
                  final number = double.tryParse(value!);
                  if (number == null) return 'Invalid number';
                  if (number < 0 || number > 100) return 'Must be 0-100%';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Purchase Price (Auto-calculated, Read-only)
              TextFormField(
                controller: _purchasePriceController,
                decoration: InputDecoration(
                  labelText: 'Purchase Price (Auto-calculated)',
                  prefixIcon: const Icon(Icons.shopping_cart),
                  prefixText: '₹ ',
                  helperText: 'Bill Price - Discount + GST',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
                readOnly: false,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(height: 24),

              // Selling Section
              Text(
                'Selling Details',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

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
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return null; // Optional
                  final number = double.tryParse(value!);
                  if (number == null) return 'Invalid number';
                  if (number < 0 || number > 100) return 'Must be 0-100%';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Sale Price (Auto-calculated, Read-only)
              TextFormField(
                controller: _salePriceController,
                decoration: InputDecoration(
                  labelText: 'Sale Price (Auto-calculated)',
                  prefixIcon: const Icon(Icons.currency_rupee),
                  prefixText: '₹ ',
                  helperText: 'Bill Price - Selling Discount + GST',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
                readOnly: false,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ========================================
            // EDITING MODE: Simple direct price input
            // ========================================
            if (isEditing) ...[
              // GST Field (Optional, for editing)
              TextFormField(
                controller: _gstController,
                decoration: InputDecoration(
                  labelText: 'GST (%) - Optional',
                  prefixIcon: const Icon(Icons.receipt),
                  suffixText: '%',
                  helperText: 'GST percentage applied',
                  filled: true,
                  fillColor: Colors.blue.shade50,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return null; // Optional
                  final number = double.tryParse(value!);
                  if (number == null) return 'Invalid number';
                  if (number < 0 || number > 100) return 'Must be 0-100%';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Purchase Price (Editable)
              TextFormField(
                controller: _purchasePriceController,
                decoration: const InputDecoration(
                  labelText: 'Purchase Price',
                  prefixIcon: Icon(Icons.shopping_cart),
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid number';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Sale Price (Editable)
              TextFormField(
                controller: _salePriceController,
                decoration: const InputDecoration(
                  labelText: 'Sale Price',
                  prefixIcon: Icon(Icons.currency_rupee),
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid number';
                  return null;
                },
              ),
              const SizedBox(height: 24),
            ],

            // Stock (Common for both modes)
            TextFormField(
              controller: _stockController,
              decoration: const InputDecoration(
                labelText: 'Stock Quantity (Optional)',
                prefixIcon: Icon(Icons.inventory),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 32),

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
              label: Text(_isLoading
                  ? 'Saving...'
                  : isEditing
                  ? 'Update Product'
                  : 'Save Product'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
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
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    _stockController.dispose();
    _gstController.dispose();
    super.dispose();
  }
}