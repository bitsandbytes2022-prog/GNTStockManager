import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/firebase_service.dart';
import '../../services/settings_service.dart';
import '../widgets/size_input_dialog.dart';

/// Result of the image-source bottom sheet.
enum _ImageAction { camera, gallery, remove }

class CategorySettingsScreen extends StatefulWidget {
  const CategorySettingsScreen({super.key});

  @override
  State<CategorySettingsScreen> createState() => _CategorySettingsScreenState();
}

class _CategorySettingsScreenState extends State<CategorySettingsScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final SettingsService _settingsService = SettingsService();
  final ImagePicker _picker = ImagePicker();

  List<String> _categories = [];
  Map<String, List<String>> _subcategories = {};
  CategoryImages _images = CategoryImages.empty;
  List<String> _globalSizes = [];
  String? _defaultCategory;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final categories = await _firebaseService.getCategories();
      final subcategories = await _firebaseService.getAllSubcategories();
      final images = await _firebaseService.getCategoryImages();
      final globalSizes = await _firebaseService.getGlobalSizes();
      await _firebaseService.getUnits(); // refresh the app-wide units cache
      final defaultCategory = await _firebaseService.getDefaultCategory();

      setState(() {
        _categories = categories;
        _subcategories = subcategories;
        _images = images;
        _globalSizes = globalSizes;
        _defaultCategory = defaultCategory;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('Error loading categories: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _setDefaultCategory(String category) async {
    try {
      await _firebaseService.setDefaultCategory(category);
      await _settingsService.setDefaultCategory(category);
      setState(() => _defaultCategory = category);
      _showSnack('Default category set to: $category');
    } catch (e) {
      _showSnack('Error setting default category: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Image handling
  // ---------------------------------------------------------------------------

  Future<_ImageAction?> _chooseImageSource({required bool hasExisting}) {
    return showModalBottomSheet<_ImageAction>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, _ImageAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, _ImageAction.gallery),
            ),
            if (hasExisting)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Image'),
                onTap: () => Navigator.pop(context, _ImageAction.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Returns a compressed base64 string for a freshly picked image, or null if
  /// the user cancelled or processing failed.
  Future<String?> _pickAndEncode(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (image == null) return null;

    final bytes = await image.readAsBytes();
    final base64 = await _firebaseService.imageBytesToBase64(bytes);
    if (base64 == null) {
      _showSnack('Failed to process image');
    }
    return base64;
  }

  Future<void> _manageCategoryImage(String category) async {
    final action = await _chooseImageSource(
      hasExisting: _images.forCategory(category) != null,
    );
    if (action == null) return;

    try {
      if (action == _ImageAction.remove) {
        await _firebaseService.setCategoryImage(category, null);
        _showSnack('Image removed from $category');
      } else {
        final base64 = await _pickAndEncode(
          action == _ImageAction.camera
              ? ImageSource.camera
              : ImageSource.gallery,
        );
        if (base64 == null) return;
        await _firebaseService.setCategoryImage(category, base64);
        _showSnack('Image updated for $category');
      }
      await _loadData();
    } catch (e) {
      _showSnack('Error updating image: $e');
    }
  }

  Future<void> _manageSubcategoryImage(String category, String sub) async {
    final action = await _chooseImageSource(
      hasExisting: _images.forSubcategory(category, sub) != null,
    );
    if (action == null) return;

    try {
      if (action == _ImageAction.remove) {
        await _firebaseService.setSubcategoryImage(category, sub, null);
        _showSnack('Image removed from $sub');
      } else {
        final base64 = await _pickAndEncode(
          action == _ImageAction.camera
              ? ImageSource.camera
              : ImageSource.gallery,
        );
        if (base64 == null) return;
        await _firebaseService.setSubcategoryImage(category, sub, base64);
        _showSnack('Image updated for $sub');
      }
      await _loadData();
    } catch (e) {
      _showSnack('Error updating image: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Category / subcategory text CRUD
  // ---------------------------------------------------------------------------

  Future<String?> _promptText({
    required String title,
    required String label,
    String? hint,
    String? initialValue,
    String confirmLabel = 'Add',
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm({required String title, required String message}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _reorderCategories(int oldIndex, int newIndex) async {
    // Snapshot for rollback if the write fails.
    final previous = List<String>.from(_categories);

    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, moved);
    });

    try {
      await _firebaseService.reorderCategories(_categories);
    } catch (e) {
      setState(() => _categories = previous);
      _showSnack('Could not save new order: $e');
    }
  }

  Future<void> _addCategory() async {
    final result = await _promptText(
      title: 'Add Category',
      label: 'Category Name',
      hint: 'e.g., Adhesives',
    );
    if (result == null || result.isEmpty) return;

    try {
      await _firebaseService.addCategory(result);
      await _loadData();
      _showSnack('Category "$result" added successfully');
    } catch (e) {
      _showSnack('Error adding category: $e');
    }
  }

  Future<void> _deleteCategory(String category) async {
    final confirmed = await _confirm(
      title: 'Delete Category',
      message:
          'Are you sure you want to delete "$category"?\n\nIts subcategories and images will also be removed. Products with this category keep their value.',
    );
    if (!confirmed) return;

    try {
      await _firebaseService.deleteCategory(category);
      if (_defaultCategory == category) {
        await _settingsService.clearDefaultCategory();
        _defaultCategory = null;
      }
      await _loadData();
      _showSnack('Category "$category" deleted');
    } catch (e) {
      _showSnack('Error deleting category: $e');
    }
  }

  Future<void> _addSubcategory(String category) async {
    final result = await _promptText(
      title: 'Add Subcategory',
      label: 'Subcategory of "$category"',
      hint: 'e.g., Enamel',
    );
    if (result == null || result.isEmpty) return;

    try {
      await _firebaseService.addSubcategory(category, result);
      await _loadData();
      _showSnack('Subcategory "$result" added to $category');
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _renameSubcategory(String category, String sub) async {
    final result = await _promptText(
      title: 'Rename Subcategory',
      label: 'Subcategory of "$category"',
      initialValue: sub,
      confirmLabel: 'Save',
    );
    if (result == null || result.isEmpty || result == sub) return;

    try {
      await _firebaseService.updateSubcategory(category, sub, result);
      await _loadData();
      _showSnack('Subcategory renamed to "$result"');
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _deleteSubcategory(String category, String sub) async {
    final confirmed = await _confirm(
      title: 'Delete Subcategory',
      message:
          'Delete "$sub" from "$category"?\n\nIts image is removed. Products using it keep their value.',
    );
    if (!confirmed) return;

    try {
      await _firebaseService.deleteSubcategory(category, sub);
      await _loadData();
      _showSnack('Subcategory "$sub" deleted');
    } catch (e) {
      _showSnack('Error deleting subcategory: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Sizes — one global pool shared across all categories & subcategories
  // ---------------------------------------------------------------------------

  Future<void> _addGlobalSize() async {
    final size = await showSizeInputDialog(context);
    if (size == null || size.isEmpty) return;
    try {
      await _firebaseService.addGlobalSize(size);
      await _loadData();
      _showSnack('Size "$size" added');
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _deleteGlobalSize(String size) async {
    try {
      await _firebaseService.deleteGlobalSize(size);
      await _loadData();
    } catch (e) {
      _showSnack('Error deleting size: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Category Settings'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeaderCard(),
                _buildGlobalSizesCard(),
                Expanded(
                  child: _categories.isEmpty
                      ? const Center(
                          child: Text(
                            'No categories available.\nTap + to add one.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ReorderableListView.builder(
                          itemCount: _categories.length,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                          buildDefaultDragHandles: false,
                          onReorder: _reorderCategories,
                          proxyDecorator: (child, index, animation) {
                            return Material(
                              color: Colors.transparent,
                              elevation: 6,
                              borderRadius: BorderRadius.circular(12),
                              child: child,
                            );
                          },
                          itemBuilder: (context, index) {
                            return _buildCategoryTile(_categories[index], index);
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCategory,
        tooltip: 'Add Category',
        icon: const Icon(Icons.add),
        label: const Text('Category'),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Categories & Subcategories',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _defaultCategory != null
                ? 'Default category: "$_defaultCategory"'
                : 'No default category set',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'Drag the handle to reorder how categories appear on the home screen. '
            'Tap a thumbnail to set an image, the star to set a default, or expand to manage subcategories.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  /// Global, shared pool of sizes — available to every product regardless of
  /// category or subcategory.
  Widget _buildGlobalSizesCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.straighten, size: 18, color: Colors.indigo.shade400),
              const SizedBox(width: 8),
              const Text(
                'Sizes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Shared across all categories and subcategories.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ..._globalSizes.map((s) => InputChip(
                    label: Text(s),
                    onDeleted: () => _deleteGlobalSize(s),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                  )),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Add size'),
                onPressed: _addGlobalSize,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Circular thumbnail that shows a base64 image, or a placeholder icon.
  /// Tapping it triggers [onTap] (pick / change / remove).
  Widget _buildThumbnail({
    required String? base64,
    required VoidCallback onTap,
    double size = 44,
    IconData placeholder = Icons.category,
  }) {
    final hasImage = base64 != null && base64.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasImage
                ? Image.memory(
                    base64Decode(base64),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        Icon(placeholder, color: Colors.grey.shade400),
                  )
                : Icon(placeholder, color: Colors.grey.shade400),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasImage ? Icons.edit : Icons.add,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(String category, int index) {
    final isDefault = category == _defaultCategory;
    final subs = _subcategories[category] ?? const [];

    return Card(
      key: ValueKey('category_$category'),
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        tilePadding: const EdgeInsets.only(left: 8, right: 4),
        leading: _buildThumbnail(
          base64: _images.forCategory(category),
          onTap: () => _manageCategoryImage(category),
        ),
        title: Text(
          category,
          style: TextStyle(
            fontWeight: isDefault ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          isDefault
              ? 'Default • ${_subLabel(subs.length)}'
              : _subLabel(subs.length),
          style: TextStyle(
            fontSize: 12,
            color: isDefault ? Colors.green.shade700 : Colors.black54,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isDefault ? Icons.star : Icons.star_border,
                color: isDefault ? Colors.amber.shade700 : Colors.grey,
              ),
              tooltip: isDefault ? 'Default category' : 'Set as default',
              onPressed: () => _setDefaultCategory(category),
            ),
            const Icon(Icons.expand_more),
            // Drag handle — only this initiates a reorder, so taps/expansion
            // and the thumbnail still work normally.
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_handle, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (subs.isNotEmpty)
            ...subs.map((sub) => _buildSubcategoryTile(category, sub)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () => _addSubcategory(category),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add subcategory'),
              ),
              TextButton.icon(
                onPressed: () => _deleteCategory(category),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subLabel(int count) => count == 0
      ? 'No subcategories'
      : '$count subcategor${count == 1 ? 'y' : 'ies'}';

  Widget _buildSubcategoryTile(String category, String sub) {
    return Padding(
      key: ValueKey('sub_${category}_$sub'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _buildThumbnail(
            base64: _images.forSubcategory(category, sub),
            onTap: () => _manageSubcategoryImage(category, sub),
            size: 38,
            placeholder: Icons.account_tree_outlined,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(sub, style: const TextStyle(fontSize: 14)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Rename',
            onPressed: () => _renameSubcategory(category, sub),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 20, color: Colors.red),
            tooltip: 'Delete',
            onPressed: () => _deleteSubcategory(category, sub),
          ),
        ],
      ),
    );
  }
}
