import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/tts_chunk.dart';
import '../../data/models/tts_settings.dart';
import '../../data/services/device_tts_engine.dart';
import '../../data/services/edge_tts_engine.dart';
import '../../data/services/tts_engine.dart';

/// State management for TTS functionality
class TtsNotifier extends ChangeNotifier {
  final DeviceTtsEngine _device;
  final EdgeTtsEngine _edge;
  final SharedPreferences _prefs;

  // Persistence keys
  static const String _speechRateKey = 'tts_speech_rate';
  static const String _pitchKey = 'tts_pitch';
  static const String _volumeKey = 'tts_volume';
  static const String _languageKey = 'tts_language';
  static const String _voiceKey = 'tts_voice'; // device voice
  static const String _edgeVoiceKey = 'tts_edge_voice';
  static const String _engineKey = 'tts_device_engine';
  static const String _useEdgeKey = 'tts_use_edge';
  static const String _highlightModeKey = 'tts_highlight_mode';
  static const String _autoContinueKey = 'tts_auto_continue';
  static const String _stopOnAudioFocusLossKey = 'tts_stop_on_audio_focus_loss';

  TtsSettings _settings = const TtsSettings();
  AudioSession? _audioSession;
  StreamSubscription? _audioInterruptionSub;
  TtsState _state = TtsState.idle;
  List<TtsParagraph> _paragraphs = [];
  List<TtsChunk> _chunks = [];
  int _currentChunkIndex = 0;
  bool _isInitialized = false;
  bool _disposed = false;

  /// Callback when chapter playback completes (all chunks finished)
  VoidCallback? onChapterComplete;

  TtsSettings get settings => _settings;
  TtsState get state => _state;
  List<TtsChunk> get chunks => _chunks;
  TtsChunk? get currentChunk =>
      _currentChunkIndex < _chunks.length ? _chunks[_currentChunkIndex] : null;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _state == TtsState.playing;
  bool get isPaused => _state == TtsState.paused;

  TtsEngine get _engine => _settings.useEdgeTts ? _edge : _device;

  /// Background synthesis progress for the current chapter (Edge only).
  double get synthesisProgress => _engine.prepareTotal > 0
      ? _engine.preparedCount / _engine.prepareTotal
      : 0.0;
  bool get isSynthesizing =>
      _engine.prepareTotal > 0 && _engine.preparedCount < _engine.prepareTotal;

  List<String> get availableLanguages => _engine.languages;
  List<TtsVoice> get voicesForCurrentLanguage =>
      _engine.voicesFor(_settings.language);

  /// Installed device engines (Android) and the one in use.
  List<String> get deviceEngines => _device.engines;
  String? get currentDeviceEngine =>
      _settings.deviceEngine ?? _device.defaultEngine;

  Timer? _settingsDebounce;

  TtsNotifier(this._device, this._edge, this._prefs);

  /// Initialize TTS and load saved settings
  Future<void> init() async {
    _loadSettings();
    await _device.init();
    if (_settings.useEdgeTts) await _edge.init();
    if (_disposed) return;
    _attach(_engine);
    await _engine.applySettings(_settings);

    _isInitialized = true;
    _notify();

    // Audio focus handling - stop TTS when other audio plays
    try {
      _audioSession = await AudioSession.instance;
      await _audioSession!.configure(const AudioSessionConfiguration.speech());
      _audioInterruptionSub =
          _audioSession!.interruptionEventStream.listen((event) {
        if (event.begin && _settings.stopOnAudioFocusLoss && isPlaying) {
          stop();
        }
      });
    } catch (e) {
      debugPrint('Audio session setup failed: $e');
    }
  }

  void _attach(TtsEngine engine) {
    for (final e in <TtsEngine>[_device, _edge]) {
      final active = identical(e, engine);
      e.onStart = active ? _onStart : null;
      e.onComplete = active ? _onChunkComplete : null;
      e.onError = active ? _onError : null;
      e.onPrepareProgress = active ? _notify : null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _loadSettings() {
    var deviceVoice = _prefs.getString(_voiceKey);
    var edgeVoice = _prefs.getString(_edgeVoiceKey);
    // Older versions stored Edge voice names under the shared key.
    if (deviceVoice != null && deviceVoice.endsWith('Neural')) {
      edgeVoice ??= deviceVoice;
      deviceVoice = null;
      _prefs.remove(_voiceKey);
      _prefs.setString(_edgeVoiceKey, edgeVoice);
    }

    _settings = TtsSettings(
      speechRate: (_prefs.getDouble(_speechRateKey) ?? 0.5).clamp(0.0, 2.0),
      pitch: (_prefs.getDouble(_pitchKey) ?? 1.0).clamp(0.5, 2.0),
      volume: (_prefs.getDouble(_volumeKey) ?? 1.0).clamp(0.0, 1.0),
      language: _prefs.getString(_languageKey) ?? 'en-US',
      highlightMode: TtsHighlightMode.values[(_prefs.getInt(_highlightModeKey) ??
              0)
          .clamp(0, TtsHighlightMode.values.length - 1)],
      autoContinue: _prefs.getBool(_autoContinueKey) ?? true,
      stopOnAudioFocusLoss: _prefs.getBool(_stopOnAudioFocusLossKey) ?? true,
      useEdgeTts: _prefs.getBool(_useEdgeKey) ?? false,
      deviceEngine: _prefs.getString(_engineKey),
      deviceVoice: deviceVoice,
      edgeVoice: edgeVoice,
    );
  }

  Future<void> _saveSettings() async {
    Future<void> setOrRemove(String key, String? value) =>
        value != null ? _prefs.setString(key, value) : _prefs.remove(key);

    await Future.wait([
      _prefs.setDouble(_speechRateKey, _settings.speechRate),
      _prefs.setDouble(_pitchKey, _settings.pitch),
      _prefs.setDouble(_volumeKey, _settings.volume),
      _prefs.setString(_languageKey, _settings.language),
      _prefs.setInt(_highlightModeKey, _settings.highlightMode.index),
      _prefs.setBool(_autoContinueKey, _settings.autoContinue),
      _prefs.setBool(_stopOnAudioFocusLossKey, _settings.stopOnAudioFocusLoss),
      _prefs.setBool(_useEdgeKey, _settings.useEdgeTts),
      setOrRemove(_engineKey, _settings.deviceEngine),
      setOrRemove(_voiceKey, _settings.deviceVoice),
      setOrRemove(_edgeVoiceKey, _settings.edgeVoice),
    ]);
  }

  // Engine events

  /// Audio for the current chunk became audible: refresh the highlight.
  /// Late start events after a pause/stop are ignored.
  void _onStart() {
    if (_state == TtsState.playing) _notify();
  }

  void _onChunkComplete() {
    // Ignore if we're not actually playing (e.g., stale callback after stop)
    if (_state != TtsState.playing) return;

    if (_currentChunkIndex + 1 < _chunks.length) {
      _currentChunkIndex++;
      _speakCurrentChunk();
      // onStart notifies once the next chunk is audible, keeping the
      // highlight in sync with the voice.
      return;
    }

    // Finished all chunks in this chapter
    _state = TtsState.stopped;
    _currentChunkIndex = 0;
    if (_settings.autoContinue) onChapterComplete?.call();
    _notify();
  }

  void _onError(String error) {
    debugPrint('TTS Error: $error');
    _state = TtsState.stopped;
    _notify();
  }

  // Content

  /// Load a chapter's paragraphs and prepare them for playback.
  /// [startFromChunk] prioritises preparation from that chunk onward.
  void loadContent(List<TtsParagraph> paragraphs, {int startFromChunk = 0}) {
    _paragraphs = paragraphs;
    _chunks = chunkParagraphs(paragraphs, _settings.highlightMode);
    _currentChunkIndex =
        _chunks.isEmpty ? 0 : startFromChunk.clamp(0, _chunks.length - 1);
    _prepare();
    _notify();
  }

  void _prepare() {
    if (_chunks.isEmpty) return;
    _engine.prepare(
      _chunks.map((c) => c.text).toList(),
      startFrom: _currentChunkIndex,
    );
  }

  /// Clear current content (for chapter changes)
  void clearContent() {
    _paragraphs = [];
    _chunks = [];
    _currentChunkIndex = 0;
    _state = TtsState.idle;
    _engine.clearCache();
    _notify();
  }

  // Playback

  /// Start or resume playback
  Future<void> play() async {
    if (_chunks.isEmpty) return;
    final wasPaused = _state == TtsState.paused;

    // Update state immediately so the button and highlight respond instantly
    _state = TtsState.playing;
    _notify();

    if (wasPaused && _engine.supportsResume) {
      await _engine.resume();
    } else {
      await _speakCurrentChunk();
    }
  }

  Future<void> pause() async {
    _state = TtsState.paused;
    _notify();
    await _engine.pause();
  }

  /// Stop playback (preserves position so play picks up where we left off)
  Future<void> stop() async {
    _state = TtsState.stopped;
    _notify();
    await _engine.stop();
  }

  Future<void> togglePlayPause() => isPlaying ? pause() : play();

  Future<void> jumpToParagraph(int paragraphIndex) => jumpTo(paragraphIndex);

  /// Jump to a paragraph (or a sentence inside it) and start playing.
  /// The highlight moves immediately, before any audio is ready.
  Future<void> jumpTo(int paragraphIndex, [int? sentenceIndex]) async {
    var index = sentenceIndex == null
        ? -1
        : _chunks.indexWhere(
            (c) =>
                c.paragraphIndex == paragraphIndex &&
                c.sentenceIndex == sentenceIndex,
          );
    if (index < 0) {
      index = _chunks.indexWhere((c) => c.paragraphIndex == paragraphIndex);
    }
    if (index < 0) return;

    await _engine.stop();
    _currentChunkIndex = index;
    _state = TtsState.playing;
    _notify();
    _prepare(); // re-prioritise synthesis from the new position
    await _speakCurrentChunk();
  }

  Future<void> _speakCurrentChunk() async {
    if (_currentChunkIndex >= _chunks.length) return;

    // Activate audio session so we receive interruption events
    if (_audioSession != null && _settings.stopOnAudioFocusLoss) {
      try {
        await _audioSession!.setActive(true);
      } catch (_) {}
    }

    // Prefetch the next few chunks for seamless playback
    for (int i = 1; i <= 3 && _currentChunkIndex + i < _chunks.length; i++) {
      _engine.prefetch(_chunks[_currentChunkIndex + i].text);
    }

    await _engine.speak(_chunks[_currentChunkIndex].text);
  }

  // Settings

  Future<void> _applyAndSave() async {
    await _engine.applySettings(_settings);
    await _saveSettings();
  }

  /// Debounced apply + save for slider-driven settings (speech rate, pitch, volume).
  void _debouncedApplyAndSave() {
    _settingsDebounce?.cancel();
    _settingsDebounce = Timer(
      const Duration(milliseconds: 300),
      _applyAndSave,
    );
  }

  void updateSpeechRate(double rate) {
    _settings = _settings.copyWith(speechRate: rate.clamp(0.0, 2.0));
    _notify();
    _debouncedApplyAndSave();
  }

  void updatePitch(double pitch) {
    _settings = _settings.copyWith(pitch: pitch.clamp(0.5, 2.0));
    _notify();
    _debouncedApplyAndSave();
  }

  void updateVolume(double volume) {
    _settings = _settings.copyWith(volume: volume.clamp(0.0, 1.0));
    _notify();
    _debouncedApplyAndSave();
  }

  Future<void> updateLanguage(String language) async {
    // Voices are language-specific, so fall back to the language default.
    _settings = _settings.copyWith(
      language: language,
      clearDeviceVoice: true,
      clearEdgeVoice: true,
    );
    await _applyAndSave();
    _notify();
  }

  Future<void> updateVoice(String voiceId) async {
    _settings = _settings.useEdgeTts
        ? _settings.copyWith(edgeVoice: voiceId)
        : _settings.copyWith(deviceVoice: voiceId);
    await _applyAndSave();
    _notify();
  }

  /// Switch the device speech engine (Android). Voices differ per engine,
  /// so the saved device voice is reset.
  Future<void> updateDeviceEngine(String engine) async {
    if (engine == currentDeviceEngine) return;
    final wasPlaying = isPlaying;
    if (wasPlaying) await stop();
    _settings = _settings.copyWith(
      deviceEngine: engine,
      clearDeviceVoice: true,
    );
    await _applyAndSave();
    _notify();
    if (wasPlaying) await play();
  }

  /// Experimental: toggle Microsoft Edge online voices.
  Future<void> setUseEdgeTts(bool value) async {
    if (value == _settings.useEdgeTts) return;
    final wasPlaying = isPlaying;
    await _engine.stop();
    _engine.clearCache();
    if (_state != TtsState.idle) _state = TtsState.stopped;

    _settings = _settings.copyWith(useEdgeTts: value);
    _notify();
    if (value) await _edge.init();
    _attach(_engine);
    await _applyAndSave();
    _prepare();
    _notify();
    if (wasPlaying) await play();
  }

  Future<void> updateHighlightMode(TtsHighlightMode mode) async {
    _settings = _settings.copyWith(highlightMode: mode);
    await _saveSettings();

    // Re-chunk content if we have any, preserving the current paragraph
    if (_chunks.isNotEmpty) {
      final currentParagraph = currentChunk?.paragraphIndex ?? 0;
      final wasPlaying = isPlaying;
      if (wasPlaying) await _engine.stop();

      _chunks = chunkParagraphs(_paragraphs, mode);
      _currentChunkIndex = _chunks
          .indexWhere((c) => c.paragraphIndex == currentParagraph)
          .clamp(0, _chunks.length - 1);
      _prepare();

      if (wasPlaying) await _speakCurrentChunk();
    }
    _notify();
  }

  Future<void> updateAutoContinue(bool value) async {
    _settings = _settings.copyWith(autoContinue: value);
    await _saveSettings();
    _notify();
  }

  Future<void> updateStopOnAudioFocusLoss(bool value) async {
    _settings = _settings.copyWith(stopOnAudioFocusLoss: value);
    await _saveSettings();
    _notify();
  }

  /// Preview the current voice with a short sample sentence.
  /// Temporarily redirects engine callbacks so the preview doesn't
  /// trigger auto-advance, state changes, or chunk progression.
  Future<void> previewVoice() async {
    final engine = _engine;
    final completer = Completer<void>();
    void done([_]) {
      if (!completer.isCompleted) completer.complete();
    }

    engine
      ..onStart = null
      ..onComplete = done
      ..onError = done;

    try {
      await engine.applySettings(_settings);
      await engine.speak('The quick brown fox jumps over the lazy dog.');
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      await engine.stop();
    } finally {
      _attach(_engine);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _settingsDebounce?.cancel();
    _audioInterruptionSub?.cancel();
    // Engines are shared app-wide and reused on the next Reader visit,
    // so only stop them and detach (unless another notifier took over).
    _engine.stop();
    _engine.clearCache();
    for (final e in <TtsEngine>[_device, _edge]) {
      if (e.onComplete != _onChunkComplete) continue;
      e
        ..onStart = null
        ..onComplete = null
        ..onError = null
        ..onPrepareProgress = null;
    }
    super.dispose();
  }
}
