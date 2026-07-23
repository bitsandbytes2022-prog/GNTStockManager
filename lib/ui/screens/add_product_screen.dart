import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/product_model.dart';
import '../../models/size_units.dart';
import '../../services/firebase_service.dart';
import '../../services/settings_service.dart';
import '../widgets/size_input_dialog.dart';

class AddProductScreen extends StatefulWidget {
  final Product? product;

  /// Optional list of products + the current index, to enable Next/Previous
  /// navigation between products while editing.
  final List<Product>? products;
  final int? index;

  const AddProductScreen({
    super.key,
    this.product,
    this.products,
    this.index,
  });

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService();
  final SettingsService _settingsService = SettingsService();
  final ImagePicker _imagePicker = ImagePicker();

  final _nameController = TextEditingController();
  final _billPriceController = TextEditingController();
  final _discountReceivedController = TextEditingController();
  final _sellingDiscountController = TextEditingController();
  final _marginController = TextEditingController(text: '20'); // Default 20% margin
  final _purchasePriceController = TextEditingController();
  final _priceWithoutGstController = TextEditingController(); // Base price (GST removed)
  final _salePriceController = TextEditingController();
  final _stockController = TextEditingController();
  final _gstController = TextEditingController(text: '18'); // Default 18%

  File? _selectedImage;
  String? _existingImageBase64;
  bool _isLoading = false;

  // Category management
  String? _selectedCategory;
  List<String> _categories = ['PPR', 'CPVC', 'PVC', 'Paints'];

  // Subcategory management (optional, depends on selected category)
  String? _selectedSubcategory;
  Map<String, List<String>> _subcategories = {};

  // Size management (optional) — one global pool shared across everything.
  // The user picks a unit first, then a value within that unit.
  String? _selectedSize;
  String? _selectedSizeUnit = sizeUnits.first;
  List<String> _globalSizes = [];
  List<String> _units = List<String>.from(sizeUnits);

  // Sentinel value for the "Add unit" entry in the unit dropdown.
  static const String _kAddUnit = '__add_unit__';

  // Discount and Margin management
  bool _hasDiscount = false;

  // When true, the price the user types already includes GST, so we back out
  // the base (without-GST) price instead of adding GST on top.
  bool _priceIncludesGst = false;

  // Guards against the auto-calculation and the manual Purchase Price edit
  // listener overwriting each other (they both write to the price fields).
  bool _updatingProgrammatically = false;

  bool get isEditing => widget.product != null;

  /// Whether Next/Previous navigation is available.
  bool get _hasNav =>
      widget.products != null &&
      widget.index != null &&
      widget.products!.length > 1;

  /// Replace this screen with the edit form for the adjacent product, so the
  /// user can move through products without returning to the list.
  void _navigateTo(int delta) {
    final list = widget.products!;
    final next = (widget.index ?? 0) + delta;
    if (next < 0 || next >= list.length) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductScreen(
          product: list[next],
          products: list,
          index: next,
        ),
      ),
    );
  }

  Future<void> _deleteProduct() async {
    final product = widget.product;
    if (product == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _firebaseService.deleteProduct(product.id);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting product: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();

    if (isEditing) {
      // When editing, populate all values including pricing details
      _nameController.text = widget.product!.name;
      _stockController.text = widget.product!.stock.toString();
      _existingImageBase64 = widget.product!.imageBase64;
      _selectedCategory = widget.product!.category;
      _selectedSubcategory = widget.product!.subcategory;
      _selectedSize =
          widget.product!.size.isEmpty ? null : widget.product!.size;
      if (_selectedSize != null) {
        _selectedSizeUnit = unitOf(_selectedSize!) ?? sizeUnits.first;
      }

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
      _purchasePriceController.addListener(_onPurchasePriceEdited);
    } else {
      // Setup auto-calculation listeners for adding mode
      _billPriceController.addListener(_calculatePrices);
      _discountReceivedController.addListener(_calculatePrices);
      _sellingDiscountController.addListener(_calculatePrices);
      _marginController.addListener(_calculatePrices);
      _gstController.addListener(_calculatePrices);
      _purchasePriceController.addListener(_onPurchasePriceEdited);
    }
  }

  void _calculatePrices() {
    if (_updatingProgrammatically) return;
    _updatingProgrammatically = true;
    try {
      final entered = double.tryParse(_billPriceController.text) ?? 0.0;
      final gstRate = (double.tryParse(_gstController.text) ?? 18.0) / 100;

      if (entered <= 0) {
        _purchasePriceController.text = '';
        _priceWithoutGstController.text = '';
        _salePriceController.text = '';
        return;
      }

      // If the entered price already includes GST, back out the base price;
      // otherwise the entered value IS the base (without-GST) price.
      final billPrice = _priceIncludesGst ? entered / (1 + gstRate) : entered;
      _priceWithoutGstController.text = billPrice.toStringAsFixed(2);

      if (_hasDiscount) {
        // DISCOUNT MODE: Use discount percentages
        final discountReceived =
            double.tryParse(_discountReceivedController.text) ?? 0.0;
        final sellingDiscount =
            double.tryParse(_sellingDiscountController.text) ?? 0.0;

        // Calculate Purchase Price: (Bill Price - Discount Received%) + GST
        final priceAfterDiscount =
            billPrice - (billPrice * discountReceived / 100);
        final purchasePrice =
            priceAfterDiscount + (priceAfterDiscount * gstRate);
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
    } finally {
      _updatingProgrammatically = false;
    }
  }

  /// Called when the user types directly into the Purchase Price field.
  /// Reverse-calculates the Bill Price (and the other derived fields) from the
  /// manually-entered purchase price.
  void _onPurchasePriceEdited() {
    if (_updatingProgrammatically) return;
    final purchase = double.tryParse(_purchasePriceController.text) ?? 0.0;
    if (purchase <= 0) return;
    final gstRate = (double.tryParse(_gstController.text) ?? 18.0) / 100;

    _updatingProgrammatically = true;
    try {
      // Base price without GST (before any received discount).
      double billBase;
      if (_hasDiscount) {
        final discountReceived =
            double.tryParse(_discountReceivedController.text) ?? 0.0;
        final divisor = (1 - discountReceived / 100) * (1 + gstRate);
        billBase = divisor > 0 ? purchase / divisor : purchase / (1 + gstRate);
      } else {
        billBase = purchase / (1 + gstRate);
      }

      // Fill the Bill Price field so it reverses correctly. If the entered
      // price already includes GST, the Bill Price field holds the inclusive
      // amount; otherwise it holds the base.
      final billFieldValue =
          _priceIncludesGst ? billBase * (1 + gstRate) : billBase;
      _billPriceController.text = billFieldValue.toStringAsFixed(2);

      // Price without GST = purchase price with GST removed.
      _priceWithoutGstController.text =
          (purchase / (1 + gstRate)).toStringAsFixed(2);

      // In margin mode the sale price follows the purchase price. In discount
      // mode the sale price is driven separately, so leave it untouched.
      if (!_hasDiscount) {
        final margin = double.tryParse(_marginController.text) ?? 20.0;
        _salePriceController.text =
            (purchase + (purchase * margin / 100)).toStringAsFixed(2);
      }
    } finally {
      _updatingProgrammatically = false;
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _firebaseService.getCategories();
      final subcategories = await _firebaseService.getAllSubcategories();
      final globalSizes = await _firebaseService.getGlobalSizes();
      final units = await _firebaseService.getUnits();

      // Load default category if adding a new product (not editing)
      String? defaultCategory;
      if (!isEditing) {
        defaultCategory = await _settingsService.getDefaultCategory();
      }

      setState(() {
        _categories = categories;
        _subcategories = subcategories;
        _globalSizes = globalSizes;
        _units = units;
        // Re-derive the unit now that custom units are loaded (handles sizes
        // that use a custom unit not in the defaults).
        if (_selectedSize != null) {
          _selectedSizeUnit = unitOf(_selectedSize!) ?? _selectedSizeUnit;
        }
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

  /// Subcategory options for the currently selected category, including any
  /// legacy value already on the product so it stays selectable.
  List<String> get _currentSubcategories {
    final base = List<String>.from(_subcategories[_selectedCategory] ?? const []);
    final current = _selectedSubcategory;
    if (current != null && current.isNotEmpty && !base.contains(current)) {
      base.add(current);
    }
    return base;
  }

  Future<void> _showAddSubcategoryDialog() async {
    final category = _selectedCategory;
    if (category == null) return;

    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Subcategory'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Subcategory of "$category"',
            hintText: 'e.g., Enamel',
            border: const OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      await _firebaseService.addSubcategory(category, result);
      setState(() {
        _subcategories.putIfAbsent(category, () => <String>[]).add(result);
        _selectedSubcategory = result;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subcategory "$result" added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  /// Sizes in the global pool that match the currently selected unit, plus the
  /// product's current size if it matches (so legacy values stay selectable).
  List<String> get _sizesForSelectedUnit {
    final unit = _selectedSizeUnit;
    final result =
        _globalSizes.where((s) => unitOf(s) == unit).toSet().toList();
    // Always keep the currently-selected size in the list so the dropdown's
    // value is valid — even legacy values whose unit doesn't parse.
    final current = _selectedSize;
    if (current != null && current.isNotEmpty && !result.contains(current)) {
      result.add(current);
    }
    return result;
  }

  Future<void> _showAddSizeDialog() async {
    final result = await showSizeInputDialog(context);
    if (result == null || result.isEmpty) return;

    try {
      await _firebaseService.addGlobalSize(result);
      _globalSizes.add(result);
      setState(() {
        _selectedSize = result;
        // Switch the unit picker to match the size just added.
        _selectedSizeUnit = unitOf(result) ?? _selectedSizeUnit;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Size "$result" added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _showAddUnitDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Unit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Unit name',
            hintText: 'e.g., Dozen, Box, Meter',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      await _firebaseService.addUnit(result);
      setState(() {
        if (!_units.contains(result)) _units.add(result);
        _selectedSizeUnit = result;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unit "$result" added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
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
        size: (_selectedSize ?? '').trim(),
        purchasePrice: double.parse(_purchasePriceController.text),
        salePrice: double.parse(_salePriceController.text),
        stock: int.tryParse(_stockController.text) ?? 0,
        imageBase64: imageBase64,
        createdAt: isEditing ? widget.product!.createdAt : DateTime.now(),
        category: _selectedCategory!,
        subcategory: _selectedSubcategory,
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
      if (product.size.isNotEmpty) {
        await _firebaseService.markSizeUsed(product.size);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing
                ? 'Product updated successfully'
                : 'Product added successfully'),
          ),
        );
        // After updating, move to the next product if there is one;
        // otherwise return to the list.
        if (_hasNav && widget.index! < widget.products!.length - 1) {
          _navigateTo(1);
        } else {
          Navigator.pop(context);
        }
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
        title: Text(
          _hasNav
              ? 'Edit Product (${widget.index! + 1}/${widget.products!.length})'
              : (isEditing ? 'Edit Product' : 'Add Product'),
        ),
        elevation: 0,
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete product',
              onPressed: _isLoading ? null : _deleteProduct,
            ),
          if (_hasNav) ...[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous product',
              onPressed: widget.index! > 0 ? () => _navigateTo(-1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next product',
              onPressed: widget.index! < widget.products!.length - 1
                  ? () => _navigateTo(1)
                  : null,
            ),
            const SizedBox(width: 4),
          ],
        ],
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
                      setState(() {
                        _selectedCategory = value;
                        // Subcategory depends on the category; size is global.
                        _selectedSubcategory = null;
                      });
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

            // Subcategory Selection (optional) — shown once a category is chosen
            if (_selectedCategory != null) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedSubcategory,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Subcategory (Optional)',
                        prefixIcon: Icon(Icons.account_tree_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None'),
                        ),
                        ..._currentSubcategories.map((sub) {
                          return DropdownMenuItem<String?>(
                            value: sub,
                            child: Text(sub),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedSubcategory = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: _showAddSubcategoryDialog,
                    icon: const Icon(Icons.add),
                    tooltip: 'Add New Subcategory',
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Size Selection (optional, unified picklist)
              Row(
                children: [
                  // 1) Unit picker (with an inline "Add unit" option)
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedSizeUnit,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        prefixIcon: Icon(Icons.straighten),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        ...{..._units, if (_selectedSizeUnit != null) _selectedSizeUnit!}
                            .map((u) =>
                                DropdownMenuItem(value: u, child: Text(u))),
                        const DropdownMenuItem(
                          value: _kAddUnit,
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 18, color: Colors.blue),
                              SizedBox(width: 6),
                              Text('Add unit',
                                  style: TextStyle(color: Colors.blue)),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (unit) {
                        if (unit == _kAddUnit) {
                          _showAddUnitDialog();
                          return;
                        }
                        setState(() {
                          _selectedSizeUnit = unit;
                          // Clear the value if it doesn't belong to this unit.
                          if (_selectedSize != null &&
                              unitOf(_selectedSize!) != unit) {
                            _selectedSize = null;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 2) Value picker (filtered by the chosen unit)
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String?>(
                      value: _selectedSize,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Size (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None'),
                        ),
                        ..._sizesForSelectedUnit.map((size) {
                          return DropdownMenuItem<String?>(
                            value: size,
                            child: Text(valueOf(size)),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedSize = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: _showAddSizeDialog,
                    icon: const Icon(Icons.add),
                    tooltip: 'Add New Size',
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

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
              decoration: InputDecoration(
                labelText: _priceIncludesGst
                    ? 'Purchase Price (incl. GST)'
                    : 'Bill Price (Base Price)',
                prefixIcon: const Icon(Icons.receipt_long),
                prefixText: '₹ ',
                helperText: _priceIncludesGst
                    ? 'Enter price with GST included'
                    : 'Enter base price without GST',
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
            const SizedBox(height: 8),

            // Toggle: does the entered price already include GST?
            Card(
              elevation: 0,
              color: Colors.orange.shade50,
              child: SwitchListTile(
                value: _priceIncludesGst,
                onChanged: (value) {
                  setState(() {
                    _priceIncludesGst = value;
                    _calculatePrices();
                  });
                },
                title: const Text('Entered price includes GST?'),
                subtitle: Text(
                  _priceIncludesGst
                      ? 'Price without GST is auto-calculated'
                      : 'Price is treated as base (GST added on top)',
                  style: const TextStyle(fontSize: 12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
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

            // Price without GST (auto-calculated) — only when entering an
            // inclusive price.
            if (_priceIncludesGst) ...[
              TextFormField(
                controller: _priceWithoutGstController,
                decoration: InputDecoration(
                  labelText: 'Price without GST',
                  prefixIcon: const Icon(Icons.money_off),
                  prefixText: '₹ ',
                  helperText: 'Base price (GST removed)',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
                readOnly: true,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
              const SizedBox(height: 16),
            ],

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

            // Purchase Price (Auto-calculated, but editable to override)
            TextFormField(
              controller: _purchasePriceController,
              decoration: InputDecoration(
                labelText: 'Purchase Price',
                prefixIcon: const Icon(Icons.shopping_cart),
                prefixText: '₹ ',
                helperText: _hasDiscount
                    ? 'Auto: Bill - Discount + GST · tap to edit'
                    : 'Auto: Bill + GST · tap to edit',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) return 'Required';
                if (double.tryParse(value!) == null) return 'Invalid number';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Sale Price (Auto-calculated, but editable to override)
            TextFormField(
              controller: _salePriceController,
              decoration: InputDecoration(
                labelText: 'Sale Price',
                prefixIcon: const Icon(Icons.currency_rupee),
                prefixText: '₹ ',
                helperText: _hasDiscount
                    ? 'Auto: Bill - Selling Discount + GST · tap to edit'
                    : 'Auto: Purchase + Margin% · tap to edit',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) return 'Required';
                if (double.tryParse(value!) == null) return 'Invalid number';
                return null;
              },
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
    _billPriceController.dispose();
    _discountReceivedController.dispose();
    _sellingDiscountController.dispose();
    _marginController.dispose();
    _purchasePriceController.dispose();
    _priceWithoutGstController.dispose();
    _salePriceController.dispose();
    _stockController.dispose();
    _gstController.dispose();
    super.dispose();
  }
}