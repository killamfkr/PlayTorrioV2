// Asian Drama (kisskh.co) per-episode resolver. Single extraction path
// (no multi-server fan-out) that runs `KissKhExtractor` against a hidden
// WebView, then hands the resulting URL + subtitles to `PlayerScreen`.

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/kisskh_extractor.dart';
import '../api/kisskh_service.dart';
import '../utils/app_theme.dart';
import 'player_screen.dart';

class AsianDramaPlayerScreen extends StatefulWidget {
  final KdramaCard drama;
  final KdramaEpisode episode;
  final List<KdramaEpisode> allEpisodes;
  final Duration? startPosition;

  const AsianDramaPlayerScreen({
    super.key,
    required this.drama,
    required this.episode,
    this.allEpisodes = const [],
    this.startPosition,
  });

  @override
  State<AsianDramaPlayerScreen> createState() =>
      _AsianDramaPlayerScreenState();
}

class _AsianDramaPlayerScreenState extends State<AsianDramaPlayerScreen>
    with TickerProviderStateMixin {
  final KissKhService _service = KissKhService();
  final KissKhExtractor _extractor = KissKhExtractor();

  String _phase = 'Fetching streams…';
  String _statusLine = '';
  bool _resolving = true;
  bool _failedAll = false;
  int _subsFound = 0;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _bootstrap();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _extractor.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final stream = await _extractor.resolve(
        dramaId: widget.drama.id,
        dramaTitle: widget.drama.title,
        episodeId: widget.episode.id,
        episodeNumber: widget.episode.number,
        onProgress: (phase, detail) {
          if (!mounted) return;
          setState(() {
            if (phase == 'init') _phase = 'Opening kisskh…';
            if (phase == 'loaded') _phase = 'Waiting for stream key…';
            if (phase == 'done') _phase = 'Stream ready';
            if (phase == 'error') _statusLine = detail;
          });
        },
      );

      if (!mounted) return;
      if (stream == null) {
        setState(() {
          _resolving = false;
          _failedAll = true;
          _phase = 'No stream available';
        });
        return;
      }
      _subsFound = stream.subtitles.length;
      await _launchPlayer(stream);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _failedAll = true;
        _phase = 'Resolver crashed';
        _statusLine = '$e';
      });
    }
  }

  Future<void> _launchPlayer(KissKhStream stream) async {
    final sources = stream.toSources(label: 'kisskh');
    final subs = stream.subtitles;

    await _service.recordWatch(
      drama: widget.drama,
      episodeNumber: widget.episode.number,
      totalEpisodes: widget.allEpisodes.isNotEmpty
          ? widget.allEpisodes.length
          : widget.episode.number.toInt(),
    );

    final title =
        '${widget.drama.title} • EP ${widget.episode.displayNumber}';

    KdramaEpisode? nextFromList;
    if (widget.allEpisodes.isNotEmpty) {
      for (final e in widget.allEpisodes) {
        if (e.number == widget.episode.number + 1) {
          nextFromList = e;
          break;
        }
      }
    }
    final hasNext =
        widget.allEpisodes.isEmpty ? true : nextFromList != null;

    if (!mounted) return;
    final navigator = Navigator.of(context);

    Future<void> goNext() async {
      var ep = nextFromList;
      var list = widget.allEpisodes;
      if (ep == null) {
        try {
          final det = await _service.getDetails(widget.drama.id);
          list = det.episodes;
          for (final e in det.episodes) {
            if (e.number == widget.episode.number + 1) {
              ep = e;
              break;
            }
          }
        } catch (_) {}
      }
      if (ep == null) return;
      await navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => AsianDramaPlayerScreen(
            drama: widget.drama,
            episode: ep!,
            allEpisodes: list,
          ),
        ),
      );
    }

    await navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: sources.first.url,
          title: title,
          headers: sources.first.headers,
          sources: sources,
          activeProvider: 'kisskh',
          startPosition: widget.startPosition,
          externalSubtitles: subs.isNotEmpty ? subs : null,
          onPlaybackProgress: (pos, dur) async {
            await _service.recordWatch(
              drama: widget.drama,
              episodeNumber: widget.episode.number,
              totalEpisodes: widget.allEpisodes.isNotEmpty
                  ? widget.allEpisodes.length
                  : widget.episode.number.toInt(),
              position: pos,
              duration: dur,
            );
          },
          hasCustomNextEpisode: hasNext,
          onCustomNextEpisode: hasNext ? goNext : null,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePreset>(
      valueListenable: AppTheme.themeNotifier,
      builder: (context, theme, _) {
        return Scaffold(
          backgroundColor: theme.bgDark,
          appBar: AppBar(
            backgroundColor: theme.bgDark,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              '${widget.drama.title} • EP ${widget.episode.displayNumber}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_resolving) ...[
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, child) => Transform.scale(
                        scale: 0.92 + (_pulseCtrl.value * 0.18),
                        child: child,
                      ),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              theme.primaryColor.withValues(alpha: 0.45),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ] else if (_failedAll) ...[
                    Icon(Icons.error_outline,
                        color: theme.primaryColor, size: 56),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    _phase,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_statusLine.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _statusLine,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  if (_subsFound > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '$_subsFound subtitle'
                      '${_subsFound > 1 ? 's' : ''} loaded',
                      style: TextStyle(
                        color: theme.primaryColor.withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (_failedAll) ...[
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _resolving = true;
                          _failedAll = false;
                          _phase = 'Fetching streams…';
                          _statusLine = '';
                        });
                        _bootstrap();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Back',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
