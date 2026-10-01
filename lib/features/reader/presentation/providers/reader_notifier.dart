import 'dart:async';
import 'dart:convert';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../data/services/epub_service.dart';
import '../../../tts/data/models/tts_chunk.dart';
import '../../../library/data/services/library_service.dart';

/// Determine MIME type from filename (used in isolate).
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
    final title = chapters[i]['title'] ?? 'Chapter ${i + 1}';

    // Parse HTML to plain text
    final document = html_parser.parse(html);
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
  Map<String, String> _imageAliases = {};
  Map<String, String> _normalizedImageAliases = {};
  final Map<String, String> _imageDataUrls = {};

  // Performance: cache processed HTML to avoid expensive re-parsing on every widget rebuild
  String? _cachedChapterHtml;
  String? _cachedProcessedHtml;
  List<TtsParagraph> _cachedParagraphs = const [];

  Future<void> loadBook(String assetPath) async {
    _isLoading = true;
    _errorMessage = null;
    _imageAliases = {};
    _normalizedImageAliases = {};
    _imageDataUrls.clear();
    _cachedChapterHtml = null;
    _cachedProcessedHtml = null;
    _cachedParagraphs = const [];
    _currentBookPath = assetPath;
    notifyListeners();

    try {
      _currentBook = await _epubService.parseEpub(assetPath);

      // Extract and cache images
      _extractImages();

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
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get current chapter index
  int get currentChapterIndex {
    if (_currentBook?.Chapters == null || _currentChapter == null) return 0;
    return _currentBook!.Chapters!.indexOf(_currentChapter!);
  }

  /// Save reading position (chapter index + scroll position)
  Future<void> saveReadingPosition(double scrollPosition) async {
    if (_currentBookPath == null) return;
    await _libraryService.updateReadingProgress(
      _currentBookPath!,
      currentChapterIndex,
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

  void _extractImages() {
    final images = _currentBook?.Content?.Images;
    if (images == null) return;

    for (final entry in images.entries) {
      if (entry.value.Content == null) continue;
      final fileName = entry.key;
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

    return htmlContent.replaceAllMapped(_srcRegex, (match) {
      final dataUrl = _findImageDataUrl(match.group(1) ?? '');
      return dataUrl != null ? 'src="$dataUrl"' : match.group(0)!;
    });
  }

  String? _findImageDataUrl(String src) {
    final cleanSrc = _stripParentDirs(src);
    final fileName = _imageAliases[src] ??
        _imageAliases[cleanSrc] ??
        _normalizedImageAliases[cleanSrc] ??
        _normalizedImageAliases[src.split('/').last.toLowerCase()];
    if (fileName == null) return null;

    return _imageDataUrls.putIfAbsent(fileName, () {
      final bytes = _currentBook!.Content!.Images![fileName]!.Content!;
      return 'data:${_getMimeTypeFromName(fileName)};base64,${base64Encode(bytes)}';
    });
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
    _autoHideTimer?.cancel();
    super.dispose();
  }

  Future<void> jumpToChapter(EpubChapter chapter) async {
    _currentChapter = chapter;
    notifyListeners();
  }

  void nextChapter() {
    if (_currentBook == null || _currentChapter == null) return;

    final chapters = _currentBook!.Chapters!;
    final index = chapters.indexOf(_currentChapter!);
    if (index < chapters.length - 1) {
      _currentChapter = chapters[index + 1];
      notifyListeners();
    }
  }

  void previousChapter() {
    if (_currentBook == null || _currentChapter == null) return;

    final chapters = _currentBook!.Chapters!;
    final index = chapters.indexOf(_currentChapter!);
    if (index > 0) {
      _currentChapter = chapters[index - 1];
      notifyListeners();
    }
  }

  static const _blockSelector = 'p, div, h1, h2, h3, h4, h5, h6, li, blockquote';

  /// Keep only block elements that contain no other matched block, so wrapper
  /// divs aren't counted as separate paragraphs (which would make TTS speak and
  /// highlight them as one giant chunk). Linear in elements × depth.
  static List<dom.Element> _leafBlocks(dom.Element body) {
    final elements = body.querySelectorAll(_blockSelector);
    final matched = elements.toSet();
    final hasBlockChild = <dom.Element>{};
    for (final el in elements) {
      for (var node = el.parent; node != null; node = node.parent) {
        if (matched.contains(node) && !hasBlockChild.add(node)) break;
      }
    }
    return elements.where((el) => !hasBlockChild.contains(el)).toList();
  }

  /// Paragraphs and sentences of the current chapter, indexed exactly like
  /// the rendered page's data-para / data-sent attributes.
  List<TtsParagraph> get ttsParagraphs {
    getProcessedHtml();
    return _cachedParagraphs;
  }

  /// Wrap sentences in spans for sentence-level highlighting and collect the
  /// matching TTS paragraphs in the same pass, so spoken sentences always line
  /// up with the highlighted ones. Preserves inner tags (<i>, <b>, <a>, …).
  (String, List<TtsParagraph>) _processForTts(String htmlContent) {
    final body = html_parser.parse(htmlContent).body;
    if (body == null) return (htmlContent, const []);

    final paragraphs = <TtsParagraph>[];
    for (final p in _leafBlocks(body)) {
      final text = p.text.trim();
      if (text.isEmpty) continue;
      final paraIndex = paragraphs.length;

      final sentences = _splitHtmlIntoSentences(p.innerHtml);
      final spoken = <TtsSentence>[];
      if (sentences.length > 1) {
        final newInnerHtml = StringBuffer();
        for (int sIdx = 0; sIdx < sentences.length; sIdx++) {
          final sentence = sentences[sIdx];
          if (sentence.trim().isEmpty) continue;
          newInnerHtml.write(
            '<span class="tts-sent" data-para="$paraIndex" data-sent="$sIdx">$sentence</span>',
          );
          if (sIdx < sentences.length - 1) newInnerHtml.write(' ');
        }
        p.innerHtml = newInnerHtml.toString();
        // Read the sentences back from the parsed spans: that's exactly the
        // text the page shows for each data-sent index.
        final seen = <int>{};
        for (final span in p.querySelectorAll('span.tts-sent')) {
          final idx = int.tryParse(span.attributes['data-sent'] ?? '');
          final spanText = span.text.trim();
          if (idx != null && spanText.isNotEmpty && seen.add(idx)) {
            spoken.add((index: idx, text: spanText));
          }
        }
      }
      p.attributes['data-para'] = paraIndex.toString();
      p.classes.add('tts-para');
      paragraphs.add(TtsParagraph(text, spoken));
    }

    return (body.innerHtml, paragraphs);
  }

  /// Split an HTML string into sentences, preserving inner tags (<i>, <b>, <a>, etc.).
  /// Splits at sentence-ending punctuation ([.!?]) followed by whitespace,
  /// but only when the punctuation is in text content (not inside an HTML tag).
  List<String> _splitHtmlIntoSentences(String html) {
    final sentences = <String>[];
    final current = StringBuffer();
    bool inTag = false;

    int i = 0;
    while (i < html.length) {
      final char = html[i];

      if (char == '<') {
        inTag = true;
        current.write(char);
        i++;
        continue;
      }
      if (char == '>') {
        inTag = false;
        current.write(char);
        i++;
        continue;
      }

      current.write(char);

      // Check for sentence boundary: punctuation followed by whitespace, not inside a tag
      if (!inTag && (char == '.' || char == '!' || char == '?')) {
        if (i + 1 < html.length) {
          final next = html[i + 1];
          if (next == ' ' || next == '\n' || next == '\t' || next == '\r') {
            // Sentence boundary found
            sentences.add(current.toString());
            current.clear();
            // Skip the whitespace between sentences
            i++;
            while (i + 1 < html.length) {
              final c = html[i + 1];
              if (c == ' ' || c == '\n' || c == '\t' || c == '\r') {
                i++;
              } else {
                break;
              }
            }
            i++;
            continue;
          }
        }
      }

      i++;
    }

    if (current.isNotEmpty) {
      sentences.add(current.toString());
    }

    return sentences;
  }

  /// Get processed HTML with images replaced and sentences wrapped for TTS.
  /// Cached to avoid expensive HTML parsing + regex on every widget rebuild.
  String getProcessedHtml() {
    final rawHtml = _currentChapter?.HtmlContent;
    if (rawHtml == null) return '';
    if (rawHtml == _cachedChapterHtml && _cachedProcessedHtml != null) {
      return _cachedProcessedHtml!;
    }
    _cachedChapterHtml = rawHtml;
    final (html, paragraphs) = _processForTts(processHtmlWithImages(rawHtml));
    _cachedProcessedHtml = html;
    _cachedParagraphs = paragraphs;
    return html;
  }
}
