import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/local_server_service.dart';
import 'cast_hw_transcode_android.dart';

/// Google Cast (Chromecast) sender — Android + iOS (including Android TV).
class PlaytorrioCastService {
  PlaytorrioCastService._();
  static final PlaytorrioCastService instance = PlaytorrioCastService._();

  bool _initialized = false;

  String? _lastCastInitializationError;

  /// Last Cast init failure (Platform channel / Dart); exposed for diagnostics UI.
  String? get lastCastInitializationError => _lastCastInitializationError;

  Future<void>? _initFuture;

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_initialized) return;
    final fut = _initFuture ??= _initializeOnce();
    await fut;
  }

  Future<void> _initializeOnce() async {
    try {
      if (Platform.isAndroid) {
        await _ensureAndroidNearbyWifiPermission();
      }
      const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
      final GoogleCastOptions options = Platform.isIOS
          ? IOSGoogleCastOptions(
              GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
              stopCastingOnAppTerminated: false,
            )
          : GoogleCastOptionsAndroid(
              appId: appId,
              stopCastingOnAppTerminated: false,
            );
      final ok =
          await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      if (ok != true) {
        throw StateError(
          'Google Cast initialization returned false (native channel declined).',
        );
      }
      _initialized = true;
      _lastCastInitializationError = null;
      debugPrint('[Cast] Google Cast context ready');
    } catch (e, st) {
      _initialized = false;
      _lastCastInitializationError = e is PlatformException
          ? '${e.code}: ${e.message}'
          : '$e';
      debugPrint('[Cast] init failed: $e\n$st');
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _ensureAndroidNearbyWifiPermission() async {
    try {
      final perm = Permission.nearbyWifiDevices;
      final status = await perm.status;
      if (!status.isGranted) {
        await perm.request();
      }
    } catch (e) {
      debugPrint('[Cast] nearbyWifiDevices permission: $e');
    }
  }

  /// Call before opening the Cast sheet if startup initialization failed once.
  Future<void> retryInitialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_initialized) return;
    await initialize();
  }

  bool get isInitialized => _initialized;

  /// True while a Cast session is connected (receiver playing or ready).
  ///
  /// Waits for [initialize] on first listen — important because the player UI
  /// often mounts before app-startup Cast init finishes; returning a completed
  /// `Stream.value(false)` would never emit session updates afterward.
  Stream<bool> get isCastingActiveStream => _isCastingActiveStreamImpl();

  Stream<bool> _isCastingActiveStreamImpl() async* {
    if (!Platform.isAndroid && !Platform.isIOS) {
      yield false;
      return;
    }
    await initialize();
    if (!_initialized) {
      yield false;
      return;
    }
    yield* GoogleCastSessionManager.instance.currentSessionStream.map(
      (s) =>
          s != null &&
          s.connectionState == GoogleCastConnectState.connected,
    );
  }

  bool get isCastingActiveNow {
    if (!_initialized) return false;
    return GoogleCastSessionManager.instance.hasConnectedSession;
  }

  String? get connectedCastDeviceName {
    if (!_initialized) return null;
    return GoogleCastSessionManager.instance.currentSession?.device?.friendlyName;
  }

  Future<void> stopCasting() async {
    try {
      if (_initialized) {
        await GoogleCastSessionManager.instance.endSessionAndStopCasting();
      }
    } catch (e, st) {
      debugPrint('[Cast] stopCasting: $e\n$st');
    }
    await CastHwTranscodeCoordinator.instance.disposeActive();
  }

  /// Rough hint for UI: Cast receiver appears to be playing or trying to play.
  Stream<bool> get castRemoteIsPlayingStream =>
      _castRemoteIsPlayingStreamImpl();

  Stream<bool> _castRemoteIsPlayingStreamImpl() async* {
    if (!Platform.isAndroid && !Platform.isIOS) {
      yield false;
      return;
    }
    await initialize();
    if (!_initialized) {
      yield false;
      return;
    }
    yield* GoogleCastRemoteMediaClient.instance.mediaStatusStream.map((s) {
      final ps = s?.playerState;
      return ps == CastMediaPlayerState.playing ||
          ps == CastMediaPlayerState.buffering ||
          ps == CastMediaPlayerState.loading;
    });
  }

  Future<void> remotePlay() async {
    if (!_initialized || !isCastingActiveNow) return;
    try {
      await GoogleCastRemoteMediaClient.instance.play();
    } catch (e, st) {
      debugPrint('[Cast] remotePlay: $e\n$st');
    }
  }

  Future<void> remotePause() async {
    if (!_initialized || !isCastingActiveNow) return;
    try {
      await GoogleCastRemoteMediaClient.instance.pause();
    } catch (e, st) {
      debugPrint('[Cast] remotePause: $e\n$st');
    }
  }

  Future<void> remoteSeekRelative(Duration delta) async {
    if (!_initialized || !isCastingActiveNow) return;
    try {
      await GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(
          position: delta,
          relative: true,
        ),
      );
    } catch (e, st) {
      debugPrint('[Cast] remoteSeekRelative: $e\n$st');
    }
  }

  /// Jump to live edge for Cast live / event streams (when supported by the receiver).
  Future<void> remoteSeekLiveEdge() async {
    if (!_initialized || !isCastingActiveNow) return;
    try {
      await GoogleCastRemoteMediaClient.instance.seek(
        GoogleCastMediaSeekOption(
          position: Duration.zero,
          seekToInfinity: true,
        ),
      );
    } catch (e, st) {
      debugPrint('[Cast] remoteSeekLiveEdge: $e\n$st');
    }
  }

  /// Whether to show Cast controls for this playback. Does not require [_initialized]
  /// so a failed/timed-out SDK init still shows the icon (tap explains / retries).
  bool eligibleForCastUi({
    required String mediaPath,
    String? magnetLink,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (magnetLink != null && magnetLink.isNotEmpty) return false;
    final u = mediaPath.trim().toLowerCase();
    if (!u.startsWith('http://') && !u.startsWith('https://')) return false;
    return true;
  }

  String _guessContentType(Uri uri) {
    final p = uri.path.toLowerCase();
    // Phone-local proxy: Cast uses [contentType] before loading; the path is always /hls-proxy.
    if (p.contains('hls-proxy')) {
      final nested = uri.queryParameters['url'];
      if (nested != null && nested.isNotEmpty) {
        try {
          final d = Uri.decodeComponent(nested).toLowerCase();
          if (d.contains('.m3u8') ||
              d.contains('m3u8') ||
              d.contains('/playlist') ||
              d.contains('master.m3u')) {
            return 'application/vnd.apple.mpegurl';
          }
          if (d.endsWith('.ts') ||
              d.contains('.ts?') ||
              d.contains('/live/')) {
            return 'video/mp2t';
          }
        } catch (_) {}
      }
      return 'application/vnd.apple.mpegurl';
    }
    if (p.contains('.m3u8')) return 'application/vnd.apple.mpegurl';
    if (p.contains('.mpd')) return 'application/dash+xml';
    if (p.endsWith('.mp4')) return 'video/mp4';
    if (p.endsWith('.webm')) return 'video/webm';
    if (p.endsWith('.mkv')) return 'video/x-matroska';
    return 'video/mp4';
  }

  GoogleCastMediaInformation _mediaInfo({
    required Uri uri,
    required String title,
    String? subtitle,
    Uri? poster,
    required bool live,
    Map<String, String>? headers,
  }) {
    final meta = GoogleCastMovieMediaMetadata(
      title: title,
      subtitle: subtitle,
      images: poster != null
          ? [
              GoogleCastImage(url: poster, height: 720, width: 480),
            ]
          : null,
    );
    return GoogleCastMediaInformation(
      contentId: uri.toString(),
      streamType: live ? CastMediaStreamType.live : CastMediaStreamType.buffered,
      contentType: _guessContentType(uri),
      contentUrl: uri,
      metadata: meta,
      customData: (headers != null && headers.isNotEmpty)
          ? <String, dynamic>{'requestHeaders': headers}
          : null,
    );
  }

  Future<void> _waitConnected() async {
    // Give the native session a moment to transition out of "idle".
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final sm = GoogleCastSessionManager.instance;
      if (sm.hasConnectedSession) return;
      if (sm.connectionState == GoogleCastConnectState.connected) return;
      final sess = sm.currentSession;
      if (sess != null &&
          sess.connectionState == GoogleCastConnectState.connected) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final sm = GoogleCastSessionManager.instance;
    debugPrint(
      '[Cast] waitConnected timeout: mgr=${sm.connectionState} '
      'hasSession=${sm.hasConnectedSession} sess=${sm.currentSession?.connectionState}',
    );
    throw StateError('Timed out connecting to the Cast device.');
  }

  /// Default Chromecast CAF does not honor [customData.requestHeaders]. When the
  /// upstream CDN needs Referer / Cookie / etc., route through [LocalServerService]
  /// `hls-proxy` first so the phone applies headers (same pattern as Stremio IPTV).
  bool _needsHeaderEmbeddingProxy(String streamUrl, Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return false;
    final u = streamUrl.trim().toLowerCase();
    if (!u.startsWith('http://') && !u.startsWith('https://')) return false;
    if (u.contains('/hls-proxy')) return false;
    return true;
  }

  Future<({String url, Map<String, String>? receiverHeaders})>
      _resolveCastUrlForPlayback({
    required String streamUrl,
    Map<String, String>? headers,
    required bool preferAndroidHwTranscode,
  }) async {
    await LocalServerService().start();
    var castUrl = streamUrl.trim();
    Map<String, String>? receiverHeaders = headers;

    if (_needsHeaderEmbeddingProxy(castUrl, receiverHeaders)) {
      castUrl =
          LocalServerService().getHlsProxyUrl(castUrl, receiverHeaders!);
      receiverHeaders = null;
    }

    if (preferAndroidHwTranscode && Platform.isAndroid) {
      final hw = await androidHwTranscodeCastUrlIfEnabled(
        inputUrl: castUrl,
        headers: receiverHeaders,
        enabled: true,
      );
      if (hw != null && hw.isNotEmpty) {
        return (url: hw, receiverHeaders: null);
      }
    }

    var outUrl = castUrl;
    final lanUrl = await LocalServerService().urlWithLanHostForCast(outUrl);
    if (lanUrl != null && lanUrl.isNotEmpty) {
      outUrl = lanUrl;
    }
    return (url: outUrl, receiverHeaders: receiverHeaders);
  }

  Future<void> openCastSheet({
    required BuildContext context,
    required String streamUrl,
    required String title,
    String? subtitle,
    String? posterUrl,
    required bool liveStream,
    Duration startPosition = Duration.zero,
    Map<String, String>? headers,
    VoidCallback? onCastStarted,
    bool preferAndroidHwTranscode = false,
  }) async {
    if (!_initialized) {
      for (var attempt = 0; attempt < 6 && !_initialized; attempt++) {
        await retryInitialize();
        if (!_initialized && attempt < 5) {
          await Future.delayed(const Duration(milliseconds: 450));
        }
      }
    }
    if (!_initialized) {
      if (context.mounted) {
        final detail = lastCastInitializationError;
        final tail = (detail != null && detail.isNotEmpty)
            ? '\n\n$detail'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Platform.isAndroid
                  ? 'Chromecast failed to start. Install a build with Cast ProGuard rules, '
                      'accept Nearby devices/Wi‑Fi if prompted, and ensure Google Play services are available.'
                      '$tail'
                  : 'Chromecast failed to start. Settings → PlayTorrio → enable Local Network, '
                      'then try again.'
                      '$tail',
            ),
          ),
        );
      }
      return;
    }

    final streamTrim = streamUrl.trim();
    if (Uri.tryParse(streamTrim)?.hasScheme != true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid stream URL for casting.')),
        );
      }
      return;
    }

    Uri? posterUri;
    if (posterUrl != null && posterUrl.isNotEmpty) {
      posterUri = Uri.tryParse(posterUrl);
    }

    await GoogleCastDiscoveryManager.instance.startDiscovery();

    if (!context.mounted) return;

    final rootContext = context;

    Future<({String url, Map<String, String>? receiverHeaders})>?
        resolvedCastFuture;
    Future<({String url, Map<String, String>? receiverHeaders})>
        ensureResolvedCastUrl() async {
      resolvedCastFuture ??= _resolveCastUrlForPlayback(
        streamUrl: streamTrim,
        headers: headers,
        preferAndroidHwTranscode: preferAndroidHwTranscode,
      );
      return resolvedCastFuture!;
    }

    final picked = await showModalBottomSheet<GoogleCastDevice?>(
      context: context,
      backgroundColor: const Color(0xFF1A1025),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final willEmbedHeaders =
            _needsHeaderEmbeddingProxy(streamTrim, headers);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cast_rounded, color: Colors.white70),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cast to TV',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  ),
                ],
              ),
              if (preferAndroidHwTranscode && Platform.isAndroid)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Hardware transcoding on this phone is enabled for Chromecast. '
                    'The first TV you pick may take a few seconds while HLS segments are generated.',
                    style: TextStyle(
                      color: Colors.cyanAccent.withValues(alpha: 0.82),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              if (headers != null && headers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    willEmbedHeaders
                        ? 'Referer and other headers are applied on your phone, then Chromecast loads the stream from this device (default receiver works).'
                        : 'This stream uses custom headers. Chromecast often cannot play such URLs unless you use a custom receiver.',
                    style: TextStyle(
                      color: willEmbedHeaders
                          ? Colors.cyanAccent.withValues(alpha: 0.85)
                          : Colors.amber.shade200,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.42,
                child: StreamBuilder<List<GoogleCastDevice>>(
                  stream: GoogleCastDiscoveryManager.instance.devicesStream,
                  initialData: GoogleCastDiscoveryManager.instance.devices,
                  builder: (_, snap) {
                    final devices = snap.data ?? const <GoogleCastDevice>[];
                    if (devices.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(strokeWidth: 2),
                              SizedBox(height: 12),
                              Text(
                                'Looking for Chromecast devices…',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      itemBuilder: (_, i) {
                        final d = devices[i];
                        return ListTile(
                          leading: const Icon(Icons.cast_rounded, color: Colors.white70),
                          title: Text(d.friendlyName,
                              style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            d.modelName ?? '',
                            style: const TextStyle(color: Colors.white38),
                          ),
                          onTap: () => Navigator.pop(ctx, d),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      await GoogleCastDiscoveryManager.instance.stopDiscovery();
    } catch (_) {}

    if (!rootContext.mounted) return;
    if (picked == null) return;

    try {
      final resolved = await ensureResolvedCastUrl();
      final castUri = Uri.tryParse(resolved.url.trim());
      if (castUri == null || !castUri.hasScheme) {
        throw StateError('Invalid resolved cast URL.');
      }
      final castBuffered = resolved.url.contains('/cast-hw/');
      final effectiveLive = liveStream && !castBuffered;
      final ok = await GoogleCastSessionManager.instance
          .startSessionWithDevice(picked);
      if (!ok) {
        throw StateError('Could not start Cast session.');
      }
      await _waitConnected();
      await GoogleCastRemoteMediaClient.instance.loadMedia(
        _mediaInfo(
          uri: castUri,
          title: title,
          subtitle: subtitle,
          poster: posterUri,
          live: effectiveLive,
          headers: resolved.receiverHeaders,
        ),
        autoPlay: true,
        playPosition:
            effectiveLive ? Duration.zero : startPosition,
      );
      onCastStarted?.call();
      if (rootContext.mounted) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          SnackBar(
            content: Text('Playing on ${picked.friendlyName}'),
          ),
        );
      }
    } catch (e) {
      await CastHwTranscodeCoordinator.instance.disposeActive();
      if (rootContext.mounted) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          SnackBar(content: Text('Cast failed: $e')),
        );
      }
    }
  }
}
