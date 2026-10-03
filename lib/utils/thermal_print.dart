import 'package:pdf/pdf.dart';

/// The thermal receipt layouts the shop prints. Page width is the printer's
/// printable width, not the nominal roll width — e.g. an "80mm" roll only
/// prints ~72mm wide, and a "57mm" roll ~48mm, once the printer's own side
/// margins are accounted for.
enum ThermalRollSize {
  mm80(
    pageWidthMm: 72,
    contentWidthMm: 62,
    label: 'Thermal Receipt (3" / 80mm)',
    subtitle: 'Thermal roll printer',
  ),
  mm57(
    pageWidthMm: 48,
    contentWidthMm: 38,
    label: 'Thermal Receipt (2" / 57mm)',
    subtitle: 'Thermal roll printer',
  ),

  /// A 57mm roll padded into the middle of an 80mm printer. The printer
  /// (and its driver) still think the paper is 80mm and start printing from
  /// the left edge of the full-width print head, so a plain 57mm-wide page
  /// lands on the left, mostly off the narrow paper. Instead the page is laid
  /// out at the 80mm printer's full printable width with the receipt
  /// content centred in it, plus a user-tunable offset since the taped-in
  /// roll is never perfectly centred.
  mm57In80(
    pageWidthMm: 72,
    contentWidthMm: 46,
    label: 'Thermal Receipt (57mm paper in 80mm printer)',
    subtitle: 'Receipt centred on the page',
    adjustable: true,
    // The paper sits slightly right of the print head's centre in practice.
    baseShiftMm: 6,
  );

  const ThermalRollSize({
    required this.pageWidthMm,
    required this.contentWidthMm,
    required this.label,
    required this.subtitle,
    this.adjustable = false,
    this.baseShiftMm = 0,
  });

  final double pageWidthMm;
  final double contentWidthMm;
  final String label;
  final String subtitle;

  /// Whether the content can be nudged left/right (see
  /// [thermalOffsetLimitMm]).
  final bool adjustable;

  /// Built-in left (negative) / right shift of the content, applied before
  /// the user's own offset.
  final double baseShiftMm;
}

/// How far (in mm, either direction) the centred content of an
/// [ThermalRollSize.adjustable] layout can be shifted.
const double thermalOffsetLimitMm = 10;

const double _verticalMarginMm = 5;

// Bottom margin of each chunk. The browser / printer driver can crop the
// last few mm of a page (a paper size slightly shorter than the chunk, or
// the printer's unprintable edge), which silently cut off the last line on
// a page — e.g. an item's qty x rate line under its name. Every chunk is
// a fixed height anyway, so keeping well clear of the edge only moves a
// little more content onto the next chunk.
const double _bottomSafetyMarginMm = 20;

// A long thermal receipt is built as several fixed-height chunks rather than
// one arbitrarily tall auto-sized page — a single extremely tall page gets
// silently clipped by the browser's print pipeline, while a continuous-roll
// printer prints sequential same-width pages back-to-back with no real gap.
// A4's height is a safe, universally supported page length to chunk at.
const double _chunkHeight = 297 * PdfPageFormat.mm;

/// Page format for one chunk of a thermal receipt. [offsetMm] shifts the
/// content right (positive) or left (negative) and only applies to
/// [ThermalRollSize.adjustable] layouts.
PdfPageFormat thermalPageFormat(ThermalRollSize size, {double offsetMm = 0}) {
  final side = (size.pageWidthMm - size.contentWidthMm) / 2;
  final userOffset = size.adjustable
      ? offsetMm.clamp(-thermalOffsetLimitMm, thermalOffsetLimitMm).toDouble()
      : 0.0;
  // Never push a margin below zero, however far base + user shift go.
  final offset = (size.baseShiftMm + userOffset).clamp(-side, side).toDouble();
  return PdfPageFormat(
    size.pageWidthMm * PdfPageFormat.mm,
    _chunkHeight,
    marginLeft: (side + offset) * PdfPageFormat.mm,
    marginRight: (side - offset) * PdfPageFormat.mm,
    marginTop: _verticalMarginMm * PdfPageFormat.mm,
    marginBottom: _bottomSafetyMarginMm * PdfPageFormat.mm,
  );
}
