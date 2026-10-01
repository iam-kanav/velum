import 'package:flutter/material.dart';
import '../../data/models/scanned_book.dart';
import '../../data/models/book_collection.dart';
import '../../data/services/collection_service.dart';
import '../../data/services/library_service.dart';

enum LibrarySortOption { recent, alphabetical }

class LibraryNotifier extends ChangeNotifier {
  final LibraryService _libraryService;
  final CollectionService _collectionService;

  LibraryNotifier(this._libraryService, this._collectionService) {
    _collections = _collectionService.load();
    _loadBooks();
    _initAutoScan();
  }

  List<ScannedBook> _books = [];
  List<ScannedBook> get books => _books;

  // ════════════════════════════════════════════════════════════════════════════
  // COLLECTIONS
  // ════════════════════════════════════════════════════════════════════════════

  List<BookCollection> _collections = [];
  List<BookCollection> get collections => _collections;

  /// The collection being shown, or null for all books.
  String? _currentCollectionId;
  BookCollection? get currentCollection =>
      _collections.where((c) => c.id == _currentCollectionId).firstOrNull;

  /// Books of [collection] that are still in the library.
  int bookCount(BookCollection collection) {
    final paths = _books.map((b) => b.filePath).toSet();
    return collection.bookPaths.where(paths.contains).length;
  }

  void showCollection(String? id) {
    _currentCollectionId = id;
    _sortedAndFilteredCache = null;
    notifyListeners();
  }

  void _reloadCollections() {
    _collections = _collectionService.load();
    if (currentCollection == null) _currentCollectionId = null;
    _sortedAndFilteredCache = null;
    notifyListeners();
  }

  Future<BookCollection> createCollection(
    String name, {
    Iterable<String> bookPaths = const [],
    bool hideFromLibrary = false,
  }) async {
    final c = await _collectionService.create(
      name,
      bookPaths.toList(),
      hideFromLibrary: hideFromLibrary,
    );
    _reloadCollections();
    return c;
  }

  Future<void> updateCollection(
    String id, {
    String? name,
    bool? hideFromLibrary,
  }) async {
    await _collectionService.update(
      id,
      name: name,
      hideFromLibrary: hideFromLibrary,
    );
    _reloadCollections();
  }

  /// Paths kept out of "All books" by collections set to hide their books.
  Set<String> get _hiddenFromLibrary => {
    for (final c in _collections)
      if (c.hideFromLibrary) ...c.bookPaths,
  };

  /// Number of books "All books" shows.
  int get allBooksCount {
    final hidden = _hiddenFromLibrary;
    return _books.where((b) => !hidden.contains(b.filePath)).length;
  }

  Future<void> deleteCollection(String id) async {
    await _collectionService.delete(id);
    _reloadCollections();
  }

  Future<void> setInCollection(
    String id,
    Iterable<String> bookPaths,
    bool member,
  ) async {
    await _collectionService.setMembership(id, bookPaths, member);
    _reloadCollections();
  }

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  LibrarySortOption _currentSort = LibrarySortOption.recent;
  LibrarySortOption get currentSort => _currentSort;

  // Cache sorted/filtered result to avoid recomputing on every access
  List<ScannedBook>? _sortedAndFilteredCache;

  final bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  int _scanProgress = 0;
  int get scanProgress => _scanProgress;

  bool get isOnboardingComplete => _libraryService.isOnboardingComplete;

  bool get isAutoScanEnabled => _libraryService.isAutoScanEnabled;

  /// Returns the list of books filtered by search query and sorted by current option.
  /// Pinned books are always at the top. Result is cached until inputs change.
  List<ScannedBook> get sortedAndFilteredBooks {
    if (_sortedAndFilteredCache != null) return _sortedAndFilteredCache!;

    List<ScannedBook> filtered = List.from(_books);

    // 0. Limit to the open collection
    final collection = currentCollection;
    if (collection != null) {
      final paths = collection.bookPaths.toSet();
      filtered = filtered.where((b) => paths.contains(b.filePath)).toList();
    } else {
      final hidden = _hiddenFromLibrary;
      if (hidden.isNotEmpty) {
        filtered = filtered.where((b) => !hidden.contains(b.filePath)).toList();
      }
    }

    // 1. Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((b) {
        return b.title.toLowerCase().contains(query) ||
            b.author.toLowerCase().contains(query);
      }).toList();
    }

    // 2. Sort
    filtered.sort((a, b) {
      // Pinned always first
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }

      switch (_currentSort) {
        case LibrarySortOption.recent:
          // Sort by lastReadTime desc, then addedAt desc
          final aTime = a.lastReadTime ?? a.addedAt ?? DateTime(0);
          final bTime = b.lastReadTime ?? b.addedAt ?? DateTime(0);
          return bTime.compareTo(aTime);

        case LibrarySortOption.alphabetical:
          final aTitle = a.title;
          final bTitle = b.title;
          return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
      }
    });

    _sortedAndFilteredCache = filtered;
    return filtered;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _sortedAndFilteredCache = null;
    notifyListeners();
  }

  void setSortOption(LibrarySortOption option) {
    _currentSort = option;
    _sortedAndFilteredCache = null;
    notifyListeners();
  }

  void _loadBooks() {
    _books = _libraryService.getSavedBooks();
    _sortedAndFilteredCache = null;
    notifyListeners();
  }

  /// Drop library entries whose files were deleted outside the app, and
  /// take them out of collections too.
  Future<void> _removeMissingBooks() async {
    final missing = await _libraryService.removeMissingBooks();
    if (missing.isEmpty) return;
    for (final path in missing) {
      await _collectionService.forgetBook(path);
    }
    _collections = _collectionService.load();
    _loadBooks();
  }

  /// Initialize auto-scan on startup if enabled and permitted
  Future<void> _initAutoScan() async {
    await _removeMissingBooks();
    if (_libraryService.isAutoScanEnabled) {
      final hasPermission = await _libraryService.hasStoragePermission();
      if (hasPermission) {
        await scanDevice();
      }
    }
  }

  Future<void> completeOnboarding() async {
    await _libraryService.completeOnboarding();
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PINNING & HISTORY
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> toggleBookPin(ScannedBook book) async {
    await _libraryService.toggleBookPin(book.filePath);
    _loadBooks();
  }

  Future<void> updateLastRead(ScannedBook book) async {
    await _libraryService.updateLastReadTime(book.filePath);
    _loadBooks();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // AUTO-SCAN
  // ════════════════════════════════════════════════════════════════════════════

  Future<bool> hasStoragePermission() async {
    return await _libraryService.hasStoragePermission();
  }

  Future<bool> requestStoragePermission() async {
    return await _libraryService.requestStoragePermission();
  }

  Future<void> setAutoScanEnabled(bool enabled) async {
    await _libraryService.setAutoScanEnabled(enabled);
    notifyListeners();
  }

  /// Scan the entire device for EPUB files
  Future<void> scanDevice() async {
    _isScanning = true;
    _scanProgress = 0;
    notifyListeners();

    try {
      final stopwatch = Stopwatch()..start();
      _books = await _libraryService.scanDeviceForEpubs(
        onProgress: (count) {
          _scanProgress = count;
          // Throttle UI updates to max once every 500ms
          if (stopwatch.elapsedMilliseconds >= 500) {
            stopwatch.reset();
            notifyListeners();
          }
        },
      );
    } finally {
      _isScanning = false;
      _sortedAndFilteredCache = null;
      notifyListeners();
    }
    await _removeMissingBooks();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // MANUAL FILE PICKING
  // ════════════════════════════════════════════════════════════════════════════

  /// Pick EPUB files and add them to library
  Future<void> pickFiles() async {
    _isScanning = true;
    notifyListeners();

    try {
      _books = await _libraryService.pickEpubFiles();
    } finally {
      _isScanning = false;
      _sortedAndFilteredCache = null;
      notifyListeners();
    }
  }

  /// Alias for pickFiles - used by UI
  Future<void> pickFolder() async {
    await pickFiles();
  }

  Future<void> refresh() async {
    await _removeMissingBooks();
    if (isAutoScanEnabled) {
      final hasPermission = await _libraryService.hasStoragePermission();
      if (hasPermission) {
        await scanDevice();
        return;
      }
    }
    _loadBooks();
  }

  Future<void> saveNote(String filePath, String title) async {
    await _libraryService.saveNote(filePath, title);
    _loadBooks();
  }

  /// See [LibraryService.removeBook]. Returns false if the device file
  /// couldn't be deleted.
  Future<bool> removeBook(ScannedBook book, {bool deleteFile = false}) async {
    final ok = await _libraryService.removeBook(
      book.filePath,
      deleteFile: deleteFile,
    );
    await _collectionService.forgetBook(book.filePath);
    _collections = _collectionService.load();
    _loadBooks();
    return ok;
  }
}
