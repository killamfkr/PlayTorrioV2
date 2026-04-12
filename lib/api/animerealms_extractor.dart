import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Direct HTTP client for animerealms.org API.
/// Uses the same AniList IDs as miruro.
///
/// API:
///   GET  /api/mappings?id={anilistId}             → available providers
///   GET  /api/mappings?id={anilistId}&provider=X  → specific provider mapping
///   POST /api/watch  {provider, anilistId, episodeNumber} → streams
class AnimeRealmsExtractor {
  static const String _baseUrl = 'https://www.animerealms.org';
  static final http.Client _client = http.Client();

  static const _browserHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  };

  /// Get available provider mappings for an anime.
  Future<Map<String, dynamic>> getMappings(int anilistId, {String? provider}) async {
    final query = provider != null
        ? 'id=$anilistId&provider=$provider'
        : 'id=$anilistId';
    final uri = Uri.parse('$_baseUrl/api/mappings?$query');
    final res = await _client.get(
      uri,
      headers: {
        ..._browserHeaders,
        'Referer': '$_baseUrl/',
        'Origin': _baseUrl,
      },
    );
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// Fetch streams from a specific provider for an episode.
  Future<Map<String, dynamic>> getStreams({
    required String provider,
    required int anilistId,
    required int episodeNumber,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/watch');
    final res = await _client.post(
      uri,
      headers: {
        ..._browserHeaders,
        'Content-Type': 'application/json',
        'Referer': '$_baseUrl/',
        'Origin': _baseUrl,
      },
      body: jsonEncode({
        'provider': provider,
        'anilistId': anilistId,
        'episodeNumber': episodeNumber,
      }),
    );
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// Try all available providers and return results from every one that has streams.
  /// Returns a list of {provider, streams, subtitles} maps.
  Future<List<Map<String, dynamic>>> getAllSources({
    required int anilistId,
    required int episodeNumber,
  }) async {
    // 1. Get available providers
    Map<String, dynamic> mappings;
    try {
      mappings = await getMappings(anilistId);
    } catch (e) {
      debugPrint('[AnimeRealms] Failed to get mappings: $e');
      mappings = {};
    }

    final providerNames = getProviderNames(mappings);

    debugPrint('[AnimeRealms] Trying ${providerNames.length} providers for $anilistId ep $episodeNumber');

    final results = <Map<String, dynamic>>[];

    for (final provider in providerNames) {
      try {
        final data = await getStreams(
          provider: provider,
          anilistId: anilistId,
          episodeNumber: episodeNumber,
        );
        final streams = data['streams'] as List?;
        if (streams != null && streams.isNotEmpty) {
          final real = streams.where((s) =>
              s['url'] != null &&
              !(s['url'] as String).contains('test-streams.mux.dev')).toList();
          if (real.isNotEmpty) {
            debugPrint('[AnimeRealms] ✓ $provider: ${real.length} stream(s)');
            results.add({
              'provider': provider,
              'streams': real,
              'subtitles': data['subtitles'] ?? [],
            });
          }
        }
      } catch (e) {
        debugPrint('[AnimeRealms] ✗ $provider: $e');
      }
    }

    return results;
  }

  /// Extract provider names from a mappings response.
  /// The API returns a flat map like {"allmanga":"id","hianime":"id",...}
  static List<String> getProviderNames(Map<String, dynamic> mappings) {
    if (mappings.isEmpty) return _defaultProviders;
    // Filter out non-provider keys (error, message, etc.)
    final names = mappings.keys
        .where((k) => mappings[k] is String || mappings[k] is num)
        .toList();
    return names.isNotEmpty ? names : _defaultProviders;
  }

  static const List<String> _defaultProviders = [
    'allmanga', 'hianime', 'gogoanime', 'zencloud',
    'animepahe', 'animez', 'animekai', 'kickassanime',
    'anizone', 'febbox', 'hanime-tv',
  ];
}
