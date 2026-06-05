/// Port of webstreamr/src/source/Eurostreaming.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class EurostreamingSource extends Source {
  EurostreamingSource(super.fetcher);

  @override
  String get id => 'eurostreaming';
  @override
  String get label => 'Eurostreaming';
  @override
  List<String> get contentTypes => const ['series'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.it];
  @override
  String get baseUrl => 'https://eurostreaming.luxe';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);
    final ny = await getTmdbNameAndYear(ctx, fetcher, tmdbId, 'it');
    final name = ny[0] as String;

    final keyword = name.replaceAll(':', '').replaceAll('-', '');
    final seriesPageUrl = await _fetchSeriesPageUrl(ctx, keyword);
    if (seriesPageUrl == null) return const [];

    final html = await fetcher.text(ctx, seriesPageUrl);
    final doc = html_parser.parse(html);
    final title = '$name ${tmdbId.formatSeasonAndEpisode()}';

    final out = <SourceResult>[];
    final num = '${tmdbId.season}x${tmdbId.episode}';
    for (final n in doc.querySelectorAll('[data-num="$num"]')) {
      final mirrors = n.parent?.querySelector('.mirrors');
      if (mirrors == null) continue;
      for (final el in mirrors.querySelectorAll('[data-link]')) {
        final raw = el.attributes['data-link'];
        if (raw == null || raw == '#') continue;
        final u = Uri.parse(raw);
        if (u.host.contains('eurostreaming')) continue;
        out.add(SourceResult(
          url: u,
          meta: Meta(
            countryCodes: const [CountryCode.it],
            referer: seriesPageUrl.toString(),
            title: title,
          ),
        ));
      }
    }
    return out;
  }

  Future<Uri?> _fetchSeriesPageUrl(Context ctx, String keyword) async {
    final postUrl = Uri.parse('$baseUrl/index.php?do=search');
    final origin = '${postUrl.scheme}://${postUrl.host}';
    final body =
        'subaction=search&story=${Uri.encodeQueryComponent(keyword)}';
    final html = await fetcher.textPost(
        ctx,
        postUrl,
        body,
        FetcherRequestConfig(headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': origin,
        }));
    final doc = html_parser.parse(html);

    final anchors = doc.querySelectorAll('.post-thumb a[href]');

    Uri? exact;
    Uri? similar;
    Uri? partial;
    for (final a in anchors) {
      final href = a.attributes['href'];
      final t = a.attributes['title']?.trim() ?? '';
      if (href == null) continue;
      if (exact == null && t == keyword) {
        exact = Uri.parse(href);
      }
      if (similar == null && _lev(t, keyword) < 5) {
        similar = Uri.parse(href);
      }
      if (partial == null && t.contains(keyword)) {
        partial = Uri.parse(href);
      }
    }
    return exact ?? similar ?? partial;
  }

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length, n = b.length;
    final prev = List<int>.generate(n + 1, (i) => i);
    final curr = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      for (var k = 0; k <= n; k++) {
        prev[k] = curr[k];
      }
    }
    return prev[n];
  }
}
