/// Port of webstreamr/src/extractor/Vidora.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/height.dart';
import '../utils/unpacker.dart';
import 'extractor.dart';

class Vidora extends Extractor {
  Vidora(super.fetcher);

  @override
  String get id => 'vidora';
  @override
  String get label => 'Vidora';
  @override
  Duration get ttl => const Duration(hours: 12);

  @override
  bool supports(Context ctx, Uri url) => url.host.contains('vidora');

  @override
  Uri normalize(Uri url) =>
      Uri.parse(url.toString().replaceFirst('/embed/', '/'));

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final html = await fetcher.text(ctx, url);
    final doc = html_parser.parse(html);
    final title = doc.querySelector('title')?.text.trim().replaceFirst(
            RegExp(r'^Watch '), '').trim();

    final m3u8 = extractUrlFromPacked(html, [RegExp(r'file: ?"(.*?)"')]);
    final origin = '${url.scheme}://${url.host}';
    final headers = {'Origin': origin};

    final out = meta.clone();
    out.height ??= await guessHeightFromPlaylist(
        ctx, fetcher, m3u8, FetcherRequestConfig(headers: headers));
    if (title != null && title.isNotEmpty) out.title = title;

    return [
      InternalUrlResult(
        url: m3u8,
        format: Format.hls,
        meta: out,
        requestHeaders: headers,
      ),
    ];
  }
}
