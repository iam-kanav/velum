import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../settings/data/models/reader_settings.dart';
import '../providers/reader_notifier.dart';

class ColorPickerBar extends StatelessWidget {
  final ReaderTheme readerTheme;
  final ReaderNotifier notifier;
  final String selectedText;
  final Function(String, Color) onHighlightSelected;

  const ColorPickerBar({
    super.key,
    required this.readerTheme,
    required this.notifier,
    required this.selectedText,
    required this.onHighlightSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Colors matching default highlights (yellow, green, blue, pink, orange)
    final colors = [
      ('yellow', const Color(0xFFFFEB3B)),
      ('green', const Color(0xFF4CAF50)),
      ('blue', const Color(0xFF2196F3)),
      ('pink', const Color(0xFFE91E63)),
      ('orange', const Color(0xFFFF9800)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: readerTheme.backgroundColor.withAlpha((0.95 * 255).round()),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.1 * 255).round()),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Highlight',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: readerTheme.textColor.withAlpha(150),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: colors.map((c) {
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onHighlightSelected(c.$1, c.$2);
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.$2,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: readerTheme.textColor.withAlpha(50),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: c.$2.withAlpha((0.4 * 255).round()),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
