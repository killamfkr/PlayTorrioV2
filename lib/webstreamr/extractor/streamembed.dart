/// Port of webstreamr/src/extractor/StreamEmbed.ts
library;

import 'dart:convert';

import '../errors.dart';
import '../types.dart';
import '../utils/fetcher.dart';
import 'extractor.dart';

class StreamEmbed extends Extractor {
  StreamEmbed(super.fetcher);

  @override
  String get id => 'streamembed';
  @override
  String get label => 'StreamEmbed';
  @override
  Duration get ttl => const Duration(days: 3);

  @override
  bool supports(Context ctx, Uri url) =>
      RegExp(r'bullstream|mp4player|watch\.gxplayer').hasMatch(url.host);

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final html =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    if (RegExp(r'Video is not ready').hasMatch(html)) throw NotFoundError();

    final m = RegExp(r'video ?= ?(.*);').firstMatch(html);
    if (m == null) throw StateError('StreamEmbed: video= missing');
    final video = jsonDecode(m.group(1)!) as Map<String, dynamic>;
    final origin = '${url.scheme}://${url.host}';
    final m3u8 = Uri.parse(
        '$origin/m3u8/${video['uid']}/${video['md5']}/master.txt'
        '?s=1&id=${video['id']}&cache=${video['status']}');
    final qualityList =
        jsonDecode(video['quality'] as String) as List<dynamic>;

    final out = meta.clone();
    out.height = int.tryParse('${qualityList.first}');
    out.title = Uri.decodeComponent(video['title'] as String);

    return [
      InternalUrlResult(url: m3u8, format: Format.hls, meta: out),
    ];
  }
}
