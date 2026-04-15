import 'package:flutter/foundation.dart';

import '../api/local_server_service.dart';

bool _looksLikeAdaptiveOrLiveStreamUrl(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('.m3u8') || lower.contains('m3u8')) return true;
  if (lower.contains('.mpd') || lower.contains('/manifest')) return true;
  if (lower.contains('application/vnd.apple.mpegurl')) return true;
  // Path patterns without a clear extension
  if (lower.contains('/playlist') ||
      lower.contains('master') ||
      lower.contains('index.m3u') ||
      lower.contains('/hls/')) {
    return true;
  }
  return false;
}

/// Stremio’s engine proxies HLS so **every** playlist/segment/key request carries
/// [behaviorHints.proxyHeaders.request]. Plain players only attach headers to the
/// first open; nested libav HLS fetches often 403 without a proxy.
///
/// On mobile/desktop we rewrite the master URL through [LocalServerService]’s
/// HLS proxy (localhost) so all sub-playlists and segments use the same headers.
/// On web the local server is unavailable — pass the original URL and headers.
///
/// Returns [openHeaders]: `null` when the proxy carries Stremio headers (mpv must
/// not duplicate them). Otherwise the map to pass to [Media.httpHeaders].
Future<({String playUrl, Map<String, String>? openHeaders, bool usedLocalProxy})>
    resolveStremioLiveTvPlayback({
  required String url,
  required Map<String, String>? requestHeaders,
  required bool isStremioLiveTv,
  required bool isStremioDirect,
}) async {
  final parsed = Uri.tryParse(url);
  if (parsed != null &&
      (parsed.host == '127.0.0.1' || parsed.host == 'localhost') &&
      parsed.path.contains('hls-proxy')) {
    return (playUrl: url, openHeaders: null, usedLocalProxy: true);
  }
  if (kIsWeb ||
      !isStremioLiveTv ||
      !isStremioDirect ||
      requestHeaders == null ||
      requestHeaders.isEmpty) {
    return (playUrl: url, openHeaders: requestHeaders, usedLocalProxy: false);
  }
  // Adaptive / typical live patterns — avoid proxying plain progressive MP4 (OOM risk).
  if (!_looksLikeAdaptiveOrLiveStreamUrl(url)) {
    return (playUrl: url, openHeaders: requestHeaders, usedLocalProxy: false);
  }
  try {
    await LocalServerService().start();
    final proxied = LocalServerService().getHlsProxyUrl(url, requestHeaders);
    return (playUrl: proxied, openHeaders: null, usedLocalProxy: true);
  } catch (e) {
    debugPrint('[StremioHls] Local HLS proxy unavailable, using direct URL: $e');
    return (playUrl: url, openHeaders: requestHeaders, usedLocalProxy: false);
  }
}
