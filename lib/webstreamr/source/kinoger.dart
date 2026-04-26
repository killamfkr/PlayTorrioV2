/// Port of webstreamr/src/source/KinoGer.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class KinoGerSource extends Source {
  KinoGerSource(super.fetcher);

  @override
  String get id => 'kinoger';
  @override
  String get label => 'KinoGer';
  @override
  List<String> get contentTypes => const ['movie', 'series'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.de];
  @override
  String get baseUrl => 'https://kinoger.com';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);
    final ny = await getTmdbNameAndYear(ctx, fetcher, tmdbId, 'de');
    final name = ny[0] as String;
    final year = ny[1] as int;

    final pageUrl = await _fetchPageUrl(ctx, name, year);
    if (pageUrl == null) return const [];

    final title = tmdbId.season != null
        ? '$name ${tmdbId.season}x${tmdbId.episode}'
        : '$name ($year)';
    final seasonIndex = (tmdbId.season ?? 1) - 1;
    final episodeIndex = (tmdbId.episode ?? 1) - 1;

    final html = await fetcher.text(ctx, pageUrl);
    final out = <SourceResult>[];
    for (final m in RegExp(r'\.show\(.*').allMatches(html)) {
      final url = _findEpisodeUrlInShowJs(m.group(0)!, seasonIndex, episodeIndex);
      if (url == null) continue;
      out.add(SourceResult(
        url: url,
        meta: Meta(
          countryCodes: const [CountryCode.de],
          referer: pageUrl.toString(),
          title: title,
        ),
      ));
    }
    return out;
  }

  Uri? _findEpisodeUrlInShowJs(
      String showJs, int seasonIndex, int episodeIndex) {
    final lists = RegExp(r'\[(.*?)]').allMatches(showJs).toList();
    if (seasonIndex < 0 || seasonIndex >= lists.length) return null;
    final inner = lists[seasonIndex].group(1);
    if (inner == null) return null;
    final parts = inner.split(',');
    if (episodeIndex < 0 || episodeIndex >= parts.length) return null;
    final m = RegExp("https?://[^\\s'\"<>]+").firstMatch(parts[episodeIndex]);
    if (m == null) return null;
    return Uri.parse(m.group(0)!);
  }

  Future<Uri?> _fetchPageUrl(
      Context ctx, String keyword, int year) async {
    final searchUrl = Uri.parse(
        '$baseUrl/?do=search&subaction=search&titleonly=3&story=${Uri.encodeComponent(keyword)}&x=0&y=0&submit=submit');
    final html = await fetcher.text(ctx, searchUrl);
    final doc = html_parser.parse(html);
    final yearStr = '$year';
    for (final a in doc.querySelectorAll('.title a')) {
      if (!a.text.contains(yearStr)) continue;
      final href = a.attributes['href'];
      if (href == null) continue;
      return Uri.parse(href).hasScheme
          ? Uri.parse(href)
          : Uri.parse(baseUrl).resolve(href);
    }
    return null;
  }
}
