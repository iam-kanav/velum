import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:edge_tts/edge_tts.dart';
import 'package:just_audio/just_audio.dart';
import '../models/tts_settings.dart';

/// Represents a text chunk for TTS with its position info
class TtsChunk {
  final int index;
  final String text;
  final int paragraphIndex;
  final int? sentenceIndex; // null if highlight mode is paragraph

  const TtsChunk({
    required this.index,
    required this.text,
    required this.paragraphIndex,
    this.sentenceIndex,
  });
}

/// Audio source that plays MP3 bytes from memory
class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  _BytesAudioSource(this._bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/mpeg',
    );
  }
}

/// LRU cache for synthesized audio chunks.
/// Keeps the most recently used entries up to [maxSize].
class _AudioCache {
  final int maxSize;
  final LinkedHashMap<String, Uint8List> _map = LinkedHashMap();

  _AudioCache({this.maxSize = 40});

  Uint8List? get(String key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value; // move to end (most recently used)
    }
    return value;
  }

  void put(String key, Uint8List value) {
    _map.remove(key); // remove old position if exists
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first); // evict oldest
    }
  }

  void clear() => _map.clear();
}

/// Service wrapper around Edge TTS + just_audio
class TtsService {
  final AudioPlayer _player = AudioPlayer();

  List<Voice> _availableVoices = [];
  TtsState _state = TtsState.idle;

  // Synthesis parameters
  String _voice = 'en-US-EmmaMultilingualNeural';
  String _rate = '+0%';
  String _pitch = '+0Hz';
  double _volume = 1.0;

  /// Cache key incorporates voice + rate + pitch so settings changes
  /// correctly invalidate stale entries.
  String _settingsFingerprint = '';

  /// LRU audio cache — avoids re-synthesis when navigating back & forth
  final _AudioCache _cache = _AudioCache(maxSize: 40);

  /// In-flight prefetch futures keyed by cache key
  final Map<String, Future<Uint8List>> _pendingSynths = {};

  /// Batch synthesis tracking
  int _batchTotal = 0;
  int _batchDone = 0;

  // Callbacks
  VoidCallback? onStart;
  VoidCallback? onComplete;
  VoidCallback? onPause;
  VoidCallback? onContinue;
  void Function(String text, int start, int end, String word)? onProgress;
  void Function(String error)? onError;
  /// Called whenever batch synthesis progress changes
  void Function(int done, int total)? onSynthesisProgress;

  TtsState get state => _state;
  List<Voice> get availableVoices => _availableVoices;
  int get batchTotal => _batchTotal;
  int get batchDone => _batchDone;

  /// Unique locales derived from available voices
  List<String> get availableLanguages {
    return _availableVoices.map((v) => v.locale).toSet().toList()..sort();
  }

  /// Initialize the TTS engine
  Future<void> init() async {
    // Fetch available voices from Edge TTS
    try {
      _availableVoices = await listVoices();
    } catch (e) {
      debugPrint('Failed to fetch Edge TTS voices: $e');
      _availableVoices = [];
    }

    // Listen for playback completion
    _player.processingStateStream.listen((processingState) {
      if (processingState == ProcessingState.completed) {
        _state = TtsState.stopped;
        onComplete?.call();
      }
    });

    debugPrint(
      'Edge TTS initialized with ${availableLanguages.length} languages '
      'and ${_availableVoices.length} voices',
    );
  }

  /// Apply TTS settings
  Future<void> applySettings(TtsSettings settings) async {
    // Convert speechRate (0.0–1.0, default 0.5) → edge_tts percentage string
    // 0.5 → '+0%', 1.0 → '+100%', 0.1 → '-80%'
    final ratePercent = ((settings.speechRate / 0.5) - 1) * 100;
    _rate = '${ratePercent >= 0 ? '+' : ''}${ratePercent.round()}%';

    // Convert pitch (0.5–2.0, default 1.0) → edge_tts Hz string
    // 1.0 → '+0Hz', 0.5 → '-50Hz', 2.0 → '+100Hz'
    final pitchHz = (settings.pitch - 1.0) * 100;
    _pitch = '${pitchHz >= 0 ? '+' : ''}${pitchHz.round()}Hz';

    // Volume handled by the audio player (0.0–1.0)
    _volume = settings.volume;
    await _player.setVolume(_volume);

    // Set voice
    if (settings.voiceName != null) {
      _voice = settings.voiceName!;
    } else {
      final langVoices = getVoicesForLanguage(settings.language);
      if (langVoices.isNotEmpty) {
        _voice = langVoices.first.shortName;
      }
    }

    // If synthesis params changed, invalidate cache
    final newFingerprint = '$_voice|$_rate|$_pitch';
    if (newFingerprint != _settingsFingerprint) {
      _settingsFingerprint = newFingerprint;
      _cache.clear();
      _pendingSynths.clear();
    }
  }

  /// Get voices filtered by language (exact locale match)
  List<Voice> getVoicesForLanguage(String language) {
    final normalizedLang = language.toLowerCase().replaceAll('_', '-');
    return _availableVoices
        .where(
          (v) => v.locale.toLowerCase().replaceAll('_', '-') == normalizedLang,
        )
        .toList();
  }

  /// Build a cache key for a piece of text under current settings
  String _cacheKey(String text) => '$_settingsFingerprint|$text';

  /// Synthesize text to MP3 bytes, using cache when available.
  Future<Uint8List> _getAudio(String text) async {
    final key = _cacheKey(text);

    // 1. Check LRU cache
    final cached = _cache.get(key);
    if (cached != null) return cached;

    // 2. Join an in-flight synthesis for the same key if one exists
    if (_pendingSynths.containsKey(key)) {
      return _pendingSynths[key]!;
    }

    // 3. Start new synthesis
    final future = _synthesize(text).then((bytes) {
      _cache.put(key, bytes);
      _pendingSynths.remove(key);
      return bytes;
    }).catchError((e) {
      _pendingSynths.remove(key);
      throw e;
    });

    _pendingSynths[key] = future;
    return future;
  }

  /// Raw synthesis via Edge TTS
  Future<Uint8List> _synthesize(String text) async {
    final communicate = Communicate(
      text: text,
      voice: _voice,
      rate: _rate,
      pitch: _pitch,
    );
    return communicate.toBytes();
  }

  /// Start prefetching audio for a text chunk in the background.
  /// The result goes into the LRU cache for instant playback later.
  void prefetch(String text) {
    if (text.isEmpty) return;
    final key = _cacheKey(text);
    // Already cached or in-flight — nothing to do
    if (_cache.get(key) != null || _pendingSynths.containsKey(key)) return;
    // Fire and forget
    _getAudio(text).ignore();
  }

  /// Synthesize all chunk texts in the background, reporting progress.
  /// Runs up to [concurrency] requests in parallel.
  void synthesizeAll(List<String> texts, {int concurrency = 3}) {
    _batchTotal = texts.length;
    // Count how many are already cached
    _batchDone = texts.where((t) => _cache.get(_cacheKey(t)) != null).length;
    onSynthesisProgress?.call(_batchDone, _batchTotal);

    if (_batchDone >= _batchTotal) return;

    // Collect texts that still need synthesis
    final pending = texts.where((t) => _cache.get(_cacheKey(t)) == null).toList();

    // Process with limited concurrency
    var running = 0;
    var nextIndex = 0;

    void startNext() {
      while (running < concurrency && nextIndex < pending.length) {
        final text = pending[nextIndex++];
        running++;
        _getAudio(text).then((_) {
          _batchDone++;
          running--;
          onSynthesisProgress?.call(_batchDone, _batchTotal);
          startNext();
        }).catchError((_) {
          // Count failures as done so the progress bar still completes
          _batchDone++;
          running--;
          onSynthesisProgress?.call(_batchDone, _batchTotal);
          startNext();
        });
      }
    }

    startNext();
  }

  /// Speak text
  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    _state = TtsState.playing;
    onStart?.call();

    try {
      final audioBytes = await _getAudio(text);

      if (audioBytes.isEmpty) {
        _state = TtsState.stopped;
        onComplete?.call();
        return;
      }

      await _player.setAudioSource(_BytesAudioSource(audioBytes));
      await _player.setVolume(_volume);
      await _player.play();
    } catch (e) {
      _state = TtsState.stopped;
      onError?.call(e.toString());
    }
  }

  /// Stop speaking
  Future<void> stop() async {
    _state = TtsState.stopped;
    await _player.stop();
  }

  /// Pause speaking (proper pause with just_audio)
  Future<void> pause() async {
    _state = TtsState.paused;
    await _player.pause();
    onPause?.call();
  }

  /// Resume speaking from paused position
  Future<void> resume() async {
    _state = TtsState.playing;
    await _player.play();
    onContinue?.call();
  }

  /// Clear the audio cache (e.g. on chapter change)
  void clearCache() {
    _cache.clear();
    _pendingSynths.clear();
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _player.stop();
    await _player.dispose();
    _cache.clear();
    _pendingSynths.clear();
  }

  /// Split text into chunks based on highlight mode
  static List<TtsChunk> chunkText(String text, TtsHighlightMode mode) {
    final chunks = <TtsChunk>[];

    // Split into paragraphs first
    final paragraphs = text.split(RegExp(r'\n\s*\n'));

    int chunkIndex = 0;
    int filteredParagraphIndex = 0;

    for (int pIndex = 0; pIndex < paragraphs.length; pIndex++) {
      final para = paragraphs[pIndex].trim();
      if (para.isEmpty) continue;

      if (mode == TtsHighlightMode.paragraph) {
        chunks.add(
          TtsChunk(
            index: chunkIndex++,
            text: para,
            paragraphIndex: filteredParagraphIndex,
          ),
        );
      } else {
        final sentences = _splitIntoSentences(para);
        for (int sIndex = 0; sIndex < sentences.length; sIndex++) {
          final sentence = sentences[sIndex].trim();
          if (sentence.isEmpty) continue;
          chunks.add(
            TtsChunk(
              index: chunkIndex++,
              text: sentence,
              paragraphIndex: filteredParagraphIndex,
              sentenceIndex: sIndex,
            ),
          );
        }
      }
      filteredParagraphIndex++;
    }

    return chunks;
  }

  /// Helper to split paragraph into sentences
  static List<String> _splitIntoSentences(String text) {
    final regex = RegExp(r'(?<=[.!?])\s+');
    return text.split(regex);
  }
}
