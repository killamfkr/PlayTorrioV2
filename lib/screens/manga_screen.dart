import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/app_theme.dart';
import '../api/manga_service.dart';
import 'manga_details_screen.dart';
import 'manga_reader_screen.dart';

class MangaScreen extends StatefulWidget {
  final String? initialSearch;
  const MangaScreen({super.key, this.initialSearch});

  @override
  State<MangaScreen> createState() => _MangaScreenState();
}

class _MangaScreenState extends State<MangaScreen> with WidgetsBindingObserver {
  final MangaService _mangaService = MangaService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Manga> _manga = [];
  List<String> _likedIds = [];
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  bool _isShowingLiked = false;
  bool _isSearching = false;
  String _searchQuery = '';
  int _currentPage = 1;
  String? _selectedGenre;
  bool _isGenreDropdownOpen = false;
  /// Default on: show all ratings including 18+ / NSFW (user can turn off via 18+ toggle).
  bool _allowAdult = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLikedStatus();
    _loadHistory();
    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      _searchController.text = widget.initialSearch!;
    }
    _fetchManga();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reload history when app comes back to foreground
      _loadHistory();
    }
  }

  Future<void> _loadLikedStatus() async {
    final liked = await _mangaService.getLikedManga();
    if (mounted) {
      setState(() {
        _likedIds = liked.map((m) => m.id).toList();
      });
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('manga_reading_history') ?? [];
    if (mounted) {
      setState(() {
        _history = historyJson.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
      });
    }
  }

  void _resumeReading(Map<String, dynamic> progress) {
    final manga = Manga.fromJson(progress['manga']);
    final chapterIndex = progress['chapterIndex'] as int;
    final pageIndex = progress['pageIndex'] as int;
    final chapters = (progress['chapters'] as List).map((c) => MangaChapter.fromJson(c)).toList();
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MangaReaderScreen(
          manga: manga,
          chapters: chapters,
          currentChapterIndex: chapterIndex,
          resumePageIndex: pageIndex,
        ),
      ),
    ).then((_) => _loadHistory());
  }

  void _removeFromHistory(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('manga_reading_history') ?? [];
    final history = historyJson.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    
    history.removeWhere((h) => h['manga']['id'] == id);
    
    await prefs.setStringList('manga_reading_history', history.map((e) => jsonEncode(e)).toList());
    _loadHistory();
  }

  Future<void> _fetchManga() async {
    setState(() {
      _isLoading = true;
      _isShowingLiked = false;
      _isSearching = false;
    });
    final manga = await _mangaService.getManga(page: _currentPage, tag: _selectedGenre, allowAdult: _allowAdult);
    setState(() {
      _manga = manga;
      _isLoading = false;
    });
    _scrollToTop();
  }

  Future<void> _searchManga(String query) async {
    if (query.trim().isEmpty) {
      _currentPage = 1;
      _fetchManga();
      return;
    }

    setState(() {
      _isLoading = true;
      _isShowingLiked = false;
      _isSearching = true;
      _searchQuery = query;
      _currentPage = 1;
    });
    
    final results = await _mangaService.searchManga(query, page: _currentPage, allowAdult: _allowAdult);
    setState(() {
      _manga = results;
      _isLoading = false;
    });
    _scrollToTop();
  }

  Future<void> _loadMoreSearchResults() async {
    if (!_isSearching || _searchQuery.isEmpty) return;
    
    setState(() => _isLoading = true);
    final results = await _mangaService.searchManga(_searchQuery, page: _currentPage, allowAdult: _allowAdult);
    setState(() {
      _manga = results;
      _isLoading = false;
    });
    _scrollToTop();
  }

  Future<void> _fetchLikedManga() async {
    setState(() {
      _isLoading = true;
      _isShowingLiked = true;
    });
    final liked = await _mangaService.getLikedManga();
    setState(() {
      _manga = liked;
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
    if (_isSearching) {
      _loadMoreSearchResults();
    } else {
      _fetchManga();
    }
  }

  void _prevPage() {
    if (_currentPage > 1) {
      setState(() => _currentPage--);
      if (_isSearching) {
        _loadMoreSearchResults();
      } else {
        _fetchManga();
      }
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
                        await _fetchLikedManga();
                      } else {
                        await _fetchManga();
                      }
                      await _loadHistory();
                    },
                    color: AppTheme.primaryColor,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          _buildContinueReading(),
                          _buildBody(),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!_isShowingLiked && _selectedGenre == null) _buildPagination(),
            if (!_isShowingLiked && _selectedGenre != null) _buildPagination(),
              ],
            ),
            if (_isGenreDropdownOpen)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isGenreDropdownOpen = false;
                  });
                },
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            if (_isGenreDropdownOpen)
              Positioned(
                top: 140,
                right: 24,
                child: _buildGenreMenu(),
              ),
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
            'Manga',
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
                _fetchManga();
              } else {
                _fetchLikedManga();
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: _searchManga,
              onChanged: (value) {
                setState(() {}); // Update UI for clear button
              },
              decoration: InputDecoration(
                hintText: 'Search manga...',
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
                          _currentPage = 1;
                          _fetchManga();
                          setState(() {});
                        },
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildGenreDropdown(),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() => _allowAdult = !_allowAdult);
              if (_isSearching) {
                _searchManga(_searchQuery);
              } else {
                _fetchManga();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: _allowAdult
                    ? AppTheme.primaryColor.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: _allowAdult ? AppTheme.primaryColor : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _allowAdult ? Icons.check_box : Icons.check_box_outline_blank,
                    color: _allowAdult ? AppTheme.primaryColor : Colors.white54,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '18+',
                    style: TextStyle(
                      color: _allowAdult ? AppTheme.primaryColor : Colors.white54,
                      fontSize: 13,
                      fontWeight: _allowAdult ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenreDropdown() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isGenreDropdownOpen = !_isGenreDropdownOpen;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: _isGenreDropdownOpen ? AppTheme.primaryColor : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_list, color: Colors.white54, size: 20),
            const SizedBox(width: 8),
            Text(
              _selectedGenre ?? 'Genre',
              style: TextStyle(
                color: _selectedGenre != null ? Colors.white : Colors.white54,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _isGenreDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: Colors.white54,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenreMenu() {
    return Container(
      width: 250,
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Genre',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_selectedGenre != null)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedGenre = null;
                        _isGenreDropdownOpen = false;
                        _currentPage = 1; // Reset to page 1
                      });
                      _fetchManga(); // Fetch all manga
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: MangaService.availableTags.length,
              itemBuilder: (context, index) {
                final genre = MangaService.availableTags[index];
                final isSelected = _selectedGenre == genre;
                
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedGenre = genre;
                      _isGenreDropdownOpen = false;
                      _currentPage = 1; // Reset to page 1 when changing genre
                    });
                    _fetchManga(); // Fetch with new genre
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.2) : Colors.transparent,
                    child: Row(
                      children: [
                        if (isSelected)
                          const Icon(Icons.check, color: AppTheme.primaryColor, size: 18)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            genre,
                            style: TextStyle(
                              color: isSelected ? AppTheme.primaryColor : Colors.white,
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
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
    return Center(
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
            _isShowingLiked ? 'No liked manga yet' : 'No manga found',
            style: const TextStyle(color: Colors.white70, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }
    if (_manga.isEmpty) return _buildEmptyState();

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
        itemCount: _manga.length,
        itemBuilder: (context, index) {
          final manga = _manga[index];
          final isLiked = _likedIds.contains(manga.id);
          return _MangaCard(
            manga: manga,
            isLiked: isLiked,
            onLikeChanged: () {
              _loadLikedStatus();
              if (_isShowingLiked) {
                _fetchLikedManga();
              }
            },
          );
        },
    );
  }

  Widget _buildContinueReading() {
    if (_history.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Text(
            'CONTINUE READING',
            style: TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: 12,
            ),
          ),
        ),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _history.length,
            itemBuilder: (context, index) {
              final progress = _history[index];
              final manga = Manga.fromJson(progress['manga']);
              final chapterIndex = progress['chapterIndex'] as int;
              final pageIndex = progress['pageIndex'] as int;
              final chapters = progress['chapters'] as List;
              final chapter = MangaChapter.fromJson(chapters[chapterIndex]);
              
              return Container(
                width: 300,
                margin: const EdgeInsets.only(right: 16),
                child: Stack(
                  children: [
                    FocusableControl(
                      onTap: () => _resumeReading(progress),
                      borderRadius: 12,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: manga.coverNormal,
                                width: 60,
                                height: 90,
                                fit: BoxFit.cover,
                                errorWidget: (c, u, e) => Container(
                                  width: 60,
                                  height: 90,
                                  color: Colors.white10,
                                  child: const Icon(Icons.book, color: Colors.white24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    manga.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Chapter ${chapter.number}',
                                    style: const TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Page ${pageIndex + 1}',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.play_circle_fill,
                              color: AppTheme.primaryColor,
                              size: 36,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _removeFromHistory(manga.id),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white70,
                          ),
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
}

class _MangaCard extends StatefulWidget {
  final Manga manga;
  final bool isLiked;
  final VoidCallback onLikeChanged;

  const _MangaCard({required this.manga, required this.isLiked, required this.onLikeChanged});

  @override
  State<_MangaCard> createState() => _MangaCardState();
}

class _MangaCardState extends State<_MangaCard> {
  final MangaService _mangaService = MangaService();
  bool _isHovered = false;

  Future<void> _toggleLike() async {
    await _mangaService.toggleLike(widget.manga);
    widget.onLikeChanged();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MangaDetailsScreen(manga: widget.manga),
            ),
          ).then((_) {
            if (!mounted) return;
            widget.onLikeChanged();
          });
          
          // Reload history when screen becomes visible again
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final mangaScreenState = context.findAncestorStateOfType<_MangaScreenState>();
              if (mangaScreenState != null) {
                mangaScreenState._loadHistory();
              }
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.diagonal3Values(_isHovered ? 1.05 : 1.0, _isHovered ? 1.05 : 1.0, 1.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _isHovered ? 0.1 : 0.05),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CachedNetworkImage(
                      imageUrl: widget.manga.coverNormal,
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
                          widget.manga.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.manga.type.toUpperCase(),
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
                child: GestureDetector(
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
      ),
    );
  }
}
