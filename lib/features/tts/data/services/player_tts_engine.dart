import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'bytes_audio_source.dart';
import 'tts_engine.dart';

/// What the Edge and Phonon engines share: each turns a chunk into encoded
/// audio in memory ([audioFor]), which just_audio plays.
abstract class PlayerTtsEngine extends TtsEngine {
  // TtsNotifier handles interruptions for every engine. Left on, the player
  // also paused and resumed itself whenever another app made a sound, even
  // with "pause for other audio" turned off.
  @protected
  final AudioPlayer player = AudioPlayer(handleInterruptions: false);

  /// Audible, with its end still to be reported through [onComplete].
  bool _playing = false;

  /// Paused part-way through a chunk, so [resume] can carry on with it.
  bool _paused = false;

  /// The paused chunk played to its end before the pause took effect.
  bool _endedWhilePaused = false;

  /// Incremented by every speak() and stop(), and by a pause() that lands
  /// before the audio is ready, so stale async work is ignored.
  int _speakGeneration = 0;

  PlayerTtsEngine() {
    // Only fire onComplete while playing, so stale events from a previous
    // audio source (after stop/replace) are ignored.
    player.processingStateStream.listen((state) {
      if (state != ProcessingState.completed) return;
      if (_playing) {
        _playing = false;
        onComplete?.call();
      } else if (_paused) {
        _endedWhilePaused = true;
      }
    });
  }

  /// MIME type of the audio [audioFor] returns.
  @protected
  String get mimeType;

  /// The encoded audio for [text], or null to skip the chunk. [isCurrent]
  /// turns false once this speak() has been stopped, paused or replaced by
  /// another one; whatever is returned after that is ignored.
  @protected
  Future<Uint8List?> audioFor(String text, bool Function() isCurrent);

  /// Give up the speak() in progress without reporting anything.
  @protected
  void abandonSpeak() => _speakGeneration++;

  /// A speak() in progress was stopped, or paused before its audio was
  /// ready.
  @protected
  void onSpeakAbandoned() {}

  /// What [onError] is told when [audioFor] or the player throws [error].
  @protected
  String describeError(Object error) => '$error';

  @override
  bool get supportsResume => _paused;

  @override
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    final gen = ++_speakGeneration;
    bool isCurrent() => gen == _speakGeneration;

    // Stop first so replacing the source doesn't fire a 'completed' event.
    _playing = false;
    _paused = false;
    await player.stop();
    if (!isCurrent()) return;

    try {
      final audio = await audioFor(text, isCurrent);
      if (!isCurrent()) return;

      if (audio == null || audio.isEmpty) {
        onComplete?.call();
        return;
      }

      await player.setAudioSource(BytesAudioSource(audio, mimeType));
      if (!isCurrent()) return;
      _playing = true;
      // play()'s future only completes when playback ends, so don't await it —
      // the bytes are in memory and audio starts right away.
      player.play().ignore();
      onStart?.call();
    } catch (e) {
      if (!isCurrent()) return;
      _playing = false;
      onError?.call(describeError(e));
    }
  }

  @override
  Future<void> stop() async {
    abandonSpeak();
    onSpeakAbandoned();
    _playing = false;
    _paused = false;
    await player.stop();
  }

  @override
  Future<void> pause() async {
    if (_playing) {
      _playing = false;
      _paused = true;
      _endedWhilePaused = false;
      await player.pause();
    } else if (!_paused) {
      // speak() is still getting or loading the audio: cancel it. Nothing
      // is left to resume, so the next play speaks the chunk again.
      abandonSpeak();
      onSpeakAbandoned();
    }
  }

  @override
  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    if (_endedWhilePaused) {
      onComplete?.call();
      return;
    }
    _playing = true;
    player.play().ignore();
  }
}
