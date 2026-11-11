import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/reader_notifier.dart';
import 'package:velum/features/library/data/services/library_service.dart';
import '../widgets/reader_tutorial_overlay.dart';
import 'package:velum/features/settings/data/models/reader_settings.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import 'package:velum/features/settings/presentation/widgets/settings_modal.dart';
import 'package:velum/features/tts/data/models/tts_chunk.dart';
import 'package:velum/features/tts/data/models/tts_settings.dart';
import 'package:velum/features/tts/presentation/providers/tts_notifier.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/highlight.dart';
import '../../data/models/bookmark.dart';
import '../providers/highlight_notifier.dart';
import '../providers/bookmark_notifier.dart';
import '../widgets/contents_modal.dart';
import '../widgets/highlights_modal.dart';

import 'package:flutter/services.dart'
    show HapticFeedback, MethodChannel, rootBundle;
import 'package:velum/features/reader/presentation/widgets/color_picker_bar.dart';
import 'package:velum/features/reader/presentation/widgets/global_search_overlay.dart';
import 'package:velum/features/reader/presentation/widgets/book_complete_overlay.dart';
import 'package:velum/features/reader/presentation/widgets/tts_fab.dart';
import 'package:velum/core/theme/app_colors.dart';
import 'package:velum/core/storage/book_data.dart';
import 'package:velum/features/notes/data/note_service.dart';
import 'package:velum/core/motion/motion.dart';

const Color _accent = AppColors.accent;

/// Reader bottom bar (progress line + controls row).
const double _barHeight = 96;

class ReaderScreen extends StatefulWidget {
  final String assetPath;

  const ReaderScreen({super.key, required this.assetPath});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final WebViewController _controller;

  /// A pasted file ("New File"): one page, no chapter swiping or
  /// "finished the book" screen.
  late final bool _isNote = NoteService.isNote(widget.assetPath);
  static String? _readerJs; // reader.js, loaded once
  String? _lastHtmlContent;
  double _savedScrollPosition = 0;
  bool _shouldRestoreScroll = false;
  String? _lastHighlightKey; // Track current TTS highlight position
  bool _isPageReady = false; // Track if JS is injected and ready
  bool _showTutorial = false; // First-time tutorial overlay
  bool _followOff = false; // User scrolled away from the spoken sentence
  bool _showBookComplete = false; // End-of-book celebration screen

  // Cache for custom font base64 to avoid blocking file I/O on every content load
  String? _cachedFontPath;
  String? _cachedFontBase64;

  // Global search
  bool _showSearch = false;
  double? _pendingScrollPercent;

  // Page turn animation
  late AnimationController _pageAnimController;
  late Animation<Offset> _slideAnimation;

  // Text selection / highlight color picker
  bool _showColorPicker = false;
  Rect? _selectionRect; // selection on screen: top of first line, end of last
  String _selectedText = '';
  int _selectionStartOffset = 0;
  int _selectionEndOffset = 0;

  // Pending scroll-to-highlight after chapter load
  String? _pendingScrollHighlightId;

  // GlobalKeys for tutorial spotlight positioning
  final GlobalKey _backButtonKey = GlobalKey();
  final GlobalKey _highlightsIconKey = GlobalKey();
  final GlobalKey _chapterNameKey = GlobalKey();
  final GlobalKey _settingsIconKey = GlobalKey();
  final GlobalKey _fabKey = GlobalKey();

  // Cached reference to avoid looking up ancestor in dispose()
  TtsNotifier? _ttsNotifier;
  ReaderNotifier? _readerNotifier;
  HighlightNotifier? _highlightNotifier;
  BookmarkNotifier? _bookmarkNotifier;

  @override
  void initState() {
    super.initState();
    _prefs = context.read<SharedPreferences>();
    _initController();
    _checkTutorialFlag();
    WidgetsBinding.instance.addObserver(this);

    // Initialize page turn animation
    _pageAnimController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _pageAnimController, curve: Curves.easeOut),
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChapterPositions();

      // Highlight the sentence being read and follow it between chapters.
      // Read-aloud is app-wide: it may already be reading this book (or
      // another one) and carries on after this screen closes.
      _ttsNotifier = context.read<TtsNotifier>();
      _lastTtsChapter = _ttsNotifier!.chapterIndex;
      _ttsNotifier!.addListener(_onTtsStateChanged);
      _ttsNotifier!.onBookFinished = _onBookFinished;

      _readerNotifier = context.read<ReaderNotifier>();
      _readerNotifier!.addListener(_onReaderChanged);
      _readerNotifier!.loadBook(widget.assetPath);

      // Load highlights for this book and listen for removals
      _highlightNotifier = context.read<HighlightNotifier>();
      _highlightNotifier!.loadHighlights(widget.assetPath);
      _highlightNotifier!.addListener(_onHighlightChanged);

      // Load bookmarks for this book
      _bookmarkNotifier = context.read<BookmarkNotifier>();
      _bookmarkNotifier!.loadBookmarks(widget.assetPath);
    });
  }

  @override
  void dispose() {
    // Save reading position when exiting
    _savePosition();

    WidgetsBinding.instance.removeObserver(this);
    _readerNotifier?.removeListener(_onReaderChanged);
    _highlightNotifier?.removeListener(_onHighlightChanged);
    // Reading aloud carries on after the reader closes.
    _ttsNotifier?.removeListener(_onTtsStateChanged);
    if (_ttsNotifier?.onBookFinished == _onBookFinished) {
      _ttsNotifier!.onBookFinished = null;
    }
    // Read-aloud was waiting for the new page to say where to carry on, and
    // no answer is coming now: start from the remembered sentence rather
    // than stay "playing" in silence.
    if (_continuePending) {
      _isPageReady = false; // no page left to highlight on
      _continueReading(_rememberedStart);
    }
    _continueFallback?.cancel();
    _pageAnimController.dispose();
    super.dispose();
  }

  Object? _shownChapter;
  int _shownChapterIndex = 0;

  /// Where the reader was in each chapter of this book: scroll offset and
  /// the last read-aloud sentence, so returning to a chapter (swipe, contents)
  /// picks up exactly there. Persisted per book.
  final Map<int, ({double scroll, int? para, int? sent})> _chapterPositions =
      {};
  double? _pendingBookmarkScroll;
  late final SharedPreferences _prefs;

  void _loadChapterPositions() {
    final raw = BookData.read(
      _prefs,
      BookData.chapterPositions,
      widget.assetPath,
    );
    if (raw == null) return;
    try {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
        final l = v as List<dynamic>;
        _chapterPositions[int.parse(k)] = (
          scroll: (l[0] as num).toDouble(),
          para: l[1] as int?,
          sent: l[2] as int?,
        );
      });
    } catch (_) {}
  }

  void _saveChapterPositions() {
    BookData.write(
      _prefs,
      BookData.chapterPositions,
      widget.assetPath,
      jsonEncode({
        for (final e in _chapterPositions.entries)
          '${e.key}': [e.value.scroll, e.value.para, e.value.sent],
      }),
    );
  }

  /// Remember the chapter being left: scroll offset and read-aloud position.
  void _rememberChapter(int index) {
    final tts = _ttsNotifier;
    final chunk = tts?.currentChunk;
    // While read-aloud waits to carry on in a new chapter it has no place
    // in it yet.
    final hasTts =
        tts != null &&
        _ownsTts &&
        !_continuePending &&
        tts.chapterIndex == index &&
        tts.chunks.isNotEmpty &&
        tts.state != TtsState.idle;
    final previous = _chapterPositions[index];
    _chapterPositions[index] = (
      scroll: _savedScrollPosition,
      para: hasTts ? chunk?.paragraphIndex : previous?.para,
      sent: hasTts ? chunk?.sentenceIndex : previous?.sent,
    );
    _saveChapterPositions();
  }

  /// The sentence the chapter on screen was left on, as "para:sent" ("" if
  /// read-aloud hasn't been there).
  String get _rememberedStart {
    final remembered = _chapterPositions[_shownChapterIndex];
    return remembered?.para == null
        ? ''
        : '${remembered!.para}:${remembered.sent ?? ''}';
  }

  /// Where a chapter being turned to opens: a bookmark's spot, else where
  /// the reader left it, else the top. Search/highlight jumps scroll on
  /// their own.
  double _openingScroll(int index) =>
      _pendingBookmarkScroll ??
      (_pendingScrollPercent == null && _pendingScrollHighlightId == null
          ? _chapterPositions[index]?.scroll
          : null) ??
      0;

  /// Save where the reader is: this chapter's spot, and the book's position
  /// in the library. Nothing is saved until the first chapter is on the
  /// page: before that the position isn't known, and saving would reset it.
  void _savePosition() {
    if (_shownChapter == null || _isInitialLoad) return;
    _rememberChapter(_shownChapterIndex);
    _readerNotifier?.saveReadingPosition(_savedScrollPosition);
  }

  bool? _lastShowUI;

  /// When the bars hide, the Play button slides down onto where the settings
  /// gear was; taps landing during that move were meant for the gear.
  DateTime _fabMovedAt = DateTime(0);

  /// Changing chapter while reading aloud (swipe, contents, search,
  /// highlights, bookmarks, start over) carries on reading in the new
  /// chapter, from where its page opens. When not playing, the old
  /// chapter's read-aloud position is dropped so it isn't highlighted on
  /// the new page.
  void _onReaderChanged() {
    final showUI = _readerNotifier?.showUI;
    if (showUI != _lastShowUI) {
      _lastShowUI = showUI;
      _fabMovedAt = DateTime.now();
    }
    final chapter = _readerNotifier?.currentChapter;
    if (identical(chapter, _shownChapter)) return;
    final index = _readerNotifier?.currentChapterIndex ?? 0;
    final tts = _ttsNotifier;
    final owns = tts != null && _ownsTts;

    // Reopening the book being read aloud: show the chapter it's on.
    if (_shownChapter == null &&
        owns &&
        tts.chunks.isNotEmpty &&
        tts.chapterIndex != index &&
        _followTtsChapter(tts.chapterIndex, animate: false)) {
      return;
    }

    final firstShow = _shownChapter == null;
    if (!firstShow) {
      _rememberChapter(_shownChapterIndex);
      // The book reopens at this chapter even if the app is quit without
      // warning before the next save.
      _readerNotifier!.saveReadingPosition(_openingScroll(index));
    }
    _shownChapter = chapter;
    _shownChapterIndex = index;
    // The old page stays up until the new one loads: don't highlight the
    // new chapter's sentences on it.
    if (_readerNotifier!.getProcessedHtml() != _lastHtmlContent) {
      _isPageReady = false;
    }
    if (firstShow || _followingTts || !owns) return;

    if (tts.isPlaying) {
      final paragraphs = _readerNotifier!.ttsParagraphs;
      if (paragraphs.isNotEmpty) {
        _lastTtsChapter = index;
        tts.loadChapter(_readAloudBook(), index, paragraphs);
        _waitToContinue();
        return;
      }
    }
    if (tts.chunks.isNotEmpty) {
      tts.stop();
      tts.clearContent();
    }
  }

  /// Read-aloud is on this book (rather than another one, carrying on in
  /// the background).
  bool get _ownsTts => _ttsNotifier?.bookPath == widget.assetPath;

  /// Read-aloud has the chapter on screen loaded.
  bool get _ttsOnThisChapter {
    final tts = _ttsNotifier;
    return tts != null &&
        _shownChapter != null &&
        _ownsTts &&
        tts.chunks.isNotEmpty &&
        tts.chapterIndex == _shownChapterIndex;
  }

  /// The read-aloud chapter last seen here; a change means reading moved
  /// on to the next chapter by itself.
  int _lastTtsChapter = 0;
  bool _followingTts = false;

  /// Turn to the chapter read-aloud is on. False if there's no such page.
  bool _followTtsChapter(int index, {bool animate = true}) {
    final reader = _readerNotifier;
    final chapters = reader?.currentBook?.Chapters;
    if (reader == null || chapters == null || index >= chapters.length) {
      return false;
    }
    if (animate) {
      // Listening starts the chapter from the top.
      _chapterPositions.remove(index);
      _animatePageTurn(index > _shownChapterIndex ? -1 : 1);
    } else {
      // The saved scroll position belongs to another chapter.
      _isInitialLoad = false;
    }
    _followingTts = true;
    reader.jumpToChapter(chapters[index]);
    _followingTts = false;
    return true;
  }

  void _onBookFinished() {
    if (mounted && _ownsTts && !_isNote) {
      setState(() => _showBookComplete = true);
    }
  }

  /// This book as read-aloud sees it, so it can carry on into later
  /// chapters with the reader closed.
  ReadAloudBook _readAloudBook() {
    final reader = _readerNotifier!;
    final book = reader.currentBook;
    final chapters = [...?book?.Chapters];
    final library = context.read<LibraryService>();
    final path = widget.assetPath;
    return ReadAloudBook(
      path: path,
      title: book?.Title ?? 'Unknown Book',
      chapterTitles: [for (final c in chapters) c.Title ?? 'Unknown Chapter'],
      // Same paragraphs as the page, which then shows the chapter without
      // processing it again.
      paragraphsFor: (i) => reader.paragraphsOf(chapters[i].HtmlContent ?? ''),
      onChapterStarted: (i) => library.updateReadingProgress(path, i, 0),
    );
  }

  /// Reading carried on into a new chapter and waits, still "playing", for
  /// its page to say where to start (see onPageFinished).
  bool _continuePending = false;
  Timer? _continueFallback;

  void _waitToContinue() {
    _continuePending = true;
    // Same page content (chapters that share one file): no reload coming.
    if (_isPageReady) _askWhereToContinue();
    _continueFallback?.cancel();
    // If the page never reports, start from the remembered sentence.
    _continueFallback = Timer(
      const Duration(seconds: 5),
      () => _continueReading(_rememberedStart),
    );
  }

  /// Ask the page where reading should carry on: the remembered sentence
  /// if it's on screen, else the first one visible. It answers with a
  /// 'tts-start:' message once any scrolling has settled.
  void _askWhereToContinue() {
    final jumping =
        _pendingScrollHighlightId != null || _pendingScrollPercent != null;
    final remembered = _chapterPositions[_shownChapterIndex];
    final top = _topBarHeight.round();
    _controller.runJavaScript(
      'window.ttsContinueFrom($top, ${remembered?.para ?? -1}, '
      '${remembered?.sent ?? -1}, ${jumping ? 400 : 100});',
    );
  }

  /// Start reading the chapter just turned to at [start] ("para:sent",
  /// "para", or "" for its first sentence).
  void _continueReading(String start) {
    if (!_continuePending) return;
    _continuePending = false;
    _continueFallback?.cancel();
    final tts = _ttsNotifier;
    if (tts == null || !_ttsOnThisChapter) return;
    final parts = start.split(':');
    final para = int.tryParse(parts.first) ?? tts.chunks.first.paragraphIndex;
    final sent = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (tts.isPlaying) {
      tts.jumpTo(para, sent);
    } else if (tts.isPaused) {
      tts.moveTo(para, sent); // paused while the page was loading
    }
    _updateTtsHighlight(tts);
  }

  /// Listener for TTS state changes - updates WebView highlight via JS
  /// without triggering a full widget rebuild.
  void _onTtsStateChanged() {
    final tts = _ttsNotifier;
    if (tts == null) return;
    // Reading moved on to the next chapter by itself: turn the page with it.
    if (_ownsTts && tts.chapterIndex != _lastTtsChapter) {
      _lastTtsChapter = tts.chapterIndex;
      _followTtsChapter(tts.chapterIndex);
    }
    _updateTtsHighlight(tts);
  }

  /// Sanitize a string to only allow UUID characters (alphanumeric + hyphens).
  static final RegExp _uuidSanitizer = RegExp(r'[^a-zA-Z0-9\-]');
  String _sanitizeId(String id) => id.replaceAll(_uuidSanitizer, '');

  /// Listener for highlight changes — removes deleted highlights from the WebView.
  void _onHighlightChanged() {
    final removedId = _highlightNotifier?.lastRemovedHighlightId;
    if (removedId != null && _isPageReady) {
      _highlightNotifier!.clearLastRemoved();
      final safeId = _sanitizeId(removedId);
      _controller.runJavaScript("window.removeHighlight('$safeId');");
    }
  }

  /// Leaving the app in any way may be the last chance to save. On the Mac
  /// it is never "paused": it loses focus, is hidden, or quits.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _saveOnLeaving();
  }

  /// Save the position as known now (the app may not live long enough for
  /// the page to answer), then again with the page's exact scroll offset:
  /// the last one it reported can be a moment old.
  Future<void> _saveOnLeaving() async {
    _savePosition();
    final chapter = _shownChapter;
    if (chapter == null || !_isPageReady) return;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        'window.scrollY',
      );
      final scroll = result is num
          ? result.toDouble()
          : double.tryParse('$result');
      if (!mounted ||
          scroll == null ||
          scroll == _savedScrollPosition ||
          !_isPageReady ||
          !identical(chapter, _shownChapter)) {
        return;
      }
      _savedScrollPosition = scroll;
      _savePosition();
    } catch (_) {}
  }

  /// Check if the user has seen the reader tutorial before.
  void _checkTutorialFlag() {
    _showTutorial = !(_prefs.getBool('has_seen_reader_tutorial') ?? false);
  }

  /// Dismiss tutorial and persist the flag
  void _dismissTutorial() async {
    await _prefs.setBool('has_seen_reader_tutorial', true);
    if (mounted) {
      setState(() => _showTutorial = false);
    }
  }

  // ── Search ──────────────────────────────────────────────────────────

  void _openSearch() => setState(() => _showSearch = true);

  void _closeSearch() => setState(() => _showSearch = false);

  void _onSearchResultTap(GlobalSearchResult result) {
    _closeSearch();
    _showChapter(
      result.chapterIndex,
      scrollNow: () {
        final safePct = result.positionPercent.clamp(0.0, 1.0);
        _controller.runJavaScript(
          'window.scrollTo(0, document.body.scrollHeight * $safePct);',
        );
      },
      scrollOnLoad: () => _pendingScrollPercent = result.positionPercent,
    );
  }

  /// Go to a place in chapter [index] (search result, highlight, bookmark).
  /// [scrollNow] runs if that chapter is already on screen; otherwise
  /// [scrollOnLoad] notes what its page should do once loaded, and the
  /// chapter is opened. A chapter that doesn't exist is ignored, with
  /// nothing noted that a later chapter change could pick up.
  void _showChapter(
    int index, {
    required VoidCallback scrollNow,
    required VoidCallback scrollOnLoad,
  }) {
    final notifier = context.read<ReaderNotifier>();
    final chapters = notifier.currentBook?.Chapters;
    if (chapters == null || index < 0 || index >= chapters.length) return;
    if (index == notifier.currentChapterIndex) {
      scrollNow();
    } else {
      scrollOnLoad();
      notifier.jumpToChapter(chapters[index]);
    }
  }

  /// Height of the top bar, which lies over the page.
  double get _topBarHeight =>
      MediaQuery.of(context).padding.top + kToolbarHeight;

  /// Animate page turn - direction: -1 for next (left), 1 for prev (right)
  /// Full slide: old content slides out, new content slides in
  void _animatePageTurn(int direction) {
    // Slide out current content
    _slideAnimation =
        Tween<Offset>(
          begin: Offset.zero,
          end: Offset(direction.toDouble(), 0),
        ).animate(
          CurvedAnimation(parent: _pageAnimController, curve: Curves.easeIn),
        );

    _pageAnimController.forward(from: 0).then((_) {
      if (!mounted) return;
      // Content has changed by now, slide new content in from opposite side
      _slideAnimation =
          Tween<Offset>(
            begin: Offset(-direction.toDouble(), 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: _pageAnimController, curve: Curves.easeOut),
          );
      setState(() {});
      _pageAnimController.forward(from: 0);
    });
  }

  void _initController() {
    _controller = WebViewController();
    // The Mac WebView can't change its background; the page paints its own.
    if (!Platform.isMacOS) {
      _controller.setBackgroundColor(const Color(0x00000000));
    }
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ReaderChannel',
        onMessageReceived: (JavaScriptMessage message) {
          // The page can still be reporting after the reader has closed.
          if (!mounted) return;
          final notifier = context.read<ReaderNotifier>();
          switch (message.message) {
            case 'toggle':
              notifier.toggleUI();
              break;
            case 'next':
              // Pasted files are a single page: no swiping between chapters.
              if (_isNote) break;
              HapticFeedback.mediumImpact();
              final chapterBefore = notifier.currentChapter;
              notifier.nextChapter();
              if (identical(notifier.currentChapter, chapterBefore)) {
                // Already on the last chapter — show completion screen
                setState(() => _showBookComplete = true);
              } else {
                _animatePageTurn(-1);
              }
              break;
            case 'prev':
              if (_isNote) break;
              final chapterBefore = notifier.currentChapter;
              notifier.previousChapter();
              // Already on the first chapter: no page to turn.
              if (identical(notifier.currentChapter, chapterBefore)) break;
              HapticFeedback.mediumImpact();
              _animatePageTurn(1); // Slide right
              break;
            default:
              // Read-aloud follow mode toggled by the user scrolling away/back
              if (message.message.startsWith('tts-follow:')) {
                final off = message.message == 'tts-follow:off';
                if (off != _followOff) setState(() => _followOff = off);
              }
              // Handle external URL opening
              else if (message.message.startsWith('open-url:')) {
                // Only web links: a book's page could ask for anything.
                final uri = Uri.tryParse(message.message.substring(9));
                if (uri != null &&
                    (uri.isScheme('http') || uri.isScheme('https')) &&
                    uri.host.isNotEmpty) {
                  _openExternalUrl(uri.toString());
                }
              }
              // Handle scroll position message
              else if (message.message.startsWith('scroll:')) {
                final parsed = double.tryParse(message.message.substring(7));
                if (parsed != null) _savedScrollPosition = parsed;
              }
              // Handle text selection for highlighting
              else if (message.message.startsWith('selection:')) {
                try {
                  final json = jsonDecode(message.message.substring(10));
                  final text = json['text'] as String? ?? '';
                  final start = json['startOffset'] as int? ?? 0;
                  final end = json['endOffset'] as int? ?? 0;
                  double n(String k) => (json[k] as num?)?.toDouble() ?? 0;
                  if (text.isNotEmpty) {
                    setState(() {
                      _selectionRect = Rect.fromLTRB(
                        0,
                        n('top'),
                        n('right'),
                        n('bottom'),
                      );
                      _selectedText = text;
                      _selectionStartOffset = start;
                      _selectionEndOffset = end;
                      _showColorPicker = true;
                    });
                  }
                } catch (_) {}
              }
              // Handle dismiss color picker
              else if (message.message == 'selection-cleared') {
                if (_showColorPicker) {
                  setState(() => _showColorPicker = false);
                }
              }
              // Where read-aloud carries on after a chapter change
              else if (message.message.startsWith('tts-start:')) {
                _continueReading(message.message.substring(10));
              }
              // Handle TTS skip to paragraph/sentence
              else if (message.message.startsWith('tts-skip:')) {
                final parts = message.message.substring(9).split(':');
                final paraIndex = int.tryParse(parts[0]);
                final sentIndex = parts.length > 1
                    ? int.tryParse(parts[1])
                    : null;
                if (paraIndex != null) {
                  if (_loadTts()) {
                    context.read<TtsNotifier>().jumpTo(paraIndex, sentIndex);
                  }
                }
              }
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            // Allow the chapter content load itself
            if (request.url.startsWith('data:') ||
                request.url.startsWith('about:')) {
              return NavigationDecision.navigate;
            }
            // Block all other URLs from loading in the WebView.
            // The JS click interceptor opens them externally.
            return NavigationDecision.prevent;
          },
          onPageFinished: (String url) async {
            _readerJs ??= await rootBundle.loadString('assets/js/reader.js');
            await _controller.runJavaScript(_readerJs!);
            if (!mounted) return;
            _sendSwipeDistance(context.read<SettingsNotifier>().settings);

            _isPageReady = true; // JS is now ready
            if (_followOff) setState(() => _followOff = false);
            // Re-apply the TTS highlight: the new page starts without one,
            // and updates were skipped while it was loading.
            _lastHighlightKey = null;
            if (_ttsNotifier != null) _updateTtsHighlight(_ttsNotifier!);
            // Restore saved highlights for current chapter
            _restoreHighlights();
            // Restore scroll position after page loads
            if (_shouldRestoreScroll && _savedScrollPosition > 0) {
              final safeScroll = _savedScrollPosition.toInt();
              _controller.runJavaScript('window.scrollTo(0, $safeScroll);');
              _shouldRestoreScroll = false;
            }
            // Reading aloud carried on into this chapter: start where the
            // page opens, once any jump to a highlight or search result
            // (below, after 300 ms) has finished.
            if (_continuePending && mounted) _askWhereToContinue();
            // Scroll to a pending highlight if navigated from highlights modal
            if (_pendingScrollHighlightId != null) {
              final hlId = _sanitizeId(_pendingScrollHighlightId!);
              _pendingScrollHighlightId = null;
              // Small delay to let restoreHighlights finish rendering
              Future.delayed(const Duration(milliseconds: 300), () {
                _controller.runJavaScript("window.scrollToHighlight('$hlId');");
              });
            }
            // Scroll to position from global search result
            if (_pendingScrollPercent != null) {
              final pct = _pendingScrollPercent!.clamp(0.0, 1.0);
              _pendingScrollPercent = null;
              Future.delayed(const Duration(milliseconds: 300), () {
                _controller.runJavaScript(
                  'window.scrollTo(0, document.body.scrollHeight * $pct);',
                );
              });
            }
          },
        ),
      );
  }

  /// Make the chapter on screen the one read aloud, unless it already is
  /// (taking over from another chapter or book). Returns false if the
  /// chapter has nothing to read.
  bool _loadTts() {
    _continuePending = false;
    _continueFallback?.cancel();
    if (_ttsOnThisChapter) return true;
    final paragraphs = _readerNotifier!.ttsParagraphs;
    if (paragraphs.isEmpty) return false;
    _lastTtsChapter = _shownChapterIndex;
    context.read<TtsNotifier>().loadChapter(
      _readAloudBook(),
      _shownChapterIndex,
      paragraphs,
    );
    return true;
  }

  /// Open the editor for this note; reload it if it was changed.
  Future<void> _editNote() async {
    if (_ownsTts) await _ttsNotifier?.pause();
    if (!mounted) return;
    final changed = await context.push<bool>(
      '/editor?path=${Uri.encodeComponent(widget.assetPath)}',
    );
    if (changed == true && mounted) {
      await _readerNotifier?.loadBook(widget.assetPath);
    }
  }

  /// Play button: pause, resume, or start reading from what's on screen
  /// (the last spoken sentence if it's still visible, else the first one).
  Future<void> _onPlayPressed() async {
    if (DateTime.now().difference(_fabMovedAt).inMilliseconds < 500) return;
    final tts = context.read<TtsNotifier>();
    final wasLoaded = _ttsOnThisChapter;
    if (wasLoaded && tts.isPlaying) return tts.pause();
    if (wasLoaded && tts.isPaused) return tts.play();
    if (!_loadTts()) return;

    // Prefer the sentence last read here: the current one, or the one this
    // chapter was left on.
    final remembered = _chapterPositions[_shownChapterIndex];
    final current = wasLoaded
        ? tts.currentChunk
        : (remembered?.para == null
              ? null
              : TtsChunk(
                  text: '',
                  paragraphIndex: remembered!.para!,
                  sentenceIndex: remembered.sent,
                ));
    final top = _topBarHeight.round();
    String start = '';
    if (_isPageReady) {
      try {
        final result = await _controller.runJavaScriptReturningResult(
          'window.ttsVisibleStart($top, ${current?.paragraphIndex ?? -1}, '
          '${current?.sentenceIndex ?? -1})',
        );
        start = result.toString().replaceAll('"', '');
      } catch (_) {}
    }
    final parts = start.split(':');
    final para = int.tryParse(parts.first);
    if (para == null) return tts.play();
    return tts.jumpTo(para, parts.length > 1 ? int.tryParse(parts[1]) : null);
  }

  /// Update WebView TTS highlight based on current TTS state and mode
  void _updateTtsHighlight(TtsNotifier ttsNotifier) {
    // Don't try to highlight if page/JS isn't ready yet
    if (!_isPageReady) return;

    final currentChunk = ttsNotifier.currentChunk;
    final currentPara = currentChunk?.paragraphIndex;
    // null in paragraph mode, so the whole paragraph is highlighted
    final sentence = currentChunk?.sentenceIndex;

    // While waiting to carry on in a new chapter there's nothing to show
    // yet, and highlighting its first sentence would scroll the page there.
    if (_ttsOnThisChapter &&
        !_continuePending &&
        (ttsNotifier.isPlaying || ttsNotifier.isPaused)) {
      if (currentPara == null) return;
      final key = '$currentPara-$sentence';
      if (key == _lastHighlightKey) return;
      _lastHighlightKey = key;
      _controller.runJavaScript(
        sentence != null
            ? 'window.ttsHighlightSentence($currentPara, $sentence);'
            : 'window.ttsHighlightParagraph($currentPara);',
      );
    } else if (_lastHighlightKey != null) {
      _lastHighlightKey = null;
      _controller.runJavaScript('window.ttsClearHighlight();');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<ReaderNotifier>();
    // Force UI visible during tutorial so spotlight positions are correct
    final showUI = _showTutorial ? true : notifier.showUI;
    final settings = context.watch<SettingsNotifier>().settings;
    final readerTheme = settings.readerTheme;

    // TTS highlighting is handled by _onTtsStateChanged listener -
    // no context.watch<TtsNotifier>() here to avoid full rebuilds on every chunk change

    return Scaffold(
      backgroundColor: readerTheme.backgroundColor,
      // Wrap FAB in Consumer so only the FAB rebuilds on TTS state changes
      floatingActionButton: notifier.currentChapter != null && !_showSearch
          ? Consumer<TtsNotifier>(
              builder: (context, ttsNotifier, _) {
                return TtsFab(
                  ttsNotifier: ttsNotifier,
                  active: _ttsOnThisChapter,
                  onPressed: _onPlayPressed,
                  // Sit right on top of the bar (or near the bottom edge when
                  // it is hidden). Scaffold already adds the system inset + 16.
                  bottomMargin: showUI ? _barHeight - 16 : 8,
                  isOverlayOpen:
                      _showColorPicker || _showSearch || _showBookComplete,
                  spotlightKey: _fabKey,
                );
              },
            )
          : null,
      body: Stack(
        children: [
          // Main content
          Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // Layer 1: Content with page turn animation
                    SlideTransition(
                      position: _slideAnimation,
                      child: _buildWebView(notifier),
                    ),

                    // Layer 2: Top Bar (Animated) - Uses Reader Theme
                    AnimatedPositioned(
                      duration: Motion.fast,
                      curve: Motion.smoothOut,
                      top: showUI ? 0 : -_topBarHeight,
                      left: 0,
                      right: 0,
                      height: _topBarHeight,
                      child: AppBar(
                        backgroundColor: readerTheme.backgroundColor.withAlpha(
                          (0.95 * 255).round(),
                        ),
                        iconTheme: IconThemeData(color: readerTheme.textColor),
                        leading: IconButton(
                          key: _backButtonKey,
                          icon: Icon(
                            Icons.arrow_back,
                            color: readerTheme.textColor,
                          ),
                          onPressed: () => context.go('/'),
                        ),
                        title: Text(
                          notifier.currentBook?.Title ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: readerTheme.textColor,
                          ),
                        ),
                        centerTitle: true,
                        actions: [
                          // Edit (only for files created in Velum)
                          if (_isNote)
                            IconButton(
                              icon: Icon(
                                Icons.edit_outlined,
                                color: readerTheme.textColor,
                              ),
                              tooltip: 'Edit',
                              onPressed: _editNote,
                            ),
                          // Bookmark current position
                          IconButton(
                            icon: Icon(
                              Icons.bookmark_add_outlined,
                              color: readerTheme.textColor,
                            ),
                            tooltip: 'Add Bookmark',
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              final bookmarks = context
                                  .read<BookmarkNotifier>();
                              final exists = bookmarks.hasBookmarkNear(
                                notifier.currentChapterIndex,
                                _savedScrollPosition,
                              );
                              if (!exists) {
                                bookmarks.addBookmark(
                                  chapterIndex: notifier.currentChapterIndex,
                                  scrollPosition: _savedScrollPosition,
                                  label: notifier.currentChapter?.Title,
                                );
                              }
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    exists
                                        ? 'Already bookmarked here'
                                        : 'Bookmark added',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.search,
                              color: readerTheme.textColor,
                            ),
                            onPressed: _openSearch,
                          ),
                        ],
                      ),
                    ),

                    // Layer 3: Bottom Bar (Animated) - Uses Reader Theme
                    AnimatedPositioned(
                      duration: Motion.fast,
                      curve: Motion.smoothOut,
                      bottom: showUI ? 0 : -_barHeight,
                      left: 0,
                      right: 0,
                      height: _barHeight,
                      child: Container(
                        color: readerTheme.backgroundColor.withAlpha(
                          (0.95 * 255).round(),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            // Reading progress bar
                            if (notifier.currentBook?.Chapters != null &&
                                notifier.currentBook!.Chapters!.isNotEmpty)
                              LinearProgressIndicator(
                                value:
                                    (notifier.currentChapterIndex + 1) /
                                    notifier.currentBook!.Chapters!.length,
                                minHeight: 2,
                                backgroundColor: readerTheme.textColor
                                    .withAlpha(20),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  _accent,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: SizedBox(
                                height: _barHeight - 2,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Highlights/bookmarks icon
                                    IconButton(
                                      key: _highlightsIconKey,
                                      icon: Icon(
                                        Icons.bookmark,
                                        size: 28,
                                        color: readerTheme.textColor,
                                      ),
                                      onPressed: () async {
                                        final readerNotif = context
                                            .read<ReaderNotifier>();
                                        final highlightNotif = context
                                            .read<HighlightNotifier>();
                                        final bmNotif = context
                                            .read<BookmarkNotifier>();
                                        final result =
                                            await showModalBottomSheet<dynamic>(
                                              sheetAnimationStyle: Motion.sheet,
                                              context: context,
                                              backgroundColor:
                                                  Colors.transparent,
                                              builder: (_) => MultiProvider(
                                                providers: [
                                                  ChangeNotifierProvider.value(
                                                    value: readerNotif,
                                                  ),
                                                  ChangeNotifierProvider.value(
                                                    value: highlightNotif,
                                                  ),
                                                  ChangeNotifierProvider.value(
                                                    value: bmNotif,
                                                  ),
                                                ],
                                                child: const HighlightsModal(),
                                              ),
                                            );
                                        if (result != null && mounted) {
                                          if (result is Highlight) {
                                            _navigateToHighlight(result);
                                          } else if (result is Bookmark) {
                                            _navigateToBookmark(result);
                                          }
                                        }
                                      },
                                    ),
                                    // Tappable chapter name + progress → opens Contents sheet
                                    Expanded(
                                      child: GestureDetector(
                                        key: _chapterNameKey,
                                        onTap: () {
                                          final readerNotif = context
                                              .read<ReaderNotifier>();
                                          showModalBottomSheet(
                                            sheetAnimationStyle: Motion.sheet,
                                            context: context,
                                            backgroundColor: Colors.transparent,
                                            // Lets the sheet rise above the
                                            // keyboard for its search field.
                                            isScrollControlled: true,
                                            builder: (_) =>
                                                ChangeNotifierProvider.value(
                                                  value: readerNotif,
                                                  child: const ContentsModal(),
                                                ),
                                          );
                                        },
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              notifier.currentChapter?.Title ??
                                                  '',
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: readerTheme.textColor,
                                              ),
                                            ),
                                            if (notifier
                                                        .currentBook
                                                        ?.Chapters !=
                                                    null &&
                                                notifier
                                                        .currentBook!
                                                        .Chapters!
                                                        .length >
                                                    1)
                                              Text(
                                                'Chapter ${notifier.currentChapterIndex + 1} of ${notifier.currentBook!.Chapters!.length}',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: readerTheme.textColor
                                                      .withAlpha(120),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Settings icon
                                    IconButton(
                                      key: _settingsIconKey,
                                      icon: Icon(
                                        Icons.settings,
                                        size: 28,
                                        color: readerTheme.textColor,
                                      ),
                                      onPressed: () {
                                        showModalBottomSheet(
                                          sheetAnimationStyle: Motion.sheet,
                                          context: context,
                                          backgroundColor: Colors.transparent,
                                          builder: (_) => const SettingsModal(),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // "Back to reading": shown when the user has scrolled
                    // away from the sentence being read aloud.
                    if (_followOff && !_showSearch && !_showColorPicker)
                      Consumer<TtsNotifier>(
                        builder: (context, tts, _) {
                          if (!_ttsOnThisChapter ||
                              (!tts.isPlaying && !tts.isPaused)) {
                            return const SizedBox.shrink();
                          }
                          return AnimatedPositioned(
                            duration: Motion.fast,
                            curve: Motion.smoothOut,
                            bottom: showUI ? 98 : 24,
                            left: 0,
                            right: 0,
                            child: Center(
                              // Rises in like a toast.
                              child: RevealIn(
                                duration: Motion.slow,
                                distance: Motion.distanceBase,
                                blur: Motion.blurSmall,
                                child: Material(
                                  color: _accent,
                                  elevation: 3,
                                  borderRadius: BorderRadius.circular(20),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      _controller.runJavaScript(
                                        'window.ttsFollowNow();',
                                      );
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.record_voice_over,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Back to reading',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              // Keep the bar clear of the system gesture/nav bar.
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),

          // Search: a full page over the reader and its bars. Back closes
          // it rather than leaving the book.
          if (_showSearch)
            Positioned.fill(
              child: PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _closeSearch();
                },
                child: RevealIn(
                  duration: Motion.fast,
                  distance: Motion.distanceBase,
                  blur: 0,
                  child: GlobalSearchOverlay(
                    readerTheme: readerTheme,
                    notifier: notifier,
                    onResultTap: _onSearchResultTap,
                    onClose: _closeSearch,
                  ),
                ),
              ),
            ),

          // Highlight colours: a small pill just below the last selected
          // word, so the selection and its handles stay free to adjust.
          if (_showColorPicker && _selectionRect != null)
            Builder(
              builder: (context) {
                final size = MediaQuery.of(context).size;
                final insets = MediaQuery.of(context).padding;
                const w = ColorPickerBar.width, h = ColorPickerBar.height;
                // Leave room for the selection's end handle under the text.
                var top = _selectionRect!.bottom + 44;
                if (top + h > size.height - insets.bottom - 12) {
                  // No room below: sit above the selection instead.
                  top = _selectionRect!.top - h - 64;
                }
                top = top.clamp(
                  insets.top + 8,
                  size.height - insets.bottom - h - 12,
                );
                final left = (_selectionRect!.right - w / 2).clamp(
                  12.0,
                  size.width - w - 12,
                );
                return Positioned(
                  top: top,
                  left: left,
                  child: PopIn(
                    child: ColorPickerBar(
                      readerTheme: readerTheme,
                      onHighlightSelected: _applyHighlight,
                    ),
                  ),
                );
              },
            ),

          // Book complete overlay
          if (_showBookComplete)
            Positioned.fill(
              child: BookCompleteOverlay(
                readerTheme: readerTheme,
                onBackToLibrary: () => context.go('/'),
                onStayHere: () => setState(() => _showBookComplete = false),
                onStartOver: () {
                  // From the top, not where chapter 1 was once left.
                  _chapterPositions.remove(0);
                  _showChapter(
                    0,
                    scrollNow: () =>
                        _controller.runJavaScript('window.scrollTo(0, 0);'),
                    scrollOnLoad: () {},
                  );
                  setState(() => _showBookComplete = false);
                },
              ),
            ),

          // Tutorial overlay covers the full screen
          if (_showTutorial)
            Positioned.fill(
              child: ReaderTutorialOverlay(
                onDismiss: _dismissTutorial,
                elementKeys: {
                  'back': _backButtonKey,
                  'highlights': _highlightsIconKey,
                  'chapterName': _chapterNameKey,
                  'settings': _settingsIconKey,
                  'fab': _fabKey,
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebView(ReaderNotifier notifier) {
    if (notifier.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (notifier.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 16),
              const Text(
                "This book couldn't be opened",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'The file may be corrupted or in an unsupported format.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => notifier.loadBook(widget.assetPath),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(backgroundColor: _accent),
              ),
            ],
          ),
        ),
      );
    }
    if (notifier.currentChapter == null) {
      return const Center(child: Text('Loading content...'));
    }

    // Use cached processed HTML to avoid expensive re-parsing on rebuilds
    final processedHtml = notifier.getProcessedHtml();

    // Load content if changed
    _loadChapterContent(processedHtml);

    return SafeArea(
      top: false,
      bottom: false,
      child: WebViewWidget(controller: _controller),
    );
  }

  static const _links = MethodChannel('velum/links');

  /// Open a link from the book in the default browser (MainActivity.kt on
  /// Android; apps can't start activities with the `am` command).
  Future<void> _openExternalUrl(String url) async {
    var opened = false;
    try {
      if (Platform.isAndroid) {
        opened = await _links.invokeMethod<bool>('open', {'url': url}) ?? false;
      } else if (Platform.isMacOS) {
        opened = (await Process.run('open', [url])).exitCode == 0;
      }
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Couldn\'t open the link.')));
    }
  }

  void _navigateToHighlight(Highlight highlight) {
    _showChapter(
      highlight.chapterIndex,
      scrollNow: () {
        final safeId = _sanitizeId(highlight.id);
        _controller.runJavaScript("window.scrollToHighlight('$safeId');");
      },
      scrollOnLoad: () => _pendingScrollHighlightId = highlight.id,
    );
  }

  void _navigateToBookmark(Bookmark bookmark) {
    _showChapter(
      bookmark.chapterIndex,
      scrollNow: () {
        final safeScroll = bookmark.scrollPosition.toInt();
        _controller.runJavaScript('window.scrollTo(0, $safeScroll);');
      },
      scrollOnLoad: () => _pendingBookmarkScroll = bookmark.scrollPosition,
    );
  }

  void _restoreHighlights() {
    final highlightNotifier = context.read<HighlightNotifier>();
    final readerNotifier = context.read<ReaderNotifier>();
    final chapterIndex = readerNotifier.currentChapterIndex;
    final highlights = highlightNotifier.highlightsForChapter(chapterIndex);

    if (highlights.isEmpty) return;

    final jsonList = highlights
        .map(
          (h) => {
            'id': h.id,
            'startOffset': h.startOffset,
            'endOffset': h.endOffset,
            'color': highlightCss(h.color),
          },
        )
        .toList();

    final jsonStr = jsonEncode(jsonList).replaceAll("'", "\\'");
    _controller.runJavaScript("window.restoreHighlights('$jsonStr');");
  }

  void _applyHighlight(String colorName) {
    final highlightNotifier = context.read<HighlightNotifier>();
    final notifier = context.read<ReaderNotifier>();
    final chapterIndex = notifier.currentChapterIndex;

    // The same colour the highlight gets when the chapter is loaded again.
    final cssColor = highlightCss(colorName);

    // Add to state/storage
    highlightNotifier
        .addHighlight(
          chapterIndex: chapterIndex,
          text: _selectedText,
          color: colorName,
          startOffset: _selectionStartOffset,
          endOffset: _selectionEndOffset,
        )
        .then((_) {
          // Get the newly added highlight to get its ID
          final highlights = highlightNotifier.highlightsForChapter(
            chapterIndex,
          );
          final latest = highlights.isNotEmpty ? highlights.last : null;
          if (latest != null) {
            final escapedColor = cssColor.replaceAll("'", "\\'");
            final safeId = _sanitizeId(latest.id);
            _controller.runJavaScript(
              "window.applyHighlight($_selectionStartOffset, $_selectionEndOffset, '$escapedColor', '$safeId');",
            );
          }
        });

    setState(() => _showColorPicker = false);

    // Show undo SnackBar
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Highlight added'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            final highlights = highlightNotifier.highlightsForChapter(
              chapterIndex,
            );
            if (highlights.isNotEmpty) {
              final latest = highlights.last;
              highlightNotifier.removeHighlight(latest.id);
            }
          },
        ),
      ),
    );
  }

  bool _isInitialLoad = true;
  ReaderSettings? _lastSettings;
  String? _lastFontCss;

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// @font-face rule for the selected custom font ('' when not using one).
  /// Kept in its own <style> so slider changes don't resend the font data.
  String _buildFontCss(ReaderSettings settings) {
    if (settings.font != ReaderFont.custom ||
        settings.selectedCustomFontId == null) {
      return '';
    }
    final selectedFont = settings.customFonts
        .where((f) => f.id == settings.selectedCustomFontId)
        .firstOrNull;
    if (selectedFont == null) return '';

    if (selectedFont.path != _cachedFontPath || _cachedFontBase64 == null) {
      try {
        final fontFile = File(selectedFont.path);
        // Sync read is fine here — the result is cached after the first read
        _cachedFontBase64 = fontFile.existsSync()
            ? base64Encode(fontFile.readAsBytesSync())
            : null;
        _cachedFontPath = selectedFont.path;
      } catch (e) {
        debugPrint('Error loading custom font: $e');
        _cachedFontBase64 = null;
      }
    }
    if (_cachedFontBase64 == null) return '';
    return "@font-face { font-family: 'CustomFont'; "
        "src: url(data:font/ttf;base64,$_cachedFontBase64) format('truetype'); }";
  }

  /// Build dynamic CSS string from current settings.
  /// Used both for initial HTML and for live JS-based CSS updates.
  String _buildDynamicCss(
    ReaderSettings settings, {
    required bool hasCustomFont,
  }) {
    final themeColorHex = _hex(settings.theme.textColor);
    final bgColorHex = _hex(settings.theme.backgroundColor);
    final linkColor = settings.theme == ReaderTheme.dark
        ? '#64B5F6'
        : '#1976D2';
    final fontFamily = settings.font == ReaderFont.custom
        ? (hasCustomFont ? 'CustomFont' : 'serif')
        : settings.font.fontFamily;

    return '''
    * {
      color: $themeColorHex !important;
      background-color: transparent !important;
      word-wrap: break-word !important;
      overflow-wrap: break-word !important;
    }

    html, body {
      background-color: $bgColorHex !important;
      overscroll-behavior: none !important;
      scroll-behavior: smooth !important;
    }

    html {
      -webkit-overflow-scrolling: touch !important;
      /* Keep what is scrolled into view (the spoken sentence, a highlight)
         clear of the top and bottom bars. */
      scroll-padding-top: ${(_topBarHeight + 8).toInt()}px !important;
      scroll-padding-bottom: ${(_barHeight + 8).toInt()}px !important;
    }

    body {
      font-family: '$fontFamily', serif !important;
      font-size: ${settings.fontSize.toInt()}px !important;
      line-height: ${settings.lineHeight} !important;
      text-align: ${settings.textAlignment.cssValue} !important;
      padding: ${(_topBarHeight + 8).toInt()}px ${settings.horizontalMargin.toInt()}px 80px !important;
      margin: 0 !important;
      min-height: 100vh !important;
      touch-action: pan-y !important;
      -webkit-overflow-scrolling: touch !important;
      word-wrap: break-word !important;
      overflow-wrap: break-word !important;
      hyphens: auto !important;
      -webkit-hyphens: auto !important;
      transform: translateZ(0) !important;
    }

    a { color: $linkColor !important; }

    img {
      max-width: 100% !important;
      height: auto !important;
      will-change: transform !important;
    }

    p, div, span, li, td, th, h1, h2, h3, h4, h5, h6 {
      word-wrap: break-word !important;
      overflow-wrap: break-word !important;
      max-width: 100% !important;
    }

    p, [data-para], .tts-para {
      margin-top: 0 !important;
      margin-bottom: ${settings.paragraphSpacing}em !important;
      text-indent: 0 !important;
    }

    /* TTS Highlighting Styles */
    /* The highlight eases from one sentence to the next. */
    .tts-para, .tts-sent {
      transition: background-color 150ms ease-in-out,
        box-shadow 150ms ease-in-out;
    }
    .tts-highlight {
      background-color: rgba(91, 61, 227, 0.22) !important;
      box-shadow: 0 0 0 2px rgba(91, 61, 227, 0.3);
    }
    /* A sentence crossing formatting is several spans; an outline on each
       would show seams between them. */
    .tts-sent.tts-highlight {
      box-shadow: none;
    }

    /* User highlight styles */
    .user-highlight {
      color: inherit !important;
      border-radius: 2px;
      padding: 1px 0;
      animation: velum-mark 250ms cubic-bezier(0.22, 1, 0.36, 1);
    }
    @keyframes velum-mark {
      from { background-color: transparent; }
    }
    @media (prefers-reduced-motion: reduce) {
      .tts-para, .tts-sent { transition: none; }
      .user-highlight { animation: none; }
    }
    ''';
  }

  static String _jsString(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n');

  /// Update WebView CSS dynamically via JavaScript without reloading the page.
  /// Called when only settings change (e.g. slider drags for font size, line height).
  void _updateCssViaJs(ReaderSettings settings) {
    final fontCss = _buildFontCss(settings);
    if (fontCss != _lastFontCss) {
      _lastFontCss = fontCss;
      _controller.runJavaScript(
        "document.getElementById('velum-font').textContent = '${_jsString(fontCss)}';",
      );
    }
    final css = _buildDynamicCss(settings, hasCustomFont: fontCss.isNotEmpty);
    _controller.runJavaScript(
      "document.getElementById('velum-css').textContent = '${_jsString(css)}';",
    );
  }

  /// How far a sideways swipe must go to change chapter, from Settings.
  void _sendSwipeDistance(ReaderSettings settings) {
    // Skipped if the page's script hasn't loaded yet; it's sent again then.
    _controller.runJavaScript(
      'window.setSwipeDistance && '
      'window.setSwipeDistance(${settings.chapterSwipeDistance});',
    );
  }

  void _loadChapterContent(String? htmlContent) {
    final settings = context.read<SettingsNotifier>().settings;

    if (htmlContent == null) return;

    // Only reload if content OR settings actually changed
    final contentSame = htmlContent == _lastHtmlContent;
    final settingsSame = settings == _lastSettings;

    if (contentSame && settingsSame) {
      // Nothing changed - don't reload (prevents glitch on UI toggle)
      return;
    }

    _lastSettings = settings;

    // If same chapter content but settings changed - update CSS live via JS
    if (contentSame && !settingsSame) {
      _updateCssViaJs(settings);
      _sendSwipeDistance(settings);
      return;
    }

    // New chapter content — full reload needed
    _lastHtmlContent = htmlContent;

    if (_isInitialLoad) {
      // First load - try to restore saved position
      final savedScroll = context.read<ReaderNotifier>().getSavedScrollPosition(
        widget.assetPath,
      );
      if (savedScroll > 0) {
        _savedScrollPosition = savedScroll;
        _shouldRestoreScroll = true;
      }
      _isInitialLoad = false;
    } else {
      // Navigation
      _savedScrollPosition = _openingScroll(
        context.read<ReaderNotifier>().currentChapterIndex,
      );
      _pendingBookmarkScroll = null;
      _shouldRestoreScroll = _savedScrollPosition > 0;
    }

    _isPageReady = false;

    final fontCss = _buildFontCss(settings);
    _lastFontCss = fontCss;
    final dynamicCss = _buildDynamicCss(
      settings,
      hasCustomFont: fontCss.isNotEmpty,
    );

    final combinedHtml =
        '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Merriweather:wght@300;400;700&family=Inter:wght@300;400;600&family=Roboto+Mono&display=swap');
  </style>
  <style id="velum-font">$fontCss</style>
  <style id="velum-css">
    $dynamicCss
  </style>
</head>
<body>
  $htmlContent
</body>
</html>
''';

    // loadHtmlString has no URL length cap; data: URLs are refused by the
    // WebView above 2 MB, which blanked chapters with embedded images.
    _controller.loadHtmlString(combinedHtml);
  }
}
