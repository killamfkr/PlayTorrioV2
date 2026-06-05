/// Port of webstreamr/src/extractor/Uqload.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../types.dart';
import '../utils/media_flow_proxy.dart';
import 'extractor.dart';

class Uqload extends Extractor {
  Uqload(super.fetcher);

  @override
  String get id => 'uqload';
  @override
  String get label => 'Uqload';
  @override
  bool get viaMediaFlowProxy => true;

  @override
  bool supports(Context ctx, Uri url) =>
      url.host.contains('uqload') && supportsMediaFlowProxy(ctx);

  @override
  Uri normalize(Uri url) =>
      Uri.parse(url.toString().replaceFirst('/embed-', '/'));

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final html = await fetcher.text(ctx, url);
    if (RegExp(r'File Not Found').hasMatch(html)) throw NotFoundError();

    final hM = RegExp(r'\d{3,}x(\d{3,})').firstMatch(html);
    final doc = html_parser.parse(html);
    final title = doc.querySelector('h1')?.text.trim();

    final out = meta.clone();
    if (title != null && title.isNotEmpty) out.title = title;
    if (hM != null) out.height = int.tryParse(hM.group(1)!);

    return [
      InternalUrlResult(
        url: buildMediaFlowProxyExtractorRedirectUrl(ctx, 'Uqload', url),
        format: Format.mp4,
        meta: out,
      ),
    ];
  }
}
