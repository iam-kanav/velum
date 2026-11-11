import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import '../models/tts_settings.dart';
import 'phonon_bindings.dart' as native;
import 'phonon_model.dart';
import 'player_tts_engine.dart';
import 'tts_engine.dart';

/// Phonon (gradium-ai/xn-ptts), a small neural voice
/// that runs on the device, offline. The model is downloaded from the voice
/// settings ([PhononModel]). A worker isolate turns each chunk into a WAV,
/// a few chunks ahead of the one playing, and just_audio plays it.
class PhononTtsEngine extends PlayerTtsEngine {
  final PhononModel _model;
  PhononTtsEngine(this._model);

  _Worker? _worker;
  Future<void>? _loading;
  List<TtsVoice> _voices = [];
  String _voice = _defaultVoice;

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

  @override
  List<TtsVoice> get voices => _voices;
  @override
  String get mimeType => 'audio/wav';

  /// Load the downloaded model. Throws if it can't be loaded.
  @override
  Future<void> init() {
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
    worker.onDied = (reason) {
      if (!identical(_worker, worker)) return;
      debugPrint('The Phonon worker died: $reason');
      _worker = null;
      _failAll(StateError('The Phonon voice stopped working ($reason)'));
    };
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
    // A load still running would bring the worker back after this.
    try {
      await _loading;
    } catch (_) {}
    clearCache();
    _worker?.dispose();
    _worker = null;
    // Its reply to the job in flight will never come: forget the job, or
    // the next worker would wait behind it for ever.
    _failAll(const _Cancelled());
    _voices = [];
  }

  @override
  Future<void> applySettings(TtsSettings settings) async {
    // Phonon has no rate control, so speed up playback (pitch-preserving)
    // instead.
    await player.setSpeed(settings.speed.clamp(0.2, 4.0));
    await player.setVolume(settings.volume);

    final wanted = settings.phononVoice;
    final voice = _voices.any((v) => v.id == wanted)
        ? wanted!
        : voicesFor(settings.language).firstOrNull?.id ?? _defaultVoice;
    if (voice != _voice) {
      _voice = voice;
      // A chunk speak() is waiting for is asked for again in the new voice.
      _drop(reason: const _Cancelled(voiceChanged: true));
      _cache.clear();
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

  /// Fail everything queued or being synthesised, for a worker that is gone.
  void _failAll(Object error) {
    _queue.clear();
    _inFlight = null;
    final waiting = _pending.values.toList();
    _pending.clear();
    for (final completer in waiting) {
      completer.completeError(error);
    }
  }

  /// Stop synthesising everything but [keep], failing their futures.
  void _drop({
    Set<String> keep = const {},
    _Cancelled reason = const _Cancelled(),
  }) {
    _queue.removeWhere((job) {
      if (keep.contains(job.key)) return false;
      _pending.remove(job.key)?.completeError(reason);
      return true;
    });
    final inFlight = _inFlight;
    if (inFlight != null && !keep.contains(inFlight.key)) {
      _pending.remove(inFlight.key)?.completeError(reason);
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
  /// [texts] is the whole chapter: audio for anything else (the chapter
  /// before) is freed.
  @override
  void prepare(List<String> texts, {int startFrom = 0}) {
    if (_worker == null) return;
    final chapter = texts.map(_cacheKey).toSet();
    _cache.retainWhere(chapter.contains);
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
  Future<Uint8List?> audioFor(String text, bool Function() isCurrent) async {
    // Its worker died: start another.
    if (_worker == null) await init();
    while (isCurrent()) {
      _speakingKey = _cacheKey(text);
      try {
        final wav = await _getAudio(text, urgent: true);
        if (!isCurrent()) break;
        _speakingKey = null;
        _failures = 0;
        return wav.length > _wavHeaderSize ? wav : null;
      } catch (e) {
        if (!isCurrent()) break;
        _speakingKey = null;
        if (e is _Cancelled) {
          // Dropped because the voice changed: ask again in the new one.
          if (e.voiceChanged) continue;
          // Dropped with the rest of the chapter: there's nothing to say,
          // and no error to report either.
          abandonSpeak();
        } else if (e is _SynthesisError && ++_failures <= 3) {
          debugPrint('Phonon skipped a chunk: ${e.message}');
        } else {
          rethrow;
        }
        break;
      }
    }
    return null;
  }

  @override
  void onSpeakAbandoned() => _speakingKey = null;

  @override
  String describeError(Object error) =>
      error is StateError ? error.message : '$error';

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
  /// Whether the work was dropped because the voice changed, in which case
  /// it's still wanted, in the new voice.
  final bool voiceChanged;
  const _Cancelled({this.voiceChanged = false});
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

  void retainWhere(bool Function(String key) test) {
    _map.removeWhere((key, value) {
      if (test(key)) return false;
      _bytes -= value.length;
      return true;
    });
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

  /// Called if the isolate ends by itself, which leaves its work unfinished.
  void Function(String reason)? onDied;

  _Worker._(this._requests, this._replies, this._cancelToken, this.voices);

  static Future<_Worker> spawn(String dir, int threads) async {
    final replies = ReceivePort();
    final ready = Completer<_Worker>();
    // A failure can arrive before anyone is waiting for it below.
    ready.future.ignore();
    _Worker? worker;
    replies.listen((message) {
      if (message is (int, Object?) && worker != null) {
        worker!.onResult?.call(message.$1, message.$2);
      } else if (message is (SendPort, int, List<String>)) {
        final (requests, token, voices) = message;
        worker = _Worker._(requests, replies, token, voices);
        ready.complete(worker);
      } else {
        // The isolate is gone: it couldn't load the model (a String says
        // why), threw ([error, stack trace]) or just exited (null). Without
        // this, whoever waits for it would wait for ever.
        replies.close();
        final reason = switch (message) {
          final String why => why,
          [final error, ...] => '$error',
          _ => 'it exited unexpectedly',
        };
        if (!ready.isCompleted) {
          ready.completeError(StateError(reason));
        } else {
          worker?.onDied?.call(reason);
        }
      }
    });
    try {
      await Isolate.spawn(
        _workerMain,
        (replies.sendPort, dir, threads),
        debugName: 'phonon',
        onError: replies.sendPort,
        onExit: replies.sendPort,
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
    replies.send(lastError(nullptr) ?? 'unknown error');
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
        final samples = pcm.asTypedList(len.value);
        return _encodeWav(_trimTrailingSilence(samples, sampleRate), sampleRate);
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

/// Phonon ends every utterance with 0.5–0.7 s of silence. Between
/// sentences that adds to the player's own gap and sounds halting, so keep
/// only a natural pause after the speech, faded out to avoid a click.
Float32List _trimTrailingSilence(Float32List samples, int sampleRate) {
  const threshold = 0.003; // speech has decayed to inaudible by here
  var end = samples.length;
  while (end > 0 && samples[end - 1].abs() < threshold) {
    end--;
  }
  final keep = (end + sampleRate * 0.15).round();
  if (end == 0 || keep >= samples.length) return samples;
  final trimmed = Float32List.fromList(samples.sublist(0, keep));
  final fade = (sampleRate * 0.03).round().clamp(1, keep);
  for (var i = 0; i < fade; i++) {
    trimmed[keep - 1 - i] *= i / fade;
  }
  return trimmed;
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
