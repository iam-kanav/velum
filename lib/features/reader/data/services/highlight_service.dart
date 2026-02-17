import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/highlight.dart';

class HighlightService {
  final SharedPreferences _prefs;

  HighlightService(this._prefs);

  String _key(String bookPath) =>
      'highlights_${bookPath.hashCode}';

  List<Highlight> getHighlights(String bookPath) {
    final json = _prefs.getString(_key(bookPath));
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => Highlight.fromJson(e as Map<String, dynamic>)).toList();
  }

  List<Highlight> getHighlightsForChapter(String bookPath, int chapterIndex) {
    return getHighlights(bookPath)
        .where((h) => h.chapterIndex == chapterIndex)
        .toList();
  }

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
    await _prefs.setString(_key(bookPath), json);
  }
}
