import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/app_theme.dart';
import '../api/arabic_service.dart';
import 'arabic_details_screen.dart';
import 'arabic_player_screen.dart';

class ArabicScreen extends StatefulWidget {
  const ArabicScreen({super.key});

  @override
  State<ArabicScreen> createState() => _ArabicScreenState();
}

class _ArabicScreenState extends State<ArabicScreen> {
  final ArabicService _service = ArabicService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ArabicShow> _shows = [];
  bool _isLoading = true;
  bool _isShowingLiked = false;
  bool _isSearching = false;
  String _searchQuery = '';
  int _currentPage = 1;
  String? _selectedCategory;
  bool _isCategoryDropdownOpen = false;

  @override
  void initState() {
    super.initState();
    _fetchShows();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchShows() async {
    setState(() {
      _isLoading = true;
      _isShowingLiked = false;
      _isSearching = false;
    });

    List<ArabicShow> results;
    if (_selectedCategory != null) {
      results = await _service.browseCategory(_selectedCategory!, page: _currentPage);
    } else {
      results = await _service.browse(page: _currentPage);
    }

    if (mounted) {
      setState(() {
        _shows = results;
        _isLoading = false;
      });
    }
    _scrollToTop();
  }

  Future<void> _searchShows(String query) async {
    if (query.trim().isEmpty) {
      _currentPage = 1;
      _fetchShows();
      return;
    }

    setState(() {
      _isLoading = true;
      _isShowingLiked = false;
      _isSearching = true;
      _searchQuery = query;
      _currentPage = 1;
    });

    // Search all sources in parallel
    final results = await Future.wait([
      _service.searchBrstej(query),
      _service.search(query),
      _service.searchDimaToon(query),
    ]);
    // Merge order determines priority when titles collide: brstej first,
    // then larozaa, then dimatoon.
    final merged = [...results[0], ...results[1], ...results[2]];

    // Cross-source dedup: collapse entries that look like the same show
    // (same normalized title) into one — prefer larozaa, then brstej, then
    // dimatoon, matching the order results were appended in.
    String norm(String t) => t
        .toLowerCase()
        .replaceAll(RegExp(r'^مسلسل\s+'), '')
        .replaceAll(RegExp(r'\s*الحلقة\s+.*$'), '')
        .replaceAll(RegExp(r'\s*(hd|مترجم(ة)?|مدبلج(ة)?)\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final seen = <String>{};
    final deduped = <ArabicShow>[];
    for (final s in merged) {
      final key = norm(s.title);
      if (key.isEmpty || seen.add(key)) deduped.add(s);
    }

    // Sort by relevancy to query
    final q = query.trim().toLowerCase();
    deduped.sort((a, b) {
      int score(ArabicShow s) {
        final t = s.title.toLowerCase();
        if (t == q) return 0;
        if (t.startsWith(q)) return 1;
        if (t.contains(q)) return 2;
        final words = q.split(RegExp(r'\s+'));
        final matched = words.where((w) => t.contains(w)).length;
        return 3 + (words.length - matched);
      }
      return score(a).compareTo(score(b));
    });
    if (mounted) {
      setState(() {
        _shows = deduped;
        _isLoading = false;
      });
    }
    _scrollToTop();
  }

  Future<void> _fetchLiked() async {
    setState(() {
      _isLoading = true;
      _isShowingLiked = true;
    });
    final liked = await _service.getLiked();
    if (mounted) {
      setState(() {
        _shows = liked;
        _isLoading = false;
      });
    }
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _nextPage() {
    setState(() => _currentPage++);
    if (_isSearching) {
      _doSearchPage();
    } else {
      _fetchShows();
    }
  }

  void _prevPage() {
    if (_currentPage > 1) {
      setState(() => _currentPage--);
      if (_isSearching) {
        _doSearchPage();
      } else {
        _fetchShows();
      }
    }
  }

  Future<void> _doSearchPage() async {
    setState(() => _isLoading = true);
    final results = await _service.search(_searchQuery, page: _currentPage);
    if (mounted) {
      setState(() {
        _shows = results;
        _isLoading = false;
      });
    }
    _scrollToTop();
  }

  void _onShowTap(ArabicShow show) {
    if (show.isMovie) {
      // Movies go directly to the player
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArabicPlayerScreen(videoId: show.id, title: show.title),
        ),
      );
    } else {
      // Series go to details
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArabicDetailsScreen(show: show),
        ),
      ).then((_) {
        if (_isShowingLiked) _fetchLiked();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 24),
                _buildHeader(),
                _buildSearchBar(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      if (_isShowingLiked) {
                        await _fetchLiked();
                      } else {
                        await _fetchShows();
                      }
                    },
                    color: AppTheme.primaryColor,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: _buildBody(),
                    ),
                  ),
                ),
                if (!_isShowingLiked) _buildPagination(),
              ],
            ),
            if (_isCategoryDropdownOpen)
              GestureDetector(
                onTap: () => setState(() => _isCategoryDropdownOpen = false),
                child: Container(color: Colors.black.withValues(alpha: 0.5)),
              ),
            if (_isCategoryDropdownOpen) _buildCategoryDropdown(),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        children: [
          const Icon(Icons.movie_filter_outlined, color: AppTheme.primaryColor, size: 28),
          const SizedBox(width: 12),
          const Text(
            'عربي',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Category filter
          GestureDetector(
            onTap: () => setState(() => _isCategoryDropdownOpen = !_isCategoryDropdownOpen),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _selectedCategory != null
                    ? AppTheme.primaryColor.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _selectedCategory != null ? AppTheme.primaryColor : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedCategory != null
                        ? arabicCategories.firstWhere((c) => c.slug == _selectedCategory).label
                        : 'التصنيف',
                    style: TextStyle(
                      color: _selectedCategory != null ? AppTheme.primaryColor : Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isCategoryDropdownOpen ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Liked toggle
          GestureDetector(
            onTap: () {
              if (_isShowingLiked) {
                _currentPage = 1;
                _fetchShows();
              } else {
                _fetchLiked();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isShowingLiked
                    ? AppTheme.primaryColor.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _isShowingLiked ? Icons.favorite : Icons.favorite_border,
                color: _isShowingLiked ? Colors.redAccent : Colors.white54,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ──────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: TextField(
        controller: _searchController,
        textDirection: TextDirection.rtl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'ابحث عن مسلسل أو فيلم...',
          hintTextDirection: TextDirection.rtl,
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38),
                  onPressed: () {
                    _searchController.clear();
                    _currentPage = 1;
                    _fetchShows();
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.07),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onSubmitted: _searchShows,
        onChanged: (v) => setState(() {}),
      ),
    );
  }

  // ── Category dropdown ───────────────────────────────────────────────

  Widget _buildCategoryDropdown() {
    return Positioned(
      top: 80,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 220,
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // "All" option
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCategory = null;
                        _isCategoryDropdownOpen = false;
                        _currentPage = 1;
                      });
                      _fetchShows();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: _selectedCategory == null
                          ? AppTheme.primaryColor.withValues(alpha: 0.15)
                          : Colors.transparent,
                      child: Text(
                        'الكل',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: _selectedCategory == null
                              ? AppTheme.primaryColor
                              : Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  ...arabicCategories.map((cat) => InkWell(
                        onTap: () {
                          setState(() {
                            _selectedCategory = cat.slug;
                            _isCategoryDropdownOpen = false;
                            _currentPage = 1;
                          });
                          _fetchShows();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          color: _selectedCategory == cat.slug
                              ? AppTheme.primaryColor.withValues(alpha: 0.15)
                              : Colors.transparent,
                          child: Text(
                            cat.label,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: _selectedCategory == cat.slug
                                  ? AppTheme.primaryColor
                                  : Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Body (grid) ─────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 100),
        child: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      );
    }

    if (_shows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 100),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.movie_filter_outlined, color: Colors.white24, size: 64),
              const SizedBox(height: 16),
              Text(
                _isShowingLiked ? 'لا توجد مفضلات' : 'لا توجد نتائج',
                style: const TextStyle(color: Colors.white38, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          int crossAxisCount;
          if (width > 1200) {
            crossAxisCount = 6;
          } else if (width > 900) {
            crossAxisCount = 5;
          } else if (width > 600) {
            crossAxisCount = 4;
          } else {
            crossAxisCount = 3;
          }

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.65,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _shows.length,
            itemBuilder: (context, index) {
              return _ShowCard(
                show: _shows[index],
                onTap: () => _onShowTap(_shows[index]),
              );
            },
          );
        },
      ),
    );
  }

  // ── Pagination ──────────────────────────────────────────────────────

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1 ? _prevPage : null,
            icon: const Icon(Icons.chevron_left, color: Colors.white54),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'صفحة $_currentPage',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          IconButton(
            onPressed: _shows.isNotEmpty ? _nextPage : null,
            icon: const Icon(Icons.chevron_right, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

// ── Show Card ──────────────────────────────────────────────────────────

class _ShowCard extends StatefulWidget {
  final ArabicShow show;
  final VoidCallback onTap;

  const _ShowCard({required this.show, required this.onTap});

  @override
  State<_ShowCard> createState() => _ShowCardState();
}

class _ShowCardState extends State<_ShowCard> {
  bool _isHovered = false;
  bool _isLiked = false;
  final _service = ArabicService();

  @override
  void initState() {
    super.initState();
    _checkLiked();
  }

  @override
  void didUpdateWidget(covariant _ShowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.show.id != widget.show.id) _checkLiked();
  }

  void _checkLiked() {
    _service.isLiked(widget.show.id).then((v) {
      if (mounted) setState(() => _isLiked = v);
    });
  }

  void _toggleLike() {
    _service.toggleLike(widget.show).then((_) => _checkLiked());
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: _isHovered
              ? Matrix4.diagonal3Values(1.05, 1.05, 1.0)
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 16,
                    )
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Poster image
                widget.show.poster.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: widget.show.poster,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          color: Colors.white.withValues(alpha: 0.05),
                          child: const Center(
                            child: Icon(Icons.movie_outlined, color: Colors.white24, size: 32),
                          ),
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: Colors.white.withValues(alpha: 0.05),
                          child: const Center(
                            child: Icon(Icons.broken_image, color: Colors.white24, size: 32),
                          ),
                        ),
                      )
                    : Container(
                        color: Colors.white.withValues(alpha: 0.05),
                        child: const Center(
                          child: Icon(Icons.movie_outlined, color: Colors.white24, size: 32),
                        ),
                      ),
                // Gradient overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                    child: Text(
                      widget.show.title,
                      textDirection: TextDirection.rtl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                // Movie/Series badge
                if (widget.show.isMovie)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'فيلم',
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                // Like button
                Positioned(
                  top: 4,
                  left: 4,
                  child: GestureDetector(
                    onTap: _toggleLike,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked ? Colors.redAccent : Colors.white70,
                        size: 18,
                      ),
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
}
