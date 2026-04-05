import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:flutter/foundation.dart';
import '../scrapers/scraper_aggregator.dart';

class LocalServerService {
  static final LocalServerService _instance = LocalServerService._internal();
  factory LocalServerService() => _instance;
  LocalServerService._internal();

  HttpServer? _server;
  final Router _router = Router();
  int _port = 0;

  // Persistent HTTP client for connection reuse (keep-alive)
  final http.Client _httpClient = http.Client();

  int get port => _port;
  String get baseUrl => 'http://localhost:$_port';

  Future<void> start() async {
    if (_server != null) return;

    _setupRoutes();

    try {
      _server = await io.serve(_router.call, InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      debugPrint('[LocalServer] Started on $baseUrl');
    } catch (e) {
      debugPrint('[LocalServer] Error starting server: $e');
    }
  }

  void _setupRoutes() {
    _router.get('/api/ultimate', (Request request) async {
      final params = request.url.queryParameters;
      final query = params['query'];
      if (query == null || query.isEmpty) {
        return Response(400, body: json.encode({'error': 'Query parameter is required'}), headers: {'content-type': 'application/json'});
      }
      try {
        final results = await ScraperAggregator.searchAll(query);
        return Response.ok(json.encode({'query': query, 'totalResults': results.length, 'results': results}), headers: {'content-type': 'application/json'});
      } catch (e) {
        return Response(500, body: json.encode({'error': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // --- Tokybook Specialized Proxy ---
    _router.get('/toky-proxy', _handleTokyProxy);

    // --- Comic Specialized Proxy ---
    _router.get('/comic-proxy', _handleComicProxy);

    // --- Jellyfin Streaming Proxy ---
    _router.add('GET', '/jellyfin-stream', _handleJellyfinStream);
    _router.add('HEAD', '/jellyfin-stream', _handleJellyfinStream);

    _router.add('GET', '/proxy', _handleProxyRequest);
    _router.add('HEAD', '/proxy', _handleProxyRequest);

    // --- HLS-aware streaming proxy (rewrites m3u8 segment URLs) ---
    _router.add('GET', '/hls-proxy', _handleHlsProxy);
    _router.add('HEAD', '/hls-proxy', _handleHlsProxy);

    _router.get('/health', (Request request) {
      return Response.ok(json.encode({'status': 'ok', 'port': _port}), headers: {'content-type': 'application/json'});
    });
  }

  Future<Response> _handleTokyProxy(Request request) async {
    final params = request.url.queryParameters;
    final targetUrl = params['url'];
    final audiobookId = params['id'];
    final token = params['token'];
    final trackSrc = params['src'];

    if (targetUrl == null) return Response.notFound('Missing url');

    // FIX: Decode the path before passing to Uri.https to prevent double-encoding (%2520)
    // targetUrl comes in already decoded by shelf from the query param
    final baseUri = Uri.parse(targetUrl);
    final decodedPath = Uri.decodeComponent(baseUri.path);
    
    // Construct final URL with single encoding
    final finalUrl = Uri.https('tokybook.com', decodedPath).toString();

    // Construct track source header with single encoding
    final String finalTrackSrc;
    if (trackSrc != null) {
      finalTrackSrc = Uri.https('tokybook.com', Uri.decodeComponent(trackSrc)).path;
    } else {
      finalTrackSrc = '';
    }

    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
      'Referer': 'https://tokybook.com/',
      'Origin': 'https://tokybook.com',
      'Accept': '*/*',
      ...?audiobookId != null ? {'x-audiobook-id': audiobookId} : null,
      ...?token != null ? {'x-stream-token': token} : null,
      'x-track-src': finalTrackSrc,
    };

    debugPrint('[TokyProxy] GET $finalUrl');

    try {
      final res = await http.get(Uri.parse(finalUrl), headers: headers);
      
      if (res.statusCode != 200) {
        debugPrint('[TokyProxy] Error ${res.statusCode} from Tokybook');
        return Response(res.statusCode, body: res.body);
      }

      if (targetUrl.endsWith('.m3u8')) {
        String body = res.body;
        final baseDir = targetUrl.substring(0, targetUrl.lastIndexOf('/') + 1);
        final baseSrcDir = trackSrc?.substring(0, trackSrc.lastIndexOf('/') + 1) ?? '';
        
        final lines = body.split('\n');
        final rewrittenLines = lines.map((line) {
          if (line.isEmpty || line.startsWith('#')) return line;
          
          final segmentUrl = line.startsWith('http') ? line : '$baseDir$line';
          final segmentSrc = line.startsWith('http') ? line : '$baseSrcDir$line';
          
          return getTokyProxyUrl(segmentUrl, audiobookId ?? '', token ?? '', segmentSrc);
        }).toList();
        
        return Response.ok(
          rewrittenLines.join('\n'),
          headers: {'Content-Type': 'application/x-mpegURL'},
        );
      }

      return Response.ok(res.bodyBytes, headers: {
        'Content-Type': res.headers['content-type'] ?? 'video/mp2t',
        'Access-Control-Allow-Origin': '*',
      });
    } catch (e) {
      debugPrint('[TokyProxy] Fatal Error: $e');
      return Response.internalServerError(body: e.toString());
    }
  }

  String getTokyProxyUrl(String url, String id, String token, String src) {
    return '$baseUrl/toky-proxy?url=${Uri.encodeComponent(url)}&id=$id&token=${Uri.encodeComponent(token)}&src=${Uri.encodeComponent(src)}';
  }

  Future<Response> _handleComicProxy(Request request) async {
    // Get the raw query string to avoid shelf splitting it at '&'
    final queryStr = request.requestedUri.query;
    final urlMatch = RegExp(r'url=(.*)').firstMatch(queryStr);
    
    if (urlMatch == null) return Response.notFound('Missing url');
    
    final targetUrl = Uri.decodeComponent(urlMatch.group(1)!);
    
    debugPrint('[ComicProxy] Fetching: $targetUrl');

    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
      'Referer': 'https://readcomiconline.li/',
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Sec-Fetch-Dest': 'image',
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Site': 'cross-site',
    };

    try {
      final res = await http.get(Uri.parse(targetUrl), headers: headers);
      
      if (res.statusCode != 200) {
        debugPrint('[ComicProxy] Error ${res.statusCode} from ${Uri.parse(targetUrl).host}');
        debugPrint('[ComicProxy] Response body: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
        return Response(res.statusCode, body: res.body);
      }

      return Response.ok(res.bodyBytes, headers: {
        'Content-Type': res.headers['content-type'] ?? 'image/jpeg',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'public, max-age=86400',
      });
    } catch (e) {
      debugPrint('[ComicProxy] Fatal Error: $e');
      return Response.internalServerError(body: e.toString());
    }
  }

  String getComicProxyUrl(String url) {
    // URL encode the entire URL to preserve special characters
    return '$baseUrl/comic-proxy?url=${Uri.encodeComponent(url)}';
  }

  /// Jellyfin streaming proxy — forwards requests with proper auth headers
  /// so that mpv / media_kit can play from servers that reject api_key query params.
  /// Also rewrites HLS m3u8 playlists so segment URLs go through the proxy too.
  Future<Response> _handleJellyfinStream(Request request) async {
    final params = request.url.queryParameters;
    final targetUrl = params['url'];
    final authHeader = params['auth'];

    if (targetUrl == null || authHeader == null) {
      return Response(400, body: 'Missing url or auth parameter');
    }

    final decodedUrl = Uri.decodeComponent(targetUrl);
    final targetUri = Uri.parse(decodedUrl);
    final serverBase = '${targetUri.scheme}://${targetUri.host}${targetUri.hasPort ? ':${targetUri.port}' : ''}';
    debugPrint('[JellyfinProxy] ${request.method} $decodedUrl');

    try {
      final client = http.Client();
      final req = http.Request(request.method, targetUri);

      // Set Jellyfin auth headers
      req.headers['X-Emby-Authorization'] = authHeader;
      req.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';
      req.headers['Accept'] = '*/*';
      req.headers['Connection'] = 'keep-alive';

      // Forward Range header for seeking support
      final range = request.headers['range'];
      if (range != null) {
        req.headers['Range'] = range;
        debugPrint('[JellyfinProxy] Range: $range');
      }

      final streamedResponse = await client.send(req);

      if (streamedResponse.statusCode >= 400) {
        debugPrint('[JellyfinProxy] Upstream error: ${streamedResponse.statusCode}');
      }

      final contentType = streamedResponse.headers['content-type'] ?? '';

      // HLS playlist? Rewrite segment/sub-playlist URLs to go through proxy
      if (contentType.contains('mpegurl') ||
          contentType.contains('x-mpegurl') ||
          decodedUrl.contains('.m3u8')) {
        final body = await streamedResponse.stream.bytesToString();
        final basePath = decodedUrl.substring(0, decodedUrl.lastIndexOf('/') + 1);

        final rewrittenLines = body.split('\n').map((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) {
            // Rewrite URI= attributes inside #EXT-X-MAP or #EXT-X-MEDIA
            if (trimmed.contains('URI="')) {
              return trimmed.replaceAllMapped(
                RegExp(r'URI="([^"]+)"'),
                (m) {
                  final uri = m.group(1)!;
                  final fullUri = uri.startsWith('http') ? uri
                      : uri.startsWith('/') ? '$serverBase$uri'
                      : '$basePath$uri';
                  return 'URI="${getJellyfinProxyUrl(fullUri, authHeader)}"';
                },
              );
            }
            return line;
          }
          // Non-comment, non-empty line = segment or sub-playlist URL
          final fullUrl = trimmed.startsWith('http') ? trimmed
              : trimmed.startsWith('/') ? '$serverBase$trimmed'
              : '$basePath$trimmed';
          return getJellyfinProxyUrl(fullUrl, authHeader);
        }).toList();

        return Response.ok(
          rewrittenLines.join('\n'),
          headers: {
            'Content-Type': 'application/vnd.apple.mpegurl',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }

      final responseHeaders = <String, String>{
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
        'Access-Control-Allow-Headers': '*',
        'Accept-Ranges': 'bytes',
        'Connection': 'keep-alive',
      };

      // Forward critical headers for playback
      final fwd = ['content-type', 'content-length', 'content-range',
                    'accept-ranges', 'content-disposition', 'etag',
                    'last-modified', 'x-emby-content-duration'];
      for (final h in fwd) {
        final v = streamedResponse.headers[h];
        if (v != null) responseHeaders[h] = v;
      }

      return Response(
        streamedResponse.statusCode,
        body: streamedResponse.stream,
        headers: responseHeaders,
      );
    } catch (e) {
      debugPrint('[JellyfinProxy] Fatal Error: $e');
      return Response.internalServerError(body: 'Jellyfin proxy error: $e');
    }
  }

  /// Returns a local proxy URL for a Jellyfin stream.
  String getJellyfinProxyUrl(String targetUrl, String authHeaderValue) {
    return '$baseUrl/jellyfin-stream'
        '?url=${Uri.encodeComponent(targetUrl)}'
        '&auth=${Uri.encodeComponent(authHeaderValue)}';
  }

  Future<Response> _handleProxyRequest(Request request) async {
    final params = request.url.queryParameters;
    final targetUrl = params['url'];
    if (targetUrl == null) return Response.notFound('Missing url parameter');
    final decodedUrl = Uri.decodeComponent(targetUrl);
    Map<String, String> customHeaders = {};
    if (params['headers'] != null) {
      try {
        customHeaders = Map<String, String>.from(json.decode(params['headers']!));
      } catch (e) {
        // Ignore invalid JSON headers
      }
    }

    try {
      final proxyHeaders = <String, String>{
        'User-Agent': customHeaders['User-Agent'] ?? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': customHeaders['Referer'] ?? 'https://www.youtube.com/',
        if (customHeaders.containsKey('Origin')) 'Origin': customHeaders['Origin']!,
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive',
      };

      final range = request.headers['range'];
      if (range != null) {
        proxyHeaders['Range'] = range;
        debugPrint('[LocalProxy] Range: $range');
      }

      final client = http.Client();
      final req = http.Request(request.method, Uri.parse(decodedUrl));
      req.headers.addAll(proxyHeaders);
      
      final streamedResponse = await client.send(req);

      final responseHeaders = <String, String>{
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS, POST',
        'Access-Control-Allow-Headers': '*',
        'Accept-Ranges': 'bytes',
        'Connection': 'keep-alive',
        'Content-Type': streamedResponse.headers['content-type'] ?? 'audio/mpeg',
      };

      // Forward these critical headers for seeking
      if (streamedResponse.headers.containsKey('content-length')) {
        responseHeaders['Content-Length'] = streamedResponse.headers['content-length']!;
      }
      if (streamedResponse.headers.containsKey('content-range')) {
        responseHeaders['Content-Range'] = streamedResponse.headers['content-range']!;
      }
      if (streamedResponse.headers.containsKey('accept-ranges')) {
        responseHeaders['Accept-Ranges'] = streamedResponse.headers['accept-ranges']!;
      }

      return Response(streamedResponse.statusCode, body: streamedResponse.stream, headers: responseHeaders);
    } catch (e) {
      return Response.internalServerError(body: 'Proxy error: $e');
    }
  }

  /// HLS-aware proxy: fetches with custom headers, rewrites m3u8 playlists
  /// so that segment/sub-playlist URLs also go through the proxy.
  Future<Response> _handleHlsProxy(Request request) async {
    final params = request.url.queryParameters;
    final targetUrl = params['url'];
    final headersJson = params['headers'];

    if (targetUrl == null) {
      return Response(400, body: 'Missing url parameter');
    }

    final decodedUrl = Uri.decodeComponent(targetUrl);
    final targetUri = Uri.parse(decodedUrl);
    final serverBase = '${targetUri.scheme}://${targetUri.host}${targetUri.hasPort ? ':${targetUri.port}' : ''}';

    Map<String, String> customHeaders = {};
    if (headersJson != null) {
      try {
        customHeaders = Map<String, String>.from(json.decode(headersJson));
      } catch (_) {}
    }

    final proxyHeaders = <String, String>{
      'User-Agent': customHeaders['User-Agent'] ?? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
      if (customHeaders.containsKey('Referer')) 'Referer': customHeaders['Referer']!,
      if (customHeaders.containsKey('Origin')) 'Origin': customHeaders['Origin']!,
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
    };

    final range = request.headers['range'];
    if (range != null) proxyHeaders['Range'] = range;

    try {
      final req = http.Request(request.method, targetUri);
      req.headers.addAll(proxyHeaders);
      final streamedResponse = await _httpClient.send(req);

      if (streamedResponse.statusCode >= 400) {
        debugPrint('[HlsProxy] Upstream ${streamedResponse.statusCode} for $decodedUrl');
      }

      final contentType = streamedResponse.headers['content-type'] ?? '';

      // HLS playlist? Rewrite URLs so sub-playlists & segments also go through proxy
      if (contentType.contains('mpegurl') ||
          contentType.contains('x-mpegurl') ||
          decodedUrl.contains('.m3u8')) {
        final body = await streamedResponse.stream.bytesToString();
        final basePath = decodedUrl.substring(0, decodedUrl.lastIndexOf('/') + 1);

        final rewrittenLines = body.split('\n').map((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) {
            // Rewrite URI= attributes inside EXT tags
            if (trimmed.contains('URI="')) {
              return trimmed.replaceAllMapped(
                RegExp(r'URI="([^"]+)"'),
                (m) {
                  final uri = m.group(1)!;
                  final fullUri = uri.startsWith('http') ? uri
                      : uri.startsWith('/') ? '$serverBase$uri'
                      : '$basePath$uri';
                  return 'URI="${getHlsProxyUrl(fullUri, customHeaders)}"';
                },
              );
            }
            return line;
          }
          // Non-comment line = segment or sub-playlist URL
          final fullUrl = trimmed.startsWith('http') ? trimmed
              : trimmed.startsWith('/') ? '$serverBase$trimmed'
              : '$basePath$trimmed';
          return getHlsProxyUrl(fullUrl, customHeaders);
        }).toList();

        return Response.ok(
          rewrittenLines.join('\n'),
          headers: {
            'Content-Type': 'application/vnd.apple.mpegurl',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }

      // Non-HLS (segments, mp4, etc.) — stream through
      final responseHeaders = <String, String>{
        'Access-Control-Allow-Origin': '*',
        'Accept-Ranges': 'bytes',
        'Connection': 'keep-alive',
      };
      for (final h in ['content-type', 'content-length', 'content-range', 'accept-ranges']) {
        final v = streamedResponse.headers[h];
        if (v != null) responseHeaders[h] = v;
      }

      return Response(streamedResponse.statusCode, body: streamedResponse.stream, headers: responseHeaders);
    } catch (e) {
      debugPrint('[HlsProxy] Error: $e');
      return Response.internalServerError(body: 'HLS proxy error: $e');
    }
  }

  /// Returns a local proxy URL for an HLS stream with custom headers.
  String getHlsProxyUrl(String targetUrl, Map<String, String> headers) {
    return '$baseUrl/hls-proxy'
        '?url=${Uri.encodeComponent(targetUrl)}'
        '&headers=${Uri.encodeComponent(json.encode(headers))}';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }
}
