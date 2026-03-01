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
import 'package:velum/features/tts/presentation/providers/tts_notifier.dart';
import 'package:velum/features/tts/data/models/tts_settings.dart';
import 'package:velum/features/tts/data/services/velum_audio_handler.dart';
import 'package:velum/core/widgets/banner_ad_widget.dart';
import 'package:velum/core/providers/ad_notifier.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/highlight.dart';
import '../providers/highlight_notifier.dart';
import '../widgets/contents_modal.dart';
import '../widgets/highlights_modal.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:velum/features/reader/presentation/widgets/color_picker_bar.dart';
import 'package:velum/features/reader/presentation/widgets/global_search_overlay.dart';
import 'package:velum/features/reader/presentation/widgets/book_complete_overlay.dart';
import 'package:velum/features/reader/presentation/widgets/tts_fab.dart';

const Color _accentGreen = Color(0xFF4CAF50);

class ReaderScreen extends StatefulWidget {
  final String assetPath;

  const ReaderScreen({super.key, required this.assetPath});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final WebViewController _controller;
  String? _lastHtmlContent;
  double _savedScrollPosition = 0;
  bool _shouldRestoreScroll = false;
  String? _lastHighlightKey; // Track current TTS highlight position
  bool _isPageReady = false; // Track if JS is injected and ready
  bool _showTutorial = false; // First-time tutorial overlay
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

  @override
  void initState() {
    super.initState();
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
      _readerNotifier = context.read<ReaderNotifier>();
      _readerNotifier?.loadBook(widget.assetPath);

      // Load highlights for this book and listen for removals
      _highlightNotifier = context.read<HighlightNotifier>();
      _highlightNotifier!.loadHighlights(widget.assetPath);
      _highlightNotifier!.addListener(_onHighlightChanged);

      // Set up TTS callbacks and listener for highlight updates
      _ttsNotifier = context.read<TtsNotifier>();
      _ttsNotifier!.addListener(_onTtsStateChanged);

      // Auto-continue to next chapter when TTS finishes
      _ttsNotifier!.onChapterComplete = () {
        final readerNotifier = context.read<ReaderNotifier>();

        // Attempt to advance — nextChapter() is a no-op on the last chapter.
        final chapterBefore = readerNotifier.currentChapter;
        readerNotifier.nextChapter();
        final chapterAfter = readerNotifier.currentChapter;

        if (chapterAfter == chapterBefore) {
          // Chapter didn't change → we were on the last chapter.
          _ttsNotifier!.stop();
          if (mounted) setState(() => _showBookComplete = true);
          return;
        }

        // Successfully moved to next chapter — animate and continue playing.
        _animatePageTurn(-1);
        _ttsNotifier!.clearContent();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            final text = readerNotifier.extractStructuredText();
            if (text.isNotEmpty) {
              _ttsNotifier!.loadContent(text);

              // Update notification metadata for new chapter
              context.read<VelumAudioHandler>().setMediaMetadata(
                bookTitle: readerNotifier.currentBook?.Title ?? 'Unknown Book',
                chapterTitle:
                    readerNotifier.currentChapter?.Title ?? 'Unknown Chapter',
              );

              _ttsNotifier!.play();
            }
          }
        });
      };
    });
  }

  @override
  void dispose() {
    // Save reading position when exiting
    _readerNotifier?.saveReadingPosition(_savedScrollPosition);

    WidgetsBinding.instance.removeObserver(this);
    _highlightNotifier?.removeListener(_onHighlightChanged);
    _ttsNotifier?.removeListener(_onTtsStateChanged);
    _ttsNotifier?.onChapterComplete = null;
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageAnimController.dispose();
    super.dispose();
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

  /// Listener for highlight changes — removes deleted highlights from the WebView.
  void _onHighlightChanged() {
    final removedId = _highlightNotifier?.lastRemovedHighlightId;
    if (removedId != null && _isPageReady) {
      _highlightNotifier!.clearLastRemoved();
      _controller.runJavaScript("window.removeHighlight('$removedId');");
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

  // _buildGlobalSearchOverlay removed

  void _onSearchResultTap(GlobalSearchResult result) {
    final notifier = context.read<ReaderNotifier>();
    final chapters = notifier.currentBook?.Chapters;
    if (chapters == null) return;

    _closeSearch();

    final sameChapter = result.chapterIndex == notifier.currentChapterIndex;
    if (sameChapter) {
      // Scroll to position in current chapter
      _controller.runJavaScript(
        'window.scrollTo(0, document.body.scrollHeight * ${result.positionPercent});',
      );
    } else {
      // Jump to the target chapter, scroll after it loads
      _pendingScrollPercent = result.positionPercent;
      if (result.chapterIndex < chapters.length) {
        context.read<TtsNotifier>().stop();
        context.read<TtsNotifier>().clearContent();
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
              backgroundColor: _accentGreen,
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
              final chapterBefore = notifier.currentChapter;
              notifier.nextChapter();
              if (notifier.currentChapter == chapterBefore) {
                // Already on the last chapter — show completion screen
                setState(() => _showBookComplete = true);
              } else {
                context.read<TtsNotifier>().stop();
                context.read<TtsNotifier>().clearContent();
                _animatePageTurn(-1);
              }
              break;
            case 'prev':
              _animatePageTurn(1); // Slide right
              notifier.previousChapter();
              context.read<TtsNotifier>().stop();
              context.read<TtsNotifier>().clearContent();
              break;
            default:
              // Handle scroll position message
              if (message.message.startsWith('scroll:')) {
                _savedScrollPosition =
                    double.tryParse(message.message.substring(7)) ?? 0;
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
                  final ttsNotifier = context.read<TtsNotifier>();
                  final readerNotifier = context.read<ReaderNotifier>();

                  // Load content if not already loaded
                  if (ttsNotifier.chunks.isEmpty) {
                    final text = readerNotifier.extractStructuredText();
                    if (text.isNotEmpty) {
                      ttsNotifier.loadContent(text);
                    }
                  }

                  // Jump to position and start playing
                  if (sentIndex != null) {
                    ttsNotifier.jumpToSentence(paraIndex, sentIndex);
                  } else {
                    ttsNotifier.jumpToParagraph(paraIndex);
                  }
                }
              }
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            // Load and inject JS from asset
            final jsString = await rootBundle.loadString('assets/js/reader.js');
            _controller.runJavaScript(jsString);

            _isPageReady = true; // JS is now ready
            // Restore saved highlights for current chapter
            _restoreHighlights();
            // Restore scroll position after page loads
            if (_shouldRestoreScroll && _savedScrollPosition > 0) {
              _controller.runJavaScript(
                'window.scrollTo(0, $_savedScrollPosition);',
              );
              _shouldRestoreScroll = false;
            }
            // Scroll to a pending highlight if navigated from highlights modal
            if (_pendingScrollHighlightId != null) {
              final hlId = _pendingScrollHighlightId!;
              _pendingScrollHighlightId = null;
              // Small delay to let restoreHighlights finish rendering
              Future.delayed(const Duration(milliseconds: 300), () {
                _controller.runJavaScript("window.scrollToHighlight('$hlId');");
              });
            }
            // Scroll to position from global search result
            if (_pendingScrollPercent != null) {
              final pct = _pendingScrollPercent!;
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

  // CSS is now baked into HTML in _loadChapterContent - no separate injection needed

  // JS is loaded directly from asset in _initController

  /// Update WebView TTS highlight based on current TTS state and mode
  void _updateTtsHighlight(TtsNotifier ttsNotifier) {
    // Don't try to highlight if page/JS isn't ready yet
    if (!_isPageReady) return;

    final currentChunk = ttsNotifier.currentChunk;
    final currentPara = currentChunk?.paragraphIndex;
    final currentSent = currentChunk?.sentenceIndex;
    final isSentenceMode =
        ttsNotifier.settings.highlightMode == TtsHighlightMode.sentence;

    // Determine what to highlight
    if (ttsNotifier.isPlaying || ttsNotifier.isPaused) {
      if (currentPara != null) {
        // Create a unique key for current position
        final currentKey = isSentenceMode && currentSent != null
            ? '$currentPara-$currentSent'
            : '$currentPara';

        if (currentKey != _lastHighlightKey) {
          _lastHighlightKey = currentKey;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (isSentenceMode && currentSent != null) {
              _controller.runJavaScript(
                'if(window.ttsHighlightSentence) window.ttsHighlightSentence($currentPara, $currentSent);',
              );
            } else {
              _controller.runJavaScript(
                'if(window.ttsHighlightParagraph) window.ttsHighlightParagraph($currentPara);',
              );
            }
          });
        }
      }
    } else {
      // TTS is stopped - clear highlight
      if (_lastHighlightKey != null) {
        _lastHighlightKey = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _controller.runJavaScript(
            'if(window.ttsClearHighlight) window.ttsClearHighlight();',
          );
        });
      }
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
      extendBodyBehindAppBar: true,
      // Wrap FAB in Consumer so only the FAB rebuilds on TTS state changes
      floatingActionButton: notifier.currentChapter != null
          ? Consumer<TtsNotifier>(
              builder: (context, ttsNotifier, _) {
                return KeyedSubtree(
                  key: _fabKey,
                  child: TtsFab(
                    ttsNotifier: ttsNotifier,
                    readerNotifier: notifier,
                    showUI: showUI,
                    isOverlayOpen:
                        _showColorPicker || _showSearch || _showBookComplete,
                    readerTheme: readerTheme,
                  ),
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
                      bottom: showUI ? 0 : -80,
                      left: 0,
                      right: 0,
                      height: 80,
                      child: Container(
                        color: readerTheme.backgroundColor.withAlpha(
                          (0.95 * 255).round(),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Highlights/bookmarks icon
                            IconButton(
                              key: _highlightsIconKey,
                              icon: Icon(
                                Icons.bookmark,
                                color: readerTheme.textColor,
                              ),
                              onPressed: () async {
                                final highlight =
                                    await showModalBottomSheet<Highlight>(
                                      context: context,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => const HighlightsModal(),
                                    );
                                if (highlight != null && mounted) {
                                  _navigateToHighlight(highlight, notifier);
                                }
                              },
                            ),
                            // Tappable chapter name → opens Contents sheet
                            Expanded(
                              child: GestureDetector(
                                key: _chapterNameKey,
                                onTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => const ContentsModal(),
                                  );
                                },
                                child: Text(
                                  notifier.currentChapter?.Title ?? '',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: readerTheme.textColor,
                                  ),
                                ),
                              ),
                            ),
                            // Settings icon
                            IconButton(
                              key: _settingsIconKey,
                              icon: Icon(
                                Icons.settings,
                                color: readerTheme.textColor,
                              ),
                              onPressed: () {
                                showModalBottomSheet(
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
              Consumer<AdNotifier>(
                builder: (context, adNotifier, _) {
                  if (!adNotifier.showBanner) return const SizedBox.shrink();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _showRemoveAdsDialog(readerTheme),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 4),
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
                  );
                },
              ),
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

  // _buildTtsFab, _buildColorPicker, _buildBookCompleteScreen extracted to widgets

  void _navigateToHighlight(Highlight highlight, ReaderNotifier notifier) {
    final chapters = notifier.currentBook?.Chapters;
    if (chapters == null) return;

    final sameChapter = highlight.chapterIndex == notifier.currentChapterIndex;

    if (sameChapter) {
      // Already on the right chapter — just scroll
      _controller.runJavaScript("window.scrollToHighlight('${highlight.id}');");
    } else {
      // Different chapter — jump there, then scroll after page loads
      _pendingScrollHighlightId = highlight.id;
      if (highlight.chapterIndex < chapters.length) {
        notifier.jumpToChapter(chapters[highlight.chapterIndex]);
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
            _controller.runJavaScript(
              "window.applyHighlight($_selectionStartOffset, $_selectionEndOffset, '$escapedColor', '${latest.id}');",
            );
          }
        });

    setState(() => _showColorPicker = false);
  }

  bool _isInitialLoad = true;
  ReaderSettings? _lastSettings;

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

    // If same chapter content but settings changed - preserve scroll
    if (contentSame && !settingsSame) {
      // Save scroll position before reload
      _controller.runJavaScript(
        'ReaderChannel.postMessage("scroll:" + window.scrollY);',
      );
      _shouldRestoreScroll = true;
    } else {
      // New chapter
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
        // Regular navigation - start at top
        _shouldRestoreScroll = false;
        _savedScrollPosition = 0;
      }
    }

    _lastHtmlContent = htmlContent;
    _lastSettings = settings;

    // Compute colors
    final r = (settings.theme.textColor.r * 255.0).round().clamp(0, 255);
    final g = (settings.theme.textColor.g * 255.0).round().clamp(0, 255);
    final b = (settings.theme.textColor.b * 255.0).round().clamp(0, 255);
    final themeColorHex =
        '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';

    final bgR = (settings.theme.backgroundColor.r * 255.0).round().clamp(
      0,
      255,
    );
    final bgG = (settings.theme.backgroundColor.g * 255.0).round().clamp(
      0,
      255,
    );
    final bgB = (settings.theme.backgroundColor.b * 255.0).round().clamp(
      0,
      255,
    );
    final bgColorHex =
        '#${bgR.toRadixString(16).padLeft(2, '0')}${bgG.toRadixString(16).padLeft(2, '0')}${bgB.toRadixString(16).padLeft(2, '0')}';

    final linkColor = settings.theme == ReaderTheme.dark
        ? '#64B5F6'
        : '#1976D2';

    // Prepare Font CSS
    String fontCss = '';
    String fontFamily = settings.font.fontFamily;

    if (settings.font == ReaderFont.custom &&
        settings.selectedCustomFontId != null) {
      try {
        final selectedFont = settings.customFonts.firstWhere(
          (f) => f.id == settings.selectedCustomFontId,
          orElse: () => throw Exception('Font not found'),
        );

        // Cache font bytes to avoid blocking file I/O on every content load
        if (selectedFont.path != _cachedFontPath || _cachedFontBase64 == null) {
          final fontFile = File(selectedFont.path);
          if (fontFile.existsSync()) {
            final fontBytes = fontFile.readAsBytesSync();
            _cachedFontBase64 = base64Encode(fontBytes);
            _cachedFontPath = selectedFont.path;
          }
        }

        if (_cachedFontBase64 != null) {
          fontFamily = 'CustomFont';
          fontCss =
              '''
            @font-face {
              font-family: 'CustomFont';
              src: url(data:font/ttf;base64,$_cachedFontBase64) format('truetype');
            }
          ''';
        }
      } catch (e) {
        debugPrint('Error loading custom font: $e');
        // Fallback to serif if custom font fails
        fontFamily = 'serif';
      }
    }

    debugPrint(
      'Theme: ${settings.theme}, TextColor: $themeColorHex, BgColor: $bgColorHex, Font: $fontFamily',
    );

    // Ultra-simple HTML with inline styles on body for maximum compatibility
    final combinedHtml =
        '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Merriweather:wght@300;400;700&family=Inter:wght@300;400;600&family=Roboto+Mono&display=swap');
    
    $fontCss

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
      padding: 20px !important;
      padding-bottom: 80px !important;
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
    
    /* TTS Highlighting Styles */
    .tts-paragraph {
      transition: background-color 0.3s ease, border-radius 0.3s ease;
      border-radius: 4px;
      padding: 2px 4px;
      margin: -2px -4px;
    }
    
    .tts-highlight {
      background-color: rgba(76, 175, 80, 0.25) !important;
      box-shadow: 0 0 0 2px rgba(76, 175, 80, 0.3);
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
  </style>
</head>
<body style="color: $themeColorHex !important; background-color: $bgColorHex !important;">
  $htmlContent
</body>
</html>
''';

    final contentBase64 = base64Encode(utf8.encode(combinedHtml));
    _controller.loadRequest(
      Uri.parse('data:text/html;charset=utf-8;base64,$contentBase64'),
    );
  }
}
