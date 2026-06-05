/// Port of webstreamr/src/source/VidSrc.ts
library;

import '../types.dart';
import '../utils/id.dart';
import 'source.dart';

class VidSrcSource extends Source {
  VidSrcSource(super.fetcher);

  @override
  String get id => 'vidsrc';
  @override
  String get label => 'VidSrc';
  @override
  int? get useOnlyWithMaxUrlsFound => 0;
  @override
  List<String> get contentTypes => const ['movie', 'series'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.multi];
  @override
  String get baseUrl => 'https://vidsrc-embed.ru';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final url = id.season != null
        ? Uri.parse('$baseUrl/embed/tv/${id is ImdbId ? id.id : (id as TmdbId).id}/${id.season}-${id.episode}')
        : Uri.parse(
            '$baseUrl/embed/movie/${id is ImdbId ? id.id : (id as TmdbId).id}');
    return [
      SourceResult(
        url: url,
        meta: Meta(countryCodes: const [CountryCode.multi]),
      ),
    ];
  }
}
