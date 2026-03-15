import 'custom_font.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum ReaderTheme {
  light,
  dark,
  sepia;

  Color get backgroundColor {
    switch (this) {
      case ReaderTheme.light:
        return const Color(0xFFFAF9F6); // Off-white/Paper
      case ReaderTheme.dark:
        return const Color(0xFF1A1A1A); // Dark Grey
      case ReaderTheme.sepia:
        return const Color.fromARGB(
          255,
          230,
          223,
          202,
        ); // Lighter Warm Paper for better contrast
    }
  }

  Color get textColor {
    switch (this) {
      case ReaderTheme.light:
        return const Color(0xFF2D2D2D); // Almost Black
      case ReaderTheme.dark:
        // Slightly dim white for less eye strain
        return const Color(0xFFE0E0E0);
      case ReaderTheme.sepia:
        return const Color(0xFF2A1F1D); // Dark Coffee for sharp contrast
    }
  }

  String get displayName {
    switch (this) {
      case ReaderTheme.light:
        return 'Light';
      case ReaderTheme.dark:
        return 'Dark';
      case ReaderTheme.sepia:
        return 'Sepia';
    }
  }
}

enum ReaderFont {
  serif('Merriweather'),
  sans('Inter'),
  mono('Roboto Mono'),
  custom('Custom');

  final String fontFamily;
  const ReaderFont(this.fontFamily);
}

enum TextAlignment {
  left,
  justify;

  String get cssValue {
    switch (this) {
      case TextAlignment.left:
        return 'left';
      case TextAlignment.justify:
        return 'justify';
    }
  }

  String get displayName {
    switch (this) {
      case TextAlignment.left:
        return 'Left';
      case TextAlignment.justify:
        return 'Justify';
    }
  }
}

class ReaderSettings extends Equatable {
  final ReaderTheme
  appTheme; // Theme for app UI (Library, Settings, Reader overlays)
  final ReaderTheme readerTheme; // Theme for reading content (WebView)
  final ReaderFont font;
  final List<CustomFont> customFonts; // List of added custom fonts
  final String?
  selectedCustomFontId; // ID of the currently selected custom font
  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final TextAlignment textAlignment;
  final double horizontalMargin; // 0.0 – 40.0 px

  const ReaderSettings({
    this.appTheme = ReaderTheme.light,
    this.readerTheme = ReaderTheme.light,
    this.font = ReaderFont.serif,
    this.customFonts = const [],
    this.selectedCustomFontId,
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.paragraphSpacing = 1.2,
    this.textAlignment = TextAlignment.left,
    this.horizontalMargin = 20.0,
  });

  // Convenience getter for backward compatibility
  ReaderTheme get theme => readerTheme;

  ReaderSettings copyWith({
    ReaderTheme? appTheme,
    ReaderTheme? readerTheme,
    ReaderFont? font,
    List<CustomFont>? customFonts,
    String? selectedCustomFontId,
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    TextAlignment? textAlignment,
    double? horizontalMargin,
  }) {
    return ReaderSettings(
      appTheme: appTheme ?? this.appTheme,
      readerTheme: readerTheme ?? this.readerTheme,
      font: font ?? this.font,
      customFonts: customFonts ?? this.customFonts,
      selectedCustomFontId: selectedCustomFontId ?? this.selectedCustomFontId,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      textAlignment: textAlignment ?? this.textAlignment,
      horizontalMargin: horizontalMargin ?? this.horizontalMargin,
    );
  }

  @override
  List<Object?> get props => [
    appTheme,
    readerTheme,
    font,
    customFonts,
    selectedCustomFontId,
    fontSize,
    lineHeight,
    paragraphSpacing,
    textAlignment,
    horizontalMargin,
  ];
}
