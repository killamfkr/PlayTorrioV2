import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/movie.dart';
import '../../models/stream_source.dart';
import '../../services/android_player_launcher.dart';
import 'mobile_player_screen.dart';

/// Android: Media3 ExoPlayer in a [PlatformView]. On fatal error, tries VLC;
/// if VLC is missing or fails, falls back to [MobilePlayerScreen] (media_kit).
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

  bool _fallbackStarted = false;
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
    if (_fallbackStarted || !mounted) return;
    if (event is! Map) return;
    final type = event['type']?.toString();
    if (type != 'error') return;
    final msg = event['message']?.toString() ?? 'Playback error';
    await _onExoFatal(msg);
  }

  Future<void> _onExoFatal(String message) async {
    if (_fallbackStarted || !mounted) return;
    _fallbackStarted = true;
    await _exoSub?.cancel();
    _exoSub = null;

    setState(() => _status = 'ExoPlayer: $message\nTrying VLC…');

    final vlcOk = await AndroidPlayerLauncher.launch(
      url: widget.mediaPath,
      packageName: 'org.videolan.vlc',
      title: widget.title,
      extras: const {'title': true},
    );

    if (!mounted) return;

    if (vlcOk) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _status = 'VLC not available. Opening built-in player…');
    await Future<void>.delayed(const Duration(milliseconds: 400));
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
