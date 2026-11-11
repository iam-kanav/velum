import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../tts/data/models/tts_settings.dart';
import '../../../tts/presentation/providers/tts_notifier.dart';
import 'package:velum/core/theme/app_colors.dart';
import 'package:velum/core/motion/motion.dart';

class TtsFab extends StatelessWidget {
  final TtsNotifier ttsNotifier;

  /// Read-aloud is on this chapter. When it's reading something else (in
  /// the background), the button offers to start reading here.
  final bool active;

  /// Play/pause. The reader decides where playback starts (what's on screen).
  final VoidCallback onPressed;

  /// Distance above the Scaffold's default FAB position.
  final double bottomMargin;
  final bool isOverlayOpen;

  /// Key placed on the visual FAB group so the
  /// tutorial spotlight resolves the correct on-screen position.
  final GlobalKey? spotlightKey;

  const TtsFab({
    super.key,
    required this.ttsNotifier,
    required this.active,
    required this.onPressed,
    required this.bottomMargin,
    required this.isOverlayOpen,
    this.spotlightKey,
  });

  @override
  Widget build(BuildContext context) {
    // Don't show FAB if user is highlighting text or searching
    if (isOverlayOpen) {
      return const SizedBox.shrink();
    }

    final isPlaying = active && ttsNotifier.isPlaying;
    final isSynthesizing = active && ttsNotifier.isSynthesizing;
    final progress = ttsNotifier.synthesisProgress;
    final percent = (progress * 100).round();

    // Use AnimatedContainer with margin to shift the FAB up when the bottom bar
    // is visible. Unlike AnimatedSlide, margin changes go through layout so the
    // hit-test area follows the visual position exactly.
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.smoothOut,
      margin: EdgeInsets.only(bottom: bottomMargin),
      child: Stack(
        key: spotlightKey,
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          FloatingActionButton(
            heroTag: 'tts_fab',
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            elevation: 4,
            onPressed: () {
              HapticFeedback.lightImpact();
              onPressed();
            },
            child: MotionSwap.icon(
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                key: ValueKey(isPlaying),
              ),
            ),
          ),
          // Moon badge — top-left of FAB while a sleep timer is set
          if (ttsNotifier.sleepTimer != SleepTimer.off)
            Positioned(
              top: -4,
              left: -4,
              child: _BadgePop(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(40),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bedtime,
                    size: 12,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          // Percentage pill — bottom-right of FAB
          if (isSynthesizing)
            Positioned(
              bottom: -4,
              right: -4,
              child: _BadgePop(
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
                      color: AppColors.accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small badge popping onto the button with a slight overshoot.
class _BadgePop extends StatelessWidget {
  final Widget child;

  const _BadgePop({required this.child});

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.verySlow,
      curve: Motion.bounce,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.4 + 0.6 * t, child: child),
      ),
      child: child,
    );
  }
}
