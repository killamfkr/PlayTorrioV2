import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/tmdb_api.dart';
import '../api/stremio_service.dart';
import '../api/settings_service.dart';
import '../models/movie.dart';
import '../services/my_list_service.dart';
import '../utils/app_theme.dart';
import 'details_screen.dart';
import 'streaming_details_screen.dart';
import 'main_screen.dart';

/// A single result section that streams in dynamically.
class _SearchSection {
  final String key;
  final String title;
  final String? icon; // network icon URL (for addon sections)
  final bool isTmdb;
  List<dynamic> results; // Movie for TMDB, Map<String,dynamic> for addons

  _SearchSection({
    required this.key,
    required this.title,
    this.icon,
    this.isTmdb = false,
    List<dynamic>? results,
  }) : results = results ?? [];
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final TmdbApi _api = TmdbApi();
  final StremioService _stremio = StremioService();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  String _query = '';

  /// All search-capable addon providers (loaded once).
  List<Map<String, dynamic>> _addonProviders = [];

  /// Currently visible sections (populated dynamically as results arrive).
  final List<_SearchSection> _sections = [];

  /// Track which search generation we're on to discard stale results.
  int _searchGeneration = 0;

  /// True while at least one provider hasn't responded yet.
  bool _isSearching = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadProviders();
    MainScreen.stremioSearchNotifier.addListener(_onExternalSearch);
  }

  Future<void> _loadProviders() async {
    final catalogs = await _stremio.getAllCatalogs();
    final Map<String, Map<String, dynamic>> providers = {};
    for (final c in catalogs) {
      if (c['supportsSearch'] != true) continue;
      final key = c['addonBaseUrl'] as String;
      if (!providers.containsKey(key)) {
        providers[key] = {
          'id': key,
          'name': c['addonName'],
          'icon': c['addonIcon'],
          'baseUrl': key,
          'catalogs': <Map<String, dynamic>>[],
        };
      }
      (providers[key]!['catalogs'] as List).add(c);
    }
    if (mounted) {
      setState(() => _addonProviders = providers.values.toList());
    }
  }

  void _onExternalSearch() async {
    final data = MainScreen.stremioSearchNotifier.value;
    if (data == null || (data['query'] ?? '').isEmpty) return;
    final query = data['query']!;
    if (_addonProviders.isEmpty) await _loadProviders();
    if (mounted) {
      _controller.text = query;
      _onSearchChanged(query);
    }
  }

  void _onSearchChanged(String query) {
    setState(() => _query = query);
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _sections.clear();
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performUnifiedSearch(query);
    });
  }

  /// Fire all search APIs in parallel; results stream in as they arrive.
  Future<void> _performUnifiedSearch(String query) async {
    if (query.trim().isEmpty) return;

    final gen = ++_searchGeneration;
    setState(() {
      _sections.clear();
      _isSearching = true;
    });

    int pendingCount = 1 + _addonProviders.length; // TMDB + each addon

    void decPending() {
      pendingCount--;
      if (pendingCount <= 0 && gen == _searchGeneration && mounted) {
        setState(() => _isSearching = false);
      }
    }

    // ── TMDB ──
    _searchTmdb(query, gen).then((_) => decPending());

    // ── Stremio Addons ──
    for (final provider in _addonProviders) {
      _searchAddon(query, provider, gen).then((_) => decPending());
    }
  }

  Future<void> _searchTmdb(String query, int gen) async {
    try {
      final results = await _api.searchMulti(query);
      if (gen != _searchGeneration || !mounted) return;

      final movies = results.where((m) => m.mediaType == 'movie').toList();
      final shows = results.where((m) => m.mediaType == 'tv').toList();

      setState(() {
        if (movies.isNotEmpty) {
          _sections.insert(0, _SearchSection(
            key: 'tmdb_movies',
            title: 'TMDB Movies',
            isTmdb: true,
            results: movies,
          ));
        }
        if (shows.isNotEmpty) {
          // Insert after tmdb_movies if it exists, else at 0
          final idx = _sections.indexWhere((s) => s.key == 'tmdb_movies');
          _sections.insert(idx >= 0 ? idx + 1 : 0, _SearchSection(
            key: 'tmdb_shows',
            title: 'TMDB Shows',
            isTmdb: true,
            results: shows,
          ));
        }
      });
    } catch (e) {
      debugPrint('TMDB search error: $e');
    }
  }

  Future<void> _searchAddon(String query, Map<String, dynamic> provider, int gen) async {
    final providerBaseUrl = provider['baseUrl'] as String;
    final providerName = provider['name'] as String;
    final providerIcon = provider['icon']?.toString() ?? '';
    final catalogs = provider['catalogs'] as List<Map<String, dynamic>>;

    // Group results by type (movie / series)
    final Map<String, List<Map<String, dynamic>>> byType = {};

    await Future.wait(catalogs.map((cat) async {
      try {
        final results = await _stremio.getCatalog(
          baseUrl: cat['addonBaseUrl'],
          type: cat['catalogType'],
          id: cat['catalogId'],
          search: query,
        );
        for (final r in results) {
          r['_addonBaseUrl'] = providerBaseUrl;
          r['_addonName'] = providerName;
        }
        final type = cat['catalogType']?.toString() ?? 'other';
        byType.putIfAbsent(type, () => []);
        byType[type]!.addAll(results);
      } catch (_) {}
    }));

    if (gen != _searchGeneration || !mounted) return;

    setState(() {
      for (final entry in byType.entries) {
        // Deduplicate within this type
        final seen = <String>{};
        final deduped = entry.value.where((r) {
          final id = r['id']?.toString() ?? '';
          if (id.isEmpty || seen.contains(id)) return false;
          seen.add(id);
          return true;
        }).toList();

        if (deduped.isEmpty) continue;

        final typeLabel = entry.key == 'series' ? 'Shows' : (entry.key == 'movie' ? 'Movies' : entry.key);
        _sections.add(_SearchSection(
          key: '${providerBaseUrl}_${entry.key}',
          title: '$providerName $typeLabel',
          icon: providerIcon,
          results: deduped,
        ));
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Navigation helpers (unchanged from original)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _openDetails(Movie movie) async {
    final settings = SettingsService();
    final isStreaming = await settings.isStreamingModeEnabled();
    if (!mounted) return;
    if (isStreaming) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => StreamingDetailsScreen(movie: movie)));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(movie: movie)));
    }
  }

  Future<void> _openStremioItem(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    final type = item['type']?.toString() ?? 'movie';
    final name = item['name']?.toString() ?? 'Unknown';
    final poster = item['poster']?.toString() ?? '';
    final isCustomId = !id.startsWith('tt');
    final isCollection = id.startsWith('ctmdb.') || type == 'collections';

    if (!isCustomId && !isCollection) {
      try {
        final movie = await _api.findByImdbId(id, mediaType: type == 'series' ? 'tv' : 'movie');
        if (movie != null && mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(movie: movie, stremioItem: item)));
          return;
        }
      } catch (_) {}
    }

    if (!isCustomId && !isCollection) {
      try {
        final results = await _api.searchMulti(name);
        if (results.isNotEmpty && mounted) {
          final match = results.firstWhere(
            (m) => m.title.toLowerCase() == name.toLowerCase(),
            orElse: () => results.first,
          );
          Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(movie: match, stremioItem: item)));
          return;
        }
      } catch (_) {}
    }

    if (mounted) {
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
      final updatedItem = Map<String, dynamic>.from(item);
      if (isCollection) updatedItem['type'] = 'collections';
      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsScreen(movie: movie, stremioItem: updatedItem)));
    }
  }

  @override
  void dispose() {
    MainScreen.stremioSearchNotifier.removeListener(_onExternalSearch);
    _controller.dispose();
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onSearchChanged,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: "Search movies, shows...",
            hintStyle: const TextStyle(color: Colors.white38),
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white70),
                    onPressed: () {
                      _controller.clear();
                      _onSearchChanged('');
                    },
                  )
                : const Icon(Icons.search, color: Colors.white70),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) return _buildEmpty();
    if (_sections.isEmpty && _isSearching) {
      return Center(child: CircularProgressIndicator(color: AppTheme.current.primaryColor));
    }
    if (_sections.isEmpty && !_isSearching) return _buildEmpty();

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _sections.length + (_isSearching ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _sections.length) {
          // Loading indicator at the bottom while more results are coming
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24))),
          );
        }
        final section = _sections[index];
        return _buildSliderSection(section);
      },
    );
  }

  Widget _buildSliderSection(_SearchSection section) {
    final cardWidth = MediaQuery.of(context).size.width > 600 ? 140.0 : 120.0;
    final cardHeight = cardWidth * 1.5;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (section.icon != null && section.icon!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: section.icon!,
                      width: 20, height: 20,
                      errorWidget: (_, _, _) => const Icon(Icons.extension, size: 16, color: Colors.white38),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (section.isTmdb) ...[
                  const Icon(Icons.movie, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                ],
                Text(
                  section.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${section.results.length}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Horizontal slider with scroll arrows
          _ScrollableSlider(
            height: cardHeight + 32,
            itemCount: section.results.length,
            cardWidth: cardWidth,
            itemBuilder: (context, index) {
              final item = section.results[index];
              if (item is Movie) {
                return SizedBox(
                  width: cardWidth,
                  child: _SearchCard(movie: item, onTap: () => _openDetails(item)),
                );
              } else {
                final map = item as Map<String, dynamic>;
                return SizedBox(
                  width: cardWidth,
                  child: _StremioSearchCard(item: map, onTap: () => _openStremioItem(map)),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 80, color: Colors.white.withValues(alpha: 0.05)),
          const SizedBox(height: 16),
          Text(
            _query.isEmpty ? "Search for your favorite content" : "No results found",
            style: const TextStyle(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Scrollable slider with left/right arrows
// ═════════════════════════════════════════════════════════════════════════════

class _ScrollableSlider extends StatefulWidget {
  final double height;
  final int itemCount;
  final double cardWidth;
  final IndexedWidgetBuilder itemBuilder;

  const _ScrollableSlider({
    required this.height,
    required this.itemCount,
    required this.cardWidth,
    required this.itemBuilder,
  });

  @override
  State<_ScrollableSlider> createState() => _ScrollableSliderState();
}

class _ScrollableSliderState extends State<_ScrollableSlider> {
  final ScrollController _scrollController = ScrollController();
  bool _showLeft = false;
  bool _showRight = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateArrows);
  }

  void _updateArrows() {
    if (!mounted) return;
    final pos = _scrollController.position;
    final newLeft = pos.pixels > 10;
    final newRight = pos.pixels < pos.maxScrollExtent - 10;
    if (newLeft != _showLeft || newRight != _showRight) {
      setState(() {
        _showLeft = newLeft;
        _showRight = newRight;
      });
    }
  }

  void _scroll(double direction) {
    final target = _scrollController.offset + direction * (widget.cardWidth + 12) * 3;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: widget.itemBuilder,
          ),
          // Left arrow
          if (_showLeft)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _ArrowButton(
                icon: Icons.chevron_left,
                onTap: () => _scroll(-1),
                alignment: Alignment.centerLeft,
              ),
            ),
          // Right arrow
          if (_showRight && widget.itemCount > 2)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _ArrowButton(
                icon: Icons.chevron_right,
                onTap: () => _scroll(1),
                alignment: Alignment.centerRight,
              ),
            ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Alignment alignment;

  const _ArrowButton({required this.icon, required this.onTap, required this.alignment});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        alignment: alignment,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: alignment == Alignment.centerLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: alignment == Alignment.centerLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              AppTheme.bgDark.withValues(alpha: 0.9),
              AppTheme.bgDark.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Result Cards
// ═════════════════════════════════════════════════════════════════════════════

class _SearchCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;

  const _SearchCard({required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = movie.posterPath.isNotEmpty ? TmdbApi.getImageUrl(movie.posterPath) : '';

    return FocusableControl(
      onTap: onTap,
      borderRadius: 12,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppTheme.bgCard),
                errorWidget: (_, _, _) => const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
              )
            else
              Center(child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(movie.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              )),

            if (movie.voteAverage > 0)
              Positioned(
                top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(movie.voteAverage.toStringAsFixed(1), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber)),
                ),
              ),

            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Text(
                  movie.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),

            Positioned(
              top: 6, left: 6,
              child: _AddToMyListButton(movie: movie),
            ),
          ],
        ),
      ),
    );
  }
}

class _StremioSearchCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _StremioSearchCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final poster = item['poster']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Unknown';
    final rating = item['imdbRating']?.toString() ?? '';
    final type = item['type']?.toString() ?? '';

    return FocusableControl(
      onTap: onTap,
      borderRadius: 12,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (poster.isNotEmpty)
              CachedNetworkImage(
                imageUrl: poster,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppTheme.bgCard),
                errorWidget: (_, _, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white38)),
                  ),
                ),
              )
            else
              Center(child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white38)),
              )),

            if (type.isNotEmpty)
              Positioned(
                top: 5, left: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: type == 'series' ? Colors.blue.withValues(alpha: 0.7) : AppTheme.current.primaryColor.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(type.toUpperCase(), style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),

            if (rating.isNotEmpty)
              Positioned(
                top: 5, right: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 9, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(rating, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber)),
                    ],
                  ),
                ),
              ),

            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),

            Positioned(
              bottom: 30, right: 5,
              child: _AddToMyListStremioButton(item: item),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My List button helpers for search cards
// ─────────────────────────────────────────────────────────────────────────────

class _AddToMyListButton extends StatelessWidget {
  final Movie movie;
  const _AddToMyListButton({required this.movie});

  @override
  Widget build(BuildContext context) {
    final uid = MyListService.movieId(movie.id, movie.mediaType);
    return ValueListenableBuilder<int>(
      valueListenable: MyListService.changeNotifier,
      builder: (context, _, _) {
        final inList = MyListService().contains(uid);
        return GestureDetector(
          onTap: () async {
            final added = await MyListService().toggleMovie(
              tmdbId: movie.id,
              imdbId: movie.imdbId,
              title: movie.title,
              posterPath: movie.posterPath,
              mediaType: movie.mediaType,
              voteAverage: movie.voteAverage,
              releaseDate: movie.releaseDate,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(added ? 'Added to My List' : 'Removed from My List'),
                duration: const Duration(seconds: 1),
              ));
            }
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              inList ? Icons.bookmark : Icons.add,
              size: 16,
              color: inList ? AppTheme.primaryColor : Colors.white70,
            ),
          ),
        );
      },
    );
  }
}

class _AddToMyListStremioButton extends StatelessWidget {
  final Map<String, dynamic> item;
  const _AddToMyListStremioButton({required this.item});

  @override
  Widget build(BuildContext context) {
    final uid = MyListService.stremioItemId(item);
    return ValueListenableBuilder<int>(
      valueListenable: MyListService.changeNotifier,
      builder: (context, _, _) {
        final inList = MyListService().contains(uid);
        return GestureDetector(
          onTap: () async {
            final added = await MyListService().toggleStremioItem(item);
            if (context.mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(added ? 'Added to My List' : 'Removed from My List'),
                duration: const Duration(seconds: 1),
              ));
            }
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              inList ? Icons.bookmark : Icons.add,
              size: 16,
              color: inList ? AppTheme.primaryColor : Colors.white70,
            ),
          ),
        );
      },
    );
  }
}
