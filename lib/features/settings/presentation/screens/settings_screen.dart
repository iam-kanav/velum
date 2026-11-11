import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:velum/features/settings/data/models/custom_font.dart';
import 'package:velum/features/settings/data/models/reader_settings.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import 'package:velum/features/settings/presentation/widgets/reader_controls.dart';
import 'package:velum/features/library/presentation/providers/library_notifier.dart';
import 'package:velum/features/library/presentation/widgets/storage_access.dart';
import 'package:velum/core/theme/app_colors.dart';
import 'package:velum/features/notes/data/clipboard_listen.dart';

const Color _accent = AppColors.accent;

// The user's fonts that were loaded for the preview, by font id. (The
// reader doesn't need this: it uses the font files through CSS.)
final Map<String, Future<String?>> _previewFonts = {};

/// The family name [font] can be used under in the preview, or null if its
/// file can't be read.
Future<String?> _previewFamily(CustomFont font) =>
    _previewFonts[font.id] ??= () async {
      final family = 'custom_${font.id}';
      try {
        final bytes = await File(font.path).readAsBytes();
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        return family;
      } catch (_) {
        return null;
      }
    }();

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsNotifier = context.watch<SettingsNotifier>();
    final settings = settingsNotifier.settings;
    final appTheme = settings.appTheme;

    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: appTheme.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: appTheme.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ═══════════════════════════════════════════════════════════════
          // GLOBAL SETTINGS
          // ═══════════════════════════════════════════════════════════════
          _buildSectionHeader('Global Settings', appTheme),
          const SizedBox(height: 16),

          // App Theme
          _buildSettingsCard(
            appTheme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardTitle('App Theme', appTheme),
                const SizedBox(height: 4),
                Text(
                  'Theme for Library and Settings',
                  style: TextStyle(
                    fontSize: 12,
                    color: appTheme.textColor.withAlpha(150),
                  ),
                ),
                const SizedBox(height: 16),
                ThemeCircles(
                  selected: settings.appTheme,
                  onSelect: settingsNotifier.updateAppTheme,
                  labelColor: appTheme.textColor,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ═══════════════════════════════════════════════════════════════
          // LIBRARY SETTINGS
          // ═══════════════════════════════════════════════════════════════
          _buildSectionHeader('Library', appTheme),
          const SizedBox(height: 16),

          _buildLibrarySettingsCard(context, appTheme),

          const SizedBox(height: 32),

          if (ClipboardListen.isSupported) ...[
            _buildSectionHeader('Shortcuts', appTheme),
            const SizedBox(height: 16),
            _buildSettingsCard(
              appTheme,
              child: _ClipboardListenSetting(theme: appTheme),
            ),
            const SizedBox(height: 32),
          ],

          // ═══════════════════════════════════════════════════════════════
          // READER SETTINGS
          // ═══════════════════════════════════════════════════════════════
          _buildSectionHeader('Reader Settings', appTheme),
          const SizedBox(height: 16),

          // Reader Theme
          _buildSettingsCard(
            appTheme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardTitle('Reader Theme', appTheme),
                const SizedBox(height: 4),
                Text(
                  'Theme while reading books',
                  style: TextStyle(
                    fontSize: 12,
                    color: appTheme.textColor.withAlpha(150),
                  ),
                ),
                const SizedBox(height: 16),
                ThemeCircles(
                  selected: settings.readerTheme,
                  onSelect: settingsNotifier.updateReaderTheme,
                  labelColor: appTheme.textColor,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Typography Settings
          _buildSettingsCard(
            appTheme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardTitle('Typography', appTheme),
                const SizedBox(height: 20),

                // Font Family
                SettingLabel('Font Family', theme: appTheme),
                const SizedBox(height: 12),
                FontChips(notifier: settingsNotifier, theme: appTheme),

                const SizedBox(height: 24),

                TypographySliders(notifier: settingsNotifier, theme: appTheme),

                const SizedBox(height: 20),

                SettingLabel('Text Alignment', theme: appTheme),
                const SizedBox(height: 12),
                TextAlignmentChips(notifier: settingsNotifier, theme: appTheme),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Preview
          _buildSettingsCard(
            appTheme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardTitle('Preview', appTheme),
                const SizedBox(height: 16),
                _buildLivePreview(settings),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Chapter Swipe
          _buildSettingsCard(
            appTheme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardTitle('Chapter Swipe', appTheme),
                const SizedBox(height: 4),
                Text(
                  'How far to swipe sideways to change chapter. Shorter is '
                  'easier; longer avoids changing chapter by accident.',
                  style: TextStyle(
                    fontSize: 12,
                    color: appTheme.textColor.withAlpha(150),
                  ),
                ),
                const SizedBox(height: 16),
                SettingSlider(
                  label: 'Swipe Distance',
                  valueLabel:
                      '${(settings.chapterSwipeDistance * 100).round()}% of screen',
                  value: settings.chapterSwipeDistance,
                  min: 0.10,
                  max: 0.40,
                  divisions: 15,
                  onChanged: settingsNotifier.updateChapterSwipeDistance,
                  theme: appTheme,
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildLibrarySettingsCard(BuildContext context, ReaderTheme appTheme) {
    final libraryNotifier = context.watch<LibraryNotifier>();

    return _buildSettingsCard(
      appTheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardTitle('Auto-Detect EPUBs', appTheme),
          const SizedBox(height: 4),
          Text(
            'Automatically scan your device for EPUB files',
            style: TextStyle(
              fontSize: 12,
              color: appTheme.textColor.withAlpha(150),
            ),
          ),
          const SizedBox(height: 16),
          // Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Auto-scan on startup',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: appTheme.textColor.withAlpha(200),
                ),
              ),
              Switch(
                value: libraryNotifier.isAutoScanEnabled,
                activeThumbColor: _accent,
                onChanged: (value) async {
                  if (value && !await requestStorageAccess(context)) return;
                  await libraryNotifier.setAutoScanEnabled(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Scan Now button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: libraryNotifier.isScanning
                  ? null
                  : () async {
                      if (!await requestStorageAccess(context)) return;
                      final found = await libraryNotifier.scanDevice();
                      if (found != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              found == 0
                                  ? 'No new books found'
                                  : 'Found $found new book${found == 1 ? '' : 's'}',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: const BorderSide(color: _accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: libraryNotifier.isScanning
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accent.withAlpha(150),
                      ),
                    )
                  : const Icon(Icons.manage_search, size: 20),
              label: Text(
                libraryNotifier.isScanning
                    ? 'Scanning... (${libraryNotifier.scanProgress} found)'
                    : 'Scan Now',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (libraryNotifier.books.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${booksLabel(libraryNotifier.books.length)} in library',
              style: TextStyle(
                fontSize: 12,
                color: appTheme.textColor.withAlpha(120),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionHeader(String title, ReaderTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: theme.textColor.withAlpha(120),
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(ReaderTheme theme, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _getCardColor(theme),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme == ReaderTheme.dark
              ? Colors.white.withAlpha(10)
              : Colors.black.withAlpha(5),
        ),
      ),
      child: child,
    );
  }

  Widget _buildCardTitle(String title, ReaderTheme theme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: theme.textColor,
      ),
    );
  }

  Widget _buildLivePreview(ReaderSettings settings) {
    final readerTheme = settings.readerTheme;
    final customFont = settings.font == ReaderFont.custom
        ? settings.customFonts
              .where((font) => font.id == settings.selectedCustomFontId)
              .firstOrNull
        : null;
    Widget sample(String? fontFamily) => Text(
      'The quick brown fox jumps over the lazy dog.\n\n'
      'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
      'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
      style: _previewTextStyle(
        settings,
        readerTheme,
      ).copyWith(fontFamily: fontFamily),
    );

    return Container(
      height: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: readerTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withAlpha(40), width: 1),
      ),
      child: SingleChildScrollView(
        child: customFont == null
            ? sample(null)
            : FutureBuilder<String?>(
                future: _previewFamily(customFont),
                builder: (context, loaded) => sample(loaded.data),
              ),
      ),
    );
  }

  TextStyle _previewTextStyle(
    ReaderSettings settings,
    ReaderTheme readerTheme,
  ) {
    final base = TextStyle(
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      color: readerTheme.textColor,
    );
    switch (settings.font) {
      case ReaderFont.serif:
        return GoogleFonts.merriweather(textStyle: base);
      case ReaderFont.sans:
        return GoogleFonts.inter(textStyle: base);
      case ReaderFont.mono:
        return GoogleFonts.robotoMono(textStyle: base);
      case ReaderFont.custom:
        return base;
    }
  }

  Color _getCardColor(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.dark:
        return const Color(0xFF252525);
      case ReaderTheme.sepia:
        return const Color(0xFFEDE4D3);
      case ReaderTheme.light:
        return Colors.white;
    }
  }
}

/// Turns the "Listen to clipboard" notification on or off.
class _ClipboardListenSetting extends StatefulWidget {
  final ReaderTheme theme;

  const _ClipboardListenSetting({required this.theme});

  @override
  State<_ClipboardListenSetting> createState() =>
      _ClipboardListenSettingState();
}

class _ClipboardListenSettingState extends State<_ClipboardListenSetting> {
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    ClipboardListen.isEnabled().then((enabled) {
      if (mounted) setState(() => _enabled = enabled);
    });
  }

  Future<void> _set(bool enabled) async {
    if (enabled && !await Permission.notification.request().isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Allow notifications to use this shortcut'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    await ClipboardListen.setEnabled(enabled);
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Listen to Clipboard',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.textColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Keeps a notification in your shade. Tap it to save what you last '
          'copied as a note and hear it read aloud, without leaving the app '
          "you're in.",
          style: TextStyle(fontSize: 12, color: theme.textColor.withAlpha(150)),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Show notification',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.textColor.withAlpha(200),
              ),
            ),
            Switch(value: _enabled, activeThumbColor: _accent, onChanged: _set),
          ],
        ),
      ],
    );
  }
}
