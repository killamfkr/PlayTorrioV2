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

  Duration? get start =>
      startMs != null ? Duration(milliseconds: startMs!) : null;
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
              ?.map((e) => IntroDbTimestamp.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      recap: (json['recap'] as List<dynamic>?)
              ?.map((e) => IntroDbTimestamp.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      credits: (json['credits'] as List<dynamic>?)
              ?.map((e) => IntroDbTimestamp.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      preview: (json['preview'] as List<dynamic>?)
              ?.map((e) => IntroDbTimestamp.fromJson(e as Map<String, dynamic>))
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

  /// Fetch skip timestamps for a movie or TV episode.
  /// Returns null if no data is found (404) or on error.
  Future<IntroDbResponse?> getTimestamps({
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

      final response =
          await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return IntroDbResponse.fromJson(decoded);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
