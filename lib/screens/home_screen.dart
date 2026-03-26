import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../api/tmdb_api.dart';
import '../api/settings_service.dart';
import '../api/stremio_service.dart';
import '../api/stream_extractor.dart';
import '../api/stream_providers.dart';
import '../api/amri_extractor.dart';
import '../api/torrent_stream_service.dart';
import '../api/debrid_api.dart';
import '../api/trakt_service.dart';
import '../api/webstreamr_service.dart';
import '../services/watch_history_service.dart';
import '../services/my_list_service.dart';
import '../models/movie.dart';
import '../utils/app_theme.dart';
import 'details_screen.dart';
import 'streaming_details_screen.dart';
import 'player_screen.dart';
import 'stremio_catalog_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  final TmdbApi _api = TmdbApi();
  final StremioService _stremio = StremioService();
  final PageController _heroController = PageController();
  
  late Future<List<Movie>> _trendingFuture;
  late Future<List<Movie>> _popularFuture;
  late Future<List<Movie>> _topRatedFuture;
  late Future<List<Movie>> _nowPlayingFuture;
  
  Timer? _heroTimer;
  int _heroIndex = 0;

  // Stremio catalog data
  List<Map<String, dynamic>> _stremioCatalogs = [];
  final Map<String, List<Map<String, dynamic>>> _catalogItems = {};
  bool _catalogsLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _trendingFuture = _api.getTrending();
    _popularFuture = _api.getPopular();
    _topRatedFuture = _api.getTopRated();
    _nowPlayingFuture = _api.getNowPlaying();
    
    _startHeroTimer();
    _loadStremioCatalogs();

    // Reload catalogs whenever addons are added/removed in Settings
    SettingsService.addonChangeNotifier.addListener(_onAddonsChanged);

    // Trakt auto-sync (runs once per session, no-op if not logged in)
    TraktService().fullSync();
  }

  void _startHeroTimer() {
    _heroTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (_heroController.hasClients) {
        final next = (_heroIndex + 1) % 5;
        _heroController.animateToPage(
          next,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOutCubic,
        );
        setState(() => _heroIndex = next);
      }
    });
  }

  void _onAddonsChanged() {
    // Clear stale data and schedule a rebuild so the old sliders disappear
    // immediately while the new ones load.
    setState(() {
      _stremioCatalogs = [];
      _catalogItems.clear();
      _catalogsLoaded = false;
    });
    _loadStremioCatalogs();
  }

  @override
  void dispose() {
    SettingsService.addonChangeNotifier.removeListener(_onAddonsChanged);
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  Future<void> _openDetails(Movie movie) async {
    final settings = SettingsService();
    final isStreaming = await settings.isStreamingModeEnabled();
    
    if (!mounted) return;

    if (isStreaming) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => StreamingDetailsScreen(movie: movie)));
    } else {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(movie: movie)));
    }
  }

  Future<void> _loadStremioCatalogs() async {
    try {
      final catalogs = await _stremio.getAllCatalogs();
      if (!mounted || catalogs.isEmpty) return;

      // Group non-search-required catalogs by addon, preserving order.
      final Map<String, List<Map<String, dynamic>>> byAddon = {};
      for (final c in catalogs) {
        if (c['searchRequired'] == true) continue;
        final key = c['addonBaseUrl'] as String;
        byAddon.putIfAbsent(key, () => []).add(c);
      }

      // Mark that we've started loading so the build can show shimmer / placeholders.
      if (mounted) setState(() => _catalogsLoaded = true);

      // For each addon, try catalogs in order until one returns items.
      // All addons are tried in parallel; within each addon they are tried sequentially.
      await Future.wait(byAddon.values.map((addonCatalogs) async {
        for (final cat in addonCatalogs) {
          try {
            final items = await _stremio.getCatalog(
              baseUrl: cat['addonBaseUrl'],
              type: cat['catalogType'],
              id: cat['catalogId'],
            );
            if (items.isEmpty) continue; // try next catalog for this addon

            // Tag each item with the addon that provided it
            for (final item in items) {
              item['_addonBaseUrl'] = cat['addonBaseUrl'];
              item['_addonName'] = cat['addonName'];
            }
            if (mounted) {
              final itemKey = '${cat['addonBaseUrl']}/${cat['catalogType']}/${cat['catalogId']}';
              setState(() {
                // Add the winning catalog to the list if not already present
                if (!_stremioCatalogs.any((c) =>
                    c['addonBaseUrl'] == cat['addonBaseUrl'] &&
                    c['catalogId'] == cat['catalogId'])) {
                  _stremioCatalogs = [..._stremioCatalogs, cat];
                }
                _catalogItems[itemKey] = items;
              });
            }
            return; // done for this addon
          } catch (_) {}
        }
      }));
    } catch (e) {
      debugPrint('[HomeScreen] Error loading Stremio catalogs: $e');
    }
  }

  void _openStremioCatalog(Map<String, dynamic> catalog) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StremioCatalogScreen(initialCatalog: catalog)),
    );
  }

  Future<void> _openStremioItem(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    final type = item['type']?.toString() ?? 'movie';
    final name = item['name']?.toString() ?? 'Unknown';
    final poster = item['poster']?.toString() ?? '';
    final isCustomId = !id.startsWith('tt');
    
    // Check if this is a collection by ID prefix
    final isCollection = id.startsWith('ctmdb.') || type == 'collections';

    // IMDB ID → TMDB lookup
    if (!isCustomId && !isCollection) {
      try {
        final movie = await _api.findByImdbId(id, mediaType: type == 'series' ? 'tv' : 'movie');
        if (movie != null && mounted) {
          // Always use DetailsScreen for Stremio items
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => DetailsScreen(movie: movie, stremioItem: item),
          ));
          return;
        }
      } catch (_) {}
    }

    // For non-custom IDs that failed, try name search
    if (!isCustomId && !isCollection) {
      try {
        final results = await _api.searchMulti(name);
        if (results.isNotEmpty && mounted) {
          final match = results.firstWhere(
            (m) => m.title.toLowerCase() == name.toLowerCase(),
            orElse: () => results.first,
          );
          // Always use DetailsScreen for Stremio items
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => DetailsScreen(movie: match, stremioItem: item),
          ));
          return;
        }
      } catch (_) {}
    }

    // Custom ID, collection, or all lookups failed
    if (mounted) {
      // Override type to 'collections' if it's a collection ID
      final actualType = isCollection ? 'collections' : (type == 'series' ? 'tv' : 'movie');
      
      final movie = Movie(
        id: id.hashCode,
        imdbId: id.startsWith('tt') ? id : null,
        title: name,
        posterPath: poster,
        backdropPath: item['background']?.toString() ?? poster,
        voteAverage: double.tryParse(item['imdbRating']?.toString() ?? '') ?? 0,
        releaseDate: item['releaseInfo']?.toString() ?? '',
        overview: item['description']?.toString() ?? '',
        mediaType: actualType,
      );
      
      // Update the stremioItem type to collections if needed
      final updatedItem = Map<String, dynamic>.from(item);
      if (isCollection) {
        updatedItem['type'] = 'collections';
      }
      
      // Always use DetailsScreen for Stremio items
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => DetailsScreen(movie: movie, stremioItem: updatedItem),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppTheme.bgDark,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. Hero Section
          SliverToBoxAdapter(
            child: FutureBuilder<List<Movie>>(
              future: _trendingFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildHeroShimmer();
                }
                final movies = snapshot.data!.take(5).toList();
                return _buildHeroCarousel(movies);
              },
            ),
          ),

          // 2. Content Sections
          SliverToBoxAdapter(
            child: Column(
              children: [
                const _ContinueWatchingSection(),
                _MovieSection(title: 'Trending Now', icon: Icons.local_fire_department_rounded, future: _trendingFuture, onMovieTap: _openDetails),
                _MovieSection(title: 'Popular Movies', icon: Icons.movie_filter_rounded, future: _popularFuture, onMovieTap: _openDetails, isPortrait: true, showRank: true),
                // ── Stremio Addon Catalogs ──
                if (_catalogsLoaded)
                  ..._stremioCatalogs.map((cat) {
                    final key = '${cat['addonBaseUrl']}/${cat['catalogType']}/${cat['catalogId']}';
                    final items = _catalogItems[key];
                    if (items == null || items.isEmpty) return const SizedBox.shrink();
                    return _StremioCatalogSection(
                      catalog: cat,
                      items: items,
                      onItemTap: _openStremioItem,
                      onShowAll: () => _openStremioCatalog(cat),
                    );
                  }),
                _MovieSection(title: 'Top Rated', icon: Icons.star_rounded, future: _topRatedFuture, onMovieTap: _openDetails),
                _MovieSection(title: 'New Releases', icon: Icons.new_releases_rounded, future: _nowPlayingFuture, onMovieTap: _openDetails, isPortrait: true),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }
// ... (rest of file is same until _ContinueWatchingSection) ...

// I need to update _ContinueWatchingSection separately or I can try to replace the whole file? No, replace partial.
// The above block replaces _HomeScreenState entirely. I will use it.


  Widget _buildHeroShimmer() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Container(
      height: isLandscape ? MediaQuery.of(context).size.height * 0.55 : MediaQuery.of(context).size.height * 0.72,
      color: AppTheme.bgCard,
    );
  }

  Widget _buildHeroCarousel(List<Movie> movies) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final height = isLandscape ? MediaQuery.of(context).size.height * 0.55 : MediaQuery.of(context).size.height * 0.72;
    final heroMovie = movies[_heroIndex];
    
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // Background image with parallax-like crossfade
          PageView.builder(
            controller: _heroController,
            itemCount: movies.length,
            onPageChanged: (i) => setState(() => _heroIndex = i),
            itemBuilder: (context, index) {
              final movie = movies[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: movie.backdropPath.isNotEmpty 
                        ? TmdbApi.getImageUrl(movie.backdropPath) 
                        : TmdbApi.getImageUrl(movie.posterPath),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    placeholder: (c, u) => Container(color: AppTheme.bgCard),
                  ),
                  // Multi-layer gradient for depth
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppTheme.bgDark.withValues(alpha: 0.15),
                          AppTheme.bgDark.withValues(alpha: 0.7),
                          AppTheme.bgDark,
                        ],
                        stops: const [0.0, 0.35, 0.75, 1.0],
                      ),
                    ),
                  ),
                  // Side vignette
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          AppTheme.bgDark.withValues(alpha: 0.5),
                          Colors.transparent,
                          Colors.transparent,
                          AppTheme.bgDark.withValues(alpha: 0.3),
                        ],
                        stops: const [0.0, 0.2, 0.8, 1.0],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          
          // Content overlay
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Genre chips
                  if (heroMovie.genres.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: heroMovie.genres.take(3).map((g) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Text(g, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                        )).toList(),
                      ),
                    ),
                  // Title
                  Text(
                    heroMovie.title,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      shadows: [const Shadow(color: Colors.black, blurRadius: 30)],
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // Meta row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                            const SizedBox(width: 3),
                            Text(
                              heroMovie.voteAverage.toStringAsFixed(1),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (heroMovie.releaseDate.isNotEmpty)
                        Text(
                          heroMovie.releaseDate.split('-').first,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      if (heroMovie.mediaType == 'tv') ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('TV SERIES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                        ),
                      ],
                    ],
                  ),
                  // Synopsis
                  if (heroMovie.overview.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        heroMovie.overview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  // Action buttons
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _openDetails(heroMovie),
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                        label: const Text("Watch Now"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 8,
                          shadowColor: AppTheme.primaryColor.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: IconButton(
                          onPressed: () => _openDetails(heroMovie),
                          icon: const Icon(Icons.info_outline_rounded, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MyListButton.movie(movie: heroMovie),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Page indicator
                  Center(
                    child: SmoothPageIndicator(
                      controller: _heroController,
                      count: movies.length,
                      effect: WormEffect(
                        activeDotColor: AppTheme.primaryColor,
                        dotColor: Colors.white.withValues(alpha: 0.2),
                        dotHeight: 6,
                        dotWidth: 6,
                        spacing: 8,
                      ),
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
}

class _MovieSection extends StatefulWidget {
  final String title;
  final IconData? icon;
  final Future<List<Movie>> future;
  final Function(Movie) onMovieTap;
  final bool isPortrait;
  final bool showRank;

  const _MovieSection({
    required this.title,
    this.icon,
    required this.future,
    required this.onMovieTap,
    this.isPortrait = false,
    this.showRank = false,
  });

  @override
  State<_MovieSection> createState() => _MovieSectionState();
}

class _MovieSectionState extends State<_MovieSection> {
  final ScrollController _scrollController = ScrollController();

  void _scrollLeft() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.offset - 600,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _scrollRight() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.offset + 600,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Movie>>(
      future: widget.future,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          // Shimmer placeholder while loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(height: 20, width: 140, decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(6))),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: widget.isPortrait ? 240 : 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: 5,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (_, _) => Container(
                        width: widget.isPortrait ? 150 : 280,
                        decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        }
        final movies = snapshot.data!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
              child: Row(
                children: [
                  // Accent bar
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: AppTheme.primaryColor, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                  ),
                  FocusableControl(
                    onTap: _scrollLeft,
                    borderRadius: 20,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FocusableControl(
                    onTap: _scrollRight,
                    borderRadius: 20,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: widget.isPortrait ? 260 : 190,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: movies.length,
                separatorBuilder: (_, _) => SizedBox(width: widget.showRank ? 6 : 14),
                itemBuilder: (context, index) => _MovieCard(
                  movie: movies[index],
                  onTap: () => widget.onMovieTap(movies[index]),
                  isPortrait: widget.isPortrait,
                  rank: widget.showRank ? index + 1 : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MovieCard extends StatelessWidget {
  final Movie movie;
  final bool isPortrait;
  final int? rank;
  final VoidCallback onTap;

  const _MovieCard({
    required this.movie,
    this.isPortrait = false,
    this.rank,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;
    
    final cardWidth = isPortrait 
        ? (isDesktop ? 165.0 : 140.0) 
        : (isDesktop ? 320.0 : 270.0);
        
    final image = isPortrait ? movie.posterPath : movie.backdropPath;
    final imageUrl = image.isNotEmpty ? TmdbApi.getImageUrl(image) : '';
    final hasRank = rank != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Big rank number
        if (hasRank)
          Text(
            '$rank',
            style: TextStyle(
              fontSize: isPortrait ? 110 : 80,
              fontWeight: FontWeight.w900,
              color: Colors.white.withValues(alpha: 0.08),
              height: 0.85,
              letterSpacing: -6,
            ),
          ),
        FocusableControl(
          onTap: onTap,
          borderRadius: 14,
          child: Container(
            width: cardWidth,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 6)),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (c, u) => Container(color: AppTheme.bgCard),
                    errorWidget: (c, u, e) => Container(
                      color: AppTheme.bgCard,
                      child: Center(child: Text(movie.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white24))),
                    ),
                  )
                else
                  Container(
                    color: AppTheme.bgCard,
                    child: Center(child: Text(movie.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white24))),
                  ),
                
                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                        Colors.black.withValues(alpha: 0.95),
                      ],
                      stops: const [0.0, 0.45, 0.8, 1.0],
                    ),
                  ),
                ),
                
                // Rating badge (top right)
                if (movie.voteAverage > 0)
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            movie.voteAverage.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bottom content
                Positioned(
                  bottom: 10, left: 10, right: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        movie.title,
                        maxLines: isPortrait ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white, 
                          fontWeight: FontWeight.bold, 
                          fontSize: isDesktop ? 14 : 13,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (movie.releaseDate.isNotEmpty)
                            Text(
                              movie.releaseDate.split('-').first,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                            ),
                          if (movie.mediaType == 'tv') ...[
                            if (movie.releaseDate.isNotEmpty) ...[
                              Text('  •  ', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
                            ],
                            Text('TV', style: TextStyle(color: AppTheme.primaryColor.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // My List button
                Positioned(
                  top: 8, left: 8,
                  child: _MyListButton.movie(movie: movie),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueWatchingSection extends StatefulWidget {
  const _ContinueWatchingSection();

  @override
  State<_ContinueWatchingSection> createState() => _ContinueWatchingSectionState();
}

class _ContinueWatchingSectionState extends State<_ContinueWatchingSection> {
  final ScrollController _scrollController = ScrollController();
  String? _loadingItemId;

  void _scrollLeft() {
    _scrollController.animateTo(
      _scrollController.offset - 600,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _scrollRight() {
    _scrollController.animateTo(
      _scrollController.offset + 600,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resumePlayback(Map<String, dynamic> item) async {
    final uniqueId = item['uniqueId'] as String;
    if (_loadingItemId != null) return;
    
    setState(() => _loadingItemId = uniqueId);

    try {
      final method = item['method'] as String;
      final tmdbId = item['tmdbId'] as int;
      final season = item['season'] as int?;
      final episode = item['episode'] as int?;
      final title = item['title'] as String;
      final posterPath = item['posterPath'] as String; 
      final startPos = Duration(milliseconds: item['position'] as int);
      
      // Get saved magnet link and file index for torrents
      final savedMagnetLink = item['magnetLink'] as String?;
      final savedFileIndex = item['fileIndex'] as int?;

      String? streamUrl;
      String? activeProvider;
      String? magnetLink;
      int? fileIndex;
      String? stremioItemId;
      String? stremioAddonBase;

      if (method == 'stremio_direct') {
        // Direct stremio stream — try the saved URL first
        final savedUrl = item['streamUrl'] as String?;
        stremioItemId = item['stremioId'] as String?;
        stremioAddonBase = item['stremioAddonBaseUrl'] as String?;
        activeProvider = 'stremio_direct';

        if (savedUrl != null && savedUrl.isNotEmpty) {
          // Try playing the saved URL directly
          streamUrl = savedUrl;
          debugPrint('[Resume] Trying saved stremio direct URL: $savedUrl');
        }

        // If no saved URL, or if player fails, we'll fall through to the
        // "open details page" fallback below
        if (streamUrl == null && stremioItemId != null && stremioAddonBase != null) {
          // Re-fetch streams from the addon
          debugPrint('[Resume] Re-fetching stremio streams for $stremioItemId from $stremioAddonBase');
          final stremioType = item['stremioType'] as String? ?? (season != null ? 'series' : 'movie');
          final stremio = StremioService();
          try {
            final streams = await stremio.getStreams(
              baseUrl: stremioAddonBase,
              type: stremioType,
              id: stremioItemId,
            );
            if (streams.isNotEmpty) {
              final first = streams.first;
              if (first is Map<String, dynamic> && first['url'] != null) {
                streamUrl = first['url'] as String;
              }
            }
          } catch (e) {
            debugPrint('[Resume] Re-fetch stremio streams failed: $e');
          }
        }

        // If we still have nothing, open the details page
        if (streamUrl == null) {
          if (mounted) {
            final mediaType = item['mediaType'] as String? ?? (season != null ? 'tv' : 'movie');
            final movie = Movie(
              id: tmdbId,
              title: title,
              posterPath: posterPath,
              backdropPath: '',
              overview: '',
              releaseDate: '',
              voteAverage: 0,
              mediaType: mediaType,
              genres: [],
              imdbId: item['imdbId'],
            );
            Map<String, dynamic>? stremioItem;
            if (stremioItemId != null) {
              stremioItem = {
                'id': stremioItemId,
                '_addonBaseUrl': stremioAddonBase ?? '',
                'type': item['stremioType'] ?? (season != null ? 'series' : 'movie'),
                'name': title,
              };
            }
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => DetailsScreen(movie: movie, stremioItem: stremioItem),
            ));
          }
          return; // Skip the player launch below
        }
      } else if (method == 'stream') {
        // Re-extract stream using saved sourceId (tmdbId + season + episode)
        final sourceId = item['sourceId'] as String;
        activeProvider = sourceId;
        
        if (sourceId == 'webstreamr') {
          debugPrint('[Resume] Using WebStreamrService for $title');
          final webStreamr = WebStreamrService();
          final imdbId = item['imdbId']?.toString() ?? '';
          if (imdbId.isNotEmpty) {
            final webStreamrSources = await webStreamr.getStreams(
              imdbId: imdbId,
              isMovie: season == null,
              season: season,
              episode: episode,
            );
            if (webStreamrSources.isNotEmpty) {
              streamUrl = webStreamrSources.first.url;
              if (mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      streamUrl: streamUrl!,
                      title: title,
                      movie: Movie(
                        id: tmdbId,
                        title: title,
                        posterPath: posterPath,
                        backdropPath: '', 
                        overview: '', 
                        releaseDate: '', 
                        voteAverage: 0, 
                        mediaType: season != null ? 'tv' : 'movie', 
                        genres: [], 
                        imdbId: imdbId,
                      ),
                      selectedSeason: season,
                      selectedEpisode: episode,
                      activeProvider: 'webstreamr',
                      startPosition: startPos,
                      sources: webStreamrSources,
                    ),
                  ),
                );
                return;
              }
            }
          }
        }

        final provider = StreamProviders.providers[sourceId];
        if (provider == null) {
           throw Exception("Provider $sourceId not available");
        }

        debugPrint('[Resume] Re-extracting stream for $title (TMDB: $tmdbId, S:$season, E:$episode)');
        final url = season != null && episode != null
            ? provider['tv'](tmdbId, season, episode)
            : provider['movie'](tmdbId);
        
        final extractor = StreamExtractor();
        final result = await extractor.extract(url, timeout: const Duration(seconds: 20));
        streamUrl = result?.url;
      } else if (method == 'amri') {
        // Re-extract AMRI using tmdbId + season + episode
        activeProvider = 'AMRI';
        debugPrint('[Resume] Re-extracting AMRI for $title (TMDB: $tmdbId, S:$season, E:$episode)');
        final amriExtractor = AmriExtractor(
          onLog: (message) => debugPrint('[AMRI Resume] $message'),
        );
        
        final year = item['year']?.toString() ?? '';
        
        final sourcesData = await amriExtractor.extractSources(
          tmdbId.toString(),
          title,
          year,
          season: season,
          episode: episode,
        );
        
        if (sourcesData['sources'] != null && sourcesData['sources'].isNotEmpty) {
          final sources = sourcesData['sources'] as List;
          streamUrl = sources.first['url'] as String?;
        }
      } else if (method == 'torrent') {
        // Use saved magnet link - NEVER re-search
        magnetLink = savedMagnetLink;
        fileIndex = savedFileIndex;
        
        if (magnetLink == null || magnetLink.isEmpty) {
          throw Exception("No magnet link saved for this torrent");
        }
        
        debugPrint('[Resume] Using saved magnet link: ${magnetLink.substring(0, 60)}...');
        debugPrint('[Resume] Using saved file index: $fileIndex');

        // Check Debrid Preference
        final useDebridSetting = await SettingsService().useDebridForStreams();
        final debridService = await SettingsService().getDebridService();
        final useDebrid = useDebridSetting && debridService != 'None';

        if (useDebrid) {
          debugPrint('[Resume] Using debrid service: $debridService');
          if (debridService == 'Real-Debrid') {
             final files = await DebridApi().resolveRealDebrid(magnetLink);
             if (fileIndex != null && fileIndex < files.length) {
               // Use saved file index
               streamUrl = files[fileIndex].downloadUrl;
               debugPrint('[Resume] Using file at index $fileIndex: ${files[fileIndex].filename}');
             } else {
               // Fallback to largest file
               files.sort((a, b) => b.filesize.compareTo(a.filesize));
               if (files.isNotEmpty) streamUrl = files.first.downloadUrl;
             }
          } else if (debridService == 'TorBox') {
             final files = await DebridApi().resolveTorBox(magnetLink);
             if (fileIndex != null && fileIndex < files.length) {
               streamUrl = files[fileIndex].downloadUrl;
               debugPrint('[Resume] Using file at index $fileIndex: ${files[fileIndex].filename}');
             } else {
               files.sort((a, b) => b.filesize.compareTo(a.filesize));
               if (files.isNotEmpty) streamUrl = files.first.downloadUrl;
             }
          } else {
             throw Exception("No Debrid service configured");
          }
        } else {
          // Local Torrent Engine
          debugPrint('[Resume] Using local torrent engine');
          streamUrl = await TorrentStreamService().streamTorrent(magnetLink, season: season, episode: episode, fileIdx: fileIndex);
        }
      } else if (method == 'trakt_import') {
        // Trakt-imported items have no stream source — find one automatically
        if (context.mounted) {
          final mediaType = item['mediaType'] as String? ?? (season != null ? 'tv' : 'movie');
          final movie = Movie(
            id: tmdbId,
            title: title,
            posterPath: posterPath,
            backdropPath: '',
            overview: '',
            releaseDate: '',
            voteAverage: 0,
            mediaType: mediaType,
            genres: [],
            imdbId: item['imdbId'],
          );
          final navigator = Navigator.of(context);
          final isStreaming = await SettingsService().isStreamingModeEnabled();
          navigator.push(MaterialPageRoute(
            builder: (_) => isStreaming
                ? StreamingDetailsScreen(
                    movie: movie,
                    initialSeason: season,
                    initialEpisode: episode,
                    startPosition: startPos,
                  )
                : DetailsScreen(
                    movie: movie,
                    initialSeason: season,
                    initialEpisode: episode,
                  ),
          ));
        }
        return;
      }

      if (streamUrl != null && mounted) {
        // Launch Player
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              streamUrl: streamUrl!,
              title: title,
              movie: Movie(
                id: tmdbId,
                title: title,
                posterPath: posterPath,
                backdropPath: '', 
                overview: '', 
                releaseDate: '', 
                voteAverage: 0, 
                mediaType: season != null ? 'tv' : 'movie', 
                genres: [], 
                imdbId: item['imdbId'],
              ),
              selectedSeason: season,
              selectedEpisode: episode,
              magnetLink: magnetLink,
              fileIndex: fileIndex, // Pass file index to player
              activeProvider: activeProvider,
              startPosition: startPos,
              stremioId: stremioItemId,
              stremioAddonBaseUrl: stremioAddonBase,
            ),
          ),
        );
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to load video")));
      }
    } catch (e) {
      debugPrint('[Resume] Error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _loadingItemId = null);
    }
  }

  Future<void> _removeItem(Map<String, dynamic> item) async {
    await WatchHistoryService().removeItem(item['uniqueId']);

    // Also remove from Trakt playback progress if logged in
    final tmdbId = item['tmdbId'] as int?;
    if (tmdbId != null) {
      final mediaType = item['mediaType']?.toString() ?? 'movie';
      final season = item['season'] as int?;
      final episode = item['episode'] as int?;
      await TraktService().removePlaybackProgress(
        tmdbId: tmdbId,
        mediaType: mediaType,
        season: season,
        episode: episode,
      );
    }
  }

  /// Opens the details page for a history item based on streaming mode and item type
  Future<void> _openHistoryItemDetails(Map<String, dynamic> item) async {
    final tmdbId = item['tmdbId'] as int;
    final title = item['title'] as String;
    final posterPath = item['posterPath'] as String;
    final season = item['season'] as int?;
    final episode = item['episode'] as int?;
    final mediaType = item['mediaType'] as String? ?? (season != null ? 'tv' : 'movie');
    
    final movie = Movie(
      id: tmdbId,
      title: title,
      posterPath: posterPath,
      backdropPath: '',
      overview: '',
      releaseDate: '',
      voteAverage: 0,
      mediaType: mediaType,
      genres: [],
      imdbId: item['imdbId'],
    );

    final isStreamingMode = await SettingsService().isStreamingModeEnabled();
    
    // Determine which screen to open based on streaming mode and item type
    if (isStreamingMode) {
      // Streaming mode ON -> always open StreamingDetailsScreen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StreamingDetailsScreen(
              movie: movie,
              initialSeason: season,
              initialEpisode: episode,
            ),
          ),
        );
      }
    } else {
      // Streaming mode OFF
      // Check if it's a Stremio addon with custom ID
      final stremioItemId = item['stremioId'] as String?;
      final stremioAddonBase = item['stremioAddonBaseUrl'] as String?;
      final isCustomId = stremioItemId != null && 
                         stremioAddonBase != null && 
                         !stremioItemId.startsWith('tt');
      
      if (isCustomId) {
        // Stremio addon with custom ID -> open DetailsScreen (torrent mode)
        Map<String, dynamic>? stremioItem = {
          'id': stremioItemId,
          '_addonBaseUrl': stremioAddonBase,
          'type': item['stremioType'] ?? (season != null ? 'series' : 'movie'),
          'name': title,
        };
        
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetailsScreen(
                movie: movie,
                stremioItem: stremioItem,
                initialSeason: season,
                initialEpisode: episode,
              ),
            ),
          );
        }
      } else {
        // Regular content -> open DetailsScreen (torrent mode)
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetailsScreen(
                movie: movie,
                initialSeason: season,
                initialEpisode: episode,
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: WatchHistoryService().historyStream,
      initialData: WatchHistoryService().current,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        final history = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.deepPurpleAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.play_circle_outline_rounded, color: Colors.deepPurpleAccent, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text("Continue Watching", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
                  ),
                  if (history.isNotEmpty) ...[
                    FocusableControl(
                      onTap: _scrollLeft,
                      borderRadius: 20,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 16),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FocusableControl(
                      onTap: _scrollRight,
                      borderRadius: 20,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              height: MediaQuery.of(context).orientation == Orientation.landscape ? 140 : 175,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: history.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final historyItem = history[index];
                  final itemId = historyItem['uniqueId'] as String;
                  return _HistoryCard(
                    item: historyItem,
                    onTap: () => _resumePlayback(historyItem),
                    onRemove: () => _removeItem(historyItem),
                    onInfo: () => _openHistoryItemDetails(historyItem),
                    isLoading: _loadingItemId == itemId,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onInfo;
  final bool isLoading;

  const _HistoryCard({
    required this.item,
    required this.onTap,
    required this.onRemove,
    required this.onInfo,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final posterPath = item['posterPath'] as String;
    final title = item['title'] as String;
    final season = item['season'] as int?;
    final episode = item['episode'] as int?;
    final episodeTitle = item['episodeTitle'] as String?;
    final position = item['position'] as int;
    final duration = item['duration'] as int;
    
    final progress = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;
    final remaining = duration > 0 ? Duration(milliseconds: duration - position) : Duration.zero;
    final remainingText = remaining.inMinutes > 0 ? '${remaining.inMinutes}m left' : '';
    final imageUrl = posterPath.isNotEmpty
        ? (posterPath.startsWith('http') ? posterPath : TmdbApi.getImageUrl(posterPath))
        : '';
    
    final subtitle = season != null 
        ? 'S$season E$episode${episodeTitle != null && episodeTitle.isNotEmpty ? ' • $episodeTitle' : ''}'
        : '';

    return FocusableControl(
      onTap: isLoading ? () {} : onTap,
      borderRadius: 14,
      child: Container(
        width: 280,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Full bleed poster image
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (c, u) => Container(color: AppTheme.bgCard),
              )
            else
              Container(color: AppTheme.bgCard, child: const Icon(Icons.movie, color: Colors.white24, size: 40)),
            
            // Dark overlay gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.95),
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                ),
              ),
            ),

            // Play button (center)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.3), blurRadius: 16, spreadRadius: 2)],
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
              ),
            ),

            // Top-right actions
            Positioned(
              top: 6, right: 6,
              child: Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onRemove,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.white70, size: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onInfo,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                        child: const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom content: title + episode + progress
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        if (subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                            ),
                          ),
                        if (remainingText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              remainingText,
                              style: TextStyle(color: Colors.deepPurpleAccent.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Progress bar
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      color: Colors.deepPurpleAccent,
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
            ),
            
            if (isLoading)
               Container(
                 decoration: BoxDecoration(
                   color: Colors.black.withValues(alpha: 0.6),
                   borderRadius: BorderRadius.circular(14),
                 ),
                 child: const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
               ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  STREMIO ADDON CATALOG SECTION
// ═══════════════════════════════════════════════════════════════════════════════

class _StremioCatalogSection extends StatefulWidget {
  final Map<String, dynamic> catalog;
  final List<Map<String, dynamic>> items;
  final Function(Map<String, dynamic>) onItemTap;
  final VoidCallback onShowAll;

  const _StremioCatalogSection({
    required this.catalog,
    required this.items,
    required this.onItemTap,
    required this.onShowAll,
  });

  @override
  State<_StremioCatalogSection> createState() => _StremioCatalogSectionState();
}

class _StremioCatalogSectionState extends State<_StremioCatalogSection> {
  final ScrollController _scrollController = ScrollController();

  void _scrollLeft() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.offset - 600,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _scrollRight() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.offset + 600,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.catalog;
    final addonName = cat['addonName'] as String;
    final catalogName = cat['catalogName'] as String;
    final addonIcon = (cat['addonIcon'] ?? '').toString();
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              if (addonIcon.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: addonIcon,
                    width: 20, height: 20,
                    errorWidget: (_, _, _) => const Icon(Icons.extension, size: 20, color: Colors.white38),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      catalogName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                    ),
                    Text(
                      addonName,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                    ),
                  ],
                ),
              ),
              FocusableControl(
                onTap: widget.onShowAll,
                borderRadius: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Show All', style: TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 11, color: AppTheme.primaryColor),
                    ],
                  ),
                ),
              ),
              if (isDesktop) ...[
                const SizedBox(width: 10),
                FocusableControl(
                  onTap: _scrollLeft,
                  borderRadius: 20,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 16),
                  ),
                ),
                const SizedBox(width: 4),
                FocusableControl(
                  onTap: _scrollRight,
                  borderRadius: 20,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: isDesktop ? 240 : 200,
          child: ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: widget.items.length.clamp(0, 20),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return _StremioCatalogCard(
                item: item,
                onTap: () => widget.onItemTap(item),
                height: isDesktop ? 240 : 200,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StremioCatalogCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final double height;

  const _StremioCatalogCard({required this.item, required this.onTap, this.height = 200});

  @override
  Widget build(BuildContext context) {
    final poster = item['poster']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Unknown';
    final rating = item['imdbRating']?.toString() ?? '';
    final shape = item['posterShape']?.toString() ?? 'poster';

    final double width;
    if (shape == 'landscape') {
      width = height * (16 / 9);
    } else if (shape == 'square') {
      width = height;
    } else {
      width = height * (2 / 3);
    }

    return FocusableControl(
      onTap: onTap,
      borderRadius: 14,
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (poster.isNotEmpty)
              CachedNetworkImage(
                imageUrl: poster,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppTheme.bgCard),
                errorWidget: (_, _, _) => Container(
                  color: AppTheme.bgCard,
                  child: Center(child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white38))),
                ),
              )
            else
              Center(child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white38))),

            // Improved gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                    Colors.black.withValues(alpha: 0.95),
                  ],
                  stops: const [0.0, 0.4, 0.75, 1.0],
                ),
              ),
            ),

            // Rating badge
            if (rating.isNotEmpty)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(rating, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
              ),

            // Name
            Positioned(
              bottom: 10, left: 10, right: 10,
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, height: 1.2),
              ),
            ),

            // My List button
            Positioned(
              top: 8, left: 8,
              child: _MyListButton.stremio(stremioItem: item),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared My List add/remove button used on movie & stremio cards
// ─────────────────────────────────────────────────────────────────────────────

class _MyListButton extends StatelessWidget {
  final Movie? movie;
  final Map<String, dynamic>? stremioItem;

  const _MyListButton.movie({required Movie this.movie}) : stremioItem = null;
  const _MyListButton.stremio({required Map<String, dynamic> this.stremioItem}) : movie = null;

  String get _uniqueId {
    if (movie != null) return MyListService.movieId(movie!.id, movie!.mediaType);
    return MyListService.stremioItemId(stremioItem!);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MyListService.changeNotifier,
      builder: (context, _, _) {
        final inList = MyListService().contains(_uniqueId);
        return GestureDetector(
          onTap: () async {
            if (movie != null) {
              final added = await MyListService().toggleMovie(
                tmdbId: movie!.id,
                imdbId: movie!.imdbId,
                title: movie!.title,
                posterPath: movie!.posterPath,
                mediaType: movie!.mediaType,
                voteAverage: movie!.voteAverage,
                releaseDate: movie!.releaseDate,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(added ? 'Added to My List' : 'Removed from My List'),
                  duration: const Duration(seconds: 1),
                ));
              }
            } else if (stremioItem != null) {
              final added = await MyListService().toggleStremioItem(stremioItem!);
              if (context.mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(added ? 'Added to My List' : 'Removed from My List'),
                  duration: const Duration(seconds: 1),
                ));
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(
              inList ? Icons.bookmark_rounded : Icons.add_rounded,
              size: 16,
              color: inList ? AppTheme.primaryColor : Colors.white70,
            ),
          ),
        );
      },
    );
  }
}
