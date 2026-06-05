/// Port of webstreamr/src/source/Cuevana.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class CuevanaSource extends Source {
  CuevanaSource(super.fetcher);

  @override
  String get id => 'cuevana';
  @override
  String get label => 'Cuevana';
  @override
  List<String> get contentTypes => const ['movie', 'series'];
  @override
  List<CountryCode> get countryCodes =>
      const [CountryCode.es, CountryCode.mx];
  @override
  String get baseUrl => 'https://ww1.cuevana3.is';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);
    final ny = await getTmdbNameAndYear(ctx, fetcher, tmdbId, 'es');
    final name = ny[0] as String;
    final year = ny[1] as int;

    var pageUrl = await _fetchPageUrl(ctx, name);
    if (pageUrl == null) return const [];

    var title = name;
    if (tmdbId.season != null) {
      title += ' ${tmdbId.formatSeasonAndEpisode()}';
      pageUrl = await _fetchEpisodeUrl(ctx, pageUrl, tmdbId);
      if (pageUrl == null) return const [];
    } else {
      title += ' ($year)';
    }

    final html = await fetcher.text(ctx, pageUrl);
    final doc = html_parser.parse(html);
    final origin = '${pageUrl.scheme}://${pageUrl.host}';

    final initial = <SourceResult>[];
    for (final sub in doc.querySelectorAll('.open_submenu')) {
      final t = sub.text;
      if (!t.contains('Español')) continue;
      final cc = t.contains('Latino') ? CountryCode.mx : CountryCode.es;
      for (final el in sub.querySelectorAll('[data-tr], [data-video]')) {
        final raw =
            el.attributes['data-tr'] ?? el.attributes['data-video'];
        if (raw == null) continue;
        initial.add(SourceResult(
          url: Uri.parse(raw),
          meta: Meta(
              countryCodes: [cc],
              referer: pageUrl.toString(),
              title: title),
        ));
      }
    }

    final out = <SourceResult>[];
    for (final r in initial) {
      if (!r.url.host.contains('cuevana3')) {
        out.add(r);
        continue;
      }
      final h = await fetcher.text(ctx, r.url,
          FetcherRequestConfig(headers: {'Referer': origin}));
      final m = RegExp(r"url ?= ?'(.*)'").firstMatch(h);
      if (m == null) continue;
      out.add(SourceResult(url: Uri.parse(m.group(1)!), meta: r.meta));
    }
    return out;
  }

  Future<Uri?> _fetchPageUrl(Context ctx, String keyword) async {
    final searchUrl =
        Uri.parse('$baseUrl/search/${Uri.encodeComponent(keyword)}/');
    final origin = '${searchUrl.scheme}://${searchUrl.host}';
    final html = await fetcher.text(ctx, searchUrl,
        FetcherRequestConfig(headers: {'Referer': origin}));
    final doc = html_parser.parse(html);
    for (final t in doc.querySelectorAll('.TPost .Title')) {
      if (t.text.trim() != keyword) continue;
      var p = t.parent;
      while (p != null && p.localName != 'a') {
        p = p.parent;
      }
      final href = p?.attributes['href'];
      if (href == null) continue;
      return Uri.parse(href).hasScheme
          ? Uri.parse(href)
          : Uri.parse('$origin$href');
    }
    return null;
  }

  Future<Uri?> _fetchEpisodeUrl(
      Context ctx, Uri pageUrl, TmdbId tmdbId) async {
    final origin = '${pageUrl.scheme}://${pageUrl.host}';
    final html = await fetcher.text(ctx, pageUrl,
        FetcherRequestConfig(headers: {'Referer': origin}));
    final doc = html_parser.parse(html);
    final marker = '${tmdbId.season}x${tmdbId.episode}';
    for (final y in doc.querySelectorAll('.TPost .Year')) {
      if (y.text.trim() != marker) continue;
      var p = y.parent;
      while (p != null && p.localName != 'a') {
        p = p.parent;
      }
      final href = p?.attributes['href'];
      if (href == null) continue;
      return Uri.parse(href).hasScheme
          ? Uri.parse(href)
          : Uri.parse('$origin$href');
    }
    return null;
  }
}
