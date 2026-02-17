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
import 'package:go_router/go_router.dart';
import '../../data/models/highlight.dart';
import '../providers/highlight_notifier.dart';
import '../widgets/contents_modal.dart';
import '../widgets/highlights_modal.dart';

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
  String? _lastChapterTitle; // Track chapter changes for TTS
  String? _lastHighlightKey; // Track current TTS highlight position
  bool _isPageReady = false; // Track if JS is injected and ready
  bool _showTutorial = false; // First-time tutorial overlay
  bool _showBookComplete = false; // End-of-book celebration screen

  // Cache for custom font base64 to avoid blocking file I/O on every content load
  String? _cachedFontPath;
  String? _cachedFontBase64;

  // In-chapter search
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  int _searchMatchCount = 0;
  int _searchCurrentIndex = -1;

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

      // Load highlights for this book
      context.read<HighlightNotifier>().loadHighlights(widget.assetPath);

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
    _controller.runJavaScript('if(window.searchClear) window.searchClear();');
    setState(() {
      _showSearch = false;
      _searchMatchCount = 0;
      _searchCurrentIndex = -1;
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final escaped = value.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      _controller.runJavaScript(
        "if(window.searchFind) window.searchFind('$escaped');",
      );
    });
  }

  Widget _buildSearchBar(ReaderTheme readerTheme) {
    final Color bg;
    final Color border;
    switch (readerTheme) {
      case ReaderTheme.dark:
        bg = const Color(0xFF2A2A2A);
        border = Colors.white.withAlpha(25);
      case ReaderTheme.sepia:
        bg = const Color(0xFFEDE4D3);
        border = Colors.brown.withAlpha(30);
      case ReaderTheme.light:
        bg = Colors.white;
        border = Colors.black.withAlpha(15);
    }

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(28),
      color: bg,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            // Close button
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                size: 20,
                color: readerTheme.textColor,
              ),
              onPressed: _closeSearch,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            // Text field
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                style: TextStyle(fontSize: 14, color: readerTheme.textColor),
                decoration: InputDecoration(
                  hintText: 'Find...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: readerTheme.textColor.withAlpha(100),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            // Match count
            if (_searchMatchCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '${_searchCurrentIndex + 1}/$_searchMatchCount',
                  style: TextStyle(
                    fontSize: 12,
                    color: readerTheme.textColor.withAlpha(150),
                  ),
                ),
              )
            else if (_searchController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '0',
                  style: TextStyle(
                    fontSize: 12,
                    color: readerTheme.textColor.withAlpha(150),
                  ),
                ),
              ),
            // Prev / Next
            IconButton(
              icon: Icon(
                Icons.keyboard_arrow_up,
                size: 20,
                color: readerTheme.textColor.withAlpha(
                  _searchMatchCount > 0 ? 255 : 60,
                ),
              ),
              onPressed: _searchMatchCount > 0
                  ? () => _controller.runJavaScript(
                      'if(window.searchPrev) window.searchPrev();',
                    )
                  : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
            ),
            IconButton(
              icon: Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: readerTheme.textColor.withAlpha(
                  _searchMatchCount > 0 ? 255 : 60,
                ),
              ),
              onPressed: _searchMatchCount > 0
                  ? () => _controller.runJavaScript(
                      'if(window.searchNext) window.searchNext();',
                    )
                  : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
            ),
          ],
        ),
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
                _animatePageTurn(-1);
              }
              break;
            case 'prev':
              _animatePageTurn(1); // Slide right
              notifier.previousChapter();
              break;
            default:
              // Handle scroll position message
              if (message.message.startsWith('scroll:')) {
                _savedScrollPosition =
                    double.tryParse(message.message.substring(7)) ?? 0;
              }
              // Handle search result count
              else if (message.message.startsWith('search-results:')) {
                final count = int.tryParse(message.message.substring(15)) ?? 0;
                setState(() {
                  _searchMatchCount = count;
                  _searchCurrentIndex = count > 0 ? 0 : -1;
                });
              }
              // Handle search index navigation
              else if (message.message.startsWith('search-index:')) {
                final idx = int.tryParse(message.message.substring(13)) ?? -1;
                setState(() {
                  _searchCurrentIndex = idx;
                });
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
          onPageFinished: (String url) {
            _injectJS();
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
                _controller.runJavaScript(
                  "window.scrollToHighlight('$hlId');",
                );
              });
            }
          },
        ),
      );
  }

  // CSS is now baked into HTML in _loadChapterContent - no separate injection needed

  void _injectJS() {
    // Inject swipe and tap handlers
    _controller.runJavaScript('''
      // Track for double-tap detection
      var lastTapTime = 0;
      var lastTapTarget = null;
      var tapTimeout = null;
      
      // Swipe detection
      var touchStartX = 0;
      var touchStartY = 0;
      var touchStartTime = 0;
      
      document.addEventListener('touchstart', function(e) {
        touchStartX = e.touches[0].clientX;
        touchStartY = e.touches[0].clientY;
        touchStartTime = Date.now();
      }, { passive: true });

      document.addEventListener('touchend', function(e) {
        var touchEndX = e.changedTouches[0].clientX;
        var touchEndY = e.changedTouches[0].clientY;
        var deltaX = touchEndX - touchStartX;
        var deltaY = touchEndY - touchStartY;
        var deltaTime = Date.now() - touchStartTime;

        // Only detect horizontal swipes (not vertical scrolling)
        // Require: >50px horizontal, <150px vertical, <700ms duration
        if (Math.abs(deltaX) > 50 && Math.abs(deltaY) < 150 && deltaTime < 700) {
          if (deltaX > 0) {
            // Swipe right = previous chapter
            ReaderChannel.postMessage('prev');
          } else {
            // Swipe left = next chapter
            ReaderChannel.postMessage('next');
          }
        }
      }, { passive: true });
      
      document.body.addEventListener('click', function(e) {
        var now = Date.now();

        // Check for double-tap on TTS paragraph/sentence FIRST
        // (before selection check, so browser's double-click text selection doesn't interfere)
        var target = e.target.closest('[data-para]');

        if (target && lastTapTarget === target && (now - lastTapTime) < 400) {
          // Double tap detected - skip to this paragraph/sentence
          clearTimeout(tapTimeout);
          // Clear any text selection that may have occurred
          window.getSelection().removeAllRanges();
          var paraIndex = target.getAttribute('data-para');
          var sentIndex = target.getAttribute('data-sent');
          if (sentIndex !== null) {
            ReaderChannel.postMessage('tts-skip:' + paraIndex + ':' + sentIndex);
          } else {
            ReaderChannel.postMessage('tts-skip:' + paraIndex);
          }
          lastTapTime = 0;
          lastTapTarget = null;
          e.preventDefault();
          e.stopPropagation();
          return;
        }

        // Don't trigger if user is selecting text (by dragging)
        if (window.getSelection().toString().length > 0) return;

        lastTapTime = now;
        lastTapTarget = target;

        // Delay single-tap to allow for double-tap detection
        clearTimeout(tapTimeout);
        tapTimeout = setTimeout(function() {
          // Single tap toggles UI (no more edge navigation)
          ReaderChannel.postMessage('toggle');
        }, target ? 400 : 0);
      });
      
      // TTS highlight functions
      window.ttsHighlightParagraph = function(index) {
        // Remove previous highlight
        var prev = document.querySelector('.tts-highlight');
        if (prev) prev.classList.remove('tts-highlight');
        
        // Find paragraph by data-para attribute
        var el = document.querySelector('[data-para="' + index + '"]');
        if (el) {
          el.classList.add('tts-highlight');
          el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      };
      
      window.ttsHighlightSentence = function(paraIndex, sentIndex) {
        // Remove previous highlight
        var prev = document.querySelector('.tts-highlight');
        if (prev) prev.classList.remove('tts-highlight');
        
        // Find sentence by data-para and data-sent attributes
        var el = document.querySelector('[data-para="' + paraIndex + '"][data-sent="' + sentIndex + '"]');
        if (el) {
          el.classList.add('tts-highlight');
          el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        } else {
          // Fallback to paragraph highlight if no sentence span found
          window.ttsHighlightParagraph(paraIndex);
        }
      };
      
      window.ttsClearHighlight = function() {
        var prev = document.querySelector('.tts-highlight');
        if (prev) prev.classList.remove('tts-highlight');
      };

      // Scroll listener to update Flutter state
      var scrollTimeout;
      window.addEventListener('scroll', function() {
        clearTimeout(scrollTimeout);
        scrollTimeout = setTimeout(function() {
          ReaderChannel.postMessage('scroll:' + window.scrollY);
        }, 200);
      });

      // Search functions
      window._searchMatches = [];
      window._searchIndex = -1;

      window.searchFind = function(query) {
        window.searchClear();
        if (!query || query.length === 0) {
          ReaderChannel.postMessage('search-results:0');
          return;
        }
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
        var textNodes = [];
        while (walker.nextNode()) textNodes.push(walker.currentNode);
        var lowerQ = query.toLowerCase();
        var count = 0;
        textNodes.forEach(function(node) {
          var text = node.nodeValue;
          var lower = text.toLowerCase();
          var idx = lower.indexOf(lowerQ);
          if (idx === -1) return;
          var parent = node.parentNode;
          var frag = document.createDocumentFragment();
          var last = 0;
          while (idx !== -1) {
            if (idx > last) frag.appendChild(document.createTextNode(text.substring(last, idx)));
            var mark = document.createElement('mark');
            mark.className = 'search-match';
            mark.setAttribute('data-si', count.toString());
            mark.textContent = text.substring(idx, idx + query.length);
            frag.appendChild(mark);
            count++;
            last = idx + query.length;
            idx = lower.indexOf(lowerQ, last);
          }
          if (last < text.length) frag.appendChild(document.createTextNode(text.substring(last)));
          parent.replaceChild(frag, node);
        });
        window._searchMatches = document.querySelectorAll('.search-match');
        if (count > 0) {
          window._searchIndex = 0;
          window._searchMatches[0].classList.add('search-current');
          window._searchMatches[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
        ReaderChannel.postMessage('search-results:' + count);
      };

      window.searchNext = function() {
        var m = window._searchMatches;
        if (!m || m.length === 0) return;
        m[window._searchIndex].classList.remove('search-current');
        window._searchIndex = (window._searchIndex + 1) % m.length;
        m[window._searchIndex].classList.add('search-current');
        m[window._searchIndex].scrollIntoView({ behavior: 'smooth', block: 'center' });
        ReaderChannel.postMessage('search-index:' + window._searchIndex);
      };

      window.searchPrev = function() {
        var m = window._searchMatches;
        if (!m || m.length === 0) return;
        m[window._searchIndex].classList.remove('search-current');
        window._searchIndex = (window._searchIndex - 1 + m.length) % m.length;
        m[window._searchIndex].classList.add('search-current');
        m[window._searchIndex].scrollIntoView({ behavior: 'smooth', block: 'center' });
        ReaderChannel.postMessage('search-index:' + window._searchIndex);
      };

      window.searchClear = function() {
        var marks = document.querySelectorAll('.search-match');
        marks.forEach(function(mk) {
          var p = mk.parentNode;
          p.replaceChild(document.createTextNode(mk.textContent), mk);
          p.normalize();
        });
        window._searchMatches = [];
        window._searchIndex = -1;
      };

      // ── Highlight system ──────────────────────────────────────────
      // Listen for text selection changes
      var selectionTimeout;
      document.addEventListener('selectionchange', function() {
        clearTimeout(selectionTimeout);
        selectionTimeout = setTimeout(function() {
          var sel = window.getSelection();
          if (sel && sel.toString().trim().length > 0 && sel.rangeCount > 0) {
            var range = sel.getRangeAt(0);
            // Calculate text offset within the body
            var preRange = document.createRange();
            preRange.selectNodeContents(document.body);
            preRange.setEnd(range.startContainer, range.startOffset);
            var startOffset = preRange.toString().length;
            var endOffset = startOffset + sel.toString().length;
            ReaderChannel.postMessage('selection:' + JSON.stringify({
              text: sel.toString().trim(),
              startOffset: startOffset,
              endOffset: endOffset
            }));
          } else {
            ReaderChannel.postMessage('selection-cleared');
          }
        }, 300);
      });

      // Apply a highlight visually
      window.applyHighlight = function(startOffset, endOffset, color, hlId) {
        var body = document.body;
        var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null, false);
        var charCount = 0;
        var nodesToWrap = [];

        while (walker.nextNode()) {
          var node = walker.currentNode;
          var nodeLen = node.nodeValue.length;
          var nodeStart = charCount;
          var nodeEnd = charCount + nodeLen;

          if (nodeEnd > startOffset && nodeStart < endOffset) {
            var wrapStart = Math.max(0, startOffset - nodeStart);
            var wrapEnd = Math.min(nodeLen, endOffset - nodeStart);
            nodesToWrap.push({ node: node, start: wrapStart, end: wrapEnd });
          }
          charCount += nodeLen;
          if (charCount >= endOffset) break;
        }

        for (var i = nodesToWrap.length - 1; i >= 0; i--) {
          var item = nodesToWrap[i];
          var range = document.createRange();
          range.setStart(item.node, item.start);
          range.setEnd(item.node, item.end);
          var mark = document.createElement('mark');
          mark.className = 'user-highlight';
          mark.setAttribute('data-hl-id', hlId);
          mark.style.setProperty('background-color', color, 'important');
          mark.style.setProperty('border-radius', '2px', 'important');
          mark.style.setProperty('padding', '1px 0', 'important');
          try {
            range.surroundContents(mark);
          } catch(e) {
            // If surroundContents fails (partial overlap), use extractContents
            var frag = range.extractContents();
            mark.appendChild(frag);
            range.insertNode(mark);
          }
        }
        // Clear selection after highlighting
        window.getSelection().removeAllRanges();
      };

      // Remove a highlight by ID
      window.removeHighlight = function(hlId) {
        var marks = document.querySelectorAll('mark[data-hl-id="' + hlId + '"]');
        marks.forEach(function(mark) {
          var parent = mark.parentNode;
          while (mark.firstChild) {
            parent.insertBefore(mark.firstChild, mark);
          }
          parent.removeChild(mark);
          parent.normalize();
        });
      };

      // Restore all highlights from JSON
      window.restoreHighlights = function(highlightsJson) {
        var highlights = JSON.parse(highlightsJson);
        highlights.forEach(function(h) {
          window.applyHighlight(h.startOffset, h.endOffset, h.color, h.id);
        });
      };

      // Scroll to a specific highlight by ID
      window.scrollToHighlight = function(hlId) {
        var el = document.querySelector('mark[data-hl-id="' + hlId + '"]');
        if (el) {
          el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      };
    ''');
  }

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
                return _buildTtsFab(
                  ttsNotifier,
                  notifier,
                  showUI,
                  readerTheme,
                )!;
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
                                Icons.bookmark_outline,
                                color: readerTheme.textColor,
                              ),
                              onPressed: () async {
                                final highlight = await showModalBottomSheet<Highlight>(
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
              const BannerAdWidget(),
            ],
          ),

          // Search overlay
          if (_showSearch)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
              left: 24,
              right: 24,
              child: _buildSearchBar(readerTheme),
            ),

          // Color picker overlay for highlighting
          if (_showColorPicker)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
              left: 0,
              right: 0,
              child: _buildColorPicker(readerTheme, notifier),
            ),

          // Book complete overlay
          if (_showBookComplete)
            Positioned.fill(
              child: _buildBookCompleteScreen(notifier, readerTheme),
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

  Widget? _buildTtsFab(
    TtsNotifier ttsNotifier,
    ReaderNotifier readerNotifier,
    bool showUI,
    ReaderTheme readerTheme,
  ) {
    // Only show FAB when content is loaded
    if (readerNotifier.currentChapter == null) return null;

    final currentChapterTitle = readerNotifier.currentChapter?.Title;

    // Detect chapter change - stop TTS and clear content
    // Skip the first build (_lastChapterTitle == null) so re-entering the
    // reader from the library doesn't falsely clear TTS position.
    if (_lastChapterTitle == null) {
      _lastChapterTitle = currentChapterTitle;
    } else if (_lastChapterTitle != currentChapterTitle) {
      _lastChapterTitle = currentChapterTitle;
      // Schedule content clear after build (not during build)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ttsNotifier.isPlaying || ttsNotifier.isPaused) {
          ttsNotifier.stop();
        }
        // Clear chunks so next play loads new chapter
        ttsNotifier.loadContent('');
      });
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: EdgeInsets.only(bottom: showUI ? 140 : 66),
      child: FloatingActionButton(
        key: _fabKey,
        onPressed: () async {
          // Load current chapter content
          if (ttsNotifier.chunks.isEmpty) {
            final text = readerNotifier.extractStructuredText();
            if (text.isNotEmpty) {
              ttsNotifier.loadContent(text);
            }
          }

          // Update notification metadata
          context.read<VelumAudioHandler>().setMediaMetadata(
            bookTitle: readerNotifier.currentBook?.Title ?? 'Unknown Book',
            chapterTitle:
                readerNotifier.currentChapter?.Title ?? 'Unknown Chapter',
          );

          await ttsNotifier.togglePlayPause();
        },
        backgroundColor: _accentGreen,
        child: Icon(
          ttsNotifier.isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildColorPicker(ReaderTheme readerTheme, ReaderNotifier notifier) {
    const colorOptions = <String, Color>{
      'yellow': Color(0xFFFFF176),
      'green': Color(0xFF81C784),
      'blue': Color(0xFF64B5F6),
      'pink': Color(0xFFF48FB1),
      'orange': Color(0xFFFFB74D),
    };

    return Center(
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(28),
        color: readerTheme.backgroundColor,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: readerTheme.textColor.withAlpha(30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...colorOptions.entries.map((entry) {
                return GestureDetector(
                  onTap: () => _applyHighlight(entry.key, entry.value, notifier),
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: entry.value.withAlpha(200),
                        width: 2,
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  _controller.runJavaScript(
                    'window.getSelection().removeAllRanges();',
                  );
                  setState(() => _showColorPicker = false);
                },
                child: Container(
                  width: 32,
                  height: 32,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookCompleteScreen(
    ReaderNotifier notifier,
    ReaderTheme readerTheme,
  ) {
    final bookTitle = notifier.currentBook?.Title ?? 'the book';

    return Material(
      color: readerTheme.backgroundColor.withAlpha((0.96 * 255).round()),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accentGreen.withAlpha(30),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 48,
                    color: _accentGreen,
                  ),
                ),
                const SizedBox(height: 28),

                // Heading
                Text(
                  'You finished it!',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: readerTheme.textColor,
                    letterSpacing: 0.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Book title
                Text(
                  bookTitle,
                  style: TextStyle(
                    fontSize: 15,
                    color: readerTheme.textColor.withAlpha(160),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 48),

                // Back to Library button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.go('/'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accentGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.library_books_rounded, size: 20),
                    label: const Text(
                      'Back to Library',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Start Over button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final chapters = notifier.currentBook?.Chapters;
                      if (chapters != null && chapters.isNotEmpty) {
                        notifier.jumpToChapter(chapters.first);
                      }
                      setState(() => _showBookComplete = false);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: readerTheme.textColor,
                      side: BorderSide(
                        color: readerTheme.textColor.withAlpha(60),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.replay_rounded, size: 20),
                    label: const Text(
                      'Start Over',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Dismiss — keep reading at the last chapter
                TextButton(
                  onPressed: () => setState(() => _showBookComplete = false),
                  child: Text(
                    'Stay here',
                    style: TextStyle(
                      fontSize: 14,
                      color: readerTheme.textColor.withAlpha(120),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToHighlight(Highlight highlight, ReaderNotifier notifier) {
    final chapters = notifier.currentBook?.Chapters;
    if (chapters == null) return;

    final sameChapter = highlight.chapterIndex == notifier.currentChapterIndex;

    if (sameChapter) {
      // Already on the right chapter — just scroll
      _controller.runJavaScript(
        "window.scrollToHighlight('${highlight.id}');",
      );
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

    final jsonList = highlights.map((h) => {
      'id': h.id,
      'startOffset': h.startOffset,
      'endOffset': h.endOffset,
      'color': colorMap[h.color] ?? 'rgba(255, 241, 118, 0.4)',
    }).toList();

    final jsonStr = jsonEncode(jsonList).replaceAll("'", "\\'");
    _controller.runJavaScript("window.restoreHighlights('$jsonStr');");
  }

  void _applyHighlight(String colorName, Color color, ReaderNotifier notifier) {
    final highlightNotifier = context.read<HighlightNotifier>();
    final chapterIndex = notifier.currentChapterIndex;

    // Convert color to CSS rgba
    final cssColor = 'rgba(${(color.r * 255).round()}, ${(color.g * 255).round()}, ${(color.b * 255).round()}, 0.4)';

    // Add to state/storage
    highlightNotifier.addHighlight(
      chapterIndex: chapterIndex,
      text: _selectedText,
      color: colorName,
      startOffset: _selectionStartOffset,
      endOffset: _selectionEndOffset,
    ).then((_) {
      // Get the newly added highlight to get its ID
      final highlights = highlightNotifier.highlightsForChapter(chapterIndex);
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

    // Clear search state when content changes (DOM is about to be replaced)
    if (!contentSame) {
      _searchMatchCount = 0;
      _searchCurrentIndex = -1;
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
