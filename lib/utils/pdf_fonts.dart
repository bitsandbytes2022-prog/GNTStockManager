import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Fallback fonts for scripts the PDF package's built-in Helvetica can't
/// render (Devanagari/Gurmukhi) — customer names/addresses on bills are
/// often typed in Hindi or Punjabi. Loaded once and cached; pass the result
/// as `fontFallback` on a `pw.Document`'s theme so Latin text still uses the
/// default (smaller, no bundling needed) base font.
Future<List<pw.Font>>? _fallbackFontsFuture;

Future<List<pw.Font>> loadUnicodeFallbackFonts() {
  return _fallbackFontsFuture ??= Future.wait([
    rootBundle
        .load('assets/fonts/NotoSansDevanagari.ttf')
        .then(pw.Font.ttf),
    rootBundle
        .load('assets/fonts/NotoSansGurmukhi.ttf')
        .then(pw.Font.ttf),
  ]);
}
