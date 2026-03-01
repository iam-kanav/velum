import 'package:flutter/material.dart';
import '../../../settings/data/models/reader_settings.dart';
import '../providers/reader_notifier.dart';
import '../../../tts/presentation/providers/tts_notifier.dart';

class TtsFab extends StatelessWidget {
  final TtsNotifier ttsNotifier;
  final ReaderNotifier readerNotifier;
  final bool showUI;
  final bool isOverlayOpen;
  final ReaderTheme readerTheme;

  const TtsFab({
    super.key,
    required this.ttsNotifier,
    required this.readerNotifier,
    required this.showUI,
    required this.isOverlayOpen,
    required this.readerTheme,
  });

  @override
  Widget build(BuildContext context) {
    const Color accentGreen = Color(0xFF4CAF50);
    // Don't show FAB if user is highlighting text or searching
    if (isOverlayOpen) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        offset: showUI ? const Offset(0, -1.5) : Offset.zero,
        child: FloatingActionButton(
          heroTag: 'tts_fab',
          backgroundColor: accentGreen,
          foregroundColor: Colors.white,
          elevation: 4,
          onPressed: () async {
            if (ttsNotifier.isPlaying) {
              ttsNotifier.pause();
            } else if (ttsNotifier.isPaused) {
              await ttsNotifier.togglePlayPause();
            } else {
              // Stop parsing and load text
              final text = readerNotifier.extractStructuredText();
              if (text.isNotEmpty) {
                ttsNotifier.loadContent(text);
                await ttsNotifier.togglePlayPause();
              }
            }
          },
          child: Icon(ttsNotifier.isPlaying ? Icons.pause : Icons.play_arrow),
        ),
      ),
    );
  }
}
