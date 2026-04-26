/// Port of webstreamr/src/source/Frembed.ts
library;

import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class FrembedSource extends Source {
  FrembedSource(super.fetcher);

  @override
  String get id => 'frembed';
  @override
  String get label => 'Frembed';
  @override
  List<String> get contentTypes => const ['movie', 'series'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.fr];
  @override
  String get baseUrl => 'https://frembed.work';

  Uri? _resolvedBase;
  DateTime? _resolvedAt;
  Future<Uri> _getBaseUrl(Context ctx) async {
    final now = DateTime.now();
    if (_resolvedBase != null &&
        _resolvedAt != null &&
        now.difference(_resolvedAt!) < const Duration(hours: 1)) {
      return _resolvedBase!;
    }
    _resolvedBase = await fetcher.getFinalRedirectUrl(ctx, Uri.parse(baseUrl));
    _resolvedAt = now;
    return _resolvedBase!;
  }

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final tmdbId = await getTmdbId(ctx, fetcher, id);
    final ny = await getTmdbNameAndYear(ctx, fetcher, tmdbId);
    final year = ny[1] as int;

    final base = await _getBaseUrl(ctx);
    final origin = '${base.scheme}://${base.host}';

    final apiUrl = tmdbId.season != null
        ? base.resolve(
            '/api/series?id=${tmdbId.id}&sa=${tmdbId.season}&epi=${tmdbId.episode}&idType=tmdb')
        : base.resolve('/api/films?id=${tmdbId.id}&idType=tmdb');

    final json = await fetcher.json(
            ctx, apiUrl, FetcherRequestConfig(headers: {'Referer': origin}))
        as Map<String, dynamic>;

    final urls = <Uri>[];
    for (final entry in json.entries) {
      final k = entry.key;
      final v = entry.value;
      if (!k.startsWith('link')) continue;
      if (v is! String || v.isEmpty) continue;
      if (v.contains(',https')) continue;
      try {
        final resolved = await fetcher.getFinalRedirectUrl(
          ctx,
          base.resolve(v.trim()),
          FetcherRequestConfig(headers: {'Referer': '$origin/'}),
        );
        urls.add(resolved);
      } catch (_) {
        // skip invalid
      }
    }

    final apiTitle = json['title']?.toString() ?? '';
    final title = tmdbId.season != null
        ? '$apiTitle ${tmdbId.formatSeasonAndEpisode()}'
        : '$apiTitle ($year)';

    return urls
        .map((u) => SourceResult(
              url: u,
              meta: Meta(
                countryCodes: const [CountryCode.fr],
                referer: origin,
                title: title,
              ),
            ))
        .toList();
  }
}
