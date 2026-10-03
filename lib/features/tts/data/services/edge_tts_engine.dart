import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:edge_tts/edge_tts.dart';
import 'package:just_audio/just_audio.dart';
import '../models/tts_settings.dart';
import 'tts_engine.dart';

/// Audio source that plays MP3 bytes from memory
// ignore: experimental_member_use
class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  _BytesAudioSource(this._bytes);

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    // ignore: experimental_member_use
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

  bool contains(String key) => _map.containsKey(key);

  void put(String key, Uint8List value) {
    _map.remove(key); // remove old position if exists
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first); // evict oldest
    }
  }

  void clear() => _map.clear();
}

/// Experimental engine: Microsoft Edge neural voices (online) played via just_audio.
class EdgeTtsEngine extends TtsEngine {
  // TtsNotifier handles interruptions for both engines. Left on, the player
  // also paused and resumed itself whenever another app made a sound, even
  // with "pause for other audio" turned off.
  final AudioPlayer _player = AudioPlayer(handleInterruptions: false);

  List<TtsVoice> _voices = [];
  bool _initialized = false;
  bool _playing = false;

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

  /// In-flight synthesis futures keyed by cache key
  final Map<String, Future<Uint8List>> _pendingSynths = {};

  /// Batch synthesis tracking
  int _batchTotal = 0;
  int _batchDone = 0;

  /// Incremented on every speak()/stop() so stale async work is ignored.
  int _speakGeneration = 0;

  @override
  List<TtsVoice> get voices => _voices;
  @override
  int get prepareTotal => _batchTotal;
  @override
  int get preparedCount => _batchDone;
  @override
  bool get supportsResume => true;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Only fire onComplete while playing, so stale events from a previous
    // audio source (after stop/replace) are ignored.
    _player.processingStateStream.listen((processingState) {
      if (processingState == ProcessingState.completed && _playing) {
        _playing = false;
        onComplete?.call();
      }
    });

    try {
      _voices = (await listVoices())
          .map(
            (v) => TtsVoice(
              id: v.shortName,
              label: _voiceLabel(v.shortName, v.gender),
              locale: TtsEngine.normaliseLocale(v.locale),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('Failed to fetch Edge TTS voices: $e');
      _initialized = false; // retry next time
    }
  }

  /// 'en-US-EmmaNeural' + 'Female' → 'Emma (Female)';
  /// 'en-US-EmmaMultilingualNeural' → 'Emma (Female, Multilingual)', so the
  /// two variants of a voice don't look like duplicates.
  static String _voiceLabel(String shortName, String gender) {
    final parts = shortName.split('-');
    if (parts.length < 3) return shortName;
    final raw = parts.sublist(2).join('-');
    final name = raw.replaceAll('Neural', '').replaceAll('Multilingual', '');
    if (name.isEmpty) return shortName;
    final details = [
      if (gender.isNotEmpty)
        '${gender[0].toUpperCase()}${gender.substring(1).toLowerCase()}',
      if (raw.contains('Multilingual')) 'Multilingual',
    ];
    return details.isEmpty ? name : '$name (${details.join(', ')})';
  }

  @override
  Future<void> applySettings(TtsSettings settings) async {
    // speechRate is stored with 0.5 = 1x. Edge caps synthesis at 2x ('+100%')
    // and silently ignores anything faster, so synthesise at up to 2x and
    // speed up playback (pitch-preserving) for the rest, up to 4x.
    final speed = settings.speechRate * 2;
    final synthSpeed = speed.clamp(0.1, 2.0);
    final ratePercent = (synthSpeed - 1) * 100;
    _rate = '${ratePercent >= 0 ? '+' : ''}${ratePercent.round()}%';
    await _player.setSpeed(speed / synthSpeed);

    // pitch (0.5–2.0, default 1.0) → '+0Hz' at 1.0, '-50Hz' at 0.5, '+100Hz' at 2.0
    final pitchHz = (settings.pitch - 1.0) * 100;
    _pitch = '${pitchHz >= 0 ? '+' : ''}${pitchHz.round()}Hz';

    _volume = settings.volume;
    await _player.setVolume(_volume);

    final voice = settings.edgeVoice;
    if (voice != null) {
      _voice = voice;
    } else {
      final langVoices = voicesFor(settings.language);
      if (langVoices.isNotEmpty) _voice = langVoices.first.id;
    }

    final newFingerprint = '$_voice|$_rate|$_pitch';
    if (newFingerprint != _settingsFingerprint) {
      _settingsFingerprint = newFingerprint;
      clearCache();
    }
  }

  String _cacheKey(String text) => '$_settingsFingerprint|$text';

  /// Synthesize text to MP3 bytes, using cache or joining in-flight work.
  Future<Uint8List> _getAudio(String text) {
    final key = _cacheKey(text);
    final cached = _cache.get(key);
    if (cached != null) return Future.value(cached);
    final pending = _pendingSynths[key];
    if (pending != null) return pending;

    final future = Communicate(
      text: text,
      voice: _voice,
      rate: _rate,
      pitch: _pitch,
    ).toBytes().then((bytes) {
      _cache.put(key, bytes);
      _pendingSynths.remove(key);
      return bytes;
    }).catchError((Object e) {
      _pendingSynths.remove(key);
      throw e;
    });

    _pendingSynths[key] = future;
    return future;
  }

  @override
  void prefetch(String text) {
    if (text.isEmpty) return;
    final key = _cacheKey(text);
    if (_cache.contains(key) || _pendingSynths.containsKey(key)) return;
    _getAudio(text).ignore();
  }

  /// Synthesize all chunk texts in the background (3 at a time), starting at
  /// [startFrom] and wrapping around, so playback mid-chapter never waits
  /// on earlier chunks.
  @override
  void prepare(List<String> texts, {int startFrom = 0, int concurrency = 3}) {
    _batchTotal = texts.length;
    _batchDone = texts.where((t) => _cache.contains(_cacheKey(t))).length;
    onPrepareProgress?.call();
    if (_batchDone >= _batchTotal) return;

    final start = startFrom.clamp(0, texts.length);
    final pending = [...texts.sublist(start), ...texts.sublist(0, start)]
        .where((t) => !_cache.contains(_cacheKey(t)))
        .toList();

    var running = 0;
    var nextIndex = 0;
    void startNext() {
      while (running < concurrency && nextIndex < pending.length) {
        running++;
        // Failures count as done so the progress indicator still completes.
        _getAudio(pending[nextIndex++]).then((_) {}, onError: (_) {}).whenComplete(() {
          _batchDone++;
          running--;
          onPrepareProgress?.call();
          startNext();
        });
      }
    }

    startNext();
  }

  @override
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    final gen = ++_speakGeneration;

    // Stop first so replacing the source doesn't fire a 'completed' event.
    _playing = false;
    await _player.stop();

    try {
      final audioBytes = await _getAudio(text);
      if (gen != _speakGeneration) return;

      if (audioBytes.isEmpty) {
        onComplete?.call();
        return;
      }

      await _player.setAudioSource(_BytesAudioSource(audioBytes));
      if (gen != _speakGeneration) return;
      _playing = true;
      // play()'s future only completes when playback ends, so don't await it —
      // the bytes are in memory and audio starts right away.
      _player.play().ignore();
      onStart?.call();
    } catch (e) {
      if (gen != _speakGeneration) return;
      _playing = false;
      onError?.call(e.toString());
    }
  }

  @override
  Future<void> stop() async {
    _speakGeneration++;
    _playing = false;
    await _player.stop();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    _playing = true;
    _player.play().ignore();
  }

  @override
  void clearCache() {
    _cache.clear();
    _pendingSynths.clear();
    _batchTotal = 0;
    _batchDone = 0;
  }
}
