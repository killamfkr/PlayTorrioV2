/// Port of webstreamr/src/extractor/HubDrive.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/fetcher.dart';
import 'extractor.dart';
import 'hubcloud.dart';

class HubDrive extends Extractor {
  final HubCloud hubCloud;
  HubDrive(super.fetcher, this.hubCloud);

  @override
  String get id => 'hubdrive';
  @override
  String get label => 'HubDrive';
  @override
  Duration get ttl => const Duration(hours: 12);
  @override
  int? get cacheVersion => 1;

  @override
  bool supports(Context ctx, Uri url) => url.host.contains('hubdrive');

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final html =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    final doc = html_parser.parse(html);
    final hubCloudA = doc.querySelectorAll('a').firstWhere(
          (a) => a.text.contains('HubCloud'),
          orElse: () => html_parser.parseFragment('').nodes.isEmpty
              ? throw StateError('no anchors')
              : html_parser.parseFragment('<a></a>').children.first,
        );
    final hubCloudHref = hubCloudA.attributes['href'];
    if (hubCloudHref == null || hubCloudHref.isEmpty) return const [];
    final results = await hubCloud.extract(ctx, Uri.parse(hubCloudHref), meta);
    // hubCloud.extract returns UrlResults but Extractor.extractInternal needs
    // InternalUrlResults — convert (drop ttl, keep label).
    return results
        .map((r) => InternalUrlResult(
              url: r.url,
              format: r.format,
              isExternal: r.isExternal,
              ytId: r.ytId,
              error: r.error,
              label: r.label,
              meta: r.meta,
              requestHeaders: r.requestHeaders,
            ))
        .toList();
  }
}
