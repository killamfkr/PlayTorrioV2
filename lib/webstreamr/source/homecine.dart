/// Port of webstreamr/src/source/HomeCine.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

int _lev(String a, String b) {
  final s = a.toLowerCase();
  final t = b.toLowerCase();
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;
  final prev = List<int>.generate(t.length + 1, (i) => i);
  final cur = List<int>.filled(t.length + 1, 0);
  for (var i = 0; i < s.length; i++) {
    cur[0] = i + 1;
    for (var j = 0; j < t.length; j++) {
      final cost = s.codeUnitAt(i) == t.codeUnitAt(j) ? 0 : 1;
      cur[j + 1] = [cur[j] + 1, prev[j + 1] + 1, prev[j] + cost]
          .reduce((a, b) => a < b ? a : b);
    }
    for (var k = 0; k <= t.length; k++) {
      prev[k] = cur[k];
    }
  }
  return prev[t.length];
}

class HomeCineSource extends Source {
  HomeCineSource(super.fetcher);

  @override
  String get id => 'homecine';
  @override
  String get label => 'HomeCine';
  @override
  List<String> get contentTypes => const ['movie', 'series'];
  @override
  List<CountryCode> get countryCodes =>
      const [CountryCode.es, CountryCode.mx];
  @override
  String get baseUrl => 'https://www3.homecine.to';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);
    final ny = await getTmdbNameAndYear(ctx, fetcher, tmdbId, 'es');
    final name = ny[0] as String;
    final year = ny[1] as int;
    final originalName = ny[2] as String;

    var pageUrl = await _fetchPageUrl(ctx, name, tmdbId);
    pageUrl ??= await _fetchPageUrl(ctx, originalName, tmdbId);
    if (pageUrl == null) return const [];

    var pageHtml = await fetcher.text(ctx, pageUrl);

    if (tmdbId.season != null) {
      final epUrl = _fetchEpisodeUrl(pageHtml, tmdbId);
      if (epUrl == null) return const [];
      pageHtml = await fetcher.text(ctx, epUrl);
    }

    final title = tmdbId.season != null
        ? '$name ${tmdbId.formatSeasonAndEpisode()}'
        : '$name ($year)';

    final doc = html_parser.parse(pageHtml);
    final out = <SourceResult>[];
    for (final a in doc.querySelectorAll('.les-content a')) {
      final t = a.text.toLowerCase();
      List<CountryCode> ccs;
      if (t.contains('latino')) {
        ccs = const [CountryCode.mx];
      } else if (t.contains('castellano')) {
        ccs = const [CountryCode.es];
      } else {
        continue;
      }
      // Upstream queries `iframe` inside the anchor.
      final src = a.querySelector('iframe')?.attributes['src'];
      if (src == null) continue;
      out.add(SourceResult(
        url: Uri.parse(src),
        meta: Meta(
            countryCodes: ccs,
            referer: pageUrl.toString(),
            title: title),
      ));
    }
    return out;
  }

  Future<Uri?> _fetchPageUrl(
      Context ctx, String name, TmdbId tmdbId) async {
    final searchUrl =
        Uri.parse('$baseUrl/?s=${Uri.encodeComponent(name)}');
    final html = await fetcher.text(ctx, searchUrl);
    final doc = html_parser.parse(html);
    final keywords = <String>{name, name.replaceAll('-', '–')};

    bool matchesType(Uri u) =>
        tmdbId.season != null
            ? u.toString().contains('/series/')
            : !u.toString().contains('/series/');

    // Exact match
    for (final k in keywords) {
      for (final el in doc.querySelectorAll('a[oldtitle="$k"]')) {
        final href = el.attributes['href'];
        if (href == null) continue;
        final u = Uri.parse(href);
        if (matchesType(u)) return u;
      }
    }
    // Similar match
    for (final k in keywords) {
      for (final el in doc.querySelectorAll('a[oldtitle]')) {
        final ot = (el.attributes['oldtitle'] ?? '').trim();
        if (_lev(ot, k) >= 5) continue;
        final href = el.attributes['href'];
        if (href == null) continue;
        final u = Uri.parse(href);
        if (matchesType(u)) return u;
      }
    }
    return null;
  }

  Uri? _fetchEpisodeUrl(String pageHtml, TmdbId tmdbId) {
    final doc = html_parser.parse(pageHtml);
    final suffix = '-temporada-${tmdbId.season}-capitulo-${tmdbId.episode}';
    for (final a in doc.querySelectorAll('#seasons a')) {
      final href = a.attributes['href'];
      if (href == null) continue;
      if (href.endsWith(suffix)) return Uri.parse(href);
    }
    return null;
  }
}
