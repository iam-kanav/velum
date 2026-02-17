import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import '../providers/reader_notifier.dart';

const Color _accentGreen = Color(0xFF4CAF50);

class ContentsModal extends StatelessWidget {
  const ContentsModal({super.key});

  @override
  Widget build(BuildContext context) {
    final readerTheme = context.watch<SettingsNotifier>().settings.readerTheme;
    final notifier = context.watch<ReaderNotifier>();
    final chapters = notifier.currentBook?.Chapters;

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
                : ListView.builder(
                    itemCount: chapters.length,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemBuilder: (context, index) {
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
