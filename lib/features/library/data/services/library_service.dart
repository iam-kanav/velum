import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';
import 'package:epubx/epubx.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/scanned_book.dart';
import '../../../notes/data/note_service.dart';
import '../../../../core/storage/app_directory.dart';
import '../../../../core/storage/book_data.dart';

final _epubExtension = RegExp(r'\.epub$', caseSensitive: false);

/// The entry for a book that has no usable metadata: titled after its file.
ScannedBook _untitledBook(String fileName, String filePath) => ScannedBook(
  filePath: filePath,
  title: fileName.replaceFirst(_epubExtension, ''),
  author: 'Unknown Author',
  addedAt: DateTime.now(),
);

/// epubx gives an empty string, not null, for a missing title or author.
String _orElse(String? value, String fallback) =>
    value == null || value.trim().isEmpty ? fallback : value;

/// Top-level function for compute() — reads the EPUB at `readPath` and parses
/// it in a background isolate, as the library entry for `filePath`.
/// Must be top-level (not a method) so Dart can send it to the isolate.
/// Null if the file can't be read at all.
Future<ScannedBook?> _parseEpubInIsolate(
  (String readPath, String fileName, String filePath) params,
) async {
  final (readPath, fileName, filePath) = params;
  final Uint8List bytes;
  try {
    bytes = await File(readPath).readAsBytes();
  } catch (_) {
    return null;
  }
  final untitled = _untitledBook(fileName, filePath);
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
      title: _orElse(bookRef.Title, untitled.title),
      author: _orElse(bookRef.Author, untitled.author),
      addedAt: untitled.addedAt,
      coverBase64: coverBase64,
    );
  } catch (_) {
    return untitled;
  }
}

/// Pick the cover image (by name, else the first image) and read only it.
Future<String?> _extractCover(EpubBookRef bookRef) async {
  final images = bookRef.Content?.Images;
  if (images == null || images.isEmpty) return null;
  final key =
      ['cover', 'front', 'title']
          .map(
            (pattern) => images.keys
                .where((k) => k.toLowerCase().contains(pattern))
                .firstOrNull,
          )
          .firstWhere((k) => k != null, orElse: () => null) ??
      images.keys.first;
  return base64Encode(await images[key]!.readContentAsBytes());
}

/// What a scan changed in the library.
class ScanResult {
  /// How many new books it added.
  final int added;

  /// Books whose file was moved or renamed outside the app: old path to new.
  final Map<String, String> moved;

  /// Paths of books dropped because their file is gone.
  final List<String> removed;

  const ScanResult({
    this.added = 0,
    this.moved = const {},
    this.removed = const [],
  });
}

class LibraryService {
  static const String _booksKey = 'scanned_books';
  static const String _onboardingCompleteKey = 'onboarding_complete';
  static const String _autoScanEnabledKey = 'auto_scan_enabled';
  static const String _deletedPathsKey = 'deleted_book_paths';
  static const String _sortKey = 'library_sort';

  /// A scan saves what it has found every this many books, so one that is
  /// interrupted doesn't lose everything.
  static const int _saveBatchSize = 20;

  // Directories a scan skips (performance / irrelevant)
  static const _skipDirs = {
    'Android',
    '.thumbnails',
    '.cache',
    'cache',
    '.trash',
    'LOST.DIR',
    'node_modules',
  };

  final SharedPreferences _prefs;
  final Box<ScannedBook> _booksBox;
  final List<Directory>? _scanRootsOverride;

  /// [scanRoots] replaces the device folders a scan looks in (for tests).
  LibraryService(this._prefs, this._booksBox, {List<Directory>? scanRoots})
    : _scanRootsOverride = scanRoots;

  // ════════════════════════════════════════════════════════════════════════════
  // ONBOARDING
  // ════════════════════════════════════════════════════════════════════════════

  bool get isOnboardingComplete =>
      _prefs.getBool(_onboardingCompleteKey) ?? false;

  Future<void> completeOnboarding() async {
    await _prefs.setBool(_onboardingCompleteKey, true);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LIBRARY SETTINGS
  // ════════════════════════════════════════════════════════════════════════════

  bool get isAutoScanEnabled => _prefs.getBool(_autoScanEnabledKey) ?? false;

  Future<void> setAutoScanEnabled(bool enabled) async {
    await _prefs.setBool(_autoScanEnabledKey, enabled);
  }

  /// Name of the sort order the library was last shown in, if any.
  String? get sortOption => _prefs.getString(_sortKey);

  Future<void> setSortOption(String name) => _prefs.setString(_sortKey, name);

  // ════════════════════════════════════════════════════════════════════════════
  // STORAGE PERMISSION
  // ════════════════════════════════════════════════════════════════════════════

  /// All-files access on Android 11 and later. Earlier versions don't have
  /// it (it is reported as restricted) and use the classic storage permission.
  Future<Permission> _storagePermission() async =>
      await Permission.manageExternalStorage.isRestricted
      ? Permission.storage
      : Permission.manageExternalStorage;

  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true; // desktop doesn't need this
    return (await _storagePermission()).isGranted;
  }

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    return (await (await _storagePermission()).request()).isGranted;
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

  /// Add the EPUBs on the device that aren't in the library yet, and drop
  /// books whose file is gone. A new file that is plainly one of the missing
  /// books (moved or renamed folder) takes that book's place instead, with
  /// its progress, pin, highlights and bookmarks.
  Future<ScanResult> scanDeviceForEpubs({
    void Function(int count)? onProgress,
  }) async {
    final missing = await _missingBooks();
    final known = _booksBox.keys.cast<String>().toSet();
    final deletedPaths = _getDeletedPaths();

    final unsaved = <String, ScannedBook>{};
    // Found files that look like a missing book. Held back until the scan
    // ends: saved now, an interrupted scan would leave them as new books
    // and the next one would drop the book they came from.
    final candidates = <ScannedBook>[];
    var found = 0;

    Future<void> onFound(ScannedBook book) async {
      if (missing.any((m) => _sameBook(m, book))) {
        candidates.add(book);
      } else {
        unsaved[book.filePath] = book;
        if (unsaved.length >= _saveBatchSize) {
          await _booksBox.putAll(Map.of(unsaved));
          unsaved.clear();
        }
      }
      found++;
      onProgress?.call(found);
    }

    try {
      for (final rootDir in _scanRootsOverride ?? _scanRoots()) {
        if (!await rootDir.exists()) continue;
        await _scanDirectory(rootDir, known, deletedPaths, onFound);
      }
    } catch (e) {
      debugPrint('Error scanning device: $e');
    }

    final moved = <String, String>{};
    for (final book in candidates) {
      final matches = missing.where((m) => _sameBook(m, book)).toList();
      final old = matches.length == 1 ? matches.single : null;
      if (old == null || moved.containsKey(old.filePath)) {
        // Can't tell which book it was (or a second copy of one): new book.
        unsaved[book.filePath] = book;
        continue;
      }
      await _booksBox.put(
        book.filePath,
        old.copyWith(filePath: book.filePath, coverBase64: book.coverBase64),
      );
      await BookData.move(_prefs, old.filePath, book.filePath);
      await _booksBox.delete(old.filePath);
      moved[old.filePath] = book.filePath;
    }
    if (unsaved.isNotEmpty) await _booksBox.putAll(unsaved);

    final removed = [
      for (final book in missing)
        if (!moved.containsKey(book.filePath)) book.filePath,
    ];
    // Their highlights and bookmarks stay: a file that only seems gone
    // (not downloaded from iCloud yet, a card taken out) gets them back
    // when a later scan finds it at the same path.
    await _booksBox.deleteAll(removed);

    return ScanResult(
      added: found - moved.length,
      moved: moved,
      removed: removed,
    );
  }

  /// Whether [found], a file new to the library, looks like the missing
  /// book [missing] in a new place: same file name, title and author.
  static bool _sameBook(ScannedBook missing, ScannedBook found) =>
      p.basename(missing.filePath) == p.basename(found.filePath) &&
      missing.title == found.title &&
      missing.author == found.author;

  /// Where a scan looks: all of shared storage on Android; on a Mac, the
  /// folders books usually end up in (scanning the whole home folder would
  /// crawl through Library and every project folder).
  List<Directory> _scanRoots() {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return [
        'Documents',
        'Downloads',
        'Desktop',
        'Books',
        'Library/Mobile Documents/com~apple~CloudDocs', // iCloud Drive
      ].map((dir) => Directory(p.join(home, dir))).toList();
    }
    return [Directory('/storage/emulated/0')];
  }

  Future<void> _scanDirectory(
    Directory dir,
    Set<String> known,
    Set<String> deletedPaths,
    Future<void> Function(ScannedBook book) onFound,
  ) async {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final dirName = p.basename(entity.path);
          if (_skipDirs.contains(dirName) || dirName.startsWith('.')) {
            continue;
          }
          await _scanDirectory(entity, known, deletedPaths, onFound);
        } else if (entity is File &&
            entity.path.toLowerCase().endsWith('.epub')) {
          // Skip if already in library or explicitly deleted by the user
          if (known.contains(entity.path)) continue;
          if (deletedPaths.contains(entity.path)) continue;

          final book = await _parse(
            entity.path,
            p.basename(entity.path),
            entity.path,
          );
          // A file that can't be read can't be opened either: leave it out.
          if (book != null) await onFound(book);
        }
      }
    } catch (e) {
      // Permission denied for this directory, skip
      debugPrint('Cannot access ${dir.path}: $e');
    }
  }

  /// The library entry for the EPUB at [readPath], kept under [filePath].
  /// Null if the file can't be read.
  Future<ScannedBook?> _parse(
    String readPath,
    String fileName,
    String filePath,
  ) async {
    try {
      return await compute(_parseEpubInIsolate, (readPath, fileName, filePath));
    } catch (e) {
      debugPrint('Failed to read $fileName: $e');
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FILE PICKING - Pick individual EPUB files (works reliably on Android)
  // ════════════════════════════════════════════════════════════════════════════

  /// Let the user pick EPUB files and copy them into the library.
  Future<void> pickEpubFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      // Picked files are copied to the app's own folder under unique names,
      // so different books with the same file name don't overwrite each other.
      final importDir = Directory(await _importDir());
      await importDir.create(recursive: true);

      for (final file in result.files) {
        final source = file.path;
        if (source == null) continue;
        final saved = p.join(
          importDir.path,
          '${const Uuid().v4()}_${file.name}',
        );
        final book = await _parse(source, file.name, saved);
        if (book == null) continue;
        try {
          final size = await File(source).length();
          if (await _alreadyImported(file.name, size, book)) continue;
          await File(source).copy(saved);
          await _booksBox.put(saved, book);
        } catch (e) {
          debugPrint('Failed to import ${file.name}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
    } finally {
      // On Android the picker hands over a cached copy of each file.
      if (Platform.isAndroid) {
        try {
          await FilePicker.platform.clearTemporaryFiles();
        } catch (_) {}
      }
    }
  }

  /// Folder holding the app's own copies of picked books.
  Future<String> _importDir() async =>
      p.join((await getAppDataDirectory()).path, 'books');

  /// Whether the library already has a copy of a picked file: one imported
  /// from a file of the same name and size, with the same title and author.
  Future<bool> _alreadyImported(
    String fileName,
    int size,
    ScannedBook book,
  ) async {
    final importDir = await _importDir();
    for (final existing in _booksBox.values) {
      if (!p.isWithin(importDir, existing.filePath)) continue;
      // Imported copies are named `<uuid>_<original name>`.
      final name = p.basename(existing.filePath);
      if (name.length <= 37 || name.substring(37) != fileName) continue;
      if (existing.title != book.title || existing.author != book.author) {
        continue;
      }
      try {
        if (await File(existing.filePath).length() == size) return true;
      } catch (_) {}
    }
    return false;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BOOK STORAGE
  // ════════════════════════════════════════════════════════════════════════════

  List<ScannedBook> getSavedBooks() {
    return _booksBox.values.toList();
  }

  /// Remove books whose file no longer exists (deleted or moved outside the
  /// app). They aren't added to the deleted list and keep their highlights
  /// and bookmarks, so if the file comes back a scan finds it again with
  /// them. Returns the removed paths.
  Future<List<String>> removeMissingBooks() async {
    final missing = [for (final book in await _missingBooks()) book.filePath];
    await _booksBox.deleteAll(missing);
    return missing;
  }

  /// Books whose file is gone.
  Future<List<ScannedBook>> _missingBooks() async {
    // Without storage access, files in shared storage can't be seen and would
    // all look missing; only check the app's own copies then.
    final appDir = (await getAppDataDirectory()).path;
    final canSeeShared = await hasStoragePermission();
    final canList = <String, bool>{};
    final missing = <ScannedBook>[];
    for (final book in getSavedBooks()) {
      final path = book.filePath;
      if (!canSeeShared && !path.startsWith(appDir)) continue;
      try {
        if (await File(path).exists()) continue;
        // Files in a folder that can't be looked into (access taken away)
        // only seem to be gone.
        final dir = Directory(p.dirname(path));
        if (await dir.exists() &&
            !(canList[dir.path] ??= await _canList(dir))) {
          continue;
        }
        missing.add(book);
      } catch (_) {
        // Unreadable path (e.g. permission revoked): keep the entry.
      }
    }
    return missing;
  }

  Future<bool> _canList(Directory dir) async {
    try {
      await dir.list(followLinks: false).isEmpty;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Add a note to the library, or update its title if it's already there
  /// (keeping reading progress and pin).
  Future<void> saveNote(String filePath, String title) async {
    final existing = _booksBox.get(filePath);
    await _booksBox.put(
      filePath,
      existing?.copyWith(title: title) ??
          ScannedBook(
            filePath: filePath,
            title: title,
            author: 'Your file',
            addedAt: DateTime.now(),
            lastReadTime: DateTime.now(),
          ),
    );
  }

  /// Remove a book from the library, with its highlights, bookmarks and
  /// reading positions. App-owned copies (imports, notes) are always
  /// deleted; with [deleteFile] the original file on the device is deleted
  /// too. Returns false if that file couldn't be deleted.
  Future<bool> removeBook(String filePath, {bool deleteFile = false}) async {
    await _booksBox.delete(filePath);
    await BookData.delete(_prefs, filePath);
    if (NoteService.isNote(filePath)) {
      await const NoteService().delete(filePath);
      return true;
    }

    final appCopy = p.isWithin(await _importDir(), filePath);
    if (!appCopy && !deleteFile) {
      // Kept on the device: don't let the next scan add it back.
      await _addToDeletedPaths(filePath);
      return true;
    }
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
      return true;
    } catch (e) {
      debugPrint('Error deleting book file: $e');
      await _addToDeletedPaths(filePath);
      return false;
    }
  }

  Set<String> _getDeletedPaths() {
    final json = _prefs.getString(_deletedPathsKey);
    if (json == null) return {};
    try {
      // Anything that isn't a path is left out rather than failing the lot.
      return (jsonDecode(json) as List).whereType<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _addToDeletedPaths(String filePath) async {
    final paths = _getDeletedPaths()..add(filePath);
    await _prefs.setString(_deletedPathsKey, jsonEncode(paths.toList()));
  }

  Future<void> _update(
    String filePath,
    ScannedBook Function(ScannedBook book) change,
  ) async {
    final book = _booksBox.get(filePath);
    if (book != null) await _booksBox.put(filePath, change(book));
  }

  Future<void> toggleBookPin(String filePath) =>
      _update(filePath, (book) => book.copyWith(isPinned: !book.isPinned));

  Future<void> updateLastReadTime(String filePath) =>
      _update(filePath, (book) => book.copyWith(lastReadTime: DateTime.now()));

  Future<void> updateReadingProgress(
    String filePath,
    int chapterIndex,
    double scrollPosition,
  ) => _update(
    filePath,
    (book) => book.copyWith(
      lastReadTime: DateTime.now(),
      lastReadChapter: chapterIndex,
      lastReadPosition: scrollPosition,
    ),
  );
}
