import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as hp;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_server_service.dart';
import 'comic_page_extractor.dart';
import 'readcomicsonline_scraper.dart';

class Comic {
  final String title;
  final String url;
  final String poster;
  final String status;
  final String publication;
  final String summary;
  /// Source tag identifying which scraper produced this comic.
  /// '' or 'rco' = readcomiconline.li (default), 'rcoru' = readcomicsonline.ru.
  final String source;

  Comic({
    required this.title,
    required this.url,
    required this.poster,
    required this.status,
    required this.publication,
    required this.summary,
    this.source = '',
  });

  factory Comic.fromJson(Map<String, dynamic> json) {
    return Comic(
      title: json['title'] ?? '',
      url: json['url'] ?? '',
      poster: json['poster'] ?? '',
      status: json['status'] ?? '',
      publication: json['publication'] ?? '',
      summary: json['summary'] ?? '',
      source: json['source'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'poster': poster,
      'status': status,
      'publication': publication,
      'summary': summary,
      'source': source,
    };
  }
}

class ComicChapter {
  final String title;
  final String url;
  final String dateAdded;

  ComicChapter({required this.title, required this.url, required this.dateAdded});
}

class ComicDetails {
  final Comic comic;
  final String otherName;
  final List<String> genres;
  final String publisher;
  final String writer;
  final String artist;
  final String publicationDate;
  final List<ComicChapter> chapters;

  ComicDetails({
    required this.comic,
    required this.otherName,
    required this.genres,
    required this.publisher,
    required this.writer,
    required this.artist,
    required this.publicationDate,
    required this.chapters,
  });
}

class ComicsService {
  static const String _baseUrl = 'https://readcomiconline.li';
  static const String _likedKey = 'liked_comics';

  Future<List<Comic>> getComics({int page = 1}) async {
    try {
      final url = '$_baseUrl/ComicList?page=$page';
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (response.statusCode == 200) {
        return _parseComics(response.body);
      }
    } catch (e) {
      debugPrint('Error fetching comics: $e');
    }
    return [];
  }

  Future<List<Comic>> searchComics(String query) async {
    // Run both sources in parallel and merge, deduping by normalized title.
    final results = await Future.wait<List<Comic>>([
      _searchRco(query),
      ReadComicsOnlineScraper.searchComics(query),
    ]);

    final seen = <String>{};
    final merged = <Comic>[];
    for (final list in results) {
      for (final c in list) {
        final key = c.title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);
        merged.add(c);
      }
    }
    return merged;
  }

  Future<List<Comic>> _searchRco(String query) async {
    try {
      final url = '$_baseUrl/Search/Comic';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'keyword=$query',
      );

      if (response.statusCode == 200) {
        return _parseComics(response.body);
      }
    } catch (e) {
      debugPrint('Error searching comics: $e');
    }
    return [];
  }

  Future<ComicDetails?> getComicDetails(Comic comic) async {
    // Dispatch by source / host.
    if (comic.source == ReadComicsOnlineScraper.sourceTag ||
        ReadComicsOnlineScraper.ownsUrl(comic.url)) {
      return ReadComicsOnlineScraper.getComicDetails(comic);
    }
    try {
      var url = comic.url.startsWith('http') ? comic.url : '$_baseUrl${comic.url}';
      // Ensure we don't have duplicate s2
      if (!url.contains('s=s2')) {
        url += url.contains('?') ? '&s=s2' : '?s=s2';
      }
      
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (response.statusCode != 200) return null;

      final document = hp.parse(response.body);
      final infoParas = document.querySelectorAll('.barContent p');
      
      String otherName = 'None';
      List<String> genres = [];
      String publisher = 'Unknown';
      String writer = 'Unknown';
      String artist = 'Unknown';
      String publicationDate = 'Unknown';

      for (var p in infoParas) {
        final infoSpan = p.querySelector('.info');
        if (infoSpan == null) continue;
        final label = infoSpan.text.toLowerCase();
        final content = p.text.replaceFirst(infoSpan.text, '').trim();

        if (label.contains('other name')) otherName = content;
        if (label.contains('genres')) {
          genres = p.querySelectorAll('a').map((e) => e.text.trim()).toList();
        }
        if (label.contains('publisher')) publisher = content;
        if (label.contains('writer')) writer = content;
        if (label.contains('artist')) artist = content;
        if (label.contains('publication date')) publicationDate = content;
      }

      final chapters = <ComicChapter>[];
      final table = document.querySelector('table.listing');
      if (table != null) {
        final rows = table.querySelectorAll('tr');
        for (var row in rows) {
          final link = row.querySelector('a');
          if (link != null) {
            final tds = row.querySelectorAll('td');
            final date = tds.length > 1 ? tds[1].text.trim() : '';
            
            var chapterUrl = link.attributes['href'] ?? '';
            if (chapterUrl.isNotEmpty && !chapterUrl.contains('s=s2')) {
              chapterUrl += chapterUrl.contains('?') ? '&s=s2' : '?s=s2';
            }

            chapters.add(ComicChapter(
              title: link.text.trim(),
              url: chapterUrl,
              dateAdded: date,
            ));
          }
        }
      }

      return ComicDetails(
        comic: comic,
        otherName: otherName,
        genres: genres,
        publisher: publisher,
        writer: writer,
        artist: artist,
        publicationDate: publicationDate,
        chapters: chapters,
      );
    } catch (e) {
      debugPrint('Error getting comic details: $e');
      return null;
    }
  }

  Future<List<String>> getChapterPages(String chapterUrl, ComicPageExtractor extractor) async {
    // Dispatch by host.
    if (ReadComicsOnlineScraper.ownsUrl(chapterUrl)) {
      return ReadComicsOnlineScraper.getChapterPages(chapterUrl);
    }
    try {
      // MANDATORY: Add &s=s2 to the URL
      var url = chapterUrl.startsWith('http') ? chapterUrl : '$_baseUrl$chapterUrl';
      if (!url.contains('s=s2')) {
        url += url.contains('?') ? '&s=s2' : '?s=s2';
      }

      debugPrint('[ComicsService] Loading chapter: $url');

      // Pure HTTP scrape — the headless WebView was crashing the app on Windows
      // when running the page's heavily-obfuscated JS. We replicate the site's
      // decoder (beau/baeu from rguard.min.js) directly in Dart.
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (response.statusCode != 200) {
        throw Exception('Chapter page returned HTTP ${response.statusCode}');
      }

      final html = response.body;

      // Locate decoder call site in SetImage: src="' + <fname>(3, <arr>[cImgIndex])
      // Both function and array names are randomized per request.
      final callMatch = RegExp(
        r"""src\s*=\s*"'\s*\+\s*(f\w+)\s*\(\s*3\s*,\s*(\w+)\[""",
      ).firstMatch(html);
      if (callMatch == null) {
        throw Exception('Could not locate decoder call site in chapter HTML.');
      }
      final funcName = callMatch.group(1)!;
      final arrName = callMatch.group(2)!;

      // Extract outer replace rules from the decoder function body:
      //   function <fname>(z, l) { l = l.replace(/X/g, 'Y'); ... return baeu(l, '<base>'); }
      final funcBodyMatch = RegExp(
        'function\\s+${RegExp.escape(funcName)}\\s*\\(\\s*z\\s*,\\s*l\\s*\\)\\s*\\{([\\s\\S]*?)\\}',
      ).firstMatch(html);
      final outerRules = <List<String>>[];
      String baseUrl = 'https://ano1.rconet.biz/pic';
      if (funcBodyMatch != null) {
        final body = funcBodyMatch.group(1)!;
        final ruleRe = RegExp(r"l\s*=\s*l\.replace\(/([^/]+)/g,\s*'([^']*)'\)");
        for (final m in ruleRe.allMatches(body)) {
          outerRules.add([m.group(1)!, m.group(2)!]);
        }
        final baseMatch = RegExp(r"baeu\s*\(\s*l\s*,\s*'([^']+)'\s*\)").firstMatch(body);
        if (baseMatch != null) baseUrl = baseMatch.group(1)!;
      }

      // Extract encoded values. The page emits `<arr>xnz = '<value>';` before
      // each `<arr>.push(<arr>xnz);`. We read the literal assignments in order.
      final encVarName = '${arrName}xnz';
      final valueRe = RegExp(
        RegExp.escape(encVarName) + r"\s*=\s*'([^']+)'",
      );
      final encodedValues = valueRe.allMatches(html).map((m) => m.group(1)!).toList();

      if (encodedValues.isEmpty) {
        debugPrint('[ComicsService] No encoded page values found for $encVarName');
        throw Exception('No comic pages found on this chapter page.');
      }

      debugPrint('[ComicsService] Comic has ${encodedValues.length} pages (decoder=$funcName, arr=$arrName)');

      // Decode each value via the replicated beau/baeu pipeline.
      final proxy = LocalServerService();
      final pageUrls = <String>[];
      for (final enc in encodedValues) {
        final decoded = _decodeEncodedValue(enc, outerRules, baseUrl);
        if (decoded.isEmpty) continue;
        pageUrls.add(proxy.getComicProxyUrl(decoded));
      }

      if (pageUrls.isEmpty) {
        throw Exception('Failed to decode any comic page URLs.');
      }

      return pageUrls;
    } catch (e) {
      debugPrint('Error getting chapter pages: $e');
      rethrow;
    }
  }

  // Replicates rguard.min.js's `baeu(l, m)` for the non-https branch,
  // combined with the outer wrapper function's replace rules.
  //
  // Outer wrapper applies rules like:
  //   l = l.replace(/Vz__x2OdwP_/g, 'g');
  //   l = l.replace(/b/g, 'pw_.g28x');
  //   l = l.replace(/h/g, 'd2pr.x_27');
  // then calls baeu(l, '<base>'). Inside baeu the first thing is a reverse:
  //   l = l.replace(/pw_.g28x/g, 'b').replace(/d2pr.x_27/g, 'h');
  // so the `b`/`h` rules cancel out. Only non-reversible rules have net effect.
  String _decodeEncodedValue(String enc, List<List<String>> outerRules, String baseUrl) {
    try {
      String l = enc;
      // Apply outer rules in order
      for (final rule in outerRules) {
        l = l.replaceAll(RegExp(rule[0]), rule[1]);
      }
      // baeu reverse replacements (cancels the b/h obfuscation)
      l = l.replaceAll(RegExp(r'pw_\.g28x'), 'b').replaceAll(RegExp(r'd2pr\.x_27'), 'h');

      // Value does not start with https, so we execute baeu's decoding branch.
      final qi = l.indexOf('?');
      final trailer = qi >= 0 ? l.substring(qi) : '';
      String e;
      String suffix;
      final s0Idx = l.indexOf('=s0?');
      if (s0Idx > 0) {
        e = l.substring(0, s0Idx);
        suffix = '=s0';
      } else {
        final s16Idx = l.indexOf('=s1600?');
        if (s16Idx > 0) {
          e = l.substring(0, s16Idx);
          suffix = '=s1600';
        } else {
          // Fallback: strip trailing =s1600 / =s0 without query
          if (l.endsWith('=s0')) {
            e = l.substring(0, l.length - 3);
            suffix = '=s0';
          } else if (l.endsWith('=s1600')) {
            e = l.substring(0, l.length - 6);
            suffix = '=s1600';
          } else {
            e = l;
            suffix = '=s1600';
          }
        }
      }

      // step1(l) = l.substring(15, 15+18) + l.substring(15+18+17) = [15,33) + [50,)
      if (e.length < 50) return '';
      e = e.substring(15, 33) + e.substring(50);
      // step2(l) = l.substring(0, len-11) + l[len-2] + l[len-1]
      if (e.length < 11) return '';
      e = e.substring(0, e.length - 11) + e.substring(e.length - 2);

      // atob + decodeURIComponent(escape(...)) == base64 decode then UTF-8
      final padded = e + '=' * ((4 - e.length % 4) % 4);
      final bytes = base64.decode(padded);
      String d = utf8.decode(bytes, allowMalformed: true);

      // substring(0, 13) + substring(17)
      if (d.length <= 17) return '';
      d = d.substring(0, 13) + d.substring(17);

      // strip last 2 chars then append suffix
      if (d.length < 2) return '';
      d = d.substring(0, d.length - 2) + suffix;

      final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      return '$base/$d$trailer';
    } catch (err) {
      debugPrint('[ComicsService] Decode error: $err');
      return '';
    }
  }

  // Get a single page image URL (called on-demand when user navigates).
  // Pages are now fully resolved up-front in getChapterPages, so this is a
  // pass-through for backward compatibility with the reader UI.
  Future<String?> getPageImage(String pageUrl, ComicPageExtractor extractor) async {
    return pageUrl;
  }


  List<Comic> _parseComics(String html) {
    final List<Comic> comics = [];
    final document = hp.parse(html);
    final items = document.querySelectorAll('.list-comic .item, .item');

    for (var item in items) {
      final titleAttr = item.attributes['title'] ?? '';
      final titleDoc = hp.parse(titleAttr);
      
      final title = titleDoc.querySelector('.title')?.text ?? item.querySelector('.title')?.text ?? 'Unknown';
      final status = _extractFromTitle(titleAttr, 'Status:');
      final publication = _extractFromTitle(titleAttr, 'Publication:');
      final summary = titleDoc.querySelector('.description')?.text ?? 'No summary available';

      final link = item.querySelector('a');
      final url = link?.attributes['href'] ?? '';
      
      final img = item.querySelector('img');
      var poster = img?.attributes['src'] ?? '';
      if (poster.isNotEmpty && !poster.startsWith('http')) {
        poster = '$_baseUrl$poster';
      }

      if (title != 'Unknown' && url.isNotEmpty) {
        comics.add(Comic(
          title: title.trim(),
          url: url,
          poster: poster,
          status: status,
          publication: publication,
          summary: summary.trim(),
        ));
      }
    }
    return comics;
  }

  String _extractFromTitle(String titleAttr, String label) {
    final doc = hp.parse(titleAttr);
    final strongs = doc.querySelectorAll('strong');
    for (var strong in strongs) {
      if (strong.text.contains(label)) {
        final parentText = strong.parent?.text ?? '';
        return parentText.replaceFirst(strong.text, '').trim();
      }
    }
    return 'Unknown';
  }

  // Like Functionality
  Future<void> toggleLike(Comic comic) async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    
    final index = likedJson.indexWhere((j) => Comic.fromJson(jsonDecode(j)).url == comic.url);
    
    if (index != -1) {
      likedJson.removeAt(index);
    } else {
      likedJson.add(jsonEncode(comic.toJson()));
    }
    
    await prefs.setStringList(_likedKey, likedJson);
  }

  Future<bool> isLiked(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    return likedJson.any((j) => Comic.fromJson(jsonDecode(j)).url == url);
  }

  Future<List<Comic>> getLikedComics() async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    return likedJson.map((j) => Comic.fromJson(jsonDecode(j))).toList();
  }
}
