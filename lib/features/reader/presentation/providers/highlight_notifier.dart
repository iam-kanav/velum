import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/highlight.dart';
import '../../data/services/highlight_service.dart';

class HighlightNotifier extends ChangeNotifier {
  final HighlightService _service;
  static const _uuid = Uuid();

  String? _currentBookPath;
  List<Highlight> _highlights = [];

  HighlightNotifier(this._service);

  List<Highlight> get highlights => _highlights;

  /// Grouped by color for display in highlights modal
  Map<String, List<Highlight>> get highlightsByColor {
    final map = <String, List<Highlight>>{};
    for (final h in _highlights) {
      map.putIfAbsent(h.color, () => []).add(h);
    }
    return map;
  }

  void loadHighlights(String bookPath) {
    _currentBookPath = bookPath;
    _highlights = _service.getHighlights(bookPath);
    notifyListeners();
  }

  List<Highlight> highlightsForChapter(int chapterIndex) {
    return _highlights.where((h) => h.chapterIndex == chapterIndex).toList();
  }

  Future<void> addHighlight({
    required int chapterIndex,
    required String text,
    required String color,
    required int startOffset,
    required int endOffset,
  }) async {
    if (_currentBookPath == null) return;
    final highlight = Highlight(
      id: _uuid.v4(),
      bookPath: _currentBookPath!,
      chapterIndex: chapterIndex,
      text: text,
      color: color,
      startOffset: startOffset,
      endOffset: endOffset,
      createdAt: DateTime.now(),
    );
    await _service.addHighlight(highlight);
    _highlights = _service.getHighlights(_currentBookPath!);
    notifyListeners();
  }

  Future<void> removeHighlight(String id) async {
    if (_currentBookPath == null) return;
    await _service.removeHighlight(_currentBookPath!, id);
    _highlights = _service.getHighlights(_currentBookPath!);
    notifyListeners();
  }
}
