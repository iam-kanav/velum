import 'dart:async';
import 'dart:convert';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;

import '../../data/services/epub_service.dart';
import '../../../library/data/services/library_service.dart';

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

      final before = (snippetStart > 0 ? '...' : '') +
          plainText.substring(snippetStart, idx);
      final matched = plainText.substring(idx, idx + query.length);
      final after = plainText.substring(idx + query.length, snippetEnd) +
          (snippetEnd < plainText.length ? '...' : '');

      final positionPercent = plainText.isNotEmpty ? idx / plainText.length : 0.0;

      results.add(GlobalSearchResult(
        chapterIndex: i,
        chapterTitle: title,
        snippetBefore: before,
        matchedText: matched,
        snippetAfter: after,
        positionPercent: positionPercent,
      ));

      searchFrom = idx + query.length;
    }
  }

  return results;
}

class ReaderNotifier extends ChangeNotifier {
  final EpubService _epubService;
  final LibraryService _libraryService;

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

  // Performance: cache processed HTML to avoid expensive re-parsing on every widget rebuild
  String? _cachedChapterHtml;
  String? _cachedProcessedHtml;

  Future<void> loadBook(String assetPath) async {
    _isLoading = true;
    _errorMessage = null;
    _imageDataUrls = {};
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
        // Determine MIME type from filename
        final mimeType = _getMimeType(fileName);

        // Convert to base64 data URL
        final base64Data = base64Encode(imageContent.Content!);
        final dataUrl = 'data:$mimeType;base64,$base64Data';

        // Store with various key formats for matching
        _imageDataUrls[fileName] = dataUrl;

        // Also store with just the filename (no path)
        final justFileName = fileName.split('/').last;
        _imageDataUrls[justFileName] = dataUrl;

        // Store without extension variations
        if (fileName.contains('/')) {
          final pathParts = fileName.split('/');
          // Store the last two parts (e.g., "images/cover.jpg")
          if (pathParts.length >= 2) {
            _imageDataUrls['${pathParts[pathParts.length - 2]}/${pathParts.last}'] =
                dataUrl;
          }
        }
      }
    }

    debugPrint('Cached ${_imageDataUrls.length} image data URLs');
  }

  String _getMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    } else if (lower.endsWith('.png')) {
      return 'image/png';
    } else if (lower.endsWith('.gif')) {
      return 'image/gif';
    } else if (lower.endsWith('.svg')) {
      return 'image/svg+xml';
    } else if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/png'; // Default
  }

  /// Process HTML content to replace image sources with base64 data URLs
  String processHtmlWithImages(String? htmlContent) {
    if (htmlContent == null) return '';
    if (_imageDataUrls.isEmpty) return htmlContent;

    var processed = htmlContent;

    // Replace image sources with data URLs
    // Match src="..." or src='...'
    final srcRegex = RegExp(
      r'src=["'
      ']([^"'
      ']+)["'
      ']',
      caseSensitive: false,
    );

    processed = processed.replaceAllMapped(srcRegex, (match) {
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

    // Try just the filename
    final justFileName = src.split('/').last;
    if (_imageDataUrls.containsKey(justFileName)) {
      return _imageDataUrls[justFileName];
    }

    // Try matching the last part of the path
    for (final key in _imageDataUrls.keys) {
      if (key.endsWith(justFileName) || src.endsWith(key.split('/').last)) {
        return _imageDataUrls[key];
      }
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

    final chapters = _currentBook!.Chapters!.map((ch) => {
      'html': ch.HtmlContent ?? '',
      'title': ch.Title ?? '',
    }).toList();

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

  /// Extract structured plain text from HTML, matching JS ttsGetParagraphs() order
  /// Only extracts from <p> tags to ensure alignment with JS highlighting
  String extractStructuredText() {
    if (_currentChapter?.HtmlContent == null) return '';

    // Process HTML with images first
    final htmlContent = processHtmlWithImages(_currentChapter!.HtmlContent);

    final document = html_parser.parse(htmlContent);
    final body = document.body;
    if (body == null) return '';

    // Only extract from p elements (matching JS querySelectorAll('p'))
    final paragraphs = <String>[];
    final pElements = body.querySelectorAll('p');

    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isNotEmpty) {
        paragraphs.add(text);
      }
    }

    // Join paragraphs with double newlines for TTS chunking
    return paragraphs.join('\n\n');
  }

  /// Process HTML to wrap sentences in spans for sentence-level highlighting
  /// Returns the processed HTML with each sentence wrapped in <span class="tts-sent" data-para="X" data-sent="Y">
  String processHtmlForSentenceHighlight(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final body = document.body;
    if (body == null) return htmlContent;

    final pElements = body.querySelectorAll('p');
    int paraIndex = 0;

    for (final p in pElements) {
      final text = p.text.trim();
      if (text.isEmpty) continue;

      // Split into sentences
      final sentences = _splitIntoSentences(text);
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
          // Add space between sentences
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

  /// Split text into sentences (same logic as TtsService)
  List<String> _splitIntoSentences(String text) {
    // Split on sentence-ending punctuation followed by space or end
    final regex = RegExp(r'(?<=[.!?])\s+');
    return text.split(regex);
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

    // Only index <p> elements — must match extractStructuredText() which
    // uses body.querySelectorAll('p'). Using other tags (div, h1-h6, li, etc.)
    // would shift the indices and cause TTS to read the wrong paragraph.
    final pElements = body.querySelectorAll('p');
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
