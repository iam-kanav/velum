import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:velum/core/theme/app_colors.dart';
import 'package:velum/features/settings/data/models/reader_settings.dart';
import '../../data/models/book_collection.dart';
import '../providers/library_notifier.dart';

const Color _accent = AppColors.accent;

Color _surface(ReaderTheme theme) => switch (theme) {
  ReaderTheme.dark => const Color(0xFF262626),
  ReaderTheme.sepia => Color.lerp(theme.backgroundColor, Colors.white, 0.45)!,
  ReaderTheme.light => Colors.white,
};

/// Folder with a plus: "add to collection".
const IconData collectionAddIcon = Icons.create_new_folder_outlined;

/// Side drawer: All books, then the user's collections, then "Create
/// collection". Tapping a collection shows only its books in the library.
class CollectionsDrawer extends StatelessWidget {
  final ReaderTheme theme;

  const CollectionsDrawer({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryNotifier>();
    final current = library.currentCollection;
    final text = theme.textColor;
    final muted = text.withAlpha(150);

    Widget row({
      required Widget icon,
      required String label,
      String? trailing,
      bool selected = false,
      required VoidCallback onTap,
      VoidCallback? onLongPress,
    }) {
      final color = selected ? _accent : text;
      return Material(
        color: selected ? _accent.withAlpha(30) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            height: selected ? 60 : 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  IconTheme(
                    data: IconThemeData(
                      color: selected ? _accent : muted,
                      size: 24,
                    ),
                    child: icon,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: color,
                        fontSize: 16.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (trailing != null)
                    Text(
                      trailing,
                      style: GoogleFonts.inter(
                        color: selected ? _accent : muted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    void open(String? id) {
      library.showCollection(id);
      Navigator.of(context).pop();
    }

    return Drawer(
      backgroundColor: _surface(theme),
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Text(
                'Velum',
                style: GoogleFonts.inter(
                  color: text,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            row(
              icon: const Icon(Icons.bookmark),
              label: 'All books',
              trailing: '${library.books.length}',
              selected: current == null,
              onTap: () => open(null),
            ),
            Divider(height: 21, thickness: 1, color: text.withAlpha(30)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text(
                'Collections',
                style: GoogleFonts.inter(color: muted, fontSize: 14.5),
              ),
            ),
            if (library.collections.isEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: text.withAlpha(12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text.rich(
                  TextSpan(
                    style: GoogleFonts.inter(
                      color: text.withAlpha(180),
                      fontSize: 14,
                      height: 1.55,
                    ),
                    children: [
                      const TextSpan(
                        text:
                            'No collections yet. Select books in your library, then tap ',
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _accent.withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            collectionAddIcon,
                            size: 15,
                            color: _accent,
                          ),
                        ),
                      ),
                      const TextSpan(text: ' to add them to one.'),
                    ],
                  ),
                ),
              ),
            for (final c in library.collections)
              row(
                icon: const Icon(Icons.folder),
                label: c.name,
                trailing: '${library.bookCount(c)}',
                selected: current?.id == c.id,
                onTap: () => open(c.id),
                onLongPress: () => showCollectionOptions(context, theme, c),
              ),
            row(
              icon: const Icon(Icons.add),
              label: 'Create collection',
              onTap: () async {
                final name = await showCollectionNameDialog(context, theme);
                if (name != null) await library.createCollection(name);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog asking for a collection name. Returns the trimmed name, or null.
Future<String?> showCollectionNameDialog(
  BuildContext context,
  ReaderTheme theme, {
  String title = 'New collection',
  String action = 'Create',
  String initial = '',
  String? helper,
}) {
  // Existing name starts selected, so typing replaces it.
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final name = controller.text.trim();
        if (name.isNotEmpty) Navigator.of(ctx).pop(name);
      }

      return AlertDialog(
        backgroundColor: _surface(theme),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          title,
          style: GoogleFonts.inter(
            color: theme.textColor,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => submit(),
              style: GoogleFonts.inter(color: theme.textColor, fontSize: 15.5),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: theme.textColor.withAlpha(150)),
                floatingLabelStyle: const TextStyle(color: _accent),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.textColor.withAlpha(60)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _accent, width: 2),
                ),
              ),
            ),
            if (helper != null) ...[
              const SizedBox(height: 8),
              Text(
                helper,
                style: GoogleFonts.inter(
                  color: theme.textColor.withAlpha(150),
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: theme.textColor.withAlpha(170)),
            ),
          ),
          FilledButton(
            onPressed: submit,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            child: Text(action),
          ),
        ],
      );
    },
  );
}

/// Long-press on a collection: rename or delete it.
Future<void> showCollectionOptions(
  BuildContext context,
  ReaderTheme theme,
  BookCollection collection,
) async {
  final library = context.read<LibraryNotifier>();
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: _surface(theme),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_outlined, color: theme.textColor),
              title: Text('Rename', style: TextStyle(color: theme.textColor)),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete collection',
                style: TextStyle(color: Colors.red),
              ),
              subtitle: Text(
                'Books stay in your library',
                style: TextStyle(color: theme.textColor.withAlpha(140)),
              ),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'rename') {
    final name = await showCollectionNameDialog(
      context,
      theme,
      title: 'Rename collection',
      action: 'Save',
      initial: collection.name,
    );
    if (name != null) await library.renameCollection(collection.id, name);
  } else if (choice == 'delete') {
    await library.deleteCollection(collection.id);
  }
}

/// Sheet for adding the selected books to collections (ticks toggle
/// membership right away) or creating a new one with them. Resolves to a
/// confirmation message once the user is finished, or null if they backed
/// out without finishing.
Future<String?> showAddToCollectionSheet(
  BuildContext context,
  ReaderTheme theme,
  Set<String> bookPaths,
) async {
  final count = bookPaths.length;
  final countLabel = '$count book${count == 1 ? '' : 's'}';

  void createNew(BuildContext sheetContext) =>
      Navigator.of(sheetContext).pop('new');

  Widget primaryButton(String label, VoidCallback onTap, {IconData? icon}) =>
      SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            textStyle: GoogleFonts.inter(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );

  final library = context.read<LibraryNotifier>();
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.backgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      final library = sheetContext.watch<LibraryNotifier>();
      final text = theme.textColor;
      final muted = text.withAlpha(150);
      final collections = library.collections;

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: text.withAlpha(50),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add to collection',
                  style: GoogleFonts.inter(
                    color: text,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$countLabel selected',
                  style: GoogleFonts.inter(color: muted, fontSize: 13.5),
                ),
                if (collections.isEmpty) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _accent.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.folder_outlined,
                        color: _accent,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No collections yet',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: text,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Create one and these books go straight in.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: muted, fontSize: 13.5),
                  ),
                  const SizedBox(height: 24),
                  primaryButton(
                    'New collection',
                    () => createNew(sheetContext),
                    icon: Icons.add,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in collections)
                          _CollectionTickRow(
                            theme: theme,
                            name: c.name,
                            subtitle:
                                '${library.bookCount(c)} book${library.bookCount(c) == 1 ? '' : 's'}',
                            ticked: bookPaths.every(c.bookPaths.contains),
                            onTap: (ticked) => library.setInCollection(
                              c.id,
                              bookPaths,
                              ticked,
                            ),
                          ),
                        InkWell(
                          onTap: () => createNew(sheetContext),
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 60,
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _accent.withAlpha(120),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: _accent,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'New collection',
                                  style: GoogleFonts.inter(
                                    color: _accent,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  primaryButton(
                    'Done',
                    () => Navigator.of(sheetContext).pop('done'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  if (result == 'done') return 'Collections updated';
  if (result != 'new' || !context.mounted) return null;
  final name = await showCollectionNameDialog(
    context,
    theme,
    helper: '$countLabel will be added',
  );
  if (name == null) return null;
  await library.createCollection(name, bookPaths);
  return 'Added $countLabel to $name';
}

class _CollectionTickRow extends StatelessWidget {
  final ReaderTheme theme;
  final String name;
  final String subtitle;
  final bool ticked;
  final ValueChanged<bool> onTap;

  const _CollectionTickRow({
    required this.theme,
    required this.name,
    required this.subtitle,
    required this.ticked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = theme.textColor;
    return InkWell(
      onTap: () => onTap(!ticked),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: text.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.folder, color: text.withAlpha(130), size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: text,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: text.withAlpha(150),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ticked ? _accent : Colors.transparent,
                border: ticked
                    ? null
                    : Border.all(color: text.withAlpha(90), width: 2),
              ),
              child: ticked
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
