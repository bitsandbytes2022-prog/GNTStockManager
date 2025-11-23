import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/product_model.dart';
import '../../services/firebase_service.dart';
import '../../services/settings_service.dart';

class AddProductScreen extends StatefulWidget {
  final Product? product;

  const AddProductScreen({super.key, this.product});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService();
  final SettingsService _settingsService = SettingsService();
  final ImagePicker _imagePicker = ImagePicker();

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
  String? _existingImageBase64;
  bool _isLoading = false;

  // Category management
  String? _selectedCategory;
  List<String> _categories = ['PPR', 'CPVC', 'PVC', 'Paints'];

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
      _existingImageBase64 = widget.product!.imageBase64;
      _selectedCategory = widget.product!.category;

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
      // Setup auto-calculation listeners for adding mode
      _billPriceController.addListener(_calculatePrices);
      _discountReceivedController.addListener(_calculatePrices);
      _sellingDiscountController.addListener(_calculatePrices);
      _marginController.addListener(_calculatePrices);
      _gstController.addListener(_calculatePrices);
    }
  }

  void _calculatePrices() {
    final billPrice = double.tryParse(_billPriceController.text) ?? 0.0;
    final gstRate = (double.tryParse(_gstController.text) ?? 18.0) / 100;

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
        // Set default category only when adding new product
        if (!isEditing && defaultCategory != null && categories.contains(defaultCategory)) {
          _selectedCategory = defaultCategory;
        }
      });
    } catch (e) {
      // Use default categories if loading fails
      setState(() {
        _categories = ['PPR', 'CPVC', 'PVC', 'Paints'];
      });
    }
  }

  Future<void> _showImageSourceDialog() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_selectedImage != null || _existingImageBase64 != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Remove Image'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedImage = null;
                      _existingImageBase64 = null;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
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

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? imageBase64 = _existingImageBase64;

      // Convert new image to base64 if selected
      if (_selectedImage != null) {
        imageBase64 = await _firebaseService.imageToBase64(_selectedImage!);

        if (imageBase64 == null) {
          throw Exception('Failed to convert image to base64');
        }
      }

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
        imageBase64: imageBase64,
        createdAt: isEditing ? widget.product!.createdAt : DateTime.now(),
        category: _selectedCategory!,
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
            // Image Picker
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[400]!, width: 2),
                  ),
                  child: _selectedImage != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      _selectedImage!,
                      fit: BoxFit.cover,
                    ),
                  )
                      : _existingImageBase64 != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      base64Decode(_existingImageBase64!),
                      fit: BoxFit.cover,
                    ),
                  )
                      : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to add image',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

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
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category),
                      border: OutlineInputBorder(),
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
                    validator: (value) => value == null ? 'Required' : null,
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
            const SizedBox(height: 16),

            // ========================================
            // BOTH MODES: Same UI for adding and editing
            // ========================================
            // Discount/Margin Toggle
            Card(
              elevation: 0,
              color: Colors.blue.shade50,
              child: SwitchListTile(
                value: _hasDiscount,
                onChanged: (value) {
                  setState(() {
                    _hasDiscount = value;
                    _calculatePrices();
                  });
                },
                title: const Text('Product has discount?'),
                subtitle: Text(
                  _hasDiscount
                      ? 'Using discount percentages'
                      : 'Using margin percentage',
                  style: const TextStyle(fontSize: 12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Bill Price
            TextFormField(
              controller: _billPriceController,
              decoration: const InputDecoration(
                labelText: 'Bill Price (Base Price)',
                prefixIcon: Icon(Icons.receipt_long),
                prefixText: '₹ ',
                helperText: 'Enter base price without GST',
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

            // GST %
            TextFormField(
              controller: _gstController,
              decoration: InputDecoration(
                labelText: 'GST (%)',
                prefixIcon: const Icon(Icons.receipt),
                suffixText: '%',
                helperText: 'Default: 18%',
                filled: true,
                fillColor: Colors.blue.shade50,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value?.isEmpty ?? true) return null;
                final number = double.tryParse(value!);
                if (number == null) return 'Invalid number';
                if (number < 0 || number > 100) return 'Must be 0-100%';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Conditional: Discount Fields OR Margin Field
            if (_hasDiscount) ...[
              // Discount Received
              TextFormField(
                controller: _discountReceivedController,
                decoration: const InputDecoration(
                  labelText: 'Discount Received (%)',
                  prefixIcon: Icon(Icons.local_offer),
                  suffixText: '%',
                  helperText: 'Discount from supplier',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return null;
                  final number = double.tryParse(value!);
                  if (number == null) return 'Invalid number';
                  if (number < 0 || number > 100) return 'Must be 0-100%';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Selling Discount
              TextFormField(
                controller: _sellingDiscountController,
                decoration: const InputDecoration(
                  labelText: 'Selling Discount (%)',
                  prefixIcon: Icon(Icons.discount),
                  suffixText: '%',
                  helperText: 'Discount to customers',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return null;
                  final number = double.tryParse(value!);
                  if (number == null) return 'Invalid number';
                  if (number < 0 || number > 100) return 'Must be 0-100%';
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
                  helperText: 'Default: 20%',
                  filled: true,
                  fillColor: Colors.green.shade50,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value?.isEmpty ?? true) return null;
                  final number = double.tryParse(value!);
                  if (number == null) return 'Invalid number';
                  if (number < 0) return 'Cannot be negative';
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],

            // Purchase Price (Auto-calculated)
            TextFormField(
              controller: _purchasePriceController,
              decoration: InputDecoration(
                labelText: 'Purchase Price',
                prefixIcon: const Icon(Icons.shopping_cart),
                prefixText: '₹ ',
                helperText: _hasDiscount
                    ? 'Bill - Discount + GST'
                    : 'Bill + GST',
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              readOnly: true,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 16),

            // Sale Price (Auto-calculated)
            TextFormField(
              controller: _salePriceController,
              decoration: InputDecoration(
                labelText: 'Sale Price',
                prefixIcon: const Icon(Icons.currency_rupee),
                prefixText: '₹ ',
                helperText: _hasDiscount
                    ? 'Bill - Selling Discount + GST'
                    : 'Purchase + Margin%',
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              readOnly: true,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 16),

            // Stock Quantity (Common for both modes)
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
    _marginController.dispose();
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    _stockController.dispose();
    _gstController.dispose();
    super.dispose();
  }
}