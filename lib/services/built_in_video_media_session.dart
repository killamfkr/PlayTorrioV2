import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../api/music_player_service.dart';

/// Hooks the built-in [Player] into [AudioService] so Android/iOS show a media
/// notification (play/pause, seek, dismiss) while video plays in background.
void attachBuiltInVideoMediaSession(
  Player player, {
  required String title,
  String? posterPath,
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
    h.attachVideoPlayer(player, title: title, artUri: artUri);
  } catch (e, st) {
    debugPrint('[BuiltInVideoMediaSession] attach failed: $e\n$st');
  }
}

void detachBuiltInVideoMediaSession() {
  if (kIsWeb) return;
  try {
    MusicPlayerService().playTorrioAudioHandler?.detachVideoPlayer();
  } catch (e, st) {
    debugPrint('[BuiltInVideoMediaSession] detach failed: $e\n$st');
  }
}
