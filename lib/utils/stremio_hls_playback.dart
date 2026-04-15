import 'package:flutter/foundation.dart';

import '../api/local_server_service.dart';
import 'youtube_embed_resolver.dart';

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
  // YouTube page URLs must become direct HLS **before** local proxy (proxying
  // youtube.com through our hls-proxy breaks playback).
  var effectiveUrl = url;
  if (isStremioLiveTv &&
      isStremioDirect &&
      YoutubeEmbedResolver.looksLikeYoutubePage(url)) {
    final direct = await YoutubeEmbedResolver.resolveToDirectStream(url);
    if (direct != null) effectiveUrl = direct;
  }

  final parsed = Uri.tryParse(effectiveUrl);
  if (parsed != null &&
      (parsed.host == '127.0.0.1' || parsed.host == 'localhost') &&
      parsed.path.contains('hls-proxy')) {
    return (playUrl: effectiveUrl, openHeaders: null, usedLocalProxy: true);
  }
  if (kIsWeb ||
      !isStremioLiveTv ||
      !isStremioDirect ||
      requestHeaders == null ||
      requestHeaders.isEmpty) {
    return (playUrl: effectiveUrl, openHeaders: requestHeaders, usedLocalProxy: false);
  }
  // FlixNest / dlstreams often use opaque URLs with no `.m3u8` in the string.
  // If the addon sent proxyHeaders, **always** route through our proxy (like Stremio).
  try {
    await LocalServerService().start();
    final proxied = LocalServerService().getHlsProxyUrl(effectiveUrl, requestHeaders);
    return (playUrl: proxied, openHeaders: null, usedLocalProxy: true);
  } catch (e) {
    debugPrint('[StremioHls] Local HLS proxy unavailable, using direct URL: $e');
    return (playUrl: effectiveUrl, openHeaders: requestHeaders, usedLocalProxy: false);
  }
}
