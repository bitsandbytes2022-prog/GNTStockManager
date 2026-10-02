import '../models/sale_model.dart';

/// One bill as it is printed in the monthly bill book — either a single sale
/// as-is, or several sales of the month combined into one bill by
/// [combineSalesIntoBills].
class BookBill {
  /// Printed bill number, e.g. `14`, or `14/2` for the second part of a sale
  /// that had to be split across bills.
  final String number;
  final DateTime date;
  final List<SaleItem> items;
  final double totalAmount;
  final double amountDue;
  final String paymentLabel;
  final String? buyerName;
  final String? buyerPhone;
  final String? buyerAddress;
  final String? notes;

  /// Invoice numbers of the original sales this bill covers, ascending.
  final List<int> sourceInvoices;

  const BookBill({
    required this.number,
    required this.date,
    required this.items,
    required this.totalAmount,
    required this.amountDue,
    required this.paymentLabel,
    this.buyerName,
    this.buyerPhone,
    this.buyerAddress,
    this.notes,
    required this.sourceInvoices,
  });

  factory BookBill.fromSale(Sale s) => BookBill(
        number: '${s.invoiceNumber}',
        date: s.createdAt,
        items: s.items,
        totalAmount: s.totalAmount,
        amountDue: s.isCredit ? s.amountDue : 0,
        paymentLabel: s.paymentMethod.label,
        buyerName: s.buyerName,
        buyerPhone: s.buyerPhone,
        buyerAddress: s.buyerAddress,
        notes: s.notes,
        sourceInvoices: [s.invoiceNumber],
      );

  bool get isCombined => sourceInvoices.length > 1;
  bool get hasBuyer =>
      (buyerName?.isNotEmpty ?? false) ||
      (buyerPhone?.isNotEmpty ?? false) ||
      (buyerAddress?.isNotEmpty ?? false);
}

/// Packs [sales] into as few bills as possible, each holding at most
/// [maxItems] line items.
///
/// - Identical lines (same product, size, rate and unit) from different
///   sales merge into one line with the quantities added, so they take only
///   one of a bill's [maxItems] slots.
/// - A sale with more than [maxItems] lines is split into parts; the parts
///   can then share bills with other sales like any other.
/// - With [separateBuyers] on, sales of different customers never share a
///   bill — only sales of the same customer (shopkeeper party, or the same
///   name/phone) combine, and walk-in sales with no buyer combine together.
///
/// Packing is best-fit-decreasing, which lands on the minimum bill count or
/// within one of it. Each bill is dated by its latest sale and numbered by
/// its highest original invoice number, so the book still reads in order.
List<BookBill> combineSalesIntoBills(
  List<Sale> sales, {
  int maxItems = 15,
  bool separateBuyers = true,
}) {
  assert(maxItems > 0);

  // 1. Break every sale into pieces of at most maxItems lines.
  final pieces = <_Piece>[];
  for (final sale in sales) {
    final lines = _mergeLines(sale.items);
    if (lines.isEmpty) continue;
    final partCount = (lines.length / maxItems).ceil();
    for (var p = 0; p < partCount; p++) {
      final chunk =
          lines.skip(p * maxItems).take(maxItems).toList(growable: false);
      final chunkTotal = chunk.fold<double>(0, (s, i) => s + i.total);
      final saleItemsTotal = sale.items.fold<double>(0, (s, i) => s + i.total);
      final share = saleItemsTotal > 0 ? chunkTotal / saleItemsTotal : 1 / partCount;
      pieces.add(_Piece(
        sale: sale,
        items: chunk,
        total: sale.totalAmount * share,
        due: (sale.isCredit ? sale.amountDue : 0) * share,
      ));
    }
  }

  // 2. Bin-pack the pieces, per buyer group.
  final byGroup = <String, List<_Piece>>{};
  for (final piece in pieces) {
    final key = separateBuyers ? _buyerKey(piece.sale) : '';
    byGroup.putIfAbsent(key, () => []).add(piece);
  }

  final bins = <_Bin>[];
  for (final group in byGroup.values) {
    group.sort((a, b) {
      final bySize = b.items.length.compareTo(a.items.length);
      return bySize != 0 ? bySize : a.sale.createdAt.compareTo(b.sale.createdAt);
    });
    final groupBins = <_Bin>[];
    for (final piece in group) {
      _Bin? best;
      var bestFree = maxItems + 1;
      for (final bin in groupBins) {
        final after = bin.lineCountWith(piece);
        if (after > maxItems) continue;
        final free = maxItems - after;
        // Tightest fit wins; on a tie, the bin whose sales are closest in
        // date keeps a bill's sales from being spread across the month.
        if (free < bestFree ||
            (free == bestFree &&
                best != null &&
                bin.dateGap(piece) < best.dateGap(piece))) {
          best = bin;
          bestFree = free;
        }
      }
      (best ?? (groupBins..add(_Bin())).last).add(piece);
    }
    bins.addAll(groupBins);
  }

  // 3. Turn bins into bills, in book order.
  final bills = bins.map((b) => b.toBill()).toList()
    ..sort((a, b) {
      final byNumber =
          a.sourceInvoices.last.compareTo(b.sourceInvoices.last);
      return byNumber != 0 ? byNumber : a.date.compareTo(b.date);
    });

  // Two parts of one split sale can both end up numbered after it; tell
  // them apart as 14/1, 14/2, ...
  final seen = <String, int>{};
  for (final b in bills) {
    seen[b.number] = (seen[b.number] ?? 0) + 1;
  }
  final counter = <String, int>{};
  return [
    for (final b in bills)
      if (seen[b.number]! > 1)
        BookBill(
          number: '${b.number}/${counter[b.number] = (counter[b.number] ?? 0) + 1}',
          date: b.date,
          items: b.items,
          totalAmount: b.totalAmount,
          amountDue: b.amountDue,
          paymentLabel: b.paymentLabel,
          buyerName: b.buyerName,
          buyerPhone: b.buyerPhone,
          buyerAddress: b.buyerAddress,
          notes: b.notes,
          sourceInvoices: b.sourceInvoices,
        )
      else
        b,
  ];
}

String _buyerKey(Sale s) {
  if (s.partyId?.isNotEmpty ?? false) return 'party:${s.partyId}';
  final name = (s.buyerName ?? '').trim().toLowerCase();
  final phone = (s.buyerPhone ?? '').replaceAll(RegExp(r'\D'), '');
  if (name.isEmpty && phone.isEmpty) return '';
  // Phone is the stronger identity; fall back to the name.
  return phone.isNotEmpty ? 'phone:$phone' : 'name:$name';
}

String _lineKey(SaleItem i) =>
    '${i.productId}|${i.productName}|${i.productSize}|'
    '${i.salePrice.toStringAsFixed(2)}|${i.isPerFoot}';

/// Merges identical lines (see [_lineKey]) by adding their quantities,
/// keeping first-seen order.
List<SaleItem> _mergeLines(Iterable<SaleItem> items) {
  final merged = <String, SaleItem>{};
  for (final it in items) {
    final key = _lineKey(it);
    final prev = merged[key];
    merged[key] = prev == null
        ? it
        : SaleItem(
            productId: prev.productId,
            productName: prev.productName,
            productSize: prev.productSize,
            purchasePrice: prev.purchasePrice,
            salePrice: prev.salePrice,
            quantity: prev.quantity + it.quantity,
            isPerFoot: prev.isPerFoot,
          );
  }
  return merged.values.toList();
}

class _Piece {
  final Sale sale;
  final List<SaleItem> items;
  final double total;
  final double due;

  _Piece({
    required this.sale,
    required this.items,
    required this.total,
    required this.due,
  });
}

class _Bin {
  final pieces = <_Piece>[];
  final _keys = <String>{};

  int lineCountWith(_Piece p) =>
      _keys.length + p.items.where((i) => !_keys.contains(_lineKey(i))).length;

  int dateGap(_Piece p) => pieces
      .map((x) => x.sale.createdAt.difference(p.sale.createdAt).inMinutes.abs())
      .reduce((a, b) => a < b ? a : b);

  void add(_Piece p) {
    pieces.add(p);
    _keys.addAll(p.items.map(_lineKey));
  }

  BookBill toBill() {
    pieces.sort((a, b) {
      final byDate = a.sale.createdAt.compareTo(b.sale.createdAt);
      return byDate != 0 ? byDate : a.sale.invoiceNumber.compareTo(b.sale.invoiceNumber);
    });
    final sales = <Sale>[];
    for (final p in pieces) {
      if (!sales.any((s) => s.id == p.sale.id)) sales.add(p.sale);
    }
    final invoices = sales.map((s) => s.invoiceNumber).toList()..sort();
    final latest = pieces
        .map((p) => p.sale.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final methods = <String>[];
    for (final s in sales) {
      if (!methods.contains(s.paymentMethod.label)) {
        methods.add(s.paymentMethod.label);
      }
    }
    final notes = <String>[];
    for (final s in sales) {
      final n = s.notes?.trim();
      if (n != null && n.isNotEmpty && !notes.contains(n)) notes.add(n);
    }
    Sale? buyer;
    for (final s in sales) {
      if (BookBill.fromSale(s).hasBuyer) {
        buyer = s;
        break;
      }
    }
    return BookBill(
      number: '${invoices.last}',
      date: latest,
      items: _mergeLines(pieces.expand((p) => p.items)),
      totalAmount: pieces.fold(0, (s, p) => s + p.total),
      amountDue: pieces.fold(0, (s, p) => s + p.due),
      paymentLabel: methods.join(' + '),
      buyerName: buyer?.buyerName,
      buyerPhone: buyer?.buyerPhone,
      buyerAddress: buyer?.buyerAddress,
      notes: notes.isEmpty ? null : notes.join('; '),
      sourceInvoices: invoices,
    );
  }
}
