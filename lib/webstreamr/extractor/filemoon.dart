/// Port of webstreamr/src/extractor/FileMoon.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/media_flow_proxy.dart';
import '../utils/unpacker.dart';
import 'extractor.dart';

const _kHosts = {
  '1azayf9w.xyz',
  '222i8x.lol',
  '81u6xl9d.xyz',
  '8mhlloqo.fun',
  '96ar.com',
  'bf0skv.org',
  'boosteradx.online',
  'c1z39.com',
  'cinegrab.com',
  'f51rm.com',
  'furher.in',
  'kerapoxy.cc',
  'l1afav.net',
  'moonmov.pro',
  'smdfs40r.skin',
  'xcoic.com',
  'z1ekv717.fun',
};

class FileMoon extends Extractor {
  FileMoon(super.fetcher);

  @override
  String get id => 'filemoon';
  @override
  String get label => 'FileMoon';
  @override
  bool get viaMediaFlowProxy => true;

  @override
  bool supports(Context ctx, Uri url) {
    final ok = url.host.contains('filemoon') || _kHosts.contains(url.host);
    return ok && supportsMediaFlowProxy(ctx);
  }

  @override
  Uri normalize(Uri url) =>
      Uri.parse(url.toString().replaceFirst('/e/', '/d/'));

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta,
      [Uri? originalUrl]) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final html =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    if (RegExp(r'Page not found').hasMatch(html)) throw NotFoundError();

    final doc = html_parser.parse(html);
    final title = doc.querySelector('h3')?.text.trim();

    final iframes = RegExp(r'''iframe.*?src=["'](.*?)["']''')
        .allMatches(html)
        .toList();
    if (iframes.isNotEmpty) {
      // Use the LAST match — earlier ones are decoy/adblock catchers.
      final next = Uri.parse(iframes.last.group(1)!);
      final m = meta.clone();
      if (title != null && title.isNotEmpty) m.title = title;
      return extractInternal(ctx, next, m, url);
    }

    final playlistUrl = await buildMediaFlowProxyExtractorStreamUrl(
        ctx, fetcher, 'FileMoon', originalUrl ?? url, headers);

    final unpacked = unpackEval(html);
    final hM = RegExp(r'(\d{3,})p').firstMatch(unpacked);

    final out = meta.clone();
    if (hM != null) out.height = int.tryParse(hM.group(1)!);

    return [
      InternalUrlResult(url: playlistUrl, format: Format.hls, meta: out),
    ];
  }
}
