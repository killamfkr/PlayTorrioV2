import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/movie.dart';
import '../../models/stream_source.dart';
import '../../services/player_pool_service.dart';

/// Web: minimal player (same as desktop web stub).
class MobilePlayerScreen extends StatefulWidget {
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

  const MobilePlayerScreen({
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
    this.stremioStreamType = 'series',
    this.providers,
  });

  @override
  State<MobilePlayerScreen> createState() => _MobilePlayerScreenState();
}

class _MobilePlayerScreenState extends State<MobilePlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final pool = PlayerPoolService().getPlayer();
    _player = pool.player;
    _videoController = pool.controller;
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.open(
        Media(widget.mediaPath, httpHeaders: widget.headers ?? {}),
      );
      if (widget.startPosition != null) {
        await _player.seek(widget.startPosition!);
      }
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('[WebPlayer] open failed: $e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready)
            Video(
              controller: _videoController,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              fill: Colors.black,
            )
          else
            const Center(child: CircularProgressIndicator()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                if (_ready)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        StreamBuilder<bool>(
                          stream: _player.stream.playing,
                          initialData: _player.state.playing,
                          builder: (_, snap) {
                            final playing = snap.data ?? false;
                            return IconButton(
                              icon: Icon(
                                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                if (playing) {
                                  _player.pause();
                                } else {
                                  _player.play();
                                }
                              },
                            );
                          },
                        ),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: const TextStyle(color: Colors.white70),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
