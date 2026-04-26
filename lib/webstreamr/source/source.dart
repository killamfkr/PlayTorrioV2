/// Port of webstreamr/src/source/Source.ts. ContentType is a String here
/// (`'movie'` or `'series'`) — same values stremio-addon-sdk uses.
library;

import '../errors.dart';
import '../types.dart';
import '../utils/cache.dart';
import '../utils/fetcher.dart';
import '../utils/id.dart';

abstract class Source {
  String get id;
  String get label;
  Duration get ttl => const Duration(hours: 12);
  int? get useOnlyWithMaxUrlsFound => null;
  List<String> get contentTypes; // 'movie' | 'series'
  List<CountryCode> get countryCodes;
  String get baseUrl;
  int get priority => 0;

  final Fetcher fetcher;
  Source(this.fetcher);

  static final Cacheable<List<SourceResult>> _cache =
      Cacheable<List<SourceResult>>();

  Future<List<SourceResult>> handleInternal(Context ctx, String type, Id id);

  Future<List<SourceResult>> handle(Context ctx, String type, Id id) async {
    final cacheKey = '${this.id}_${id.toString()}';
    var results = _cache.get(cacheKey);
    if (results == null) {
      try {
        results = await handleInternal(ctx, type, id);
      } on NotFoundError {
        results = const [];
      }
      _cache.set(cacheKey, results, ttl);
    }
    if (countryCodes.contains(CountryCode.multi)) return results;
    return results
        .where((r) =>
            r.meta.countryCodes
                ?.any((cc) => ctx.config.containsKey(cc.name)) ??
            false)
        .toList();
  }
}
