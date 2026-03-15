import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import '../providers/reader_notifier.dart';

const Color _accentGreen = Color(0xFF4CAF50);

class ContentsModal extends StatefulWidget {
  const ContentsModal({super.key});

  @override
  State<ContentsModal> createState() => _ContentsModalState();
}

class _ContentsModalState extends State<ContentsModal> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readerTheme = context.watch<SettingsNotifier>().settings.readerTheme;
    final notifier = context.watch<ReaderNotifier>();
    final chapters = notifier.currentBook?.Chapters;

    // Filter chapters by search query
    final filteredIndices = <int>[];
    if (chapters != null) {
      for (int i = 0; i < chapters.length; i++) {
        final title = chapters[i].Title ?? 'Chapter ${i + 1}';
        if (_filter.isEmpty || title.toLowerCase().contains(_filter.toLowerCase())) {
          filteredIndices.add(i);
        }
      }
    }

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
                      'Contents',
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
                    borderSide: const BorderSide(color: _accentGreen),
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
                        itemCount: filteredIndices.length,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemBuilder: (context, i) {
                          final index = filteredIndices[i];
                          final chapter = chapters[index];
                          final isSelected = notifier.currentChapter == chapter;
                          return ListTile(
                            title: Text(
                              chapter.Title ?? 'Chapter ${index + 1}',
                              style: TextStyle(
                                color: readerTheme.textColor,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            tileColor: isSelected
                                ? _accentGreen.withAlpha(30)
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
      ),
    );
  }
}
