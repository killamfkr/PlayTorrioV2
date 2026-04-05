import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../api/tmdb_api.dart';
import '../screens/details_screen.dart';
import '../screens/streaming_details_screen.dart';
import '../api/settings_service.dart';
import '../services/my_list_service.dart';
import '../utils/app_theme.dart';
import '../utils/extensions.dart';
import '../utils/performance_tuning.dart';

class HeroBanner extends StatefulWidget {
  final List<Movie> movies;

  /// When set (e.g. Android TV split layout), fixes carousel height to the parent constraint.
  final double? height;

  const HeroBanner({super.key, required this.movies, this.height});

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  int _currentIndex = 0;
  final CarouselSliderController _carouselController = CarouselSliderController();

  @override
  Widget build(BuildContext context) {
    if (widget.movies.isEmpty) return const SizedBox.shrink();

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final heroHeight = widget.height ??
        (isMobile ? screenHeight * 0.6 : screenHeight * 0.75);
    final featuredMovies = widget.movies.take(5).toList();
    final autoAdvance =
        !PerformanceTuning.skipHomeHeroAutoAdvance && !AppTheme.isLightMode;

    return Focus(
      child: Stack(
        children: [
          CarouselSlider(
            carouselController: _carouselController,
            options: CarouselOptions(
              height: heroHeight,
              viewportFraction: 1.0,
              autoPlay: autoAdvance,
              autoPlayInterval: const Duration(seconds: 8),
              autoPlayAnimationDuration: const Duration(milliseconds: 1000),
              autoPlayCurve: Curves.fastOutSlowIn,
              enableInfiniteScroll: featuredMovies.length > 1,
              onPageChanged: (index, reason) {
                setState(() {
                  _currentIndex = index;
                });
              },
            ),
            items: featuredMovies.map((movie) {
              final imageUrl = TmdbApi.getBackdropUrl(movie.backdropPath);
              return InkWell(
                onTap: () => _navigateToDetails(movie),
                focusColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. High-Res Background
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      placeholder: (context, url) => Container(color: const Color(0xFF0F0418)),
                      errorWidget: (context, url, error) => Container(color: const Color(0xFF0F0418)),
                    ),
                    
                    // 2. Cinematic Gradient Overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF0F0418).withValues(alpha: 0.2),
                            const Color(0xFF0F0418).withValues(alpha: 0.8),
                            const Color(0xFF0F0418),
                          ],
                          stops: const [0.0, 0.4, 0.8, 1.0],
                        ),
                      ),
                    ),

                    // 3. Side Gradient for text readability (Desktop)
                    if (!isMobile)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              const Color(0xFF0F0418).withValues(alpha: 0.8),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.5],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),

        // Content
        Positioned(
          bottom: 40,
          left: isMobile ? 24 : 60,
          right: isMobile ? 24 : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              SizedBox(
                width: isMobile ? null : screenWidth * 0.5,
                child: Text(
                  featuredMovies[_currentIndex].title,
                  style: TextStyle(
                    fontSize: isMobile ? 32 : 56,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.1,
                    shadows: [
                      Shadow(
                        blurRadius: 20.0,
                        color: Colors.black.withValues(alpha: 0.5),
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
              
              // Metadata
              Row(
                children: [
                  _buildBadge(
                    'TMDB ${featuredMovies[_currentIndex].voteAverage.toStringAsFixed(1)}', 
                    Colors.amber, 
                    Icons.star
                  ),
                  const SizedBox(width: 12),
                  _buildBadge(
                    featuredMovies[_currentIndex].releaseDate.take(4), 
                    Colors.white70, 
                    Icons.calendar_today
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _navigateToDetails(featuredMovies[_currentIndex]),
                    icon: const Icon(Icons.play_arrow_rounded, size: 28),
                    label: const Text('Play Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 8,
                      shadowColor: AppTheme.primaryColor.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _HeroMyListButton(movie: featuredMovies[_currentIndex]),
                ],
              ),
            ],
          ),
        ),

        // Indicators
        Positioned(
          bottom: 20,
          right: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: featuredMovies.asMap().entries.map((entry) {
              return GestureDetector(
                onTap: () => _carouselController.animateToPage(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: _currentIndex == entry.key ? 24.0 : 8.0,
                  height: 8.0,
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _currentIndex == entry.key 
                        ? AppTheme.primaryColor 
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

}

/// My List toggle for the hero (matches home screen behaviour).
class _HeroMyListButton extends StatelessWidget {
  final Movie movie;

  const _HeroMyListButton({required this.movie});

  @override
  Widget build(BuildContext context) {
    final uniqueId = MyListService.movieId(movie.id, movie.mediaType);
    return ValueListenableBuilder<int>(
      valueListenable: MyListService.changeNotifier,
      builder: (context, _, __) {
        final inList = MyListService().contains(uniqueId);
        return OutlinedButton.icon(
          onPressed: () async {
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
          icon: Icon(inList ? Icons.bookmark_rounded : Icons.add_rounded, size: 24),
          label: Text(inList ? 'In My List' : 'My List'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24, width: 2),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.black.withValues(alpha: 0.3),
          ),
        );
      },
    );
  }
}

extension _HeroBannerNavigate on _HeroBannerState {
  Future<void> _navigateToDetails(Movie movie) async {
    final navigator = Navigator.of(context);
    final isStreamingMode = await SettingsService().isStreamingModeEnabled();
    if (mounted) {
      navigator.push(
        MaterialPageRoute(
          builder: (context) => isStreamingMode
              ? StreamingDetailsScreen(movie: movie)
              : DetailsScreen(movie: movie),
        ),
      );
    }
  }
}


