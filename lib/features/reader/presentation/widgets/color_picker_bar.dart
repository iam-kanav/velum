import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../settings/data/models/reader_settings.dart';

/// Compact pill of highlight colours, shown just below the selected text.
class ColorPickerBar extends StatelessWidget {
  final ReaderTheme readerTheme;
  final Function(String, Color) onHighlightSelected;

  const ColorPickerBar({
    super.key,
    required this.readerTheme,
    required this.onHighlightSelected,
  });

  static const colors = [
    ('yellow', Color(0xFFFFEB3B)),
    ('green', Color(0xFF4CAF50)),
    ('blue', Color(0xFF2196F3)),
    ('pink', Color(0xFFE91E63)),
    ('orange', Color(0xFFFF9800)),
  ];

  static const double dot = 26;
  static const double gap = 10;
  static const double padding = 8;
  static const double width =
      dot * 5 + gap * 4 + padding * 2 + 8; // + horizontal breathing room
  static const double height = dot + padding * 2;

  @override
  Widget build(BuildContext context) {
    final dark = readerTheme == ReaderTheme.dark;
    return Material(
      color: dark ? const Color(0xFF2E2E2E) : Colors.white,
      elevation: 6,
      shadowColor: Colors.black45,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: padding + 4,
          vertical: padding,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < colors.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onHighlightSelected(colors[i].$1, colors[i].$2);
                },
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: colors[i].$2,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: readerTheme.textColor.withAlpha(40),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
