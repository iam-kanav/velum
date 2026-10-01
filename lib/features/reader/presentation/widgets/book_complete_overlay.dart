import 'package:flutter/material.dart';
import '../../../settings/data/models/reader_settings.dart';
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

    return Container(
      color: readerTheme.backgroundColor.withAlpha((0.95 * 255).round()),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.celebration_rounded,
                size: 64,
                color: readerTheme.textColor,
              ),
              const SizedBox(height: 24),
              Text(
                'You finished the book!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: readerTheme.textColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Hope it was a good one.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: readerTheme.textColor.withAlpha(180),
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onStayHere,
                style: TextButton.styleFrom(
                  foregroundColor: readerTheme.textColor.withAlpha(150),
                ),
                child: const Text('Stay here'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
