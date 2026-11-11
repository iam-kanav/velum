import 'package:flutter/material.dart';
import '../../../settings/data/models/reader_settings.dart';
import 'package:velum/core/motion/motion.dart';
import 'package:velum/core/theme/app_colors.dart';

class BookCompleteOverlay extends StatelessWidget {
  final ReaderTheme readerTheme;
  final VoidCallback onBackToLibrary;
  final VoidCallback onStayHere;
  final VoidCallback onStartOver;

  const BookCompleteOverlay({
    super.key,
    required this.readerTheme,
    required this.onBackToLibrary,
    required this.onStayHere,
    required this.onStartOver,
  });

  @override
  Widget build(BuildContext context) {
    // The backdrop fades in; the rest arrives line by line over it.
    return RevealIn(
      duration: Motion.fast,
      distance: 0,
      blur: 0,
      child: Container(
        color: readerTheme.backgroundColor.withAlpha((0.95 * 255).round()),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lands with a small overshoot and twist.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Motion.verySlow,
                  curve: Motion.bounce,
                  builder: (context, t, child) => Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: Motion.reduced(context) ? 0 : -0.35 * (1 - t),
                      child: Transform.scale(
                        scale: Motion.reduced(context) ? 1 : 0.5 + 0.5 * t,
                        child: child,
                      ),
                    ),
                  ),
                  child: Icon(
                    Icons.celebration_rounded,
                    size: 64,
                    color: readerTheme.textColor,
                  ),
                ),
                const SizedBox(height: 24),
                RevealIn(
                  index: 1,
                  child: Text(
                    'You finished the book!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: readerTheme.textColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                RevealIn(
                  index: 2,
                  child: Text(
                    "Hope it was a good one.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: readerTheme.textColor.withAlpha(180),
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                RevealIn(
                  index: 3,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onBackToLibrary,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Back to Library',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                RevealIn(
                  index: 4,
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onStartOver,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: readerTheme.textColor,
                        side: BorderSide(
                          color: readerTheme.textColor.withAlpha(50),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Start Over',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                RevealIn(
                  index: 5,
                  child: TextButton(
                    onPressed: onStayHere,
                    style: TextButton.styleFrom(
                      foregroundColor: readerTheme.textColor.withAlpha(150),
                    ),
                    child: const Text('Stay here'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
