import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:velum/features/settings/data/models/reader_settings.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import 'package:velum/features/library/presentation/providers/library_notifier.dart';
import 'package:velum/features/library/data/models/scanned_book.dart';
import 'package:velum/core/theme/app_colors.dart';

const Color _accent = AppColors.accent;

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final Set<String> _selectedBooks = {};
  bool _selectionMode = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // Cache decoded cover images to avoid base64 decoding on every rebuild
  final Map<String, Uint8List> _coverCache = {};

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// Debounce search input to avoid rebuilding the grid on every keystroke
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        context.read<LibraryNotifier>().setSearchQuery(value);
      }
    });
  }

  void _toggleSelection(ScannedBook book) {
    setState(() {
      if (_selectedBooks.contains(book.filePath)) {
        _selectedBooks.remove(book.filePath);
        if (_selectedBooks.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedBooks.add(book.filePath);
      }
    });
  }

  void _startSelectionMode(ScannedBook book) {
    setState(() {
      _selectionMode = true;
      _selectedBooks.add(book.filePath);
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedBooks.clear();
    });
  }

  void _deleteSelected() async {
    final libraryNotifier = context.read<LibraryNotifier>();

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Books'),
        content: Text(
          'Remove ${_selectedBooks.length} book${_selectedBooks.length == 1 ? '' : 's'} from your library?\n\nThis will not delete the files from your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final path in _selectedBooks) {
        await libraryNotifier.removeBook(
          ScannedBook(filePath: path, title: '', author: ''),
        );
      }
      _cancelSelection();
    }
  }

  void _togglePinSelected() async {
    final libraryNotifier = context.read<LibraryNotifier>();
    for (final path in _selectedBooks) {
      // Find the book object to toggle
      try {
        final book = libraryNotifier.books.firstWhere(
          (b) => b.filePath == path,
        );
        await libraryNotifier.toggleBookPin(book);
      } catch (e) {
        // Book not found, skip
      }
    }
    _cancelSelection();
  }

  /// Decode and cache cover image bytes to avoid base64 decoding on every rebuild
  Uint8List _decodeCover(ScannedBook book) {
    return _coverCache.putIfAbsent(
      book.filePath,
      () => base64Decode(book.coverBase64!),
    );
  }

  // Generate consistent color from title
  Color _getBookColor(String title) {
    // Use absolute value of hashCode to avoid negative numbers
    final hash = title.hashCode.abs();
    // Use a curated list of nice colors instead of primaries
    const colors = [
      Color(0xFF6366F1), // Indigo
      Color(0xFF8B5CF6), // Violet
      Color(0xFFA855F7), // Purple
      Color(0xFFEC4899), // Pink
      Color(0xFFF43F5E), // Rose
      Color(0xFFEF4444), // Red
      Color(0xFFF97316), // Orange
      Color(0xFFF59E0B), // Amber
      Color(0xFF10B981), // Emerald
      Color(0xFF14B8A6), // Teal
      Color(0xFF06B6D4), // Cyan
      Color(0xFF0EA5E9), // Sky
    ];
    return colors[hash % colors.length];
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Widget _buildDrawer(ReaderTheme theme) {
    Widget item(IconData icon, String label, String? subtitle, VoidCallback onTap) {
      return ListTile(
        leading: Icon(icon, color: theme.textColor),
        title: Text(
          label,
          style: GoogleFonts.inter(
            color: theme.textColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: theme.textColor.withAlpha(120),
                  fontSize: 12.5,
                ),
              ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        onTap: () {
          Navigator.of(context).pop(); // close the drawer
          onTap();
        },
      );
    }

    return Drawer(
      backgroundColor: theme.backgroundColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Text(
                'Velum',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: theme.textColor,
                ),
              ),
            ),
            item(
              Icons.note_add_outlined,
              'New File',
              'Paste text to listen to',
              () => context.push('/editor'),
            ),
            item(
              Icons.settings_outlined,
              'Settings',
              null,
              () => context.push('/settings'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsNotifier = context.watch<SettingsNotifier>();
    final libraryNotifier = context.watch<LibraryNotifier>();
    final theme = settingsNotifier.settings.appTheme;
    final books = libraryNotifier.sortedAndFilteredBooks;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.backgroundColor,
      drawer: _buildDrawer(theme),
      body: RefreshIndicator(
        onRefresh: () => libraryNotifier.refresh(),
        color: _accent,
        backgroundColor: theme.backgroundColor,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 120.0,
              floating: false,
              pinned: true,
              backgroundColor: theme.backgroundColor,
              automaticallyImplyLeading: false,
              leading: _selectionMode
                  ? IconButton(
                      icon: Icon(Icons.close, color: theme.textColor),
                      onPressed: _cancelSelection,
                    )
                  : IconButton(
                      icon: Icon(Icons.menu, color: theme.textColor),
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      tooltip: 'Menu',
                    ),
              title: _selectionMode
                  ? Text(
                      '${_selectedBooks.length} selected',
                      style: TextStyle(color: theme.textColor),
                    )
                  : null,
              actions: [
                if (_selectionMode) ...[
                  IconButton(
                    icon: Icon(Icons.push_pin_outlined, color: theme.textColor),
                    onPressed: _togglePinSelected,
                    tooltip: 'Pin/Unpin',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: _selectedBooks.isNotEmpty
                        ? _deleteSelected
                        : null,
                    tooltip: 'Delete',
                  ),
                ] else
                  IconButton(
                    icon: Icon(Icons.settings_outlined, color: theme.textColor),
                    onPressed: () => context.push('/settings'),
                    tooltip: 'Settings',
                  ),
                const SizedBox(width: 8),
              ],
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  // 1 when fully expanded, 0 when collapsed: slide the title
                  // right as it collapses so it clears the menu button.
                  final top = MediaQuery.of(context).padding.top;
                  final t = ((constraints.maxHeight - top - kToolbarHeight) /
                          (120.0 - kToolbarHeight))
                      .clamp(0.0, 1.0);
                  return FlexibleSpaceBar(
                    titlePadding: EdgeInsets.only(
                      left: 20 + 52 * (1 - t),
                      bottom: 16,
                    ),
                    title: Text(
                      'Velum',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.textColor,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Search and Sort Bar
            if (!_selectionMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Row(
                    children: [
                      // Search Bar
                      Expanded(
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: theme.textColor.withAlpha(15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: GoogleFonts.inter(
                              color: theme.textColor,
                              fontSize: 16,
                            ),
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Search books...',
                              hintStyle: GoogleFonts.inter(
                                color: theme.textColor.withAlpha(100),
                                fontSize: 16,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: theme.textColor.withAlpha(100),
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical:
                                    16, // Vertically centered in 56px height
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Sort Toggle Button
                      GestureDetector(
                        onTap: () {
                          final newSort =
                              libraryNotifier.currentSort ==
                                  LibrarySortOption.recent
                              ? LibrarySortOption.alphabetical
                              : LibrarySortOption.recent;
                          libraryNotifier.setSortOption(newSort);
                        },
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: theme.textColor.withAlpha(15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Text(
                                libraryNotifier.currentSort ==
                                        LibrarySortOption.recent
                                    ? 'Recent'
                                    : 'A-Z',
                                style: GoogleFonts.inter(
                                  color: theme.textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Icon(
                                  Icons.sort,
                                  color: theme.textColor.withAlpha(180),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (books.isEmpty && libraryNotifier.searchQuery.isNotEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    'No books found matching "${libraryNotifier.searchQuery}"',
                    style: TextStyle(color: theme.textColor.withAlpha(150)),
                  ),
                ),
              )
            else if (books.isEmpty)
              SliverFillRemaining(
                child: _buildEmptyState(context, theme, libraryNotifier),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final book = books[index];
                    return _buildBookItem(
                      context,
                      book,
                      theme,
                      libraryNotifier, // Pass notifier to handle tap updates
                    );
                  }, childCount: books.length),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: !_selectionMode
          ? FloatingActionButton(
              onPressed: () => libraryNotifier.pickFiles(),
              backgroundColor: _accent,
              child: libraryNotifier.isScanning
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ReaderTheme theme,
    LibraryNotifier notifier,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: _accent.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.menu_book, size: 50, color: _accent),
            ),
            const SizedBox(height: 24),
            Text(
              'No Books Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: theme.textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Add EPUB files from your device to build your library.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: theme.textColor.withAlpha(150),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: notifier.isScanning
                    ? null
                    : () => notifier.pickFiles(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                icon: notifier.isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add),
                label: Text(
                  notifier.isScanning ? 'Adding...' : 'Add EPUB Files',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Pull down to refresh',
              style: TextStyle(
                fontSize: 13,
                color: theme.textColor.withAlpha(100),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookItem(
    BuildContext context,
    ScannedBook book,
    ReaderTheme theme,
    LibraryNotifier notifier,
  ) {
    final isSelected = _selectedBooks.contains(book.filePath);
    final bookColor = _getBookColor(
      book.filePath,
    ); // Use filePath for unique color per book

    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          _toggleSelection(book);
        } else {
          // Update last read time and navigate
          notifier.updateLastRead(book);
          context.push('/reader?path=${Uri.encodeComponent(book.filePath)}');
        }
      },
      onLongPress: () {
        if (!_selectionMode) {
          _startSelectionMode(book);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _getCardColor(theme),
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: _accent, width: 3) : null,
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? _accent.withAlpha(40)
                  : Colors.black.withAlpha(15),
              blurRadius: isSelected ? 15 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Book cover
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: book.coverBase64 != null
                        ? Image.memory(
                            _decodeCover(book),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildCoverPlaceholder(bookColor);
                            },
                          )
                        : _buildCoverPlaceholder(bookColor),
                  ),
                ),
                // Book info
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.textColor,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          book.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textColor.withAlpha(150),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Pin Indicator
            if (book.isPinned && !isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(50),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.push_pin,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            // Selection indicator
            if (_selectionMode)
              Positioned(
                top: 8,
                right: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isSelected ? _accent : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? _accent : Colors.grey,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getCardColor(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.dark:
        return const Color(0xFF2A2A2A);
      case ReaderTheme.sepia:
        return const Color(0xFFEDE4D3);
      case ReaderTheme.light:
        return Colors.white;
    }
  }

  Widget _buildCoverPlaceholder(Color bookColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bookColor.withAlpha(200), bookColor],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.menu_book,
          size: 48,
          color: Colors.white.withAlpha(200),
        ),
      ),
    );
  }
}
