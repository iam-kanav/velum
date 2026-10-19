import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velum/features/reader/data/services/epub_service.dart';

EpubChapter chapter(String title, String file, [List<EpubChapter>? sub]) =>
    EpubChapter()
      ..Title = title
      ..ContentFileName = file
      ..SubChapters = sub ?? [];

List<String?> titles(List<EpubChapter> chapters) =>
    chapters.map((c) => c.Title).toList();

void main() {
  group('flattenChapters', () {
    test('a flat table of contents is unchanged', () {
      final flat = flattenChapters([chapter('1', 'a'), chapter('2', 'b')]);
      expect(titles(flat), ['1', '2']);
    });

    test('chapters nested under parts are listed in reading order', () {
      final flat = flattenChapters([
        chapter('Book 1', 'c1', [chapter('Ch 1', 'c1'), chapter('Ch 2', 'c2')]),
        chapter('Book 2', 'c3', [chapter('Ch 3', 'c3'), chapter('Ch 4', 'c4')]),
      ]);
      // Each "Book" points at its first chapter's file, so it is dropped
      // rather than reading that chapter twice.
      expect(titles(flat), ['Ch 1', 'Ch 2', 'Ch 3', 'Ch 4']);
      expect(flat.every((c) => c.SubChapters!.isEmpty), isTrue);
    });

    test('a part with its own page is kept', () {
      final flat = flattenChapters([
        chapter('Part 1', 'part1', [chapter('Ch 1', 'c1')]),
      ]);
      expect(titles(flat), ['Part 1', 'Ch 1']);
    });

    test('deeper nesting is flattened too', () {
      final flat = flattenChapters([
        chapter('Vol', 'v', [
          chapter('Book', 'b', [chapter('Ch 1', 'c1')]),
        ]),
      ]);
      expect(titles(flat), ['Vol', 'Book', 'Ch 1']);
    });
  });

  // Optional check against a real nested-TOC book:
  //   VELUM_TEST_EPUB=/path/to/book.epub flutter test test/epub_service_test.dart
  final path = Platform.environment['VELUM_TEST_EPUB'];
  test('real EPUB opens with all chapters', () async {
    final opened = await const EpubService().parseEpub(path!);
    final chapters = opened.book.Chapters!;
    // ignore: avoid_print
    print('${chapters.length} chapters: ${chapters.first.Title} '
        '... ${chapters.last.Title}');
    expect(chapters.length, greaterThan(10));
  }, skip: path == null ? 'set VELUM_TEST_EPUB to run' : false);
}
