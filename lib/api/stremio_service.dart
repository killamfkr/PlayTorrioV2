import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'settings_service.dart';

class StremioService {
  static final StremioService _instance = StremioService._internal();
  factory StremioService() => _instance;
  StremioService._internal();

  final SettingsService _settings = SettingsService();

  /// Manifest catalog [type] values for live TV lineups (Stremio uses `channel`;
  /// some addons e.g. Debridio TV use `tv` with `idPrefixes` like `debtv:`).
  static bool isLiveTvCatalogType(Object? catalogType) {
    final t = catalogType?.toString().toLowerCase() ?? '';
    return t == 'channel' || t == 'tv';
  }

  /// Resource path segment for `/stream/{type}/{id}.json` from a catalog/meta `type` field.
  /// Live TV addons often use `tv` or `channel`; episode-based addons use `series` / `movie`.
  static String streamTypeForStremioMetaType(String? metaType, {String? fallbackMediaType}) {
    final t = metaType?.toString().toLowerCase() ?? '';
    if (t == 'tv' || t == 'channel') return 'tv';
    if (t == 'series' || t == 'movie' || t == 'collections') return t;
    final m = fallbackMediaType?.toLowerCase() ?? '';
    if (m == 'tv') return 'series';
    return 'movie';
  }

  /// Retry an HTTP GET with exponential backoff.
  /// Does NOT retry on 404 (content simply doesn't exist).
  Future<http.Response> _retryGet(Uri uri, {int retries = 2, Duration timeout = const Duration(seconds: 15)}) async {
    http.Response? lastResponse;
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await http.get(uri).timeout(timeout);
        if (response.statusCode == 200) return response;
        lastResponse = response;
        if (response.statusCode == 404) break; // Don't retry 404s
      } catch (e) {
        lastError = e;
      }
      if (attempt < retries) {
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    if (lastResponse != null) return lastResponse;
    throw lastError ?? Exception('Request failed after $retries retries');
  }

  /// Extracts a clean base URL and optional query parameters from an addon URL.
  /// Handles addons that embed config as query params (e.g. ?apikey=...).
  static ({String baseUrl, String? queryParams}) _splitAddonUrl(String url) {
    final qIdx = url.indexOf('?');
    String path = qIdx >= 0 ? url.substring(0, qIdx) : url;
    final query = qIdx >= 0 ? url.substring(qIdx + 1) : null;
    path = path.replaceAll(RegExp(r'/manifest\.json$'), '').replaceAll(RegExp(r'/$'), '');
    if (!path.startsWith('http')) path = 'https://$path';
    return (baseUrl: path, queryParams: query);
  }

  /// Builds a full resource URL, correctly re-appending any addon query params.
  String _buildResourceUrl(String addonBaseUrl, String resourcePath) {
    final parts = _splitAddonUrl(addonBaseUrl);
    final qp = parts.queryParams;
    return qp != null
        ? '${parts.baseUrl}$resourcePath?$qp'
        : '${parts.baseUrl}$resourcePath';
  }

  /// Fetches and validates an addon manifest from a URL
  Future<Map<String, dynamic>?> fetchManifest(String url) async {
    String manifestUrl = url.trim();
    if (manifestUrl.isEmpty) return null;

    // Handle stremio:// protocol
    if (manifestUrl.startsWith('stremio://')) {
      manifestUrl = manifestUrl.replaceFirst('stremio://', 'https://');
    }

    // Installer / playlist URL: same path as addon root; swap last segment for manifest.json
    if (RegExp(r'\.m3u8$', caseSensitive: false).hasMatch(manifestUrl)) {
      manifestUrl = manifestUrl.replaceAll(
        RegExp(r'[^/]+\.m3u8$', caseSensitive: false),
        'manifest.json',
      );
    }

    // Ensure it ends with manifest.json
    if (!manifestUrl.endsWith('/manifest.json')) {
      manifestUrl = manifestUrl.endsWith('/') 
          ? '${manifestUrl}manifest.json' 
          : '$manifestUrl/manifest.json';
    }

    try {
      final response = await http.get(Uri.parse(manifestUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final manifest = json.decode(response.body);
        // Extract clean base URL, separating any query params
        final parts = _splitAddonUrl(manifestUrl);
        // Store the raw base (with query params) so _buildResourceUrl can re-attach them
        final baseUrl = parts.queryParams != null
            ? '${parts.baseUrl}?${parts.queryParams}'
            : parts.baseUrl;

        return {
          'baseUrl': baseUrl,
          'manifest': manifest,
          'name': manifest['name'] ?? 'Unknown Addon',
          'icon': manifest['logo'] ?? '',
        };
      }
    } catch (e) {
      debugPrint('[StremioService] Manifest fetch error: $e');
    }
    return null;
  }

  /// Fetches streams from a specific addon (with retry)
  Future<List<dynamic>> getStreams({
    required String baseUrl,
    required String type, // 'movie' or 'series'
    required String id,   // tt... or tt...:s:e
  }) async {
    final encodedId = id.contains('/') ? Uri.encodeComponent(id) : id;
    final resourcePath = '/stream/$type/$encodedId.json';
    final url = _buildResourceUrl(baseUrl, resourcePath);
    debugPrint('[StremioService.getStreams] URL: $url');
    try {
      final response = await _retryGet(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['streams'] ?? [];
      }
    } catch (e) {
      debugPrint('[StremioService] Stream fetch error ($url): $e');
    }
    return [];
  }

  /// Fetches subtitles from a specific addon (with retry)
  Future<List<Map<String, dynamic>>> getSubtitles({
    required String baseUrl,
    required String type,
    required String id,
    String? addonName,
  }) async {
    final List<Map<String, dynamic>> results = [];
    final encodedId = id.contains('/') ? Uri.encodeComponent(id) : id;
    final resourcePath = '/subtitles/$type/$encodedId.json';
    final url = _buildResourceUrl(baseUrl, resourcePath);
    try {
      final response = await _retryGet(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List subs = data['subtitles'] ?? [];
        for (var s in subs) {
          results.add({
            'id': s['id'] ?? s['url'],
            'url': s['url'],
            'language': s['lang'] ?? 'Unknown',
            'display': '${s['lang']?.toUpperCase() ?? '??'} - ${addonName ?? 'Addon'}',
            'sourceName': addonName ?? 'Stremio Addon',
          });
        }
      }
    } catch (e) {
      debugPrint('[StremioService] Subtitle fetch error ($url): $e');
    }
    return results;
  }

  /// Helper to get all installed addons that support a specific resource.
  /// Optionally filters by content [type] (e.g. 'movie', 'series').
  Future<List<Map<String, dynamic>>> getAddonsForResource(String resourceName, {String? type}) async {
    final allAddons = await _settings.getStremioAddons();
    return allAddons.where((addon) {
      final manifest = addon['manifest'];
      if (manifest is! Map) return false;
      final resources = manifest['resources'] as List?;
      if (resources == null) return false;
      return resources.any((r) {
        if (r is String) {
          if (r != resourceName) return false;
          // Simple string resource — check manifest-level types if filtering
          if (type != null) {
            final types = manifest['types'] as List?;
            return types != null && types.contains(type);
          }
          return true;
        }
        if (r is Map && r['name'] == resourceName) {
          if (type != null) {
            final types = r['types'] as List?;
            if (types != null && types.isNotEmpty) return types.contains(type);
            // No types on resource → fall back to manifest-level
            final mTypes = manifest['types'] as List?;
            return mTypes == null || mTypes.contains(type);
          }
          return true;
        }
        return false;
      });
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CATALOG
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns all catalogs from installed addons, each annotated with the
  /// parent addon's baseUrl and name.
  /// Handles both the detailed `extra` format (objects) and the legacy
  /// `extraSupported` / `extraRequired` flat string arrays.
  Future<List<Map<String, dynamic>>> getAllCatalogs() async {
    // Use all installed addons that declare at least one catalog.
    // We intentionally do NOT filter by getAddonsForResource('catalog')
    // because many addons omit 'catalog' from their resources array even
    // when they provide catalogs.  The presence of a non-empty 'catalogs'
    // list in the manifest is the authoritative signal.
    final allAddons = await _settings.getStremioAddons();
    final catalogAddons = allAddons.where((addon) {
      final manifest = addon['manifest'];
      if (manifest is! Map) return false;
      final cats = manifest['catalogs'];
      return cats is List && cats.isNotEmpty;
    }).toList();
    final List<Map<String, dynamic>> result = [];
    for (final addon in catalogAddons) {
      final manifest = addon['manifest'] as Map<String, dynamic>;
      final catalogs = manifest['catalogs'] as List? ?? [];
      for (final cat in catalogs) {
        if (cat is! Map) continue;

        // ── Determine supported / required extras from both formats ──────
        final extra = cat['extra'] as List? ?? [];
        final extraSupportedRaw = cat['extraSupported'] as List?;
        final extraRequiredRaw = cat['extraRequired'] as List?;

        // Build canonical sets using detailed `extra` objects first,
        // then falling back to `extraSupported` / `extraRequired`.
        final Set<String> supported = {};
        final Set<String> required = {};

        for (final e in extra) {
          if (e is Map) {
            final name = e['name']?.toString() ?? '';
            if (name.isNotEmpty) supported.add(name);
            if (e['isRequired'] == true) required.add(name);
          } else if (e is String) {
            supported.add(e);
          }
        }

        // Merge legacy flat arrays if they provide additional info
        if (extraSupportedRaw != null) {
          for (final s in extraSupportedRaw) {
            if (s is String) supported.add(s);
          }
        }
        if (extraRequiredRaw != null) {
          for (final r in extraRequiredRaw) {
            if (r is String) required.add(r);
          }
        }

        // Skip catalogs that REQUIRE special extras we can't provide
        // (e.g. Cinemeta's lastVideosIds / calendarVideosIds)
        final unfulfillable = required.where((n) => n != 'genre' && n != 'search');
        if (unfulfillable.isNotEmpty) continue;

        // ── Genres: prefer top-level, fall back to extra[genre].options ──
        List<String> genres = (cat['genres'] as List?)?.cast<String>() ?? <String>[];
        if (genres.isEmpty) {
          for (final e in extra) {
            if (e is Map && e['name'] == 'genre' && e['options'] is List) {
              genres = (e['options'] as List).cast<String>();
              break;
            }
          }
        }

        result.add({
          'addonBaseUrl': addon['baseUrl'],
          'addonName': addon['name'] ?? manifest['name'] ?? 'Unknown',
          'addonIcon': addon['icon'] ?? manifest['logo'] ?? '',
          'catalogId': cat['id'],
          'catalogName': cat['name'] ?? cat['id'],
          'catalogType': cat['type'],
          'genres': genres,
          'extra': extra,
          'supportsSearch': supported.contains('search'),
          'searchRequired': required.contains('search'),
          'supportsGenre': supported.contains('genre'),
          'supportsSkip': supported.contains('skip'),
        });
      }
    }
    return result;
  }

  /// Fetches a catalog feed.
  /// [genre] and [skip] are optional extra params.
  /// Extra args are placed in the URL path per the Stremio protocol:
  ///   /{resource}/{type}/{id}/{extraArgs}.json
  Future<List<Map<String, dynamic>>> getCatalog({
    required String baseUrl,
    required String type,
    required String id,
    String? genre,
    int? skip,
    String? search,
  }) async {
    final parts = <String>[];
    if (search != null && search.isNotEmpty) {
      parts.add('search=${Uri.encodeComponent(search)}');
    }
    if (genre != null && genre.isNotEmpty) {
      parts.add('genre=${Uri.encodeComponent(genre)}');
    }
    if (skip != null && skip > 0) {
      parts.add('skip=$skip');
    }
    final extra = parts.isNotEmpty ? '/${parts.join('&')}' : '';
    final resourcePath = '/catalog/$type/$id$extra.json';
    final url = _buildResourceUrl(baseUrl, resourcePath);
    debugPrint('[StremioService.getCatalog] URL: $url');

    try {
      final response = await _retryGet(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final metas = data['metas'] as List? ?? [];
        return metas.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[StremioService] Catalog fetch error ($url): $e');
    }
    return [];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  METADATA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Fetches full meta for a specific item (with retry).
  /// GET {baseUrl}/meta/{type}/{id}.json
  /// Supports both regular content and collections (which have a 'videos' array).
  Future<Map<String, dynamic>?> getMeta({
    required String baseUrl,
    required String type,
    required String id,
  }) async {
    final encodedId = id.contains('/') ? Uri.encodeComponent(id) : id;
    final resourcePath = '/meta/$type/$encodedId.json';
    final url = _buildResourceUrl(baseUrl, resourcePath);
    try {
      final response = await _retryGet(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final meta = data['meta'] as Map<String, dynamic>?;
        
        // For collections, convert videos array to a format similar to TV episodes
        if (meta != null && meta['type'] == 'collections' && meta['videos'] is List) {
          meta['_isCollection'] = true;
        }
        
        return meta;
      }
    } catch (e) {
      debugPrint('[StremioService] Meta fetch error ($url): $e');
    }
    return null;
  }

  /// Fetches meta from ALL installed addons that can handle this id and type.
  /// Returns the first successful non-null response.
  Future<Map<String, dynamic>?> getMetaFromAny({
    required String type,
    required String id,
  }) async {
    final addons = await getAddonsForResource('meta', type: type);
    for (final addon in addons) {
      final manifest = addon['manifest'] as Map<String, dynamic>;
      // Check idPrefixes filter
      final idPrefixes = _getIdPrefixes(manifest, 'meta');
      if (idPrefixes.isNotEmpty && !idPrefixes.any((p) => id.startsWith(p))) {
        continue;
      }
      final meta = await getMeta(baseUrl: addon['baseUrl'], type: type, id: id);
      if (meta != null && meta.isNotEmpty && meta['id'] != null) return meta;
    }
    return null;
  }

  /// Extracts idPrefixes for a specific resource from a manifest.
  List<String> _getIdPrefixes(Map<String, dynamic> manifest, String resourceName) {
    final resources = manifest['resources'] as List? ?? [];
    // Check resource-level idPrefixes first
    for (final r in resources) {
      if (r is Map && r['name'] == resourceName && r['idPrefixes'] != null) {
        return (r['idPrefixes'] as List).cast<String>();
      }
    }
    // Fallback to manifest-level
    final prefixes = manifest['idPrefixes'] as List?;
    return prefixes?.cast<String>() ?? [];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  SEARCH (catalog-based)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Searches across ALL installed addons that have catalogs with search support.
  /// Returns a flat list of meta preview objects with addon info attached.
  Future<List<Map<String, dynamic>>> searchAllAddons(String query) async {
    if (query.trim().isEmpty) return [];
    final catalogs = await getAllCatalogs();
    final searchable = catalogs.where((c) => c['supportsSearch'] == true).toList();

    final List<Map<String, dynamic>> allResults = [];
    final futures = <Future>[];

    for (final cat in searchable) {
      futures.add(
        getCatalog(
          baseUrl: cat['addonBaseUrl'],
          type: cat['catalogType'],
          id: cat['catalogId'],
          search: query,
        ).then((metas) {
          for (final m in metas) {
            m['_addonName'] = cat['addonName'];
            m['_addonBaseUrl'] = cat['addonBaseUrl'];
            m['_catalogType'] = cat['catalogType'];
          }
          allResults.addAll(metas);
        }).catchError((_) {}),
      );
    }
    await Future.wait(futures);
    return allResults;
  }

  /// Searches a specific addon's catalog.
  Future<List<Map<String, dynamic>>> searchAddonCatalog({
    required String baseUrl,
    required String type,
    required String catalogId,
    required String query,
  }) async {
    return getCatalog(baseUrl: baseUrl, type: type, id: catalogId, search: query);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  META LINK PARSING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Parses a Stremio meta link URL and returns an action descriptor.
  /// Supported formats:
  ///   stremio:///detail/{type}/{id}
  ///   stremio:///detail/{type}/{id}/{videoId}
  ///   stremio:///search?search={query}
  ///   stremio:///discover/{transportUrl}/{type}/{catalogId}?{extra}
  static Map<String, dynamic>? parseMetaLink(String url) {
    // Normalize
    String u = url.trim();
    if (u.startsWith('stremio://')) {
      u = u.replaceFirst('stremio://', 'stremio:///');
      // Fix triple slashes if already had them
      u = u.replaceAll('stremio:////', 'stremio:///');
    }

    // detail link
    final detailMatch = RegExp(r'stremio:///detail/([^/]+)/([^/?]+)(?:/([^/?]+))?').firstMatch(u);
    if (detailMatch != null) {
      return {
        'action': 'detail',
        'type': detailMatch.group(1),
        'id': detailMatch.group(2),
        'videoId': detailMatch.group(3),
      };
    }

    // search link
    final searchMatch = RegExp(r'stremio:///search\?search=(.+)').firstMatch(u);
    if (searchMatch != null) {
      return {
        'action': 'search',
        'query': Uri.decodeComponent(searchMatch.group(1)!),
      };
    }

    // discover link
    final discoverMatch = RegExp(r'stremio:///discover/([^/]+)/([^/]+)/([^/?]+)(.*)').firstMatch(u);
    if (discoverMatch != null) {
      return {
        'action': 'discover',
        'transportUrl': Uri.decodeComponent(discoverMatch.group(1)!),
        'type': discoverMatch.group(2),
        'catalogId': discoverMatch.group(3),
        'extra': discoverMatch.group(4),
      };
    }

    return null;
  }

  /// Resolves a Stremio meta ID to a TMDB Movie object.
  /// Handles: tt1234567 (IMDB), tmdb:12345, kitsu:12345, and custom IDs.
  /// For IMDB IDs, uses TMDB find-by-external-id endpoint.
  /// For others, fetches meta from addons and maps to Movie.
  Future<Map<String, dynamic>?> resolveIdToMeta(String id, String type) async {
    // Already an IMDB ID → let TMDB handle it
    if (id.startsWith('tt')) {
      return {'action': 'tmdb_lookup', 'imdbId': id, 'type': type};
    }
    // Try to get full meta from addons
    final meta = await getMetaFromAny(type: type, id: id);
    if (meta != null) {
      return {'action': 'stremio_meta', 'meta': meta, 'type': type};
    }
    return null;
  }
}
