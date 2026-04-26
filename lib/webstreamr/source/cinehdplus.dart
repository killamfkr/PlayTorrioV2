/// Port of webstreamr/src/source/CineHDPlus.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class CineHDPlusSource extends Source {
  CineHDPlusSource(super.fetcher);

  @override
  String get id => 'cinehdplus';
  @override
  String get label => 'CineHDPlus';
  @override
  List<String> get contentTypes => const ['series'];
  @override
  List<CountryCode> get countryCodes =>
      const [CountryCode.es, CountryCode.mx];
  @override
  String get baseUrl => 'https://cinehdplus.gratis';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);
    final pageUrl = await _fetchSeriesPageUrl(ctx, tmdbId);
    if (pageUrl == null) return const [];

    final html = await fetcher.text(ctx, pageUrl);
    final doc = html_parser.parse(html);

    final langs = doc.querySelector('.details__langs')?.innerHtml ?? '';
    final cc = langs.contains('Latino') ? CountryCode.mx : CountryCode.es;

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
        final url = Uri.parse(fixed);
        if (url.host.contains('cinehdplus')) continue;
        out.add(SourceResult(
          url: url,
          meta: Meta(
            countryCodes: [cc],
            referer: pageUrl.toString(),
            title: title,
          ),
        ));
      }
    }
    return out;
  }

  Future<Uri?> _fetchSeriesPageUrl(Context ctx, TmdbId tmdbId) async {
    final url = Uri.parse(
        '$baseUrl/series/?story=${tmdbId.id}&do=search&subaction=search');
    final html = await fetcher.text(ctx, url);
    final doc = html_parser.parse(html);
    final href = doc.querySelector('.card__title a[href]')?.attributes['href'];
    return href == null ? null : Uri.parse(href);
  }
}
