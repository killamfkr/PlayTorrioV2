import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import '../../models/movie.dart';
import '../../models/stream_source.dart';
import 'mobile_player_screen.dart';

VlcPlayerOptions? _vlcOptionsFromHeaders(Map<String, String>? headers) {
  if (headers == null || headers.isEmpty) return null;
  final list = <String>[];
  final referer = headers['Referer'] ?? headers['referer'];
  final ua = headers['User-Agent'] ?? headers['user-agent'];
  if (referer != null && referer.isNotEmpty) {
    list.add(VlcHttpOptions.httpReferrer(referer));
  }
  if (ua != null && ua.isNotEmpty) {
    list.add(VlcHttpOptions.httpUserAgent(ua));
  }
  if (list.isEmpty) return null;
  return VlcPlayerOptions(http: VlcHttpOptions(list));
}

/// Android: Media3 ExoPlayer in a [PlatformView]. On fatal error, embedded
/// **libVLC** via [flutter_vlc_player]; if that errors, [MobilePlayerScreen].
class NativeExoPlayerScreen extends StatefulWidget {
  static const String playerSettingsName = 'Native ExoPlayer (TV)';

  final String mediaPath;
  final String title;
  final String? audioUrl;
  final Map<String, String>? headers;
  final Movie? movie;
  final int? selectedSeason;
  final int? selectedEpisode;
  final String? magnetLink;
  final String? activeProvider;
  final Duration? startPosition;
  final List<StreamSource>? sources;
  final int? fileIndex;
  final List<Map<String, dynamic>>? externalSubtitles;
  final String? stremioId;
  final String? stremioAddonBaseUrl;
  final String stremioStreamType;
  final Map<String, dynamic>? providers;

  const NativeExoPlayerScreen({
    super.key,
    required this.mediaPath,
    required this.title,
    this.audioUrl,
    this.headers,
    this.movie,
    this.selectedSeason,
    this.selectedEpisode,
    this.magnetLink,
    this.activeProvider,
    this.startPosition,
    this.sources,
    this.fileIndex,
    this.externalSubtitles,
    this.stremioId,
    this.stremioAddonBaseUrl,
    required this.stremioStreamType,
    this.providers,
  });

  @override
  State<NativeExoPlayerScreen> createState() => _NativeExoPlayerScreenState();
}

class _NativeExoPlayerScreenState extends State<NativeExoPlayerScreen> {
  static int _nextEventSuffix = 1;

  late final int _eventSuffix;
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _exoSub;

  bool _exoFallbackStarted = false;
  bool _libVlcActive = false;
  bool _mediaKitFallback = false;
  VlcPlayerController? _vlcController;
  String? _status;

  @override
  void initState() {
    super.initState();
    _eventSuffix = _nextEventSuffix++;
    _eventChannel = EventChannel(
      'com.example.play_torrio_native/exo_player_events_$_eventSuffix',
    );
    _exoSub = _eventChannel!.receiveBroadcastStream().listen(
      _onExoEvent,
      onError: (_) => _onExoFatal('Stream error'),
    );
  }

  Future<void> _onExoEvent(dynamic event) async {
    if (_exoFallbackStarted || !mounted) return;
    if (event is! Map) return;
    final type = event['type']?.toString();
    if (type != 'error') return;
    final msg = event['message']?.toString() ?? 'Playback error';
    await _onExoFatal(msg);
  }

  Future<void> _onExoFatal(String message) async {
    if (_exoFallbackStarted || !mounted) return;
    _exoFallbackStarted = true;
    await _exoSub?.cancel();
    _exoSub = null;

    setState(() => _status = 'ExoPlayer: $message\nLoading libVLC…');

    try {
      final opts = _vlcOptionsFromHeaders(widget.headers);
      final c = VlcPlayerController.network(
        widget.mediaPath,
        hwAcc: HwAcc.decoding,
        autoInitialize: false,
        autoPlay: false,
        options: opts,
      );
      await c.initialize();
      if (widget.startPosition != null &&
          widget.startPosition!.inMilliseconds > 0) {
        await c.seekTo(widget.startPosition!);
      }
      c.addListener(_onVlcControllerUpdate);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _vlcController = c;
        _libVlcActive = true;
        _status = null;
      });
    } catch (e) {
      if (mounted) {
        await _openMediaKitFallback('libVLC failed: $e');
      }
    }
  }

  void _onVlcControllerUpdate() {
    if (_mediaKitFallback || !mounted) return;
    final c = _vlcController;
    if (c == null) return;
    if (c.value.hasError) {
      final err = c.value.errorDescription;
      c.removeListener(_onVlcControllerUpdate);
      _openMediaKitFallback(err.isEmpty ? 'libVLC error' : err);
    }
  }

  Future<void> _openMediaKitFallback(String reason) async {
    if (_mediaKitFallback || !mounted) return;
    _mediaKitFallback = true;

    setState(() => _status = '$reason\nOpening built-in player…');

    try {
      await _vlcController?.dispose();
    } catch (_) {}
    _vlcController = null;

    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => MobilePlayerScreen(
          mediaPath: widget.mediaPath,
          title: widget.title,
          audioUrl: widget.audioUrl,
          headers: widget.headers,
          movie: widget.movie,
          selectedSeason: widget.selectedSeason,
          selectedEpisode: widget.selectedEpisode,
          magnetLink: widget.magnetLink,
          activeProvider: widget.activeProvider,
          startPosition: widget.startPosition,
          sources: widget.sources,
          fileIndex: widget.fileIndex,
          externalSubtitles: widget.externalSubtitles,
          stremioId: widget.stremioId,
          stremioAddonBaseUrl: widget.stremioAddonBaseUrl,
          stremioStreamType: widget.stremioStreamType,
          providers: widget.providers,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _exoSub?.cancel();
    _vlcController?.removeListener(_onVlcControllerUpdate);
    _vlcController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return MobilePlayerScreen(
        mediaPath: widget.mediaPath,
        title: widget.title,
        audioUrl: widget.audioUrl,
        headers: widget.headers,
        movie: widget.movie,
        selectedSeason: widget.selectedSeason,
        selectedEpisode: widget.selectedEpisode,
        magnetLink: widget.magnetLink,
        activeProvider: widget.activeProvider,
        startPosition: widget.startPosition,
        sources: widget.sources,
        fileIndex: widget.fileIndex,
        externalSubtitles: widget.externalSubtitles,
        stremioId: widget.stremioId,
        stremioAddonBaseUrl: widget.stremioAddonBaseUrl,
        stremioStreamType: widget.stremioStreamType,
        providers: widget.providers,
      );
    }

    if (_libVlcActive && _vlcController != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: VlcPlayer(
                controller: _vlcController!,
                aspectRatio: 16 / 9,
                virtualDisplay: false,
                placeholder: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final creationParams = <String, dynamic>{
      'uri': widget.mediaPath,
      'positionMs': widget.startPosition?.inMilliseconds ?? 0,
      'eventChannelSuffix': _eventSuffix,
      if (widget.headers != null && widget.headers!.isNotEmpty)
        'headers': widget.headers,
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AndroidView(
            viewType: 'playtorrio_native_exo_player',
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          if (_status != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Material(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _status!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
