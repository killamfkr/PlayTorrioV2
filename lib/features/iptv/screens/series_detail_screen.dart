import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/iptv_service.dart';
import '../models/iptv_series.dart';
import '../../../screens/player_screen.dart';

class SeriesDetailScreen extends StatefulWidget {
  final IptvSeries series;
  const SeriesDetailScreen({super.key, required this.series});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  final _iptvService = IptvService();
  SeriesInfo? _seriesInfo;
  bool _loading = true;
  String? _error;
  String? _selectedSeason;

  @override
  void initState() {
    super.initState();
    _loadSeriesInfo();
  }

  Future<void> _loadSeriesInfo() async {
    try {
      setState(() { _loading = true; _error = null; });
      final info = await _iptvService.getSeriesInfo(widget.series.seriesId);
      if (mounted) {
        setState(() {
          _seriesInfo = info;
          _loading = false;
          if (info.seasonNumbers.isNotEmpty) {
            _selectedSeason = info.seasonNumbers.first;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  List<IptvEpisode> get _currentEpisodes {
    if (_seriesInfo == null || _selectedSeason == null) return [];
    return _seriesInfo!.episodes[_selectedSeason] ?? [];
  }

  void _playEpisode(IptvEpisode episode) {
    final url = _iptvService.getEpisodeUrl(episode.id, episode.containerExtension);
    final externalSubs = episode.info?.subtitles.map((s) => {
      'lang': s['lang']?.toString() ?? 'Unknown',
      'url': s['url']?.toString() ?? '',
    }).where((s) => (s['url'] ?? '').isNotEmpty).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: url,
          title: '${widget.series.name} S${episode.season}E${episode.episodeNum} - ${episode.title}',
          externalSubtitles: externalSubs?.isNotEmpty == true ? externalSubs : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.series;
    final info = _seriesInfo?.info;
    final backdrop = s.backdropPath.isNotEmpty ? s.backdropPath.first : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: CustomScrollView(
        slivers: [
          // Backdrop header
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: const Color(0xFF0A0A0F),
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdrop != null)
                    CachedNetworkImage(
                      imageUrl: backdrop,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(color: const Color(0xFF1A1A2E)),
                    )
                  else
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4A148C), Color(0xFF880E4F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF0A0A0F).withValues(alpha: 0.6),
                          const Color(0xFF0A0A0F),
                        ],
                        stops: const [0.3, 0.7, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + poster row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Poster
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 130,
                          height: 195,
                          child: s.cover != null && s.cover!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: s.cover!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, _, _) => Container(color: const Color(0xFF1A1A2E)),
                                )
                              : Container(color: const Color(0xFF1A1A2E)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                            ),
                            if (s.genre != null && s.genre!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(s.genre!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                            if (s.releaseDate != null && s.releaseDate!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(s.releaseDate!, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                            ],
                            if (s.rating != null && s.rating!.isNotEmpty && s.rating != '0') ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.amber, size: 16),
                                  const SizedBox(width: 4),
                                  Text(s.rating!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Plot
                  if ((info?.plot ?? s.plot) != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      (info?.plot ?? s.plot)!,
                      style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Loading / error
                  if (_loading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: Color(0xFF4A148C)),
                    )),

                  if (_error != null)
                    Center(
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent),
                          const SizedBox(height: 8),
                          Text('Failed to load series info', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                          TextButton(onPressed: () => _loadSeriesInfo(), child: const Text('Retry')),
                        ],
                      ),
                    ),

                  // Season selector
                  if (_seriesInfo != null && _seriesInfo!.seasonNumbers.isNotEmpty) ...[
                    Text('SEASONS', style: GoogleFonts.bebasNeue(color: Colors.white, fontSize: 18, letterSpacing: 2)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _seriesInfo!.seasonNumbers.length,
                        itemBuilder: (context, index) {
                          final sn = _seriesInfo!.seasonNumbers[index];
                          final isSelected = _selectedSeason == sn;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                'S$sn',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white60,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (_) => setState(() => _selectedSeason = sn),
                              selectedColor: const Color(0xFF4A148C),
                              backgroundColor: Colors.white.withValues(alpha: 0.06),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Episodes
                    Text(
                      'EPISODES',
                      style: GoogleFonts.bebasNeue(color: Colors.white, fontSize: 18, letterSpacing: 2),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),

          // Episode list
          if (_seriesInfo != null)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final ep = _currentEpisodes[index];
                  return _EpisodeTile(
                    episode: ep,
                    seriesName: widget.series.name,
                    onTap: () => _playEpisode(ep),
                  );
                },
                childCount: _currentEpisodes.length,
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final IptvEpisode episode;
  final String seriesName;
  final VoidCallback onTap;

  const _EpisodeTile({required this.episode, required this.seriesName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Episode thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 90,
                    height: 54,
                    child: episode.info?.movieImage != null && episode.info!.movieImage!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: episode.info!.movieImage!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => _episodePlaceholder(),
                          )
                        : _episodePlaceholder(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'E${episode.episodeNum}',
                        style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        episode.title,
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (episode.info?.duration != null && episode.info!.duration!.isNotEmpty)
                        Text(
                          episode.info!.duration!,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.play_circle_filled, color: Color(0xFF4A148C), size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _episodePlaceholder() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: const Center(child: Icon(Icons.play_arrow, color: Colors.white12, size: 24)),
    );
  }
}
