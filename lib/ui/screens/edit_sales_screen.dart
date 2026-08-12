import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/product_model.dart';
import '../../models/sale_model.dart';
import '../../services/firebase_service.dart';
import '../../services/sales_service.dart';

/// One resolved, independent cart line. The same product can appear as more
/// than one _CartLine (e.g. the original sale already had it twice, or the
/// editor adds another line for it) — each keeps its own quantity/price/
/// per-foot flag rather than merging into a shared total. Mirrors
/// RecordSaleScreen's _CartLine so edit and record stay consistent.
class _CartLine {
  final String lineKey;
  final Product product;
  final int quantity;
  final double price;
  final bool isPerFoot;

  const _CartLine({
    required this.lineKey,
    required this.product,
    required this.quantity,
    required this.price,
    required this.isPerFoot,
  });
}

class EditSaleScreen extends StatefulWidget {
  final Sale sale;

  const EditSaleScreen({super.key, required this.sale});

  @override
  State<EditSaleScreen> createState() => _EditSaleScreenState();
}

class _EditSaleScreenState extends State<EditSaleScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final SalesService _salesService = SalesService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _cartSearchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _buyerNameController = TextEditingController();
  final TextEditingController _buyerPhoneController = TextEditingController();
  final TextEditingController _buyerAddressController = TextEditingController();
  final TextEditingController _amountPaidController = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];

  // The cart holds independent *lines*, not one slot per product — the same
  // product can appear more than once (already true of the original sale in
  // some cases, and now also possible by adding it again during editing).
  // Every map below is keyed by a synthetic lineKey (see _newLineKey), not
  // by productId; _lineProductId resolves a lineKey back to the real
  // product. Mirrors RecordSaleScreen's cart model.
  Map<String, int> _selectedQuantities = {};
  Map<String, double> _customPrices = {};

  /// lineKey -> sold-by-length (pipes cut to feet). Quantity for these
  /// products is feet, not units — see Product.feetPerPipe.
  Map<String, bool> _perFootItems = {};

  /// Tracks line order (original sale order, then append-on-add) so the
  /// saved sale's item list isn't silently reshuffled into product-catalog
  /// order — see _cartLines below.
  List<String> _cartItemOrder = [];
  Map<String, String> _lineProductId = {}; // lineKey -> productId
  int _lineKeyCounter = 0;
  String _searchQuery = '';
  String _cartSearchQuery = '';
  bool _isLoading = true;
  bool _isSaving = false;
  String _paymentMethod = 'Cash';

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1200;
  bool get _isTablet => MediaQuery.of(context).size.width >= 768;

  // A fresh, unique key for each cart line so the same product can appear
  // as more than one independent line.
  String _newLineKey(String productId) => '${productId}_L${_lineKeyCounter++}';

  /// Whether [productId] has at least one line in the cart.
  bool _isProductInCart(String productId) =>
      _lineProductId.values.contains(productId);

  @override
  void initState() {
    super.initState();
    _initializeFromSale();
    _loadProducts();
    _searchController.addListener(_filterProducts);
    _cartSearchController.addListener(_filterCartProducts);
  }

  void _filterCartProducts() {
    setState(() {
      _cartSearchQuery = _cartSearchController.text.toLowerCase();
    });
  }

  void _initializeFromSale() {
    // Initialize from existing sale
    _paymentMethod = widget.sale.paymentMethod?.label ?? 'Cash';
    _notesController.text = widget.sale.notes ?? '';
    _buyerNameController.text = widget.sale.buyerName ?? '';
    _buyerPhoneController.text = widget.sale.buyerPhone ?? '';
    _buyerAddressController.text = widget.sale.buyerAddress ?? '';
    _amountPaidController.text = widget.sale.amountPaid.toStringAsFixed(2);

    // Populate selected items, preserving the original sale's item order.
    // Each sale item becomes its own cart line — if the original sale
    // already had a product on more than one line, that must stay intact
    // rather than collapsing into one combined entry.
    for (final item in widget.sale.items) {
      final lineKey = _newLineKey(item.productId);
      _cartItemOrder.add(lineKey);
      _lineProductId[lineKey] = item.productId;
      _selectedQuantities[lineKey] = item.quantity;
      _customPrices[lineKey] = item.salePrice;
      _perFootItems[lineKey] = item.isPerFoot;
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      _allProducts = await _firebaseService.getCachedProducts();
      _filteredProducts = List.from(_allProducts);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading products: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterProducts() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();

      if (_searchQuery.isEmpty) {
        _filteredProducts = List.from(_allProducts);
      } else {
        final queryWords = _searchQuery.split(' ').where((w) => w.isNotEmpty);

        _filteredProducts = _allProducts.where((product) {
          final name = product.name.toLowerCase();
          final size = product.size.toLowerCase();

          return queryWords.every((word) => name.contains(word) || size.contains(word));
        }).toList();
      }
    });
  }

  /// Tapping a product in the browse grid always adds a fresh cart line —
  /// even if the product already has lines in the cart, so coming back for
  /// more of the same item shows up as its own line rather than silently
  /// merging into (or replacing) an earlier one. Removing a line is done
  /// from the cart panel itself via the line's remove button.
  void _addProductLine(Product product) {
    setState(() {
      final lineKey = _newLineKey(product.id);
      _cartItemOrder.add(lineKey);
      _lineProductId[lineKey] = product.id;
      _selectedQuantities[lineKey] = 1;
      _customPrices[lineKey] = product.salePrice;
      _perFootItems[lineKey] = false;
    });
  }

  /// Removes one specific cart line, identified by its lineKey (not the
  /// productId — a product may have several lines).
  void _removeFromCart(String lineKey) {
    setState(() {
      _selectedQuantities.remove(lineKey);
      _customPrices.remove(lineKey);
      _perFootItems.remove(lineKey);
      _lineProductId.remove(lineKey);
      _cartItemOrder.remove(lineKey);
    });
  }

  void _updateQuantity(String lineKey, int quantity) {
    if (quantity <= 0) {
      _removeFromCart(lineKey);
    } else {
      setState(() {
        _selectedQuantities[lineKey] = quantity;
      });
    }
  }

  void _updatePrice(String lineKey, double price) {
    setState(() {
      _customPrices[lineKey] = price;
    });
  }

  /// Toggling per-foot rescales the price the same way record_sale_screen's
  /// add dialog does — otherwise switching modes leaves a per-pipe price on
  /// a per-foot line (or vice versa), which then fails the minimum-price
  /// check since that's scaled to match.
  void _updatePerFoot(String lineKey, Product product, bool isPerFoot) {
    setState(() {
      _perFootItems[lineKey] = isPerFoot;
      final feet = product.feetPerPipe;
      if (feet != null && feet > 0) {
        _customPrices[lineKey] =
            isPerFoot ? product.salePrice / feet : product.salePrice;
      }
    });
  }

  double _getMinimumPrice(Product product, bool isPerFoot) {
    final feet = product.feetPerPipe;
    if (isPerFoot && feet != null && feet > 0) {
      return (product.purchasePrice / feet) * 0.50;
    }
    return product.purchasePrice * 0.50;
  }

  /// Buyer name/phone/address (recorded for future reference) plus, when
  /// Payment Method is Credit, an editable "amount received so far" field —
  /// needed for fixing a sale that was logged under the wrong payment
  /// method (e.g. recorded as Cash when it was actually Credit).
  Widget _buildBuyerAndCreditFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Buyer Details (optional)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _buyerNameController,
          decoration: InputDecoration(
            labelText: 'Name',
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _buyerPhoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Phone',
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _buyerAddressController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Address',
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        if (_paymentMethod == 'Credit') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _amountPaidController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount received so far',
              helperText: 'Set to 0 if nothing has been received yet',
              prefixText: '₹',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ],
    );
  }

  /// Payment method + buyer/credit fields + notes, as one block appended to
  /// the end of the scrollable cart-items list (rather than pinned outside
  /// it) — otherwise, on a short screen, the extra Credit fields can push
  /// this section's height past what's left after the pinned Total/Update
  /// footer, causing a render overflow.
  Widget _buildPaymentAndNotesSection({required Color backgroundColor}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Method',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _paymentMethod,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              filled: true,
              fillColor: Colors.white,
            ),
            items: ['Cash', 'UPI', 'Card', 'Credit', 'Other']
                .map((method) => DropdownMenuItem(
                      value: method,
                      child: Text(method),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _paymentMethod = value);
              }
            },
          ),
          const SizedBox(height: 16),
          _buildBuyerAndCreditFields(),
          const SizedBox(height: 16),
          const Text(
            'Notes (Optional)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add any notes...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(12),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  double get _totalAmount {
    double total = 0;
    for (final line in _cartLines) {
      total += line.price * line.quantity;
    }
    return total;
  }

  /// One resolved cart line per entry in cart order (original sale order,
  /// then any lines added during this edit, appended in the order they
  /// were added) — not catalog order, so saving doesn't reshuffle the
  /// sale's item list. A product can legitimately resolve to more than one
  /// line here.
  List<_CartLine> get _cartLines {
    final lines = <_CartLine>[];
    for (final key in _cartItemOrder) {
      final productId = _lineProductId[key];
      if (productId == null) continue;
      Product? product;
      try {
        product = _allProducts.firstWhere((p) => p.id == productId);
      } catch (_) {
        continue; // Product no longer in the catalog — skip it.
      }
      final quantity = _selectedQuantities[key];
      final price = _customPrices[key];
      if (quantity == null || price == null) continue;
      lines.add(_CartLine(
        lineKey: key,
        product: product,
        quantity: quantity,
        price: price,
        isPerFoot: _perFootItems[key] ?? false,
      ));
    }
    return lines;
  }

  List<_CartLine> get _filteredCartLines {
    if (_cartSearchQuery.isEmpty) return _cartLines;

    final queryWords = _cartSearchQuery.split(' ').where((w) => w.isNotEmpty);

    return _cartLines.where((line) {
      final name = line.product.name.toLowerCase();
      final size = line.product.size.toLowerCase();

      return queryWords.every((word) => name.contains(word) || size.contains(word));
    }).toList();
  }

  Future<void> _updateSale() async {
    if (_selectedQuantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one product')),
      );
      return;
    }

    // Validate prices
    for (final line in _cartLines) {
      final minPrice = _getMinimumPrice(line.product, line.isPerFoot);

      if (line.price < minPrice) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${line.product.name}: Price must be at least ₹${minPrice.toStringAsFixed(2)}',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // _cartLines resolves each cart line's product from _allProducts — if a
    // line's product can no longer be found there (deleted, or _allProducts
    // went stale), it silently drops out of updatedSaleItems below while
    // the sale's total still reflects it. Fail loudly instead of saving a
    // sale whose items no longer match its total.
    if (_cartLines.length != _cartItemOrder.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Some cart items could not be found (they may have been deleted). '
            'Please remove them from the cart and try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Create updated sale items — each cart line becomes its own SaleItem,
      // so a product appearing on more than one line (already true of some
      // original sales, or added again during this edit) is saved as
      // separate lines rather than merged into one combined quantity.
      final updatedSaleItems = _cartLines.map((line) {
        final product = line.product;
        final isPerFoot = line.isPerFoot;
        final quantity = line.quantity;
        final purchasePrice = isPerFoot && product.feetPerPipe != null
            ? product.purchasePrice / product.feetPerPipe!
            : product.purchasePrice;
        final stockUnits = isPerFoot
            ? (product.feetPerPipe != null && product.feetPerPipe! > 0
                ? (quantity / product.feetPerPipe!).ceil()
                : quantity)
            : quantity;

        return SaleItem(
          productId: product.id,
          productName: product.name,
          productSize: product.size,
          quantity: quantity,
          salePrice: line.price,
          purchasePrice: purchasePrice,
          imageBase64: product.imageBase64,
          isPerFoot: isPerFoot,
          stockUnits: stockUnits,
        );
      }).toList();

      // Convert payment method string to enum
      PaymentMethod paymentMethodEnum;
      switch (_paymentMethod.toLowerCase()) {
        case 'cash':
          paymentMethodEnum = PaymentMethod.cash;
          break;
        case 'upi':
          paymentMethodEnum = PaymentMethod.upi;
          break;
        case 'card':
          paymentMethodEnum = PaymentMethod.card;
          break;
        case 'credit':
          paymentMethodEnum = PaymentMethod.credit;
          break;
        default:
          paymentMethodEnum = PaymentMethod.other;
      }

      // Calculate total
      final total = updatedSaleItems.fold<double>(
        0.0,
            (sum, item) => sum + (item.salePrice * item.quantity),
      );

      // Amount paid only makes sense to edit for Credit sales (e.g.
      // correcting a sale that was mistakenly logged as Cash but was
      // actually Credit). For any other payment method, treat it as fully
      // paid — pass null so the Sale constructor sets it to the total.
      final amountPaid = paymentMethodEnum == PaymentMethod.credit
          ? (double.tryParse(_amountPaidController.text) ?? widget.sale.amountPaid)
          : null;

      final updatedSale = Sale(
        invoiceNumber: widget.sale.invoiceNumber,
        id: widget.sale.id,
        items: updatedSaleItems,
        totalAmount: total,
        createdAt: widget.sale.createdAt, // Keep original creation date
        paymentMethod: paymentMethodEnum,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        isMock: widget.sale.isMock, // Preserve mock flag through edits
        buyerName: _buyerNameController.text.trim().isEmpty
            ? null
            : _buyerNameController.text.trim(),
        buyerPhone: _buyerPhoneController.text.trim().isEmpty
            ? null
            : _buyerPhoneController.text.trim(),
        buyerAddress: _buyerAddressController.text.trim().isEmpty
            ? null
            : _buyerAddressController.text.trim(),
        amountPaid: amountPaid,
        payments: widget.sale.payments,
      );

      // Update sale with stock adjustments. Stock deltas are computed by
      // SalesService from oldSale vs. newSale item totals per product, so
      // no separate original-quantities map is needed here.
      await _salesService.updateSale(
        widget.sale,
        updatedSale,
        const {},
      );

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating sale: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return _buildDesktopLayout();
    } else {
      return _buildMobileLayout();
    }
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Sale'),
            Text(
              'Sale from ${DateFormat('MMM dd, yyyy hh:mm a').format(widget.sale.createdAt)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: Row(
        children: [
          // Left side - Product selection
          Expanded(
            flex: 3,
            child: _buildProductList(),
          ),

          // Right side - Cart
          Container(
            width: 400,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                left: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: _buildCart(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Sale'),
            Text(
              DateFormat('MMM dd, yyyy').format(widget.sale.createdAt),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: _buildProductList(),
      bottomSheet: _selectedQuantities.isNotEmpty
          ? _buildCartBottomSheet()
          : null,
    );
  }

  Widget _buildProductList() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search products...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),

        // Product grid
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredProducts.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No products found',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          )
              : GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _isDesktop ? 4 : (_isTablet ? 3 : 2),
              childAspectRatio: 0.75,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _filteredProducts.length,
            itemBuilder: (context, index) {
              final product = _filteredProducts[index];
              final isSelected = _isProductInCart(product.id);

              return _ProductCard(
                product: product,
                isSelected: isSelected,
                onTap: () => _addProductLine(product),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCart() {
    return Column(
      children: [
        // Cart header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.shopping_cart, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Cart (${_cartLines.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (_selectedQuantities.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _cartSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search cart...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _cartSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _cartSearchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Cart items
        Expanded(
          child: _cartLines.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No items selected',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          )
              : _filteredCartLines.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No items found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search term',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final line in _filteredCartLines)
                          _CartItem(
                            product: line.product,
                            quantity: line.quantity,
                            price: line.price,
                            onQuantityChanged: (qty) => _updateQuantity(line.lineKey, qty),
                            onPriceChanged: (price) => _updatePrice(line.lineKey, price),
                            onRemove: () => _removeFromCart(line.lineKey),
                            minimumPrice: _getMinimumPrice(line.product, line.isPerFoot),
                            isPerFoot: line.isPerFoot,
                            onPerFootChanged: (value) =>
                                _updatePerFoot(line.lineKey, line.product, value),
                          ),
                        _buildPaymentAndNotesSection(backgroundColor: Colors.white),
                      ],
                    ),
        ),

        // Total and complete button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '₹${_totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving || _selectedQuantities.isEmpty
                      ? null
                      : _updateSale,
                  icon: _isSaving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.check),
                  label: Text(_isSaving ? 'Updating...' : 'Update Sale'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCartBottomSheet() {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.shopping_cart),
                  title: Text('${_cartLines.length} items'),
                  trailing: Text(
                    '₹${_totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => _buildCartModal(),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving || _selectedQuantities.isEmpty
                          ? null
                          : _updateSale,
                      icon: _isSaving
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.check),
                      label: Text(_isSaving ? 'Updating...' : 'Update Sale'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCartModal() {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text(
                      'Cart Items',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Search bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _cartSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search cart...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _cartSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _cartSearchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),

              // Cart items
              Expanded(
                child: _filteredCartLines.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No items found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try a different search term',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final line in _filteredCartLines)
                            _CartItem(
                              product: line.product,
                              quantity: line.quantity,
                              price: line.price,
                              onQuantityChanged: (qty) {
                                setState(() => _updateQuantity(line.lineKey, qty));
                              },
                              onPriceChanged: (price) {
                                setState(() => _updatePrice(line.lineKey, price));
                              },
                              onRemove: () {
                                setState(() => _removeFromCart(line.lineKey));
                              },
                              minimumPrice: _getMinimumPrice(line.product, line.isPerFoot),
                              isPerFoot: line.isPerFoot,
                              onPerFootChanged: (value) {
                                setState(() => _updatePerFoot(line.lineKey, line.product, value));
                              },
                            ),
                          _buildPaymentAndNotesSection(backgroundColor: Colors.grey.shade50),
                        ],
                      ),
              ),

              // Total and button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '₹${_totalAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSaving || _selectedQuantities.isEmpty
                            ? null
                            : _updateSale,
                        icon: _isSaving
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(Icons.check),
                        label: Text(_isSaving ? 'Updating...' : 'Update Sale'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cartSearchController.dispose();
    _notesController.dispose();
    _buyerNameController.dispose();
    _buyerPhoneController.dispose();
    _buyerAddressController.dispose();
    _amountPaidController.dispose();
    super.dispose();
  }
}

// Product Card Widget
class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isSelected;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 8 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product image
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: product.imageBase64 != null
                        ? ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: Image.memory(
                        base64Decode(product.imageBase64!),
                        fit: BoxFit.cover,
                      ),
                    )
                        : Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                  ),
                ),

                // Product info
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product.size,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₹${product.salePrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Selected indicator
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Cart Item Widget (reusing from RecordSaleScreen)
class _CartItem extends StatefulWidget {
  final Product product;
  final int quantity;
  final double price;
  final Function(int) onQuantityChanged;
  final Function(double) onPriceChanged;
  final VoidCallback onRemove;
  final double minimumPrice;
  final bool isPerFoot;
  final ValueChanged<bool>? onPerFootChanged;

  const _CartItem({
    required this.product,
    required this.quantity,
    required this.price,
    required this.onQuantityChanged,
    required this.onPriceChanged,
    required this.onRemove,
    required this.minimumPrice,
    this.isPerFoot = false,
    this.onPerFootChanged,
  });

  @override
  State<_CartItem> createState() => _CartItemState();
}

class _CartItemState extends State<_CartItem> {
  late TextEditingController _priceController;
  late TextEditingController _qtyController;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.price.toStringAsFixed(0),
    );
    _qtyController = TextEditingController(
      text: widget.quantity.toString(),
    );
  }

  @override
  void didUpdateWidget(_CartItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.price != widget.price) {
      _priceController.text = widget.price.toStringAsFixed(0);
    }
    if (oldWidget.quantity != widget.quantity) {
      _qtyController.text = widget.quantity.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Product image
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: widget.product.imageBase64 != null
                        ? Image.memory(
                      base64Decode(widget.product.imageBase64!),
                      fit: BoxFit.cover,
                    )
                        : Icon(
                      Icons.inventory_2_outlined,
                      color: Colors.grey[400],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Product info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            widget.product.size,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (widget.isPerFoot) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.indigo.shade200),
                              ),
                              child: Text(
                                'PER FOOT',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Remove button
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
            if (widget.product.feetPerPipe != null && widget.onPerFootChanged != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: widget.isPerFoot ? Colors.indigo.shade50 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.isPerFoot ? Colors.indigo.shade200 : Colors.grey.shade300,
                  ),
                ),
                child: SwitchListTile(
                  value: widget.isPerFoot,
                  onChanged: (value) => widget.onPerFootChanged!(value),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Sell per Foot',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Each pipe is ${widget.product.feetPerPipe} ft',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Quantity and price controls
            Row(
              children: [
                // Quantity
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isPerFoot ? 'Feet' : 'Quantity',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              if (widget.quantity > 1) {
                                widget.onQuantityChanged(widget.quantity - 1);
                              }
                            },
                            icon: const Icon(Icons.remove, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.grey[100],
                            ),
                          ),
                          Expanded(
                            child: Text(
                              widget.isPerFoot ? '${widget.quantity} ft' : '${widget.quantity}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              if (widget.isPerFoot || widget.quantity < widget.product.stock) {
                                widget.onQuantityChanged(widget.quantity + 1);
                              }
                            },
                            icon: const Icon(Icons.add, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.blue.shade50,
                              foregroundColor: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Price
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isPerFoot ? 'Price per foot' : 'Price',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixText: '₹',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) {
                          final price = double.tryParse(value);
                          if (price != null) {
                            widget.onPriceChanged(price);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Subtotal
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subtotal',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  '₹${(widget.price * widget.quantity).toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }
}