import 'dart:io';
import 'package:flutter/material.dart';
import 'package:play_torrio_native/models/movie.dart';
import 'package:play_torrio_native/models/stream_source.dart';
import 'player/mobile_player_screen.dart';
import 'player/desktop_player_screen.dart';

class PlayerScreen extends StatelessWidget {
  final String streamUrl;
  final String? audioUrl;
  final String title;
  final String? magnetLink;
  final Map<String, String>? headers;
  final Movie? movie;
  final Map<String, dynamic>? providers;
  final String? activeProvider;
  final int? selectedSeason;
  final int? selectedEpisode;
  final Duration? startPosition;
  final List<StreamSource>? sources;
  final int? fileIndex;
  final List<Map<String, dynamic>>? externalSubtitles;
  final String? stremioId;
  final String? stremioAddonBaseUrl;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    this.audioUrl,
    required this.title,
    this.magnetLink,
    this.headers,
    this.movie,
    this.providers,
    this.activeProvider,
    this.selectedSeason,
    this.selectedEpisode,
    this.startPosition,
    this.sources,
    this.fileIndex,
    this.externalSubtitles,
    this.stremioId,
    this.stremioAddonBaseUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      return MobilePlayerScreen(
        mediaPath: streamUrl,
        title: title,
        audioUrl: audioUrl,
        headers: headers,
        movie: movie,
        selectedSeason: selectedSeason,
        selectedEpisode: selectedEpisode,
        magnetLink: magnetLink,
        activeProvider: activeProvider,
        startPosition: startPosition,
        sources: sources,
        fileIndex: fileIndex,
        externalSubtitles: externalSubtitles,
        stremioId: stremioId,
        stremioAddonBaseUrl: stremioAddonBaseUrl,
        providers: providers,
      );
    } else {
      return DesktopPlayerScreen(
        mediaPath: streamUrl,
        title: title,
        audioUrl: audioUrl,
        headers: headers,
        movie: movie,
        selectedSeason: selectedSeason,
        selectedEpisode: selectedEpisode,
        magnetLink: magnetLink,
        activeProvider: activeProvider,
        startPosition: startPosition,
        sources: sources,
        fileIndex: fileIndex,
        externalSubtitles: externalSubtitles,
        stremioId: stremioId,
        stremioAddonBaseUrl: stremioAddonBaseUrl,
        providers: providers,
      );
    }
  }
}
