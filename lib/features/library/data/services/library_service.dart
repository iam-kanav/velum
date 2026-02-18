import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:epubx/epubx.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/scanned_book.dart';

/// Top-level function for compute() — parses EPUB bytes in a background isolate.
/// Must be top-level (not a method) so Dart can send it to the isolate.
Future<ScannedBook> _parseEpubInIsolate(
    (Uint8List bytes, String fileName, String filePath) params) async {
  final (bytes, fileName, filePath) = params;
  try {
    final epubBook = await EpubReader.readBook(bytes);
    String? coverBase64;
    try {
      coverBase64 = _extractCoverFromEpub(epubBook);
    } catch (_) {}
    return ScannedBook(
      filePath: filePath,
      title: epubBook.Title ?? fileName.replaceAll('.epub', ''),
      author: epubBook.Author ?? 'Unknown Author',
      addedAt: DateTime.now(),
      coverBase64: coverBase64,
    );
  } catch (_) {
    return ScannedBook(
      filePath: filePath,
      title: fileName.replaceAll('.epub', ''),
      author: 'Unknown Author',
      addedAt: DateTime.now(),
    );
  }
}

/// Top-level helper for cover extraction inside the isolate.
String? _extractCoverFromEpub(EpubBook epubBook) {
  if (epubBook.Content?.Images == null) return null;
  final images = epubBook.Content!.Images!;
  final coverPatterns = ['cover', 'front', 'title'];
  for (final pattern in coverPatterns) {
    for (final entry in images.entries) {
      if (entry.key.toLowerCase().contains(pattern)) {
        if (entry.value.Content != null) {
          return base64Encode(entry.value.Content!);
        }
      }
    }
  }
  if (images.isNotEmpty) {
    final firstImage = images.values.first;
    if (firstImage.Content != null) {
      return base64Encode(firstImage.Content!);
    }
  }
  return null;
}

class LibraryService {
  static const String _booksKey = 'scanned_books';
  static const String _onboardingCompleteKey = 'onboarding_complete';
  static const String _autoScanEnabledKey = 'auto_scan_enabled';

  final SharedPreferences _prefs;

  // In-memory cache to avoid repeated JSON deserialization from SharedPreferences
  List<ScannedBook>? _cachedBooks;

  LibraryService(this._prefs);

  // ════════════════════════════════════════════════════════════════════════════
  // ONBOARDING
  // ════════════════════════════════════════════════════════════════════════════

  bool get isOnboardingComplete =>
      _prefs.getBool(_onboardingCompleteKey) ?? false;

  Future<void> completeOnboarding() async {
    await _prefs.setBool(_onboardingCompleteKey, true);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // AUTO-SCAN SETTINGS
  // ════════════════════════════════════════════════════════════════════════════

  bool get isAutoScanEnabled => _prefs.getBool(_autoScanEnabledKey) ?? false;

  Future<void> setAutoScanEnabled(bool enabled) async {
    await _prefs.setBool(_autoScanEnabledKey, enabled);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // STORAGE PERMISSION
  // ════════════════════════════════════════════════════════════════════════════

  Future<bool> hasStoragePermission() async {
    if (Platform.isAndroid) {
      return await Permission.manageExternalStorage.isGranted;
    }
    return true; // iOS/desktop don't need this
  }

  Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    }
    return true;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // DEVICE SCANNING - Recursively find all EPUBs on device
  // ════════════════════════════════════════════════════════════════════════════

  Future<List<ScannedBook>> scanDeviceForEpubs({
    void Function(int count)? onProgress,
  }) async {
    final List<ScannedBook> foundBooks = [];
    final existingBooks = getSavedBooks();
    final existingPaths = existingBooks.map((b) => b.filePath).toSet();

    try {
      // Common Android storage root
      final rootDir = Directory('/storage/emulated/0');
      if (!await rootDir.exists()) {
        debugPrint('Storage root not found');
        return existingBooks;
      }

      // Directories to skip (performance / irrelevant)
      final skipDirs = {
        'Android',
        '.thumbnails',
        '.cache',
        'cache',
        '.trash',
        'LOST.DIR',
      };

      await _scanDirectory(
        rootDir,
        foundBooks,
        existingPaths,
        skipDirs,
        onProgress,
      );
    } catch (e) {
      debugPrint('Error scanning device: $e');
    }

    // Merge with existing books
    final allBooks = List<ScannedBook>.from(existingBooks);
    for (final book in foundBooks) {
      if (!allBooks.any((b) => b.filePath == book.filePath)) {
        allBooks.add(book);
      }
    }

    await _saveBooks(allBooks);
    return allBooks;
  }

  Future<void> _scanDirectory(
    Directory dir,
    List<ScannedBook> foundBooks,
    Set<String> existingPaths,
    Set<String> skipDirs,
    void Function(int count)? onProgress,
  ) async {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final dirName = entity.path.split('/').last;
          if (skipDirs.contains(dirName) || dirName.startsWith('.')) {
            continue;
          }
          await _scanDirectory(
            entity,
            foundBooks,
            existingPaths,
            skipDirs,
            onProgress,
          );
        } else if (entity is File &&
            entity.path.toLowerCase().endsWith('.epub')) {
          // Skip if already in library
          if (existingPaths.contains(entity.path)) continue;

          try {
            final bytes = await entity.readAsBytes();
            final fileName = entity.path.split('/').last;
            final book = await compute(
              _parseEpubInIsolate,
              (bytes, fileName, entity.path),
            );
            foundBooks.add(book);
            onProgress?.call(foundBooks.length);
          } catch (e) {
            final fileName = entity.path.split('/').last;
            foundBooks.add(
              ScannedBook(
                filePath: entity.path,
                title: fileName.replaceAll('.epub', ''),
                author: 'Unknown Author',
                addedAt: DateTime.now(),
              ),
            );
            onProgress?.call(foundBooks.length);
          }
        }
      }
    } catch (e) {
      // Permission denied for this directory, skip
      debugPrint('Cannot access ${dir.path}: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FILE PICKING - Pick individual EPUB files (works reliably on Android)
  // ════════════════════════════════════════════════════════════════════════════

  Future<List<ScannedBook>> pickEpubFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
        allowMultiple: true,
        withData: true, // Important: Get file bytes directly
      );

      if (result == null || result.files.isEmpty) {
        return getSavedBooks();
      }

      final List<ScannedBook> newBooks = [];

      for (final file in result.files) {
        if (file.bytes != null) {
          try {
            final book = await compute(
              _parseEpubInIsolate,
              (file.bytes!, file.name, file.path ?? file.name),
            );
            newBooks.add(book);
          } catch (e) {
            debugPrint('Failed to parse ${file.name}: $e');
            newBooks.add(
              ScannedBook(
                filePath: file.path ?? file.name,
                title: file.name.replaceAll('.epub', ''),
                author: 'Unknown Author',
                addedAt: DateTime.now(),
              ),
            );
          }
        }
      }

      // Add new books to existing collection
      final existingBooks = getSavedBooks();
      for (final book in newBooks) {
        if (!existingBooks.any((b) => b.filePath == book.filePath)) {
          existingBooks.add(book);
        }
      }

      await _saveBooks(existingBooks);
      return existingBooks;
    } catch (e) {
      debugPrint('Error picking files: $e');
      return getSavedBooks();
    }
  }


  // ════════════════════════════════════════════════════════════════════════════
  // BOOK STORAGE
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _saveBooks(List<ScannedBook> books) async {
    _cachedBooks = List.from(books);
    final jsonList = books.map((b) => b.toJson()).toList();
    await _prefs.setString(_booksKey, jsonEncode(jsonList));
  }

  List<ScannedBook> getSavedBooks() {
    if (_cachedBooks != null) return List.from(_cachedBooks!);

    final jsonString = _prefs.getString(_booksKey);
    if (jsonString == null) return [];

    try {
      final jsonList = jsonDecode(jsonString) as List;
      _cachedBooks = jsonList
          .map((json) => ScannedBook.fromJson(json as Map<String, dynamic>))
          .toList();
      return List.from(_cachedBooks!);
    } catch (e) {
      return [];
    }
  }

  Future<void> addBook(ScannedBook book) async {
    final books = getSavedBooks();
    // Avoid duplicates
    if (!books.any((b) => b.filePath == book.filePath)) {
      books.add(book);
      await _saveBooks(books);
    }
  }

  Future<void> removeBook(String filePath) async {
    final books = getSavedBooks();
    books.removeWhere((b) => b.filePath == filePath);
    await _saveBooks(books);
  }

  Future<void> clearBooks() async {
    _cachedBooks = null;
    await _prefs.remove(_booksKey);
  }

  Future<void> toggleBookPin(String filePath) async {
    final books = getSavedBooks();
    final index = books.indexWhere((b) => b.filePath == filePath);
    if (index != -1) {
      final book = books[index];
      books[index] = book.copyWith(isPinned: !book.isPinned);
      await _saveBooks(books);
    }
  }

  Future<void> updateLastReadTime(String filePath) async {
    final books = getSavedBooks();
    final index = books.indexWhere((b) => b.filePath == filePath);
    if (index != -1) {
      final book = books[index];
      books[index] = book.copyWith(lastReadTime: DateTime.now());
      await _saveBooks(books);
    }
  }

  Future<void> updateReadingProgress(
    String filePath,
    int chapterIndex,
    double scrollPosition,
  ) async {
    final books = getSavedBooks();
    final index = books.indexWhere((b) => b.filePath == filePath);
    if (index != -1) {
      final book = books[index];
      books[index] = book.copyWith(
        lastReadTime: DateTime.now(),
        lastReadChapter: chapterIndex,
        lastReadPosition: scrollPosition,
      );
      await _saveBooks(books);
    }
  }
}
