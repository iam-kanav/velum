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

/// Sleep timer choices: stop after a duration or at the end of the chapter.
enum SleepTimer {
  off(null, 'Off'),
  min15(Duration(minutes: 15), '15 min'),
  min30(Duration(minutes: 30), '30 min'),
  min60(Duration(minutes: 60), '60 min'),
  endOfChapter(null, 'End of chapter');

  final Duration? duration;
  final String label;
  const SleepTimer(this.duration, this.label);
}

/// TTS playback state
enum TtsState { idle, playing, paused, stopped }

/// Settings for Text-to-Speech
class TtsSettings extends Equatable {
  final double speechRate;
  final double pitch;
  final double volume;
  final String language;
  final TtsHighlightMode highlightMode;
  final bool autoContinue; // Auto-advance to next chapter when current finishes
  final bool stopOnAudioFocusLoss; // Stop TTS when other audio plays

  /// Experimental: use Microsoft Edge online voices instead of the device engine.
  final bool useEdgeTts;

  /// Android TTS engine package; null means the system default.
  final String? deviceEngine;
  final String? deviceVoice;
  final String? edgeVoice;

  const TtsSettings({
    this.speechRate = 0.5,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.language = 'en-US',
    this.highlightMode = TtsHighlightMode.sentence,
    this.autoContinue = true,
    this.stopOnAudioFocusLoss = true,
    this.useEdgeTts = false,
    this.deviceEngine,
    this.deviceVoice,
    this.edgeVoice,
  });

  /// Voice selected for the active engine (null = engine default).
  String? get voiceName => useEdgeTts ? edgeVoice : deviceVoice;

  TtsSettings copyWith({
    double? speechRate,
    double? pitch,
    double? volume,
    String? language,
    TtsHighlightMode? highlightMode,
    bool? autoContinue,
    bool? stopOnAudioFocusLoss,
    bool? useEdgeTts,
    String? deviceEngine,
    String? deviceVoice,
    String? edgeVoice,
    bool clearDeviceVoice = false,
    bool clearEdgeVoice = false,
  }) {
    return TtsSettings(
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      language: language ?? this.language,
      highlightMode: highlightMode ?? this.highlightMode,
      autoContinue: autoContinue ?? this.autoContinue,
      stopOnAudioFocusLoss: stopOnAudioFocusLoss ?? this.stopOnAudioFocusLoss,
      useEdgeTts: useEdgeTts ?? this.useEdgeTts,
      deviceEngine: deviceEngine ?? this.deviceEngine,
      deviceVoice: clearDeviceVoice ? null : (deviceVoice ?? this.deviceVoice),
      edgeVoice: clearEdgeVoice ? null : (edgeVoice ?? this.edgeVoice),
    );
  }

  @override
  List<Object?> get props => [
    speechRate,
    pitch,
    volume,
    language,
    highlightMode,
    autoContinue,
    stopOnAudioFocusLoss,
    useEdgeTts,
    deviceEngine,
    deviceVoice,
    edgeVoice,
  ];
}
