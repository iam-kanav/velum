import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
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

  group('followReadingOrder', () {
    String page(String body) => '<html><body>$body</body></html>';
    EpubChapter entry(String title, String file, [String? anchor]) =>
        chapter(title, file)
          ..Anchor = anchor
          ..HtmlContent = 'original $file';
    String text(EpubChapter c) => html_parser
        .parse(c.HtmlContent)
        .querySelectorAll('p, h2')
        .map((e) => e.text)
        .join(' ');

    test('a chapter that is one whole file is left as it is', () {
      final chapters = followReadingOrder(
        [entry('1', 'a'), entry('2', 'b')],
        ['a', 'b'],
        {'a': page('<p>A</p>'), 'b': page('<p>B</p>')},
      );
      expect(chapters.map((c) => c.HtmlContent), ['original a', 'original b']);
    });

    test('files the contents skip stay in the chapter before them', () {
      final chapters = followReadingOrder(
        [entry('1', 'a'), entry('2', 'd')],
        ['a', 'b', 'c', 'd'],
        {
          'a': page('<p>A</p>'),
          'b': page('<p>B</p>'),
          'c': page('<p>C</p>'),
          'd': page('<p>D</p>'),
        },
      );
      expect(text(chapters[0]), 'A B C');
      expect(chapters[1].HtmlContent, 'original d');
    });

    test('entries pointing into one file split it at their anchors', () {
      final chapters = followReadingOrder(
        [entry('1', 'a'), entry('2', 'b', 'x'), entry('3', 'b', 'y')],
        ['a', 'b'],
        {
          'a': page('<p>A</p>'),
          'b': page(
            '<div><section><p>B1</p><h2 id="x">X</h2><p>B2</p>'
            '<h2 id="y">Y</h2><p>B3</p></section></div>',
          ),
        },
      );
      expect(chapters.map(text), ['A B1', 'X B2', 'Y B3']);
      // The wrappers around a split are kept.
      expect(chapters[1].HtmlContent, contains('<section>'));
    });

    test('XHTML self-closed anchors split a file where they stand', () {
      final chapters = followReadingOrder(
        [entry('1', 'a', 'x'), entry('2', 'a', 'y')],
        ['a'],
        {
          'a': '<html><head><title/></head><body><p><a id="x"/>One</p>'
              '<p>More</p><div/><p><a id="y"/>Two</p></body></html>',
        },
      );
      // The emptied paragraph the second anchor sat in stays behind.
      expect(chapters.map((c) => text(c).trim()), ['One More', 'Two']);
    });

    test('old-style <a name> anchors are found', () {
      final chapters = followReadingOrder(
        [entry('1', 'a'), entry('2', 'a', 'two'), entry('3', 'a', 'three')],
        ['a'],
        {
          'a': page(
            '<p>One</p><h2><a name="two"></a>Two</h2><p>B</p>'
            '<a name="three"></a><h2 id="other">Three</h2>',
          ),
        },
      );
      expect(chapters.map((c) => text(c).trim()), ['One', 'Two B', 'Three']);
    });

    test(
      'files before the first entry stay out, files not in the spine are untouched',
      () {
        final chapters = followReadingOrder(
          [entry('1', 'b'), entry('Notes', 'notes')],
          ['cover', 'b'],
          {'cover': page('<p>Cover</p>'), 'b': page('<p>B</p>')},
        );
        expect(chapters.map((c) => c.HtmlContent), [
          'original b',
          'original notes',
        ]);
      },
    );
  });

  test('a book with no table of contents is read file by file', () {
    final chapters = chaptersFromSpine(
      ['cover', 'a', 'b'],
      {'cover': '<p>Cover</p>', 'a': '<p>A</p>', 'b': '<p>B</p>'},
    );
    expect(titles(chapters), ['Chapter 1', 'Chapter 2', 'Chapter 3']);
    expect(chapters.map((c) => c.HtmlContent), [
      '<p>Cover</p>',
      '<p>A</p>',
      '<p>B</p>',
    ]);
    expect(chapters.map((c) => c.ContentFileName), ['cover', 'a', 'b']);
  });

  // Optional check against a real nested-TOC book:
  //   VELUM_TEST_EPUB=/path/to/book.epub flutter test test/epub_service_test.dart
  final path = Platform.environment['VELUM_TEST_EPUB'];
  test('real EPUB opens with all chapters', () async {
    final opened = await const EpubService().parseEpub(path!);
    final chapters = opened.book.Chapters!;
    for (final c in chapters) {
      final words = html_parser
          .parse(c.HtmlContent ?? '')
          .body
          ?.text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      // ignore: avoid_print
      print('${c.Title}: $words words');
    }
    expect(chapters.length, greaterThan(10));
  }, skip: path == null ? 'set VELUM_TEST_EPUB to run' : false);
}
