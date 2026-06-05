/// Port of webstreamr/src/source/MegaKino.ts. The Fetcher's internal cookie
/// jar handles the Set-Cookie automatically, so we just need to do the HEAD
/// then the search.
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class MegaKinoSource extends Source {
  MegaKinoSource(super.fetcher);

  @override
  String get id => 'megakino';
  @override
  String get label => 'MegaKino';
  @override
  List<String> get contentTypes => const ['movie'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.de];
  @override
  String get baseUrl => 'https://megakino1.to';

  Uri? _resolvedBase;
  DateTime? _resolvedAt;
  Future<Uri> _getBaseUrl(Context ctx) async {
    final now = DateTime.now();
    if (_resolvedBase != null &&
        _resolvedAt != null &&
        now.difference(_resolvedAt!) < const Duration(hours: 1)) {
      return _resolvedBase!;
    }
    _resolvedBase = await fetcher.getFinalRedirectUrl(ctx, Uri.parse(baseUrl));
    _resolvedAt = now;
    return _resolvedBase!;
  }

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final imdbId = await getImdbId(ctx, fetcher, id);
    final base = await _getBaseUrl(ctx);

    // Trigger the token cookie — Fetcher's CookieJar will store it.
    await fetcher.head(ctx, base.replace(queryParameters: {'yg': 'token'}));

    final pageUrl = await _fetchPageUrl(ctx, imdbId, base);
    if (pageUrl == null) return const [];

    final html = await fetcher.text(ctx, pageUrl);
    final doc = html_parser.parse(html);
    final title = doc
        .querySelector('meta[property="og:title"]')
        ?.attributes['content']
        ?.trim();

    final out = <SourceResult>[];
    for (final iframe in doc.querySelectorAll('.video-inside iframe')) {
      final src =
          iframe.attributes['data-src'] ?? iframe.attributes['src'];
      if (src == null) continue;
      out.add(SourceResult(
        url: Uri.parse(src),
        meta: Meta(
          countryCodes: const [CountryCode.de],
          referer: pageUrl.toString(),
          title: title,
        ),
      ));
    }
    return out;
  }

  Future<Uri?> _fetchPageUrl(Context ctx, ImdbId imdbId, Uri base) async {
    final origin = '${base.scheme}://${base.host}';
    final form =
        'do=search&subaction=search&story=${Uri.encodeComponent(imdbId.id)}';
    final html = await fetcher.textPost(
        ctx,
        base,
        form,
        FetcherRequestConfig(headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': origin,
        }));
    final doc = html_parser.parse(html);
    final href =
        doc.querySelector('#dle-content a[href].poster')?.attributes['href'];
    if (href == null) return null;
    return Uri.parse(href).hasScheme
        ? Uri.parse(href)
        : base.resolve(href);
  }
}
