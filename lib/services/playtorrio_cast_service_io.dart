import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

/// Google Cast (Chromecast) sender — Android + iOS phone/tablet only.
class PlaytorrioCastService {
  PlaytorrioCastService._();
  static final PlaytorrioCastService instance = PlaytorrioCastService._();

  bool _initialized = false;
  bool _initFailed = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_initialized || _initFailed) return;
    try {
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
      await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      _initialized = true;
      debugPrint('[Cast] Google Cast context ready');
    } catch (e, st) {
      _initFailed = true;
      debugPrint('[Cast] init failed: $e\n$st');
    }
  }

  bool get isInitialized => _initialized;

  bool eligibleForCastUi({
    required bool isAndroidTv,
    required String mediaPath,
    String? magnetLink,
  }) {
    if (isAndroidTv) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (!_initialized) return false;
    if (magnetLink != null && magnetLink.isNotEmpty) return false;
    final u = mediaPath.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) return false;
    return true;
  }

  String _guessContentType(Uri uri) {
    final p = uri.path.toLowerCase();
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
    final sw = Stopwatch()..start();
    while (sw.elapsed < const Duration(seconds: 20)) {
      if (GoogleCastSessionManager.instance.connectionState ==
          GoogleCastConnectState.connected) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
    throw StateError('Timed out connecting to the Cast device.');
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
  }) async {
    if (!_initialized) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chromecast is not ready. Restart the app and try again.'),
          ),
        );
      }
      return;
    }

    final uri = Uri.tryParse(streamUrl.trim());
    if (uri == null || !uri.hasScheme) {
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

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1025),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
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
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  ),
                ],
              ),
              if (headers != null && headers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'This stream uses custom headers. Chromecast often cannot play such URLs unless you use a custom receiver.',
                    style: TextStyle(color: Colors.amber.shade200, fontSize: 12),
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
                          onTap: () async {
                            Navigator.pop(ctx);
                            try {
                              final ok = await GoogleCastSessionManager.instance
                                  .startSessionWithDevice(d);
                              if (!ok) {
                                throw StateError('Could not start Cast session.');
                              }
                              await _waitConnected();
                              await GoogleCastRemoteMediaClient.instance.loadMedia(
                                _mediaInfo(
                                  uri: uri,
                                  title: title,
                                  subtitle: subtitle,
                                  poster: posterUri,
                                  live: liveStream,
                                  headers: headers,
                                ),
                                autoPlay: true,
                                playPosition: startPosition,
                              );
                              onCastStarted?.call();
                              if (rootContext.mounted) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  SnackBar(
                                    content: Text('Playing on ${d.friendlyName}'),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (rootContext.mounted) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  SnackBar(content: Text('Cast failed: $e')),
                                );
                              }
                            }
                          },
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
    ).whenComplete(() async {
      try {
        await GoogleCastDiscoveryManager.instance.stopDiscovery();
      } catch (_) {}
    });
  }
}
