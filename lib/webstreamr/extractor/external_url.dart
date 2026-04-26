/// Port of webstreamr/src/extractor/ExternalUrl.ts
library;

import '../types.dart';
import '../utils/config.dart';
import 'extractor.dart';

class ExternalUrl extends Extractor {
  ExternalUrl(super.fetcher);

  @override
  String get id => 'external';
  @override
  String get label => 'External';
  @override
  Duration get ttl => const Duration(hours: 6);

  @override
  bool supports(Context ctx, Uri url) => showExternalUrls(ctx.config);

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    return [
      InternalUrlResult(
        url: url,
        format: Format.unknown,
        isExternal: true,
        label: url.host,
        meta: meta,
      ),
    ];
  }
}
