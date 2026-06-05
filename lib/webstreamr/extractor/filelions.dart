/// Port of webstreamr/src/extractor/FileLions.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../types.dart';
import '../utils/bytes.dart';
import '../utils/fetcher.dart';
import '../utils/media_flow_proxy.dart';
import '../utils/unpacker.dart';
import 'extractor.dart';

const _kHosts = {
  '6sfkrspw4u.sbs',
  'ajmidyadfihayh.sbs',
  'alhayabambi.sbs',
  'anime7u.com',
  'azipcdn.com',
  'bingezove.com',
  'callistanise.com',
  'coolciima.online',
  'dhtpre.com',
  'dingtezuni.com',
  'dintezuvio.com',
  'e4xb5c2xnz.sbs',
  'egsyxutd.sbs',
  'fdewsdc.sbs',
  'gsfomqu.sbs',
  'javplaya.com',
  'katomen.online',
  'lumiawatch.top',
  'minochinos.com',
  'mivalyo.com',
  'moflix-stream.click',
  'motvy55.store',
  'movearnpre.com',
  'peytonepre.com',
  'ryderjet.com',
  'smoothpre.com',
  'taylorplayer.com',
  'techradar.ink',
  'videoland.sbs',
  'vidhide.com',
  'vidhide.fun',
  'vidhidefast.com',
  'vidhidehub.com',
  'vidhideplus.com',
  'vidhidepre.com',
  'vidhidepro.com',
  'vidhidevip.com',
};

class FileLions extends Extractor {
  FileLions(super.fetcher);

  @override
  String get id => 'filelions';
  @override
  String get label => 'FileLions';
  @override
  bool get viaMediaFlowProxy => true;

  @override
  bool supports(Context ctx, Uri url) {
    final ok = RegExp(r'.*lions?').hasMatch(url.host) || _kHosts.contains(url.host);
    return ok && supportsMediaFlowProxy(ctx);
  }

  @override
  Uri normalize(Uri url) => Uri.parse(url
      .toString()
      .replaceFirst('/v/', '/f/')
      .replaceFirst('/download/', '/f/')
      .replaceFirst('/file/', '/f/'));

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final html =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    if (html.contains('This video can be watched as embed only')) {
      return extractInternal(
          ctx, Uri.parse(url.toString().replaceFirst('/f/', '/v/')), meta);
    }
    if (RegExp(r'File Not Found|deleted by administration').hasMatch(html)) {
      throw NotFoundError();
    }

    final unpacked = unpackEval(html);
    final hM = RegExp(r'(\d{3,})p').firstMatch(unpacked);
    final sM = RegExp(r'([\d.]+ ?[GM]B)').firstMatch(html);
    final doc = html_parser.parse(html);
    final title =
        doc.querySelector('meta[name="description"]')?.attributes['content'];

    final out = meta.clone();
    if (hM != null) out.height = int.tryParse(hM.group(1)!);
    if (sM != null) out.bytes = parseBytes(sM.group(1));
    if (title != null && title.isNotEmpty) out.title = title;

    return [
      InternalUrlResult(
        url: await buildMediaFlowProxyExtractorStreamUrl(
            ctx, fetcher, 'FileLions', url, headers),
        format: Format.hls,
        meta: out,
      ),
    ];
  }
}
