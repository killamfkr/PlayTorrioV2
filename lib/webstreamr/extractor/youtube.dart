/// Port of webstreamr/src/extractor/YouTube.ts
library;

import '../types.dart';
import '../utils/fetcher.dart';
import 'extractor.dart';

class YouTube extends Extractor {
  YouTube(super.fetcher);

  @override
  String get id => 'youtube';
  @override
  String get label => 'YouTube';
  @override
  Duration get ttl => const Duration(hours: 6);

  @override
  bool supports(Context ctx, Uri url) =>
      url.host.contains('youtube') && url.queryParameters.containsKey('v');

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final html =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    final m = RegExp(r'"title":\{"runs":\[\{"text":"(.*?)"').firstMatch(html);
    final out = meta.clone();
    out.title = m?.group(1);
    return [
      InternalUrlResult(
        url: url,
        format: Format.unknown,
        ytId: url.queryParameters['v'],
        meta: out,
      ),
    ];
  }
}
