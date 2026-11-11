import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velum/core/storage/book_data.dart';
import '../models/bookmark.dart';

class BookmarkService {
  final SharedPreferences _prefs;

  BookmarkService(this._prefs);

  List<Bookmark> getBookmarks(String bookPath) => BookData.readRecords(
    _prefs,
    BookData.bookmarks,
    bookPath,
    Bookmark.fromJson,
  );

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
    await BookData.write(_prefs, BookData.bookmarks, bookPath, json);
  }
}
