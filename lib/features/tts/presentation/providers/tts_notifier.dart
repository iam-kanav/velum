import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/tts_settings.dart';
import '../../data/services/tts_service.dart';

/// State management for TTS functionality
class TtsNotifier extends ChangeNotifier {
  final TtsService _ttsService;
  final SharedPreferences _prefs;

  // Persistence keys
  static const String _speechRateKey = 'tts_speech_rate';
  static const String _pitchKey = 'tts_pitch';
  static const String _volumeKey = 'tts_volume';
  static const String _languageKey = 'tts_language';
  static const String _voiceKey = 'tts_voice';
  static const String _highlightModeKey = 'tts_highlight_mode';
  static const String _autoContinueKey = 'tts_auto_continue';
  static const String _stopOnAudioFocusLossKey = 'tts_stop_on_audio_focus_loss';

  TtsSettings _settings = const TtsSettings();
  AudioSession? _audioSession;
  StreamSubscription? _audioInterruptionSub;
  TtsState _state = TtsState.idle;
  List<TtsChunk> _chunks = [];
  int _currentChunkIndex = 0;
  bool _isInitialized = false;

  /// Callback when chapter playback completes (all chunks finished)
  VoidCallback? onChapterComplete;

  TtsSettings get settings => _settings;
  TtsState get state => _state;
  List<TtsChunk> get chunks => _chunks;
  int get currentChunkIndex => _currentChunkIndex;
  TtsChunk? get currentChunk =>
      _currentChunkIndex < _chunks.length ? _chunks[_currentChunkIndex] : null;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _state == TtsState.playing;
  bool get isPaused => _state == TtsState.paused;

  /// Synthesis progress for the current chapter (0.0 – 1.0)
  double get synthesisProgress =>
      _ttsService.batchTotal > 0
          ? _ttsService.batchDone / _ttsService.batchTotal
          : 0.0;
  bool get isSynthesizing =>
      _ttsService.batchTotal > 0 &&
      _ttsService.batchDone < _ttsService.batchTotal;

  List<String> get availableLanguages => _ttsService.availableLanguages;
  List<dynamic> get availableVoices => _ttsService.availableVoices;

  Timer? _settingsDebounce;

  TtsNotifier(this._ttsService, this._prefs);

  /// Initialize TTS and load saved settings
  Future<void> init() async {
    await _ttsService.init();

    // Set up callbacks
    _ttsService.onStart = _onStart;
    _ttsService.onComplete = _onChunkComplete;
    _ttsService.onPause = _onPause;
    _ttsService.onContinue = _onContinue;
    _ttsService.onError = _onError;
    _ttsService.onSynthesisProgress = (_, __) => notifyListeners();

    // Load saved settings
    _loadSettings();
    await _ttsService.applySettings(_settings);

    _isInitialized = true;
    notifyListeners();

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

  void _loadSettings() {
    final speechRate = _prefs.getDouble(_speechRateKey) ?? 0.5;
    final pitch = _prefs.getDouble(_pitchKey) ?? 1.0;
    final volume = _prefs.getDouble(_volumeKey) ?? 1.0;
    final language = _prefs.getString(_languageKey) ?? 'en-US';
    final voiceName = _prefs.getString(_voiceKey);
    final highlightModeIndex = _prefs.getInt(_highlightModeKey) ?? 0;
    final autoContinue = _prefs.getBool(_autoContinueKey) ?? true;
    final stopOnAudioFocusLoss =
        _prefs.getBool(_stopOnAudioFocusLossKey) ?? true;

    _settings = TtsSettings(
      speechRate: speechRate.clamp(0.0, 2.0),
      pitch: pitch.clamp(0.5, 2.0),
      volume: volume.clamp(0.0, 1.0),
      language: language,
      voiceName: voiceName,
      highlightMode:
          TtsHighlightMode.values[highlightModeIndex.clamp(
            0,
            TtsHighlightMode.values.length - 1,
          )],
      autoContinue: autoContinue,
      stopOnAudioFocusLoss: stopOnAudioFocusLoss,
    );
  }

  Future<void> _saveSettings() async {
    // Batch all writes in parallel instead of sequential awaits
    final futures = <Future>[
      _prefs.setDouble(_speechRateKey, _settings.speechRate),
      _prefs.setDouble(_pitchKey, _settings.pitch),
      _prefs.setDouble(_volumeKey, _settings.volume),
      _prefs.setString(_languageKey, _settings.language),
      _prefs.setInt(_highlightModeKey, _settings.highlightMode.index),
      _prefs.setBool(_autoContinueKey, _settings.autoContinue),
      _prefs.setBool(
          _stopOnAudioFocusLossKey, _settings.stopOnAudioFocusLoss),
      if (_settings.voiceName != null)
        _prefs.setString(_voiceKey, _settings.voiceName!)
      else
        _prefs.remove(_voiceKey),
    ];
    await Future.wait(futures);
  }

  // Event handlers
  void _onStart() {
    // State is already set to playing in play() — just notify for highlight sync
    if (_state != TtsState.playing) {
      _state = TtsState.playing;
    }
    notifyListeners();
  }

  void _onChunkComplete() {
    // Ignore if we're not actually playing (e.g., stale callback after stop)
    if (_state != TtsState.playing) return;

    // Advance to next chunk if available
    if (_currentChunkIndex + 1 < _chunks.length) {
      _currentChunkIndex++;
      _speakCurrentChunk();
    } else {
      // Finished all chunks in this chapter
      _state = TtsState.stopped;
      _currentChunkIndex = 0;

      // Call chapter complete callback if autoContinue is enabled
      if (_settings.autoContinue && onChapterComplete != null) {
        onChapterComplete!();
      }
    }
    notifyListeners();
  }

  void _onPause() {
    _state = TtsState.paused;
    notifyListeners();
  }

  void _onContinue() {
    _state = TtsState.playing;
    notifyListeners();
  }

  void _onError(String error) {
    debugPrint('TTS Error: $error');
    _state = TtsState.stopped;
    notifyListeners();
  }

  /// Load text content for TTS and start synthesizing the whole chapter.
  /// [startFromChunk] prioritises synthesis from that chunk index onward.
  void loadContent(String text, {int startFromChunk = 0}) {
    _chunks = TtsService.chunkText(text, _settings.highlightMode);
    _currentChunkIndex = startFromChunk.clamp(0, _chunks.length - 1).clamp(0, _chunks.length);

    // Pre-synthesize all chunks, prioritising from current position
    if (_chunks.isNotEmpty) {
      _ttsService.synthesizeAll(
        _chunks.map((c) => c.text).toList(),
        startFrom: _currentChunkIndex,
      );
    }

    notifyListeners();
  }

  /// Clear current content (for chapter changes)
  void clearContent() {
    _chunks = [];
    _currentChunkIndex = 0;
    _state = TtsState.idle;
    _ttsService.clearCache();
    notifyListeners();
  }

  /// Start or resume playback
  Future<void> play() async {
    if (_chunks.isEmpty) return;

    final wasPaused = _state == TtsState.paused;

    // Update state immediately so the UI reflects the change instantly
    _state = TtsState.playing;
    notifyListeners();

    if (wasPaused) {
      await _ttsService.resume();
    } else {
      await _speakCurrentChunk();
    }
  }

  /// Pause playback
  Future<void> pause() async {
    // Update state immediately so the UI reflects the change instantly
    _state = TtsState.paused;
    notifyListeners();
    await _ttsService.pause();
  }

  /// Stop playback (preserves position so resume picks up where we left off)
  Future<void> stop() async {
    _state = TtsState.stopped;
    notifyListeners();
    await _ttsService.stop();
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Jump to a specific paragraph
  Future<void> jumpToParagraph(int paragraphIndex) async {
    // Find first chunk in this paragraph
    final chunkIndex = _chunks.indexWhere(
      (c) => c.paragraphIndex == paragraphIndex,
    );
    if (chunkIndex >= 0) {
      await _ttsService.stop();
      _currentChunkIndex = chunkIndex;
      // Re-prioritize synthesis from the new position
      _ttsService.synthesizeAll(
        _chunks.map((c) => c.text).toList(),
        startFrom: chunkIndex,
      );
      await _speakCurrentChunk();
      notifyListeners();
    }
  }

  /// Jump to a specific sentence within a paragraph
  Future<void> jumpToSentence(int paragraphIndex, int sentenceIndex) async {
    // Find chunk matching both paragraph and sentence index
    final chunkIndex = _chunks.indexWhere(
      (c) =>
          c.paragraphIndex == paragraphIndex &&
          c.sentenceIndex == sentenceIndex,
    );
    if (chunkIndex >= 0) {
      await _ttsService.stop();
      _currentChunkIndex = chunkIndex;
      // Re-prioritize synthesis from the new position
      _ttsService.synthesizeAll(
        _chunks.map((c) => c.text).toList(),
        startFrom: chunkIndex,
      );
      await _speakCurrentChunk();
      notifyListeners();
    } else {
      // Fallback to paragraph jump if sentence not found
      await jumpToParagraph(paragraphIndex);
    }
  }

  /// Jump to specific chunk by index
  Future<void> jumpToChunk(int chunkIndex) async {
    if (chunkIndex >= 0 && chunkIndex < _chunks.length) {
      await _ttsService.stop();
      _currentChunkIndex = chunkIndex;
      await _speakCurrentChunk();
      notifyListeners();
    }
  }

  Future<void> _speakCurrentChunk() async {
    if (_currentChunkIndex < _chunks.length) {
      // Activate audio session so we receive interruption events
      if (_audioSession != null && _settings.stopOnAudioFocusLoss) {
        try {
          await _audioSession!.setActive(true);
        } catch (_) {}
      }
      final chunk = _chunks[_currentChunkIndex];

      // Prefetch the next few chunks for seamless playback
      for (int i = 1; i <= 3; i++) {
        final ahead = _currentChunkIndex + i;
        if (ahead < _chunks.length) {
          _ttsService.prefetch(_chunks[ahead].text);
        }
      }

      await _ttsService.speak(chunk.text);
    }
  }

  /// Debounced apply + save for slider-driven settings (speech rate, pitch, volume).
  /// Updates UI immediately but delays the expensive applySettings + persist calls.
  void _debouncedApplyAndSave() {
    _settingsDebounce?.cancel();
    _settingsDebounce = Timer(const Duration(milliseconds: 300), () async {
      await _ttsService.applySettings(_settings);
      await _saveSettings();
    });
  }

  // Settings update methods
  void updateSpeechRate(double rate) {
    _settings = _settings.copyWith(speechRate: rate.clamp(0.0, 2.0));
    notifyListeners();
    _debouncedApplyAndSave();
  }

  void updatePitch(double pitch) {
    _settings = _settings.copyWith(pitch: pitch.clamp(0.5, 2.0));
    notifyListeners();
    _debouncedApplyAndSave();
  }

  void updateVolume(double volume) {
    _settings = _settings.copyWith(volume: volume.clamp(0.0, 1.0));
    notifyListeners();
    _debouncedApplyAndSave();
  }

  Future<void> updateLanguage(String language) async {
    // Clear voice when language changes (clearVoice: true)
    _settings = _settings.copyWith(language: language, clearVoice: true);
    await _ttsService.applySettings(_settings);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> updateVoice(String voiceName) async {
    _settings = _settings.copyWith(voiceName: voiceName);
    await _ttsService.applySettings(_settings);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> updateHighlightMode(TtsHighlightMode mode) async {
    _settings = _settings.copyWith(highlightMode: mode);
    await _saveSettings();

    // Re-chunk content if we have any, preserving current position
    if (_chunks.isNotEmpty) {
      // Save current paragraph before re-chunking
      final currentParagraph = currentChunk?.paragraphIndex ?? 0;
      final wasPlaying = isPlaying;

      // Stop if playing
      if (wasPlaying) {
        await _ttsService.stop();
      }

      // Re-chunk with new mode
      final fullText = _chunks.map((c) => c.text).join('\n\n');
      _chunks = TtsService.chunkText(fullText, mode);

      // Find chunk that matches current paragraph
      final newChunkIndex = _chunks.indexWhere(
        (c) => c.paragraphIndex == currentParagraph,
      );
      _currentChunkIndex = newChunkIndex >= 0 ? newChunkIndex : 0;

      // Resume if was playing
      if (wasPlaying && _chunks.isNotEmpty) {
        await _speakCurrentChunk();
      }
    }
    notifyListeners();
  }

  Future<void> updateAutoContinue(bool value) async {
    _settings = _settings.copyWith(autoContinue: value);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> updateStopOnAudioFocusLoss(bool value) async {
    _settings = _settings.copyWith(stopOnAudioFocusLoss: value);
    await _saveSettings();
    notifyListeners();
  }

  /// Preview the current voice with a short sample sentence.
  /// Temporarily disconnects ALL callbacks so the preview doesn't
  /// trigger auto-advance, state changes, or chunk progression.
  Future<void> previewVoice() async {
    // Save and disconnect all callbacks
    final savedOnStart = _ttsService.onStart;
    final savedOnComplete = _ttsService.onComplete;
    final savedOnPause = _ttsService.onPause;
    final savedOnContinue = _ttsService.onContinue;
    final savedOnError = _ttsService.onError;

    final completer = Completer<void>();
    _ttsService.onStart = null;
    _ttsService.onComplete = () {
      if (!completer.isCompleted) completer.complete();
    };
    _ttsService.onPause = null;
    _ttsService.onContinue = null;
    _ttsService.onError = (_) {
      if (!completer.isCompleted) completer.complete();
    };

    try {
      await _ttsService.applySettings(_settings);
      await _ttsService.speak('The quick brown fox jumps over the lazy dog.');
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
      await _ttsService.stop();
    } finally {
      // Restore all callbacks
      _ttsService.onStart = savedOnStart;
      _ttsService.onComplete = savedOnComplete;
      _ttsService.onPause = savedOnPause;
      _ttsService.onContinue = savedOnContinue;
      _ttsService.onError = savedOnError;
    }
  }

  /// Get voices filtered by current language
  List<Map<String, dynamic>> getVoicesForCurrentLanguage() {
    return _ttsService.getVoicesForLanguage(_settings.language).map((v) => {
      'name': v.shortName,
      'locale': v.locale,
      'gender': v.gender,
      'friendlyName': v.friendlyName,
    }).toList();
  }

  @override
  void dispose() {
    _settingsDebounce?.cancel();
    _audioInterruptionSub?.cancel();
    // Stop playback and clear cache, but do NOT dispose the shared TtsService —
    // it outlives this notifier and will be reused on the next Reader visit.
    _ttsService.stop();
    _ttsService.clearCache();
    super.dispose();
  }
}
