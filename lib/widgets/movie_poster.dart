import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/my_list_service.dart';
import '../api/tmdb_api.dart';
import '../screens/details_screen.dart';
import '../screens/streaming_details_screen.dart';
import '../api/settings_service.dart';
import '../utils/app_theme.dart';
import '../utils/device_profile.dart';
import '../widgets/tv_interactive.dart';

class MoviePoster extends StatefulWidget {
  final Movie movie;

  const MoviePoster({super.key, required this.movie});

  @override
  State<MoviePoster> createState() => _MoviePosterState();
}

class _MoviePosterState extends State<MoviePoster> {
  bool _isHovered = false;
  bool _isFocused = false;

  Future<void> _openMovie(BuildContext context) async {
    final navigator = Navigator.of(context);
    final isStreamingMode = await SettingsService().isStreamingModeEnabled();
    if (!context.mounted) return;
    navigator.push(
      MaterialPageRoute(
        builder: (context) => isStreamingMode
            ? StreamingDetailsScreen(movie: widget.movie)
            : DetailsScreen(movie: widget.movie),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = _isHovered || _isFocused;

    final posterCore = AnimatedScale(
      scale: isActive && !AppTheme.isLightMode ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: const EdgeInsets.all(4.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: isActive ? Colors.deepPurpleAccent : Colors.white10,
            width: isActive ? 3 : 1,
          ),
          boxShadow: isActive && !AppTheme.isLightMode
              ? [
                  BoxShadow(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.4),
                    blurRadius: 15,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: TmdbApi.getImageUrl(widget.movie.posterPath),
                fit: BoxFit.cover,
                memCacheWidth: 340,
                placeholder: (context, url) => Container(
                  color: const Color(0xFF2D0C3F),
                  child:
                      const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
              AnimatedOpacity(
                opacity: isActive ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF0F0418).withValues(alpha: 0.8),
                        const Color(0xFF0F0418),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.movie.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            widget.movie.voteAverage.toStringAsFixed(1),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: ValueListenableBuilder<int>(
                  valueListenable: MyListService.changeNotifier,
                  builder: (context, _, __) {
                    final uid = MyListService.movieId(
                        widget.movie.id, widget.movie.mediaType);
                    final inList = MyListService().contains(uid);
                    return TvGestureTap(
                      borderRadius: 999,
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        final added = await MyListService().toggleMovie(
                          tmdbId: widget.movie.id,
                          imdbId: widget.movie.imdbId,
                          title: widget.movie.title,
                          posterPath: widget.movie.posterPath,
                          mediaType: widget.movie.mediaType,
                          voteAverage: widget.movie.voteAverage,
                          releaseDate: widget.movie.releaseDate,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(added
                                ? 'Added to My List'
                                : 'Removed from My List'),
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
                          color: inList
                              ? Colors.deepPurpleAccent
                              : Colors.white70,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (DeviceProfile.isAndroidTv) {
      return FocusableControl(
        onTap: () => _openMovie(context),
        borderRadius: 16,
        child: posterCore,
      );
    }

    return InkWell(
      onFocusChange: (hasFocus) {
        setState(() {
          _isFocused = hasFocus;
        });
      },
      onHover: (isHovering) {
        setState(() {
          _isHovered = isHovering;
        });
      },
      onTap: () => _openMovie(context),
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      splashColor: Colors.deepPurpleAccent.withValues(alpha: 0.3),
      highlightColor: Colors.transparent,
      borderRadius: BorderRadius.circular(16.0),
      child: posterCore,
    );
  }
}
