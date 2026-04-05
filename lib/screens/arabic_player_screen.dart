import 'package:flutter/material.dart';
import '../api/arabic_service.dart';
import '../models/stream_source.dart';
import '../utils/app_theme.dart';
import 'player_screen.dart';

class ArabicPlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;
  final String source; // 'larozaa' or 'dimatoon'

  const ArabicPlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
    this.source = 'larozaa',
  });

  @override
  State<ArabicPlayerScreen> createState() => _ArabicPlayerScreenState();
}

class _ArabicPlayerScreenState extends State<ArabicPlayerScreen> {
  final ArabicService _service = ArabicService();
  bool _loading = true;
  String _status = 'جاري تحميل السيرفرات...';

  @override
  void initState() {
    super.initState();
    _loadAndPlay();
  }

  Future<void> _loadAndPlay() async {
    setState(() {
      _loading = true;
      _status = 'جاري تحميل السيرفرات...';
    });

    // DimaToon: direct MP4 from episode page
    if (widget.source == 'dimatoon') {
      final mp4Url = await _service.getDimaToonVideoUrl(widget.videoId);
      if (mp4Url != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              streamUrl: mp4Url,
              title: widget.title,
              activeProvider: 'arabic',
            ),
          ),
        );
        return;
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _status = 'فشل استخراج الرابط';
        });
      }
      return;
    }

    final servers = await _service.getServers(widget.videoId);
    if (!mounted) return;

    if (servers.isEmpty) {
      setState(() {
        _loading = false;
        _status = 'لا توجد سيرفرات';
      });
      return;
    }

    // Prioritize reliable servers (vidmoly) to the front
    const priorityHosts = ['vidmoly'];
    servers.sort((a, b) {
      final aPri = priorityHosts.any((h) => a.embedUrl.contains(h)) ? 0 : 1;
      final bPri = priorityHosts.any((h) => b.embedUrl.contains(h)) ? 0 : 1;
      return aPri.compareTo(bPri);
    });

    // Try each server until one works
    for (int i = 0; i < servers.length; i++) {
      if (!mounted) return;
      final server = servers[i];
      setState(() {
        _status = 'جاري استخراج الرابط من ${server.name}... (${i + 1}/${servers.length})';
      });

      final result = await ArabicService.extractStreamUrl(server.embedUrl);
      if (result != null && mounted) {
        debugPrint('[ArabicPlayer] Extract OK from ${server.name}');

        // Build sources list: all servers as switchable options (embed URLs)
        final sources = servers.map((s) => StreamSource(
          url: s.embedUrl,
          title: s.name,
          type: 'arabic_embed',
        )).toList();

        // Replace the working server's URL with the actual stream URL
        sources[i] = StreamSource(
          url: result.url,
          title: server.name,
          type: result.url.contains('.m3u8') ? 'hls' : result.url.contains('.mpd') ? 'dash' : 'mp4',
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              streamUrl: result.url,
              audioUrl: result.audioUrl,
              title: widget.title,
              headers: result.headers,
              sources: sources,
              activeProvider: 'arabic',
            ),
          ),
        );
        return;
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _status = 'فشل استخراج الرابط من جميع السيرفرات';
      });
    }
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
          textDirection: TextDirection.rtl,
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
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: AppTheme.primaryColor),
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
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => _loadAndPlay(),
            child: const Text(
              'إعادة المحاولة',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
