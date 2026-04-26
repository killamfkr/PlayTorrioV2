/// Port of webstreamr/src/extractor/Dropload.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../types.dart';
import '../utils/bytes.dart';
import '../utils/fetcher.dart';
import '../utils/height.dart';
import '../utils/unpacker.dart';
import 'extractor.dart';

class Dropload extends Extractor {
  Dropload(super.fetcher);

  @override
  String get id => 'dropload';
  @override
  String get label => 'Dropload';
  @override
  Duration get ttl => const Duration(hours: 3);

  @override
  bool supports(Context ctx, Uri url) =>
      RegExp(r'dropload|dr0pstream').hasMatch(url.host);

  @override
  Uri normalize(Uri url) => Uri.parse(url
      .toString()
      .replaceFirst('/d/', '/')
      .replaceFirst('/e/', '/')
      .replaceFirst('/embed-', '/'));

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final html =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    if (html.contains('File Not Found') || html.contains('Pending in queue')) {
      throw NotFoundError();
    }
    Uri playlistUrl;
    try {
      playlistUrl = extractUrlFromPacked(
          html, [RegExp(r'sources:\[\{file:"(.*?)"')]);
    } on FormatException {
      // Newer dr0pstream pages no longer use packed JS — fall back to the
      // raw HTML search.
      final m = RegExp(r'sources:\s*\[\s*\{\s*file:\s*"(https?:[^"]+)"')
              .firstMatch(html) ??
          RegExp(r'''file:\s*["'](https?:[^"']+\.m3u8[^"']*)["']''')
              .firstMatch(html) ??
          RegExp(r'''["'](https?:[^"']+\.m3u8[^"']*)["']''').firstMatch(html);
      if (m == null) rethrow;
      playlistUrl = Uri.parse(m.group(1)!);
    }
    final playlistHeaders = {'Referer': 'https://dr0pstream.com/'};

    final hM = RegExp(r'\d{3,}x(\d{3,}),').firstMatch(html);
    var height = hM != null ? int.tryParse(hM.group(1)!) : meta.height;
    height ??= await guessHeightFromPlaylist(ctx, fetcher, playlistUrl,
        FetcherRequestConfig(headers: playlistHeaders));

    final sM = RegExp(r'([\d.]+ ?[GM]B)').firstMatch(html);
    final size = parseBytes(sM?.group(1));

    final doc = html_parser.parse(html);
    final title = doc.querySelector('.videoplayer h1')?.text.trim();

    final out = meta.clone();
    if (title != null && title.isNotEmpty) out.title = title;
    if (size != null) out.bytes = size;
    if (height != null) out.height = height;

    return [
      InternalUrlResult(
        url: playlistUrl,
        format: Format.hls,
        meta: out,
        requestHeaders: playlistHeaders,
      ),
    ];
  }
}
