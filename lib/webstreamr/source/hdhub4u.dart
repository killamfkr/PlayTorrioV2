/// Port of webstreamr/src/source/HDHub4u.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/hd_hub_helper.dart';
import '../utils/id.dart';
import '../utils/language.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class HDHub4uSource extends Source {
  HDHub4uSource(super.fetcher);

  @override
  String get id => 'hdhub4u';
  @override
  String get label => 'HDHub4u';
  @override
  List<String> get contentTypes => const ['movie', 'series'];
  @override
  List<CountryCode> get countryCodes => const [
        CountryCode.multi,
        CountryCode.gu,
        CountryCode.hi,
        CountryCode.ml,
        CountryCode.pa,
        CountryCode.ta,
        CountryCode.te,
      ];
  @override
  String get baseUrl => 'https://new5.hdhub4u.fo';

  static const _searchUrl = 'https://search.pingora.fyi';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final imdbId = await getImdbId(ctx, fetcher, id);
    final pageUrls = await _fetchPageUrls(ctx, imdbId);

    final lists = await Future.wait(
        pageUrls.map((u) => _handlePage(ctx, u, imdbId)));
    return lists.expand((e) => e).toList();
  }

  Future<List<SourceResult>> _handlePage(
      Context ctx, Uri pageUrl, ImdbId imdbId) async {
    final html = await fetcher.text(ctx, pageUrl);
    final doc = html_parser.parse(html);

    String langText = '';
    for (final div in doc.querySelectorAll('div')) {
      if (div.text.contains('Language') && div.children.isEmpty) {
        langText = div.text;
        break;
      }
    }
    final meta = Meta(
      countryCodes: <CountryCode>{
        CountryCode.multi,
        ...findCountryCodes(langText),
      }.toList(),
    );

    final out = <SourceResult>[];
    if (imdbId.episode == null) {
      out.addAll(_extractHubDriveUrlResults(html, meta));
      for (final a in doc.querySelectorAll('a[href*="gadgetsweb"]')) {
        final href = a.attributes['href'];
        if (href == null) continue;
        out.addAll(
            await _handleHubLinks(ctx, Uri.parse(href), pageUrl, meta));
      }
      return out;
    }

    final epStr = '${imdbId.episode}';
    final epPad = epStr.padLeft(2, '0');

    for (final a in doc.querySelectorAll('a')) {
      final t = a.text;
      if (t.contains('EPiSODE $epStr') || t.contains('EPiSODE $epPad')) {
        final href = a.attributes['href'];
        if (href == null) continue;
        out.addAll(
            await _handleHubLinks(ctx, Uri.parse(href), pageUrl, meta));
      }
    }

    // Find the matching <h4>… block, accumulate its siblings until <hr>.
    final headers = doc.querySelectorAll('h4');
    for (final h in headers) {
      final t = h.text;
      if (!(t.contains('EPiSODE $epStr') || t.contains('EPiSODE $epPad'))) {
        continue;
      }
      final buf = StringBuffer();
      var n = h.nextElementSibling;
      while (n != null && n.localName != 'hr') {
        buf.write(n.outerHtml);
        n = n.nextElementSibling;
      }
      out.addAll(_extractHubDriveUrlResults(buf.toString(), meta));
      break;
    }

    return out;
  }

  Future<List<SourceResult>> _handleHubLinks(
      Context ctx, Uri redirectUrl, Uri refererUrl, Meta meta) async {
    final hubLinksUrl = await resolveRedirectUrl(ctx, fetcher, redirectUrl);
    final html = await fetcher.text(ctx, hubLinksUrl,
        FetcherRequestConfig(headers: {'Referer': refererUrl.toString()}));
    final m = meta.clone();
    m.referer = hubLinksUrl.toString();
    return _extractHubDriveUrlResults(html, m);
  }

  List<SourceResult> _extractHubDriveUrlResults(String html, Meta meta) {
    final doc = html_parser.parse(html);
    final out = <SourceResult>[];
    for (final a in doc.querySelectorAll('a[href*="hubdrive"]')) {
      if (a.text.contains('⚡')) continue;
      final href = a.attributes['href'];
      if (href == null) continue;
      out.add(SourceResult(url: Uri.parse(href), meta: meta.clone()));
    }
    return out;
  }

  Future<List<Uri>> _fetchPageUrls(Context ctx, ImdbId imdbId) async {
    final searchUrl = Uri.parse(
        '$_searchUrl/collections/post/documents/search?query_by=imdb_id&q=${Uri.encodeComponent(imdbId.id)}');
    final resp = await fetcher.json(ctx, searchUrl,
        FetcherRequestConfig(headers: {'Referer': baseUrl})) as Map<String, dynamic>;

    final hits = (resp['hits'] as List).cast<Map<String, dynamic>>();
    final out = <Uri>[];
    for (final hit in hits) {
      final doc = hit['document'] as Map<String, dynamic>;
      if (doc['imdb_id'] != imdbId.id) continue;
      final postTitle = doc['post_title'] as String? ?? '';
      if (imdbId.season != null) {
        final s = imdbId.season.toString();
        final sPad = s.padLeft(2, '0');
        if (!postTitle.contains('Season $s') &&
            !postTitle.contains('S$s') &&
            !postTitle.contains('S$sPad')) {
          continue;
        }
      }
      final permalink = doc['permalink'] as String;
      out.add(Uri.parse(permalink).hasScheme
          ? Uri.parse(permalink)
          : Uri.parse(baseUrl).resolve(permalink));
    }
    return out;
  }
}
