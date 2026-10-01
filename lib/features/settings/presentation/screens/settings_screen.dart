import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:velum/features/settings/data/models/reader_settings.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import 'package:velum/features/library/presentation/providers/library_notifier.dart';
import 'package:velum/core/theme/app_colors.dart';

const Color _accent = AppColors.accent;

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
                _buildThemeRow(
                  settings.appTheme,
                  appTheme,
                  (theme) => settingsNotifier.updateAppTheme(theme),
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
                _buildThemeRow(
                  settings.readerTheme,
                  appTheme,
                  (theme) => settingsNotifier.updateReaderTheme(theme),
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
                _buildSettingLabel('Font Family', appTheme),
                const SizedBox(height: 12),
                _buildFontChips(settingsNotifier, appTheme),

                const SizedBox(height: 24),

                // Font Size
                _buildSliderRow(
                  'Font Size',
                  '${settings.fontSize.toInt()}px',
                  settings.fontSize,
                  12,
                  32,
                  10,
                  (val) => settingsNotifier.updateFontSize(val),
                  appTheme,
                ),

                const SizedBox(height: 20),

                // Line Height
                _buildSliderRow(
                  'Line Height',
                  settings.lineHeight.toStringAsFixed(1),
                  settings.lineHeight,
                  1.0,
                  2.5,
                  15,
                  (val) => settingsNotifier.updateLineHeight(val),
                  appTheme,
                ),
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
                  if (value) {
                    final granted = await libraryNotifier
                        .requestStoragePermission();
                    if (!granted) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Storage permission is required for auto-scan',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      return;
                    }
                  }
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
                      final granted = await libraryNotifier
                          .hasStoragePermission();
                      if (!granted) {
                        final result = await libraryNotifier
                            .requestStoragePermission();
                        if (!result) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Storage permission is required to scan',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                          return;
                        }
                      }
                      await libraryNotifier.scanDevice();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Found ${libraryNotifier.books.length} books',
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
              '${libraryNotifier.books.length} book${libraryNotifier.books.length == 1 ? '' : 's'} in library',
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

  Widget _buildSettingLabel(String label, ReaderTheme theme) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: theme.textColor.withAlpha(200),
      ),
    );
  }

  Widget _buildThemeRow(
    ReaderTheme selectedTheme,
    ReaderTheme displayTheme,
    void Function(ReaderTheme) onSelect,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: ReaderTheme.values.map((theme) {
        final isSelected = selectedTheme == theme;
        return GestureDetector(
          onTap: () => onSelect(theme),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.backgroundColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? _accent
                        : Colors.grey.withAlpha(60),
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _accent.withAlpha(60),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Aa',
                    style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                theme.displayName,
                style: TextStyle(
                  fontSize: 11,
                  color: displayTheme.textColor.withAlpha(
                    isSelected ? 255 : 150,
                  ),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFontChips(SettingsNotifier notifier, ReaderTheme theme) {
    final settings = notifier.settings;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ...ReaderFont.values.where((f) => f != ReaderFont.custom).map((font) {
          final isSelected = settings.font == font;
          final displayName = font == ReaderFont.serif
              ? 'Serif'
              : font == ReaderFont.sans
              ? 'Sans Serif'
              : 'Monospace';
          return GestureDetector(
            onTap: () => notifier.updateFont(font),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? _accent : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? _accent : Colors.grey.withAlpha(80),
                  width: 1.5,
                ),
              ),
              child: Text(
                displayName,
                style: _fontChipStyle(font, isSelected, theme),
              ),
            ),
          );
        }),
        // Custom Font Chips
        ...settings.customFonts.map((customFont) {
          final isSelected =
              settings.font == ReaderFont.custom &&
              settings.selectedCustomFontId == customFont.id;
          return GestureDetector(
            onTap: () => notifier.selectCustomFont(customFont.id),
            onLongPress: () => notifier.removeCustomFont(customFont.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? _accent : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? _accent : Colors.grey.withAlpha(80),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    customFont.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? Colors.white : theme.textColor,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => notifier.removeCustomFont(customFont.id),
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        // Add Font Button
        GestureDetector(
          onTap: () => notifier.importCustomFont(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.textColor.withAlpha(60),
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16, color: theme.textColor),
                const SizedBox(width: 4),
                Text(
                  'Add',
                  style: TextStyle(fontSize: 13, color: theme.textColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _fontChipStyle(
    ReaderFont font,
    bool isSelected,
    ReaderTheme theme,
  ) {
    final color = isSelected ? Colors.white : theme.textColor;
    final weight = isSelected ? FontWeight.w600 : FontWeight.normal;
    switch (font) {
      case ReaderFont.serif:
        return GoogleFonts.merriweather(
          fontSize: 13, color: color, fontWeight: weight);
      case ReaderFont.sans:
        return GoogleFonts.inter(
          fontSize: 13, color: color, fontWeight: weight);
      case ReaderFont.mono:
        return GoogleFonts.robotoMono(
          fontSize: 13, color: color, fontWeight: weight);
      case ReaderFont.custom:
        return TextStyle(fontSize: 13, color: color, fontWeight: weight);
    }
  }

  Widget _buildSliderRow(
    String label,
    String value,
    double currentValue,
    double min,
    double max,
    int divisions,
    void Function(double) onChanged,
    ReaderTheme theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSettingLabel(label, theme),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme == ReaderTheme.dark
                    ? Colors.white.withAlpha(15)
                    : Colors.black.withAlpha(8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.textColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: _accent,
            inactiveTrackColor: Colors.grey.withAlpha(60),
            thumbColor: _accent,
            overlayColor: _accent.withAlpha(30),
            trackHeight: 4,
          ),
          child: Slider(
            value: currentValue,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildLivePreview(ReaderSettings settings) {
    final readerTheme = settings.readerTheme;

    return Container(
      height: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: readerTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withAlpha(40), width: 1),
      ),
      child: SingleChildScrollView(
        child: Text(
          'The quick brown fox jumps over the lazy dog.\n\n'
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
          'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
          style: _previewTextStyle(settings, readerTheme),
        ),
      ),
    );
  }

  TextStyle _previewTextStyle(ReaderSettings settings, ReaderTheme readerTheme) {
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
