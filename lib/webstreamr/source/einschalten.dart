/// Port of webstreamr/src/source/Einschalten.ts
library;

import '../types.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class EinschaltenSource extends Source {
  EinschaltenSource(super.fetcher);

  @override
  String get id => 'einschalten';
  @override
  String get label => 'Einschalten';
  @override
  List<String> get contentTypes => const ['movie'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.de];
  @override
  String get baseUrl => 'https://einschalten.in';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);
    final data = await fetcher.json(
            ctx, Uri.parse('$baseUrl/api/movies/${tmdbId.id}/watch'))
        as Map<String, dynamic>;
    final title = data['releaseName'] as String;
    final streamUrl = Uri.parse(data['streamUrl'] as String);
    return [
      SourceResult(
        url: streamUrl,
        meta: Meta(
          countryCodes: const [CountryCode.de],
          referer: '$baseUrl/movies/${tmdbId.id}',
          title: title,
        ),
      ),
    ];
  }
}
