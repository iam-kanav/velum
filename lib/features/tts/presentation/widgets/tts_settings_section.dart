import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/tts_settings.dart';
import '../../data/services/device_tts_engine.dart';
import '../../data/services/phonon_model.dart';
import '../providers/tts_notifier.dart';
import 'pronunciations_dialog.dart';
import 'package:velum/core/theme/app_colors.dart';

const Color _accent = AppColors.accent;

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
          if (!settings.useEdgeTts &&
              !settings.usePhonon &&
              ttsNotifier.deviceEngines.isNotEmpty) ...[
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

          // Speech Rate: slider in 0.1x steps from 0.2x to 4x.
          // speechRate is stored with 0.5 = normal, so x = speechRate * 2.
          _buildSlider(
            label: 'Speed',
            value: settings.speechRate,
            min: 0.1,
            max: 2.0,
            divisions: 38,
            displayValue: '${(settings.speechRate * 2).toStringAsFixed(1)}x',
            onChanged: ttsNotifier.updateSpeechRate,
          ),

          const SizedBox(height: 16),

          // Pitch Slider (Phonon voices have no pitch control)
          if (!settings.usePhonon) ...[
            _buildSlider(
              label: 'Pitch',
              value: settings.pitch,
              min: 0.5,
              max: 2.0,
              displayValue: settings.pitch.toStringAsFixed(1),
              onChanged: ttsNotifier.updatePitch,
            ),
            const SizedBox(height: 16),
          ],

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

          const SizedBox(height: 20),

          // Sleep Timer
          _buildSleepTimerSelector(ttsNotifier),

          const SizedBox(height: 16),

          // Auto-Continue Toggle
          _buildAutoContinueToggle(ttsNotifier),

          const SizedBox(height: 16),

          // Audio Focus Toggle
          _buildAudioFocusToggle(ttsNotifier),

          const SizedBox(height: 8),

          _buildPronunciationsRow(ttsNotifier),

          const SizedBox(height: 16),

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
                      color: _accent.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _accent.withAlpha(60)),
                    ),
                    child: Center(
                      child: _isPreviewing
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _accent,
                              ),
                            )
                          : Icon(Icons.volume_up, size: 16, color: _accent),
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
    int? divisions,
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
            activeTrackColor: _accent,
            inactiveTrackColor: widget.textColor.withAlpha(40),
            thumbColor: _accent,
            overlayColor: _accent.withAlpha(30),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
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
                    color: isSelected ? _accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? _accent
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
          activeThumbColor: _accent,
          activeTrackColor: _accent.withAlpha(80),
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
              'Pause for calls and other apps\' audio',
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
          activeThumbColor: _accent,
          activeTrackColor: _accent.withAlpha(80),
        ),
      ],
    );
  }

  Widget _buildPronunciationsRow(TtsNotifier ttsNotifier) {
    final count = ttsNotifier.pronunciations.length;
    return InkWell(
      onTap: () => showPronunciationsDialog(
        context,
        ttsNotifier,
        textColor: widget.textColor,
        backgroundColor: widget.backgroundColor,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pronunciations',
                    style: TextStyle(
                      color: widget.textColor.withAlpha(200),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Read words differently from how they\'re written',
                    style: TextStyle(
                      color: widget.textColor.withAlpha(120),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (count > 0)
              Text(
                '$count',
                style: TextStyle(
                  color: widget.textColor.withAlpha(150),
                  fontSize: 13,
                ),
              ),
            Icon(Icons.chevron_right, color: widget.textColor.withAlpha(150)),
          ],
        ),
      ),
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
              activeThumbColor: _accent,
              activeTrackColor: _accent.withAlpha(80),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildPhononRow(ttsNotifier),
      ],
    );
  }

  /// Experimental: Phonon on-device voices, downloaded here first.
  Widget _buildPhononRow(TtsNotifier ttsNotifier) {
    final model = context.watch<PhononModel>();
    const size = '${PhononModel.approximateMegabytes} MB';
    final subtitle = switch (model.status) {
      PhononModelStatus.unsupported => 'Not available on this device.',
      PhononModelStatus.notInstalled =>
        'Natural voices that run on your device, offline. English only. One-time $size download.',
      PhononModelStatus.downloading =>
        'Downloading… ${(model.progress * 100).floor()}%',
      PhononModelStatus.installed =>
        'Natural voices that run on your device, offline. English only.',
    };
    final Widget? trailing = switch (model.status) {
      PhononModelStatus.unsupported => null,
      PhononModelStatus.notInstalled => OutlinedButton(
        // Downloading is asking for the voice, so it's turned on after.
        onPressed: ttsNotifier.downloadPhonon,
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: BorderSide(color: _accent.withAlpha(120)),
          visualDensity: VisualDensity.compact,
        ),
        child: const Text('Download'),
      ),
      PhononModelStatus.downloading => TextButton(
        onPressed: model.cancelDownload,
        style: TextButton.styleFrom(foregroundColor: widget.textColor),
        child: const Text('Cancel'),
      ),
      PhononModelStatus.installed => Switch(
        value: ttsNotifier.settings.usePhonon,
        onChanged: (value) => _setUsePhonon(ttsNotifier, value),
        activeThumbColor: _accent,
        activeTrackColor: _accent.withAlpha(80),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phonon On-Device Voices',
                    style: TextStyle(
                      color: widget.textColor.withAlpha(200),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: widget.textColor.withAlpha(120),
                      fontSize: 11,
                    ),
                  ),
                  if (model.error != null &&
                      model.status == PhononModelStatus.notInstalled)
                    Text(
                      model.error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ?trailing,
          ],
        ),
        if (model.status == PhononModelStatus.downloading) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: model.progress,
            color: _accent,
            backgroundColor: widget.textColor.withAlpha(30),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
        if (model.status == PhononModelStatus.installed)
          GestureDetector(
            onTap: () => _confirmDeletePhonon(ttsNotifier),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Remove download ($size)',
                style: TextStyle(
                  color: widget.textColor.withAlpha(150),
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: widget.textColor.withAlpha(100),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _setUsePhonon(TtsNotifier ttsNotifier, bool value) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await ttsNotifier.setUsePhonon(value)) return;
    messenger?.showSnackBar(
      const SnackBar(content: Text('Couldn\'t load the Phonon voice.')),
    );
  }

  Future<void> _confirmDeletePhonon(TtsNotifier ttsNotifier) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.backgroundColor,
        title: Text(
          'Remove Phonon voices?',
          style: TextStyle(color: widget.textColor),
        ),
        content: Text(
          'Reading aloud goes back to your device voice. You can download them again any time.',
          style: TextStyle(color: widget.textColor.withAlpha(200)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: widget.textColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
    if (remove == true) await ttsNotifier.deletePhononModel();
  }

  Widget _buildSleepTimerSelector(TtsNotifier ttsNotifier) {
    final current = ttsNotifier.sleepTimer;
    final remaining = ttsNotifier.sleepRemaining;
    final status = switch (current) {
      SleepTimer.off => null,
      SleepTimer.endOfChapter => 'Stops at the end of this chapter',
      _ => remaining == null
          ? null
          : 'Stops in ${(remaining.inSeconds / 60).ceil().clamp(1, 999)} min',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sleep Timer',
          style: TextStyle(
            color: widget.textColor.withAlpha(200),
            fontSize: 14,
          ),
        ),
        if (status != null)
          Text(
            status,
            style: TextStyle(
              color: widget.textColor.withAlpha(120),
              fontSize: 11,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: SleepTimer.values.map((timer) {
            final isSelected = current == timer;
            return GestureDetector(
              onTap: () => ttsNotifier.setSleepTimer(timer),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? _accent : widget.textColor.withAlpha(60),
                  ),
                ),
                child: Text(
                  timer.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected ? Colors.white : widget.textColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
