/// Port of webstreamr/src/extractor/Extractor.ts
library;

import '../errors.dart';
import '../types.dart';
import '../utils/fetcher.dart';

abstract class Extractor {
  String get id;
  String get label;
  Duration get ttl => const Duration(minutes: 15);
  int? get cacheVersion => null;
  bool get viaMediaFlowProxy => false;

  final Fetcher fetcher;
  Extractor(this.fetcher);

  bool supports(Context ctx, Uri url);

  Uri normalize(Uri url) => url;

  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta);

  Future<List<UrlResult>> extract(Context ctx, Uri url, Meta meta) async {
    try {
      final results = await extractInternal(ctx, url, meta);
      return results
          .map((r) => UrlResult(
                url: r.url,
                format: r.format,
                isExternal: r.isExternal,
                ytId: r.ytId,
                error: r.error,
                label: _formatLabel(r.label ?? label),
                ttl: ttl.inMilliseconds,
                meta: r.meta,
                requestHeaders: r.requestHeaders,
              ))
          .toList();
    } catch (error) {
      if (error is NotFoundError) return const [];
      return [
        UrlResult(
          url: url,
          format: Format.unknown,
          isExternal: true,
          error: error,
          label: _formatLabel(label),
          ttl: 0,
          meta: meta,
        ),
      ];
    }
  }

  String _formatLabel(String l) => viaMediaFlowProxy ? '$l (MFP)' : l;
}
