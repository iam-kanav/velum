import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:velum/features/settings/data/models/reader_settings.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import '../../data/models/highlight.dart';
import '../providers/highlight_notifier.dart';
import '../providers/bookmark_notifier.dart';
import '../providers/reader_notifier.dart';
import 'package:velum/core/theme/app_colors.dart';

const Color _accent = AppColors.accent;

const Map<String, Color> highlightColors = {
  'yellow': Color(0xFFFFF176),
  'green': Color(0xFF81C784),
  'blue': Color(0xFF64B5F6),
  'pink': Color(0xFFF48FB1),
  'orange': Color(0xFFFFB74D),
};

class HighlightsModal extends StatefulWidget {
  const HighlightsModal({super.key});

  @override
  State<HighlightsModal> createState() => _HighlightsModalState();
}

class _HighlightsModalState extends State<HighlightsModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readerTheme = context.watch<SettingsNotifier>().settings.readerTheme;
    final highlightNotifier = context.watch<HighlightNotifier>();
    final bookmarkNotifier = context.watch<BookmarkNotifier>();
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
                      'Highlights & Bookmarks',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: readerTheme.textColor,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (grouped.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.copy, color: readerTheme.textColor, size: 20),
                            tooltip: 'Copy All Highlights',
                            onPressed: () {
                              _copyAllHighlights(context, grouped, readerNotifier, readerTheme);
                            },
                          ),
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
          // Tab bar
          TabBar(
            controller: _tabController,
            labelColor: _accent,
            unselectedLabelColor: readerTheme.textColor.withAlpha(150),
            indicatorColor: _accent,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.highlight, size: 16),
                    const SizedBox(width: 6),
                    Text('Highlights (${highlightNotifier.highlights.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bookmark, size: 16),
                    const SizedBox(width: 6),
                    Text('Bookmarks (${bookmarkNotifier.bookmarks.length})'),
                  ],
                ),
              ),
            ],
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildHighlightsTab(context, grouped, readerTheme, highlightNotifier, readerNotifier),
                _buildBookmarksTab(context, bookmarkNotifier, readerNotifier, readerTheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightsTab(
    BuildContext context,
    Map<String, List<Highlight>> grouped,
    ReaderTheme readerTheme,
    HighlightNotifier highlightNotifier,
    ReaderNotifier readerNotifier,
  ) {
    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.highlight, size: 48, color: readerTheme.textColor.withAlpha(80)),
            const SizedBox(height: 12),
            Text('No highlights yet', style: TextStyle(color: readerTheme.textColor.withAlpha(150))),
            const SizedBox(height: 4),
            Text('Select text to create a highlight', style: TextStyle(fontSize: 12, color: readerTheme.textColor.withAlpha(100))),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: grouped.entries.map((entry) {
        final colorName = entry.key;
        final highlights = entry.value;
        final dotColor = highlightColors[colorName] ?? Colors.grey;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${colorName[0].toUpperCase()}${colorName.substring(1)} (${highlights.length})',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: readerTheme.textColor.withAlpha(180)),
                  ),
                ],
              ),
            ),
            ...highlights.map(
              (h) => _buildHighlightCard(context, h, dotColor, readerTheme, highlightNotifier, readerNotifier),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildBookmarksTab(
    BuildContext context,
    BookmarkNotifier bookmarkNotifier,
    ReaderNotifier readerNotifier,
    ReaderTheme readerTheme,
  ) {
    final bookmarks = bookmarkNotifier.bookmarks;
    if (bookmarks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border, size: 48, color: readerTheme.textColor.withAlpha(80)),
            const SizedBox(height: 12),
            Text('No bookmarks yet', style: TextStyle(color: readerTheme.textColor.withAlpha(150))),
            const SizedBox(height: 4),
            Text('Tap the bookmark icon in the top bar', style: TextStyle(fontSize: 12, color: readerTheme.textColor.withAlpha(100))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: bookmarks.length,
      itemBuilder: (context, index) {
        final bm = bookmarks[index];
        final chapters = readerNotifier.currentBook?.Chapters;
        final chapterName = chapters != null && bm.chapterIndex < chapters.length
            ? chapters[bm.chapterIndex].Title ?? 'Chapter ${bm.chapterIndex + 1}'
            : 'Chapter ${bm.chapterIndex + 1}';
        final timeStr = DateFormat.yMMMd().add_jm().format(bm.createdAt);

        return InkWell(
          onTap: () {
            // Navigate to bookmark position — return bookmark as result
            Navigator.pop(context, bm);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accent.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: _accent, width: 3)),
            ),
            child: Row(
              children: [
                Icon(Icons.bookmark, color: _accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapterName,
                        style: TextStyle(fontSize: 13, color: readerTheme.textColor, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeStr,
                        style: TextStyle(fontSize: 11, color: readerTheme.textColor.withAlpha(120)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: readerTheme.textColor.withAlpha(120)),
                  onPressed: () => bookmarkNotifier.removeBookmark(bm.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _copyAllHighlights(
    BuildContext context,
    Map<String, List<Highlight>> grouped,
    ReaderNotifier readerNotifier,
    ReaderTheme readerTheme,
  ) {
    final chapters = readerNotifier.currentBook?.Chapters;
    final buffer = StringBuffer();
    final bookTitle = readerNotifier.currentBook?.Title ?? 'Unknown Book';
    buffer.writeln('Highlights from "$bookTitle"');
    buffer.writeln('${'=' * 40}\n');

    final byChapter = <int, List<Highlight>>{};
    for (final entry in grouped.values) {
      for (final h in entry) {
        byChapter.putIfAbsent(h.chapterIndex, () => []).add(h);
      }
    }

    final sortedChapters = byChapter.keys.toList()..sort();
    for (final chIdx in sortedChapters) {
      final chapterName = chapters != null && chIdx < chapters.length
          ? chapters[chIdx].Title ?? 'Chapter ${chIdx + 1}'
          : 'Chapter ${chIdx + 1}';
      buffer.writeln('## $chapterName\n');
      for (final h in byChapter[chIdx]!) {
        buffer.writeln('> ${h.text}\n');
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All highlights copied to clipboard')),
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
