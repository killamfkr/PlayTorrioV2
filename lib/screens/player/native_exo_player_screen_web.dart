import 'package:flutter/material.dart';
import '../../models/movie.dart';
import '../../models/stream_source.dart';
import 'mobile_player_screen.dart';

/// Web: no ExoView / libVLC — use media_kit player.
class NativeExoPlayerScreen extends StatelessWidget {
  static const String playerSettingsName = 'Native ExoPlayer (TV)';

  final String mediaPath;
  final String title;
  final Map<String, String>? headers;
  final Movie? movie;
  final int? selectedSeason;
  final int? selectedEpisode;
  final String? magnetLink;
  final String? activeProvider;
  final Duration? startPosition;
  final List<StreamSource>? sources;
  final int? fileIndex;
  final String? stremioId;
  final String? stremioAddonBaseUrl;
  final String stremioStreamType;
  final Map<String, dynamic>? providers;

  const NativeExoPlayerScreen({
    super.key,
    required this.mediaPath,
    required this.title,
    this.headers,
    this.movie,
    this.selectedSeason,
    this.selectedEpisode,
    this.magnetLink,
    this.activeProvider,
    this.startPosition,
    this.sources,
    this.fileIndex,
    this.stremioId,
    this.stremioAddonBaseUrl,
    required this.stremioStreamType,
    this.providers,
  });

  @override
  Widget build(BuildContext context) {
    return MobilePlayerScreen(
      mediaPath: mediaPath,
      title: title,
      headers: headers,
      movie: movie,
      selectedSeason: selectedSeason,
      selectedEpisode: selectedEpisode,
      magnetLink: magnetLink,
      activeProvider: activeProvider,
      startPosition: startPosition,
      sources: sources,
      fileIndex: fileIndex,
      stremioId: stremioId,
      stremioAddonBaseUrl: stremioAddonBaseUrl,
      stremioStreamType: stremioStreamType,
      providers: providers,
    );
  }
}
