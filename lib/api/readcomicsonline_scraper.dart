import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as hp;
import 'comics_service.dart';
import 'local_server_service.dart';

/// Scraper for readcomicsonline.ru — used as a secondary comics source
/// alongside readcomiconline.li.
///
/// Protocol:
///   - Search:   `GET https://readcomicsonline.ru/search?query=<q>`
///               -> JSON `{ suggestions: [{ value, data }] }`
///               where `data` is the comic slug.
///   - Detail:   `GET https://readcomicsonline.ru/comic/<slug>`
///               HTML; chapters live in `<ul class="chapters">` with
///               anchors `/comic/<slug>/<n>` and date in `.date-chapter-title-rtl`.
///               Cover at `/uploads/manga/<slug>/cover/cover_250x350.jpg`.
///   - Chapter:  `GET https://readcomicsonline.ru/comic/<slug>/<n>`
///               `<img class="img-responsive" data-src="<image_url>" ...>`
class ReadComicsOnlineScraper {
  static const String baseUrl = 'https://readcomicsonline.ru';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String sourceTag = 'rcoru';

  /// Returns true if the given URL belongs to this scraper's source.
  static bool ownsUrl(String url) {
    try {
      return Uri.parse(url).host.contains('readcomicsonline.ru');
    } catch (_) {
      return false;
    }
  }

  /// Search: returns lightweight Comic objects (poster + slug-based URL).
  static Future<List<Comic>> searchComics(String query) async {
    try {
      final uri = Uri.parse('$baseUrl/search')
          .replace(queryParameters: {'query': query});
      final res = await http.get(uri, headers: {'User-Agent': _ua});
      if (res.statusCode != 200) return [];

      final body = json.decode(res.body);
      final suggestions = (body is Map && body['suggestions'] is List)
          ? body['suggestions'] as List
          : const [];

      final comics = <Comic>[];
      for (final s in suggestions) {
        if (s is! Map) continue;
        final title = (s['value'] ?? '').toString().trim();
        final slug = (s['data'] ?? '').toString().trim();
        if (title.isEmpty || slug.isEmpty) continue;
        comics.add(Comic(
          title: title,
          url: '$baseUrl/comic/$slug',
          poster: '$baseUrl/uploads/manga/$slug/cover/cover_250x350.jpg',
          status: '',
          publication: '',
          summary: '',
          source: sourceTag,
        ));
      }
      return comics;
    } catch (e) {
      debugPrint('[ReadComicsOnline] search error: $e');
      return [];
    }
  }

  /// Detail page: extracts metadata + full chapter list.
  static Future<ComicDetails?> getComicDetails(Comic comic) async {
    try {
      final res = await http.get(Uri.parse(comic.url), headers: {'User-Agent': _ua});
      if (res.statusCode != 200) return null;

      final doc = hp.parse(res.body);

      // Metadata via the <dl class="dl-horizontal"> term/definition pairs.
      String publisher = 'Unknown';
      String writer = 'Unknown';
      String artist = 'Unknown';
      String publicationDate = 'Unknown';
      String status = '';
      final genres = <String>[];

      final dl = doc.querySelector('dl.dl-horizontal');
      if (dl != null) {
        final children = dl.children;
        for (var i = 0; i < children.length - 1; i++) {
          if (children[i].localName != 'dt') continue;
          final label = children[i].text.trim().toLowerCase();
          final dd = children[i + 1];
          if (dd.localName != 'dd') continue;
          final value = dd.text.trim().replaceAll(RegExp(r'\s+'), ' ');

          if (label.startsWith('status')) status = value;
          if (label.startsWith('author')) writer = value;
          if (label.startsWith('artist')) artist = value;
          if (label.startsWith('date')) publicationDate = value;
          if (label.startsWith('categor')) {
            genres.addAll(dd.querySelectorAll('a').map((e) => e.text.trim()));
          }
          if (label.startsWith('type')) publisher = value;
        }
      }

      // Summary lives in a <p> right after <h5><strong>Summary</strong></h5>.
      String summary = '';
      for (final h5 in doc.querySelectorAll('h5')) {
        if (h5.text.toLowerCase().contains('summary')) {
          final p = h5.nextElementSibling;
          if (p != null) summary = p.text.trim();
          break;
        }
      }

      // Chapters: <ul class="chapters"> -> <li> -> <a href> + .date-chapter-title-rtl.
      final chapters = <ComicChapter>[];
      for (final li in doc.querySelectorAll('ul.chapters li')) {
        final a = li.querySelector('a');
        if (a == null) continue;
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        final fullUrl = href.startsWith('http') ? href : '$baseUrl$href';
        final dateEl = li.querySelector('.date-chapter-title-rtl');
        chapters.add(ComicChapter(
          title: a.text.trim(),
          url: fullUrl,
          dateAdded: dateEl?.text.trim() ?? '',
        ));
      }

      // Update comic with richer info while keeping identity (url/source).
      final enriched = Comic(
        title: comic.title,
        url: comic.url,
        poster: comic.poster,
        status: status.isNotEmpty ? status : comic.status,
        publication: publicationDate != 'Unknown' ? publicationDate : comic.publication,
        summary: summary.isNotEmpty ? summary : comic.summary,
        source: sourceTag,
      );

      return ComicDetails(
        comic: enriched,
        otherName: 'None',
        genres: genres,
        publisher: publisher,
        writer: writer,
        artist: artist,
        publicationDate: publicationDate,
        chapters: chapters,
      );
    } catch (e) {
      debugPrint('[ReadComicsOnline] detail error: $e');
      return null;
    }
  }

  /// Chapter pages: parses <img data-src="..."> from the reader page and
  /// wraps each URL with the local comic-proxy.
  static Future<List<String>> getChapterPages(String chapterUrl) async {
    final res = await http.get(Uri.parse(chapterUrl), headers: {'User-Agent': _ua});
    if (res.statusCode != 200) {
      throw Exception('Chapter page returned HTTP ${res.statusCode}');
    }

    // The site renders <img data-src=' https://...jpg '> (note surrounding
    // whitespace inside the quotes). Allow both ' and ".
    final re = RegExp(
      r'''data-src=\s*['"]\s*(https?://readcomicsonline\.ru/uploads/manga/[^'"\s]+\.(?:jpg|jpeg|png|webp|gif))\s*['"]''',
      caseSensitive: false,
    );
    final urls = re
        .allMatches(res.body)
        .map((m) => m.group(1)!)
        .toList();

    if (urls.isEmpty) {
      throw Exception('No comic pages found on this chapter page.');
    }

    final proxy = LocalServerService();
    return urls.map(proxy.getComicProxyUrl).toList();
  }
}
