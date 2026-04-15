import 'package:flutter/material.dart';
import '../api/anime_service.dart';
import '../api/animerealms_extractor.dart';
import '../models/stream_source.dart';
import '../utils/app_theme.dart';
import 'player_screen.dart';

class AnimePlayerScreen extends StatefulWidget {
  final String episodeId;
  final String provider;
  final String category;
  final int anilistId;
  final String title;
  final String? episodeTitle;
  final AnimeCard? animeCard;
  final int? episodeNumber;
  final bool useAnimeRealms;
  final Duration? startPosition;

  const AnimePlayerScreen({
    super.key,
    required this.episodeId,
    required this.provider,
    required this.category,
    required this.anilistId,
    required this.title,
    this.episodeTitle,
    this.animeCard,
    this.episodeNumber,
    this.useAnimeRealms = false,
    this.startPosition,
  });

  @override
  State<AnimePlayerScreen> createState() => _AnimePlayerScreenState();
}

class _AnimePlayerScreenState extends State<AnimePlayerScreen> {
  final AnimeService _service = AnimeService();
  bool _loading = true;
  String _status = 'Loading streams...';

  @override
  void initState() {
    super.initState();
    _loadAndPlay();
  }

  Future<void> _loadAndPlay() async {
    // If coming from AnimeRealms mode, skip miruro entirely
    if (widget.useAnimeRealms) {
      await _tryAnimeRealms();
      return;
    }

    setState(() {
      _loading = true;
      _status = 'Fetching stream from ${widget.provider}...';
    });

    try {
      final sources = await _service.getSources(
        episodeId: widget.episodeId,
        provider: widget.provider,
        category: widget.category,
        anilistId: widget.anilistId,
      );

      if (!mounted) return;

      // Find the best HLS stream
      final hlsStreams = sources.streams.where((s) => s.type == 'hls').toList();
      if (hlsStreams.isEmpty) {
        // Miruro returned no playable streams, try AnimeRealms fallback
        await _tryAnimeRealms();
        return;
      }

      _navigateToPlayer(hlsStreams, sources.subtitles);
    } catch (e) {
      debugPrint('[AnimePlayer] Miruro failed: $e, trying AnimeRealms...');
      if (!mounted) return;
      // Miruro failed entirely, try AnimeRealms
      await _tryAnimeRealms();
    }
  }

  Future<void> _tryAnimeRealms() async {
    if (!mounted) return;
    final epNum = widget.episodeNumber;
    if (epNum == null) {
      setState(() {
        _loading = false;
        _status = 'No playable streams found';
      });
      return;
    }

    setState(() {
      _loading = true;
      _status = 'Fetching from ${widget.provider}...';
    });

    try {
      final extractor = AnimeRealmsExtractor();

      // Try the selected provider first for speed
      final data = await extractor.getStreams(
        provider: widget.provider,
        anilistId: widget.anilistId,
        episodeNumber: epNum,
      );

      if (!mounted) return;

      final streams = (data['streams'] as List?) ?? [];
      final real = streams.where((s) =>
          s['url'] != null &&
          !(s['url'] as String).contains('test-streams.mux.dev')).toList();

      if (real.isNotEmpty) {
        _playAnimeRealmsStreams(real, data['subtitles'] as List? ?? [], widget.provider);
        return;
      }

      // Selected provider had no streams — try all others
      setState(() => _status = 'Trying other providers...');

      final allSources = await extractor.getAllSources(
        anilistId: widget.anilistId,
        episodeNumber: epNum,
      );

      if (!mounted) return;

      if (allSources.isEmpty) {
        setState(() {
          _loading = false;
          _status = 'No playable streams found';
        });
        return;
      }

      // Use first provider that worked
      final best = allSources.first;
      _playAnimeRealmsStreams(
        best['streams'] as List,
        best['subtitles'] as List? ?? [],
        best['provider'] as String,
      );
    } catch (e) {
      debugPrint('[AnimePlayer] AnimeRealms failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _status = 'Failed to load streams';
        });
      }
    }
  }

  void _playAnimeRealmsStreams(List streams, List rawSubs, String provName) {
    final animeStreams = streams.map((s) {
      final url = s['url'] as String? ?? '';
      final quality = s['quality'] as String? ?? 'Default';
      final hdrs = s['headers'] as Map<String, dynamic>?;
      final referer = hdrs?['Referer'] as String?;
      final isHls = url.contains('.m3u8');
      return AnimeStream(
        url: url,
        type: isHls ? 'hls' : 'mp4',
        quality: '$quality ($provName)',
        referer: referer,
      );
    }).toList();

    final subtitles = rawSubs.map((s) => AnimeSubtitle(
      url: s['url'] ?? s['file'] ?? '',
      label: s['label'] ?? 'Unknown',
      language: s['language'] ?? '',
    )).toList();

    _navigateToPlayer(animeStreams, subtitles, source: 'animerealms');
  }

  void _navigateToPlayer(
    List<AnimeStream> streams,
    List<AnimeSubtitle> subtitles, {
    String source = 'miruro',
  }) {
    // Prefer HLS, then mp4
    final hlsStreams = streams.where((s) => s.type == 'hls').toList();
    final mp4Streams = streams.where((s) => s.type == 'mp4').toList();
    final playable = hlsStreams.isNotEmpty ? hlsStreams : mp4Streams;

    if (playable.isEmpty) {
      setState(() {
        _loading = false;
        _status = 'No playable streams found';
      });
      return;
    }

    final best = playable.firstWhere((s) => s.isDefault, orElse: () => playable.first);

    final streamSources = playable.map((s) {
      final h = <String, String>{};
      if (s.referer != null && s.referer!.isNotEmpty) {
        h['Referer'] = s.referer!;
      }
      return StreamSource(
        url: s.url,
        title: s.quality ?? s.server ?? 'Default',
        type: s.type,
        headers: h.isNotEmpty ? h : null,
      );
    }).toList();

    final externalSubs = subtitles.map((s) => <String, dynamic>{
      'url': s.url,
      'title': s.label,
      'language': s.language,
    }).toList();

    // Use best stream's referer as the global default header
    final headers = <String, String>{};
    if (best.referer != null && best.referer!.isNotEmpty) {
      headers['Referer'] = best.referer!;
    }

    // Save watch history
    if (widget.animeCard != null && widget.episodeNumber != null) {
      _service.addToWatchHistory(
        anime: widget.animeCard!,
        episodeNumber: widget.episodeNumber!,
        episodeTitle: widget.episodeTitle ?? '',
        provider: widget.provider,
        category: widget.category,
        episodeId: widget.episodeId,
        useAnimeRealms: source == 'animerealms' || widget.useAnimeRealms,
      );
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: best.url,
          title: widget.title,
          headers: headers.isNotEmpty ? headers : null,
          sources: streamSources,
          activeProvider: 'anime_${source}_${widget.provider}',
          externalSubtitles: externalSubs.isNotEmpty ? externalSubs : null,
          startPosition: widget.startPosition,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: _loading ? _buildLoading() : _buildFailed(),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: Color(0xFFFF6B9D)),
        const SizedBox(height: 20),
        Text(
          _status,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildFailed() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => _loadAndPlay(),
            child: const Text(
              'Retry',
              style: TextStyle(color: Color(0xFFFF6B9D)),
            ),
          ),
        ],
      ),
    );
  }
}
