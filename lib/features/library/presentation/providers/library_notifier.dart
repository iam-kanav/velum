import 'package:flutter/material.dart';
import '../../data/models/scanned_book.dart';
import '../../data/services/library_service.dart';

enum LibrarySortOption { recent, alphabetical }

class LibraryNotifier extends ChangeNotifier {
  final LibraryService _libraryService;

  LibraryNotifier(this._libraryService) {
    _loadBooks();
    _initAutoScan();
  }

  List<ScannedBook> _books = [];
  List<ScannedBook> get books => _books;

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

  /// Initialize auto-scan on startup if enabled and permitted
  Future<void> _initAutoScan() async {
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
    if (isAutoScanEnabled) {
      final hasPermission = await _libraryService.hasStoragePermission();
      if (hasPermission) {
        await scanDevice();
        return;
      }
    }
    _loadBooks();
  }

  Future<void> removeBook(ScannedBook book) async {
    await _libraryService.removeBook(book.filePath);
    _loadBooks();
  }
}
