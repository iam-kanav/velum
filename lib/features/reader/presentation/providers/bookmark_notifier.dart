import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/bookmark.dart';
import '../../data/services/bookmark_service.dart';

class BookmarkNotifier extends ChangeNotifier {
  final BookmarkService _service;
  static const _uuid = Uuid();

  String? _currentBookPath;
  List<Bookmark> _bookmarks = [];

  BookmarkNotifier(this._service);

  List<Bookmark> get bookmarks => _bookmarks;

  void loadBookmarks(String bookPath) {
    _currentBookPath = bookPath;
    _bookmarks = _service.getBookmarks(bookPath);
    notifyListeners();
  }

  List<Bookmark> bookmarksForChapter(int chapterIndex) {
    return _bookmarks.where((b) => b.chapterIndex == chapterIndex).toList();
  }

  Future<void> addBookmark({
    required int chapterIndex,
    required double scrollPosition,
    String? label,
  }) async {
    if (_currentBookPath == null) return;
    final bookmark = Bookmark(
      id: _uuid.v4(),
      bookPath: _currentBookPath!,
      chapterIndex: chapterIndex,
      scrollPosition: scrollPosition,
      label: label,
      createdAt: DateTime.now(),
    );
    await _service.addBookmark(bookmark);
    _bookmarks = _service.getBookmarks(_currentBookPath!);
    notifyListeners();
  }

  Future<void> removeBookmark(String id) async {
    if (_currentBookPath == null) return;
    await _service.removeBookmark(_currentBookPath!, id);
    _bookmarks = _service.getBookmarks(_currentBookPath!);
    notifyListeners();
  }

  /// Check if a bookmark exists for the given chapter and approximate position.
  bool hasBookmarkNear(int chapterIndex, double scrollPosition, {double threshold = 50}) {
    return _bookmarks.any(
      (b) => b.chapterIndex == chapterIndex &&
             (b.scrollPosition - scrollPosition).abs() < threshold,
    );
  }
}
