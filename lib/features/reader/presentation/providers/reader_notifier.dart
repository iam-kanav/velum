import 'dart:async';
import 'dart:convert';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../../data/services/chapter_processor.dart';
import '../../data/services/epub_service.dart';
import '../../../tts/data/models/tts_chunk.dart';
import '../../../library/data/services/library_service.dart';

/// Determine MIME type from filename.
String _getMimeTypeFromName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.svg')) return 'image/svg+xml';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/png';
}

class GlobalSearchResult {
  final int chapterIndex;
  final String chapterTitle;
  final String snippetBefore;
  final String matchedText;
  final String snippetAfter;
  final double positionPercent;

  const GlobalSearchResult({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.snippetBefore,
    required this.matchedText,
    required this.snippetAfter,
    required this.positionPercent,
  });
}

/// Top-level function for compute() – runs search off main thread.
List<GlobalSearchResult> _searchChaptersIsolate(Map<String, dynamic> params) {
  final query = params['query'] as String;
  final chapters = params['chapters'] as List<Map<String, String>>;
  final lowerQuery = query.toLowerCase();
  final results = <GlobalSearchResult>[];

  for (int i = 0; i < chapters.length; i++) {
    final html = chapters[i]['html'] ?? '';
    final given = chapters[i]['title']?.trim() ?? '';
    final title = given.isEmpty ? 'Chapter ${i + 1}' : given;

    // Parse HTML to plain text
    final document = html_parser.parse(
      ChapterProcessor.expandSelfClosing(html),
    );
    final body = document.body;
    if (body == null) continue;
    final plainText = body.text;
    if (plainText.isEmpty) continue;

    final lowerText = plainText.toLowerCase();
    int searchFrom = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerQuery, searchFrom);
      if (idx == -1) break;

      // Build snippet with ~30 chars of context
      final snippetStart = (idx - 30).clamp(0, plainText.length);
      final snippetEnd = (idx + query.length + 30).clamp(0, plainText.length);

      final before =
          (snippetStart > 0 ? '...' : '') +
          plainText.substring(snippetStart, idx);
      final matched = plainText.substring(idx, idx + query.length);
      final after =
          plainText.substring(idx + query.length, snippetEnd) +
          (snippetEnd < plainText.length ? '...' : '');

      final positionPercent = plainText.isNotEmpty
          ? idx / plainText.length
          : 0.0;

      results.add(
        GlobalSearchResult(
          chapterIndex: i,
          chapterTitle: title,
          snippetBefore: before,
          matchedText: matched,
          snippetAfter: after,
          positionPercent: positionPercent,
        ),
      );

      searchFrom = idx + query.length;
    }
  }

  return results;
}

class ReaderNotifier extends ChangeNotifier {
  final EpubService _epubService;
  final LibraryService _libraryService;

  /// Pre-compiled regex for matching image src attributes — avoids recompilation per call.
  static final RegExp _srcRegex = RegExp(
    r'''src=["']([^"']+)["']''',
    caseSensitive: false,
  );

  /// SVG images (`<image xlink:href="cover.jpeg"/>`, as on Calibre cover
  /// pages) name their file in href rather than src.
  static final RegExp _svgImageRegex = RegExp(
    r'<image\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _hrefRegex = RegExp(
    r'''((?:xlink:)?href)=["']([^"']+)["']''',
    caseSensitive: false,
  );

  ReaderNotifier(this._epubService, this._libraryService);

  String? _currentBookPath;

  EpubBook? _currentBook;
  EpubBook? get currentBook => _currentBook;

  EpubChapter? _currentChapter;
  EpubChapter? get currentChapter => _currentChapter;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Image lookup: path variants -> EPUB image file name. Data URLs are
  // encoded lazily per chapter instead of for every image when a book opens.
  List<int>? Function(String imageName) _readImage = (_) => null;
  Map<String, String> _imageAliases = {};
  Map<String, String> _normalizedImageAliases = {};

  /// Encoded images, least recently used first. Only the last few are kept:
  /// a picture book would otherwise end up in memory whole.
  final Map<String, String> _imageDataUrls = {};
  static const _maxCachedImages = 32;

  // Performance: cache processed HTML to avoid expensive re-parsing on every
  // widget rebuild. [_ahead] is a chapter processed before it is shown.
  _Processed? _shown;
  _Processed? _ahead;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadBook(String assetPath) async {
    _isLoading = true;
    _errorMessage = null;
    _imageAliases = {};
    _normalizedImageAliases = {};
    _imageDataUrls.clear();
    _shown = null;
    _ahead = null;
    _currentBookPath = assetPath;
    notifyListeners();

    try {
      final opened = await _epubService.parseEpub(assetPath);
      _currentBook = opened.book;
      _readImage = opened.readImage;
      _indexImages(opened.imageNames);

      // Restore saved chapter position from LibraryService
      int savedIndex = 0;
      final books = _libraryService.getSavedBooks();
      final bookIndex = books.indexWhere((b) => b.filePath == assetPath);
      if (bookIndex != -1) {
        savedIndex = books[bookIndex].lastReadChapter ?? 0;
      }

      if (_currentBook?.Chapters?.isNotEmpty ?? false) {
        final chapters = _currentBook!.Chapters!;
        if (savedIndex < chapters.length) {
          _currentChapter = chapters[savedIndex];
        } else {
          _currentChapter = chapters.first;
        }
      } else {
        // Nothing to show: say so rather than wait for a chapter forever.
        _currentChapter = null;
        _errorMessage = 'This book has no chapters.';
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      // The reader may have been closed while the book was being read.
      _notify();
    }
  }

  /// Where the current chapter is in the book, or -1 before one is loaded.
  /// By identity: epubx compares chapters by value, so two contents entries
  /// with the same title and text would both count as the first of them.
  int get _chapterIndex {
    final current = _currentChapter;
    final chapters = _currentBook?.Chapters;
    if (current == null || chapters == null) return -1;
    return chapters.indexWhere((c) => identical(c, current));
  }

  /// Get current chapter index
  int get currentChapterIndex {
    final index = _chapterIndex;
    return index < 0 ? 0 : index;
  }

  /// Save reading position (chapter index + scroll position). Does nothing
  /// until a chapter is showing: while a book is still loading, or failed to
  /// load, there is no position, and saving would reset it to chapter 1.
  Future<void> saveReadingPosition(double scrollPosition) async {
    final index = _chapterIndex;
    if (_currentBookPath == null || index < 0) return;
    await _libraryService.updateReadingProgress(
      _currentBookPath!,
      index,
      scrollPosition,
    );
  }

  /// Get saved scroll position for a book
  double getSavedScrollPosition(String bookPath) {
    final books = _libraryService.getSavedBooks();
    final index = books.indexWhere((b) => b.filePath == bookPath);
    if (index != -1) {
      return books[index].lastReadPosition ?? 0;
    }
    return 0;
  }

  void _indexImages(List<String> imageNames) {
    for (final fileName in imageNames) {
      final parts = fileName.split('/');
      _imageAliases[fileName] = fileName;
      _imageAliases[parts.last] = fileName;
      if (parts.length >= 2) {
        _imageAliases['${parts[parts.length - 2]}/${parts.last}'] = fileName;
      }
    }

    // Secondary keys (no leading ../, lower-case file name) for fuzzy matching
    for (final entry in _imageAliases.entries) {
      _normalizedImageAliases[_stripParentDirs(entry.key)] = entry.value;
      _normalizedImageAliases[entry.key.split('/').last.toLowerCase()] =
          entry.value;
    }
  }

  static String _stripParentDirs(String path) {
    var clean = path;
    while (clean.startsWith('../')) {
      clean = clean.substring(3);
    }
    return clean;
  }

  /// Process HTML content to replace image sources with base64 data URLs
  String processHtmlWithImages(String? htmlContent) {
    if (htmlContent == null) return '';
    if (_imageAliases.isEmpty) return htmlContent;

    final html = htmlContent.replaceAllMapped(_srcRegex, (match) {
      final dataUrl = _findImageDataUrl(match.group(1) ?? '');
      return dataUrl != null ? 'src="$dataUrl"' : match.group(0)!;
    });
    if (!html.contains('<image')) return html;
    return html.replaceAllMapped(
      _svgImageRegex,
      (tag) => tag.group(0)!.replaceAllMapped(_hrefRegex, (match) {
        final dataUrl = _findImageDataUrl(match.group(2) ?? '');
        return dataUrl != null
            ? '${match.group(1)}="$dataUrl"'
            : match.group(0)!;
      }),
    );
  }

  String? _findImageDataUrl(String src) {
    final cleanSrc = _stripParentDirs(src);
    final fileName = _imageAliases[src] ??
        _imageAliases[cleanSrc] ??
        _normalizedImageAliases[cleanSrc] ??
        _normalizedImageAliases[src.split('/').last.toLowerCase()];
    if (fileName == null) return null;

    // Taken out and put back so the map stays in order of last use.
    var dataUrl = _imageDataUrls.remove(fileName);
    if (dataUrl == null) {
      final bytes = _readImage(fileName);
      if (bytes == null) return null;
      dataUrl =
          'data:${_getMimeTypeFromName(fileName)};base64,${base64Encode(bytes)}';
      if (_imageDataUrls.length >= _maxCachedImages) {
        _imageDataUrls.remove(_imageDataUrls.keys.first);
      }
    }
    return _imageDataUrls[fileName] = dataUrl;
  }

  bool _showUI = true;
  bool get showUI => _showUI;

  Timer? _autoHideTimer;
  static const Duration _autoHideDuration = Duration(seconds: 5);

  void toggleUI() {
    _showUI = !_showUI;
    notifyListeners();

    // Cancel any existing timer
    _autoHideTimer?.cancel();

    // If showing UI, start auto-hide timer
    if (_showUI) {
      _autoHideTimer = Timer(_autoHideDuration, () {
        _showUI = false;
        notifyListeners();
      });
    }
  }

  /// Search all chapters for a query string, returning results with snippets.
  /// Runs off the main thread via compute().
  Future<List<GlobalSearchResult>> searchAllChapters(String query) async {
    if (query.isEmpty || _currentBook?.Chapters == null) return [];

    final chapters = _currentBook!.Chapters!
        .map((ch) => {'html': ch.HtmlContent ?? '', 'title': ch.Title ?? ''})
        .toList();

    return compute(_searchChaptersIsolate, {
      'query': query,
      'chapters': chapters,
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void jumpToChapter(EpubChapter chapter) {
    _currentChapter = chapter;
    notifyListeners();
  }

  void nextChapter() {
    final index = _chapterIndex;
    if (index < 0) return;

    final chapters = _currentBook!.Chapters!;
    if (index < chapters.length - 1) {
      _currentChapter = chapters[index + 1];
      notifyListeners();
    }
  }

  void previousChapter() {
    final index = _chapterIndex;
    if (index > 0) {
      _currentChapter = _currentBook!.Chapters![index - 1];
      notifyListeners();
    }
  }

  /// Paragraphs and sentences of the current chapter, indexed exactly like
  /// the rendered page's data-para / data-sent attributes.
  List<TtsParagraph> get ttsParagraphs {
    getProcessedHtml();
    return _shown?.paragraphs ?? const [];
  }

  /// Paragraphs of a chapter (given its HTML from the book) that read-aloud
  /// is about to carry on into. The result is kept, so the page that then
  /// turns to that chapter doesn't process it a second time.
  List<TtsParagraph> paragraphsOf(String rawHtml) {
    // With the reader closed there is no page: the text alone is enough
    // (inlining images doesn't change it).
    if (_disposed) return ChapterProcessor.process(rawHtml).$2;
    if (rawHtml == _shown?.raw) return _shown!.paragraphs;
    if (rawHtml != _ahead?.raw) _ahead = _process(rawHtml);
    return _ahead!.paragraphs;
  }

  /// Get processed HTML with images replaced and sentences wrapped for TTS.
  /// Cached to avoid expensive HTML parsing + regex on every widget rebuild.
  String getProcessedHtml() {
    final rawHtml = _currentChapter?.HtmlContent;
    if (rawHtml == null) return '';
    if (rawHtml != _shown?.raw) {
      _shown = rawHtml == _ahead?.raw ? _ahead : _process(rawHtml);
      _ahead = null;
    }
    return _shown!.html;
  }

  _Processed _process(String rawHtml) {
    final (html, paragraphs) =
        ChapterProcessor.process(processHtmlWithImages(rawHtml));
    return (raw: rawHtml, html: html, paragraphs: paragraphs);
  }
}

/// A chapter's HTML as stored in the book ([raw]) and as shown on the page.
typedef _Processed = ({String raw, String html, List<TtsParagraph> paragraphs});
