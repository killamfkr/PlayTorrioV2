/// Port of webstreamr/src/extractor/SuperVideo.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../types.dart';
import '../utils/bytes.dart';
import '../utils/fetcher.dart';
import '../utils/height.dart';
import '../utils/unpacker.dart';
import 'extractor.dart';

class SuperVideo extends Extractor {
  SuperVideo(super.fetcher);

  @override
  String get id => 'supervideo';
  @override
  String get label => 'SuperVideo';
  @override
  Duration get ttl => const Duration(hours: 3);

  @override
  bool supports(Context ctx, Uri url) => url.host.contains('supervideo');

  @override
  Uri normalize(Uri url) => Uri.parse(url
      .toString()
      .replaceFirst('/e/', '/')
      .replaceFirst('/k/', '/')
      .replaceFirst('/embed-', '/'));

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final html =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    if (html.contains('This video can be watched as embed only')) {
      return extractInternal(
          ctx,
          Uri.parse('${url.scheme}://${url.host}/e${url.path}'),
          meta);
    }
    if (RegExp(r"'?The file was deleted|The file expired|Video is processing")
        .hasMatch(html)) {
      throw NotFoundError();
    }
    final playlistUrl =
        extractUrlFromPacked(html, [RegExp(r'sources:\[\{file:"(.*?)"')]);
    final playlistHeaders = {'Referer': 'https://supervideo.cc/'};

    final hsM = RegExp(r'\d{3,}x(\d{3,}), ([\d.]+ ?[GM]B)').firstMatch(html);
    final size = hsM != null ? parseBytes(hsM.group(2)) : null;
    final height = hsM != null
        ? int.tryParse(hsM.group(1)!)
        : (meta.height ??
            await guessHeightFromPlaylist(ctx, fetcher, playlistUrl,
                FetcherRequestConfig(headers: playlistHeaders)));

    final doc = html_parser.parse(html);
    final title = doc.querySelector('.download__title')?.text.trim();

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
