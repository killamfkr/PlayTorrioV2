/// Port of webstreamr/src/extractor/HubCloud.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/bytes.dart';
import '../utils/fetcher.dart';
import '../utils/language.dart';
import '../utils/resolution.dart';
import 'extractor.dart';

class HubCloud extends Extractor {
  HubCloud(super.fetcher);

  @override
  String get id => 'hubcloud';
  @override
  String get label => 'HubCloud';
  @override
  Duration get ttl => const Duration(hours: 12);
  @override
  int? get cacheVersion => 1;

  @override
  bool supports(Context ctx, Uri url) =>
      url.host.contains('hubcloud') || url.host.contains('vcloud');

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final redirectHtml =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    final m = RegExp(r"var url ?= ?'(.*?)'").firstMatch(redirectHtml);
    if (m == null) return const [];
    final linksUrl = Uri.parse(m.group(1)!);
    final linksHeaders = {'Referer': url.toString()};
    final linksHtml = await fetcher.text(
        ctx, linksUrl, FetcherRequestConfig(headers: linksHeaders));

    final doc = html_parser.parse(linksHtml);
    final title = doc.querySelector('title')?.text.trim() ?? '';
    final ccs = <CountryCode>{
      ...?meta.countryCodes,
      ...findCountryCodes(title),
    }.toList();
    final height = meta.height ?? findHeight(title);
    final size = parseBytes(doc.querySelector('#size')?.text);

    final out = <InternalUrlResult>[];
    for (final a in doc.querySelectorAll('a')) {
      final text = a.text;
      final href = a.attributes['href'];
      if (href == null) continue;

      if (text.contains('FSL') && !text.contains('FSLv2')) {
        final m = meta.clone();
        if (size != null) m.bytes = size;
        m.extractorId = '${id}_fsl';
        m.countryCodes = ccs;
        if (height != null) m.height = height;
        m.title = title;
        out.add(InternalUrlResult(
          url: Uri.parse(href),
          format: Format.unknown,
          label: '$label (FSL)',
          meta: m,
        ));
      } else if (text.contains('FSLv2')) {
        final m = meta.clone();
        if (size != null) m.bytes = size;
        m.extractorId = '${id}_fslv2';
        m.countryCodes = ccs;
        if (height != null) m.height = height;
        m.title = title;
        out.add(InternalUrlResult(
          url: Uri.parse(href),
          format: Format.unknown,
          label: '$label (FSLv2)',
          meta: m,
        ));
      } else if (text.contains('PixelServer')) {
        final userUrl = Uri.parse(href.replaceFirst('/api/file/', '/u/'));
        final apiUrl = Uri.parse(userUrl.toString()
            .replaceFirst('/u/', '/api/file/'));
        final qp = Map<String, String>.from(apiUrl.queryParameters);
        qp['download'] = '';
        final finalUrl = apiUrl.replace(queryParameters: qp);
        final m = meta.clone();
        if (size != null) m.bytes = size;
        m.extractorId = '${id}_pixelserver';
        m.countryCodes = ccs;
        if (height != null) m.height = height;
        m.title = title;
        out.add(InternalUrlResult(
          url: finalUrl,
          format: Format.unknown,
          label: '$label (PixelServer)',
          meta: m,
          requestHeaders: {'Referer': userUrl.toString()},
        ));
      }
    }
    return out;
  }
}
