import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:epubx/epubx.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/scanned_book.dart';

/// Top-level function for compute() — parses EPUB bytes in a background isolate.
/// Must be top-level (not a method) so Dart can send it to the isolate.
Future<ScannedBook> _parseEpubInIsolate(
  (Uint8List bytes, String fileName, String filePath) params,
) async {
  final (bytes, fileName, filePath) = params;
  try {
    // Only title, author and one cover image are needed, so open the book
    // lazily instead of unpacking (and decoding) everything.
    final bookRef = await EpubReader.openBook(bytes);
    String? coverBase64;
    try {
      coverBase64 = await _extractCover(bookRef);
    } catch (_) {}
    return ScannedBook(
      filePath: filePath,
      title: bookRef.Title ?? fileName.replaceAll('.epub', ''),
      author: bookRef.Author ?? 'Unknown Author',
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

/// Pick the cover image (by name, else the first image) and read only it.
Future<String?> _extractCover(EpubBookRef bookRef) async {
  final images = bookRef.Content?.Images;
  if (images == null || images.isEmpty) return null;
  final key = ['cover', 'front', 'title']
          .map((pattern) => images.keys
              .where((k) => k.toLowerCase().contains(pattern))
              .firstOrNull)
          .firstWhere((k) => k != null, orElse: () => null) ??
      images.keys.first;
  return base64Encode(await images[key]!.readContentAsBytes());
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

      // Copy picked files to a persistent app directory with unique names
      // so multiple versions of the same book don't overwrite each other.
      final appDir = await getApplicationDocumentsDirectory();
      final booksDir = Directory(p.join(appDir.path, 'books'));
      if (!await booksDir.exists()) {
        await booksDir.create(recursive: true);
      }

      final List<ScannedBook> newBooks = [];

      for (final file in result.files) {
        if (file.bytes != null) {
          try {
            // Save with a UUID prefix to guarantee uniqueness
            final uniqueName = '${const Uuid().v4()}_${file.name}';
            final savedFile = File(p.join(booksDir.path, uniqueName));
            await savedFile.writeAsBytes(file.bytes!);

            final book = await compute(_parseEpubInIsolate, (
              file.bytes!,
              file.name,
              savedFile.path,
            ));
            newBooks.add(book);
          } catch (e) {
            debugPrint('Failed to parse ${file.name}: $e');
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

    // Clean up the copied file if it's in our books directory
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final booksDir = p.join(appDir.path, 'books');
      if (filePath.startsWith(booksDir)) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Error deleting book file: $e');
    }
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
