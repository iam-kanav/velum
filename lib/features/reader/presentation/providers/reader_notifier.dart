import 'dart:async';
import 'dart:convert';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../data/services/epub_service.dart';
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

  // Image cache: filename -> base64 data URL
  Map<String, String> _imageDataUrls = {};
  Map<String, String> get imageDataUrls => _imageDataUrls;

  // Normalized key lookup map for O(1) image matching
  Map<String, String> _normalizedImageLookup = {};

  // Performance: cache processed HTML to avoid expensive re-parsing on every widget rebuild
  String? _cachedChapterHtml;
  String? _cachedProcessedHtml;

  Future<void> loadBook(String assetPath) async {
    _isLoading = true;
    _errorMessage = null;
    _imageDataUrls = {};
    _normalizedImageLookup = {};
    _cachedChapterHtml = null;
    _cachedProcessedHtml = null;
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
    if (_currentBook?.Content?.Images == null) return;

    final images = _currentBook!.Content!.Images!;
    debugPrint('Extracting ${images.length} images from EPUB');

    for (final entry in images.entries) {
      final fileName = entry.key;
      final imageContent = entry.value;

      if (imageContent.Content != null) {
        final mimeType = _getMimeTypeFromName(fileName);
        final base64Data = base64Encode(imageContent.Content!);
        final dataUrl = 'data:$mimeType;base64,$base64Data';

        _imageDataUrls[fileName] = dataUrl;

        final justFileName = fileName.split('/').last;
        _imageDataUrls[justFileName] = dataUrl;

        if (fileName.contains('/')) {
          final pathParts = fileName.split('/');
          if (pathParts.length >= 2) {
            _imageDataUrls['${pathParts[pathParts.length - 2]}/${pathParts.last}'] =
                dataUrl;
          }
        }
      }
    }

    // Build normalized lookup map for O(1) matching
    _normalizedImageLookup = _buildNormalizedLookup(_imageDataUrls);
    debugPrint('Cached ${_imageDataUrls.length} image data URLs');
  }

  /// Process HTML content to replace image sources with base64 data URLs
  String processHtmlWithImages(String? htmlContent) {
    if (htmlContent == null) return '';
    if (_imageDataUrls.isEmpty) return htmlContent;

    var processed = htmlContent;

    // Replace image sources with data URLs
    processed = processed.replaceAllMapped(_srcRegex, (match) {
      final originalSrc = match.group(1) ?? '';

      // Try to find matching image in our cache
      String? dataUrl = _findImageDataUrl(originalSrc);

      if (dataUrl != null) {
        return 'src="$dataUrl"';
      }

      // If not found, return original
      return match.group(0) ?? '';
    });

    return processed;
  }

  /// Build a secondary lookup map keyed by normalized filenames for O(1) matching.
  static Map<String, String> _buildNormalizedLookup(Map<String, String> imageDataUrls) {
    final lookup = <String, String>{};
    for (final entry in imageDataUrls.entries) {
      final key = entry.key;
      final dataUrl = entry.value;
      // Store with cleaned-up keys (no leading ../)
      var clean = key;
      while (clean.startsWith('../')) {
        clean = clean.substring(3);
      }
      lookup[clean] = dataUrl;
      // Store just the filename
      lookup[key.split('/').last.toLowerCase()] = dataUrl;
    }
    return lookup;
  }

  String? _findImageDataUrl(String src) {
    // Direct match
    if (_imageDataUrls.containsKey(src)) {
      return _imageDataUrls[src];
    }

    // Try without leading ../
    var cleanSrc = src;
    while (cleanSrc.startsWith('../')) {
      cleanSrc = cleanSrc.substring(3);
    }
    if (_imageDataUrls.containsKey(cleanSrc)) {
      return _imageDataUrls[cleanSrc];
    }
    if (_normalizedImageLookup.containsKey(cleanSrc)) {
      return _normalizedImageLookup[cleanSrc];
    }

    // Try just the filename (case-insensitive via normalized lookup)
    final justFileName = src.split('/').last.toLowerCase();
    if (_normalizedImageLookup.containsKey(justFileName)) {
      return _normalizedImageLookup[justFileName];
    }

    return null;
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

  void showUITemporarily() {
    _showUI = true;
    notifyListeners();

    // Cancel any existing timer and start a new one
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(_autoHideDuration, () {
      _showUI = false;
      notifyListeners();
    });
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

  /// Extract plain text from the current chapter's HTML content
  String extractPlainText() {
    if (_currentChapter?.HtmlContent == null) return '';

    // Process HTML with images first (to ensure we have the full content)
    final htmlContent = processHtmlWithImages(_currentChapter!.HtmlContent);

    // Parse HTML and extract text
    final document = html_parser.parse(htmlContent);
    final body = document.body;
    if (body == null) return '';

    // Get text content, normalize whitespace
    String text = body.text;

    // Normalize multiple newlines to paragraph breaks
    text = text.replaceAll(RegExp(r'\n\s*\n+'), '\n\n');
    // Normalize multiple spaces
    text = text.replaceAll(RegExp(r' +'), ' ');
    // Trim each line
    text = text.split('\n').map((line) => line.trim()).join('\n');
    // Remove leading/trailing whitespace
    text = text.trim();

    return text;
  }

  /// Filter block elements to remove any that are ancestors of other elements
  /// in the list. Prevents wrapper divs from being counted as separate
  /// paragraphs (which would cause TTS to speak and highlight them as one
  /// giant chunk covering the entire chapter).
  static List<dom.Element> _filterToLeafBlocks(List<dom.Element> elements) {
    if (elements.length <= 1) return elements;
    return elements.where((el) {
      // Exclude this element if any other matched element is its descendant
      return !elements.any((other) {
        if (identical(other, el)) return false;
        dom.Node? node = other.parent;
        while (node != null) {
          if (identical(node, el)) return true;
          node = node.parent;
        }
        return false;
      });
    }).toList();
  }

  /// Extract structured plain text from HTML, matching JS ttsGetParagraphs() order
  /// Only extracts from <p> tags to ensure alignment with JS highlighting
  String extractStructuredText() {
    if (_currentChapter?.HtmlContent == null) return '';

    // Process HTML with images first
    final htmlContent = processHtmlWithImages(_currentChapter!.HtmlContent);

    final document = html_parser.parse(htmlContent);
    final body = document.body;
    if (body == null) return '';

    // Extract from block elements to avoid missing text
    final paragraphs = <String>[];
    final allElements = body.querySelectorAll(
      'p, div, h1, h2, h3, h4, h5, h6, li, blockquote',
    );
    // Filter out ancestor elements so wrapper divs don't duplicate child text
    final pElements = _filterToLeafBlocks(allElements.toList());

    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isNotEmpty) {
        paragraphs.add(text);
      }
    }

    // Join paragraphs with double newlines for TTS chunking
    return paragraphs.join('\n\n');
  }

  /// Process HTML to wrap sentences in spans for sentence-level highlighting.
  /// Preserves inner HTML tags (<i>, <b>, <a>, etc.) by splitting on the
  /// innerHTML string rather than plain text.
  String processHtmlForSentenceHighlight(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final body = document.body;
    if (body == null) return htmlContent;

    final allElements = body.querySelectorAll(
      'p, div, h1, h2, h3, h4, h5, h6, li, blockquote',
    );
    // Filter out ancestor elements so wrapper divs don't get separate indices
    final pElements = _filterToLeafBlocks(allElements.toList());
    int paraIndex = 0;

    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isEmpty) continue;

      // Split innerHTML into sentences, preserving inner tags
      final sentences = _splitHtmlIntoSentences(p.innerHtml);
      if (sentences.length <= 1) {
        // Single sentence - just add paragraph attributes
        p.attributes['data-para'] = paraIndex.toString();
        p.classes.add('tts-para');
      } else {
        // Multiple sentences - wrap each in a span
        final newInnerHtml = StringBuffer();
        for (int sIdx = 0; sIdx < sentences.length; sIdx++) {
          final sentence = sentences[sIdx];
          if (sentence.trim().isEmpty) continue;
          newInnerHtml.write(
            '<span class="tts-sent" data-para="$paraIndex" data-sent="$sIdx">$sentence</span>',
          );
          // Add space between sentences for correct rendering
          if (sIdx < sentences.length - 1) newInnerHtml.write(' ');
        }
        p.innerHtml = newInnerHtml.toString();
        p.attributes['data-para'] = paraIndex.toString();
        p.classes.add('tts-para');
      }
      paraIndex++;
    }

    return body.innerHtml;
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
    final htmlWithImages = processHtmlWithImages(rawHtml);
    _cachedProcessedHtml = processHtmlForSentenceHighlight(htmlWithImages);
    return _cachedProcessedHtml!;
  }

  /// Process HTML to wrap paragraphs with IDs for TTS highlighting
  /// Only indexes <p> elements to match extractStructuredText() and chunkText()
  String processHtmlForTts(String? htmlContent) {
    if (htmlContent == null || htmlContent.isEmpty) return htmlContent ?? '';

    final document = html_parser.parse(htmlContent);
    final body = document.body;
    if (body == null) return htmlContent;

    // Index block elements consistently with extractStructuredText()
    final allElements = body.querySelectorAll(
      'p, div, h1, h2, h3, h4, h5, h6, li, blockquote',
    );
    // Filter out ancestor elements so wrapper divs don't get separate indices
    final pElements = _filterToLeafBlocks(allElements.toList());
    int paragraphIndex = 0;

    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isEmpty) continue;

      p.attributes['id'] = 'tts-para-$paragraphIndex';
      p.attributes['data-para'] = paragraphIndex.toString();
      p.classes.add('tts-paragraph');
      paragraphIndex++;
    }

    // Return only the body's inner HTML to preserve original structure
    return body.innerHtml;
  }
}
