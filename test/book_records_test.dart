import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velum/features/reader/data/models/highlight.dart';
import 'package:velum/features/reader/data/services/bookmark_service.dart';
import 'package:velum/features/reader/data/services/highlight_service.dart';

void main() {
  const book = '/books/a.epub';

  Highlight highlight(String id) => Highlight(
    id: id,
    bookPath: book,
    chapterIndex: 0,
    text: 'text',
    color: 'yellow',
    startOffset: 0,
    endOffset: 4,
    createdAt: DateTime(2026),
  );

  test('a highlight that cannot be read is skipped, not fatal', () async {
    SharedPreferences.setMockInitialValues({
      'highlights:$book': jsonEncode([
        highlight('good').toJson(),
        {'id': 'no other fields'},
        'not a record',
        highlight('also good').toJson(),
      ]),
    });
    final service = HighlightService(await SharedPreferences.getInstance());

    expect(service.getHighlights(book).map((h) => h.id), ['good', 'also good']);

    // Adding and removing still work for the book.
    await service.addHighlight(highlight('new'));
    await service.removeHighlight(book, 'good');
    expect(service.getHighlights(book).map((h) => h.id), ['also good', 'new']);
  });

  test('stored data that is not a list loads as nothing', () async {
    SharedPreferences.setMockInitialValues({
      'highlights:$book': '{"oops": true',
      'bookmarks:$book': '{"oops": true}',
    });
    final prefs = await SharedPreferences.getInstance();

    expect(HighlightService(prefs).getHighlights(book), isEmpty);
    expect(BookmarkService(prefs).getBookmarks(book), isEmpty);
  });
}
