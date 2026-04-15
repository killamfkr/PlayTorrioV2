import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../api/music_player_service.dart';

/// Hooks the built-in [Player] into [AudioService] so Android Auto, Bluetooth,
/// and lock-screen controls see metadata and transport actions.
void attachBuiltInVideoMediaSession(
  Player player, {
  required String title,
  String? posterPath,
  String? displaySubtitle,
  String? album,
  bool? isLive,
  Map<String, dynamic>? extras,
}) {
  if (kIsWeb) return;
  try {
    final h = MusicPlayerService().playTorrioAudioHandler;
    if (h == null) return;
    Uri? artUri;
    if (posterPath != null && posterPath.isNotEmpty) {
      if (posterPath.startsWith('http')) {
        artUri = Uri.tryParse(posterPath);
      } else {
        artUri = Uri.parse('https://image.tmdb.org/t/p/w342$posterPath');
      }
    }
    h.attachVideoPlayer(
      player,
      title: title,
      artUri: artUri,
      displaySubtitle: displaySubtitle,
      album: album,
      isLive: isLive,
      extras: extras,
    );
  } catch (e, st) {
    debugPrint('[BuiltInVideoMediaSession] attach failed: $e\n$st');
  }
}

/// Pass the same [player] instance given to [attachBuiltInVideoMediaSession] so
/// overlapping routes (e.g. next-episode [Navigator.pushReplacement]) do not
/// clear the new session when the old screen disposes.
void detachBuiltInVideoMediaSession(Player player) {
  if (kIsWeb) return;
  try {
    MusicPlayerService().playTorrioAudioHandler?.detachVideoPlayer(player);
  } catch (e, st) {
    debugPrint('[BuiltInVideoMediaSession] detach failed: $e\n$st');
  }
}
