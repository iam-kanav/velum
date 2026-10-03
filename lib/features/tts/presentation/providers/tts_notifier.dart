import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/tts_chunk.dart';
import '../../data/models/tts_settings.dart';
import '../../data/services/device_tts_engine.dart';
import '../../data/services/edge_tts_engine.dart';
import '../../data/services/tts_engine.dart';

/// State management for TTS functionality. Lives for the whole app, so
/// reading carries on in the library or while another book is open.
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
  StreamSubscription? _becomingNoisySub;
  TtsState _state = TtsState.idle;
  List<TtsParagraph> _paragraphs = [];
  List<TtsChunk> _chunks = [];
  int _currentChunkIndex = 0;
  bool _isInitialized = false;
  bool _disposed = false;

  /// True once the engine has started the current chunk, so a pause can be
  /// resumed in place. False after new content or a stop.
  bool _canResume = false;

  // The book and chapter being read aloud
  ReadAloudBook? _book;
  int _chapterIndex = 0;

  /// Called when reading reaches the end of the book.
  VoidCallback? onBookFinished;

  String? get bookPath => _book?.path;
  String? get bookTitle => _book?.title;
  int get chapterIndex => _chapterIndex;
  String? get chapterTitle {
    final titles = _book?.chapterTitles;
    return titles != null && _chapterIndex < titles.length
        ? titles[_chapterIndex]
        : null;
  }

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

  // Sleep timer (not persisted: it applies to this listening session)
  SleepTimer _sleepTimer = SleepTimer.off;
  DateTime? _sleepEndsAt;
  Timer? _sleepFire;
  Timer? _sleepTick;

  SleepTimer get sleepTimer => _sleepTimer;

  /// Time left on a duration-based sleep timer.
  Duration? get sleepRemaining => _sleepEndsAt?.difference(DateTime.now());

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

    // Audio focus handling. Notification sounds only ask other audio to duck,
    // so they must not pause reading (the default speech config turns ducks
    // into pauses, hence androidWillPauseWhenDucked: false).
    try {
      _audioSession = await AudioSession.instance;
      await _audioSession!.configure(
        const AudioSessionConfiguration.speech().copyWith(
          androidWillPauseWhenDucked: false,
        ),
      );
      _audioInterruptionSub =
          _audioSession!.interruptionEventStream.listen(_onInterruption);
      // Headphones unplugged: don't carry on out loud.
      _becomingNoisySub = _audioSession!.becomingNoisyEventStream.listen((_) {
        if (isPlaying) pause();
      });
    } catch (e) {
      debugPrint('Audio session setup failed: $e');
    }
  }

  /// True while playback is paused because of a temporary interruption
  /// (a call, a voice assistant), so it resumes by itself afterwards.
  bool _pausedByInterruption = false;

  /// Apps often grab audio for a moment as they open or close. Reading only
  /// pauses for a temporary interruption that lasts longer than this.
  static const _interruptionGrace = Duration(milliseconds: 1500);
  Timer? _interruptionPause;

  void _onInterruption(AudioInterruptionEvent event) {
    if (!_settings.stopOnAudioFocusLoss) return;
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          break; // notification sound: keep reading
        case AudioInterruptionType.pause:
          if (isPlaying) {
            _interruptionPause?.cancel();
            _interruptionPause = Timer(_interruptionGrace, () {
              if (!isPlaying) return;
              pause();
              _pausedByInterruption = true;
            });
          }
        case AudioInterruptionType.unknown:
          // Another app took over audio for good (e.g. music started):
          // pause, and let the user resume from the same word.
          _interruptionPause?.cancel();
          if (isPlaying) pause();
      }
    } else if (_interruptionPause?.isActive ?? false) {
      _interruptionPause!.cancel(); // over before reading had to pause
    } else if (_pausedByInterruption) {
      _pausedByInterruption = false;
      if (isPaused) play();
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
    _currentChunkIndex = 0;
    if (_sleepTimer == SleepTimer.endOfChapter) {
      setSleepTimer(SleepTimer.off);
    } else if (_settings.autoContinue && _book != null) {
      _continueToNextChapter();
      return;
    }
    _state = TtsState.stopped;
    _notify();
  }

  /// Carry on into the next chapter that has text (skipping covers and
  /// image pages), whether or not the reader screen is open.
  void _continueToNextChapter() {
    final book = _book!;
    for (var i = _chapterIndex + 1; i < book.chapterTitles.length; i++) {
      final paragraphs = book.paragraphsFor(i);
      if (paragraphs.isEmpty) continue;
      _chapterIndex = i;
      book.onChapterStarted(i);
      loadContent(paragraphs);
      _speakCurrentChunk();
      return;
    }
    _state = TtsState.stopped;
    _notify();
    onBookFinished?.call();
  }

  void _onError(String error) {
    debugPrint('TTS Error: $error');
    _state = TtsState.stopped;
    _notify();
  }

  // Content

  /// Read [chapter] of [book] aloud from now on, replacing whatever was
  /// loaded (another chapter, or another book). If reading was playing it
  /// stays "playing" without a sound until the caller picks the start with
  /// [jumpTo], so switching chapters never shows as a pause.
  Future<void> loadChapter(
    ReadAloudBook book,
    int chapter,
    List<TtsParagraph> paragraphs,
  ) async {
    _interruptionPause?.cancel();
    _pausedByInterruption = false;
    if (_state == TtsState.paused) _state = TtsState.stopped;
    _book = book;
    _chapterIndex = chapter;
    // Swap the content before awaiting, so a jumpTo straight after this
    // call already sees the new chapter.
    final stopped = _engine.stop();
    loadContent(paragraphs);
    await stopped;
  }

  /// Load a chapter's paragraphs and prepare them for playback.
  /// [startFromChunk] prioritises preparation from that chunk onward.
  void loadContent(List<TtsParagraph> paragraphs, {int startFromChunk = 0}) {
    _canResume = false;
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
    _canResume = false;
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
    _interruptionPause?.cancel();
    _pausedByInterruption = false;
    if (_chunks.isEmpty) return;
    final wasPaused = _state == TtsState.paused;

    // Update state immediately so the button and highlight respond instantly
    _state = TtsState.playing;
    _notify();
    await _activateSession();

    if (wasPaused && _canResume && _engine.supportsResume) {
      await _engine.resume();
    } else {
      await _speakCurrentChunk();
    }
  }

  Future<void> pause() async {
    // A manual pause (or one from the timer) shouldn't auto-resume later.
    _interruptionPause?.cancel();
    _pausedByInterruption = false;
    _state = TtsState.paused;
    _notify();
    await _engine.pause();
  }

  /// Stop playback (preserves position so play picks up where we left off)
  Future<void> stop() async {
    _interruptionPause?.cancel();
    _pausedByInterruption = false;
    _canResume = false;
    _state = TtsState.stopped;
    _notify();
    await _engine.stop();
  }

  Future<void> togglePlayPause() => isPlaying ? pause() : play();

  Future<void> jumpToParagraph(int paragraphIndex) => jumpTo(paragraphIndex);

  int _chunkIndexOf(int paragraphIndex, int? sentenceIndex) {
    final index = sentenceIndex == null
        ? -1
        : _chunks.indexWhere(
            (c) =>
                c.paragraphIndex == paragraphIndex &&
                c.sentenceIndex == sentenceIndex,
          );
    return index >= 0
        ? index
        : _chunks.indexWhere((c) => c.paragraphIndex == paragraphIndex);
  }

  /// Jump to a paragraph (or a sentence inside it) and start playing.
  /// The highlight moves immediately, before any audio is ready.
  Future<void> jumpTo(int paragraphIndex, [int? sentenceIndex]) async {
    final index = _chunkIndexOf(paragraphIndex, sentenceIndex);
    if (index < 0) return;

    await _engine.stop();
    _currentChunkIndex = index;
    _state = TtsState.playing;
    _notify();
    _prepare(); // re-prioritise synthesis from the new position
    await _activateSession();
    await _speakCurrentChunk();
  }

  /// Move to a paragraph (or sentence) without starting playback.
  void moveTo(int paragraphIndex, [int? sentenceIndex]) {
    final index = _chunkIndexOf(paragraphIndex, sentenceIndex);
    if (index < 0 || index == _currentChunkIndex) return;
    _canResume = false;
    _currentChunkIndex = index;
    _prepare();
    _notify();
  }

  /// Hold audio focus while reading, so we hear about interruptions.
  /// Requested when playback starts, not before every sentence: asking
  /// again each time would take the audio back from whoever has it.
  Future<void> _activateSession() async {
    if (_audioSession == null || !_settings.stopOnAudioFocusLoss) return;
    try {
      await _audioSession!.setActive(true);
    } catch (_) {}
  }

  Future<void> _speakCurrentChunk() async {
    if (_currentChunkIndex >= _chunks.length) return;
    _canResume = true;

    // Prefetch the next few chunks for seamless playback
    for (int i = 1; i <= 3 && _currentChunkIndex + i < _chunks.length; i++) {
      _engine.prefetch(_chunks[_currentChunkIndex + i].text);
    }

    await _engine.speak(_chunks[_currentChunkIndex].text);
  }

  /// Start (or cancel) the sleep timer. When it runs out playback pauses,
  /// so the listener can pick up where they dozed off.
  void setSleepTimer(SleepTimer timer) {
    _sleepFire?.cancel();
    _sleepTick?.cancel();
    _sleepEndsAt = null;
    _sleepTimer = timer;

    final duration = timer.duration;
    if (duration != null) {
      _sleepEndsAt = DateTime.now().add(duration);
      _sleepFire = Timer(duration, () {
        setSleepTimer(SleepTimer.off);
        if (isPlaying) pause();
      });
      // Refresh the "stops in N min" label
      _sleepTick = Timer.periodic(const Duration(seconds: 30), (_) => _notify());
    }
    _notify();
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
    // Re-selecting the current mode must not restart the paragraph.
    if (mode == _settings.highlightMode) return;
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
    _sleepFire?.cancel();
    _sleepTick?.cancel();
    _interruptionPause?.cancel();
    _audioInterruptionSub?.cancel();
    _becomingNoisySub?.cancel();
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
