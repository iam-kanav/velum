import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../settings/data/models/reader_settings.dart';
import '../providers/reader_notifier.dart';
import '../../../tts/presentation/providers/tts_notifier.dart';

class TtsFab extends StatelessWidget {
  final TtsNotifier ttsNotifier;
  final ReaderNotifier readerNotifier;
  final bool showUI;
  final bool isOverlayOpen;
  final ReaderTheme readerTheme;

  /// Key placed on the visual FAB group (inside AnimatedSlide) so the
  /// tutorial spotlight resolves the correct on-screen position.
  final GlobalKey? spotlightKey;

  const TtsFab({
    super.key,
    required this.ttsNotifier,
    required this.readerNotifier,
    required this.showUI,
    required this.isOverlayOpen,
    required this.readerTheme,
    this.spotlightKey,
  });

  @override
  Widget build(BuildContext context) {
    const Color accentGreen = Color(0xFF4CAF50);
    // Don't show FAB if user is highlighting text or searching
    if (isOverlayOpen) {
      return const SizedBox.shrink();
    }

    final isPlaying = ttsNotifier.isPlaying;
    final isSynthesizing = ttsNotifier.isSynthesizing;
    final progress = ttsNotifier.synthesisProgress;
    final percent = (progress * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        offset: showUI ? const Offset(0, -1.5) : Offset.zero,
        // spotlightKey is INSIDE AnimatedSlide so localToGlobal accounts
        // for the fractional translation → tutorial spotlight is accurate.
        child: Stack(
          key: spotlightKey,
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            FloatingActionButton(
              heroTag: 'tts_fab',
              backgroundColor: accentGreen,
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: () async {
                HapticFeedback.lightImpact();
                if (isPlaying) {
                  await ttsNotifier.pause();
                } else if (ttsNotifier.chunks.isNotEmpty) {
                  // Content already loaded — just resume/play
                  await ttsNotifier.play();
                } else {
                  // First time — load content then play
                  final text = readerNotifier.extractStructuredText();
                  if (text.isNotEmpty) {
                    ttsNotifier.loadContent(text);
                    await ttsNotifier.play();
                  }
                }
              },
              child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            // Percentage pill — bottom-right of FAB
            if (isSynthesizing)
              Positioned(
                bottom: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(40),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    '$percent%',
                    style: const TextStyle(
                      color: accentGreen,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
