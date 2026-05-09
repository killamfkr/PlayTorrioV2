import 'dart:async';
import 'dart:collection';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/stream_source.dart';
import 'amri_extractor.dart';
import 'tmdb_service.dart';

class ExtractedMedia {
  final String url;
  final String? audioUrl;
  final Map<String, String> headers;
  final List<StreamSource>? sources;
  final String? provider;
  /// Optional external subtitles: [{url, title, language}].
  final List<Map<String, dynamic>>? externalSubtitles;

  ExtractedMedia({
    required this.url,
    this.audioUrl,
    required this.headers,
    this.sources,
    this.provider,
    this.externalSubtitles,
  });
}

class StreamExtractor {
  HeadlessInAppWebView? _headlessWebView;
  Completer<ExtractedMedia?>? _completer;
  Timer? _timeoutTimer;
  
  String? _capturedVideo;
  String? _capturedAudio;
  Map<String, String>? _capturedHeaders;
  
  // Track all detected video URLs to select best quality
  final List<String> _detectedVideoUrls = [];
  
  // Amri integration
  AmriExtractor? _amriExtractor;
  final TmdbService _tmdbService = TmdbService();

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  // ── Helper: build default headers from a referer URL ──────────────────────
  Map<String, String> _buildHeaders(String referer) {
    final uri = Uri.tryParse(referer);
    final origin = uri != null ? '${uri.scheme}://${uri.host}' : referer;
    return {
      'User-Agent': _userAgent,
      'Referer': referer,
      'Origin': origin,
    };
  }

  Future<ExtractedMedia?> extractWithAmri({
    required String tmdbId,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    try {
      // Initialize Amri extractor if needed
      _amriExtractor ??= AmriExtractor(onLog: (msg) => debugPrint('[Amri] $msg'));
      
      // Fetch title and year from TMDB
      String title;
      String year;
      
      if (isMovie) {
        final movieData = await _tmdbService.getMovieDetails(tmdbId);
        title = _tmdbService.getMovieTitle(movieData);
        year = _tmdbService.getReleaseYear(movieData);
      } else {
        final tvData = await _tmdbService.getTvShowDetails(tmdbId);
        title = _tmdbService.getTvShowTitle(tvData);
        year = _tmdbService.getReleaseYear(tvData);
      }
      
      // Extract sources
      final sourcesData = await _amriExtractor!.extractSources(
        tmdbId,
        title,
        year,
        season: season,
        episode: episode,
      );
      
      // Check for rate limit
      if (sourcesData['error'] == 'rate_limit') {
        debugPrint('[Amri] Rate limited, will fallback');
        return null;
      }
      
      // Parse sources
      final sourcesList = (sourcesData['sources'] as List?)
          ?.map((s) => StreamSource.fromJson(s as Map<String, dynamic>))
          .toList() ?? [];
      
      debugPrint('[Amri] Parsed ${sourcesList.length} sources');
      
      if (sourcesList.isEmpty) {
        debugPrint('[Amri] No sources found');
        return null;
      }
      
      debugPrint('[Amri] First source URL: ${sourcesList.first.url}');
      debugPrint('[Amri] First source title: ${sourcesList.first.title}');
      
      // Return first source as primary
      return ExtractedMedia(
        url: sourcesList.first.url,
        headers: {'User-Agent': _userAgent},
        sources: sourcesList,
        provider: 'amri',
      );
    } catch (e) {
      debugPrint('[Amri] Error: $e');
      return null;
    }
  }

  Future<ExtractedMedia?> extract(
    String url, {
    Duration timeout = const Duration(seconds: 60),
    String? referer,
    String? iframeWrapperBaseUrl,
  }) async {
    // 0. Ensure previous instance is fully cleaned up before starting new one
    await _cleanup();
    
    _completer = Completer<ExtractedMedia?>();
    _capturedVideo = null;
    _capturedAudio = null;
    _capturedHeaders = null;
    _detectedVideoUrls.clear();
    
    _timeoutTimer = Timer(timeout, () { 
      if (_completer != null && !_completer!.isCompleted) {
        // Select best quality from detected URLs before completing
        if (_detectedVideoUrls.isNotEmpty) {
           _capturedVideo = _selectBestQuality(_detectedVideoUrls);
           _completeWithCaptured(url);
        } else if (_capturedVideo != null) {
           _completeWithCaptured(url);
        } else {
          debugPrint('[StreamExtractor] Sniffing Session Timeout for: $url');
          _cleanup();
          _completer?.complete(null);
        }
      }
    });

    debugPrint('[StreamExtractor] RAW SNIFFER START: $url'
        '${referer != null ? ' (referer=$referer)' : ''}'
        '${iframeWrapperBaseUrl != null ? ' (wrapper=$iframeWrapperBaseUrl)' : ''}');

    // Build the headless webview. There are two modes:
    //  1) Direct: load `url` itself (with optional Referer/Origin headers).
    //  2) Wrapped: load a tiny HTML page via `loadData` whose baseUrl is
    //     `iframeWrapperBaseUrl`. We then iframe `url` inside it. The iframe
    //     receives `document.referrer = iframeWrapperBaseUrl`, defeating
    //     embed providers that block direct loads (megaplay/vidwish).
    if (iframeWrapperBaseUrl != null) {
      _headlessWebView = HeadlessInAppWebView(
        initialData: InAppWebViewInitialData(
          data: _buildIframeWrapperHtml(url),
          baseUrl: WebUri(iframeWrapperBaseUrl),
          historyUrl: WebUri(iframeWrapperBaseUrl),
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        initialSize: const Size(1280, 720),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: _getRawSpyJs(),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: false,
          ),
        ]),
        initialSettings: _wrapperSettings(),
        onLoadResource: _onLoadResource(url),
        onLoadStop: _onLoadStop(),
        onConsoleMessage: _onConsoleMessage(url),
      );
    } else {
      final initialReq = URLRequest(
        url: WebUri(url),
        headers: referer != null
            ? {
                'Referer': referer,
                'Origin': Uri.tryParse(referer)?.origin ?? referer,
              }
            : null,
      );
      _headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: initialReq,
        initialSize: const Size(1280, 720),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: _getRawSpyJs(),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: false,
          ),
        ]),
        initialSettings: _wrapperSettings(),
        onLoadResource: _onLoadResource(url),
        onLoadStop: _onLoadStop(),
        onConsoleMessage: _onConsoleMessage(url),
      );
    }

    try {
      await _headlessWebView?.run();
    } catch (e) {
      debugPrint('[StreamExtractor] Engine Error: $e');
    }
    return _completer?.future;
  }

  // ── Wrapper helpers ──────────────────────────────────────────────────────

  InAppWebViewSettings _wrapperSettings() => InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        userAgent: _userAgent,
        mediaPlaybackRequiresUserGesture: false,
        cacheEnabled: true,
        clearCache: false,
        allowsInlineMediaPlayback: true,
        useOnLoadResource: true,
        iframeAllow: 'autoplay; fullscreen; encrypted-media',
        iframeAllowFullscreen: true,
      );

  void Function(InAppWebViewController, LoadedResource) _onLoadResource(String fallbackReferer) =>
      (controller, resource) {
        final rUrl = resource.url.toString();
        debugPrint('[StreamExtractor Resource] $rUrl');
        _processUrl(rUrl, fallbackReferer);
      };

  void Function(InAppWebViewController, WebUri?) _onLoadStop() =>
      (controller, loadedUrl) async {
        debugPrint('[StreamExtractor] Page Loaded: $loadedUrl');
        await controller.evaluateJavascript(source: _getRawSpyJs());
      };

  void Function(InAppWebViewController, ConsoleMessage) _onConsoleMessage(String fallbackReferer) =>
      (controller, consoleMessage) {
        final msg = consoleMessage.message;
        debugPrint('[StreamExtractor Console] $msg');
        if (msg.contains('PT_EXTRACT:')) {
          String fullMsg =
              msg.substring(msg.indexOf('PT_EXTRACT:') + 'PT_EXTRACT:'.length).trim();
          String streamUrl = fullMsg;
          String? frameUrl;
          if (fullMsg.contains(' | FRAME: ')) {
            final parts = fullMsg.split(' | FRAME: ');
            streamUrl = parts[0];
            frameUrl = parts[1];
          }
          streamUrl = streamUrl.replaceAll('"', '').replaceAll("'", "").trim();
          streamUrl = streamUrl
              .replaceFirst('[FETCH]', '')
              .replaceFirst('[XHR]', '')
              .replaceFirst('[POSTMESSAGE]', '')
              .replaceFirst('[ATTR_SRC]', '')
              .replaceFirst('[MUTATION_SRC]', '')
              .replaceFirst('[ATTR_DATA-SRC]', '')
              .replaceFirst('[VIDEO_SRC]', '')
              .replaceFirst('[SOURCE_SRC]', '')
              .replaceFirst('[MEDIA_PLAY]', '')
              .trim();
          _processUrl(streamUrl, frameUrl ?? fallbackReferer);
        }
      };

  String _buildIframeWrapperHtml(String embedUrl) {
    // Minimal page: full-bleed iframe with autoplay + fullscreen perms.
    // Because we load this via `loadData(baseUrl: …)`, the iframe's
    // `document.referrer` and `window.parent.location.origin` reflect the
    // base URL (e.g. https://www.enma.lol/), which is what megaplay/vidwish
    // gate on. No HTML-escaping needed: the URL was built by us.
    return '''<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="referrer" content="unsafe-url">
<title>player</title>
<style>html,body{margin:0;padding:0;height:100%;background:#000;overflow:hidden}iframe{border:0;width:100%;height:100%;display:block}</style>
</head><body>
<iframe id="p" src="$embedUrl" allow="autoplay; fullscreen; encrypted-media" allowfullscreen referrerpolicy="unsafe-url"></iframe>
</body></html>''';
  }


  void _processUrl(String rUrl, String referer) {
    if ((rUrl.contains('.m3u8') ||
            rUrl.contains('.mp4') ||
            rUrl.contains('playlist') ||
            rUrl.contains('master') ||
            rUrl.contains('.mpd') ||
            rUrl.contains('manifest') ||
            rUrl.contains('heistotron.uk/p/') ||
            // VK CDN direct video URLs (no file extension, query-string based)
            // Exclude API init requests (appId=, asubs=) — only match actual video sources
            (rUrl.contains('okcdn.ru/') && rUrl.contains('type=') && !rUrl.contains('bytes=') && !rUrl.contains('appId=')) ||
            (rUrl.contains('vkuser.net/') && rUrl.contains('type=') && !rUrl.contains('bytes=') && !rUrl.contains('appId='))) &&
        !rUrl.contains('google')) {

       // Check audio only in the URL path (not query params)
       final pathOnly = Uri.tryParse(rUrl)?.path ?? rUrl;
       if (pathOnly.contains('/audio/') || pathOnly.contains('audio_')) {
          debugPrint('[StreamExtractor] AUDIO DETECTED: $rUrl');
          _capturedAudio = rUrl;
          // ✅ FIX: was `headers` (undefined getter) — now builds the map correctly
          _capturedHeaders ??= _buildHeaders(referer);
       } else {
          debugPrint('[StreamExtractor] VIDEO/STREAM DETECTED: $rUrl');
          
          // Add to detected URLs list for quality selection
          if (!_detectedVideoUrls.contains(rUrl)) {
            _detectedVideoUrls.add(rUrl);
          }
          
          // Update captured video with best quality so far
          _capturedVideo = _selectBestQuality(_detectedVideoUrls);
          // ✅ FIX: was `headers` (undefined getter) — now builds the map correctly
          _capturedHeaders ??= _buildHeaders(referer);
       }

       // For anitaro, wait a bit longer to collect all quality options
       // For others, complete immediately if we have video
       if (referer.contains('anitaro')) {
          // Don't complete yet, let timeout handle it after collecting all URLs
       } else if (_capturedVideo != null &&
           (_capturedAudio != null || !referer.contains('anitaro'))) {
          _completeWithCaptured(referer);
       }
    }
  }

  String _selectBestQuality(List<String> urls) {
    // Quality priority: 4K > 2160p > 1440p > 1080p > 720p > 480p > 360p
    final qualityOrder = ['4K', '2160p', '1440p', '1080p', '720p', '480p', '360p'];
    
    for (final quality in qualityOrder) {
      final match = urls.firstWhere(
        (url) => url.toLowerCase().contains('quality=$quality'.toLowerCase()),
        orElse: () => '',
      );
      if (match.isNotEmpty) {
        debugPrint('[StreamExtractor] Selected quality: $quality from ${urls.length} options');
        return match;
      }
    }
    
    // If no quality parameter found, return first URL (likely master playlist)
    return urls.first;
  }

  void _completeWithCaptured(String referer) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(ExtractedMedia(
        url: _capturedVideo!,
        audioUrl: _capturedAudio,
        headers: _capturedHeaders ?? _buildHeaders(referer),
      ));
      _cleanup();
    }
  }

  String _getRawSpyJs() {
    return """
    (function() {
      if (window.pt_raw_injected) return;
      window.pt_raw_injected = true;
      
      const log = (type, url) => {
        if (!url || typeof url !== 'string' || url.startsWith('data:')) return;
        console.log('PT_EXTRACT: [' + type + '] ' + url + ' | FRAME: ' + window.location.href);
      };

      console.log('PT_LOG: Sniffer Active on ' + window.location.href);

      // 1. Popup Blocking
      window.open = function() { return null; };
      window.alert = function() { return true; };

      // 2. Sniff Fetch
      const originalFetch = window.fetch;
      window.fetch = async function(...args) {
        const url = args[0] instanceof Request ? args[0].url : args[0];
        log('FETCH', url);
        return originalFetch.apply(this, args);
      };

      // 3. Sniff XHR
      const originalXHROpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        log('XHR', url);
        return originalXHROpen.apply(this, arguments);
      };

      // 4. Sniff Worker
      const OriginalWorker = window.Worker;
      window.Worker = function(scriptURL, options) {
        log('WORKER', scriptURL);
        return new OriginalWorker(scriptURL, options);
      };

      // 5. Sniff postMessage
      const originalPostMessage = window.postMessage;
      window.postMessage = function(message, targetOrigin, transfer) {
        if (typeof message === 'string') {
           log('POSTMESSAGE', message);
        }
        return originalPostMessage.apply(this, arguments);
      };

      // 6. Sniff URL.createObjectURL
      const originalCreateObjectURL = URL.createObjectURL;
      URL.createObjectURL = function(obj) {
        const url = originalCreateObjectURL.apply(this, arguments);
        log('BLOB_URL', url);
        return url;
      };

      // 7. Hook setAttribute
      const originalSetAttribute = Element.prototype.setAttribute;
      Element.prototype.setAttribute = function(name, value) {
        if (name === 'src' || name === 'data-src') {
           log('ATTR_' + name.toUpperCase(), value);
        }
        return originalSetAttribute.apply(this, arguments);
      };

      // 8. MutationObserver for dynamic elements
      const observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          mutation.addedNodes.forEach((node) => {
            if (node.tagName === 'VIDEO' || node.tagName === 'SOURCE' || node.tagName === 'IFRAME') {
              if (node.src) log('MUTATION_SRC', node.src);
            }
          });
          if (mutation.type === 'attributes' && (mutation.attributeName === 'src' || mutation.attributeName === 'data-src')) {
            log('MUTATION_ATTR', mutation.target.getAttribute(mutation.attributeName));
          }
        });
      });
      observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true });

      // 8b. Strip iframe sandbox — nested YouTube embeds fail on Android WebView with
      // "Remove sandbox attributes on the iframe tag" when parent pages use restrictive sandbox.
      const relaxIframes = () => {
        document.querySelectorAll('iframe[sandbox]').forEach((el) => {
          try { el.removeAttribute('sandbox'); } catch (e) {}
        });
      };
      relaxIframes();
      const iframeObserver = new MutationObserver(() => relaxIframes());
      iframeObserver.observe(document.documentElement, { childList: true, subtree: true });

      // 9. Hook Media Element Methods
      const originalPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function() {
        if (this.src) log('MEDIA_PLAY', this.src);
        return originalPlay.apply(this, arguments);
      };

      // 10. Auto-interact to trigger playback
      const interact = () => {
        // Click center of screen (Spam click 3 times)
        const centerX = window.innerWidth / 2;
        const centerY = window.innerHeight / 2;
        
        for(let i=0; i<3; i++) {
          const el = document.elementFromPoint(centerX, centerY);
          if (el) {
            el.click();
            el.dispatchEvent(new MouseEvent('click', { view: window, bubbles: true, cancelable: true, clientX: centerX, clientY: centerY }));
          }
        }

        const selectors = [
          '.play-icon-main', '.jw-icon-display', '.jw-display-icon-container', '.jw-icon-playback', 
          '.jw-button-color', '#play-button', '.play-button', '.v-play-button',
          '.vjs-big-play-button', '[class*="play" i]', '[id*="play" i]',
          '.play-icon', '.play_icon', '.play-btn', '.play_btn',
          '.click_to_play', '.overlay', '#player_overlay', 'button', 'a'
        ];
        
        selectors.forEach(selector => {
          document.querySelectorAll(selector).forEach(btn => {
             const rect = btn.getBoundingClientRect();
             if (rect.width > 0 && rect.height > 0) {
                const text = (btn.innerText || btn.textContent || '').toLowerCase();
                const id = (btn.id || '').toLowerCase();
                const cls = (btn.className || '').toString().toLowerCase();
                
                if (text.includes('play') || id.includes('play') || cls.includes('play') || cls.includes('overlay')) {
                   btn.click();
                }
             }
          });
        });

        document.querySelectorAll('video').forEach(v => {
          if (v.paused) v.play().catch(() => v.click());
          if (v.src) log('VIDEO_SRC', v.src);
        });
      };
      
      setTimeout(() => {
        interact();
        setInterval(interact, 800);
      }, 1000);
    })();
    """;
  }

  Future<void> _cleanup() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    
    if (_headlessWebView != null) {
      debugPrint('[StreamExtractor] Disposing Headless WebView...');
      try {
        await _headlessWebView?.dispose();
      } catch (e) {
        debugPrint('[StreamExtractor] Error during disposal: $e');
      }
      _headlessWebView = null;
    }
  }

  Future<void> dispose() async {
    await _cleanup();
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(null);
    }
    
    // Dispose Amri extractor
    await _amriExtractor?.dispose();
    _amriExtractor = null;
  }
}