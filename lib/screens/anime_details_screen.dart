import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../api/anime_service.dart';
import '../api/animerealms_extractor.dart';
import '../utils/app_theme.dart';
import 'anime_player_screen.dart';

class AnimeDetailsScreen extends StatefulWidget {
  final AnimeCard anime;

  const AnimeDetailsScreen({super.key, required this.anime});

  @override
  State<AnimeDetailsScreen> createState() => _AnimeDetailsScreenState();
}

class _AnimeDetailsScreenState extends State<AnimeDetailsScreen> {
  final AnimeService _service = AnimeService();

  AnimeEpisodes? _episodes;
  bool _isLoading = true;
  String _selectedProvider = 'kiwi';
  String _selectedCategory = 'sub'; // sub or dub
  bool _isDescriptionExpanded = false;

  List<String> _availableProviders = [];
  bool _hasSub = false;
  bool _hasDub = false;

  // AnimeRealms fallback
  bool _usingAnimeRealms = false;
  List<AnimeEpisode> _animeRealmsEpisodes = [];
  List<String> _animeRealmsProviders = [];

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    setState(() => _isLoading = true);
    try {
      final episodes = await _service.getEpisodes(widget.anime.id);
      if (mounted) {
        final providers = episodes.providers.keys.toList();
        String defaultProvider = providers.isNotEmpty ? providers.first : 'kiwi';
        if (providers.contains('kiwi')) defaultProvider = 'kiwi';
        else if (providers.contains('zoro')) defaultProvider = 'zoro';

        final prov = episodes.providers[defaultProvider];
        final hasSub = prov != null && prov.subEpisodes.isNotEmpty;
        final hasDub = prov != null && prov.dubEpisodes.isNotEmpty;

        // If miruro returned no providers/episodes at all, fall back
        if (providers.isEmpty || (!hasSub && !hasDub)) {
          await _loadFromAnimeRealms();
          return;
        }

        setState(() {
          _episodes = episodes;
          _availableProviders = providers;
          _selectedProvider = defaultProvider;
          _hasSub = hasSub;
          _hasDub = hasDub;
          _selectedCategory = hasSub ? 'sub' : (hasDub ? 'dub' : 'sub');
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AnimeDetails] Miruro failed: $e, trying AnimeRealms...');
      if (mounted) await _loadFromAnimeRealms();
    }
  }

  Future<void> _loadFromAnimeRealms() async {
    try {
      final extractor = AnimeRealmsExtractor();
      final mappings = await extractor.getMappings(widget.anime.id);
      final providers = AnimeRealmsExtractor.getProviderNames(mappings);

      if (!mounted) return;

      // Generate episodes from the anime's known episode count
      final epCount = widget.anime.episodes ?? 0;
      final episodes = <AnimeEpisode>[];
      // If we know the count, generate that many; otherwise generate 1
      // so the user can at least try episode 1
      final count = epCount > 0 ? epCount : 1;
      for (int i = 1; i <= count; i++) {
        episodes.add(AnimeEpisode(
          id: 'ar:${widget.anime.id}:$i',
          number: i,
          title: 'Episode $i',
        ));
      }

      setState(() {
        _usingAnimeRealms = true;
        _animeRealmsProviders = providers;
        _animeRealmsEpisodes = episodes;
        _availableProviders = providers;
        _selectedProvider = providers.first;
        _hasSub = true;
        _hasDub = false;
        _selectedCategory = 'sub';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[AnimeDetails] AnimeRealms also failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onProviderChanged(String provider) {
    if (_usingAnimeRealms) {
      setState(() => _selectedProvider = provider);
      return;
    }
    final prov = _episodes?.providers[provider];
    final hasSub = prov != null && prov.subEpisodes.isNotEmpty;
    final hasDub = prov != null && prov.dubEpisodes.isNotEmpty;
    setState(() {
      _selectedProvider = provider;
      _hasSub = hasSub;
      _hasDub = hasDub;
      if (_selectedCategory == 'sub' && !hasSub && hasDub) _selectedCategory = 'dub';
      if (_selectedCategory == 'dub' && !hasDub && hasSub) _selectedCategory = 'sub';
    });
  }

  List<AnimeEpisode> get _currentEpisodes {
    if (_usingAnimeRealms) return _animeRealmsEpisodes;
    final prov = _episodes?.providers[_selectedProvider];
    if (prov == null) return [];
    return _selectedCategory == 'dub' ? prov.dubEpisodes : prov.subEpisodes;
  }

  void _playEpisode(AnimeEpisode episode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnimePlayerScreen(
          episodeId: episode.id,
          provider: _selectedProvider,
          category: _selectedCategory,
          anilistId: widget.anime.id,
          title: '${widget.anime.displayTitle} - Ep ${episode.number}',
          episodeTitle: episode.title,
          animeCard: widget.anime,
          episodeNumber: episode.number,
          useAnimeRealms: _usingAnimeRealms,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoSection(),
                  if (widget.anime.description != null && widget.anime.description!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildDescription(),
                  ],
                  const SizedBox(height: 24),
                  if (_isLoading)
                    _buildEpisodesShimmer()
                  else if (_episodes != null || _usingAnimeRealms) ...[
                    _buildControls(),
                    const SizedBox(height: 16),
                    if (_currentEpisodes.isNotEmpty)
                      _buildEpisodesList()
                    else
                      _buildNoEpisodes(),
                  ] else
                    _buildNoEpisodes(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sliver App Bar ────────────────────────────────────────────────

  Widget _buildSliverAppBar() {
    final bannerUrl = widget.anime.bannerImage ?? widget.anime.coverUrl;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return SliverAppBar(
      expandedHeight: isLandscape ? 200 : 320,
      pinned: true,
      backgroundColor: AppTheme.bgDark,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Banner image
            CachedNetworkImage(
              imageUrl: bannerUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (_, __) => Container(color: AppTheme.bgCard),
              errorWidget: (_, __, ___) => Container(color: AppTheme.bgCard),
            ),
            // Gradient overlays
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppTheme.bgDark.withValues(alpha: 0.4),
                    AppTheme.bgDark.withValues(alpha: 0.9),
                    AppTheme.bgDark,
                  ],
                  stops: const [0.0, 0.45, 0.75, 1.0],
                ),
              ),
            ),
            // Poster + Title at bottom
            Positioned(
              bottom: 0,
              left: 20,
              right: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Poster
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6B9D).withValues(alpha: 0.25),
                          blurRadius: 20,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: widget.anime.coverUrl,
                        width: 100,
                        height: 140,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 100,
                          height: 140,
                          color: AppTheme.bgCard,
                          child: const Icon(Icons.movie_outlined, color: Colors.white24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Title + meta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.anime.displayTitle,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.anime.titleRomaji.isNotEmpty &&
                            widget.anime.titleRomaji != widget.anime.displayTitle)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              widget.anime.titleRomaji,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.4),
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Info badges ───────────────────────────────────────────────────

  Widget _buildInfoSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (widget.anime.averageScore != null)
            _infoBadge(
              Icons.star_rounded,
              '${(widget.anime.averageScore! / 10).toStringAsFixed(1)}',
              Colors.amber,
            ),
          if (widget.anime.episodes != null)
            _infoBadge(
              Icons.video_library_outlined,
              '${widget.anime.episodes} episodes',
              const Color(0xFF00E5FF),
            ),
          if (widget.anime.format != null)
            _infoBadge(
              Icons.tv_rounded,
              widget.anime.format!,
              const Color(0xFFC44DFF),
            ),
          if (widget.anime.status != null)
            _infoBadge(
              Icons.info_outline,
              _formatStatus(widget.anime.status!),
              _statusColor(widget.anime.status!),
            ),
          if (widget.anime.duration != null)
            _infoBadge(
              Icons.timer_outlined,
              '${widget.anime.duration} min',
              Colors.white60,
            ),
          if (widget.anime.seasonYear != null)
            _infoBadge(
              Icons.calendar_today_outlined,
              '${widget.anime.seasonYear}',
              Colors.white60,
            ),
          ...widget.anime.genres.map((g) => _genreChip(g)),
        ],
      ),
    );
  }

  Widget _infoBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _genreChip(String genre) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(genre, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
    );
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'RELEASING': return 'Airing';
      case 'FINISHED': return 'Completed';
      case 'NOT_YET_RELEASED': return 'Upcoming';
      case 'CANCELLED': return 'Cancelled';
      case 'HIATUS': return 'On Hiatus';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'RELEASING': return const Color(0xFF00E676);
      case 'FINISHED': return const Color(0xFF00E5FF);
      case 'NOT_YET_RELEASED': return const Color(0xFFFFD740);
      case 'CANCELLED': return const Color(0xFFFF5252);
      default: return Colors.white60;
    }
  }

  // ── Description ───────────────────────────────────────────────────

  Widget _buildDescription() {
    final desc = widget.anime.description!
        .replaceAll(RegExp(r'<[^>]*>'), '') // strip HTML
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SYNOPSIS',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
          child: AnimatedCrossFade(
            firstChild: Text(
              desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13.5, height: 1.5),
            ),
            secondChild: Text(
              desc,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13.5, height: 1.5),
            ),
            crossFadeState: _isDescriptionExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _isDescriptionExpanded ? 'Show less' : 'Show more',
          style: const TextStyle(color: Color(0xFFFF6B9D), fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  // ── Provider & Category Controls ──────────────────────────────────

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Provider selector
        if (_availableProviders.length > 1) ...[
          Text(
            'SERVER',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _availableProviders.length,
              itemBuilder: (_, i) {
                final p = _availableProviders[i];
                final isSelected = _selectedProvider == p;
                return GestureDetector(
                  onTap: () => _onProviderChanged(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? const LinearGradient(colors: [Color(0xFFFF6B9D), Color(0xFFC44DFF)])
                          : null,
                      color: isSelected ? null : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected ? null : Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Text(
                      p.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white54,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Sub / Dub toggle
        Row(
          children: [
            Text(
              'EPISODES',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${_currentEpisodes.length})',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12),
            ),
            const Spacer(),
            if (_hasSub || _hasDub)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_hasSub)
                      GestureDetector(
                        onTap: () => setState(() => _selectedCategory = 'sub'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: _selectedCategory == 'sub'
                                ? const LinearGradient(colors: [Color(0xFFFF6B9D), Color(0xFFC44DFF)])
                                : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'SUB',
                            style: TextStyle(
                              color: _selectedCategory == 'sub' ? Colors.white : Colors.white.withValues(alpha: 0.4),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if (_hasDub)
                      GestureDetector(
                        onTap: () => setState(() => _selectedCategory = 'dub'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: _selectedCategory == 'dub'
                                ? const LinearGradient(colors: [Color(0xFFFF6B9D), Color(0xFFC44DFF)])
                                : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'DUB',
                            style: TextStyle(
                              color: _selectedCategory == 'dub' ? Colors.white : Colors.white.withValues(alpha: 0.4),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Episodes List ─────────────────────────────────────────────────

  Widget _buildEpisodesList() {
    final episodes = _currentEpisodes;
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: episodes.length,
      separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.04), height: 1),
      itemBuilder: (_, i) {
        final ep = episodes[i];
        return _EpisodeTile(
          episode: ep,
          onTap: () => _playEpisode(ep),
        );
      },
    );
  }

  Widget _buildNoEpisodes() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined, color: Colors.white.withValues(alpha: 0.1), size: 56),
            const SizedBox(height: 12),
            const Text('No episodes available', style: TextStyle(color: Colors.white30, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodesShimmer() {
    return Column(
      children: List.generate(
        6,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Shimmer.fromColors(
            baseColor: Colors.white.withValues(alpha: 0.04),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Episode Tile ────────────────────────────────────────────────────────

class _EpisodeTile extends StatelessWidget {
  final AnimeEpisode episode;
  final VoidCallback onTap;

  const _EpisodeTile({required this.episode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Episode number badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFC44DFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B9D).withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${episode.number}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Thumbnail
            if (episode.image != null && episode.image!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 90,
                  height: 55,
                  child: CachedNetworkImage(
                    imageUrl: episode.image!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: AppTheme.bgCard),
                  ),
                ),
              ),
            if (episode.image != null && episode.image!.isNotEmpty) const SizedBox(width: 12),
            // Title + details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title ?? 'Episode ${episode.number}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (episode.duration != null) ...[
                        Text(
                          '${episode.duration}m',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (episode.filler)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'FILLER',
                            style: TextStyle(color: Color(0xFFFF5252), fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.play_circle_outline, color: Colors.white.withValues(alpha: 0.2), size: 24),
          ],
        ),
      ),
    );
  }
}
