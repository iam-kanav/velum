import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/tts_settings.dart';
import '../providers/tts_notifier.dart';

const Color _accentGreen = Color(0xFF4CAF50);

/// TTS settings section for inclusion in settings modal
class TtsSettingsSection extends StatefulWidget {
  final Color textColor;
  final Color backgroundColor;
  final bool startExpanded;

  const TtsSettingsSection({
    super.key,
    required this.textColor,
    required this.backgroundColor,
    this.startExpanded = false,
  });

  @override
  State<TtsSettingsSection> createState() => _TtsSettingsSectionState();
}

class _TtsSettingsSectionState extends State<TtsSettingsSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.startExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final ttsNotifier = context.watch<TtsNotifier>();

    if (!ttsNotifier.isInitialized) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Initializing TTS...',
            style: TextStyle(color: widget.textColor.withAlpha(150)),
          ),
        ),
      );
    }

    // If startExpanded, just show content directly without header
    if (widget.startExpanded) {
      return _buildExpandedContent(ttsNotifier);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with expand/collapse
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.record_voice_over,
                      color: widget.textColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Text-to-Speech',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: widget.textColor,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: widget.textColor,
                ),
              ],
            ),
          ),
        ),

        // Expanded content
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildExpandedContent(ttsNotifier),
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildExpandedContent(TtsNotifier ttsNotifier) {
    final settings = ttsNotifier.settings;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language Dropdown
          _buildDropdownRow(
            label: 'Language',
            value: settings.language,
            items:
                (ttsNotifier.availableLanguages.toList()
                      ..sort((a, b) => a.toString().compareTo(b.toString())))
                    .map(
                      (lang) => DropdownMenuItem<String>(
                        value: lang.toString(),
                        child: Text(
                          lang.toString(),
                          style: TextStyle(
                            color: widget.textColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                    .toList(),
            onChanged: (val) {
              if (val != null) ttsNotifier.updateLanguage(val);
            },
          ),

          const SizedBox(height: 16),

          // Voice Dropdown
          _buildVoiceDropdown(ttsNotifier),

          const SizedBox(height: 20),

          // Speech Rate Slider
          _buildSlider(
            label: 'Speed',
            value: settings.speechRate,
            min: 0.1,
            max: 1.0,
            displayValue: '${(settings.speechRate * 2).toStringAsFixed(1)}x',
            onChanged: ttsNotifier.updateSpeechRate,
          ),

          const SizedBox(height: 16),

          // Pitch Slider
          _buildSlider(
            label: 'Pitch',
            value: settings.pitch,
            min: 0.5,
            max: 2.0,
            displayValue: settings.pitch.toStringAsFixed(1),
            onChanged: ttsNotifier.updatePitch,
          ),

          const SizedBox(height: 16),

          // Volume Slider
          _buildSlider(
            label: 'Volume',
            value: settings.volume,
            min: 0.0,
            max: 1.0,
            displayValue: '${(settings.volume * 100).toInt()}%',
            onChanged: ttsNotifier.updateVolume,
          ),

          const SizedBox(height: 20),

          // Highlight Mode
          _buildHighlightModeSelector(ttsNotifier),

          const SizedBox(height: 16),

          // Auto-Continue Toggle
          _buildAutoContinueToggle(ttsNotifier),

          const SizedBox(height: 16),

          // Audio Focus Toggle
          _buildAudioFocusToggle(ttsNotifier),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDropdownRow({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: widget.textColor.withAlpha(200),
            fontSize: 14,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: widget.textColor.withAlpha(60)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: items.any((item) => item.value == value) ? value : null,
            items: items,
            onChanged: onChanged,
            underline: const SizedBox(),
            dropdownColor: widget.backgroundColor,
            style: TextStyle(color: widget.textColor, fontSize: 13),
            icon: Icon(Icons.arrow_drop_down, color: widget.textColor),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceDropdown(TtsNotifier ttsNotifier) {
    final allVoices = ttsNotifier.getVoicesForCurrentLanguage();
    final settings = ttsNotifier.settings;

    // Deduplicate voices by name
    final seenNames = <String>{};
    final voices = allVoices.where((v) {
      final name = v['name'] as String?;
      if (name == null || seenNames.contains(name)) return false;
      seenNames.add(name);
      return true;
    }).toList();

    if (voices.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Voice',
            style: TextStyle(
              color: widget.textColor.withAlpha(200),
              fontSize: 14,
            ),
          ),
          Text(
            'Default',
            style: TextStyle(
              color: widget.textColor.withAlpha(150),
              fontSize: 13,
            ),
          ),
        ],
      );
    }

    // Check if saved voice exists in current list
    final voiceNames = voices.map((v) => v['name'] as String).toList();
    final currentVoice =
        settings.voiceName != null && voiceNames.contains(settings.voiceName)
        ? settings.voiceName
        : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Voice',
          style: TextStyle(
            color: widget.textColor.withAlpha(200),
            fontSize: 14,
          ),
        ),
        Container(
          constraints: const BoxConstraints(maxWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: widget.textColor.withAlpha(60)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: currentVoice,
            hint: Text(
              'Default',
              style: TextStyle(
                color: widget.textColor.withAlpha(150),
                fontSize: 13,
              ),
            ),
            items: voices
                .map(
                  (v) => DropdownMenuItem<String>(
                    value: v['name'] as String,
                    child: Text(
                      (v['name'] as String).length > 18
                          ? '${(v['name'] as String).substring(0, 18)}...'
                          : v['name'] as String,
                      style: TextStyle(color: widget.textColor, fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) ttsNotifier.updateVoice(val);
            },
            underline: const SizedBox(),
            dropdownColor: widget.backgroundColor,
            icon: Icon(Icons.arrow_drop_down, color: widget.textColor),
            isExpanded: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: widget.textColor.withAlpha(200),
                fontSize: 14,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: widget.textColor.withAlpha(15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                displayValue,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: _accentGreen,
            inactiveTrackColor: widget.textColor.withAlpha(40),
            thumbColor: _accentGreen,
            overlayColor: _accentGreen.withAlpha(30),
            trackHeight: 3,
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }

  Widget _buildHighlightModeSelector(TtsNotifier ttsNotifier) {
    final settings = ttsNotifier.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Highlight Mode',
          style: TextStyle(
            color: widget.textColor.withAlpha(200),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: TtsHighlightMode.values.map((mode) {
            final isSelected = settings.highlightMode == mode;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => ttsNotifier.updateHighlightMode(mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? _accentGreen : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? _accentGreen
                          : widget.textColor.withAlpha(60),
                    ),
                  ),
                  child: Text(
                    mode.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? Colors.white : widget.textColor,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAutoContinueToggle(TtsNotifier ttsNotifier) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Auto-Continue',
              style: TextStyle(
                color: widget.textColor.withAlpha(200),
                fontSize: 14,
              ),
            ),
            Text(
              'Continue to next chapter',
              style: TextStyle(
                color: widget.textColor.withAlpha(120),
                fontSize: 11,
              ),
            ),
          ],
        ),
        Switch(
          value: ttsNotifier.settings.autoContinue,
          onChanged: (value) => ttsNotifier.updateAutoContinue(value),
          activeThumbColor: Theme.of(context).primaryColor,
        ),
      ],
    );
  }

  Widget _buildAudioFocusToggle(TtsNotifier ttsNotifier) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pause on Interruption',
              style: TextStyle(
                color: widget.textColor.withAlpha(200),
                fontSize: 14,
              ),
            ),
            Text(
              'Stop when other audio plays',
              style: TextStyle(
                color: widget.textColor.withAlpha(120),
                fontSize: 11,
              ),
            ),
          ],
        ),
        Switch(
          value: ttsNotifier.settings.stopOnAudioFocusLoss,
          onChanged: (value) =>
              ttsNotifier.updateStopOnAudioFocusLoss(value),
          activeThumbColor: Theme.of(context).primaryColor,
        ),
      ],
    );
  }
}
