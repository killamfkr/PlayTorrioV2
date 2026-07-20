import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'comic_details_screen.dart';
import 'comic_reader_screen.dart';
import '../api/comics_service.dart';
import '../utils/app_theme.dart';
import '../widgets/tv_interactive.dart';

class ComicsScreen extends StatefulWidget {
  final String? initialSearch;
  const ComicsScreen({super.key, this.initialSearch});

  @override
  State<ComicsScreen> createState() => _ComicsScreenState();
}

class _ComicsScreenState extends State<ComicsScreen> {
  final ComicsService _comicsService = ComicsService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<Comic> _comics = [];
  List<String> _likedUrls = [];
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  int _currentPage = 1;
  bool _isShowingLiked = false;
  String _currentSearchQuery = '';

  static const String _historyKey = 'comic_reading_history';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadLikedStatus();
    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      _currentSearchQuery = widget.initialSearch!;
      _searchController.text = _currentSearchQuery;
      _searchComics(_currentSearchQuery);
    } else {
      _fetchComics();
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_historyKey) ?? [];
    if (mounted) {
      setState(() {
        _history = historyJson.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
      });
    }
  }

  Future<void> _removeFromHistory(String comicUrl) async {
    final prefs = await SharedPreferences.getInstance();
    _history.removeWhere((h) => h['comic']['url'] == comicUrl);
    await prefs.setStringList(_historyKey, _history.map((e) => jsonEncode(e)).toList());
    setState(() {});
  }

  void _resumeReading(Map<String, dynamic> progress) {
    final comic = Comic.fromJson(progress['comic']);
    final chapterIndex = progress['chapterIndex'] as int;
    final pageIndex = progress['pageIndex'] as int;
    final chapters = (progress['chapters'] as List).map((e) => ComicChapter(
      title: e['title'],
      url: e['url'],
      dateAdded: e['dateAdded'],
    )).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ComicReaderScreen(
          chapterTitle: chapters[chapterIndex].title,
          chapterUrl: chapters[chapterIndex].url,
          chapters: chapters,
          currentChapterIndex: chapterIndex,
          resumePageIndex: pageIndex,
          comic: comic,
        ),
      ),
    ).then((_) => _loadHistory()); // Reload history when returning
  }

  Future<void> _loadLikedStatus() async {
    final liked = await _comicsService.getLikedComics();
    if (mounted) {
      setState(() {
        _likedUrls = liked.map((c) => c.url).toList();
      });
    }
  }

  Future<void> _fetchComics() async {
    setState(() {
      _isLoading = true;
      _isShowingLiked = false;
    });
    final comics = await _comicsService.getComics(page: _currentPage);
    setState(() {
      _comics = comics;
      _isLoading = false;
    });
    _scrollToTop();
  }

  Future<void> _searchComics(String query) async {
    if (query.isEmpty) {
      _currentPage = 1;
      _fetchComics();
      return;
    }
    setState(() {
      _isLoading = true;
      _isShowingLiked = false;
      _currentSearchQuery = query;
    });
    final comics = await _comicsService.searchComics(query);
    setState(() {
      _comics = comics;
      _isLoading = false;
    });
    _scrollToTop();
  }

  Future<void> _fetchLikedComics() async {
    setState(() {
      _isLoading = true;
      _isShowingLiked = true;
    });
    final liked = await _comicsService.getLikedComics();
    setState(() {
      _comics = liked;
      _isLoading = false;
    });
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _nextPage() {
    setState(() => _currentPage++);
    _fetchComics();
  }

  void _prevPage() {
    if (_currentPage > 1) {
      setState(() => _currentPage--);
      _fetchComics();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildHeader(),
            _buildSearchBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  if (_isShowingLiked) {
                    await _fetchLikedComics();
                  } else if (_currentSearchQuery.isNotEmpty) {
                    await _searchComics(_currentSearchQuery);
                  } else {
                    await _fetchComics();
                  }
                },
                color: AppTheme.primaryColor,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      if (_history.isNotEmpty && !_isShowingLiked && _currentSearchQuery.isEmpty) _buildHistoryCarousel(),
                      _buildBody(),
                    ],
                  ),
                ),
              ),
            ),
            if (!_isShowingLiked && _currentSearchQuery.isEmpty) _buildPagination(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Comics',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
          ),
          IconButton(
            icon: Icon(
              _isShowingLiked ? Icons.favorite : Icons.favorite_border,
              color: _isShowingLiked ? Colors.redAccent : Colors.white,
              size: 28,
            ),
            onPressed: () {
              if (_isShowingLiked) {
                _fetchComics();
              } else {
                _fetchLikedComics();
              }
            },
            tooltip: _isShowingLiked ? 'Show All' : 'Show Liked',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: TextField(
        controller: _searchController,
        onSubmitted: _searchComics,
        decoration: InputDecoration(
          hintText: 'Search comics...',
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _currentSearchQuery = '';
                    _currentPage = 1;
                    _fetchComics();
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildHistoryCarousel() {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    final pageController = PageController(viewportFraction: isDesktop ? 0.45 : 0.9);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('CONTINUE READING', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
              if (isDesktop && _history.length > 1)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, size: 16),
                      onPressed: () {
                        pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      color: Colors.white54,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 16),
                      onPressed: () {
                        pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      color: Colors.white54,
                    ),
                  ],
                ),
            ],
          ),
        ),
        SizedBox(
          height: 120,
          child: PageView.builder(
            controller: pageController,
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final progress = _history[index];
              final comic = Comic.fromJson(progress['comic']);
              final chapterIdx = progress['chapterIndex'] + 1;
              final pageIdx = progress['pageIndex'] + 1;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Stack(
                  children: [
                    FocusableControl(
                      onTap: () => _resumeReading(progress),
                      borderRadius: 16,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: comic.poster,
                                width: 60, height: 60, fit: BoxFit.cover,
                                errorWidget: (c, u, e) => const Icon(Icons.book),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(comic.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text('Chapter $chapterIdx • Page $pageIdx', style: const TextStyle(color: AppTheme.primaryColor, fontSize: 13, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            const Icon(Icons.menu_book, color: AppTheme.primaryColor, size: 40),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4, right: 4,
                      child: TvGestureTap(
                        onTap: () => _removeFromHistory(comic.url),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Colors.white70),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton(
            onPressed: _currentPage > 1 ? _prevPage : null,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white),
            child: const Text('Previous'),
          ),
          Text('Page $_currentPage', style: const TextStyle(fontWeight: FontWeight.bold)),
          ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            child: const Text('Next Page'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isShowingLiked ? Icons.favorite_border : Icons.search_off,
              size: 64,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              _isShowingLiked ? 'No liked comics yet' : 'No comics found',
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Padding(padding: EdgeInsets.only(top: 100), child: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)));
    if (_comics.isEmpty) return _buildEmptyState();

    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 2;
    if (screenWidth > 1200) {
      crossAxisCount = 6;
    } else if (screenWidth > 900) {
      crossAxisCount = 4;
    } else if (screenWidth > 600) {
      crossAxisCount = 3;
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.7,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _comics.length,
      itemBuilder: (context, index) {
        final comic = _comics[index];
        final isLiked = _likedUrls.contains(comic.url);
        return _ComicCard(
          comic: comic,
          isLiked: isLiked,
          onLikeChanged: () {
            _loadLikedStatus();
            if (_isShowingLiked) {
              _fetchLikedComics();
            }
          },
        );
      },
    );
  }
}

class _ComicCard extends StatefulWidget {
  final Comic comic;
  final bool isLiked;
  final VoidCallback onLikeChanged;

  const _ComicCard({required this.comic, required this.isLiked, required this.onLikeChanged});

  @override
  State<_ComicCard> createState() => _ComicCardState();
}

class _ComicCardState extends State<_ComicCard> {
  final ComicsService _comicsService = ComicsService();

  Future<void> _toggleLike() async {
    await _comicsService.toggleLike(widget.comic);
    widget.onLikeChanged();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableControl(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ComicDetailsScreen(comic: widget.comic),
          ),
        ).then((_) {
          widget.onLikeChanged(); // Refresh like status when coming back
          // Trigger parent to reload history
          if (context.mounted) {
            final state = context.findAncestorStateOfType<_ComicsScreenState>();
            state?._loadHistory();
          }
        });
      },
      borderRadius: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CachedNetworkImage(
                    imageUrl: widget.comic.poster,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (context, url) => Container(color: Colors.white10),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.white10,
                      child: const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.comic.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.comic.status,
                        style: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: TvGestureTap(
                onTap: _toggleLike,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isLiked ? Icons.favorite : Icons.favorite_border,
                    color: widget.isLiked ? Colors.redAccent : Colors.white70,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
