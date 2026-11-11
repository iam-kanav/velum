import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velum/core/storage/book_data.dart';
import 'package:velum/features/library/data/models/scanned_book.dart';
import 'package:velum/features/library/data/services/collection_service.dart';
import 'package:velum/features/library/data/services/library_service.dart';
import 'package:velum/features/library/presentation/providers/library_notifier.dart';
import 'package:velum/features/notes/data/note_service.dart';

/// Stands in for the system file picker: "picks" [paths].
class _FakePicker extends FilePicker {
  List<String> paths = [];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    for (final path in paths)
      PlatformFile(
        path: path,
        name: p.basename(path),
        size: File(path).lengthSync(),
      ),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory appData;
  late Directory shelf; // the folder a scan looks in
  late SharedPreferences prefs;
  late Box<ScannedBook> box;
  late LibraryService service;
  final picker = _FakePicker();
  var run = 0;

  File writeBook(String path, String title) => File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(NoteService.buildEpub(Note(title, '<p>$title</p>')));

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('velum_library_test');
    appData = Directory(p.join(temp.path, 'app'))..createSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => appData.path,
        );
    Hive.init(p.join(temp.path, 'hive'));
    Hive.registerAdapter(ScannedBookAdapter());
    FilePicker.platform = picker;
  });

  tearDownAll(() async {
    await Hive.close();
    temp.deleteSync(recursive: true);
  });

  setUp(() async {
    run++;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    box = await Hive.openBox<ScannedBook>('books_$run');
    shelf = Directory(p.join(temp.path, 'shelf_$run'))..createSync();
    service = LibraryService(prefs, box, scanRoots: [shelf]);
  });

  group('scan', () {
    test('adds new books once and reports how many', () async {
      writeBook(p.join(shelf.path, 'one.epub'), 'One');
      writeBook(p.join(shelf.path, 'deeper', 'two.EPUB'), 'Two');

      final first = await service.scanDeviceForEpubs();
      expect(first.added, 2);
      expect(service.getSavedBooks().map((b) => b.title).toSet(), {
        'One',
        'Two',
      });

      final second = await service.scanDeviceForEpubs();
      expect(second.added, 0);
      expect(service.getSavedBooks(), hasLength(2));
    });

    test('a book without a title or that cannot be parsed is named after '
        'its file, whatever the case of the extension', () async {
      writeBook(p.join(shelf.path, 'Untitled Draft.EPUB'), '  ');
      File(p.join(shelf.path, 'Broken.Epub')).writeAsStringSync('not a zip');

      await service.scanDeviceForEpubs();
      expect(service.getSavedBooks().map((b) => b.title).toSet(), {
        'Untitled Draft',
        'Broken',
      });
    });

    test('a file that cannot be read is left out', () async {
      final locked = File(p.join(shelf.path, 'locked.epub'))
        ..writeAsStringSync('secret');
      Process.runSync('chmod', ['000', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['600', locked.path]));

      final result = await service.scanDeviceForEpubs();
      expect(result.added, 0);
      expect(service.getSavedBooks(), isEmpty);
    }, skip: Platform.isWindows);

    test('saves more books than one batch holds', () async {
      for (var i = 0; i < 45; i++) {
        File(p.join(shelf.path, 'book$i.epub')).writeAsStringSync('x');
      }
      final counts = <int>[];
      final result = await service.scanDeviceForEpubs(onProgress: counts.add);
      expect(result.added, 45);
      expect(counts.last, 45);
      expect(service.getSavedBooks(), hasLength(45));
    });

    test('a moved file stays the same book', () async {
      final oldPath = p.join(shelf.path, 'old', 'dune.epub');
      final newPath = p.join(shelf.path, 'new', 'dune.epub');
      writeBook(oldPath, 'Dune');
      await service.scanDeviceForEpubs();
      await service.updateReadingProgress(oldPath, 7, 0.5);
      await service.toggleBookPin(oldPath);
      await BookData.write(prefs, BookData.highlights, oldPath, '[1]');
      final before = box.get(oldPath)!;

      Directory(p.dirname(newPath)).createSync();
      File(oldPath).renameSync(newPath);
      final result = await service.scanDeviceForEpubs();

      expect(result.moved, {oldPath: newPath});
      expect(result.added, 0);
      expect(result.removed, isEmpty);
      expect(box.get(oldPath), isNull);
      final after = box.get(newPath)!;
      expect(after.lastReadChapter, 7);
      expect(after.lastReadPosition, 0.5);
      expect(after.lastReadTime, before.lastReadTime);
      expect(after.addedAt, before.addedAt);
      expect(after.isPinned, isTrue);
      expect(BookData.read(prefs, BookData.highlights, newPath), '[1]');
      expect(BookData.read(prefs, BookData.highlights, oldPath), isNull);
    });

    test('a book whose file is gone is dropped, but its bookmarks wait '
        'for it to come back', () async {
      final path = p.join(shelf.path, 'gone.epub');
      writeBook(path, 'Gone');
      writeBook(p.join(shelf.path, 'stays.epub'), 'Stays');
      await service.scanDeviceForEpubs();
      await BookData.write(prefs, BookData.bookmarks, path, '[1]');

      File(path).deleteSync();
      final result = await service.scanDeviceForEpubs();

      expect(result.removed, [path]);
      expect(result.moved, isEmpty);
      expect(service.getSavedBooks().single.title, 'Stays');
      expect(BookData.read(prefs, BookData.bookmarks, path), '[1]');
    });

    test('a new file that could be either of two missing books is a new '
        'book', () async {
      final a = p.join(shelf.path, 'a', 'same.epub');
      final b = p.join(shelf.path, 'b', 'same.epub');
      writeBook(a, 'Same');
      writeBook(b, 'Same');
      await service.scanDeviceForEpubs();
      await service.updateReadingProgress(a, 3, 0);

      final c = p.join(shelf.path, 'c', 'same.epub');
      Directory(p.dirname(c)).createSync();
      File(a).renameSync(c);
      File(b).deleteSync();
      final result = await service.scanDeviceForEpubs();

      expect(result.moved, isEmpty);
      expect(result.added, 1);
      expect(result.removed.toSet(), {a, b});
      expect(service.getSavedBooks().single.lastReadChapter, isNull);
    });

    test('a different book under the same file name is not a move', () async {
      final oldPath = p.join(shelf.path, 'old', 'book.epub');
      writeBook(oldPath, 'First');
      await service.scanDeviceForEpubs();
      await service.updateReadingProgress(oldPath, 4, 0);

      File(oldPath).deleteSync();
      writeBook(p.join(shelf.path, 'new', 'book.epub'), 'Second');
      final result = await service.scanDeviceForEpubs();

      expect(result.moved, isEmpty);
      expect(result.removed, [oldPath]);
      expect(service.getSavedBooks().single.lastReadChapter, isNull);
    });

    test('a book removed from the library but kept on the device is not '
        'added back, even if the list of those holds junk', () async {
      final path = p.join(shelf.path, 'unwanted.epub');
      writeBook(path, 'Unwanted');
      await service.scanDeviceForEpubs();
      await service.removeBook(path);
      expect(File(path).existsSync(), isTrue);

      final listed = prefs.getString('deleted_book_paths')!;
      await prefs.setString(
        'deleted_book_paths',
        listed.replaceFirst('[', '[42,null,'),
      );
      expect((await service.scanDeviceForEpubs()).added, 0);
      expect(service.getSavedBooks(), isEmpty);
    });
  });

  test('removing a book forgets its highlights, bookmarks and '
      'positions', () async {
    final path = p.join(shelf.path, 'read.epub');
    writeBook(path, 'Read');
    await service.scanDeviceForEpubs();
    for (final kind in [
      BookData.highlights,
      BookData.bookmarks,
      BookData.chapterPositions,
    ]) {
      await BookData.write(prefs, kind, path, '[1]');
    }

    expect(await service.removeBook(path, deleteFile: true), isTrue);

    expect(File(path).existsSync(), isFalse);
    expect(service.getSavedBooks(), isEmpty);
    expect(prefs.getKeys().where((key) => key.contains(path)), isEmpty);
  });

  group('picking files', () {
    late Directory downloads;
    Directory imports() => Directory(p.join(appData.path, 'books'));

    setUp(() {
      downloads = Directory(p.join(temp.path, 'downloads_$run'))..createSync();
      if (imports().existsSync()) imports().deleteSync(recursive: true);
    });

    test('copies the file into the app and adds it', () async {
      final picked = writeBook(p.join(downloads.path, 'emma.epub'), 'Emma');
      picker.paths = [picked.path];
      await service.pickEpubFiles();

      final book = service.getSavedBooks().single;
      expect(book.title, 'Emma');
      expect(p.dirname(book.filePath), imports().path);
      expect(p.basename(book.filePath), endsWith('_emma.epub'));
      expect(File(book.filePath).readAsBytesSync(), picked.readAsBytesSync());
    });

    test('picking the same file again adds nothing', () async {
      final picked = writeBook(p.join(downloads.path, 'emma.epub'), 'Emma');
      picker.paths = [picked.path];
      await service.pickEpubFiles();
      await service.pickEpubFiles();
      picker.paths = [picked.path, picked.path];
      await service.pickEpubFiles();

      expect(service.getSavedBooks(), hasLength(1));
      expect(imports().listSync(), hasLength(1));
    });

    test('another book with the same file name is still added', () async {
      final picked = writeBook(p.join(downloads.path, 'book.epub'), 'First');
      picker.paths = [picked.path];
      await service.pickEpubFiles();
      writeBook(picked.path, 'Second');
      await service.pickEpubFiles();

      expect(service.getSavedBooks().map((b) => b.title).toSet(), {
        'First',
        'Second',
      });
      expect(imports().listSync(), hasLength(2));
    });
  });

  group('LibraryNotifier', () {
    Future<LibraryNotifier> open() async {
      final notifier = LibraryNotifier(service, CollectionService(prefs));
      // Let the check it starts with finish.
      await service.removeMissingBooks();
      await pumpEventQueue();
      return notifier;
    }

    test('a scan started while one is running does nothing', () async {
      writeBook(p.join(shelf.path, 'one.epub'), 'One');
      final notifier = await open();

      final first = notifier.scanDevice();
      expect(notifier.isScanning, isTrue);
      expect(await notifier.scanDevice(), isNull);
      await notifier.refresh();
      expect(await first, 1);
      expect(notifier.isScanning, isFalse);
      expect(notifier.books.single.title, 'One');
    });

    test('a moved book stays in its collection; a deleted one leaves '
        'it', () async {
      final moving = p.join(shelf.path, 'old', 'moving.epub');
      final going = p.join(shelf.path, 'going.epub');
      writeBook(moving, 'Moving');
      writeBook(going, 'Going');
      final notifier = await open();
      await notifier.scanDevice();
      await notifier.createCollection('Shelf', bookPaths: [moving, going]);

      final moved = p.join(shelf.path, 'moving.epub');
      File(moving).renameSync(moved);
      File(going).deleteSync();
      expect(await notifier.scanDevice(), 0);

      expect(notifier.collections.single.bookPaths, [moved]);
      expect(notifier.books.single.filePath, moved);
    });

    test('remembers the sort order', () async {
      (await open()).setSortOption(LibrarySortOption.alphabetical);
      expect((await open()).currentSort, LibrarySortOption.alphabetical);
    });

    test('deleting several books updates collections too', () async {
      final a = writeBook(p.join(shelf.path, 'a.epub'), 'A').path;
      final b = writeBook(p.join(shelf.path, 'b.epub'), 'B').path;
      final c = writeBook(p.join(shelf.path, 'c.epub'), 'C').path;
      final notifier = await open();
      await notifier.scanDevice();
      await notifier.createCollection('Shelf', bookPaths: [a, b, c]);

      expect(await notifier.removeBooks([a, b], deleteFiles: true), 0);

      expect(notifier.books.single.filePath, c);
      expect(notifier.collections.single.bookPaths, [c]);
    });
  });
}
