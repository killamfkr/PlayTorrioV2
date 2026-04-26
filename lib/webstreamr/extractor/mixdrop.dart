/// Port of webstreamr/src/extractor/Mixdrop.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../types.dart';
import '../utils/bytes.dart';
import '../utils/media_flow_proxy.dart';
import 'extractor.dart';

class Mixdrop extends Extractor {
  Mixdrop(super.fetcher);

  @override
  String get id => 'mixdrop';
  @override
  String get label => 'Mixdrop';
  @override
  bool get viaMediaFlowProxy => true;

  @override
  bool supports(Context ctx, Uri url) =>
      RegExp(r'mixdrop|mixdrp|mixdroop|m1xdrop').hasMatch(url.host) &&
      supportsMediaFlowProxy(ctx);

  @override
  Uri normalize(Uri url) =>
      Uri.parse(url.toString().replaceFirst('/f/', '/e/'));

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final fileUrl = Uri.parse(url.toString().replaceFirst('/e/', '/f/'));
    final html = await fetcher.text(ctx, fileUrl);
    if (RegExp(r"can't find the (file|video)").hasMatch(html)) {
      throw NotFoundError();
    }
    final sM = RegExp(r'([\d.,]+ ?[GM]B)').firstMatch(html);
    final doc = html_parser.parse(html);
    final title = doc.querySelector('.title b')?.text.trim();

    final out = meta.clone();
    if (sM != null) out.bytes = parseBytes(sM.group(1)!.replaceAll(',', ''));
    if (title != null && title.isNotEmpty) out.title = title;

    return [
      InternalUrlResult(
        url: buildMediaFlowProxyExtractorRedirectUrl(ctx, 'Mixdrop', url),
        format: Format.mp4,
        meta: out,
      ),
    ];
  }
}
