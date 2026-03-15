import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../../data/models/reader_settings.dart';
import '../../data/models/custom_font.dart';

class SettingsNotifier extends ChangeNotifier {
  static const String _appThemeKey = 'app_theme';
  static const String _readerThemeKey = 'reader_theme';
  static const String _fontKey = 'font';
  static const String _fontSizeKey = 'font_size';
  static const String _lineHeightKey = 'line_height';
  static const String _customFontsKey = 'custom_fonts_list';
  static const String _selectedCustomFontIdKey = 'selected_custom_font_id';
  static const String _paragraphSpacingKey = 'paragraph_spacing';
  static const String _textAlignmentKey = 'text_alignment';
  static const String _horizontalMarginKey = 'horizontal_margin';

  final SharedPreferences _prefs;
  ReaderSettings _settings = const ReaderSettings();
  ReaderSettings get settings => _settings;

  SettingsNotifier(this._prefs) {
    _loadSettings();
  }

  void _loadSettings() {
    // Default to dark theme if the system is in dark mode, otherwise light
    final systemDefault =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark
            ? ReaderTheme.dark.index
            : ReaderTheme.light.index;

    final appThemeIndex = _prefs.getInt(_appThemeKey) ?? systemDefault;
    final readerThemeIndex = _prefs.getInt(_readerThemeKey) ?? systemDefault;
    final fontIndex = _prefs.getInt(_fontKey) ?? 0;
    final fontSize = _prefs.getDouble(_fontSizeKey) ?? 18.0;
    final lineHeight = _prefs.getDouble(_lineHeightKey) ?? 1.6;
    final paragraphSpacing = _prefs.getDouble(_paragraphSpacingKey) ?? 1.2;
    final textAlignmentIndex = _prefs.getInt(_textAlignmentKey) ?? 0;
    final horizontalMargin = _prefs.getDouble(_horizontalMarginKey) ?? 20.0;

    // Load custom fonts
    List<CustomFont> customFonts = [];
    final customFontsJson = _prefs.getString(_customFontsKey);
    if (customFontsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(customFontsJson);
        customFonts = decoded.map((e) => CustomFont.fromJson(e)).toList();
      } catch (e) {
        debugPrint('Error loading custom fonts: $e');
      }
    }

    final selectedCustomFontId = _prefs.getString(_selectedCustomFontIdKey);

    _settings = ReaderSettings(
      appTheme: ReaderTheme
          .values[appThemeIndex.clamp(0, ReaderTheme.values.length - 1)],
      readerTheme: ReaderTheme
          .values[readerThemeIndex.clamp(0, ReaderTheme.values.length - 1)],
      font: ReaderFont.values[fontIndex.clamp(0, ReaderFont.values.length - 1)],
      customFonts: customFonts,
      selectedCustomFontId: selectedCustomFontId,
      fontSize: fontSize.clamp(12.0, 32.0),
      lineHeight: lineHeight.clamp(1.0, 2.5),
      paragraphSpacing: paragraphSpacing.clamp(0.0, 3.0),
      textAlignment: TextAlignment.values[textAlignmentIndex.clamp(0, TextAlignment.values.length - 1)],
      horizontalMargin: horizontalMargin.clamp(0.0, 40.0),
    );
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    // Batch all writes in parallel instead of sequential awaits
    final futures = <Future>[
      _prefs.setInt(_appThemeKey, _settings.appTheme.index),
      _prefs.setInt(_readerThemeKey, _settings.readerTheme.index),
      _prefs.setInt(_fontKey, _settings.font.index),
      _prefs.setDouble(_fontSizeKey, _settings.fontSize),
      _prefs.setDouble(_lineHeightKey, _settings.lineHeight),
      _prefs.setDouble(_paragraphSpacingKey, _settings.paragraphSpacing),
      _prefs.setInt(_textAlignmentKey, _settings.textAlignment.index),
      _prefs.setDouble(_horizontalMarginKey, _settings.horizontalMargin),
      _prefs.setString(
        _customFontsKey,
        jsonEncode(_settings.customFonts.map((e) => e.toJson()).toList()),
      ),
      if (_settings.selectedCustomFontId != null)
        _prefs.setString(
          _selectedCustomFontIdKey,
          _settings.selectedCustomFontId!,
        )
      else
        _prefs.remove(_selectedCustomFontIdKey),
    ];
    await Future.wait(futures);
  }

  void updateAppTheme(ReaderTheme theme) {
    _settings = _settings.copyWith(appTheme: theme);
    _saveSettings();
    notifyListeners();
  }

  void updateReaderTheme(ReaderTheme theme) {
    _settings = _settings.copyWith(readerTheme: theme);
    _saveSettings();
    notifyListeners();
  }

  // Legacy method for backward compatibility
  void updateTheme(ReaderTheme theme) {
    updateReaderTheme(theme);
  }

  void updateFont(ReaderFont font) {
    _settings = _settings.copyWith(font: font);
    _saveSettings();
    notifyListeners();
  }

  /// Import a custom font file (TTF or OTF)
  Future<void> importCustomFont() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
      );

      if (result != null && result.files.single.path != null) {
        final sourceFile = File(result.files.single.path!);
        final appDir = await getApplicationDocumentsDirectory();

        // Use UUID for unique filename to prevent collisions
        final id = const Uuid().v4();
        final fileName = 'font_$id${path.extension(sourceFile.path)}';

        // Extract original name for display, e.g. "MyFont-Bold.ttf" -> "MyFont-Bold"
        final originalName = path.basenameWithoutExtension(sourceFile.path);

        final savedFile = await sourceFile.copy(
          path.join(appDir.path, fileName),
        );

        final newFont = CustomFont(
          id: id,
          name: originalName,
          path: savedFile.path,
        );

        final updatedList = List<CustomFont>.from(_settings.customFonts)
          ..add(newFont);

        _settings = _settings.copyWith(
          font: ReaderFont.custom,
          customFonts: updatedList,
          selectedCustomFontId: id,
        );
        await _saveSettings();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error importing font: $e');
    }
  }

  void selectCustomFont(String id) {
    if (_settings.customFonts.any((f) => f.id == id)) {
      _settings = _settings.copyWith(
        font: ReaderFont.custom,
        selectedCustomFontId: id,
      );
      _saveSettings();
      notifyListeners();
    }
  }

  Future<void> removeCustomFont(String id) async {
    final fontIndex = _settings.customFonts.indexWhere((f) => f.id == id);
    if (fontIndex != -1) {
      final font = _settings.customFonts[fontIndex];

      // Delete file
      try {
        final file = File(font.path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting font file: $e');
      }

      final updatedList = List<CustomFont>.from(_settings.customFonts)
        ..removeAt(fontIndex);

      String? newSelectedId = _settings.selectedCustomFontId;
      ReaderFont newFont = _settings.font;

      // If we removed the selected font...
      if (_settings.selectedCustomFontId == id) {
        if (updatedList.isNotEmpty) {
          // Select the last one in the list
          newSelectedId = updatedList.last.id;
        } else {
          // Fallback to Serif if no custom fonts left
          newSelectedId = null;
          newFont = ReaderFont.serif;
        }
      }

      _settings = _settings.copyWith(
        customFonts: updatedList,
        selectedCustomFontId: newSelectedId,
        font: newFont,
      );
      await _saveSettings();
      notifyListeners();
    }
  }

  void updateFontSize(double size) {
    // Clamp size for sanity
    size = size.clamp(12.0, 32.0);
    _settings = _settings.copyWith(fontSize: size);
    _saveSettings();
    notifyListeners();
  }

  void updateLineHeight(double height) {
    height = height.clamp(1.0, 2.5);
    _settings = _settings.copyWith(lineHeight: height);
    _saveSettings();
    notifyListeners();
  }

  void updateParagraphSpacing(double spacing) {
    spacing = spacing.clamp(0.0, 3.0);
    _settings = _settings.copyWith(paragraphSpacing: spacing);
    _saveSettings();
    notifyListeners();
  }

  void updateTextAlignment(TextAlignment alignment) {
    _settings = _settings.copyWith(textAlignment: alignment);
    _saveSettings();
    notifyListeners();
  }

  void updateHorizontalMargin(double margin) {
    margin = margin.clamp(0.0, 40.0);
    _settings = _settings.copyWith(horizontalMargin: margin);
    _saveSettings();
    notifyListeners();
  }
}
