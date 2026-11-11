import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../motion/motion.dart';
import 'app_colors.dart';

class AppTheme {
  const AppTheme._();

  // Built once each: nothing in them changes, and a ThemeData is costly
  // to make.
  static final ThemeData lightTheme = _build(
    Brightness.light,
    surface: AppColors.lightSurface,
    primary: AppColors.inkBlack,
    secondary: AppColors.stoneGrey,
  );

  static final ThemeData darkTheme = _build(
    Brightness.dark,
    surface: AppColors.darkSurface,
    primary: AppColors.starlight,
    secondary: AppColors.ash,
  );

  static ThemeData _build(
    Brightness brightness, {
    required Color surface,
    required Color primary,
    required Color secondary,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: brightness,
        surface: surface,
        onSurface: primary,
      ),
      textTheme: _buildTextTheme(primary, secondary),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: MotionPageTransitionsBuilder(),
          TargetPlatform.macOS: MotionPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: primary),
      ),
    );
  }

  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    // Primary font for Body (Reading) - Merriweather (Serif)
    // Secondary font for UI - Inter (Sans-serif)

    final baseTextTheme = GoogleFonts.interTextTheme();
    final readingTextTheme = GoogleFonts.merriweatherTextTheme();

    return baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(color: primary),
      displayMedium: baseTextTheme.displayMedium?.copyWith(color: primary),
      displaySmall: baseTextTheme.displaySmall?.copyWith(color: primary),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(color: primary),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(color: primary),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(color: primary),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        color: primary,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        color: primary,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(color: primary),

      // Body text uses the Serif font for better reading experience
      bodyLarge: readingTextTheme.bodyLarge?.copyWith(
        color: primary,
        fontSize: 18,
        height: 1.6,
      ),
      bodyMedium: readingTextTheme.bodyMedium?.copyWith(
        color: secondary,
        fontSize: 16,
        height: 1.5,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(color: secondary),

      labelLarge: baseTextTheme.labelLarge?.copyWith(color: primary),
      labelMedium: baseTextTheme.labelMedium?.copyWith(color: secondary),
      labelSmall: baseTextTheme.labelSmall?.copyWith(color: secondary),
    );
  }
}
