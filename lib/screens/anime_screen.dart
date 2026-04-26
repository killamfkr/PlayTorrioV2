import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:shimmer/shimmer.dart';
import '../api/anime_service.dart';
import '../utils/app_theme.dart';
import 'anime_details_screen.dart';
import 'anime_discover_screen.dart';
import 'anime_player_screen.dart';

class AnimeScreen extends StatefulWidget {
  const AnimeScreen({super.key});

  @override
  State<AnimeScreen> createState() => _AnimeScreenState();
}

class _AnimeScreenState extends State<AnimeScreen> {
  final AnimeService _service = AnimeService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<AnimeCard> _trending = [];
  List<AnimeCard> _popular = [];
  List<AnimeCard> _topRated = [];
  List<AnimeCard> _searchResults = [];
  List<Map<String, dynamic>> _watchHistory = [];
  bool _isLoadingHome = true;
  bool _isSearching = false;
  bool _isSearchLoading = false;
  bool _isShowingLiked = false;
  bool _isAdultSearch = false;
  List<AnimeCard> _likedAnime = [];
  int _heroIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadHome();
    _loadWatchHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHome() async {
    setState(() => _isLoadingHome = true);
    try {
      final results = await Future.wait([
        _service.getTrending(perPage: 20),
        _service.getPopular(perPage: 20),
        _service.getTopRated(perPage: 20),
      ]);
      if (mounted) {
        setState(() {
          _trending = results[0];
          _popular = results[1];
          _topRated = results[2];
          _isLoadingHome = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHome = false);
    }
  }

  Future<void> _loadWatchHistory() async {
    final history = await _service.getWatchHistory();
    if (mounted) setState(() => _watchHistory = history);
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _isShowingLiked = false;
        _searchResults = [];
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _isSearchLoading = true;
      _isShowingLiked = false;
    });
    try {
      final results =
          await _service.search(query, perPage: 30, isAdult: _isAdultSearch);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearchLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearchLoading = false);
    }
  }

  void _goBackToHome() {
    setState(() {
      _isSearching = false;
      _isShowingLiked = false;
      _searchController.clear();
    });
    _scrollToTop();
  }

  Future<void> _showLiked() async {
    setState(() {
      _isShowingLiked = true;
      _isSearching = false;
      _isSearchLoading = true;
      _searchController.clear();
    });
    final liked = await _service.getLiked();
    if (mounted) {
      setState(() {
        _likedAnime = liked;
        _isSearchLoading = false;
      });
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _openDetails(AnimeCard anime) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AnimeDetailsScreen(anime: anime)),
    ).then((_) {
      _loadWatchHistory();
      if (_isShowingLiked) _showLiked();
    });
  }

  void _openDiscover() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnimeDiscoverScreen()),
    ).then((_) => _loadWatchHistory());
  }

  void _resumeWatching(Map<String, dynamic> entry) {
    final anime = AnimeCard.fromJson(entry['anime']);
    final epNum = entry['episodeNumber'] as int? ?? 1;
    final epTitle = entry['episodeTitle'] as String? ?? '';
    final provider = entry['provider'] as String? ?? 'allmanga';
    final category = entry['category'] as String? ?? 'sub';
    final episodeId = entry['episodeId'] as String? ?? '';
    final useAnimeRealms = entry['useAnimeRealms'] as bool? ?? false;
    final posMs = entry['position'] as int? ?? 0;
    final startPos = posMs > 10000 ? Duration(milliseconds: posMs) : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnimePlayerScreen(
          episodeId: episodeId,
          provider: provider,
          category: category,
          anilistId: anime.id,
          title: '${anime.displayTitle} - Ep $epNum',
          episodeTitle: epTitle,
          animeCard: anime,
          episodeNumber: epNum,
          useAnimeRealms: useAnimeRealms,
          startPosition: startPos,
        ),
      ),
    ).then((_) => _loadWatchHistory());
  }

  void _removeFromWatchHistory(int animeId, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Remove', style: TextStyle(color: Colors.white)),
        content: Text('Remove "$title" from continue watching?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _service.removeFromWatchHistory(animeId);
              _loadWatchHistory();
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildHeader(),
            _buildSearchBar(),
            _buildAdultToggle(),
            if (_isShowingLiked || _isSearching)
              _buildBackChip(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await _loadHome();
                  await _loadWatchHistory();
                },
                color: AppTheme.accentColor,
                child: _isSearching
                    ? _buildSearchResults()
                    : _isShowingLiked
                        ? _buildLikedResults()
                        : _buildHomeContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Anime icon with glow
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B9D), Color(0xFFC44DFF)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B9D).withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFF6B9D), Color(0xFFC44DFF), Color(0xFF00E5FF)],
            ).createShader(bounds),
            child: const Text(
              'Anime',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Spacer(),
          // Discover button
          GestureDetector(
            onTap: _openDiscover,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFC44DFF)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.explore_outlined, color: Colors.white, size: 16),
                  SizedBox(width: 5),
                  Text('Discover', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Liked button
          GestureDetector(
            onTap: () {
              if (_isShowingLiked) {
                _goBackToHome();
              } else {
                _showLiked();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isShowingLiked
                    ? const Color(0xFFFF6B9D).withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _isShowingLiked ? Icons.favorite : Icons.favorite_border,
                color: _isShowingLiked ? const Color(0xFFFF6B9D) : Colors.white54,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search ────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search anime...',
          hintStyle: const TextStyle(color: Colors.white30),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white30),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white30, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _goBackToHome();
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFFFF6B9D),
              width: 1.5,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onSubmitted: _doSearch,
        onChanged: (v) => setState(() {}),
      ),
    );
  }

  Widget _buildAdultToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() => _isAdultSearch = !_isAdultSearch);
              // Re-run the search with the new filter so the user sees the
              // change immediately, mirroring the Discover screen behaviour.
              if (_searchController.text.trim().isNotEmpty) {
                _doSearch(_searchController.text);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isAdultSearch
                    ? const Color(0xFFFF6B9D).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isAdultSearch
                      ? const Color(0xFFFF6B9D)
                      : Colors.white12,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isAdultSearch
                        ? Icons.eighteen_up_rating
                        : Icons.eighteen_up_rating_outlined,
                    color: _isAdultSearch
                        ? const Color(0xFFFF6B9D)
                        : Colors.white38,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '18+',
                    style: TextStyle(
                      color: _isAdultSearch
                          ? const Color(0xFFFF6B9D)
                          : Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

  Widget _buildBackChip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _goBackToHome,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B9D).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFF6B9D).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back_ios_new, size: 12, color: Color(0xFFFF6B9D)),
                  const SizedBox(width: 6),
                  Text(
                    _isShowingLiked ? 'Liked' : 'Search: ${_searchController.text}',
                    style: const TextStyle(color: Color(0xFFFF6B9D), fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Home content ──────────────────────────────────────────────────

  Widget _buildHomeContent() {
    if (_isLoadingHome) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 24),
            _buildHeroShimmer(),
            const SizedBox(height: 24),
            _buildSectionShimmer(),
            const SizedBox(height: 24),
            _buildSectionShimmer(),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero carousel
          if (_trending.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildHeroCarousel(),
          ],

          // Continue Watching
          if (_watchHistory.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildContinueWatching(),
          ],

          // Trending section
          if (_trending.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSection('Trending Now', _trending, accentColor: const Color(0xFFFF6B9D)),
          ],

          // Popular section
          if (_popular.isNotEmpty) ...[
            const SizedBox(height: 28),
            _buildSection('Popular All Time', _popular, accentColor: const Color(0xFFC44DFF)),
          ],

          // Top Rated section
          if (_topRated.isNotEmpty) ...[
            const SizedBox(height: 28),
            _buildSection('Top Rated', _topRated, accentColor: const Color(0xFF00E5FF)),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Continue Watching ─────────────────────────────────────────────

  Widget _buildContinueWatching() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF00E676).withValues(alpha: 0.4), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Continue Watching',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemCount: _watchHistory.length,
            itemBuilder: (_, i) {
              final entry = _watchHistory[i];
              final anime = AnimeCard.fromJson(entry['anime']);
              final epNum = entry['episodeNumber'] ?? 0;
              final epTitle = entry['episodeTitle'] ?? '';
              return GestureDetector(
                onTap: () => _resumeWatching(entry),
                child: Stack(
                  children: [
                    Container(
                      width: 280,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: anime.coverUrl,
                              width: 55, height: 80, fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Container(width: 55, height: 80, color: AppTheme.bgCard),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  anime.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Episode $epNum',
                                  style: const TextStyle(color: Color(0xFF00E676), fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                                if (epTitle.isNotEmpty)
                                  Text(
                                    epTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                                  ),
                              ],
                            ),
                          ),
                          const Icon(Icons.play_circle_filled, color: Color(0xFF00E676), size: 32),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => _removeFromWatchHistory(anime.id, anime.displayTitle),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.close, color: Colors.white70, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Hero Carousel ─────────────────────────────────────────────────

  Widget _buildHeroCarousel() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final heroHeight = isMobile ? 340.0 : 420.0;
    final featured = _trending.take(6).toList();

    return Stack(
      children: [
        CarouselSlider(
          options: CarouselOptions(
            height: heroHeight,
            viewportFraction: 1.0,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 7),
            autoPlayAnimationDuration: const Duration(milliseconds: 900),
            autoPlayCurve: Curves.easeInOutCubic,
            onPageChanged: (i, _) => setState(() => _heroIndex = i),
          ),
          items: featured.map((anime) {
            final img = anime.bannerImage ?? anime.coverUrl;
            return GestureDetector(
              onTap: () => _openDetails(anime),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: img,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    placeholder: (_, _) => Container(color: AppTheme.bgCard),
                    errorWidget: (_, _, _) => Container(color: AppTheme.bgCard),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppTheme.bgDark.withValues(alpha: 0.3),
                          AppTheme.bgDark.withValues(alpha: 0.85),
                          AppTheme.bgDark,
                        ],
                        stops: const [0.0, 0.4, 0.75, 1.0],
                      ),
                    ),
                  ),
                  if (!isMobile)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            AppTheme.bgDark.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.4],
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 40,
                    left: isMobile ? 20 : 50,
                    right: isMobile ? 20 : null,
                    child: SizedBox(
                      width: isMobile ? null : screenWidth * 0.45,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            anime.displayTitle,
                            style: TextStyle(
                              fontSize: isMobile ? 24 : 38,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.15,
                              shadows: [Shadow(blurRadius: 20, color: Colors.black.withValues(alpha: 0.6))],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (anime.averageScore != null)
                                _buildHeroBadge((anime.averageScore! / 10).toStringAsFixed(1), Colors.amber, Icons.star_rounded),
                              if (anime.episodes != null) ...[
                                const SizedBox(width: 8),
                                _buildHeroBadge('${anime.episodes} eps', Colors.white70, Icons.video_library_outlined),
                              ],
                              if (anime.format != null) ...[
                                const SizedBox(width: 8),
                                _buildHeroBadge(anime.format!, const Color(0xFFFF6B9D), Icons.tv_rounded),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (anime.genres.isNotEmpty)
                            Wrap(
                              spacing: 6, runSpacing: 4,
                              children: anime.genres.take(3).map((g) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                ),
                                child: Text(g, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                              )).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        Positioned(
          bottom: 16, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: featured.asMap().entries.map((e) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _heroIndex == e.key ? 22 : 7, height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: _heroIndex == e.key ? const LinearGradient(colors: [Color(0xFFFF6B9D), Color(0xFFC44DFF)]) : null,
                  color: _heroIndex == e.key ? null : Colors.white.withValues(alpha: 0.2),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── Section (horizontal scroll) ───────────────────────────────────

  Widget _buildSection(String title, List<AnimeCard> items, {Color accentColor = const Color(0xFFFF6B9D)}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(
                width: 4, height: 22,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [BoxShadow(color: accentColor.withValues(alpha: 0.4), blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 260,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemCount: items.length,
            itemBuilder: (_, i) => SizedBox(
              width: 150,
              child: AnimeCardWidget(anime: items[i], onTap: () => _openDetails(items[i])),
            ),
          ),
        ),
      ],
    );
  }

  // ── Search Results ────────────────────────────────────────────────

  Widget _buildSearchResults() {
    if (_isSearchLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B9D)));
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, color: Colors.white.withValues(alpha: 0.15), size: 64),
            const SizedBox(height: 12),
            const Text('No results found', style: TextStyle(color: Colors.white30, fontSize: 15)),
          ],
        ),
      );
    }
    return _buildGrid(_searchResults);
  }

  // ── Liked Results ─────────────────────────────────────────────────

  Widget _buildLikedResults() {
    if (_isSearchLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B9D)));
    }
    if (_likedAnime.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, color: Colors.white.withValues(alpha: 0.15), size: 64),
            const SizedBox(height: 12),
            const Text('No liked anime yet', style: TextStyle(color: Colors.white30, fontSize: 15)),
          ],
        ),
      );
    }
    return _buildGrid(_likedAnime);
  }

  // ── Grid ──────────────────────────────────────────────────────────

  Widget _buildGrid(List<AnimeCard> items) {
    return SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            int cols;
            if (width > 1200) { cols = 6; }
            else if (width > 900) { cols = 5; }
            else if (width > 600) { cols = 4; }
            else { cols = 3; }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: 0.58,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => AnimeCardWidget(
                anime: items[i],
                onTap: () => _openDetails(items[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Shimmers ──────────────────────────────────────────────────────

  Widget _buildHeroShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: Container(height: 340, color: Colors.white),
    );
  }

  Widget _buildSectionShimmer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Shimmer.fromColors(
            baseColor: Colors.white.withValues(alpha: 0.05),
            highlightColor: Colors.white.withValues(alpha: 0.1),
            child: Container(width: 150, height: 20, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 260,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemCount: 5,
            itemBuilder: (_, _) => Shimmer.fromColors(
              baseColor: Colors.white.withValues(alpha: 0.05),
              highlightColor: Colors.white.withValues(alpha: 0.1),
              child: Container(width: 150, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Anime Card Widget (public, reusable) ──────────────────────────────

class AnimeCardWidget extends StatefulWidget {
  final AnimeCard anime;
  final VoidCallback onTap;

  const AnimeCardWidget({super.key, required this.anime, required this.onTap});

  @override
  State<AnimeCardWidget> createState() => _AnimeCardWidgetState();
}

class _AnimeCardWidgetState extends State<AnimeCardWidget> {
  bool _isHovered = false;
  bool _isLiked = false;
  final _service = AnimeService();

  @override
  void initState() {
    super.initState();
    _checkLiked();
  }

  @override
  void didUpdateWidget(covariant AnimeCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anime.id != widget.anime.id) _checkLiked();
  }

  void _checkLiked() {
    _service.isLiked(widget.anime.id).then((v) {
      if (mounted) setState(() => _isLiked = v);
    });
  }

  void _toggleLike() {
    _service.toggleLike(widget.anime).then((_) => _checkLiked());
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          transform: _isHovered ? Matrix4.diagonal3Values(1.04, 1.04, 1.0) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: _isHovered
                ? [BoxShadow(color: const Color(0xFFFF6B9D).withValues(alpha: 0.3), blurRadius: 20, spreadRadius: -2)]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Cover
                widget.anime.coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: widget.anime.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: AppTheme.bgCard, child: const Center(child: Icon(Icons.movie_outlined, color: Colors.white12, size: 28))),
                        errorWidget: (_, _, _) => Container(color: AppTheme.bgCard, child: const Center(child: Icon(Icons.broken_image, color: Colors.white12, size: 28))),
                      )
                    : Container(color: AppTheme.bgCard, child: const Center(child: Icon(Icons.movie_outlined, color: Colors.white12, size: 28))),

                // Gradient
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: 0.7), Colors.black.withValues(alpha: 0.95)],
                        stops: const [0.0, 0.45, 0.75, 1.0],
                      ),
                    ),
                  ),
                ),

                // Like button (top-left)
                Positioned(
                  top: 6, left: 6,
                  child: GestureDetector(
                    onTap: _toggleLike,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked ? const Color(0xFFFF6B9D) : Colors.white54,
                        size: 14,
                      ),
                    ),
                  ),
                ),

                // Score badge (top-right)
                if (widget.anime.averageScore != null)
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: _scoreColors(widget.anime.averageScore!)),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: _scoreColors(widget.anime.averageScore!).first.withValues(alpha: 0.5), blurRadius: 6)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.white, size: 12),
                          const SizedBox(width: 2),
                          Text((widget.anime.averageScore! / 10).toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),

                // Title + info
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.anime.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2)),
                        const SizedBox(height: 4),
                        Row(children: [
                          if (widget.anime.format != null)
                            Text(widget.anime.format!, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10, fontWeight: FontWeight.w500)),
                          if (widget.anime.episodes != null) ...[
                            if (widget.anime.format != null)
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('•', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 10))),
                            Text('${widget.anime.episodes} ep', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10)),
                          ],
                        ]),
                      ],
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

  List<Color> _scoreColors(int score) {
    if (score >= 80) return [const Color(0xFF00E676), const Color(0xFF00C853)];
    if (score >= 60) return [const Color(0xFFFFD740), const Color(0xFFFFC400)];
    return [const Color(0xFFFF5252), const Color(0xFFD32F2F)];
  }
}
