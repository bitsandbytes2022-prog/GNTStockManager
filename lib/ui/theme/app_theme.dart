import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Design tokens for the app's look: a vivid violet brand colour with
/// hot-pink accents, deep indigo ink for headings and the sidebar, soft
/// lavender pages with white cards, and gradients for anything that should
/// catch the eye (headers, the New Sale button, selected tabs).
///
/// The names (blue, coral, navy…) are kept from the earlier palette so every
/// screen that already uses them picks up the new colours.
class AppColors {
  AppColors._();

  /// Brand violet.
  static const Color blue = Color(0xFF6D3CF5);
  static const Color blueLight = Color(0xFF9B6BFF);
  static const Color blueTint = Color(0xFFF0EBFF);

  /// Hot pink — the main call to action.
  static const Color coral = Color(0xFFFF3D77);

  /// Deep indigo ink.
  static const Color navy = Color(0xFF1E1B4B);
  static const Color navyLight = Color(0xFF312E81);
  static const Color green = Color(0xFF00A76F);
  static const Color amber = Color(0xFFFFB020);
  static const Color red = Color(0xFFF43F5E);

  static const Color page = Color(0xFFF6F5FC);
  static const Color card = Colors.white;
  static const Color border = Color(0xFFE8E5F4);
  static const Color text = Color(0xFF26233F);
  static const Color textMuted = Color(0xFF6E6B85);

  /// The thin brand strip along the top of the content.
  static const List<Color> stripe = [blue, Color(0xFFC026D3), coral];

  /// Stock level colours.
  static const Color stockOk = green;
  static const Color stockLow = Color(0xFFF59E0B);
  static const Color stockOut = Color(0xFFE5484D);

  /// One colour per product category, used for chips, badges and the quick
  /// category buttons everywhere — tuned to sit together with the brand
  /// palette.
  static Color category(String category) {
    switch (category.toLowerCase().trim()) {
      case 'ppr':
        return const Color(0xFF16A34A);
      case 'cpvc':
        return const Color(0xFFE08A00);
      case 'pvc':
        return const Color(0xFF0EA5E9);
      case 'gi':
      case 'galvanized':
        return const Color(0xFF64748B);
      case 'paints':
        return const Color(0xFF7C4DFF);
      case 'hardware':
        return const Color(0xFFF0483E);
      case 'adhesives':
        return const Color(0xFFD97706);
      case 'fittings':
        return const Color(0xFF0D9488);
      case 'electrical':
        return const Color(0xFFCA8A04);
      case 'plumbing':
        return blue;
      default:
        return const Color(0xFF475569);
    }
  }
}

/// The app's gradients. Each is a top-left → bottom-right sweep.
class AppGradients {
  AppGradients._();

  /// Headers and hero cards: deep violet into magenta.
  static const LinearGradient hero = LinearGradient(
    colors: [Color(0xFF4C1DB8), Color(0xFF7C3AED), Color(0xFFC026D3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Selected tabs and primary highlights.
  static const LinearGradient primary = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFF5B5BF7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// The main call to action (New Sale): sunset orange into hot pink.
  static const LinearGradient action = LinearGradient(
    colors: [Color(0xFFFF8A3D), Color(0xFFFF3D77)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient money = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF047857)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient ocean = LinearGradient(
    colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gold = LinearGradient(
    colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient rose = LinearGradient(
    colors: [Color(0xFFFB7185), Color(0xFFE11D48)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient slate = LinearGradient(
    colors: [Color(0xFF64748B), Color(0xFF334155)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// The desktop sidebar: deep indigo, a touch lighter at the bottom.
  static const LinearGradient sidebar = LinearGradient(
    colors: [Color(0xFF1E1B4B), Color(0xFF2E1065)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppRadii {
  AppRadii._();
  static const double card = 14;
  static const double control = 10;
}

class AppShadows {
  AppShadows._();
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F2E1065), blurRadius: 14, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x262E1065), blurRadius: 28, offset: Offset(0, 10)),
  ];

  /// A coloured glow under a gradient element.
  static List<BoxShadow> glow(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.38),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Motion timings — quick, so animation never slows down billing.
class AppMotion {
  AppMotion._();
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve curve = Curves.easeOutCubic;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.blue,
    onPrimary: Colors.white,
    secondary: AppColors.coral,
    onSecondary: Colors.white,
    tertiary: AppColors.green,
    error: AppColors.red,
    surface: AppColors.card,
    onSurface: AppColors.text,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.page,
  );
  final text = base.textTheme.apply(
    bodyColor: AppColors.text,
    displayColor: AppColors.navy,
  );

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.control),
  );
  const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
  final buttonText = text.labelLarge?.copyWith(
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.navy,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 2,
      shadowColor: const Color(0x1A2E1065),
      // Left-aligned bold page titles (web would otherwise
      // centre them on macOS/iOS).
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(
        color: AppColors.navy,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        shape: controlShape,
        padding: buttonPadding,
        textStyle: buttonText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: controlShape,
        padding: buttonPadding,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.blue,
        side: const BorderSide(color: AppColors.blue, width: 1.2),
        shape: controlShape,
        padding: buttonPadding,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.blue,
        shape: controlShape,
        textStyle: buttonText,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.coral,
      foregroundColor: Colors.white,
      elevation: 4,
      highlightElevation: 8,
      shape: StadiumBorder(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        borderSide: const BorderSide(color: AppColors.blue, width: 1.6),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: AppColors.blueTint,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      labelStyle: text.labelMedium,
    ),
    // Selected tab sits on a gradient pill.
    tabBarTheme: TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: AppColors.textMuted,
      // The white border insets the pill from the tab's edges (tab bars
      // sit on white app bars).
      indicator: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 5),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      dividerColor: Colors.transparent,
      splashBorderRadius: BorderRadius.circular(AppRadii.control),
      overlayColor: WidgetStatePropertyAll(
          AppColors.blue.withValues(alpha: 0.06)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.blueTint,
      elevation: 3,
      shadowColor: const Color(0x22000000),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.blue
                : AppColors.textMuted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          text.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.blue
                : AppColors.textMuted,
          )),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      titleTextStyle: text.titleLarge?.copyWith(
        color: AppColors.navy,
        fontWeight: FontWeight.w700,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.navy,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.navy),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.blue),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
