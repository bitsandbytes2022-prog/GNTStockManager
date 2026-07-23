import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A polished reverse-GST calculator: enter a GST-inclusive price, a quantity
/// and a GST rate, and see the base (GST-exclusive) price per item and for the
/// whole quantity, with the GST component broken out.
class GstCalculatorScreen extends StatefulWidget {
  const GstCalculatorScreen({super.key});

  @override
  State<GstCalculatorScreen> createState() => _GstCalculatorScreenState();
}

class _GstCalculatorScreenState extends State<GstCalculatorScreen> {
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _gstController = TextEditingController(text: '18');

  static const List<double> _commonRates = [5, 12, 18, 28];

  // Brand gradient for the hero result card.
  static const _heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  );

  @override
  void initState() {
    super.initState();
    _priceController.addListener(_onChanged);
    _qtyController.addListener(_onChanged);
    _gstController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  double get _inclusivePrice => double.tryParse(_priceController.text) ?? 0;
  int get _qty => int.tryParse(_qtyController.text) ?? 0;
  double get _gstRate => double.tryParse(_gstController.text) ?? 0;

  // Reverse GST: base = inclusive / (1 + rate/100)
  double get _basePerItem =>
      _gstRate <= 0 ? _inclusivePrice : _inclusivePrice / (1 + _gstRate / 100);
  double get _gstPerItem => _inclusivePrice - _basePerItem;

  double get _baseTotal => _basePerItem * _qty;
  double get _gstTotal => _gstPerItem * _qty;
  double get _grossTotal => _inclusivePrice * _qty;

  bool get _hasInput => _inclusivePrice > 0 && _qty > 0;

  String _money(double v) => '₹${v.round()}';

  void _adjustQty(int delta) {
    final next = (_qty + delta).clamp(1, 99999);
    _qtyController.text = next.toString();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _qtyController.dispose();
    _gstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('GST Calculator'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF1F2937),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildHero(),
          const SizedBox(height: 20),
          _buildInputCard(),
          if (_hasInput) ...[
            const SizedBox(height: 16),
            _buildBreakdownCard(),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Hero result
  // ---------------------------------------------------------------------------

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: _heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.savings_outlined,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'PRICE WITHOUT GST',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Headline: per-item base price
          Text(
            _hasInput ? _money(_basePerItem) : '₹0',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'per item',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.shopping_cart_outlined,
                        color: Colors.white.withOpacity(0.9), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'For ${_hasInput ? _qty : 0} item${_qty == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  _hasInput ? _money(_baseTotal) : '₹0',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Inputs
  // ---------------------------------------------------------------------------

  Widget _buildInputCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Price (incl. GST)'),
          const SizedBox(height: 8),
          TextField(
            controller: _priceController,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: '₹  ',
              prefixStyle: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
              ),
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          _label('Count'),
          const SizedBox(height: 8),
          _buildQtyStepper(),
          const SizedBox(height: 20),
          _label('GST Rate'),
          const SizedBox(height: 8),
          _buildRatePills(),
        ],
      ),
    );
  }

  Widget _buildQtyStepper() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _stepperButton(Icons.remove, () => _adjustQty(-1)),
          Expanded(
            child: TextField(
              controller: _qtyController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          _stepperButton(Icons.add, () => _adjustQty(1)),
        ],
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, size: 22, color: const Color(0xFF6366F1)),
        ),
      ),
    );
  }

  Widget _buildRatePills() {
    return Row(
      children: _commonRates.map((rate) {
        final selected = _gstRate == rate;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _gstController.text = rate.toStringAsFixed(0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: selected ? _heroGradient : null,
                  color: selected ? null : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${rate.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Breakdown
  // ---------------------------------------------------------------------------

  Widget _buildBreakdownCard() {
    return _card(
      child: Column(
        children: [
          _breakdownRow(
            icon: Icons.inventory_2_outlined,
            label: 'Per item',
            base: _basePerItem,
            gst: _gstPerItem,
            gross: _inclusivePrice,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: Colors.grey.shade200),
          ),
          _breakdownRow(
            icon: Icons.shopping_cart_outlined,
            label: 'For $_qty item${_qty == 1 ? '' : 's'}',
            base: _baseTotal,
            gst: _gstTotal,
            gross: _grossTotal,
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow({
    required IconData icon,
    required String label,
    required double base,
    required double gst,
    required double gross,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF6366F1)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _miniRow('Price without GST', _money(base), bold: true),
        const SizedBox(height: 6),
        _miniRow('GST (${_gstRate.toStringAsFixed(0)}%)', _money(gst),
            color: const Color(0xFFEF4444)),
        const SizedBox(height: 6),
        _miniRow('Price with GST', _money(gross)),
      ],
    );
  }

  Widget _miniRow(String label, String value, {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 16 : 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: color ?? const Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared bits
  // ---------------------------------------------------------------------------

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
        ),
      );

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}
