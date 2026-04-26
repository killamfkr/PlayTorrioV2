import 'dart:convert';
import 'package:http/http.dart' as http;

class IntroDbTimestamp {
  final int? startMs;
  final int? endMs;

  IntroDbTimestamp({this.startMs, this.endMs});

  factory IntroDbTimestamp.fromJson(Map<String, dynamic> json) {
    return IntroDbTimestamp(
      startMs: json['start_ms'] as int?,
      endMs: json['end_ms'] as int?,
    );
  }

  Duration? get start => startMs != null ? Duration(milliseconds: startMs!) : null;
  Duration? get end => endMs != null ? Duration(milliseconds: endMs!) : null;
}

class IntroDbResponse {
  final int tmdbId;
  final String type;
  final List<IntroDbTimestamp> intro;
  final List<IntroDbTimestamp> recap;
  final List<IntroDbTimestamp> credits;
  final List<IntroDbTimestamp> preview;

  IntroDbResponse({
    required this.tmdbId,
    required this.type,
    required this.intro,
    required this.recap,
    required this.credits,
    required this.preview,
  });

  factory IntroDbResponse.fromJson(Map<String, dynamic> json) {
    return IntroDbResponse(
      tmdbId: json['tmdb_id'] as int,
      type: json['type'] as String,
      intro: (json['intro'] as List<dynamic>?)
              ?.map((e) => IntroDbTimestamp.fromJson(e))
              .toList() ??
          [],
      recap: (json['recap'] as List<dynamic>?)
              ?.map((e) => IntroDbTimestamp.fromJson(e))
              .toList() ??
          [],
      credits: (json['credits'] as List<dynamic>?)
              ?.map((e) => IntroDbTimestamp.fromJson(e))
              .toList() ??
          [],
      preview: (json['preview'] as List<dynamic>?)
              ?.map((e) => IntroDbTimestamp.fromJson(e))
              .toList() ??
          [],
    );
  }

  bool get hasAnySegments =>
      intro.isNotEmpty ||
      recap.isNotEmpty ||
      credits.isNotEmpty ||
      preview.isNotEmpty;
}

class IntroDbService {
  static const String _baseUrl = 'https://api.theintrodb.org/v2';
  static const String _fallbackUrl = 'https://api.introdb.app';

  /// Fetch skip timestamps for a movie or TV episode.
  /// Runs both APIs in parallel and merges results — each segment type
  /// is filled from whichever source has it, so they complete each other.
  Future<IntroDbResponse?> getTimestamps({
    required int tmdbId,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    final primaryFuture = _fetchPrimary(tmdbId: tmdbId, season: season, episode: episode);
    final fallbackFuture = (imdbId != null && imdbId.isNotEmpty)
        ? _fetchFallback(imdbId: imdbId, season: season, episode: episode)
        : Future<IntroDbResponse?>.value(null);

    final results = await Future.wait([primaryFuture, fallbackFuture]);
    final primary = results[0];
    final fallback = results[1];

    if (primary == null && fallback == null) return null;
    if (primary == null) return fallback;
    if (fallback == null) return primary;

    // Merge: for each segment type, use primary if it has data, else fallback.
    return IntroDbResponse(
      tmdbId: primary.tmdbId,
      type: primary.type,
      intro: primary.intro.isNotEmpty ? primary.intro : fallback.intro,
      recap: primary.recap.isNotEmpty ? primary.recap : fallback.recap,
      credits: primary.credits.isNotEmpty ? primary.credits : fallback.credits,
      preview: primary.preview.isNotEmpty ? primary.preview : fallback.preview,
    );
  }

  Future<IntroDbResponse?> _fetchPrimary({
    required int tmdbId,
    int? season,
    int? episode,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/media').replace(
        queryParameters: {
          'tmdb_id': tmdbId.toString(),
          if (season != null) 'season': season.toString(),
          if (episode != null) 'episode': episode.toString(),
        },
      );

      final response = await http.get(uri).timeout(
        const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json is Map<String, dynamic>) {
          return IntroDbResponse.fromJson(json);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fallback API: GET https://api.introdb.app/segments?imdb_id=...&season=...&episode=...
  /// Response: { imdb_id, season, episode, intro: {start_ms, end_ms, ...}, recap: ..., outro: ... }
  Future<IntroDbResponse?> _fetchFallback({
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    try {
      final uri = Uri.parse('$_fallbackUrl/segments').replace(
        queryParameters: {
          'imdb_id': imdbId,
          if (season != null) 'season': season.toString(),
          if (episode != null) 'episode': episode.toString(),
        },
      );

      final response = await http.get(uri).timeout(
        const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json is Map<String, dynamic>) {
          return _parseFallbackResponse(json);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Convert the introdb.app response into our IntroDbResponse model.
  /// The fallback returns each segment type as a single object (or null),
  /// with start_ms/end_ms fields.
  IntroDbResponse _parseFallbackResponse(Map<String, dynamic> json) {
    IntroDbTimestamp? parseSegment(dynamic seg) {
      if (seg == null || seg is! Map<String, dynamic>) return null;
      // Prefer start_ms/end_ms; fall back to start_sec/end_sec * 1000
      int? startMs = seg['start_ms'] as int?;
      int? endMs = seg['end_ms'] as int?;
      if (startMs == null && seg['start_sec'] != null) {
        startMs = ((seg['start_sec'] as num) * 1000).round();
      }
      if (endMs == null && seg['end_sec'] != null) {
        endMs = ((seg['end_sec'] as num) * 1000).round();
      }
      if (startMs == null && endMs == null) return null;
      return IntroDbTimestamp(startMs: startMs, endMs: endMs);
    }

    final intro = parseSegment(json['intro']);
    final recap = parseSegment(json['recap']);
    // introdb.app calls it "outro"; map to "credits"
    final credits = parseSegment(json['outro']);

    return IntroDbResponse(
      tmdbId: 0, // not available from this API
      type: 'fallback',
      intro: intro != null ? [intro] : [],
      recap: recap != null ? [recap] : [],
      credits: credits != null ? [credits] : [],
      preview: [],
    );
  }
}
