import 'package:equatable/equatable.dart';

/// Highlight granularity for TTS - visual only, doesn't affect playback
enum TtsHighlightMode {
  sentence,
  paragraph;

  String get displayName {
    switch (this) {
      case TtsHighlightMode.sentence:
        return 'Sentence';
      case TtsHighlightMode.paragraph:
        return 'Paragraph';
    }
  }
}

/// TTS playback state
enum TtsState { idle, playing, paused, stopped }

/// Settings for Text-to-Speech
class TtsSettings extends Equatable {
  final double speechRate;
  final double pitch;
  final double volume;
  final String language;
  final String? voiceName;
  final TtsHighlightMode highlightMode;
  final bool autoContinue; // Auto-advance to next chapter when current finishes
  final bool stopOnAudioFocusLoss; // Stop TTS when other audio plays

  const TtsSettings({
    this.speechRate = 0.5,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.language = 'en-US',
    this.voiceName,
    this.highlightMode = TtsHighlightMode.sentence,
    this.autoContinue = true,
    this.stopOnAudioFocusLoss = true,
  });

  TtsSettings copyWith({
    double? speechRate,
    double? pitch,
    double? volume,
    String? language,
    String? voiceName,
    bool clearVoice = false,
    TtsHighlightMode? highlightMode,
    bool? autoContinue,
    bool? stopOnAudioFocusLoss,
  }) {
    return TtsSettings(
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      language: language ?? this.language,
      voiceName: clearVoice ? null : (voiceName ?? this.voiceName),
      highlightMode: highlightMode ?? this.highlightMode,
      autoContinue: autoContinue ?? this.autoContinue,
      stopOnAudioFocusLoss: stopOnAudioFocusLoss ?? this.stopOnAudioFocusLoss,
    );
  }

  @override
  List<Object?> get props => [
    speechRate,
    pitch,
    volume,
    language,
    voiceName,
    highlightMode,
    autoContinue,
    stopOnAudioFocusLoss,
  ];
}
