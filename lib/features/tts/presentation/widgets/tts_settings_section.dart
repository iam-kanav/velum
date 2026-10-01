import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/tts_settings.dart';
import '../../data/services/device_tts_engine.dart';
import '../providers/tts_notifier.dart';

const Color _accentGreen = Color(0xFF4CAF50);

const _languageNames = <String, String>{
  'af': 'Afrikaans',
  'am': 'Amharic',
  'ar': 'Arabic',
  'az': 'Azerbaijani',
  'be': 'Belarusian',
  'bg': 'Bulgarian',
  'bn': 'Bengali',
  'bs': 'Bosnian',
  'ca': 'Catalan',
  'cs': 'Czech',
  'cy': 'Welsh',
  'da': 'Danish',
  'de': 'German',
  'el': 'Greek',
  'en': 'English',
  'es': 'Spanish',
  'et': 'Estonian',
  'eu': 'Basque',
  'fa': 'Persian',
  'fi': 'Finnish',
  'fil': 'Filipino',
  'fr': 'French',
  'gl': 'Galician',
  'gu': 'Gujarati',
  'ha': 'Hausa',
  'he': 'Hebrew',
  'hi': 'Hindi',
  'hr': 'Croatian',
  'hu': 'Hungarian',
  'hy': 'Armenian',
  'id': 'Indonesian',
  'is': 'Icelandic',
  'it': 'Italian',
  'ja': 'Japanese',
  'jv': 'Javanese',
  'ka': 'Georgian',
  'kk': 'Kazakh',
  'km': 'Khmer',
  'kn': 'Kannada',
  'ko': 'Korean',
  'lo': 'Lao',
  'lt': 'Lithuanian',
  'lv': 'Latvian',
  'mk': 'Macedonian',
  'ml': 'Malayalam',
  'mn': 'Mongolian',
  'mr': 'Marathi',
  'ms': 'Malay',
  'my': 'Burmese',
  'nb': 'Norwegian',
  'ne': 'Nepali',
  'nl': 'Dutch',
  'no': 'Norwegian',
  'pa': 'Punjabi',
  'pl': 'Polish',
  'pt': 'Portuguese',
  'ro': 'Romanian',
  'ru': 'Russian',
  'si': 'Sinhala',
  'sk': 'Slovak',
  'sl': 'Slovenian',
  'so': 'Somali',
  'sq': 'Albanian',
  'sr': 'Serbian',
  'su': 'Sundanese',
  'sv': 'Swedish',
  'sw': 'Swahili',
  'ta': 'Tamil',
  'te': 'Telugu',
  'th': 'Thai',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'ur': 'Urdu',
  'uz': 'Uzbek',
  'vi': 'Vietnamese',
  'yo': 'Yoruba',
  'yue': 'Cantonese',
  'zh': 'Chinese',
  'zu': 'Zulu',
};

const _regionNames = <String, String>{
  'AU': 'Australia',
  'BD': 'Bangladesh',
  'BE': 'Belgium',
  'BR': 'Brazil',
  'CA': 'Canada',
  'CH': 'Switzerland',
  'CN': 'China',
  'DE': 'Germany',
  'DK': 'Denmark',
  'EG': 'Egypt',
  'ES': 'Spain',
  'FI': 'Finland',
  'FR': 'France',
  'GB': 'UK',
  'GH': 'Ghana',
  'GR': 'Greece',
  'HK': 'Hong Kong',
  'ID': 'Indonesia',
  'IE': 'Ireland',
  'IL': 'Israel',
  'IN': 'India',
  'IT': 'Italy',
  'JP': 'Japan',
  'KE': 'Kenya',
  'KR': 'Korea',
  'MX': 'Mexico',
  'MY': 'Malaysia',
  'NG': 'Nigeria',
  'NL': 'Netherlands',
  'NO': 'Norway',
  'NZ': 'New Zealand',
  'PH': 'Philippines',
  'PK': 'Pakistan',
  'PL': 'Poland',
  'PT': 'Portugal',
  'RO': 'Romania',
  'RU': 'Russia',
  'SA': 'Saudi Arabia',
  'SE': 'Sweden',
  'SG': 'Singapore',
  'TH': 'Thailand',
  'TR': 'Turkey',
  'TW': 'Taiwan',
  'TZ': 'Tanzania',
  'UA': 'Ukraine',
  'UK': 'UK',
  'US': 'US',
  'VN': 'Vietnam',
  'ZA': 'South Africa',
};

/// Format a locale code like "en-US" into "English (US)"
String _friendlyLanguageName(String locale) {
  // Normalise separators
  final parts = locale.replaceAll('_', '-').split('-');
  final langCode = parts.first.toLowerCase();
  final lang = _languageNames[langCode] ?? langCode;
  if (parts.length > 1) {
    final regionCode = parts[1].toUpperCase();
    final region = _regionNames[regionCode] ?? regionCode;
    return '$lang ($region)';
  }
  return lang;
}

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
          // Speech engine (device engines, Android)
          if (!settings.useEdgeTts && ttsNotifier.deviceEngines.isNotEmpty) ...[
            _buildDropdownRow(
              label: 'Engine',
              value: ttsNotifier.currentDeviceEngine ?? '',
              items: ttsNotifier.deviceEngines
                  .map(
                    (engine) => DropdownMenuItem<String>(
                      value: engine,
                      child: Text(
                        DeviceTtsEngine.engineLabel(engine),
                        style: TextStyle(color: widget.textColor, fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) ttsNotifier.updateDeviceEngine(val);
              },
            ),
            const SizedBox(height: 16),
          ],

          // Language Dropdown
          _buildDropdownRow(
            label: 'Language',
            value: settings.language,
            items:
                (ttsNotifier.availableLanguages.toList()..sort(
                      (a, b) => _friendlyLanguageName(
                        a.toString(),
                      ).compareTo(_friendlyLanguageName(b.toString())),
                    ))
                    .map(
                      (lang) => DropdownMenuItem<String>(
                        value: lang.toString(),
                        child: Text(
                          _friendlyLanguageName(lang.toString()),
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

          const SizedBox(height: 24),

          // Experimental: Edge online voices
          _buildExperimentalSection(ttsNotifier),

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

  bool _isPreviewing = false;

  Widget _buildVoiceDropdown(TtsNotifier ttsNotifier) {
    final voices = ttsNotifier.voicesForCurrentLanguage;
    final settings = ttsNotifier.settings;

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
    final currentVoice = voices.any((v) => v.id == settings.voiceName)
        ? settings.voiceName
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Voice',
              style: TextStyle(
                color: widget.textColor.withAlpha(200),
                fontSize: 14,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 150),
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
                          (voice) => DropdownMenuItem<String>(
                            value: voice.id,
                            child: Text(
                              voice.label,
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
                const SizedBox(width: 8),
                // Voice preview button
                GestureDetector(
                  onTap: _isPreviewing
                      ? null
                      : () async {
                          setState(() => _isPreviewing = true);
                          try {
                            // Temporarily speak preview text using current settings
                            final wasPlaying = ttsNotifier.isPlaying;
                            if (wasPlaying) await ttsNotifier.pause();
                            await ttsNotifier.previewVoice();
                            if (wasPlaying) await ttsNotifier.play();
                          } finally {
                            if (mounted) setState(() => _isPreviewing = false);
                          }
                        },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _accentGreen.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _accentGreen.withAlpha(60)),
                    ),
                    child: Center(
                      child: _isPreviewing
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _accentGreen,
                              ),
                            )
                          : Icon(Icons.volume_up, size: 16, color: _accentGreen),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
          activeThumbColor: _accentGreen,
          activeTrackColor: _accentGreen.withAlpha(80),
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
          onChanged: (value) => ttsNotifier.updateStopOnAudioFocusLoss(value),
          activeThumbColor: _accentGreen,
          activeTrackColor: _accentGreen.withAlpha(80),
        ),
      ],
    );
  }

  Widget _buildExperimentalSection(TtsNotifier ttsNotifier) {
    final enabled = ttsNotifier.settings.useEdgeTts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EXPERIMENTAL',
          style: TextStyle(
            color: widget.textColor.withAlpha(120),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Microsoft Edge Voices',
                    style: TextStyle(
                      color: widget.textColor.withAlpha(200),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Natural online voices. Needs internet and is slower to start.',
                    style: TextStyle(
                      color: widget.textColor.withAlpha(120),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: (value) => ttsNotifier.setUseEdgeTts(value),
              activeThumbColor: _accentGreen,
              activeTrackColor: _accentGreen.withAlpha(80),
            ),
          ],
        ),
      ],
    );
  }
}
