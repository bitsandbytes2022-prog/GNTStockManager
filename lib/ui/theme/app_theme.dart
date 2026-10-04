import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Design tokens for the app's look, modelled on Zoho Inventory's site:
/// bright blue as the brand colour, coral for the main call to action, deep
/// navy for headings and the sidebar, airy light-grey pages with white
/// cards, 10px corners and soft shadows.
class AppColors {
  AppColors._();

  static const Color blue = Color(0xFF0089FB);
  static const Color blueLight = Color(0xFF03A9F5);
  static const Color blueTint = Color(0xFFE8F3FF);
  static const Color coral = Color(0xFFF0483E);
  static const Color navy = Color(0xFF0F254E);
  static const Color navyLight = Color(0xFF1B3566);
  static const Color green = Color(0xFF009C3E);
  static const Color amber = Color(0xFFFFAE00);
  static const Color red = Color(0xFFFA0011);

  static const Color page = Color(0xFFF5F7FA);
  static const Color card = Colors.white;
  static const Color border = Color(0xFFE5E8EC);
  static const Color text = Color(0xFF272727);
  static const Color textMuted = Color(0xFF6B7280);

  /// Zoho's four-colour brand strip.
  static const List<Color> stripe = [blue, green, amber, red];
}

class AppRadii {
  AppRadii._();
  static const double card = 10;
  static const double control = 8;
}

class AppShadows {
  AppShadows._();
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x26000000), blurRadius: 25, offset: Offset(0, 5)),
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
      scrolledUnderElevation: 1,
      shadowColor: const Color(0x14000000),
      titleTextStyle: text.titleLarge?.copyWith(
        color: AppColors.navy,
        fontWeight: FontWeight.w700,
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
      elevation: 2,
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
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.blue,
      unselectedLabelColor: AppColors.textMuted,
      indicatorColor: AppColors.blue,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      dividerColor: AppColors.border,
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
        borderRadius: BorderRadius.circular(14),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
