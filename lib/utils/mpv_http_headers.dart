import 'package:media_kit/media_kit.dart';

/// mpv applies [http-header-fields] to **all** HTTP requests (master playlist + HLS
/// segments). Stremio addons often put auth/origin only in [behaviorHints.proxyHeaders];
/// passing headers only to [Media] is not enough for segment fetches.
///
/// Format per mpv manual: `Key1: value1, Key2: value2`
Future<void> applyMpvHttpHeadersFromMap(
  NativePlayer mpv,
  Map<String, String>? headers,
) async {
  if (headers == null || headers.isEmpty) {
    await mpv.setProperty('http-header-fields', '');
    return;
  }
  final parts = <String>[];
  for (final e in headers.entries) {
    final k = e.key.trim();
    if (k.isEmpty) continue;
    // Avoid breaking mpv's comma-separated list; strip commas in values (rare).
    final v = e.value.replaceAll(',', ' ');
    parts.add('$k: $v');
  }
  if (parts.isEmpty) {
    await mpv.setProperty('http-header-fields', '');
    return;
  }
  await mpv.setProperty('http-header-fields', parts.join(', '));
}
