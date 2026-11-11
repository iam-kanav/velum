import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velum/core/storage/book_data.dart';
import '../models/highlight.dart';

class HighlightService {
  final SharedPreferences _prefs;

  HighlightService(this._prefs);

  List<Highlight> getHighlights(String bookPath) => BookData.readRecords(
    _prefs,
    BookData.highlights,
    bookPath,
    Highlight.fromJson,
  );

  Future<void> addHighlight(Highlight highlight) async {
    final highlights = getHighlights(highlight.bookPath);
    highlights.add(highlight);
    await _save(highlight.bookPath, highlights);
  }

  Future<void> removeHighlight(String bookPath, String id) async {
    final highlights = getHighlights(bookPath);
    highlights.removeWhere((h) => h.id == id);
    await _save(bookPath, highlights);
  }

  Future<void> _save(String bookPath, List<Highlight> highlights) async {
    final json = jsonEncode(highlights.map((h) => h.toJson()).toList());
    await BookData.write(_prefs, BookData.highlights, bookPath, json);
  }
}
