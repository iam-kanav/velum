import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/reader_notifier.dart';
import '../widgets/reader_tutorial_overlay.dart';
import 'package:velum/features/settings/data/models/reader_settings.dart';
import 'package:velum/features/settings/presentation/providers/settings_notifier.dart';
import 'package:velum/features/settings/presentation/widgets/settings_modal.dart';
import 'package:velum/features/tts/data/models/tts_chunk.dart';
import 'package:velum/features/tts/data/models/tts_settings.dart';
import 'package:velum/features/tts/presentation/providers/tts_notifier.dart';
import 'package:velum/features/tts/data/services/velum_audio_handler.dart';
import 'package:velum/core/widgets/banner_ad_widget.dart';
import 'package:velum/core/providers/ad_notifier.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/highlight.dart';
import '../../data/models/bookmark.dart';
import '../providers/highlight_notifier.dart';
import '../providers/bookmark_notifier.dart';
import '../widgets/contents_modal.dart';
import '../widgets/highlights_modal.dart';

import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:velum/features/reader/presentation/widgets/color_picker_bar.dart';
import 'package:velum/features/reader/presentation/widgets/global_search_overlay.dart';
import 'package:velum/features/reader/presentation/widgets/book_complete_overlay.dart';
import 'package:velum/features/reader/presentation/widgets/tts_fab.dart';
import 'package:velum/core/theme/app_colors.dart';
import 'package:velum/features/notes/data/note_service.dart';

const Color _accent = AppColors.accent;

/// Reader bottom bar (progress line + controls row).
const double _barHeight = 96;

/// "Hide ads" link (30) + banner (50) below the bottom bar.
const double _adAreaHeight = 80;

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
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  double? _pendingScrollPercent;

  // Page turn animation
  late AnimationController _pageAnimController;
  late Animation<Offset> _slideAnimation;

  // Text selection / highlight color picker
  bool _showColorPicker = false;
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

      // Set up TTS callbacks and listener for highlight updates
      _ttsNotifier = context.read<TtsNotifier>();
      _ttsNotifier!.addListener(_onTtsStateChanged);

      // Auto-continue to next chapter when TTS finishes
      _ttsNotifier!.onChapterComplete = () {
        final readerNotifier = context.read<ReaderNotifier>();

        // Attempt to advance — nextChapter() is a no-op on the last chapter.
        final chapterBefore = readerNotifier.currentChapter;
        // Listening carries on into the next chapter from its beginning.
        _chapterPositions.remove(readerNotifier.currentChapterIndex + 1);
        readerNotifier.nextChapter();
        final chapterAfter = readerNotifier.currentChapter;

        if (chapterAfter == chapterBefore) {
          // Chapter didn't change → we were on the last chapter.
          _ttsNotifier!.stop();
          if (mounted && !_isNote) setState(() => _showBookComplete = true);
          return;
        }

        // Successfully moved to next chapter — animate and continue playing.
        _animatePageTurn(-1);
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            if (_loadTts()) _ttsNotifier!.play();
          }
        });
      };
    });
  }

  @override
  void dispose() {
    // Save reading position when exiting
    _readerNotifier?.saveReadingPosition(_savedScrollPosition);
    if (_shownChapter != null) _rememberChapter(_shownChapterIndex);

    WidgetsBinding.instance.removeObserver(this);
    _readerNotifier?.removeListener(_onReaderChanged);
    _highlightNotifier?.removeListener(_onHighlightChanged);
    _ttsNotifier?.removeListener(_onTtsStateChanged);
    _ttsNotifier?.onChapterComplete = null;
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageAnimController.dispose();
    super.dispose();
  }

  Object? _shownChapter;
  int _shownChapterIndex = 0;

  /// Where the reader was in each chapter of this book: scroll offset and
  /// the last read-aloud sentence, so returning to a chapter (swipe, contents)
  /// picks up exactly there. Persisted per book.
  final Map<int, ({double scroll, int? para, int? sent})> _chapterPositions = {};
  double? _pendingBookmarkScroll;
  late final SharedPreferences _prefs;

  String get _chapterPositionsKey =>
      'chapter_positions_${widget.assetPath.hashCode}';

  void _loadChapterPositions() {
    final raw = _prefs.getString(_chapterPositionsKey);
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
    _prefs.setString(
      _chapterPositionsKey,
      jsonEncode({
        for (final e in _chapterPositions.entries)
          '${e.key}': [e.value.scroll, e.value.para, e.value.sent],
      }),
    );
  }

  /// Remember the chapter being left: scroll offset and read-aloud position.
  void _rememberChapter(int index) {
    final chunk = _ttsNotifier?.currentChunk;
    final hasTts = (_ttsNotifier?.chunks.isNotEmpty ?? false) &&
        _ttsNotifier!.state != TtsState.idle;
    final previous = _chapterPositions[index];
    _chapterPositions[index] = (
      scroll: _savedScrollPosition,
      para: hasTts ? chunk?.paragraphIndex : previous?.para,
      sent: hasTts ? chunk?.sentenceIndex : previous?.sent,
    );
    _saveChapterPositions();
  }
  bool? _lastShowUI;

  /// When the bars hide, the Play button slides down onto where the settings
  /// gear was; taps landing during that move were meant for the gear.
  DateTime _fabMovedAt = DateTime(0);

  /// Read-aloud belongs to the chapter it was started in, so any chapter
  /// change (swipe, contents, search, highlights, bookmarks, start over)
  /// stops it. Otherwise the old chapter's positions get highlighted on the
  /// new page. Auto-continue reloads and restarts it after the change.
  void _onReaderChanged() {
    final showUI = _readerNotifier?.showUI;
    if (showUI != _lastShowUI) {
      _lastShowUI = showUI;
      _fabMovedAt = DateTime.now();
    }
    final chapter = _readerNotifier?.currentChapter;
    if (identical(chapter, _shownChapter)) return;
    if (_shownChapter != null) _rememberChapter(_shownChapterIndex);
    _shownChapter = chapter;
    _shownChapterIndex = _readerNotifier?.currentChapterIndex ?? 0;
    final tts = _ttsNotifier;
    if (tts != null && tts.chunks.isNotEmpty) {
      tts.stop();
      tts.clearContent();
    }
  }

  /// Listener for TTS state changes - updates WebView highlight via JS
  /// without triggering a full widget rebuild.
  void _onTtsStateChanged() {
    if (_ttsNotifier != null) {
      _updateTtsHighlight(_ttsNotifier!);
      // Reset ad-free inactivity timer when audio is playing
      if (_ttsNotifier!.isPlaying) {
        context.read<AdNotifier>().onAudioPlaying();
      }
    }
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

  bool _wasPaused = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
      // Save scroll position for persistence
      _controller.runJavaScript(
        'ReaderChannel.postMessage("scroll:" + window.scrollY);',
      );
      _readerNotifier?.saveReadingPosition(_savedScrollPosition);
    } else if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      // WebView preserves its own content and scroll position on warm resume.
      // No reload needed — just let it stay where it was.
    }
  }

  /// Check if the user has seen the reader tutorial before.
  /// Uses provided SharedPreferences instead of re-fetching the singleton.
  void _checkTutorialFlag() {
    final prefs = context.read<SharedPreferences>();
    final hasSeen = prefs.getBool('has_seen_reader_tutorial') ?? false;
    if (!hasSeen) {
      setState(() => _showTutorial = true);
    }
  }

  /// Dismiss tutorial and persist the flag
  void _dismissTutorial() async {
    final prefs = context.read<SharedPreferences>();
    await prefs.setBool('has_seen_reader_tutorial', true);
    if (mounted) {
      setState(() => _showTutorial = false);
    }
  }

  // ── Search ──────────────────────────────────────────────────────────

  void _openSearch() {
    setState(() => _showSearch = true);
    // Delay focus so the widget is built first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _showSearch = false;
    });
  }

  void _onSearchResultTap(GlobalSearchResult result) {
    final notifier = context.read<ReaderNotifier>();
    final chapters = notifier.currentBook?.Chapters;
    if (chapters == null) return;

    _closeSearch();

    final sameChapter = result.chapterIndex == notifier.currentChapterIndex;
    if (sameChapter) {
      // Scroll to position in current chapter
      final safePct = result.positionPercent.clamp(0.0, 1.0);
      _controller.runJavaScript(
        'window.scrollTo(0, document.body.scrollHeight * $safePct);',
      );
    } else {
      // Jump to the target chapter, scroll after it loads
      _pendingScrollPercent = result.positionPercent;
      if (result.chapterIndex < chapters.length) {
        notifier.jumpToChapter(chapters[result.chapterIndex]);
      }
    }
  }

  void _showRemoveAdsDialog(ReaderTheme readerTheme) {
    final adNotifier = context.read<AdNotifier>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: readerTheme.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Support the Developer',
          style: TextStyle(
            color: readerTheme.textColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Watch a short ad to hide banner ads for this session. '
          'This helps support me as an independent developer and keeps Velum free!',
          style: TextStyle(
            color: readerTheme.textColor.withAlpha(180),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Not now',
              style: TextStyle(color: readerTheme.textColor.withAlpha(120)),
            ),
          ),
          FilledButton.icon(
            onPressed: adNotifier.isRewardedAdReady
                ? () async {
                    Navigator.of(ctx).pop();
                    await adNotifier.showRewardedAd();
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: Text(
              adNotifier.isRewardedAdReady ? 'Watch Ad' : 'Loading...',
            ),
          ),
        ],
      ),
    );
  }

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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'ReaderChannel',
        onMessageReceived: (JavaScriptMessage message) {
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
              if (notifier.currentChapter == chapterBefore) {
                // Already on the last chapter — show completion screen
                setState(() => _showBookComplete = true);
              } else {
                _animatePageTurn(-1);
              }
              break;
            case 'prev':
              if (_isNote) break;
              HapticFeedback.mediumImpact();
              _animatePageTurn(1); // Slide right
              notifier.previousChapter();
              break;
            default:
              // Read-aloud follow mode toggled by the user scrolling away/back
              if (message.message.startsWith('tts-follow:')) {
                final off = message.message == 'tts-follow:off';
                if (off != _followOff) setState(() => _followOff = off);
              }
              // Handle external URL opening
              else if (message.message.startsWith('open-url:')) {
                final url = message.message.substring(9);
                _openExternalUrl(url);
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
                  if (text.isNotEmpty) {
                    setState(() {
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
              _controller.runJavaScript(
                'window.scrollTo(0, $safeScroll);',
              );
              _shouldRestoreScroll = false;
            }
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

  /// Load the current chapter into the TTS player if it isn't already, and
  /// show the book/chapter on the lock screen. Returns false if the chapter
  /// has nothing to read.
  bool _loadTts() {
    final tts = context.read<TtsNotifier>();
    final reader = context.read<ReaderNotifier>();
    if (tts.chunks.isEmpty) {
      final paragraphs = reader.ttsParagraphs;
      if (paragraphs.isEmpty) return false;
      tts.loadContent(paragraphs);
    }
    context.read<VelumAudioHandler>().setMediaMetadata(
      bookTitle: reader.currentBook?.Title ?? 'Unknown Book',
      chapterTitle: reader.currentChapter?.Title ?? 'Unknown Chapter',
    );
    return true;
  }

  /// Open the editor for this note; reload it if it was changed.
  Future<void> _editNote() async {
    await _ttsNotifier?.pause();
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
    if (tts.isPlaying) return tts.pause();
    if (tts.isPaused) return tts.play();
    final wasLoaded = tts.chunks.isNotEmpty;
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
    final top = (MediaQuery.of(context).padding.top + kToolbarHeight).round();
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

    if (ttsNotifier.isPlaying || ttsNotifier.isPaused) {
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
    final adShown = context.select<AdNotifier, bool>((a) => a.showBanner);
    final adSpace = adShown ? _adAreaHeight : 0.0;
    final settings = context.watch<SettingsNotifier>().settings;
    final readerTheme = settings.readerTheme;

    // TTS highlighting is handled by _onTtsStateChanged listener -
    // no context.watch<TtsNotifier>() here to avoid full rebuilds on every chunk change

    return Scaffold(
      backgroundColor: readerTheme.backgroundColor,
      extendBodyBehindAppBar: true,
      // Wrap FAB in Consumer so only the FAB rebuilds on TTS state changes
      floatingActionButton: notifier.currentChapter != null
          ? Consumer<TtsNotifier>(
              builder: (context, ttsNotifier, _) {
                return TtsFab(
                  ttsNotifier: ttsNotifier,
                  onPressed: _onPlayPressed,
                  // Sit right on top of the bar (or the ad area when the bar
                  // is hidden). Scaffold already adds the system inset + 16.
                  bottomMargin: showUI
                      ? _barHeight + adSpace - 16
                      : adSpace + 8,
                  isOverlayOpen:
                      _showColorPicker || _showSearch || _showBookComplete,
                  readerTheme: readerTheme,
                  spotlightKey: _fabKey,
                );
              },
            )
          : null,
      body: Stack(
        children: [
          // Main content + ad layout
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
                      duration: const Duration(milliseconds: 200),
                      top: showUI
                          ? 0
                          : -kToolbarHeight -
                                MediaQuery.of(context).padding.top,
                      left: 0,
                      right: 0,
                      height:
                          kToolbarHeight + MediaQuery.of(context).padding.top,
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
                              context.read<BookmarkNotifier>().addBookmark(
                                chapterIndex: notifier.currentChapterIndex,
                                scrollPosition: _savedScrollPosition,
                                label: notifier.currentChapter?.Title,
                              );
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Bookmark added'),
                                  duration: Duration(seconds: 2),
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
                      duration: const Duration(milliseconds: 200),
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
                                value: (notifier.currentChapterIndex + 1) /
                                    notifier.currentBook!.Chapters!.length,
                                minHeight: 2,
                                backgroundColor: readerTheme.textColor.withAlpha(20),
                                valueColor: const AlwaysStoppedAnimation<Color>(_accent),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: SizedBox(
                                height: _barHeight - 2,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                        final readerNotif = context.read<ReaderNotifier>();
                                        final highlightNotif = context.read<HighlightNotifier>();
                                        final bmNotif = context.read<BookmarkNotifier>();
                                        final result =
                                            await showModalBottomSheet<dynamic>(
                                              context: context,
                                              backgroundColor: Colors.transparent,
                                              builder: (_) => MultiProvider(
                                                providers: [
                                                  ChangeNotifierProvider.value(value: readerNotif),
                                                  ChangeNotifierProvider.value(value: highlightNotif),
                                                  ChangeNotifierProvider.value(value: bmNotif),
                                                ],
                                                child: const HighlightsModal(),
                                              ),
                                            );
                                        if (result != null && mounted) {
                                          if (result is Highlight) {
                                            _navigateToHighlight(result, notifier);
                                          } else if (result is Bookmark) {
                                            _navigateToBookmark(result, notifier);
                                          }
                                        }
                                      },
                                    ),
                                    // Tappable chapter name + progress → opens Contents sheet
                                    Expanded(
                                      child: GestureDetector(
                                        key: _chapterNameKey,
                                        onTap: () {
                                          final readerNotif = context.read<ReaderNotifier>();
                                          showModalBottomSheet(
                                            context: context,
                                            backgroundColor: Colors.transparent,
                                            builder: (_) => ChangeNotifierProvider.value(
                                              value: readerNotif,
                                              child: const ContentsModal(),
                                            ),
                                          );
                                        },
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              notifier.currentChapter?.Title ?? '',
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: readerTheme.textColor,
                                              ),
                                            ),
                                            if (notifier.currentBook?.Chapters != null &&
                                                notifier.currentBook!.Chapters!.length > 1)
                                              Text(
                                                'Chapter ${notifier.currentChapterIndex + 1} of ${notifier.currentBook!.Chapters!.length}',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: readerTheme.textColor.withAlpha(120),
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
                                        final ttsNotif = context.read<TtsNotifier>();
                                        showModalBottomSheet(
                                          context: context,
                                          backgroundColor: Colors.transparent,
                                          builder: (_) => ChangeNotifierProvider.value(
                                            value: ttsNotif,
                                            child: const SettingsModal(),
                                          ),
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
                          if (!tts.isPlaying && !tts.isPaused) {
                            return const SizedBox.shrink();
                          }
                          return AnimatedPositioned(
                            duration: const Duration(milliseconds: 200),
                            bottom: showUI ? 98 : 24,
                            left: 0,
                            right: 0,
                            child: Center(
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
                          );
                        },
                      ),
                  ],
                ),
              ),
              if (adShown)
                SizedBox(
                  height: _adAreaHeight,
                  child: Column(
                    children: [
                      SizedBox(
                        height: _adAreaHeight - 50,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showRemoveAdsDialog(readerTheme),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.favorite_border,
                                size: 14,
                                color: readerTheme.textColor.withAlpha(100),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Hide ads for this session',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: readerTheme.textColor.withAlpha(100),
                                  decoration: TextDecoration.underline,
                                  decorationColor: readerTheme.textColor
                                      .withAlpha(60),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const BannerAdWidget(),
                    ],
                  ),
                ),
              // Keep the bar and ad clear of the system gesture/nav bar.
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),

          // Global search popup
          if (_showSearch)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 60,
              child: GlobalSearchOverlay(
                readerTheme: readerTheme,
                notifier: notifier,
                onResultTap: _onSearchResultTap,
                onClose: _closeSearch,
              ),
            ),

          // Color picker overlay for highlighting
          if (_showColorPicker)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
              left: 0,
              right: 0,
              child: Stack(
                children: [
                  ColorPickerBar(
                    readerTheme: readerTheme,
                    notifier: notifier,
                    selectedText: _selectedText,
                    onHighlightSelected: _applyHighlight,
                  ),
                  Positioned(
                    right: 16,
                    top: 10,
                    child: GestureDetector(
                      onTap: () {
                        _controller.runJavaScript(
                          'window.getSelection().removeAllRanges();',
                        );
                        setState(() => _showColorPicker = false);
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: readerTheme.textColor.withAlpha(20),
                        ),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: readerTheme.textColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Book complete overlay
          if (_showBookComplete)
            Positioned.fill(
              child: BookCompleteOverlay(
                readerTheme: readerTheme,
                onBackToLibrary: () => context.go('/'),
                onStayHere: () => setState(() => _showBookComplete = false),
                onStartOver: () {
                  final chapters = notifier.currentBook?.Chapters;
                  if (chapters != null && chapters.isNotEmpty) {
                    notifier.jumpToChapter(chapters.first);
                  }
                  setState(() => _showBookComplete = false);
                },
              ),
            ),

          // Tutorial overlay covers the full screen including the ad area
          if (_showTutorial)
            Positioned.fill(
              child: ReaderTutorialOverlay(
                onDismiss: _dismissTutorial,
                bottomOffset: 50,
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
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
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

  /// Open a URL in the device's external browser via Android Intent.
  void _openExternalUrl(String url) {
    if (Platform.isAndroid) {
      Process.run('am', ['start', '-a', 'android.intent.action.VIEW', '-d', url]);
    }
    // iOS: use canLaunchUrl / system channel if needed in the future
  }

  void _navigateToHighlight(Highlight highlight, ReaderNotifier notifier) {
    final chapters = notifier.currentBook?.Chapters;
    if (chapters == null) return;

    final sameChapter = highlight.chapterIndex == notifier.currentChapterIndex;

    if (sameChapter) {
      // Already on the right chapter — just scroll
      final safeId = _sanitizeId(highlight.id);
      _controller.runJavaScript("window.scrollToHighlight('$safeId');");
    } else {
      // Different chapter — jump there, then scroll after page loads
      _pendingScrollHighlightId = highlight.id;
      if (highlight.chapterIndex < chapters.length) {
        notifier.jumpToChapter(chapters[highlight.chapterIndex]);
      }
    }
  }

  void _navigateToBookmark(Bookmark bookmark, ReaderNotifier notifier) {
    final chapters = notifier.currentBook?.Chapters;
    if (chapters == null) return;

    final sameChapter = bookmark.chapterIndex == notifier.currentChapterIndex;
    final safeScroll = bookmark.scrollPosition.toInt();

    if (sameChapter) {
      _controller.runJavaScript('window.scrollTo(0, $safeScroll);');
    } else {
      // Jump to the chapter, then scroll after page loads
      _pendingBookmarkScroll = bookmark.scrollPosition;
      if (bookmark.chapterIndex < chapters.length) {
        notifier.jumpToChapter(chapters[bookmark.chapterIndex]);
      }
    }
  }

  void _restoreHighlights() {
    final highlightNotifier = context.read<HighlightNotifier>();
    final readerNotifier = context.read<ReaderNotifier>();
    final chapterIndex = readerNotifier.currentChapterIndex;
    final highlights = highlightNotifier.highlightsForChapter(chapterIndex);

    if (highlights.isEmpty) return;

    // Build JSON with CSS colors for each highlight
    const colorMap = <String, String>{
      'yellow': 'rgba(255, 241, 118, 0.4)',
      'green': 'rgba(129, 199, 132, 0.4)',
      'blue': 'rgba(100, 181, 246, 0.4)',
      'pink': 'rgba(244, 143, 177, 0.4)',
      'orange': 'rgba(255, 183, 77, 0.4)',
    };

    final jsonList = highlights
        .map(
          (h) => {
            'id': h.id,
            'startOffset': h.startOffset,
            'endOffset': h.endOffset,
            'color': colorMap[h.color] ?? 'rgba(255, 241, 118, 0.4)',
          },
        )
        .toList();

    final jsonStr = jsonEncode(jsonList).replaceAll("'", "\\'");
    _controller.runJavaScript("window.restoreHighlights('$jsonStr');");
  }

  void _applyHighlight(String colorName, Color color) {
    final highlightNotifier = context.read<HighlightNotifier>();
    final notifier = context.read<ReaderNotifier>();
    final chapterIndex = notifier.currentChapterIndex;

    // Convert color to CSS rgba
    final cssColor =
        'rgba(${(color.r * 255).round()}, ${(color.g * 255).round()}, ${(color.b * 255).round()}, 0.4)';

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
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Highlight added'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              final highlights = highlightNotifier.highlightsForChapter(chapterIndex);
              if (highlights.isNotEmpty) {
                final latest = highlights.last;
                highlightNotifier.removeHighlight(latest.id);
              }
            },
          ),
        ),
      );
    }
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
  String _buildDynamicCss(ReaderSettings settings, {required bool hasCustomFont}) {
    final themeColorHex = _hex(settings.theme.textColor);
    final bgColorHex = _hex(settings.theme.backgroundColor);
    final linkColor = settings.theme == ReaderTheme.dark ? '#64B5F6' : '#1976D2';
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
    }

    body {
      font-family: '$fontFamily', serif !important;
      font-size: ${settings.fontSize.toInt()}px !important;
      line-height: ${settings.lineHeight} !important;
      text-align: ${settings.textAlignment.cssValue} !important;
      padding: ${(MediaQuery.of(context).padding.top + kToolbarHeight + 8).toInt()}px ${settings.horizontalMargin.toInt()}px 80px !important;
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
    .tts-highlight {
      background-color: rgba(91, 61, 227, 0.22) !important;
      box-shadow: 0 0 0 2px rgba(91, 61, 227, 0.3);
    }
    /* A sentence crossing formatting is several spans; an outline on each
       would show seams between them. */
    .tts-sent.tts-highlight {
      box-shadow: none;
    }

    /* Search highlight styles */
    .search-match {
      background-color: rgba(255, 235, 59, 0.4) !important;
      color: inherit !important;
      border-radius: 2px;
    }
    .search-current {
      background-color: rgba(255, 152, 0, 0.6) !important;
      box-shadow: 0 0 0 2px rgba(255, 152, 0, 0.4);
    }

    /* User highlight styles */
    .user-highlight {
      color: inherit !important;
      border-radius: 2px;
      padding: 1px 0;
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
      "document.getElementById('velum-css').textContent = '${_jsString(css)}';"
      "document.body.style.cssText = 'color: ${_hex(settings.theme.textColor)} !important; "
      "background-color: ${_hex(settings.theme.backgroundColor)} !important;';",
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
      return;
    }

    // New chapter content — full reload needed
    _lastHtmlContent = htmlContent;

    if (_isInitialLoad) {
      // First load - try to restore saved position
      final savedScroll = context
          .read<ReaderNotifier>()
          .getSavedScrollPosition(widget.assetPath);
      if (savedScroll > 0) {
        _savedScrollPosition = savedScroll;
        _shouldRestoreScroll = true;
      }
      _isInitialLoad = false;
    } else {
      // Navigation: a bookmark's spot, else where the reader left this
      // chapter, else the top. Search/highlight jumps scroll on their own.
      final remembered =
          _chapterPositions[context.read<ReaderNotifier>().currentChapterIndex];
      final target = _pendingBookmarkScroll ??
          (_pendingScrollPercent == null && _pendingScrollHighlightId == null
              ? remembered?.scroll
              : null);
      _pendingBookmarkScroll = null;
      _savedScrollPosition = target ?? 0;
      _shouldRestoreScroll = _savedScrollPosition > 0;
    }

    _isPageReady = false;

    final fontCss = _buildFontCss(settings);
    _lastFontCss = fontCss;
    final dynamicCss = _buildDynamicCss(settings, hasCustomFont: fontCss.isNotEmpty);

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
