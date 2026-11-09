import '../models/product_model.dart';

// Product search that understands sizes. Searching "end cap 4" should find
// the 4 inch end cap — not every size with a 4 in it (3/4, 1/4, 40) — so
// numbers are matched as whole values ("1.5" = "1 1/2" = "1-1/2"), units are
// read loosely ('4"' = "4 inch" = "4in"), and results are ranked so an exact
// size match comes first. Words still match anywhere, with a typo allowed in
// longer ones.

/// Canonical unit for each spelling seen in product sizes.
const Map<String, String> _units = {
  '"': 'inch', 'in': 'inch', 'inch': 'inch', 'inches': 'inch', 'inchs': 'inch',
  'mm': 'mm', 'cm': 'cm',
  'm': 'meter', 'mtr': 'meter', 'meter': 'meter', 'meters': 'meter',
  'metre': 'meter', 'metres': 'meter',
  'ft': 'foot', 'foot': 'foot', 'feet': 'foot', "'": 'foot',
  'l': 'liter', 'lt': 'liter', 'ltr': 'liter', 'liter': 'liter',
  'liters': 'liter', 'litre': 'liter', 'litres': 'liter',
  'ml': 'ml',
  'kg': 'kg', 'kgs': 'kg', 'kilo': 'kg',
  'g': 'gram', 'gm': 'gram', 'gms': 'gram', 'gram': 'gram', 'grams': 'gram',
  'no': 'no', 'nos': 'no',
  'hp': 'hp',
};

/// Joiners in sizes like "1 × 3/4", "10*100", "2.5 x 12" — they separate
/// numbers but aren't searched on.
const Set<String> _joiners = {'x', '×', '*'};

/// A piece of searchable text, split into words and numeric values.
class _Parsed {
  final List<String> words;
  final List<double> numbers;
  final Set<String> units;

  _Parsed(this.words, this.numbers, this.units);

  static final _num = RegExp(r'^(\d+(?:\.\d+)?|\.\d+)(?:/(\d+(?:\.\d+)?))?$');
  static final _numThenUnit =
      RegExp(r'^(\d+(?:\.\d+)?(?:/\d+)?)([a-z]+|")$');

  static double? _value(String t) {
    final m = _num.firstMatch(t);
    if (m == null) return null;
    final a = double.parse(m.group(1)!);
    if (m.group(2) == null) return a;
    final b = double.parse(m.group(2)!);
    return b == 0 ? null : a / b;
  }

  /// [mergeMixed] reads "1 1/2" as one and a half; without it that's two
  /// numbers, as in a reducer typed "1 3/4" for size "1 × 3/4".
  factory _Parsed.of(String text, {bool mergeMixed = true}) {
    final s = text
        .toLowerCase()
        // "1-1/2" is one and a half, but "26-1000" (screw codes) is two.
        .replaceAllMapped(
            RegExp(r'(\d)-(\d+/\d+)'), (m) => '${m.group(1)} ${m.group(2)}')
        .replaceAll('"', ' " ')
        .replaceAll('×', ' × ')
        .replaceAll('*', ' * ')
        // "2.5x12" / "10x10" — an x between numbers is a joiner.
        .replaceAllMapped(RegExp(r'(\d)x(?=\d)'), (m) => '${m.group(1)} x ');

    final raw = s
        .split(RegExp(r'''[\s,;:()\[\]{}+\-_|\\!?#&]+'''))
        .where((t) => t.isNotEmpty);

    final tokens = <String>[];
    for (var t in raw) {
      t = t.replaceAll(RegExp(r'^\.+|\.+$'), '');
      if (t.isEmpty) continue;
      // "25mm", "1l", "4inch", '4"' — a number then its unit. Codes that
      // start with letters ("sl1", "iex6") stay whole words.
      final m = _numThenUnit.firstMatch(t);
      if (m != null && _units.containsKey(m.group(2))) {
        tokens..add(m.group(1)!)..add(m.group(2)!);
      } else {
        tokens.add(t);
      }
    }

    final words = <String>[];
    final numbers = <double>[];
    final units = <String>{};
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (_joiners.contains(t)) continue;
      final v = _value(t);
      if (v != null) {
        // "1 1/2" — a whole number then a proper fraction is one value.
        final next = i + 1 < tokens.length ? tokens[i + 1] : null;
        final frac = next != null && next.contains('/') ? _value(next) : null;
        if (mergeMixed &&
            !t.contains('/') &&
            !t.contains('.') &&
            frac != null &&
            frac < 1) {
          numbers.add(v + frac);
          i++;
        } else {
          numbers.add(v);
        }
        continue;
      }
      final unit = _units[t];
      if (unit != null) units.add(unit);
      if (t != '"' && t != "'") words.add(t);
    }
    return _Parsed(words, numbers, units);
  }
}

bool _sameValue(double a, double b) => (a - b).abs() < 1e-6;

/// Edit distance, giving up past [max] — enough to forgive one typo.
bool _withinEdits(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return false;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
      if (cur[j] < rowMin) rowMin = cur[j];
    }
    if (rowMin > max) return false;
    prev = cur;
  }
  return prev[b.length] <= max;
}

/// A parsed search box query, reusable across every product it's tested on.
class ProductSearchQuery {
  final String text;

  /// The query read with "1 1/2" as one value, and as two when that reads
  /// differently — a product matches if either does.
  final List<_Parsed> _readings;

  factory ProductSearchQuery(String query) {
    final merged = _Parsed.of(query);
    final split = _Parsed.of(query, mergeMixed: false);
    return ProductSearchQuery._(query.trim().toLowerCase(), [
      merged,
      if (split.numbers.length != merged.numbers.length) split,
    ]);
  }

  ProductSearchQuery._(this.text, this._readings);

  bool get isEmpty =>
      _readings.first.words.isEmpty && _readings.first.numbers.isEmpty;

  /// How well a product matches, or null when it doesn't. Every number in
  /// the query must be one of the product's sizes or a number in its name,
  /// and every word must start a word in the name, size or category — or,
  /// at four letters or more, appear anywhere in the name or be one typo
  /// off a word. Units only add to the score.
  int? score(String name, String size, {String category = '', String? subcategory}) {
    if (isEmpty) return 0;
    int? best;
    for (final q in _readings) {
      final s = _score(q, name, size, category, subcategory);
      if (s != null && (best == null || s > best)) best = s;
    }
    return best;
  }

  int? _score(_Parsed q, String name, String size, String category,
      String? subcategory) {
    final n = _Parsed.of(name);
    final sz = _Parsed.of(size);
    final nameText = name.toLowerCase();
    final nameJoined = nameText.replaceAll(RegExp(r'\s+'), '');
    final sizeText = size.toLowerCase();
    final catText = '$category ${subcategory ?? ''}'.toLowerCase();
    final catWords = _Parsed.of(catText).words;

    var score = 0;

    // Numbers: whole-value matches only.
    if (q.numbers.isNotEmpty) {
      final sizeNums = sz.numbers;
      final exactSize = sizeNums.length == q.numbers.length &&
          [for (var i = 0; i < sizeNums.length; i++) _sameValue(sizeNums[i], q.numbers[i])]
              .every((e) => e);
      if (exactSize) {
        score += 100;
      } else {
        final leftover = [...sizeNums];
        final nameNums = [...n.numbers];
        for (final v in q.numbers) {
          final i = leftover.indexWhere((s) => _sameValue(s, v));
          if (i >= 0) {
            // First number of a reducer size ("4 × 3") is its main size.
            score += i == 0 ? 40 : 25;
            leftover.removeAt(i);
            continue;
          }
          final j = nameNums.indexWhere((s) => _sameValue(s, v));
          if (j >= 0) {
            score += 20;
            nameNums.removeAt(j);
            continue;
          }
          return null;
        }
      }
    }

    // "end cap" for a product named "Endcap" — the words typed together.
    final together = q.words.length > 1 && nameJoined.contains(q.words.join());

    // Words: whole word, then start of a word, then anywhere, then a typo.
    for (final w in together ? const <String>[] : q.words) {
      final unit = _units[w];
      if (unit != null && (sz.units.contains(unit) || n.units.contains(unit))) {
        score += 5;
        continue;
      }
      if (n.words.contains(w)) {
        score += 15;
      } else if (n.words.any((t) => t.startsWith(w))) {
        score += 10;
      } else if (w.length >= 4 &&
          (nameText.contains(w) || nameJoined.contains(w))) {
        // Mid-word matches only for longer words, so "tee" doesn't find
        // "steel".
        score += 6;
      } else if (sizeText.contains(w)) {
        score += 5;
      } else if (catWords.any((t) => t.startsWith(w))) {
        score += 3;
      } else if (w.length >= 4 &&
          [...n.words, ...catWords]
              .any((t) => _withinEdits(w, t, w.length >= 8 ? 2 : 1))) {
        score += 2;
      } else if (unit != null) {
        // A unit the product doesn't spell out ("4 inch" vs size "4") —
        // don't rule the product out over it.
        continue;
      } else {
        return null;
      }
    }

    if (together) score += 6 * q.words.length;

    // The name starting with what was typed first reads as the best match.
    if (q.words.isNotEmpty && nameText.startsWith(q.words.first)) score += 4;
    return score;
  }
}

/// [items] that match [query], best match first. Items that match equally
/// keep their order, so the screen's own sort (newest, best sellers…)
/// still decides between them.
List<T> rankBySearch<T>(
  List<T> items,
  String query, {
  required String Function(T) name,
  required String Function(T) size,
  String Function(T)? category,
  String? Function(T)? subcategory,
}) {
  final q = ProductSearchQuery(query);
  if (q.isEmpty) return List<T>.from(items);
  final scored = <(int, int, T)>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final s = q.score(
      name(item),
      size(item),
      category: category?.call(item) ?? '',
      subcategory: subcategory?.call(item),
    );
    if (s != null) scored.add((s, i, item));
  }
  scored.sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2));
  return [for (final e in scored) e.$3];
}

/// [products] matching [query], best match first.
List<Product> searchProducts(List<Product> products, String query) =>
    rankBySearch<Product>(
      products,
      query,
      name: (p) => p.name,
      size: (p) => p.size,
      category: (p) => p.category,
      subcategory: (p) => p.subcategory,
    );
