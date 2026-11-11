import 'package:flutter/material.dart';
import '../../../settings/data/models/reader_settings.dart';
import '../providers/reader_notifier.dart';
import 'package:velum/core/theme/app_colors.dart';

class GlobalSearchOverlay extends StatefulWidget {
  final ReaderTheme readerTheme;
  final ReaderNotifier notifier;
  final ValueChanged<GlobalSearchResult> onResultTap;
  final VoidCallback onClose;

  const GlobalSearchOverlay({
    super.key,
    required this.readerTheme,
    required this.notifier,
    required this.onResultTap,
    required this.onClose,
  });

  @override
  State<GlobalSearchOverlay> createState() => _GlobalSearchOverlayState();
}

class _GlobalSearchOverlayState extends State<GlobalSearchOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;
  List<GlobalSearchResult> _searchResults = [];
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field when opened
    Future.microtask(() => _searchFocusNode.requestFocus());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Shorter queries match on nearly every line.
  static const _minQueryLength = 2;

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;

    if (q.length < _minQueryLength) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    List<GlobalSearchResult>? results;
    try {
      results = await widget.notifier.searchAllChapters(q);
    } catch (e) {
      debugPrint('Search failed: $e');
    }
    // A newer search has taken over: these are for an old query.
    if (!mounted || q != _lastQuery) return;
    // Let the same query be tried again after a failure.
    if (results == null) _lastQuery = '';
    setState(() {
      _searchResults = results ?? [];
      _isSearching = false;
    });
  }

  /// The search for what is in the field has finished and found nothing.
  bool get _noMatches =>
      !_isSearching &&
      _searchResults.isEmpty &&
      _lastQuery.length >= _minQueryLength &&
      _lastQuery == _searchController.text.trim();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.readerTheme.backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // Search Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: widget.readerTheme.textColor.withAlpha(20),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: widget.readerTheme.textColor,
                    ),
                    onPressed: widget.onClose,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: TextStyle(
                        color: widget.readerTheme.textColor,
                        fontSize: 16,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: _performSearch,
                      onChanged: (val) {
                        // The clear button and empty state follow the text.
                        setState(() {});
                        // Search once typing pauses.
                        Future.delayed(const Duration(milliseconds: 500), () {
                          if (mounted && _searchController.text == val) {
                            _performSearch(val);
                          }
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search in book...',
                        hintStyle: TextStyle(
                          color: widget.readerTheme.textColor.withAlpha(100),
                        ),
                        border: InputBorder.none,
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  color: widget.readerTheme.textColor.withAlpha(
                                    150,
                                  ),
                                  size: 20,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                  _performSearch('');
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (!_isSearching && _searchResults.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  _searchResults.length == 1
                      ? '1 match'
                      : '${_searchResults.length} matches',
                  style: TextStyle(
                    color: widget.readerTheme.textColor.withAlpha(130),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            // Search Results
            Expanded(
              child: _isSearching
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.readerTheme.textColor.withAlpha(150),
                        ),
                        strokeWidth: 2,
                      ),
                    )
                  : _noMatches
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: widget.readerTheme.textColor.withAlpha(100),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No matches found',
                            style: TextStyle(
                              color: widget.readerTheme.textColor.withAlpha(
                                150,
                              ),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return InkWell(
                          onTap: () => widget.onResultTap(result),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: widget.readerTheme.textColor.withAlpha(
                                    15,
                                  ),
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Highlighted snippet
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      color: widget.readerTheme.textColor,
                                      fontSize: 15,
                                      height: 1.4,
                                    ),
                                    children: [
                                      TextSpan(text: result.snippetBefore),
                                      TextSpan(
                                        text: result.matchedText,
                                        style: TextStyle(
                                          backgroundColor: AppColors.accent
                                              .withAlpha((0.3 * 255).round()),
                                          color: widget.readerTheme.textColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(text: result.snippetAfter),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Metadata (Chapter + Position)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.menu_book,
                                      size: 14,
                                      color: widget.readerTheme.textColor
                                          .withAlpha(120),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        result.chapterTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: widget.readerTheme.textColor
                                              .withAlpha(120),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${(result.positionPercent * 100).toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: widget.readerTheme.textColor
                                            .withAlpha(150),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
