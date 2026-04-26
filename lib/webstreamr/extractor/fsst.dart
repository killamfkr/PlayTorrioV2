/// Port of webstreamr/src/extractor/Fsst.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/fetcher.dart';
import 'extractor.dart';

class Fsst extends Extractor {
  Fsst(super.fetcher);

  @override
  String get id => 'fsst';
  @override
  String get label => 'Fsst';
  @override
  Duration get ttl => const Duration(hours: 3);

  @override
  bool supports(Context ctx, Uri url) => url.host.contains('fsst');

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final html = await fetcher.text(ctx, url,
        FetcherRequestConfig(headers: headers, noProxyHeaders: true));
    final doc = html_parser.parse(html);
    final title = doc.querySelector('title')?.text.trim();

    final m = RegExp(r'file:"(.*)"').firstMatch(html);
    if (m == null) throw StateError('Fsst: file: missing');
    final last = m.group(1)!.split(',').last;
    final hu = RegExp(r'\[?([\d]*)p?\]?(.*)').firstMatch(last)!;
    final fileHref = hu.group(2)!;

    final finalUrl = await fetcher.getFinalRedirectUrl(
        ctx,
        Uri.parse(fileHref),
        FetcherRequestConfig(headers: headers, noProxyHeaders: true),
        1);

    final out = meta.clone();
    out.height = int.tryParse(hu.group(1) ?? '');
    if (title != null && title.isNotEmpty) out.title = title;

    return [
      InternalUrlResult(url: finalUrl, format: Format.mp4, meta: out),
    ];
  }
}
