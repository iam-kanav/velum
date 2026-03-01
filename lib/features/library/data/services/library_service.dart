import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:epubx/epubx.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/scanned_book.dart';

/// Top-level function for compute() — parses EPUB bytes in a background isolate.
/// Must be top-level (not a method) so Dart can send it to the isolate.
Future<ScannedBook> _parseEpubInIsolate(
  (Uint8List bytes, String fileName, String filePath) params,
) async {
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
  static const String _deletedPathsKey = 'deleted_book_paths';

  final SharedPreferences _prefs;
  final Box<ScannedBook> _booksBox;

  LibraryService(this._prefs, this._booksBox);

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
  // MIGRATION
  // ════════════════════════════════════════════════════════════════════════════

  /// Migrates existing books from SharedPreferences to Hive once
  Future<void> migrateFromSharedPreferencesIfNeeded() async {
    final legacyJson = _prefs.getString(_booksKey);
    if (legacyJson != null) {
      try {
        debugPrint('Migrating books from SharedPreferences to Hive...');
        final jsonList = jsonDecode(legacyJson) as List;
        final legacyBooks = jsonList
            .map((json) => ScannedBook.fromJson(json as Map<String, dynamic>))
            .toList();

        final Map<String, ScannedBook> booksMap = {};
        for (final book in legacyBooks) {
          booksMap[book.filePath] = book;
        }

        await _booksBox.putAll(booksMap);
        await _prefs.remove(_booksKey);
        debugPrint('Migration complete. Removed legacy data.');
      } catch (e) {
        debugPrint('Error migrating from SharedPreferences: $e');
      }
    }
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
    final deletedPaths = _getDeletedPaths();

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
        deletedPaths,
        skipDirs,
        onProgress,
      );
    } catch (e) {
      debugPrint('Error scanning device: $e');
    }

    // Prepare batch update for Hive
    final newBooksMap = <String, ScannedBook>{};
    for (final book in foundBooks) {
      if (!existingPaths.contains(book.filePath)) {
        newBooksMap[book.filePath] = book;
      }
    }

    if (newBooksMap.isNotEmpty) {
      await _booksBox.putAll(newBooksMap);
    }

    return getSavedBooks();
  }

  Future<void> _scanDirectory(
    Directory dir,
    List<ScannedBook> foundBooks,
    Set<String> existingPaths,
    Set<String> deletedPaths,
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
            deletedPaths,
            skipDirs,
            onProgress,
          );
        } else if (entity is File &&
            entity.path.toLowerCase().endsWith('.epub')) {
          // Skip if already in library or explicitly deleted by the user
          if (existingPaths.contains(entity.path)) continue;
          if (deletedPaths.contains(entity.path)) continue;

          try {
            final bytes = await entity.readAsBytes();
            final fileName = entity.path.split('/').last;
            final book = await compute(_parseEpubInIsolate, (
              bytes,
              fileName,
              entity.path,
            ));
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
            final book = await compute(_parseEpubInIsolate, (
              file.bytes!,
              file.name,
              file.path ?? file.name,
            ));
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

      final existingPaths = _booksBox.keys.cast<String>().toSet();
      final newBooksMap = <String, ScannedBook>{};

      for (final book in newBooks) {
        if (!existingPaths.contains(book.filePath)) {
          newBooksMap[book.filePath] = book;
        }
      }

      if (newBooksMap.isNotEmpty) {
        await _booksBox.putAll(newBooksMap);
      }

      return getSavedBooks();
    } catch (e) {
      debugPrint('Error picking files: $e');
      return getSavedBooks();
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BOOK STORAGE
  // ════════════════════════════════════════════════════════════════════════════

  List<ScannedBook> getSavedBooks() {
    return _booksBox.values.toList();
  }

  Future<void> addBook(ScannedBook book) async {
    if (!_booksBox.containsKey(book.filePath)) {
      await _booksBox.put(book.filePath, book);
    }
  }

  Future<void> removeBook(String filePath) async {
    await _booksBox.delete(filePath);
    await _addToDeletedPaths(filePath);
  }

  Set<String> _getDeletedPaths() {
    final json = _prefs.getString(_deletedPathsKey);
    if (json == null) return {};
    try {
      return Set<String>.from(jsonDecode(json) as List);
    } catch (_) {
      return {};
    }
  }

  Future<void> _addToDeletedPaths(String filePath) async {
    final paths = _getDeletedPaths()..add(filePath);
    await _prefs.setString(_deletedPathsKey, jsonEncode(paths.toList()));
  }

  Future<void> clearBooks() async {
    await _booksBox.clear();
  }

  Future<void> toggleBookPin(String filePath) async {
    final book = _booksBox.get(filePath);
    if (book != null) {
      final updatedBook = book.copyWith(isPinned: !book.isPinned);
      await _booksBox.put(filePath, updatedBook);
    }
  }

  Future<void> updateLastReadTime(String filePath) async {
    final book = _booksBox.get(filePath);
    if (book != null) {
      final updatedBook = book.copyWith(lastReadTime: DateTime.now());
      await _booksBox.put(filePath, updatedBook);
    }
  }

  Future<void> updateReadingProgress(
    String filePath,
    int chapterIndex,
    double scrollPosition,
  ) async {
    final book = _booksBox.get(filePath);
    if (book != null) {
      final updatedBook = book.copyWith(
        lastReadTime: DateTime.now(),
        lastReadChapter: chapterIndex,
        lastReadPosition: scrollPosition,
      );
      await _booksBox.put(filePath, updatedBook);
    }
  }
}
