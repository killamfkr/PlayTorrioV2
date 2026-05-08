import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/playtorrio_cloud_sync_service.dart';

const String _baseUrl = 'https://weebcentral.com';
const String _coverCdn = 'https://temp.compsci88.com/cover';

class Manga {
  final String id;
  final String title;
  final String coverSmall;
  final String coverNormal;
  final String type;
  final String status;
  final String year;
  final String author;
  final List<String> tags;
  final String synopsis;
  final String url;

  Manga({
    required this.id,
    required this.title,
    required this.coverSmall,
    required this.coverNormal,
    this.type = '',
    this.status = '',
    this.year = '',
    this.author = '',
    this.tags = const [],
    this.synopsis = '',
    this.url = '',
  });

  factory Manga.fromJson(Map<String, dynamic> json) {
    return Manga(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      coverSmall: json['cover_small'] ?? '',
      coverNormal: json['cover_normal'] ?? '',
      type: json['type'] ?? '',
      status: json['status'] ?? '',
      year: json['year'] ?? '',
      author: json['author'] ?? '',
      tags: (json['tags'] as List?)?.cast<String>() ?? [],
      synopsis: json['synopsis'] ?? '',
      url: json['url'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'cover_small': coverSmall,
      'cover_normal': coverNormal,
      'type': type,
      'status': status,
      'year': year,
      'author': author,
      'tags': tags,
      'synopsis': synopsis,
      'url': url,
    };
  }
}

class MangaChapter {
  final String id;
  final double number;
  final String name;
  final String url;
  final String rawName;

  MangaChapter({
    required this.id,
    required this.number,
    this.name = '',
    this.url = '',
    this.rawName = '',
  });

  factory MangaChapter.fromRaw(String id, String rawName, String url) {
    String cleaned = rawName;
    if (cleaned.toLowerCase().startsWith('chapter')) {
      cleaned = cleaned.substring(7).trim();
    }
    final separatorIndex = cleaned.indexOf(RegExp(r'[:\-–]'));
    String numberStr;
    String title;
    if (separatorIndex > 0) {
      numberStr = cleaned.substring(0, separatorIndex).trim();
      title = cleaned.substring(separatorIndex + 1).trim();
    } else {
      numberStr = cleaned.trim();
      title = '';
    }
    final number = double.tryParse(numberStr) ?? 0;
    return MangaChapter(id: id, number: number, name: title, url: url, rawName: rawName);
  }

  factory MangaChapter.fromJson(Map<String, dynamic> json) {
    return MangaChapter(
      id: json['id']?.toString() ?? '',
      number: (json['number'] is String
              ? double.tryParse(json['number']) ?? 0
              : json['number'] ?? 0)
          .toDouble(),
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      rawName: json['raw_name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'name': name,
      'url': url,
      'raw_name': rawName,
    };
  }
}

class MangaService {
  static const String prefsLikedKey = 'liked_manga';
  static const int _pageSize = 32;
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  final http.Client _client = http.Client();

  Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      };

  Future<String> _fetchHtml(String url) async {
    final response = await _client.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }
    return response.body;
  }

  String? _extractSeriesId(String url) {
    final match = RegExp(r'/series/([A-Z0-9]{26})').firstMatch(url);
    return match?.group(1);
  }

  String? _extractChapterId(String url) {
    final match = RegExp(r'/chapters/([A-Z0-9]{26})').firstMatch(url);
    return match?.group(1);
  }

  // ── Browse / Search ─────────────────────────────────────────────────

  Future<List<Manga>> getManga({int page = 1, String? tag, bool allowAdult = false}) async {
    try {
      final offset = (page - 1) * _pageSize;
      final adult = allowAdult ? 'Any' : 'False';
      var url =
          '$_baseUrl/search/data?text=&display_mode=Full+Display&sort=Popularity&order=Descending&official=Any&adult=$adult&offset=$offset';
      if (tag != null) {
        url += '&included_tag=${Uri.encodeComponent(tag)}';
      }
      debugPrint('[MangaService] Fetching page $page: $url');
      final html = await _fetchHtml(url);
      return _parseSearchResults(html);
    } catch (e) {
      debugPrint('[MangaService] Error fetching manga: $e');
      return [];
    }
  }

  Future<List<Manga>> searchManga(String query, {int page = 1, bool allowAdult = false}) async {
    try {
      final offset = (page - 1) * _pageSize;
      final adult = allowAdult ? 'Any' : 'False';
      final encodedQuery = Uri.encodeComponent(query);
      final url =
          '$_baseUrl/search/data?text=$encodedQuery&display_mode=Full+Display&sort=Best+Match&order=Descending&official=Any&adult=$adult&offset=$offset';
      debugPrint('[MangaService] Searching page $page: $url');
      final html = await _fetchHtml(url);
      return _parseSearchResults(html);
    } catch (e) {
      debugPrint('[MangaService] Error searching manga: $e');
      return [];
    }
  }

  List<Manga> _parseSearchResults(String html) {
    final doc = html_parser.parse(html);
    final articles = doc.querySelectorAll('article');
    final results = <Manga>[];

    for (final article in articles) {
      final seriesLink = article.querySelector('a[href*="/series/"]');
      if (seriesLink == null) continue;

      final href = seriesLink.attributes['href'] ?? '';
      final seriesId = _extractSeriesId(href);
      if (seriesId == null) continue;

      // Title: img alt stripped of " cover", or .truncate text, or link text
      String title = '';
      final img = article.querySelector('img');
      final alt = img?.attributes['alt'] ?? '';
      if (alt.endsWith(' cover')) {
        title = alt.substring(0, alt.length - 6);
      }
      if (title.isEmpty) {
        title = article.querySelector('.truncate')?.text.trim() ??
            article.querySelector('.line-clamp-1')?.text.trim() ??
            seriesLink.text.trim().split('\n').first.trim();
      }

      // Type from tooltip data-tip matching known types
      String type = '';
      for (final el in article.querySelectorAll('[data-tip]')) {
        final tip = el.attributes['data-tip'] ?? '';
        if (['Manga', 'Manhwa', 'Manhua', 'OEL'].contains(tip)) {
          type = tip;
          break;
        }
      }

      results.add(Manga(
        id: seriesId,
        title: title,
        coverSmall: '$_coverCdn/small/$seriesId.webp',
        coverNormal: '$_coverCdn/normal/$seriesId.webp',
        type: type,
        url: href,
      ));
    }

    return results;
  }

  // ── Series Detail ───────────────────────────────────────────────────

  Future<Manga> getSeriesDetail(String seriesId) async {
    final html = await _fetchHtml('$_baseUrl/series/$seriesId');
    final doc = html_parser.parse(html);

    final title = doc.querySelector('h1')?.text.trim() ?? '';

    // Parse details from <li> items with <strong> labels
    final details = <String, List<String>>{};
    for (final li in doc.querySelectorAll('li')) {
      final strong = li.querySelector('strong');
      if (strong == null) continue;
      final label =
          strong.text.trim().replaceAll(':', '').replaceAll('(s)', '');
      final links = li.querySelectorAll('a');
      final spans = li.querySelectorAll('span');
      if (links.isNotEmpty) {
        details[label] = links
            .map((a) => a.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();
      } else if (spans.isNotEmpty) {
        details[label] = spans
            .map((s) => s.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();
      }
    }

    // Synopsis: first <p> with substantial text
    String synopsis = '';
    for (final p in doc.querySelectorAll('p')) {
      final text = p.text.trim();
      if (text.length > 50 &&
          !text.contains('Copyright') &&
          !text.contains('verified')) {
        synopsis = text;
        break;
      }
    }

    return Manga(
      id: seriesId,
      title: title,
      coverSmall: '$_coverCdn/small/$seriesId.webp',
      coverNormal: '$_coverCdn/normal/$seriesId.webp',
      type: (details['Type'] ?? ['']).first,
      status: (details['Status'] ?? ['']).first,
      year: (details['Released'] ?? ['']).first,
      author: (details['Author'] ?? []).join(', '),
      tags: details['Tag'] ?? [],
      synopsis: synopsis,
      url: '/series/$seriesId',
    );
  }

  // ── Chapters ────────────────────────────────────────────────────────

  Future<List<MangaChapter>> getChapters(String seriesId) async {
    try {
      final html =
          await _fetchHtml('$_baseUrl/series/$seriesId/full-chapter-list');
      final doc = html_parser.parse(html);

      final chapters = <MangaChapter>[];
      final links = doc.querySelectorAll('a[href*="/chapters/"]');

      for (final a in links) {
        final href = a.attributes['href'] ?? '';
        final chapterId = _extractChapterId(href);
        if (chapterId == null) continue;

        String chapterName = '';
        for (final span in a.querySelectorAll('span')) {
          final t = span.text.trim();
          if (t.isNotEmpty &&
              !t.contains('{') &&
              !t.contains('.st0') &&
              !t.contains('fill:')) {
            chapterName = t;
            break;
          }
        }

        if (chapterName.isNotEmpty) {
          chapters.add(MangaChapter.fromRaw(chapterId, chapterName, href));
        }
      }

      debugPrint('[MangaService] Found ${chapters.length} chapters');
      return chapters;
    } catch (e) {
      debugPrint('[MangaService] Error fetching chapters: $e');
      return [];
    }
  }

  // ── Chapter Images ──────────────────────────────────────────────────

  Future<List<String>> getChapterImages(String chapterId) async {
    try {
      final url =
          '$_baseUrl/chapters/$chapterId/images?is_prev=False&current_page=1&reading_style=long_strip';
      final html = await _fetchHtml(url);
      final doc = html_parser.parse(html);

      final images = <String>[];
      for (final img in doc.querySelectorAll('img')) {
        final src = img.attributes['src'] ?? '';
        if (src.isNotEmpty &&
            !src.contains('/static/') &&
            !src.contains('brand')) {
          images.add(src);
        }
      }

      debugPrint('[MangaService] Found ${images.length} chapter images');
      return images;
    } catch (e) {
      debugPrint('[MangaService] Error fetching chapter images: $e');
      return [];
    }
  }

  // ── Like Functionality ──────────────────────────────────────────────

  Future<void> toggleLike(Manga manga) async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(prefsLikedKey) ?? [];

    final index = likedJson.indexWhere((j) {
      final m = jsonDecode(j) as Map<String, dynamic>;
      return m['id'] == manga.id;
    });

    if (index != -1) {
      likedJson.removeAt(index);
    } else {
      likedJson.add(jsonEncode(manga.toJson()));
    }

    await prefs.setStringList(prefsLikedKey, likedJson);
    PlaytorrioCloudSyncService.instance.scheduleDebouncedSettingsPush();
  }

  Future<bool> isLiked(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(prefsLikedKey) ?? [];
    return likedJson.any((j) {
      final m = jsonDecode(j) as Map<String, dynamic>;
      return m['id'] == id;
    });
  }

  Future<List<Manga>> getLikedManga() async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(prefsLikedKey) ?? [];
    return likedJson.map((j) => Manga.fromJson(jsonDecode(j))).toList();
  }

  // ── Available Tags ──────────────────────────────────────────────────

  static const List<String> availableTags = [
    'Action',
    'Adventure',
    'Comedy',
    'Cooking',
    'Doujinshi',
    'Drama',
    'Ecchi',
    'Fantasy',
    'Gender Bender',
    'Harem',
    'Historical',
    'Horror',
    'Isekai',
    'Josei',
    'Lolicon',
    'Martial Arts',
    'Mature',
    'Mecha',
    'Medical',
    'Music',
    'Mystery',
    'One Shot',
    'Psychological',
    'Romance',
    'School Life',
    'Sci-Fi',
    'Seinen',
    'Shotacon',
    'Shoujo',
    'Shoujo Ai',
    'Shounen',
    'Shounen Ai',
    'Slice of Life',
    'Smut',
    'Sports',
    'Supernatural',
    'Tragedy',
    'Yaoi',
    'Yuri',
  ];
}
