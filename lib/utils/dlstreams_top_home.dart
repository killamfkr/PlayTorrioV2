/// Home layout helpers for the **dlstreams.top** Stremio source: group catalog
/// rows into readable shelves (Sports TV, News, etc.) and order them before
/// generic addon rows.
library;

/// Manifest URL for the bundled / user-facing dlstreams.top addon.
const String kDlstreamsTopManifestUrl = 'https://dlstreams.top/manifest.json';

bool isDlstreamsTopAddonUrl(String? baseUrl) {
  if (baseUrl == null || baseUrl.isEmpty) return false;
  return baseUrl.toLowerCase().contains('dlstreams.top');
}

bool isDlstreamsTopCatalog(Map<String, dynamic> cat) =>
    isDlstreamsTopAddonUrl(cat['addonBaseUrl'] as String?);

/// Fixed shelf order on Home (category-by-category boards).
const List<String> kDlstreamsShelfOrder = [
  'Sports TV',
  'Movies & Series',
  'News & Business',
  'Docs',
  'Kids',
  'Music',
  'Entertainment',
  'Live schedules',
];

/// Map a Stremio catalog name/id to a shelf label.
String shelfForDlstreamsCatalog(Map<String, dynamic> cat) {
  final name = '${cat['catalogName'] ?? ''} ${cat['catalogId'] ?? ''}'
      .toLowerCase();

  bool m(RegExp r) => r.hasMatch(name);

  // EPG / "what's on" style boards — own section last.
  if (m(RegExp(
      r'schedule|now\s*playing|on\s*now|airing|today|tonight|guide|program|epg|grid'))) {
    return 'Live schedules';
  }
  if (m(RegExp(
      r'sport|football|soccer|nba|nfl|espn|ufc|fight|wrestl|golf|tennis|cricket|racing|f1|mlb|nhl|olympic'))) {
    return 'Sports TV';
  }
  if (m(RegExp(
      r'news|business|finance|stock|bloomberg|cnn|cnbc|bbc news|sky news|economic'))) {
    return 'News & Business';
  }
  if (m(RegExp(
      r'doc|documentary|nature|science|history|discovery|animal|planet|knowledge'))) {
    return 'Docs';
  }
  if (m(RegExp(
      r'kid|junior|cartoon|nick|disney jr|pbs kids|children|family fun'))) {
    return 'Kids';
  }
  if (m(RegExp(r'music|mtv|concert|radio|vh1|hits|karaoke'))) {
    return 'Music';
  }
  if (m(RegExp(
      r'movie|series|cinema|film|drama|showtime|hbo|prime video|vod|box office'))) {
    return 'Movies & Series';
  }
  if (m(RegExp(
      r'entertain|comedy|reality|lifestyle|travel|food|cooking|game\s*show|talk\s*show|variety'))) {
    return 'Entertainment';
  }
  return 'Entertainment';
}

int _shelfRank(String shelf) {
  final i = kDlstreamsShelfOrder.indexOf(shelf);
  return i >= 0 ? i : kDlstreamsShelfOrder.length;
}

/// Sort catalogs: by shelf order, then by display name.
List<Map<String, dynamic>> orderedDlstreamsCatalogs(
    List<Map<String, dynamic>> catalogs) {
  final copy = List<Map<String, dynamic>>.from(catalogs);
  copy.sort((a, b) {
    final sa = shelfForDlstreamsCatalog(a);
    final sb = shelfForDlstreamsCatalog(b);
    final ra = _shelfRank(sa);
    final rb = _shelfRank(sb);
    if (ra != rb) return ra.compareTo(rb);
    final na = '${a['catalogName']}'.toLowerCase();
    final nb = '${b['catalogName']}'.toLowerCase();
    return na.compareTo(nb);
  });
  return copy;
}

/// First catalog in each shelf gets a header title for the home UI.
void annotateDlstreamsShelfHeaders(List<Map<String, dynamic>> ordered) {
  String? prev;
  for (final cat in ordered) {
    final s = shelfForDlstreamsCatalog(cat);
    cat['_homeShelfHeader'] = (s != prev) ? s : null;
    prev = s;
  }
}
