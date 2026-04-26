/// Port of webstreamr/src/source/Movix.ts
library;

import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class MovixSource extends Source {
  MovixSource(super.fetcher);

  @override
  String get id => 'movix';
  @override
  String get label => 'Movix';
  @override
  List<String> get contentTypes => const ['movie', 'series'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.fr];
  @override
  String get baseUrl => 'https://api.movix.site';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);
    final ny = await getTmdbNameAndYear(ctx, fetcher, tmdbId);
    final year = ny[1] as int;

    final apiUrl = tmdbId.season != null
        ? Uri.parse(
            '$baseUrl/api/tmdb/tv/${tmdbId.id}?season=${tmdbId.season}&episode=${tmdbId.episode}')
        : Uri.parse('$baseUrl/api/tmdb/movie/${tmdbId.id}');

    Map<String, dynamic> json;
    try {
      json = await fetcher.json(
          ctx,
          apiUrl,
          FetcherRequestConfig(
              headers: {'Accept': 'application/json'})) as Map<String, dynamic>;
    } on FormatException {
      // Movix sometimes serves an HTML JS-redirect interstitial instead of
      // JSON (anti-bot). Skip cleanly rather than crash the whole source.
      return const [];
    }
    final data = (tmdbId.season != null
            ? json['current_episode']
            : json) as Map<String, dynamic>?;

    if (data == null || data['player_links'] == null) return const [];

    final playerLinks = data['player_links'] as List<dynamic>;
    final iframeSrc = data['iframe_src']?.toString() ?? '';
    final tmdbTitle = (json['tmdb_details']
            as Map<String, dynamic>?)?['title']?.toString() ??
        '';
    final title = tmdbId.season != null
        ? '$tmdbTitle ${tmdbId.formatSeasonAndEpisode()}'
        : '$tmdbTitle ($year)';

    return playerLinks
        .map((p) => Uri.parse(
            (p as Map<String, dynamic>)['decoded_url'] as String))
        .map((u) => SourceResult(
              url: u,
              meta: Meta(
                countryCodes: const [CountryCode.fr],
                referer: iframeSrc,
                title: title,
              ),
            ))
        .toList();
  }
}
