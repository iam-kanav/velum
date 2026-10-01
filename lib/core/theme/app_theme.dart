import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightSurface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.light,
        surface: AppColors.lightSurface,
        onSurface: AppColors.inkBlack,
      ),
      textTheme: _buildTextTheme(AppColors.inkBlack, AppColors.stoneGrey),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.inkBlack),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkSurface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.dark,
        surface: AppColors.darkSurface,
        onSurface: AppColors.starlight,
      ),
      textTheme: _buildTextTheme(AppColors.starlight, AppColors.ash),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.starlight),
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
