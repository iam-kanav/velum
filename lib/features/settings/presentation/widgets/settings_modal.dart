import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../data/models/reader_settings.dart';
import '../providers/settings_notifier.dart';
import '../../../tts/presentation/widgets/tts_settings_section.dart';
import 'package:velum/core/theme/app_colors.dart';

const Color _accent = AppColors.accent;

class SettingsModal extends StatefulWidget {
  const SettingsModal({super.key});

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  int _currentPage = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsNotifier>().settings;
    final readerTheme = settings.readerTheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: readerTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar and tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: readerTheme.textColor.withAlpha(60),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Tab selector
                _buildTabSelector(readerTheme),
              ],
            ),
          ),

          // Page content
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentPage = index),
              children: [
                _buildTtsSettings(readerTheme),
                _buildReaderSettings(context, readerTheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(ReaderTheme theme) {
    return Row(
      children: [
        _buildTab('Text-to-Speech', 0, Icons.record_voice_over, theme),
        const SizedBox(width: 12),
        _buildTab('Reader', 1, Icons.auto_stories, theme),
      ],
    );
  }

  Widget _buildTab(String label, int index, IconData icon, ReaderTheme theme) {
    final isSelected = _currentPage == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _accent.withAlpha(30) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? _accent : theme.textColor.withAlpha(40),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? _accent
                    : theme.textColor.withAlpha(150),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? _accent
                      : theme.textColor.withAlpha(200),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderSettings(BuildContext context, ReaderTheme readerTheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Theme Selector
          Text(
            'Reader Theme',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: readerTheme.textColor,
            ),
          ),
          const SizedBox(height: 12),
          Consumer<SettingsNotifier>(
            builder: (context, notifier, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ReaderTheme.values.map((theme) {
                  final isSelected = notifier.settings.readerTheme == theme;
                  return GestureDetector(
                    onTap: () => notifier.updateReaderTheme(theme),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: theme.backgroundColor,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: _accent, width: 2.5)
                            : Border.all(color: Colors.grey.withAlpha(60)),
                        boxShadow: [
                          if (isSelected)
                            BoxShadow(
                              color: _accent.withAlpha(50),
                              blurRadius: 8,
                            ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Aa',
                          style: TextStyle(
                            color: theme.textColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),

          // Font Selector
          Text(
            'Font',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: readerTheme.textColor,
            ),
          ),
          const SizedBox(height: 12),
          Consumer<SettingsNotifier>(
            builder: (context, notifier, _) {
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ...ReaderFont.values.where((f) => f != ReaderFont.custom).map(
                    (font) {
                      final isSelected = notifier.settings.font == font;
                      return GestureDetector(
                        onTap: () => notifier.updateFont(font),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? _accent
                                  : readerTheme.textColor.withAlpha(60),
                            ),
                          ),
                          child: Text(
                            font == ReaderFont.serif
                                ? 'Serif'
                                : font == ReaderFont.sans
                                ? 'Sans'
                                : 'Mono',
                            style: _fontChipStyle(
                              font,
                              isSelected,
                              readerTheme,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Custom Font Chips
                  ...notifier.settings.customFonts.map((customFont) {
                    final isSelected =
                        notifier.settings.font == ReaderFont.custom &&
                        notifier.settings.selectedCustomFontId == customFont.id;
                    return GestureDetector(
                      onTap: () => notifier.selectCustomFont(customFont.id),
                      onLongPress: () {
                        // Show delete dialog or delete directly
                        notifier.removeCustomFont(customFont.id);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? _accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? _accent
                                : readerTheme.textColor.withAlpha(60),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              customFont.name,
                              style: TextStyle(
                                fontSize: 13,
                                color: isSelected
                                    ? Colors.white
                                    : readerTheme.textColor,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () =>
                                    notifier.removeCustomFont(customFont.id),
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: readerTheme.textColor.withAlpha(60),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add,
                            size: 16,
                            color: readerTheme.textColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Add',
                            style: TextStyle(
                              fontSize: 13,
                              color: readerTheme.textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Size Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Size',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: readerTheme.textColor,
                ),
              ),
              Consumer<SettingsNotifier>(
                builder: (context, notifier, _) {
                  return Text(
                    '${notifier.settings.fontSize.toInt()}px',
                    style: TextStyle(color: readerTheme.textColor),
                  );
                },
              ),
            ],
          ),
          Consumer<SettingsNotifier>(
            builder: (context, notifier, _) {
              return SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: _accent,
                  inactiveTrackColor: readerTheme.textColor.withAlpha(40),
                  thumbColor: _accent,
                ),
                child: Slider(
                  value: notifier.settings.fontSize,
                  min: 12,
                  max: 32,
                  divisions: 10,
                  onChanged: (val) => notifier.updateFontSize(val),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Line Height Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Line Height',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: readerTheme.textColor,
                ),
              ),
              Consumer<SettingsNotifier>(
                builder: (context, notifier, _) {
                  return Text(
                    notifier.settings.lineHeight.toStringAsFixed(1),
                    style: TextStyle(color: readerTheme.textColor),
                  );
                },
              ),
            ],
          ),
          Consumer<SettingsNotifier>(
            builder: (context, notifier, _) {
              return SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: _accent,
                  inactiveTrackColor: readerTheme.textColor.withAlpha(40),
                  thumbColor: _accent,
                ),
                child: Slider(
                  value: notifier.settings.lineHeight,
                  min: 1.0,
                  max: 2.5,
                  divisions: 15,
                  onChanged: (val) => notifier.updateLineHeight(val),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Paragraph Spacing Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Paragraph Spacing',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: readerTheme.textColor,
                ),
              ),
              Consumer<SettingsNotifier>(
                builder: (context, notifier, _) {
                  return Text(
                    notifier.settings.paragraphSpacing.toStringAsFixed(1),
                    style: TextStyle(color: readerTheme.textColor),
                  );
                },
              ),
            ],
          ),
          Consumer<SettingsNotifier>(
            builder: (context, notifier, _) {
              return SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: _accent,
                  inactiveTrackColor: readerTheme.textColor.withAlpha(40),
                  thumbColor: _accent,
                ),
                child: Slider(
                  value: notifier.settings.paragraphSpacing,
                  min: 0.0,
                  max: 3.0,
                  divisions: 30,
                  onChanged: (val) => notifier.updateParagraphSpacing(val),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Horizontal Margin Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Margins',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: readerTheme.textColor,
                ),
              ),
              Consumer<SettingsNotifier>(
                builder: (context, notifier, _) {
                  return Text(
                    '${notifier.settings.horizontalMargin.toInt()}px',
                    style: TextStyle(color: readerTheme.textColor),
                  );
                },
              ),
            ],
          ),
          Consumer<SettingsNotifier>(
            builder: (context, notifier, _) {
              return SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: _accent,
                  inactiveTrackColor: readerTheme.textColor.withAlpha(40),
                  thumbColor: _accent,
                ),
                child: Slider(
                  value: notifier.settings.horizontalMargin,
                  min: 0,
                  max: 40,
                  divisions: 8,
                  onChanged: (val) => notifier.updateHorizontalMargin(val),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Text Alignment
          Text(
            'Text Alignment',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: readerTheme.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Consumer<SettingsNotifier>(
            builder: (context, notifier, _) {
              return Row(
                children: TextAlignment.values.map((alignment) {
                  final isSelected = notifier.settings.textAlignment == alignment;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => notifier.updateTextAlignment(alignment),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? _accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? _accent : readerTheme.textColor.withAlpha(60),
                          ),
                        ),
                        child: Text(
                          alignment.displayName,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected ? Colors.white : readerTheme.textColor,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  TextStyle _fontChipStyle(
    ReaderFont font,
    bool isSelected,
    ReaderTheme readerTheme,
  ) {
    final color = isSelected ? Colors.white : readerTheme.textColor;
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

  Widget _buildTtsSettings(ReaderTheme readerTheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: TtsSettingsSection(
        textColor: readerTheme.textColor,
        backgroundColor: readerTheme.backgroundColor,
        startExpanded: true,
      ),
    );
  }
}
