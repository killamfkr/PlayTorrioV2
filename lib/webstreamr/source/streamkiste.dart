/// Port of webstreamr/src/source/StreamKiste.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class StreamKisteSource extends Source {
  StreamKisteSource(super.fetcher);

  @override
  String get id => 'streamkiste';
  @override
  String get label => 'StreamKiste';
  @override
  List<String> get contentTypes => const ['series'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.de];
  @override
  String get baseUrl => 'https://streamkiste.taxi';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);
    final seriesPageUrl = await _fetchSeriesPageUrl(ctx, tmdbId);
    if (seriesPageUrl == null) return const [];

    final html = await fetcher.text(ctx, seriesPageUrl);
    final doc = html_parser.parse(html);

    final ogTitle = doc
            .querySelector('meta[property="og:title"]')
            ?.attributes['content']
            ?.trim() ??
        '';
    final title = '$ogTitle ${tmdbId.formatSeasonAndEpisode()}';

    final out = <SourceResult>[];
    final num = '${tmdbId.season}x${tmdbId.episode}';
    for (final n in doc.querySelectorAll('[data-num="$num"]')) {
      final mirrors = n.parent?.querySelector('.mirrors');
      if (mirrors == null) continue;
      for (final el in mirrors.querySelectorAll('[data-link]')) {
        final raw = el.attributes['data-link'];
        if (raw == null) continue;
        final fixed = raw.replaceFirst(RegExp(r'^(https:)?//'), 'https://');
        final u = Uri.parse(fixed);
        if (u.host.contains('streamkiste')) continue;
        out.add(SourceResult(
          url: u,
          meta: Meta(
            countryCodes: const [CountryCode.de],
            referer: seriesPageUrl.toString(),
            title: title,
          ),
        ));
      }
    }
    return out;
  }

  Future<Uri?> _fetchSeriesPageUrl(Context ctx, TmdbId tmdbId) async {
    final url = Uri.parse(
        '$baseUrl/?story=${tmdbId.id}&do=search&subaction=search');
    final html = await fetcher.text(ctx, url);
    final doc = html_parser.parse(html);
    final href = doc.querySelector('.res_item a[href]')?.attributes['href'];
    return href == null ? null : Uri.parse(href);
  }
}
