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

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q == _lastQuery) return;
    _lastQuery = q;

    if (q.isEmpty) {
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

    final results = await widget.notifier.searchAllChapters(q);

    if (mounted && q == _lastQuery) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.readerTheme.backgroundColor.withAlpha((0.98 * 255).round()),
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
                        // Optional: Debounce this for live search
                        // For now we trigger on submit or with a slight delay
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
                  : _searchResults.isEmpty && _searchController.text.isNotEmpty
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
