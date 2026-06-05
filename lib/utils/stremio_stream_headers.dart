/// Extracts HTTP headers Stremio addons attach for proxied playback.
///
/// Spec: [behaviorHints.proxyHeaders.request]. Some addons incorrectly put
/// [proxyHeaders] at the top level or use a [requests] typo — merge those too.
Map<String, String> stremioProxyRequestHeadersFromStream(Map<String, dynamic> stream) {
  final out = <String, String>{};

  void putFlatFromMap(Map? m) {
    if (m == null) return;
    for (final e in m.entries) {
      final k = e.key?.toString();
      if (k == null || k.isEmpty) continue;
      final v = e.value;
      if (v == null) continue;
      // Nested maps are not header lines
      if (v is Map) continue;
      out[k] = v.toString();
    }
  }

  void mergeProxyHeaders(Map? ph) {
    if (ph == null) return;
    putFlatFromMap(ph['request'] as Map?);
    putFlatFromMap(ph['requests'] as Map?);
    // Some addons omit `request` and put Referer/UA directly on [proxyHeaders].
    putFlatFromMap(ph);
  }

  final bh = stream['behaviorHints'];
  if (bh is Map) {
    mergeProxyHeaders(bh['proxyHeaders'] as Map?);
  }

  final top = stream['proxyHeaders'];
  if (top is Map) {
    mergeProxyHeaders(top);
  }

  final loose = stream['headers'];
  if (loose is Map) {
    putFlatFromMap(loose);
  }

  return out;
}
