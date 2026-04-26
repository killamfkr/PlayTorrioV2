/// Port of webstreamr/src/source/Kokoshka.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class KokoshkaSource extends Source {
  KokoshkaSource(super.fetcher);

  @override
  String get id => 'kokoshka';
  @override
  String get label => 'Kokoshka';
  @override
  List<String> get contentTypes => const ['movie', 'series'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.al];
  @override
  String get baseUrl => 'https://kokoshka.digital';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);

    var pageUrl = await _fetchPageUrl(ctx, tmdbId, 'sq');
    pageUrl ??= await _fetchPageUrl(ctx, tmdbId, 'en');
    if (pageUrl == null) return const [];

    if (tmdbId.season != null) {
      pageUrl = await _fetchEpisodeUrl(ctx, pageUrl, tmdbId);
      if (pageUrl == null) return const [];
    }

    final pageHtml = await fetcher.text(ctx, pageUrl);
    final doc = html_parser.parse(pageHtml);
    final title =
        doc.querySelector('title')?.text.trim() ?? '';

    final out = <SourceResult>[];
    for (final el in doc.querySelectorAll('.dooplay_player_option')) {
      if (el.id == 'player-option-trailer') continue;
      final post = int.tryParse(el.attributes['data-post'] ?? '');
      final dtype = el.attributes['data-type'];
      final nume = int.tryParse(el.attributes['data-nume'] ?? '');
      if (post == null || dtype == null || nume == null) continue;

      final dooplayerUrl =
          Uri.parse('$baseUrl/wp-json/dooplayer/v2/$post/$dtype/$nume');
      try {
        final resp = await fetcher.json(
            ctx,
            dooplayerUrl,
            FetcherRequestConfig(
                headers: {'Referer': pageUrl.toString()})) as Map<String, dynamic>;
        final embed = resp['embed_url'];
        if (embed is! String) continue;
        out.add(SourceResult(
          url: Uri.parse(embed),
          meta: Meta(
            countryCodes: const [CountryCode.al],
            referer: pageUrl.toString(),
            title: title,
          ),
        ));
      } catch (_) {
        // skip
      }
    }
    return out;
  }

  Future<Uri?> _fetchPageUrl(
      Context ctx, TmdbId tmdbId, String language) async {
    final ny = await getTmdbNameAndYear(ctx, fetcher, tmdbId, language);
    final name = ny[0] as String;
    final year = ny[1] as int;

    final query = '${name.replaceAll(':', '')} $year';
    final searchUrl =
        Uri.parse('$baseUrl/?s=${Uri.encodeComponent(query)}');
    final html = await fetcher.text(ctx, searchUrl);
    final doc = html_parser.parse(html);

    final isSeries = tmdbId.season != null;
    for (final item in doc.querySelectorAll('.result-item')) {
      // require matching kind
      final hasKind = item.querySelector(isSeries ? '.tvshows' : '.movies');
      if (hasKind == null) continue;

      final yText = item.querySelector('.year')?.text ?? '';
      final ry = int.tryParse(yText.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if ((ry - year).abs() > 1) continue;

      final tText = item.querySelector('.title')?.text ?? '';
      final cleaned = tText.replaceFirst(RegExp(r'\(\d+\).*'), '').trim();
      if (_lev(cleaned, name) >= 3) continue;

      final href = item.querySelector('a')?.attributes['href'];
      if (href == null) continue;
      return Uri.parse(href).hasScheme
          ? Uri.parse(href)
          : Uri.parse(baseUrl).resolve(href);
    }
    return null;
  }

  Future<Uri?> _fetchEpisodeUrl(
      Context ctx, Uri pageUrl, TmdbId tmdbId) async {
    final html = await fetcher.text(ctx, pageUrl);
    final doc = html_parser.parse(html);
    final marker = '${tmdbId.season}x${tmdbId.episode}';
    final el =
        doc.querySelector('.episodiotitle a[href*="$marker"]');
    final href = el?.attributes['href'];
    if (href == null) return null;
    return Uri.parse(href).hasScheme
        ? Uri.parse(href)
        : Uri.parse(baseUrl).resolve(href);
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
