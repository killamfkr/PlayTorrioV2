/// Port of webstreamr/src/extractor/DoodStream.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../types.dart';
import '../utils/bytes.dart';
import '../utils/fetcher.dart';
import '../utils/media_flow_proxy.dart';
import 'extractor.dart';

class DoodStream extends Extractor {
  DoodStream(super.fetcher);

  @override
  String get id => 'doodstream';
  @override
  String get label => 'DoodStream';
  @override
  Duration get ttl => const Duration(hours: 6);
  @override
  bool get viaMediaFlowProxy => true;

  @override
  bool supports(Context ctx, Uri url) =>
      RegExp(r'dood|do[0-9]go|doood|dooood|ds2play|ds2video|dsvplay|d0o0d|do0od|d0000d|d000d|myvidplay|vidply|all3do|doply|vide0|vvide0|d-s')
              .hasMatch(url.host) &&
      supportsMediaFlowProxy(ctx);

  @override
  Uri normalize(Uri url) {
    final segs = url.path.replaceAll(RegExp(r'/+$'), '').split('/');
    final id = segs.last;
    return Uri.parse('http://dood.to/e/$id');
  }

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final html =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    if (RegExp(r'Video not found').hasMatch(html)) throw NotFoundError();

    final doc = html_parser.parse(html);
    final title = doc.querySelector('title')?.text.trim().replaceFirst(
        RegExp(r' - DoodStream$'), '').trim();

    final downloadHtml = await fetcher
        .text(ctx, Uri.parse(url.toString().replaceFirst('/e/', '/d/')));
    final sM = RegExp(r'([\d.]+ ?[GM]B)').firstMatch(downloadHtml);

    final out = meta.clone();
    if (title != null && title.isNotEmpty) out.title = title;
    if (sM != null) out.bytes = parseBytes(sM.group(1));

    return [
      InternalUrlResult(
        url: buildMediaFlowProxyExtractorRedirectUrl(
            ctx, 'Doodstream', url, headers),
        format: Format.mp4,
        meta: out,
      ),
    ];
  }
}
