import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import '../../../settings/data/models/reader_settings.dart';

/// What to call chapter [index] in a list: its title, or "Chapter N" when
/// the book gives it none.
String chapterTitle(List<EpubChapter>? chapters, int index) {
  final title = chapters != null && index < chapters.length
      ? chapters[index].Title?.trim()
      : null;
  return title == null || title.isEmpty ? 'Chapter ${index + 1}' : title;
}

/// The frame the reader's bottom sheets share: rounded top, drag handle,
/// and a title row that ends in a close button, above [children].
class ReaderSheet extends StatelessWidget {
  final ReaderTheme readerTheme;
  final String title;

  /// Buttons shown before the close button.
  final List<Widget> actions;

  /// The sheet's content, laid out in a column under the title row.
  final List<Widget> children;

  const ReaderSheet({
    super.key,
    required this.readerTheme,
    required this.title,
    this.actions = const [],
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    // A sheet shown scroll-controlled must make room for the keyboard
    // itself, or a list being filtered ends up underneath it.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    // A Material rather than a decorated box: rows paint their tint and ink
    // on the nearest Material, and a box's background would cover them.
    return Material(
      color: readerTheme.backgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.55 + keyboard,
        padding: EdgeInsets.only(bottom: keyboard),
        child: Column(
          children: [
            // Handle bar + header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: readerTheme.textColor.withAlpha(60),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: readerTheme.textColor,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...actions,
                          IconButton(
                            icon: Icon(Icons.close, color: readerTheme.textColor),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
