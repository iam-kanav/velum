import 'package:flutter/foundation.dart';
import '../models/tts_settings.dart';

/// A voice offered by a speech engine.
class TtsVoice {
  final String id;
  final String label;
  final String locale; // normalised to "en-US" form

  const TtsVoice({required this.id, required this.label, required this.locale});
}

/// Common interface for the device speech engine and the Edge TTS engine.
abstract class TtsEngine {
  /// Fired when audio for the current utterance actually starts.
  VoidCallback? onStart;

  /// Fired when the current utterance finishes on its own (not when stopped).
  VoidCallback? onComplete;
  void Function(String error)? onError;

  /// Fired when background preparation progress changes (Edge only).
  VoidCallback? onPrepareProgress;

  Future<void> init();
  Future<void> applySettings(TtsSettings settings);
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> pause();

  /// Resume after [pause]. Only called when [supportsResume] is true;
  /// otherwise the caller re-speaks the current chunk.
  Future<void> resume() async {}
  bool get supportsResume => false;

  List<TtsVoice> get voices;

  /// Optional hooks for engines that synthesise ahead of playback.
  void prepare(List<String> texts, {int startFrom = 0}) {}
  void prefetch(String text) {}
  void clearCache() {}
  int get preparedCount => 0;
  int get prepareTotal => 0;

  List<String> get languages =>
      voices.map((v) => v.locale).toSet().toList()..sort();

  List<TtsVoice> voicesFor(String language) {
    final lang = normaliseLocale(language).toLowerCase();
    return voices.where((v) => v.locale.toLowerCase() == lang).toList();
  }

  static String normaliseLocale(String locale) => locale.replaceAll('_', '-');
}
