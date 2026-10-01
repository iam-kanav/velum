import 'package:flutter/material.dart';

class AppColors {
  // Prevent instantiation
  const AppColors._();

  // Day Palette (Paper-like, warm, high readability)
  static const Color paperWhite = Color(0xFFF8F9FA); // Slightly off-white
  static const Color cream = Color(0xFFFDFBF7); // Warm paper
  static const Color inkBlack = Color(0xFF2D2D2D); // Softer than pure black
  static const Color stoneGrey = Color(0xFF5F6368); // Secondary text

  // Night Palette (OLED friendly but distinct)
  static const Color deepSpace = Color(0xFF121212); // AMOLED background
  static const Color charcoal = Color(0xFF1E1E1E); // Surface
  static const Color starlight = Color(0xFFE0E0E0); // Primary Text
  static const Color ash = Color(0xFFA0A0A0); // Secondary Text

  // Accents (Elegant, editorial)
  /// Brand accent: the violet from the app icon.
  static const Color accent = Color(0xFF5B3DE3);
  static const Color warmGold = Color(0xFFD4AF37);
  static const Color sageGreen = Color(0xFF7C9A92);

  // Semantic mappings
  static const Color lightSurface = cream;
  static const Color darkSurface = deepSpace;
}
