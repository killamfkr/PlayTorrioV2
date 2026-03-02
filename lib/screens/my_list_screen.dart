import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/my_list_service.dart';
import '../api/tmdb_api.dart';
import '../api/settings_service.dart';
import '../models/movie.dart';
import '../utils/app_theme.dart';
import 'details_screen.dart';
import 'streaming_details_screen.dart';

class MyListScreen extends StatefulWidget {
  const MyListScreen({super.key});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  final MyListService _myList = MyListService();
  final TmdbApi _api = TmdbApi();
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _items = _myList.items;
    MyListService.changeNotifier.addListener(_onListChanged);
  }

  void _onListChanged() {
    if (mounted) {
      setState(() => _items = _myList.items);
    }
  }

  @override
  void dispose() {
    MyListService.changeNotifier.removeListener(_onListChanged);
    super.dispose();
  }

  Future<void> _openItem(Map<String, dynamic> item) async {
    final settings = SettingsService();
    final isStreaming = await settings.isStreamingModeEnabled();
    if (!mounted) return;

    final source = item['source']?.toString() ?? 'tmdb';
    final tmdbId = item['tmdbId'] as int?;
    final imdbId = item['imdbId']?.toString();
    final title = item['title']?.toString() ?? 'Unknown';
    final poster = item['posterPath']?.toString() ?? '';
    final mediaType = item['mediaType']?.toString() ?? 'movie';

    // TMDB source — we have the tmdbId directly
    if (source == 'tmdb' && tmdbId != null) {
      try {
        final Movie details;
        if (mediaType == 'tv') {
          details = await _api.getTvDetails(tmdbId);
        } else {
          details = await _api.getMovieDetails(tmdbId);
        }
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => isStreaming
                ? StreamingDetailsScreen(movie: details)
                : DetailsScreen(movie: details),
          ));
          return;
        }
      } catch (_) {}
    }

    // Stremio source or fallback — try IMDB lookup
    if (imdbId != null && imdbId.startsWith('tt')) {
      try {
        final movie = await _api.findByImdbId(imdbId, mediaType: mediaType == 'series' ? 'tv' : mediaType);
        if (movie != null && mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => isStreaming
                ? StreamingDetailsScreen(movie: movie)
                : DetailsScreen(movie: movie),
          ));
          return;
        }
      } catch (_) {}
    }

    // Last resort — build a Movie from saved data
    if (mounted) {
      final movie = Movie(
        id: tmdbId ?? title.hashCode,
        imdbId: imdbId,
        title: title,
        posterPath: poster,
        backdropPath: poster,
        voteAverage: (item['voteAverage'] as num?)?.toDouble() ?? 0,
        releaseDate: item['releaseDate']?.toString() ?? '',
        mediaType: mediaType == 'series' ? 'tv' : mediaType,
      );
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => isStreaming
            ? StreamingDetailsScreen(movie: movie)
            : DetailsScreen(movie: movie),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;
    final crossAxisCount = isDesktop ? 6 : (screenWidth > 600 ? 4 : 3);

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App bar
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: AppTheme.bgDark,
            title: Row(
              children: [
                const Icon(Icons.bookmark, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                const Text('My List', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Text(
                  '${_items.length} items',
                  style: const TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),

          // Empty state
          if (_items.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_border, size: 80, color: Colors.white.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    const Text(
                      'Your list is empty',
                      style: TextStyle(color: Colors.white38, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap the + button on any movie or show to add it here',
                      style: TextStyle(color: Colors.white24, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2 / 3,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = _items[index];
                    return _MyListCard(
                      item: item,
                      onTap: () => _openItem(item),
                      onRemove: () async {
                        await _myList.remove(item['uniqueId']);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Removed "${item['title']}" from My List'),
                              duration: const Duration(seconds: 2),
                              action: SnackBarAction(
                                label: 'UNDO',
                                onPressed: () {
                                  // Re-add the item
                                  if (item['source'] == 'stremio') {
                                    _myList.addStremioItem({
                                      'name': item['title'],
                                      'poster': item['posterPath'],
                                      'type': item['stremioType'] ?? item['mediaType'],
                                      'imdb_id': item['imdbId'],
                                      'imdbRating': item['voteAverage']?.toString(),
                                      'releaseInfo': item['releaseDate'],
                                    });
                                  } else {
                                    _myList.addMovie(
                                      tmdbId: item['tmdbId'] ?? 0,
                                      imdbId: item['imdbId'],
                                      title: item['title'] ?? '',
                                      posterPath: item['posterPath'] ?? '',
                                      mediaType: item['mediaType'] ?? 'movie',
                                      voteAverage: (item['voteAverage'] as num?)?.toDouble() ?? 0,
                                      releaseDate: item['releaseDate'] ?? '',
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                        }
                      },
                    );
                  },
                  childCount: _items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My List Card
// ─────────────────────────────────────────────────────────────────────────────

class _MyListCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _MyListCard({required this.item, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final title = item['title']?.toString() ?? 'Unknown';
    final poster = item['posterPath']?.toString() ?? '';
    final mediaType = item['mediaType']?.toString() ?? 'movie';
    final source = item['source']?.toString() ?? 'tmdb';
    final rating = (item['voteAverage'] as num?)?.toDouble() ?? 0;

    // TMDB relative paths start with "/" and need the base URL
    final imageUrl = source == 'tmdb' && poster.startsWith('/')
        ? TmdbApi.getImageUrl(poster)
        : poster;

    return FocusableControl(
      onTap: onTap,
      borderRadius: 12,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3))],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Poster image
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppTheme.bgCard),
                errorWidget: (_, _, _) => Container(
                  color: AppTheme.bgCard,
                  child: Center(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white38))),
                ),
              )
            else
              Container(
                color: AppTheme.bgCard,
                child: Center(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white38))),
              ),

            // Gradient
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.55, 1.0],
                ),
              ),
            ),

            // Rating badge
            if (rating > 0)
              Positioned(
                top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 10, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
                    ],
                  ),
                ),
              ),

            // Type badge
            Positioned(
              top: 6, left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: mediaType == 'tv' || mediaType == 'series'
                      ? Colors.blue.withValues(alpha: 0.7)
                      : AppTheme.primaryColor.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  mediaType == 'tv' || mediaType == 'series' ? 'TV' : 'MOVIE',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),

            // Title
            Positioned(
              bottom: 8, left: 8, right: 28,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),

            // Remove button — must be AFTER title so it renders on top
            Positioned(
              bottom: 4, right: 4,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
