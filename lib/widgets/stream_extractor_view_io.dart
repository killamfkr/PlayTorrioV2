import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../api/stream_extractor.dart';
import '../utils/webview_cleanup.dart';

class StreamExtractorView extends StatefulWidget {
  final String url;
  final Function(ExtractedMedia) onMediaExtracted;

  const StreamExtractorView({
    super.key,
    required this.url,
    required this.onMediaExtracted,
  });

  @override
  State<StreamExtractorView> createState() => _StreamExtractorViewState();
}

class _StreamExtractorViewState extends State<StreamExtractorView> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  String? _detectedStreamUrl;
  String? _currentUrl;
  String? _detectedFrameUrl;

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
  }

  @override
  void dispose() {
    // Dispose WebView controller to release file locks
    _webViewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Manual Stream Extraction', style: TextStyle(fontSize: 16)),
            Text(_currentUrl ?? '', style: const TextStyle(fontSize: 10, color: Colors.white70), overflow: TextOverflow.ellipsis),
          ],
        ),
        backgroundColor: const Color(0xFF0F0418),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _detectedStreamUrl = null);
              _webViewController?.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialUserScripts: UnmodifiableListView([
              UserScript(
                source: _getRawSpyJs(),
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: false,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              userAgent: _userAgent,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              useOnLoadResource: true,
              // Real browser-like settings
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
              useShouldOverrideUrlLoading: true,
              javaScriptCanOpenWindowsAutomatically: false, // Block popups
              supportMultipleWindows: false,
              isFraudulentWebsiteWarningEnabled: false,
              safeBrowsingEnabled: false,
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            ),
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url.toString();
              
              // Allow if it's a main frame navigation that looks legitimate
              if (navigationAction.isForMainFrame) {
                 if (url.contains('vixsrc.to') ||
                     url.contains('vidsrc.to') ||
                     url.contains('vidsrc.me') ||
                     url.contains('vidsrc.cc') ||
                     url.contains('vidlink.pro') ||
                     url.contains('vidnest.fun') ||
                     url.contains('anitaro.live') ||
                     url.contains('111movies.com') ||
                     url.contains('google.com')) {
                   return NavigationActionPolicy.ALLOW;
                 }
              }

              // Block obvious ad redirects that try to open new tabs/windows
              if (navigationAction.navigationType == NavigationType.OTHER && !navigationAction.isForMainFrame) {
                 debugPrint('[StreamExtractor] BLOCKED BACKGROUND REDIRECT: $url');
                 return NavigationActionPolicy.CANCEL;
              }

              return NavigationActionPolicy.ALLOW; // Be more permissive for sub-resources
            },
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStart: (controller, url) {
              setState(() {
                _isLoading = true;
                _currentUrl = url.toString();
              });
            },
            onLoadStop: (controller, url) async {
              setState(() => _isLoading = false);
              debugPrint('[StreamExtractor] Page Loaded: $url');
              await controller.evaluateJavascript(source: _getRawSpyJs());
            },
            onLoadResource: (controller, resource) {
              final rUrl = resource.url.toString();
              debugPrint('[StreamExtractor Resource] $rUrl');
              
              if (rUrl.contains('.m3u8') || rUrl.contains('playlist') || rUrl.contains('master') || rUrl.contains('.mpd') || rUrl.contains('manifest') || (rUrl.contains('.mp4') && !rUrl.contains('googlevideo.com'))) {
                 debugPrint('[StreamExtractor] MATCHED RESOURCE: $rUrl');
                 if (_detectedStreamUrl == null) {
                    setState(() {
                      _detectedStreamUrl = rUrl;
                    });
                 }
              }
            },
            onReceivedError: (controller, request, error) {
              debugPrint('[StreamExtractor Error] ${request.url} : ${error.description}');
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              debugPrint('[StreamExtractor HTTP Error] ${request.url} : ${errorResponse.statusCode}');
            },
            onConsoleMessage: (controller, consoleMessage) {
              final msg = consoleMessage.message;
              debugPrint('[WebView Console] $msg');
              
              if (msg.contains('PT_EXTRACT:')) {
                // Clean up the message from potential quotes and prefixes
                String fullMsg = msg.substring(msg.indexOf('PT_EXTRACT:') + 'PT_EXTRACT:'.length).trim();
                String streamUrl = fullMsg;
                String? frameUrl;

                if (fullMsg.contains(' | FRAME: ')) {
                  final parts = fullMsg.split(' | FRAME: ');
                  streamUrl = parts[0];
                  frameUrl = parts[1];
                }

                streamUrl = streamUrl.replaceAll('"', '').replaceAll("'", "").trim();
                
                // Remove prefixes if present
                streamUrl = streamUrl.replaceFirst('[FETCH]', '').replaceFirst('[XHR]', '').replaceFirst('[POSTMESSAGE]', '').replaceFirst('[ATTR_SRC]', '').replaceFirst('[MUTATION_SRC]', '').replaceFirst('[ATTR_DATA-SRC]', '').replaceFirst('[VIDEO_SRC]', '').replaceFirst('[SOURCE_SRC]', '').replaceFirst('[MEDIA_PLAY]', '').replaceFirst('[SRC_PROPERTY]', '').trim();

                if ((streamUrl.contains('.m3u8') || streamUrl.contains('.mp4') || streamUrl.contains('playlist') || streamUrl.contains('master') || streamUrl.contains('.mpd') || streamUrl.contains('manifest')) && !streamUrl.contains('google')) {
                   debugPrint('[StreamExtractor] SPY CAUGHT: $streamUrl');
                   if (_detectedStreamUrl == null) {
                      setState(() {
                        _detectedStreamUrl = streamUrl;
                        _detectedFrameUrl = frameUrl;
                      });
                   }
                }
              }
            },
          ),
          if (_detectedStreamUrl != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () {
                  final uri = Uri.parse(_detectedFrameUrl ?? widget.url);
                  final origin = '${uri.scheme}://${uri.host}';
                  
                  widget.onMediaExtracted(ExtractedMedia(
                    url: _detectedStreamUrl!,
                    headers: {
                      'User-Agent': _userAgent, 
                      'Referer': _detectedFrameUrl ?? widget.url,
                      'Origin': origin,
                      'Accept': '*/*',
                      'Accept-Language': 'en-US,en;q=0.9',
                    },
                  ));
                  
                  // Cleanup WebView2 cache after extraction (async, don't wait)
                  if (Platform.isWindows) {
                    // Dispose WebView first
                    _webViewController?.dispose();
                    _webViewController = null;
                    
                    // Run cleanup in background
                    WebViewCleanup.cleanupWebView2Cache().then((_) {
                      debugPrint('[StreamExtractor] Cleanup completed');
                    });
                  }
                },
                icon: const Icon(Icons.play_circle_fill),
                label: Text('PLAY DETECTED STREAM\n${_detectedStreamUrl!.split('?').first}', 
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
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

      // 1. Hook HTMLMediaElement.src
      try {
        const originalSrcDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
        if (originalSrcDescriptor) {
          Object.defineProperty(HTMLMediaElement.prototype, 'src', {
            set: function(val) {
              log('SRC_PROPERTY', val);
              return originalSrcDescriptor.set.apply(this, arguments);
            },
            get: function() {
              return originalSrcDescriptor.get.apply(this, arguments);
            },
            configurable: true
          });
        }
      } catch(e) { console.log('PT_LOG: Error hooking src: ' + e); }

      // 2. Popup Blocking
      window.open = function() { return null; };
      
      // 3. Sniff Fetch
      const originalFetch = window.fetch;
      window.fetch = async function(...args) {
        const url = args[0] instanceof Request ? args[0].url : args[0];
        log('FETCH', url);
        return originalFetch.apply(this, args);
      };

      // 4. Sniff XHR
      const originalXHROpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        log('XHR', url);
        return originalXHROpen.apply(this, arguments);
      };

      // 5. Sniff MediaSource
      try {
        const originalAddSourceBuffer = window.MediaSource ? window.MediaSource.prototype.addSourceBuffer : null;
        if (originalAddSourceBuffer) {
          window.MediaSource.prototype.addSourceBuffer = function(mime) {
            console.log('PT_LOG: MediaSource addSourceBuffer: ' + mime);
            return originalAddSourceBuffer.apply(this, arguments);
          };
        }
      } catch(e) {}

      // 6. Sniff postMessage
      const originalPostMessage = window.postMessage;
      window.postMessage = function(message, targetOrigin, transfer) {
        if (message) {
           try {
             const str = typeof message === 'string' ? message : JSON.stringify(message);
             log('POSTMESSAGE', str);
           } catch(e) {}
        }
        return originalPostMessage.apply(this, arguments);
      };

      // 7. Sniff URL.createObjectURL
      const originalCreateObjectURL = URL.createObjectURL;
      URL.createObjectURL = function(obj) {
        const url = originalCreateObjectURL.apply(this, arguments);
        log('BLOB_URL', url);
        return url;
      };

      // 8. MutationObserver
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

      // 9. Scan for strings
      const scan = () => {
        const pattern = /https?://[^s"']+(?:.m3u8|.mp4|workers.dev|trueparadise|videasy)/gi;
        const seen = new Set();
        const deepScan = (obj, depth = 0) => {
          if (depth > 2 || !obj || seen.has(obj)) return;
          seen.add(obj);
          for (let key in obj) {
            try {
              const val = obj[key];
              if (typeof val === 'string' && pattern.test(val)) log('SCAN_MATCH', val);
              else if (typeof val === 'object') deepScan(val, depth + 1);
            } catch(e) {}
          }
        };
        deepScan(window.__NEXT_DATA__);
      };

      // 10. Interaction
      const interact = () => {
        // Quality Selection logic
        const selectHighestQuality = () => {
          // 1. JW Player quality selection
          const jwSettings = document.querySelector('.jw-icon-settings, .jw-settings-content');
          if (jwSettings) {
            const qualityItems = Array.from(document.querySelectorAll('.jw-settings-content-item, .jw-reset-ul li'));
            if (qualityItems.length > 0) {
              const qualities = qualityItems.map(item => ({
                item,
                label: item.innerText.toLowerCase()
              })).filter(q => /^\\d+p|4k|hd/i.test(q.label));
              
              if (qualities.length > 0) {
                // Sort qualities: 4k/2160 > 1080 > 720 > etc.
                qualities.sort((a, b) => {
                  const getVal = (s) => {
                    if (s.includes('4k') || s.includes('2160')) return 2160;
                    const m = s.match(/(\\d+)p/);
                    return m ? parseInt(m[1]) : 0;
                  };
                  return getVal(b.label) - getVal(a.label);
                });
                
                const highest = qualities[0];
                if (!highest.item.classList.contains('jw-settings-item-active') && 
                    !highest.item.classList.contains('active')) {
                  console.log('PT_LOG: Selecting highest quality: ' + highest.label);
                  highest.item.click();
                }
              }
            }
          }

          // 2. Generic quality buttons/items (often used in sites like Anitaro)
          const qualityButtons = Array.from(document.querySelectorAll('button, li, .quality-item, [class*="quality"]'));
          const qualityOptions = qualityButtons.filter(b => {
            const txt = b.innerText.trim().toLowerCase();
            return /^(4k|2160p|1080p|720p|480p|360p)\$/i.test(txt);
          });

          if (qualityOptions.length > 0) {
            qualityOptions.sort((a, b) => {
              const getVal = (el) => {
                const s = el.innerText.toLowerCase();
                if (s.includes('4k') || s.includes('2160')) return 2160;
                const m = s.match(/(\\d+)p/);
                return m ? parseInt(m[1]) : 0;
              };
              return getVal(b) - getVal(a);
            });

            const highest = qualityOptions[0];
            const isSelected = highest.classList.contains('active') || 
                              highest.classList.contains('selected') ||
                              highest.getAttribute('aria-checked') === 'true';
            
            if (!isSelected) {
              console.log('PT_LOG: Generic quality selection: ' + highest.innerText);
              highest.click();
            }
          }
        };

        const selectors = ['.play-icon-main', '.jw-display-icon-container', '.vjs-big-play-button', '[class*="play" i]', 'button'];
        selectors.forEach(s => document.querySelectorAll(s).forEach(b => {
          if (b.getBoundingClientRect().width > 0) b.click();
        }));
        
        selectHighestQuality();

        document.querySelectorAll('video').forEach(v => {
          if (v.paused) v.play().catch(() => {});
          if (v.src) log('VIDEO_SRC', v.src);
        });
        scan();
      };
      
      setTimeout(() => { interact(); setInterval(interact, 2000); }, 1000);
    })();
    """;
  }
}
