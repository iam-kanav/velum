import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:velum/features/settings/data/models/reader_settings.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import '../../data/models/highlight.dart';
import '../providers/highlight_notifier.dart';
import '../providers/reader_notifier.dart';

const Map<String, Color> highlightColors = {
  'yellow': Color(0xFFFFF176),
  'green': Color(0xFF81C784),
  'blue': Color(0xFF64B5F6),
  'pink': Color(0xFFF48FB1),
  'orange': Color(0xFFFFB74D),
};

class HighlightsModal extends StatelessWidget {
  const HighlightsModal({super.key});

  @override
  Widget build(BuildContext context) {
    final readerTheme = context.watch<SettingsNotifier>().settings.readerTheme;
    final highlightNotifier = context.watch<HighlightNotifier>();
    final readerNotifier = context.read<ReaderNotifier>();
    final grouped = highlightNotifier.highlightsByColor;

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: readerTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                      'Highlights',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: readerTheme.textColor,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: readerTheme.textColor),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Highlights list grouped by color
          Expanded(
            child: grouped.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmark_border,
                          size: 48,
                          color: readerTheme.textColor.withAlpha(80),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No highlights yet',
                          style: TextStyle(
                            color: readerTheme.textColor.withAlpha(150),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select text to create a highlight',
                          style: TextStyle(
                            fontSize: 12,
                            color: readerTheme.textColor.withAlpha(100),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: grouped.entries.map((entry) {
                      final colorName = entry.key;
                      final highlights = entry.value;
                      final dotColor =
                          highlightColors[colorName] ?? Colors.grey;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Color group header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${colorName[0].toUpperCase()}${colorName.substring(1)} (${highlights.length})',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: readerTheme.textColor.withAlpha(180),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Highlight cards
                          ...highlights.map(
                            (h) => _buildHighlightCard(
                              context,
                              h,
                              dotColor,
                              readerTheme,
                              highlightNotifier,
                              readerNotifier,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightCard(
    BuildContext context,
    Highlight highlight,
    Color dotColor,
    ReaderTheme readerTheme,
    HighlightNotifier highlightNotifier,
    ReaderNotifier readerNotifier,
  ) {
    final chapters = readerNotifier.currentBook?.Chapters;
    final chapterName =
        chapters != null && highlight.chapterIndex < chapters.length
        ? chapters[highlight.chapterIndex].Title ??
              'Chapter ${highlight.chapterIndex + 1}'
        : 'Chapter ${highlight.chapterIndex + 1}';

    return InkWell(
      onTap: () {
        Navigator.pop(context, highlight);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: dotColor.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: dotColor, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    highlight.text.length > 120
                        ? '${highlight.text.substring(0, 120)}...'
                        : highlight.text,
                    style: TextStyle(
                      fontSize: 13,
                      color: readerTheme.textColor,
                      height: 1.3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    chapterName,
                    style: TextStyle(
                      fontSize: 11,
                      color: readerTheme.textColor.withAlpha(120),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: readerTheme.textColor.withAlpha(120),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete highlight?'),
                    content: const Text('This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          highlightNotifier.removeHighlight(highlight.id);
                          Navigator.pop(ctx);
                        },
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}
