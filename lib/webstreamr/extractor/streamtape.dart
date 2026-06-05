/// Port of webstreamr/src/extractor/Streamtape.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/bytes.dart';
import '../utils/fetcher.dart';
import '../utils/media_flow_proxy.dart';
import 'extractor.dart';

const _kHosts = {
  'strtape.cloud',
  'streamta.pe',
  'strcloud.link',
  'strcloud.club',
  'strtpe.link',
  'scloud.online',
  'stape.fun',
  'streamadblockplus.com',
  'shavetape.cash',
  'streamta.site',
  'streamadblocker.xyz',
  'tapewithadblock.org',
  'adblocktape.wiki',
  'antiadtape.com',
  'tapeblocker.com',
  'streamnoads.com',
  'tapeadvertisement.com',
  'tapeadsenjoyer.com',
  'watchadsontape.com',
};

class Streamtape extends Extractor {
  Streamtape(super.fetcher);

  @override
  String get id => 'streamtape';
  @override
  String get label => 'Streamtape';
  @override
  bool get viaMediaFlowProxy => true;

  @override
  bool supports(Context ctx, Uri url) {
    final ok = url.host.contains('streamtape') || _kHosts.contains(url.host);
    return ok && supportsMediaFlowProxy(ctx);
  }

  @override
  Uri normalize(Uri url) =>
      Uri.parse(url.toString().replaceFirst('/e/', '/v/'));

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    // Touch /e/ to get a 404 for missing files.
    await fetcher.text(
        ctx,
        Uri.parse(url.toString().replaceFirst('/v/', '/e/')),
        FetcherRequestConfig(headers: headers));

    final html =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    final sM = RegExp(r'([\d.]+ ?[GM]B)').firstMatch(html);
    final doc = html_parser.parse(html);
    final title =
        doc.querySelector('meta[name="og:title"]')?.attributes['content'];

    final out = meta.clone();
    if (title != null && title.isNotEmpty) out.title = title;
    if (sM != null) out.bytes = parseBytes(sM.group(1));

    return [
      InternalUrlResult(
        url: buildMediaFlowProxyExtractorRedirectUrl(
            ctx, 'Streamtape', url, headers),
        format: Format.mp4,
        meta: out,
      ),
    ];
  }
}
