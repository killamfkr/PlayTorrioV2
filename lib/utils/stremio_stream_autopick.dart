/// Picks a playable Stremio stream map for auto-play (addon scope + resolution tier).

/// `best` | `4k` | `1080` | `720`
int stremioStreamResolutionScore(String text) {
  final t = text.toLowerCase();
  if (t.contains('2160p') ||
      t.contains('2160') ||
      t.contains('4k') ||
      t.contains('uhd') ||
      t.contains('ultra hd')) {
    return 400;
  }
  if (t.contains('1080p') || t.contains('fhd') || t.contains('full hd')) return 300;
  if (t.contains('720p')) return 200;
  if (t.contains('480p') || t.contains('sd')) return 100;
  return 0;
}

bool stremioStreamMatchesResolutionTier(String blob, String tier) {
  final q = stremioStreamResolutionScore(blob);
  final n = blob.toLowerCase();
  switch (tier) {
    case '4k':
      return q >= 400 ||
          (n.contains('2160') && !n.contains('1080') && !n.contains('720'));
    case '1080':
      if (q >= 400) return false;
      return q == 300 ||
          n.contains('1080') ||
          n.contains('fhd') ||
          n.contains('full hd');
    case '720':
      if (q >= 400 || q == 300) return false;
      return q == 200 || n.contains('720');
    case 'best':
    default:
      return true;
  }
}

int stremioStreamParsedSeeders(Map<String, dynamic> s) {
  final blob =
      '${s['title'] ?? ''} ${s['name'] ?? ''} ${s['description'] ?? ''}';
  final m1 = RegExp(r'([\d,.]+)\s*seed', caseSensitive: false).firstMatch(blob);
  if (m1 != null) {
    return int.tryParse(m1.group(1)!.replaceAll(RegExp(r'[,.]'), '')) ?? 0;
  }
  final m2 = RegExp(r'👤\s*([\d,.]+)', caseSensitive: false).firstMatch(blob);
  if (m2 != null) {
    return int.tryParse(m2.group(1)!.replaceAll(RegExp(r'[,.]'), '')) ?? 0;
  }
  return 0;
}

String _stremioStreamBlob(Map<String, dynamic> s) {
  return '${s['title'] ?? ''} ${s['name'] ?? ''} ${s['description'] ?? ''}';
}

bool _isPlayableStremioStream(Map<String, dynamic> s) {
  if (s['externalUrl'] != null && s['externalUrl'].toString().isNotEmpty) {
    return false;
  }
  return (s['url'] != null && s['url'].toString().isNotEmpty) ||
      (s['infoHash'] != null && s['infoHash'].toString().isNotEmpty);
}

/// [addonBaseUrl] — `__all__` or a specific addon manifest `baseUrl`.
Map<String, dynamic>? pickAutoStremioStream(
  List<dynamic> rawStreams, {
  required String addonBaseUrl,
  required String resolutionTier,
  int maxCandidates = 24,
  bool fallbackChain = true,
}) {
  final streams = <Map<String, dynamic>>[];
  for (final x in rawStreams) {
    if (x is! Map) continue;
    final m = Map<String, dynamic>.from(
      x.map((k, v) => MapEntry(k.toString(), v)),
    );
    if (!_isPlayableStremioStream(m)) continue;
    if (addonBaseUrl.isNotEmpty &&
        addonBaseUrl != '__all__' &&
        m['_addonBaseUrl']?.toString() != addonBaseUrl) {
      continue;
    }
    streams.add(m);
    if (streams.length >= maxCandidates) break;
  }
  if (streams.isEmpty) return null;

  Map<String, dynamic>? pickTier(String tier) {
    if (tier == 'best' || tier.isEmpty) {
      final copy = List<Map<String, dynamic>>.from(streams);
      copy.sort((a, b) =>
          stremioStreamParsedSeeders(b).compareTo(stremioStreamParsedSeeders(a)));
      return copy.isEmpty ? null : copy.first;
    }
    final filtered = streams
        .where((s) =>
            stremioStreamMatchesResolutionTier(_stremioStreamBlob(s), tier))
        .toList();
    if (filtered.isEmpty) return null;
    filtered.sort((a, b) =>
        stremioStreamParsedSeeders(b).compareTo(stremioStreamParsedSeeders(a)));
    return filtered.first;
  }

  if (!fallbackChain) {
    return pickTier(resolutionTier.trim().toLowerCase());
  }

  final tier = resolutionTier.trim().toLowerCase();
  final tryOrder = <String>[];
  switch (tier) {
    case '4k':
    case '2160':
    case 'uhd':
      tryOrder.addAll(['4k', '1080', '720', 'best']);
      break;
    case '1080':
    case '1080p':
      tryOrder.addAll(['1080', '720', '4k', 'best']);
      break;
    case '720':
    case '720p':
      tryOrder.addAll(['720', '1080', '4k', 'best']);
      break;
    case 'best':
    default:
      tryOrder.add('best');
  }

  for (final step in tryOrder) {
    final p = pickTier(step);
    if (p != null) return p;
  }
  return null;
}
