import 'package:flutter/foundation.dart';

import '../api/music_service.dart';

/// Stremio addons (e.g. dlstreams / DLTV) often return **YouTube watch or embed
/// URLs**. Opening those inside WebView-based flows hits nested sandboxed
/// iframes and Android shows: "Remove sandbox attributes on the iframe tag".
/// Resolving to a **direct stream / HLS URL** via the same pipeline as music
/// playback avoids the embed entirely.
class YoutubeEmbedResolver {
  YoutubeEmbedResolver._();

  static final RegExp _videoIdPattern = RegExp(
    r'(?:youtube\.com\/(?:watch\?(?:[^#]*&)?v=|embed\/|live\/|shorts\/)|youtu\.be\/|m\.youtube\.com\/watch\?(?:[^#]*&)?v=)([a-zA-Z0-9_-]{11})',
    caseSensitive: false,
  );

  static String? extractVideoId(String url) {
    final u = url.trim();
    if (u.isEmpty) return null;
    final m = _videoIdPattern.firstMatch(u);
    return m?.group(1);
  }

  static bool looksLikeYoutubePage(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com/') ||
        lower.contains('youtu.be/') ||
        lower.contains('youtube-nocookie.com/');
  }

  /// Returns a URL mpv/media_kit can play, or null to keep the original.
  static Future<String?> resolveToDirectStream(String url) async {
    if (!looksLikeYoutubePage(url)) return null;
    final id = extractVideoId(url);
    if (id == null) return null;

    try {
      final music = MusicService();
      final manifest = await music.getYoutubeManifest(id);
      if (manifest == null) return null;

      // Prefer combined HLS (good quality + audio) when available.
      // youtube_explode_dart 3.x: [HlsStreamInfo] only has [StreamInfo] (bitrate), not [videoQuality].
      if (manifest.hls.isNotEmpty) {
        final list = manifest.hls.toList()
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
        return list.first.url.toString();
      }
      // Muxed MP4 tops out around 360p but works without separate audio.
      if (manifest.muxed.isNotEmpty) {
        final list = manifest.muxed.toList()
          ..sort((a, b) =>
              b.videoQuality.index.compareTo(a.videoQuality.index));
        return list.first.url.toString();
      }
    } catch (e, st) {
      debugPrint('[YoutubeEmbedResolver] resolve failed: $e\n$st');
    }
    return null;
  }
}
