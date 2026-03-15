import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bookmark.dart';

class BookmarkService {
  final SharedPreferences _prefs;

  BookmarkService(this._prefs);

  String _key(String bookPath) => 'bookmarks_${bookPath.hashCode}';

  List<Bookmark> getBookmarks(String bookPath) {
    final json = _prefs.getString(_key(bookPath));
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => Bookmark.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    final bookmarks = getBookmarks(bookmark.bookPath);
    bookmarks.add(bookmark);
    await _save(bookmark.bookPath, bookmarks);
  }

  Future<void> removeBookmark(String bookPath, String id) async {
    final bookmarks = getBookmarks(bookPath);
    bookmarks.removeWhere((b) => b.id == id);
    await _save(bookPath, bookmarks);
  }

  Future<void> _save(String bookPath, List<Bookmark> bookmarks) async {
    final json = jsonEncode(bookmarks.map((b) => b.toJson()).toList());
    await _prefs.setString(_key(bookPath), json);
  }
}
