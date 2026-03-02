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

  // Providers: 'tmdb' or addon baseUrl key
  List<Map<String, dynamic>> _searchProviders = [];
  String _selectedProvider = 'tmdb';

  List<Movie> _tmdbResults = [];
  List<Map<String, dynamic>> _stremioResults = [];
  bool _isLoading = false;
  Timer? _debounce;
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadProviders();
    MainScreen.stremioSearchNotifier.addListener(_onExternalSearch);
  }

  void _onExternalSearch() async {
    final data = MainScreen.stremioSearchNotifier.value;
    if (data == null || (data['query'] ?? '').isEmpty) return;
    final query = data['query']!;
    final requestedAddonBaseUrl = data['addonBaseUrl'] ?? '';

    // Ensure providers are loaded before selecting one
    if (_searchProviders.length <= 1) {
      await _loadProviders();
    }

    // Try to select the exact addon that triggered the search
    Map<String, dynamic> addonProvider;
    if (requestedAddonBaseUrl.isNotEmpty) {
      final match = _searchProviders.cast<Map<String, dynamic>?>().firstWhere(
        (p) => p!['id'] == requestedAddonBaseUrl,
        orElse: () => null,
      );
      addonProvider = match ?? _searchProviders.firstWhere(
        (p) => p['id'] != 'tmdb',
        orElse: () => _searchProviders.isNotEmpty ? _searchProviders.first : {'id': 'tmdb'},
      );
    } else {
      // Fall back to the first non-TMDB addon
      addonProvider = _searchProviders.firstWhere(
        (p) => p['id'] != 'tmdb',
        orElse: () => _searchProviders.isNotEmpty ? _searchProviders.first : {'id': 'tmdb'},
      );
    }

    if (mounted) {
      setState(() {
        _selectedProvider = addonProvider['id'] as String;
        _controller.text = query;
        _query = query;
        _tmdbResults = [];
        _stremioResults = [];
      });
      // Directly trigger search (bypass debounce)
      _debounce?.cancel();
      _performSearch(query);
    }
  }

  /// Immediately performs a search without debouncing.
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      if (_selectedProvider == 'tmdb') {
        final results = await _api.searchMulti(query);
        if (mounted) setState(() => _tmdbResults = results);
      } else {
        final provider = _searchProviders.firstWhere((p) => p['id'] == _selectedProvider);
        final providerBaseUrl = provider['baseUrl'] as String;
        final providerName = provider['name'] as String;
        final catalogs = provider['catalogs'] as List<Map<String, dynamic>>;
        final List<Map<String, dynamic>> allResults = [];

        await Future.wait(catalogs.map((cat) async {
          try {
            final results = await _stremio.getCatalog(
              baseUrl: cat['addonBaseUrl'],
              type: cat['catalogType'],
              id: cat['catalogId'],
              search: query,
            );
            // Tag each result with the addon that provided it
            for (final r in results) {
              r['_addonBaseUrl'] = providerBaseUrl;
              r['_addonName'] = providerName;
            }
            allResults.addAll(results);
          } catch (_) {}
        }));

        final seen = <String>{};
        final deduped = allResults.where((r) {
          final id = r['id']?.toString() ?? '';
          if (seen.contains(id)) return false;
          seen.add(id);
          return true;
        }).toList();

        if (mounted) setState(() => _stremioResults = deduped);
      }
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProviders() async {
    final catalogs = await _stremio.getAllCatalogs();
    // Collect unique addons that support search
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
      setState(() {
        _searchProviders = [
          {'id': 'tmdb', 'name': 'TMDB', 'icon': ''},
          ...providers.values,
        ];
      });
    }
  }

  void _onSearchChanged(String query) {
    setState(() => _query = query);

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _tmdbResults = [];
            _stremioResults = [];
          });
        }
        return;
      }
      _performSearch(query);
    });
  }

  void _changeProvider(String providerId) {
    setState(() {
      _selectedProvider = providerId;
      _tmdbResults = [];
      _stremioResults = [];
    });
    if (_query.isNotEmpty) {
      _onSearchChanged(_query);
    }
  }

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

    // For IMDB IDs, try TMDB lookup first for a richer details page
    if (!isCustomId) {
      try {
        final movie = await _api.findByImdbId(id, mediaType: type == 'series' ? 'tv' : 'movie');
        if (movie != null && mounted) {
          // Always use DetailsScreen for Stremio items (pass stremioItem to preserve addon context)
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => DetailsScreen(
              movie: movie,
              stremioItem: item,
            ),
          ));
          return;
        }
      } catch (_) {}
    }

    // If it's a custom ID, or IMDB lookup failed, try name search
    if (!isCustomId) {
      try {
        final results = await _api.searchMulti(name);
        if (results.isNotEmpty && mounted) {
          final match = results.firstWhere(
            (m) => m.title.toLowerCase() == name.toLowerCase(),
            orElse: () => results.first,
          );
          // Always use DetailsScreen for Stremio items
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => DetailsScreen(
              movie: match,
              stremioItem: item,
            ),
          ));
          return;
        }
      } catch (_) {}
    }

    // Custom ID or all lookups failed: open DetailsScreen with stremioItem
    if (mounted) {
      final movie = Movie(
        id: id.hashCode,
        imdbId: id.startsWith('tt') ? id : null,
        title: name,
        posterPath: poster, // full URL from Stremio
        backdropPath: item['background']?.toString() ?? poster,
        voteAverage: double.tryParse(item['imdbRating']?.toString() ?? '') ?? 0,
        releaseDate: item['releaseInfo']?.toString() ?? '',
        overview: item['description']?.toString() ?? '',
        mediaType: type == 'series' ? 'tv' : 'movie',
      );
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => DetailsScreen(
          movie: movie,
          stremioItem: item, // pass the full item with _addonBaseUrl, id, etc.
        ),
      ));
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 1200 ? 6 : (width > 900 ? 5 : (width > 600 ? 4 : 3));

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
      body: Column(
        children: [
          // Provider selector
          if (_searchProviders.length > 1) _buildProviderSelector(),
          // Results
          Expanded(child: _buildResults(crossAxisCount)),
        ],
      ),
    );
  }

  Widget _buildProviderSelector() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _searchProviders.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final provider = _searchProviders[index];
          final isSelected = provider['id'] == _selectedProvider;
          final icon = provider['icon']?.toString() ?? '';

          return GestureDetector(
            onTap: () => _changeProvider(provider['id']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.2) : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.primaryColor : Colors.white12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: icon,
                        width: 18, height: 18,
                        errorWidget: (_, _, _) => const Icon(Icons.extension, size: 16, color: Colors.white38),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ] else if (provider['id'] == 'tmdb') ...[
                    const Icon(Icons.movie, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    provider['name'],
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResults(int crossAxisCount) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }

    // TMDB results
    if (_selectedProvider == 'tmdb') {
      if (_tmdbResults.isEmpty) return _buildEmpty();
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 2 / 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _tmdbResults.length,
        itemBuilder: (context, index) {
          final movie = _tmdbResults[index];
          return _SearchCard(movie: movie, onTap: () => _openDetails(movie));
        },
      );
    }

    // Stremio results
    if (_stremioResults.isEmpty) return _buildEmpty();
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _stremioResults.length,
      itemBuilder: (context, index) {
        final item = _stremioResults[index];
        return _StremioSearchCard(item: item, onTap: () => _openStremioItem(item));
      },
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
                top: 8, right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(movie.voteAverage.toStringAsFixed(1), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
                ),
              ),

            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Text(
                  movie.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ),

            // My List add/remove button
            Positioned(
              top: 8, left: 8,
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
                    child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white38)),
                  ),
                ),
              )
            else
              Center(child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white38)),
              )),

            if (type.isNotEmpty)
              Positioned(
                top: 6, left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: type == 'series' ? Colors.blue.withValues(alpha: 0.7) : AppTheme.primaryColor.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(type.toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),

            if (rating.isNotEmpty)
              Positioned(
                top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 10, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(rating, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
                    ],
                  ),
                ),
              ),

            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ),

            // My List add/remove button
            Positioned(
              bottom: 34, right: 6,
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
      builder: (context, _, __) {
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
      builder: (context, _, __) {
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
