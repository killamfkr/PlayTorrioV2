import 'package:media_kit/media_kit.dart';

/// Builds the value for mpv's [http-header-fields] property.
///
/// mpv parses this as a **comma-separated** list of `Name: value` entries.
/// Commas **inside** a header value must be escaped as `\,` or the list splits
/// in the wrong place (see mpv issue #11661). Stripping commas corrupts
/// [Accept-Encoding], [sec-ch-ua], [Cookie] / Expires, etc., and breaks HLS.
///
/// Returns an empty string when there are no headers (caller clears the property).
String encodeMpvHttpHeaderFieldsValue(Map<String, String>? headers) {
  if (headers == null || headers.isEmpty) return '';
  final parts = <String>[];
  for (final e in headers.entries) {
    final k = e.key.trim();
    if (k.isEmpty) continue;
    // Escape backslashes first so literal "\," stays correct.
    final v = e.value.replaceAll(r'\', r'\\').replaceAll(',', r'\,');
    parts.add('$k: $v');
  }
  return parts.join(', ');
}

/// mpv applies [http-header-fields] to HTTP(S) requests from libav/ffmpeg
/// (master playlist + many HLS segment/key fetches). Stremio addons often put
/// auth/origin only in [behaviorHints.proxyHeaders]; passing headers only on
/// [Media] is not always enough for every nested request.
Future<void> applyMpvHttpHeadersFromMap(
  NativePlayer mpv,
  Map<String, String>? headers,
) async {
  final s = encodeMpvHttpHeaderFieldsValue(headers);
  await mpv.setProperty('http-header-fields', s);
}

/// FFmpeg/libavformat HLS sometimes opens keys/variants via options that do not
/// inherit mpv's global [http-header-fields]. Passing the same map via
/// [demuxer-lavf-o] `headers=` matches `ffmpeg -headers` behavior for stubborn
/// CDNs.
Future<void> applyMpvDemuxerLavfHttpHeaders(
  NativePlayer mpv,
  Map<String, String>? headers,
) async {
  if (headers == null || headers.isEmpty) {
    await mpv.setProperty('demuxer-lavf-o', '');
    return;
  }
  final lines = <String>[];
  for (final e in headers.entries) {
    final k = e.key.trim();
    if (k.isEmpty) continue;
    lines.add('$k: ${e.value}');
  }
  if (lines.isEmpty) {
    await mpv.setProperty('demuxer-lavf-o', '');
    return;
  }
  // CRLF-separated block per ffmpeg -headers / libavformat HTTP.
  final block = lines.join('\r\n');
  await mpv.setProperty('demuxer-lavf-o', 'headers=$block');
}
