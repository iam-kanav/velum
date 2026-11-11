import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/reader_settings.dart';
import '../providers/settings_notifier.dart';
import 'reader_controls.dart';
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
    final notifier = context.watch<SettingsNotifier>();
    final readerTheme = notifier.settings.readerTheme;

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
                _buildReaderSettings(notifier, readerTheme),
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
                color: isSelected ? _accent : theme.textColor.withAlpha(150),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? _accent : theme.textColor.withAlpha(200),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderSettings(
    SettingsNotifier notifier,
    ReaderTheme readerTheme,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingLabel('Reader Theme', theme: readerTheme, compact: true),
          const SizedBox(height: 12),
          ThemeCircles(
            selected: readerTheme,
            onSelect: notifier.updateReaderTheme,
            compact: true,
          ),
          const SizedBox(height: 24),

          SettingLabel('Font', theme: readerTheme, compact: true),
          const SizedBox(height: 12),
          FontChips(notifier: notifier, theme: readerTheme, compact: true),
          const SizedBox(height: 24),

          TypographySliders(
            notifier: notifier,
            theme: readerTheme,
            compact: true,
          ),
          const SizedBox(height: 16),

          SettingLabel('Text Alignment', theme: readerTheme, compact: true),
          const SizedBox(height: 8),
          TextAlignmentChips(
            notifier: notifier,
            theme: readerTheme,
            compact: true,
          ),
        ],
      ),
    );
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
