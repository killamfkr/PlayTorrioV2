/// Port of webstreamr/src/extractor/VidSrc.ts
library;

import 'dart:math' as math;

import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/height.dart';
import 'extractor.dart';

class VidSrc extends Extractor {
  final List<String> domains;
  VidSrc(super.fetcher, this.domains)
      : assert(domains.isNotEmpty, 'VidSrc needs at least one domain');

  @override
  String get id => 'vidsrc';
  @override
  String get label => 'VidSrc';
  @override
  Duration get ttl => const Duration(hours: 3);

  @override
  bool supports(Context ctx, Uri url) =>
      RegExp(r'vidsrc|vsrc').hasMatch(url.host);

  String _randomIp() {
    final r = math.Random();
    return '${r.nextInt(223) + 1}.${r.nextInt(256)}.${r.nextInt(256)}.${r.nextInt(256)}';
  }

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final newCtx = Context(
        hostUrl: ctx.hostUrl, id: ctx.id, ip: _randomIp(), config: ctx.config);
    return _tryDomains(newCtx, url, meta, List.of(domains));
  }

  Future<List<InternalUrlResult>> _tryDomains(
      Context ctx, Uri url, Meta meta, List<String> remaining) async {
    final i = math.Random().nextInt(remaining.length);
    final domain = remaining.removeAt(i);
    final newUrl = url.replace(host: domain);

    String html;
    try {
      html = await fetcher.text(
          ctx, newUrl, FetcherRequestConfig(queueLimit: 1));
    } catch (e) {
      if (remaining.isNotEmpty &&
          (e is TooManyRequestsError || e is BlockedError)) {
        return _tryDomains(ctx, url, meta, remaining);
      }
      rethrow;
    }

    // The server-rendered HTML is HTML-commented out; strip the wrapper.
    final doc = html_parser
        .parse(html.replaceFirst('<!--', '').replaceFirst('-->', ''));
    final iframeSrc = doc.querySelector('#player_iframe')?.attributes['src'];
    if (iframeSrc == null) throw StateError('VidSrc: no #player_iframe');
    final iframeUrl =
        Uri.parse(iframeSrc.replaceFirst(RegExp(r'^//'), 'https://'));
    final iframeOrigin = '${iframeUrl.scheme}://${iframeUrl.host}';
    final title = doc.querySelector('title')?.text.trim();

    final results = <InternalUrlResult>[];
    for (final el in doc.querySelectorAll('.server')) {
      final serverName = el.text;
      final dataHash = el.attributes['data-hash'];
      if (serverName != 'CloudStream Pro' || dataHash == null) continue;

      final rcpUrl = Uri.parse('$iframeOrigin/rcp/$dataHash');
      final iframeHtml = await fetcher.text(ctx, rcpUrl,
          FetcherRequestConfig(
              headers: {'Referer': '${newUrl.scheme}://${newUrl.host}'}));
      final srcM = RegExp("src:\\s?'(.*)'").firstMatch(iframeHtml);
      if (srcM == null) continue;
      final playerUrl = Uri.parse(srcM.group(1)!).hasScheme
          ? Uri.parse(srcM.group(1)!)
          : Uri.parse('$iframeOrigin${srcM.group(1)}');

      final playerHtml = await fetcher.text(ctx, playerUrl,
          FetcherRequestConfig(headers: {'Referer': rcpUrl.toString()}));
      final fileM =
          RegExp(r'(https:\/\/.*?\{v\d\}.*?) or').firstMatch(playerHtml);
      if (fileM == null) continue;
      final m3u8 = Uri.parse(
          fileM.group(1)!.replaceAll(RegExp(r'\{v\d\}'), iframeUrl.host));

      final out = meta.clone();
      out.height ??= await guessHeightFromPlaylist(
          ctx,
          fetcher,
          m3u8,
          FetcherRequestConfig(headers: {'Referer': iframeUrl.toString()}));
      if (title != null && title.isNotEmpty) out.title = title;

      results.add(InternalUrlResult(
        url: m3u8,
        format: Format.hls,
        label: serverName,
        meta: out,
      ));
    }
    return results;
  }
}
