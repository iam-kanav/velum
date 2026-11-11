import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import '../providers/reader_notifier.dart';
import 'package:velum/core/theme/app_colors.dart';
import 'reader_sheet.dart';

const Color _accent = AppColors.accent;

class ContentsModal extends StatefulWidget {
  const ContentsModal({super.key});

  @override
  State<ContentsModal> createState() => _ContentsModalState();
}

class _ContentsModalState extends State<ContentsModal> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _currentChapterKey = GlobalKey();
  String _filter = '';

  /// Height of a one-line row. Long titles wrap, so rows are at least this.
  static const double _rowHeight = 56;
  int _furthestBuiltRow = -1;
  int _revealAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrentChapter());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Open the list at the chapter being read. Rows are built lazily, so
  /// jump towards it until its row exists, then centre it.
  void _revealCurrentChapter() {
    if (!mounted || !_scrollController.hasClients) return;
    final rowContext = _currentChapterKey.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(rowContext, alignment: 0.4);
      return;
    }
    if (++_revealAttempts > 20) return;
    final index = context.read<ReaderNotifier>().currentChapterIndex;
    final position = _scrollController.position;
    // Wrapped titles make rows taller than the estimate, so the first jump
    // can land short; step on past the furthest row built so far.
    final target = _revealAttempts == 1
        ? index * _rowHeight
        : position.pixels +
            (index - _furthestBuiltRow) * _rowHeight +
            position.viewportDimension / 2;
    if (target <= position.pixels) return;
    _scrollController.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrentChapter());
  }

  @override
  Widget build(BuildContext context) {
    final readerTheme = context.watch<SettingsNotifier>().settings.readerTheme;
    final notifier = context.watch<ReaderNotifier>();
    final chapters = notifier.currentBook?.Chapters;
    final currentIndex = notifier.currentChapterIndex;

    // Filter chapters by search query
    final filteredIndices = <int>[];
    if (chapters != null) {
      final filter = _filter.toLowerCase();
      for (int i = 0; i < chapters.length; i++) {
        if (chapterTitle(chapters, i).toLowerCase().contains(filter)) {
          filteredIndices.add(i);
        }
      }
    }

    return ReaderSheet(
      readerTheme: readerTheme,
      title: 'Contents',
      children: [
        // Search field
        if (chapters != null && chapters.length > 5)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _filter = value),
              style: TextStyle(color: readerTheme.textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search chapters...',
                hintStyle: TextStyle(color: readerTheme.textColor.withAlpha(100)),
                prefixIcon: Icon(Icons.search, color: readerTheme.textColor.withAlpha(120), size: 20),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: readerTheme.textColor.withAlpha(120), size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _filter = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: readerTheme.textColor.withAlpha(10),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: readerTheme.textColor.withAlpha(30)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: readerTheme.textColor.withAlpha(30)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _accent),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        // Chapter list
        Expanded(
          child: chapters == null || chapters.isEmpty
              ? Center(
                  child: Text(
                    'No chapters found',
                    style: TextStyle(color: readerTheme.textColor.withAlpha(150)),
                  ),
                )
              : filteredIndices.isEmpty
                  ? Center(
                      child: Text(
                        'No matching chapters',
                        style: TextStyle(color: readerTheme.textColor.withAlpha(150)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: filteredIndices.length,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemBuilder: (context, i) {
                        final index = filteredIndices[i];
                        final chapter = chapters[index];
                        // By index: chapters compare by value, and a book
                        // that lists one twice would put the key on two rows.
                        final isSelected = index == currentIndex;
                        if (index > _furthestBuiltRow) _furthestBuiltRow = index;
                        return ListTile(
                          key: isSelected ? _currentChapterKey : null,
                          title: Text(
                            chapterTitle(chapters, index),
                            style: TextStyle(
                              color: readerTheme.textColor,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          tileColor: isSelected
                              ? _accent.withAlpha(30)
                              : null,
                          onTap: () {
                            notifier.jumpToChapter(chapter);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
