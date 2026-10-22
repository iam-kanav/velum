import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/tts_settings.dart';
import 'bytes_audio_source.dart';
import 'phonon_bindings.dart' as native;
import 'phonon_model.dart';
import 'tts_engine.dart';

/// Experimental engine: Phonon (gradium-ai/xn-ptts), a small neural voice
/// that runs on the device, offline. The model is downloaded from the voice
/// settings ([PhononModel]). A worker isolate turns each chunk into a WAV,
/// a few chunks ahead of the one playing, and just_audio plays it.
class PhononTtsEngine extends TtsEngine {
  final PhononModel _model;
  PhononTtsEngine(this._model);

  // TtsNotifier handles interruptions for every engine.
  final AudioPlayer _player = AudioPlayer(handleInterruptions: false);

  _Worker? _worker;
  Future<void>? _loading;
  bool _listening = false;
  List<TtsVoice> _voices = [];
  String _voice = _defaultVoice;
  bool _playing = false;

  /// Incremented on every speak()/stop() so stale async work is ignored.
  int _speakGeneration = 0;

  /// The chunk speak() is waiting on, kept when [prepare] drops the rest.
  String? _speakingKey;

  /// Synthesis failures in a row. A chunk the model can't read is skipped,
  /// but a voice that fails every time stops reading.
  int _failures = 0;

  final _cache = _WavCache();
  final Map<String, Completer<Uint8List>> _pending = {};
  final List<_Job> _queue = [];
  _Job? _inFlight;
  int _nextJobId = 0;

  /// How many chunks [prepare] synthesises ahead. Phonon runs several times
  /// faster than real time, so a short lookahead keeps playback seamless
  /// without using the CPU for a whole chapter.
  static const _lookahead = 3;
  static const _defaultVoice = 'default';

  bool get isLoaded => _worker != null;

  @override
  List<TtsVoice> get voices => _voices;
  @override
  bool get supportsResume => true;

  /// Load the downloaded model. Throws if it can't be loaded.
  @override
  Future<void> init() {
    if (!_listening) {
      _listening = true;
      // Only fire onComplete while playing, so stale events from a previous
      // audio source (after stop/replace) are ignored.
      _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed && _playing) {
          _playing = false;
          onComplete?.call();
        }
      });
    }
    if (_worker != null) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    final path = _model.path;
    if (!_model.isInstalled || path == null) {
      throw StateError('The Phonon voice is not downloaded');
    }
    final info = {for (final v in await _model.voices()) v.name: v};
    final cores = Platform.numberOfProcessors;
    // Phones mix fast and slow cores, so leave the slow half alone.
    final threads = Platform.isAndroid
        ? (cores ~/ 2).clamp(1, 4)
        : cores.clamp(1, 4);
    final worker = await _Worker.spawn(path, threads);
    worker.onResult = _onResult;
    _worker = worker;

    _voices = [
      for (final name in worker.voices)
        if (name == _defaultVoice)
          const TtsVoice(id: _defaultVoice, label: 'Default', locale: 'en-US')
        else
          TtsVoice(
            id: name,
            label: _voiceLabel(name, info[name]?.gender),
            locale: info[name]?.locale ?? 'en-US',
          ),
    ];
    // The model's own voice first, then the catalog's.
    _voices.sort((a, b) => a.id == _defaultVoice
        ? -1
        : b.id == _defaultVoice
            ? 1
            : a.label.compareTo(b.label));
  }

  static String _voiceLabel(String name, String? gender) {
    if (gender == null || gender.isEmpty) return name;
    return '$name (${gender[0].toUpperCase()}${gender.substring(1)})';
  }

  /// Free the model, e.g. before its files are deleted.
  Future<void> unload() async {
    await stop();
    clearCache();
    _worker?.dispose();
    _worker = null;
    _voices = [];
  }

  @override
  Future<void> applySettings(TtsSettings settings) async {
    // speechRate is stored with 0.5 = 1x. Phonon has no rate control, so
    // speed up playback (pitch-preserving) instead.
    await _player.setSpeed((settings.speechRate * 2).clamp(0.2, 4.0));
    await _player.setVolume(settings.volume);

    final wanted = settings.phononVoice;
    final voice = _voices.any((v) => v.id == wanted)
        ? wanted!
        : voicesFor(settings.language).firstOrNull?.id ?? _defaultVoice;
    if (voice != _voice) {
      _voice = voice;
      clearCache();
    }
  }

  String _cacheKey(String text) => '$_voice|$text';

  /// The WAV for [text]: from the cache, from synthesis already queued, or
  /// queued now. [urgent] puts it first and interrupts other work.
  Future<Uint8List> _getAudio(String text, {bool urgent = false}) {
    final key = _cacheKey(text);
    final cached = _cache.get(key);
    if (cached != null) return Future.value(cached);
    if (_worker == null) {
      return Future.error(StateError('The Phonon voice is not loaded'));
    }

    var completer = _pending[key];
    if (completer == null) {
      completer = _pending[key] = Completer<Uint8List>();
      final job = _Job(key, text, _voice);
      urgent ? _queue.insert(0, job) : _queue.add(job);
    } else if (urgent) {
      final i = _queue.indexWhere((j) => j.key == key);
      if (i > 0) _queue.insert(0, _queue.removeAt(i));
    }
    final inFlight = _inFlight;
    if (urgent && inFlight != null && inFlight.key != key) {
      // Finish this one first; the cancelled job goes back in the queue.
      _worker!.cancel();
    }
    _pump();
    return completer.future;
  }

  void _pump() {
    final worker = _worker;
    if (_inFlight != null || worker == null || _queue.isEmpty) return;
    final job = _inFlight = _queue.removeAt(0)..id = _nextJobId++;
    worker.synth(job.id, job.text, job.voice);
  }

  void _onResult(int id, Object? result) {
    final job = _inFlight;
    if (job == null || job.id != id) return;
    _inFlight = null;

    if (result is TransferableTypedData) {
      final wav = result.materialize().asUint8List();
      _cache.put(job.key, wav);
      _queue.removeWhere((j) => j.key == job.key);
      _pending.remove(job.key)?.complete(wav);
    } else if (result is String) {
      _queue.removeWhere((j) => j.key == job.key);
      _pending.remove(job.key)?.completeError(_SynthesisError(result));
    } else if (_pending.containsKey(job.key) &&
        !_queue.any((j) => j.key == job.key)) {
      // Cancelled for an urgent job, which is first in the queue; this one
      // is likely the chunk after it.
      _queue.insert(_queue.isEmpty ? 0 : 1, job);
    }
    _pump();
  }

  /// Stop synthesising everything but [keep], failing their futures.
  void _drop({Set<String> keep = const {}}) {
    _queue.removeWhere((job) {
      if (keep.contains(job.key)) return false;
      _pending.remove(job.key)?.completeError(const _Cancelled());
      return true;
    });
    final inFlight = _inFlight;
    if (inFlight != null && !keep.contains(inFlight.key)) {
      _pending.remove(inFlight.key)?.completeError(const _Cancelled());
      _worker?.cancel();
    }
  }

  @override
  void prefetch(String text) {
    if (text.isEmpty || _worker == null) return;
    _getAudio(text).ignore();
  }

  /// Synthesise the first few chunks from [startFrom], dropping work queued
  /// for anywhere else in the chapter. speak() and [prefetch] keep it ahead.
  @override
  void prepare(List<String> texts, {int startFrom = 0}) {
    if (_worker == null) return;
    final start = startFrom.clamp(0, texts.length);
    final window = texts
        .sublist(start, (start + _lookahead).clamp(0, texts.length))
        .where((t) => t.isNotEmpty)
        .toList();
    final keys = window.map(_cacheKey).toList();
    _drop(keep: {...keys, ?_speakingKey});
    _queue.sort((a, b) {
      int rank(_Job j) => j.key == _speakingKey ? -1 : keys.indexOf(j.key);
      return rank(a).compareTo(rank(b));
    });
    for (final text in window) {
      _getAudio(text).ignore();
    }
  }

  @override
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    final gen = ++_speakGeneration;

    // Stop first so replacing the source doesn't fire a 'completed' event.
    _playing = false;
    await _player.stop();

    try {
      _speakingKey = _cacheKey(text);
      final wav = await _getAudio(text, urgent: true);
      if (gen != _speakGeneration) return;
      _speakingKey = null;
      _failures = 0;

      if (wav.length <= _wavHeaderSize) {
        onComplete?.call();
        return;
      }

      await _player.setAudioSource(BytesAudioSource(wav, 'audio/wav'));
      if (gen != _speakGeneration) return;
      _playing = true;
      // play()'s future only completes when playback ends, so don't await it.
      _player.play().ignore();
      onStart?.call();
    } catch (e) {
      if (gen != _speakGeneration) return;
      _speakingKey = null;
      _playing = false;
      if (e is _SynthesisError && ++_failures <= 3) {
        debugPrint('Phonon skipped a chunk: ${e.message}');
        onComplete?.call();
        return;
      }
      onError?.call(e.toString());
    }
  }

  @override
  Future<void> stop() async {
    _speakGeneration++;
    _speakingKey = null;
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
    _drop();
    _cache.clear();
  }
}

class _Job {
  final String key;
  final String text;
  final String voice;
  int id = -1;
  _Job(this.key, this.text, this.voice);
}

class _Cancelled implements Exception {
  const _Cancelled();
  @override
  String toString() => 'Cancelled';
}

class _SynthesisError implements Exception {
  final String message;
  const _SynthesisError(this.message);
  @override
  String toString() => 'Phonon: $message';
}

/// Recently synthesised WAVs, least recently used dropped first once they
/// pass [maxBytes]. A paragraph can be a few MB, so this counts bytes.
class _WavCache {
  static const maxBytes = 48 << 20;
  final LinkedHashMap<String, Uint8List> _map = LinkedHashMap();
  int _bytes = 0;

  Uint8List? get(String key) {
    final value = _map.remove(key);
    if (value != null) _map[key] = value; // most recently used
    return value;
  }

  void put(String key, Uint8List value) {
    _bytes -= _map.remove(key)?.length ?? 0;
    _map[key] = value;
    _bytes += value.length;
    while (_bytes > maxBytes && _map.length > 1) {
      _bytes -= _map.remove(_map.keys.first)!.length;
    }
  }

  void clear() {
    _map.clear();
    _bytes = 0;
  }
}

const _wavHeaderSize = 44;

/// The model, loaded in its own isolate: its calls block for as long as
/// synthesis takes.
class _Worker {
  final SendPort _requests;
  final ReceivePort _replies;
  final int _cancelToken;
  final List<String> voices;
  void Function(int id, Object? result)? onResult;

  _Worker._(this._requests, this._replies, this._cancelToken, this.voices);

  static Future<_Worker> spawn(String dir, int threads) async {
    final replies = ReceivePort();
    final ready = Completer<_Worker>();
    _Worker? worker;
    replies.listen((message) {
      if (worker != null) {
        final (id, result) = message as (int, Object?);
        worker!.onResult?.call(id, result);
      } else if (message is (SendPort, int, List<String>)) {
        final (requests, token, voices) = message;
        worker = _Worker._(requests, replies, token, voices);
        ready.complete(worker);
      } else {
        replies.close();
        ready.completeError(StateError('$message'));
      }
    });
    try {
      await Isolate.spawn(
        _workerMain,
        (replies.sendPort, dir, threads),
        debugName: 'phonon',
      );
    } catch (e) {
      replies.close();
      rethrow;
    }
    return ready.future;
  }

  /// Synthesise [text] in [voice]. The result arrives through [onResult]:
  /// a WAV as [TransferableTypedData], an error message, or null if it
  /// was cancelled.
  void synth(int id, String text, String voice) =>
      _requests.send((id, text, voice));

  /// Make the synthesis running now return early.
  void cancel() => native.phononCancel(Pointer.fromAddress(_cancelToken));

  void dispose() {
    cancel();
    _requests.send(null);
    _replies.close();
  }
}

void _workerMain((SendPort, String, int) args) {
  final (replies, dir, threads) = args;

  String? lastError(Pointer<native.PhononHandle> h) {
    final error = native.phononLastError(h);
    return error == nullptr ? null : error.cast<Utf8>().toDartString();
  }

  final handle = using((arena) => native.phononNew(
        dir.toNativeUtf8(allocator: arena).cast(),
        'en'.toNativeUtf8(allocator: arena).cast(),
        threads,
      ));
  if (handle == nullptr) {
    replies.send(lastError(nullptr) ?? 'Could not load the Phonon voice');
    return;
  }

  // NUL-separated names, ending in a second NUL.
  final voices = <String>[];
  var p = native.phononVoices(handle).cast<Utf8>();
  while (p.cast<Uint8>().value != 0) {
    final bytes = p.length;
    voices.add(p.toDartString(length: bytes));
    p = Pointer.fromAddress(p.address + bytes + 1);
  }

  final requests = ReceivePort();
  replies.send((
    requests.sendPort,
    native.phononCancelToken(handle).address,
    voices,
  ));
  final sampleRate = native.phononSampleRate(handle);
  String? voice;

  requests.listen((message) {
    if (message == null) {
      native.phononFree(handle);
      requests.close();
      return;
    }
    final (id, text, wanted) = message as (int, String, String);
    if (wanted != voice) {
      using((arena) =>
          native.phononSetVoice(handle, wanted.toNativeUtf8(allocator: arena).cast()));
      voice = wanted;
    }
    final wav = using((arena) {
      final len = arena<Size>();
      final pcm = native.phononSynth(
        handle,
        text.toNativeUtf8(allocator: arena).cast(),
        len,
      );
      if (pcm == nullptr) return null;
      try {
        return _encodeWav(pcm.asTypedList(len.value), sampleRate);
      } finally {
        native.phononFreePcm(pcm, len.value);
      }
    });
    if (wav != null) {
      replies.send((id, TransferableTypedData.fromList([wav])));
    } else {
      replies.send((id, lastError(handle))); // null when cancelled
    }
  });
}

/// 16-bit mono PCM WAV.
Uint8List _encodeWav(Float32List samples, int sampleRate) {
  final bytes = Uint8List(_wavHeaderSize + samples.length * 2);
  final data = ByteData.sublistView(bytes);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes[offset + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final s = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(_wavHeaderSize + i * 2, s, Endian.little);
  }
  return bytes;
}
