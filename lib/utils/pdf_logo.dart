import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// The shop logo used on printed bills, loaded once and cached. Returns null
/// (rather than throwing) if the asset is missing, so a bill still prints
/// without a logo instead of failing outright.
Future<pw.ImageProvider?>? _shopLogoFuture;

Future<pw.ImageProvider?> loadShopLogo() {
  return _shopLogoFuture ??= rootBundle.load('assets/icons/ic_logo.png').then(
    (data) => pw.MemoryImage(data.buffer.asUint8List()),
    onError: (Object e) {
      debugPrint('Logo not found: $e');
      return null;
    },
  );
}
