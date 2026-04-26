/// Port of webstreamr/src/extractor/ExtractorRegistry.ts
library;

import '../types.dart';
import '../utils/cache.dart';
import '../utils/config.dart';
import '../utils/error_strings.dart';
import 'extractor.dart';

class ExtractorRegistry {
  final WsLogger logger;
  final List<Extractor> extractors;

  final Cacheable<List<UrlResult>> _urlResultCache = Cacheable<List<UrlResult>>();
  final Cacheable<List<UrlResult>> _lazyUrlResultCache =
      Cacheable<List<UrlResult>>();

  ExtractorRegistry(this.logger, this.extractors);

  Future<List<UrlResult>> handle(Context ctx, Uri url,
      [Meta? meta, bool allowLazy = false]) async {
    Extractor? extractor;
    for (final e in extractors) {
      if (isExtractorDisabled(ctx.config, e.id)) continue;
      if (e.supports(ctx, url)) {
        extractor = e;
        break;
      }
    }
    if (extractor == null) {
      logger('warn',
          'No extractor matched embed url=$url (host=${url.host}) src=${meta?.sourceId}');
      return const [];
    }

    final normalized = extractor.normalize(url);
    final cacheKey = _cacheKey(ctx, extractor, normalized);

    final stored = _urlResultCache.getRaw(cacheKey);
    if (stored != null) {
      final ttl = stored.expiresAtMs - DateTime.now().millisecondsSinceEpoch;
      if (ttl > 0) {
        return stored.value
            .map((r) => UrlResult(
                  url: r.url,
                  format: r.format,
                  isExternal: r.isExternal,
                  ytId: r.ytId,
                  error: r.error,
                  label: r.label,
                  ttl: ttl,
                  meta: r.meta,
                  notWebReady: r.notWebReady,
                  requestHeaders: r.requestHeaders,
                ))
            .toList();
      }
    }

    final lazyResults = _lazyUrlResultCache.get(normalized.toString()) ?? const [];

    logger('info', 'Extract $url using ${extractor.id} extractor');

    final mergedMeta =
        (meta ?? Meta()).merge(lazyResults.isNotEmpty ? lazyResults.first.meta : null);
    mergedMeta.extractorId = extractor.id;

    final urlResults = await extractor.extract(ctx, normalized, mergedMeta);

    final hasMeta = meta != null;
    final hasError = urlResults.any((r) => r.error != null);

    if (!hasMeta || hasError) {
      _urlResultCache.delete(cacheKey);
      _lazyUrlResultCache.delete(normalized.toString());
      return urlResults;
    }

    final ttl = urlResults.isNotEmpty
        ? extractor.ttl
        : const Duration(hours: 12);
    _urlResultCache.set(cacheKey, urlResults, ttl);
    if (extractor.id != 'external') {
      _lazyUrlResultCache.set(
          normalized.toString(), urlResults, const Duration(days: 30));
    }
    return urlResults;
  }

  String _cacheKey(Context ctx, Extractor extractor, Uri url) {
    var suffix = '';
    if (extractor.viaMediaFlowProxy) {
      suffix += '_${ctx.config['mediaFlowProxyUrl']}';
    }
    if (extractor.cacheVersion != null) {
      suffix += '_${extractor.cacheVersion}';
    }
    return '${extractor.id}_$url$suffix';
  }
}
