import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service to interact with miruro.tv API for anime streaming.
/// Uses the secure pipe protocol: base64url-encoded GET requests
/// with XOR-obfuscated + deflate-compressed responses.
class AnimeService {
  static const String _baseUrl = 'https://www.miruro.tv';
  static const String _pipeObfKey = '71951034f8fbcf53d89db52ceb3dc22c';
  static final Uint8List _obfKeyBytes = Uint8List.fromList(
    RegExp(r'.{2}')
        .allMatches(_pipeObfKey)
        .map((m) => int.parse(m.group(0)!, radix: 16))
        .toList(),
  );
  static const String _protocolVersion = '0.2.0';

  static final http.Client _http = http.Client();

  /// Generic API GET request through the secure pipe.
  Future<dynamic> _apiGet(String path, {Map<String, String>? query}) async {
    final request = {
      'path': path,
      'method': 'GET',
      'query': query ?? {},
      'body': null,
      'version': _protocolVersion,
    };
    final encoded = _base64urlEncode(jsonEncode(request));
    final uri = Uri.parse('$_baseUrl/api/secure/pipe?e=$encoded');

    final response = await _http.get(
      uri,
      headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': '$_baseUrl/',
        'Origin': _baseUrl,
      },
    );
    final body = utf8.decode(response.bodyBytes);

    final xObf = response.headers['x-obfuscated'];
    if (xObf != null) {
      return jsonDecode(_deobfuscate(body, xObf));
    }
    return jsonDecode(body);
  }

  String _base64urlEncode(String input) {
    return base64Url.encode(utf8.encode(input)).replaceAll('=', '');
  }

  String _deobfuscate(String body, String xObfuscated) {
    // Convert base64url → standard base64
    String b64 = body.replaceAll('-', '+').replaceAll('_', '/');
    final pad = b64.length % 4;
    if (pad != 0) b64 += '=' * (4 - pad);

    Uint8List data = base64Decode(b64);

    // XOR with key if obfuscation level 2
    if (xObfuscated == '2') {
      final xored = Uint8List(data.length);
      for (int i = 0; i < data.length; i++) {
        xored[i] = data[i] ^ _obfKeyBytes[i % _obfKeyBytes.length];
      }
      data = xored;
    }

    // Decompress (auto-detect format)
    return utf8.decode(_decompress(data));
  }

  Uint8List _decompress(Uint8List data) {
    try {
      if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
        return Uint8List.fromList(GZipDecoder().decodeBytes(data));
      }
    } catch (_) {}
    try {
      return Uint8List.fromList(ZLibDecoder().decodeBytes(data));
    } catch (_) {}
    try {
      return Uint8List.fromList(
        ZLibDecoder().decodeBytes(Uint8List.fromList([0x78, 0x01, ...data])),
      );
    } catch (_) {}
    return data;
  }

  // ─── Public API ────────────────────────────────────────────────

  /// Get anime info by AniList ID.
  Future<AnimeInfo> getInfo(int anilistId) async {
    final data = await _apiGet('info/$anilistId');
    return AnimeInfo.fromJson(data);
  }

  /// Get episodes for an anime by AniList ID.
  Future<AnimeEpisodes> getEpisodes(int anilistId) async {
    final data = await _apiGet('episodes', query: {'anilistId': '$anilistId'});
    return AnimeEpisodes.fromJson(data);
  }

  /// Get streaming sources for a specific episode.
  Future<AnimeSources> getSources({
    required String episodeId,
    required String provider,
    String category = 'sub',
    required int anilistId,
  }) async {
    final data = await _apiGet('sources', query: {
      'episodeId': episodeId,
      'provider': provider,
      'category': category,
      'anilistId': '$anilistId',
    });
    return AnimeSources.fromJson(data);
  }

  /// Search anime.
  Future<List<AnimeCard>> search(String query, {int page = 1, int perPage = 20}) async {
    final data = await _apiGet('search/browse', query: {
      'search': query,
      'type': 'ANIME',
      'page': '$page',
      'perPage': '$perPage',
    });
    if (data is List) {
      return data.map((e) => AnimeCard.fromJson(e)).toList();
    }
    return [];
  }

  /// Get trending anime.
  Future<List<AnimeCard>> getTrending({int page = 1, int perPage = 20}) async {
    final data = await _apiGet('search/browse', query: {
      'type': 'ANIME',
      'status': 'RELEASING',
      'sort': 'TRENDING_DESC',
      'page': '$page',
      'perPage': '$perPage',
    });
    if (data is List) return data.map((e) => AnimeCard.fromJson(e)).toList();
    return [];
  }

  /// Get popular anime of all time.
  Future<List<AnimeCard>> getPopular({int page = 1, int perPage = 20}) async {
    final data = await _apiGet('search', query: {
      'type': 'ANIME',
      'sort': 'POPULARITY_DESC',
      'page': '$page',
      'perPage': '$perPage',
    });
    if (data is List) return data.map((e) => AnimeCard.fromJson(e)).toList();
    return [];
  }

  /// Get top rated anime.
  Future<List<AnimeCard>> getTopRated({int page = 1, int perPage = 20}) async {
    final data = await _apiGet('search', query: {
      'type': 'ANIME',
      'sort': 'AVERAGE_SCORE_DESC',
      'page': '$page',
      'perPage': '$perPage',
    });
    if (data is List) return data.map((e) => AnimeCard.fromJson(e)).toList();
    return [];
  }

  /// Browse with filters.
  Future<List<AnimeCard>> browse({
    String? genre,
    String? year,
    String? season,
    String? format,
    String? status,
    bool? isAdult,
    String sort = 'POPULARITY_DESC',
    int page = 1,
    int perPage = 20,
  }) async {
    final q = <String, String>{
      'type': 'ANIME',
      'sort': sort,
      'page': '$page',
      'perPage': '$perPage',
    };
    if (genre != null) q['genres'] = genre;
    if (year != null) q['year'] = year;
    if (season != null) q['season'] = season;
    if (format != null) q['format'] = format;
    if (status != null) q['status'] = status;
    if (isAdult == true) q['isAdult'] = 'true';

    final data = await _apiGet('search/browse', query: q);
    if (data is List) return data.map((e) => AnimeCard.fromJson(e)).toList();
    return [];
  }

  // ─── Likes ─────────────────────────────────────────────────────

  static const String _likedKey = 'liked_anime';

  Future<void> toggleLike(AnimeCard anime) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_likedKey) ?? [];
    final idx = list.indexWhere((e) {
      final m = jsonDecode(e);
      return m['id'] == anime.id;
    });
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.add(jsonEncode(anime.toJson()));
    }
    await prefs.setStringList(_likedKey, list);
  }

  Future<bool> isLiked(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_likedKey) ?? [];
    return list.any((e) => jsonDecode(e)['id'] == id);
  }

  Future<List<AnimeCard>> getLiked() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_likedKey) ?? [];
    return list.map((e) => AnimeCard.fromJson(jsonDecode(e))).toList().reversed.toList();
  }

  // ─── Continue Watching ─────────────────────────────────────────

  static const String _watchHistoryKey = 'anime_watch_history';

  Future<void> addToWatchHistory({
    required AnimeCard anime,
    required int episodeNumber,
    required String episodeTitle,
    required String provider,
    required String category,
    required String episodeId,
    bool useAnimeRealms = false,
    int? position,
    int? duration,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_watchHistoryKey) ?? [];
    // Remove existing entry for this anime
    list.removeWhere((e) => jsonDecode(e)['animeId'] == anime.id);
    // Add to front
    list.insert(0, jsonEncode({
      'animeId': anime.id,
      'anime': anime.toJson(),
      'episodeNumber': episodeNumber,
      'episodeTitle': episodeTitle,
      'provider': provider,
      'category': category,
      'episodeId': episodeId,
      'useAnimeRealms': useAnimeRealms,
      'position': position ?? 0,
      'duration': duration ?? 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }));
    // Keep max 20
    if (list.length > 20) list.removeLast();
    await prefs.setStringList(_watchHistoryKey, list);
  }

  Future<List<Map<String, dynamic>>> getWatchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_watchHistoryKey) ?? [];
    return list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  Future<void> removeFromWatchHistory(int animeId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_watchHistoryKey) ?? [];
    list.removeWhere((e) => jsonDecode(e)['animeId'] == animeId);
    await prefs.setStringList(_watchHistoryKey, list);
  }
}

// ─── Models ──────────────────────────────────────────────────────

class AnimeCard {
  final int id;
  final String titleEnglish;
  final String titleRomaji;
  final String titleNative;
  final String? coverLarge;
  final String? coverExtraLarge;
  final String? bannerImage;
  final String? format;
  final String? status;
  final int? episodes;
  final int? averageScore;
  final int? popularity;
  final String? description;
  final List<String> genres;
  final int? duration;
  final Map<String, int?>? nextAiringEpisode;
  final int? seasonYear;
  final bool isAdult;

  String get displayTitle => titleEnglish.isNotEmpty ? titleEnglish : titleRomaji;
  String get coverUrl => coverExtraLarge ?? coverLarge ?? '';

  AnimeCard({
    required this.id,
    required this.titleEnglish,
    required this.titleRomaji,
    required this.titleNative,
    this.coverLarge,
    this.coverExtraLarge,
    this.bannerImage,
    this.format,
    this.status,
    this.episodes,
    this.averageScore,
    this.popularity,
    this.description,
    this.genres = const [],
    this.duration,
    this.nextAiringEpisode,
    this.seasonYear,
    this.isAdult = false,
  });

  factory AnimeCard.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as Map<String, dynamic>? ?? {};
    final cover = json['coverImage'] as Map<String, dynamic>? ?? {};
    final nae = json['nextAiringEpisode'] as Map<String, dynamic>?;

    return AnimeCard(
      id: json['id'] ?? 0,
      titleEnglish: title['english'] ?? '',
      titleRomaji: title['romaji'] ?? '',
      titleNative: title['native'] ?? '',
      coverLarge: cover['large'],
      coverExtraLarge: cover['extraLarge'],
      bannerImage: json['bannerImage'],
      format: json['format'],
      status: json['status'],
      episodes: json['episodes'],
      averageScore: json['averageScore'],
      popularity: json['popularity'],
      description: json['description'],
      genres: (json['genres'] as List?)?.cast<String>() ?? [],
      duration: json['duration'],
      nextAiringEpisode: nae != null
          ? {
              'episode': nae['episode'] as int?,
              'airingAt': nae['airingAt'] as int?,
              'timeUntilAiring': nae['timeUntilAiring'] as int?,
            }
          : null,
      seasonYear: json['seasonYear'],
      isAdult: json['isAdult'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': {
        'english': titleEnglish,
        'romaji': titleRomaji,
        'native': titleNative,
      },
      'coverImage': {
        'large': coverLarge,
        'extraLarge': coverExtraLarge,
      },
      'bannerImage': bannerImage,
      'format': format,
      'status': status,
      'episodes': episodes,
      'averageScore': averageScore,
      'popularity': popularity,
      'description': description,
      'genres': genres,
      'duration': duration,
      'seasonYear': seasonYear,
      'isAdult': isAdult,
    };
  }
}

class AnimeInfo {
  final AnimeCard media;
  final Map<String, dynamic>? mappings;
  final Map<String, dynamic>? tvdb;
  final Map<String, dynamic>? tmdb;
  final Map<String, dynamic>? schedule;

  AnimeInfo({
    required this.media,
    this.mappings,
    this.tvdb,
    this.tmdb,
    this.schedule,
  });

  factory AnimeInfo.fromJson(Map<String, dynamic> json) {
    return AnimeInfo(
      media: AnimeCard.fromJson(json['media'] ?? {}),
      mappings: json['mappings'],
      tvdb: json['tvdb'],
      tmdb: json['tmdb'],
      schedule: json['schedule'],
    );
  }
}

class AnimeEpisode {
  final String id;
  final int number;
  final String? title;
  final String? image;
  final String? airDate;
  final int? duration;
  final String? audio;
  final String? description;
  final bool filler;

  AnimeEpisode({
    required this.id,
    required this.number,
    this.title,
    this.image,
    this.airDate,
    this.duration,
    this.audio,
    this.description,
    this.filler = false,
  });

  factory AnimeEpisode.fromJson(Map<String, dynamic> json) {
    return AnimeEpisode(
      id: json['id'] ?? '',
      number: json['number'] ?? 0,
      title: json['title'],
      image: json['image'],
      airDate: json['airDate'],
      duration: json['duration'],
      audio: json['audio'],
      description: json['description'],
      filler: json['filler'] ?? false,
    );
  }
}

class AnimeEpisodes {
  final Map<String, dynamic>? mappings;
  final Map<String, AnimeProvider> providers;

  AnimeEpisodes({this.mappings, required this.providers});

  factory AnimeEpisodes.fromJson(Map<String, dynamic> json) {
    final provs = <String, AnimeProvider>{};
    final providersMap = json['providers'] as Map<String, dynamic>? ?? {};
    for (final entry in providersMap.entries) {
      provs[entry.key] = AnimeProvider.fromJson(entry.value);
    }
    return AnimeEpisodes(mappings: json['mappings'], providers: provs);
  }
}

class AnimeProvider {
  final Map<String, dynamic>? meta;
  final List<AnimeEpisode> subEpisodes;
  final List<AnimeEpisode> dubEpisodes;

  AnimeProvider({this.meta, this.subEpisodes = const [], this.dubEpisodes = const []});

  factory AnimeProvider.fromJson(Map<String, dynamic> json) {
    final episodes = json['episodes'];
    List<AnimeEpisode> sub = [];
    List<AnimeEpisode> dub = [];

    if (episodes is Map<String, dynamic>) {
      if (episodes['sub'] is List) {
        sub = (episodes['sub'] as List).map((e) => AnimeEpisode.fromJson(e)).toList();
      }
      if (episodes['dub'] is List) {
        dub = (episodes['dub'] as List).map((e) => AnimeEpisode.fromJson(e)).toList();
      }
    }

    return AnimeProvider(
      meta: json['meta'],
      subEpisodes: sub,
      dubEpisodes: dub,
    );
  }
}

class AnimeStream {
  final String url;
  final String type;
  final String? quality;
  final String? server;
  final String? referer;
  final bool isDefault;

  AnimeStream({
    required this.url,
    required this.type,
    this.quality,
    this.server,
    this.referer,
    this.isDefault = false,
  });

  factory AnimeStream.fromJson(Map<String, dynamic> json) {
    return AnimeStream(
      url: json['url'] ?? '',
      type: json['type'] ?? 'hls',
      quality: json['quality'],
      server: json['server'],
      referer: json['referer'],
      isDefault: json['default'] ?? false,
    );
  }
}

class AnimeSubtitle {
  final String url;
  final String label;
  final String language;
  final bool isDefault;

  AnimeSubtitle({
    required this.url,
    required this.label,
    required this.language,
    this.isDefault = false,
  });

  factory AnimeSubtitle.fromJson(Map<String, dynamic> json) {
    return AnimeSubtitle(
      url: json['file'] ?? json['url'] ?? '',
      label: json['label'] ?? 'Unknown',
      language: json['language'] ?? '',
      isDefault: json['default'] ?? false,
    );
  }
}

class AnimeSources {
  final List<AnimeStream> streams;
  final List<AnimeSubtitle> subtitles;
  final Map<String, int>? intro;
  final Map<String, int>? outro;

  AnimeSources({
    required this.streams,
    this.subtitles = const [],
    this.intro,
    this.outro,
  });

  factory AnimeSources.fromJson(Map<String, dynamic> json) {
    final streams = (json['streams'] as List?)
            ?.map((e) => AnimeStream.fromJson(e))
            .toList() ??
        [];
    final subs = (json['subtitles'] as List?)
            ?.map((e) => AnimeSubtitle.fromJson(e))
            .toList() ??
        [];

    return AnimeSources(
      streams: streams,
      subtitles: subs,
      intro: json['intro'] != null
          ? {'start': json['intro']['start'] ?? 0, 'end': json['intro']['end'] ?? 0}
          : null,
      outro: json['outro'] != null
          ? {'start': json['outro']['start'] ?? 0, 'end': json['outro']['end'] ?? 0}
          : null,
    );
  }
}
