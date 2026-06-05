/// Port of webstreamr/src/source/VixSrc.ts
library;

import '../types.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class VixSrcSource extends Source {
  VixSrcSource(super.fetcher);

  @override
  String get id => 'vixsrc';
  @override
  String get label => 'VixSrc';
  @override
  List<String> get contentTypes => const ['movie', 'series'];
  @override
  List<CountryCode> get countryCodes =>
      const [CountryCode.multi, CountryCode.it];
  @override
  String get baseUrl => 'https://vixsrc.to';
  @override
  int get priority => 1;

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);
    final ny = await getTmdbNameAndYear(ctx, fetcher, tmdbId);
    final name = ny[0] as String;
    final year = ny[1] as int;

    var title = name;
    if (tmdbId.season != null) {
      title += ' ${tmdbId.formatSeasonAndEpisode()}';
    } else {
      title += ' ($year)';
    }

    final url = tmdbId.season != null
        ? Uri.parse(
            '$baseUrl/tv/${tmdbId.id}/${tmdbId.season}/${tmdbId.episode}')
        : Uri.parse('$baseUrl/movie/${tmdbId.id}');

    return [SourceResult(url: url, meta: Meta(title: title))];
  }
}
