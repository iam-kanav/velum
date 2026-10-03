import 'package:audio_service/audio_service.dart';
import 'package:velum/features/tts/data/models/tts_settings.dart';
import 'package:velum/features/tts/presentation/providers/tts_notifier.dart';

class VelumAudioHandler extends BaseAudioHandler {
  TtsNotifier? _ttsNotifier;

  /// Connect this handler to the TtsNotifier.
  void attachNotifier(TtsNotifier notifier) {
    _ttsNotifier = notifier;
    _ttsNotifier!.addListener(_syncPlaybackState);
    _syncPlaybackState();
  }

  /// Detach when disposing.
  void detachNotifier() {
    _ttsNotifier?.removeListener(_syncPlaybackState);
    _ttsNotifier = null;
  }

  String? _bookTitle;
  String? _chapterTitle;

  /// Map TtsNotifier state -> audio_service media item and PlaybackState.
  /// Only real changes are sent: this runs on every highlight update, and
  /// rebuilding the notification each sentence slows the phone down.
  void _syncPlaybackState() {
    final notifier = _ttsNotifier;
    if (notifier == null) return;

    if (notifier.bookTitle != _bookTitle ||
        notifier.chapterTitle != _chapterTitle) {
      _bookTitle = notifier.bookTitle;
      _chapterTitle = notifier.chapterTitle;
      final bookTitle = _bookTitle ?? 'Unknown Book';
      final chapterTitle = _chapterTitle ?? 'Unknown Chapter';
      mediaItem.add(MediaItem(
        id: 'velum_tts',
        title: chapterTitle,
        album: bookTitle,
        artist: 'Velum Reader',
        displayTitle: chapterTitle,
        displaySubtitle: bookTitle,
      ));
    }

    final AudioProcessingState processingState;
    final bool playing;

    switch (notifier.state) {
      case TtsState.playing:
        processingState = AudioProcessingState.ready;
        playing = true;
      case TtsState.paused:
        processingState = AudioProcessingState.ready;
        playing = false;
      case TtsState.stopped:
      case TtsState.idle:
        processingState = AudioProcessingState.idle;
        playing = false;
    }

    final current = playbackState.value;
    if (current.playing == playing &&
        current.processingState == processingState) {
      return;
    }

    final controls = [
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];

    playbackState.add(PlaybackState(
      controls: controls,
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: playing,
    ));
  }

  @override
  Future<void> play() async {
    await _ttsNotifier?.play();
  }

  @override
  Future<void> pause() async {
    await _ttsNotifier?.pause();
  }

  @override
  Future<void> stop() async {
    await _ttsNotifier?.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    final notifier = _ttsNotifier;
    if (notifier == null || notifier.chunks.isEmpty) return;

    final currentChunk = notifier.currentChunk;
    if (currentChunk == null) return;

    final nextParagraphIndex = currentChunk.paragraphIndex + 1;
    final hasNext = notifier.chunks.any(
      (c) => c.paragraphIndex == nextParagraphIndex,
    );

    if (hasNext) {
      await notifier.jumpToParagraph(nextParagraphIndex);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final notifier = _ttsNotifier;
    if (notifier == null || notifier.chunks.isEmpty) return;

    final currentChunk = notifier.currentChunk;
    if (currentChunk == null) return;

    final prevParagraphIndex = currentChunk.paragraphIndex - 1;

    if (prevParagraphIndex >= 0) {
      await notifier.jumpToParagraph(prevParagraphIndex);
    } else {
      await notifier.jumpToParagraph(0);
    }
  }
}
