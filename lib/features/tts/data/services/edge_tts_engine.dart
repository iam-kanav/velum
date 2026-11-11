import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:edge_tts/edge_tts.dart';
import '../models/tts_settings.dart';
import 'player_tts_engine.dart';
import 'tts_engine.dart';

/// LRU cache for synthesized audio chunks.
/// Keeps the most recently used entries up to [maxSize].
class _AudioCache {
  final int maxSize;
  final LinkedHashMap<String, Uint8List> _map = LinkedHashMap();

  _AudioCache({required this.maxSize});

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

/// Microsoft Edge neural voices (online) played via just_audio.
class EdgeTtsEngine extends PlayerTtsEngine {
  List<TtsVoice> _voices = [];
  Future<void>? _loadingVoices;

  // Synthesis parameters
  String _voice = 'en-US-EmmaMultilingualNeural';
  String _rate = '+0%';
  String _pitch = '+0Hz';

  /// Cache key incorporates voice + rate + pitch so settings changes
  /// correctly invalidate stale entries.
  String _settingsFingerprint = '';

  static const _cacheSize = 40;

  /// How many chunks [prepare] synthesises ahead of the playback position.
  /// Fewer than the cache holds, so they aren't evicted before they're
  /// played; speak() and [prefetch] keep a few ahead from there on.
  static const _prepareWindow = 30;
  static const _prepareConcurrency = 3;

  /// LRU audio cache — avoids re-synthesis when navigating back & forth
  final _AudioCache _cache = _AudioCache(maxSize: _cacheSize);

  /// In-flight synthesis futures keyed by cache key
  final Map<String, Future<Uint8List>> _pendingSynths = {};

  /// Batch synthesis tracking
  int _batchTotal = 0;
  int _batchDone = 0;

  /// Incremented by every [prepare] and [clearCache], which ends the
  /// previous batch.
  int _prepareGeneration = 0;

  /// What the current batch still has to start, and how many syntheses
  /// started by [prepare] (this batch or an earlier one) are running.
  final Queue<String> _prepareQueue = Queue();
  int _prepareRunning = 0;

  @override
  List<TtsVoice> get voices => _voices;
  @override
  int get prepareTotal => _batchTotal;
  @override
  int get preparedCount => _batchDone;
  @override
  String get mimeType => 'audio/mpeg';

  // Without these a stalled connection never fails, and reading sits in
  // "playing" with no sound. A paragraph normally takes a second or two.
  static const _voiceListTimeout = Duration(seconds: 15);
  static const _synthesisTimeout = Duration(seconds: 30);

  /// Fetches the voice list. It never throws: with no connection the list
  /// stays empty, and calling this again tries once more.
  @override
  Future<void> init() {
    if (_voices.isNotEmpty) return Future.value();
    return _loadingVoices ??=
        _loadVoices().whenComplete(() => _loadingVoices = null);
  }

  Future<void> _loadVoices() async {
    try {
      _voices = (await listVoices().timeout(_voiceListTimeout))
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
    }
  }

  @override
  String describeError(Object error) {
    debugPrint('Edge TTS failed: $error');
    return error is IOException || error is TimeoutException
        ? 'Couldn\'t reach the Microsoft Edge voices. Check your connection.'
        : 'The Microsoft Edge voice failed: $error';
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
    // Edge caps synthesis at 2x ('+100%') and silently ignores anything
    // faster, so synthesise at up to 2x and speed up playback
    // (pitch-preserving) for the rest, up to 4x.
    final speed = settings.speed;
    final synthSpeed = speed.clamp(0.1, 2.0);
    final ratePercent = (synthSpeed - 1) * 100;
    _rate = '${ratePercent >= 0 ? '+' : ''}${ratePercent.round()}%';
    await player.setSpeed(speed / synthSpeed);

    // pitch (0.5–2.0, default 1.0) → '+0Hz' at 1.0, '-50Hz' at 0.5, '+100Hz' at 2.0
    final pitchHz = (settings.pitch - 1.0) * 100;
    _pitch = '${pitchHz >= 0 ? '+' : ''}${pitchHz.round()}Hz';

    await player.setVolume(settings.volume);

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

    // After clearCache() the result belongs to old settings or a chapter
    // already left: hand it to whoever is waiting, but don't keep it.
    late final Future<Uint8List> future;
    bool current() => identical(_pendingSynths[key], future);
    future = Communicate(
      text: text,
      voice: _voice,
      rate: _rate,
      pitch: _pitch,
    ).toBytes().timeout(_synthesisTimeout).then((bytes) {
      if (current()) _cache.put(key, bytes);
      return bytes;
    }).whenComplete(() {
      if (current()) _pendingSynths.remove(key);
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

  /// Synthesize the chunks from [startFrom] on in the background, a few at
  /// a time, in place of whatever an earlier call still had to do.
  @override
  void prepare(List<String> texts, {int startFrom = 0}) {
    _prepareGeneration++;
    final start = startFrom.clamp(0, texts.length);
    // A set: a sentence that comes up twice is synthesised and counted once.
    final window = texts
        .sublist(start, (start + _prepareWindow).clamp(0, texts.length))
        .where((t) => t.isNotEmpty)
        .toSet();
    // get() also marks the ones already here as recently used, so the new
    // ones push out audio from elsewhere rather than these.
    _prepareQueue
      ..clear()
      ..addAll(window.where((t) => _cache.get(_cacheKey(t)) == null));
    _batchTotal = window.length;
    _batchDone = window.length - _prepareQueue.length;
    onPrepareProgress?.call();
    _pumpPrepare();
  }

  void _pumpPrepare() {
    final gen = _prepareGeneration;
    while (_prepareRunning < _prepareConcurrency && _prepareQueue.isNotEmpty) {
      _prepareRunning++;
      _getAudio(_prepareQueue.removeFirst())
          .then((_) {}, onError: (_) {})
          .whenComplete(() {
        _prepareRunning--;
        // Failures count as done so the progress indicator still completes.
        // Work started for a batch that has been replaced isn't counted.
        if (gen == _prepareGeneration) {
          _batchDone++;
          onPrepareProgress?.call();
        }
        _pumpPrepare();
      });
    }
  }

  @override
  Future<Uint8List?> audioFor(String text, bool Function() isCurrent) =>
      _getAudio(text);

  @override
  void clearCache() {
    _prepareGeneration++;
    _prepareQueue.clear();
    _cache.clear();
    _pendingSynths.clear();
    _batchTotal = 0;
    _batchDone = 0;
  }
}
