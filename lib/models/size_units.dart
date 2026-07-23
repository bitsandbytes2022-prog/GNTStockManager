/// Default seed units. A size value is stored as a composed string,
/// e.g. "5 Liter", "750 ML", "20 MM", "3/4 Inch".
const List<String> kDefaultSizeUnits = ['Liter', 'ML', 'KG', 'Inch', 'MM'];

/// App-wide, runtime list of size units. Starts as the defaults and is replaced
/// with the saved units once loaded from Firestore (via FirebaseService.getUnits).
/// Used by [unitOf]/[valueOf] so size strings parse against custom units too.
List<String> sizeUnits = List<String>.from(kDefaultSizeUnits);

/// Compose a size value and unit into the canonical stored string.
String composeSize(String value, String? unit) {
  final v = value.trim();
  if (v.isEmpty) return '';
  if (unit == null || unit.isEmpty) return v;
  return '$v $unit';
}

/// Extract the unit from a composed size string (e.g. "200 ML" -> "ML",
/// "1 × 3/4 Inch" -> "Inch"). Returns null if no known unit is present.
String? unitOf(String size) {
  for (final u in sizeUnits) {
    if (size == u || size.endsWith(' $u')) return u;
  }
  return null;
}

/// Extract the value portion of a composed size string (everything except the
/// trailing unit). E.g. "200 ML" -> "200", "1 × 3/4 Inch" -> "1 × 3/4".
String valueOf(String size) {
  final u = unitOf(size);
  if (u == null) return size;
  return size.substring(0, size.length - u.length).trim();
}

/// Compose a reducer/adapter size with two values sharing one unit,
/// e.g. ("1", "3/4", "Inch") -> "1 × 3/4 Inch". Falls back to a single value
/// if either side is empty.
String composeReducerSize(String value1, String value2, String? unit) {
  final a = value1.trim();
  final b = value2.trim();
  if (a.isEmpty || b.isEmpty) {
    return composeSize(a.isEmpty ? b : a, unit);
  }
  final base = '$a × $b';
  if (unit == null || unit.isEmpty) return base;
  return '$base $unit';
}
