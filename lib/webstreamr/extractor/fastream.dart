/// Port of webstreamr/src/extractor/Fastream.ts
library;

import '../errors.dart';
import '../types.dart';
import '../utils/bytes.dart';
import '../utils/fetcher.dart';
import '../utils/media_flow_proxy.dart';
import 'extractor.dart';

class Fastream extends Extractor {
  Fastream(super.fetcher);

  @override
  String get id => 'fastream';
  @override
  String get label => 'Fastream';
  @override
  bool get viaMediaFlowProxy => true;

  @override
  bool supports(Context ctx, Uri url) =>
      url.host.contains('fastream') && supportsMediaFlowProxy(ctx);

  @override
  Uri normalize(Uri url) => Uri.parse(
      url.toString().replaceFirst('/e/', '/embed-').replaceFirst('/d/', '/embed-'));

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final downloadUrl =
        Uri.parse(url.toString().replaceFirst('/embed-', '/d/'));
    final html = await fetcher.text(
        ctx, downloadUrl, FetcherRequestConfig(headers: headers));
    if (RegExp(r'No such file').hasMatch(html)) throw NotFoundError();

    final playlistUrl = await buildMediaFlowProxyExtractorStreamUrl(
        ctx, fetcher, 'Fastream', url, headers);

    final m = RegExp(r'\d{3,}x(\d{3,}), ([\d.]+ ?[GM]B)').firstMatch(html);
    final t = RegExp(r'>Download (.*?)<').firstMatch(html);

    final out = meta.clone();
    if (m != null) {
      out.height = int.tryParse(m.group(1)!);
      out.bytes = parseBytes(m.group(2));
    }
    if (t != null) out.title = t.group(1);

    return [
      InternalUrlResult(url: playlistUrl, format: Format.hls, meta: out),
    ];
  }
}
