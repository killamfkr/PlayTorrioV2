import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/jellyfin_service.dart';
import '../utils/app_theme.dart';
import 'player_screen.dart';

// ─── Jellyfin Palette ────────────────────────────────────────────────────────
const _jfBlue = Color(0xFF00A4DC);
const _jfBlueDark = Color(0xFF0077B6);
const _jfSurface = Color(0xFF13131E);
const _jfSurfaceLight = Color(0xFF1A1A2E);

// ─── Hover / Press Card ─────────────────────────────────────────────────────
class _HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _HoverCard({required this.child, this.onTap});
  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hovered = false;
  bool _pressed = false;
  double get _scale => _pressed ? 0.96 : (_hovered ? 1.04 : 1.0);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap?.call();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Details Screen
// ═════════════════════════════════════════════════════════════════════════════

class JellyfinDetailsScreen extends StatefulWidget {
  final JellyfinItem item;
  const JellyfinDetailsScreen({super.key, required this.item});
  @override
  State<JellyfinDetailsScreen> createState() => _JellyfinDetailsScreenState();
}

class _JellyfinDetailsScreenState extends State<JellyfinDetailsScreen> {
  final JellyfinService _jf = JellyfinService();

  JellyfinItem? _details;
  bool _isLoading = true;
  String? _error;

  // TV Shows
  List<JellyfinItem> _seasons = [];
  List<JellyfinItem> _episodes = [];
  List<JellyfinItem> _allEpisodes = [];
  bool _usingVirtualSeasons = false;
  int _selectedSeasonIndex = 0;
  bool _isLoadingEpisodes = false;

  // Similar items
  List<JellyfinItem> _similarItems = [];

  // Overview expansion
  bool _overviewExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Data Loading (preserved from original)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadDetails() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _seasons = [];
      _episodes = [];
      _allEpisodes = [];
      _usingVirtualSeasons = false;
      _selectedSeasonIndex = 0;
    });
    try {
      if (widget.item.type == 'Series') {
        // Use parallel loader for TV shows
        final firstGenre = widget.item.genres.isNotEmpty ? widget.item.genres.first : null;
        final seriesData = await _jf.loadSeriesData(widget.item.id, firstGenre: firstGenre);
        _details = seriesData.details;
        _similarItems = seriesData.similarItems;
        _allEpisodes = seriesData.allEpisodes;

        if (seriesData.seasons.isNotEmpty) {
          _seasons = seriesData.seasons;
          final firstIdx = _seasons.indexWhere((s) => (s.indexNumber ?? 0) > 0);
          _selectedSeasonIndex = firstIdx >= 0 ? firstIdx : 0;
          // Filter episodes for selected season
          final selectedSeason = _seasons[_selectedSeasonIndex];
          _episodes = _allEpisodes
              .where((ep) => ep.seasonId == selectedSeason.id ||
                  (ep.parentIndexNumber ?? 1) == (selectedSeason.indexNumber ?? 1))
              .toList();
        } else if (_allEpisodes.isEmpty) {
          // loadSeriesData fallbacks failed, try canonical series lookup
          try {
            final canonicalId = await _jf.findCanonicalSeriesId(
              _details!.name,
              excludeId: widget.item.id,
            );
            if (canonicalId != null) {
              debugPrint('[JellyfinDetails] Using canonical ID: $canonicalId');
              final canonData = await _jf.loadSeriesData(canonicalId, firstGenre: firstGenre);
              _seasons = canonData.seasons;
              _allEpisodes = canonData.allEpisodes;
              if (_seasons.isNotEmpty) {
                final firstIdx = _seasons.indexWhere((s) => (s.indexNumber ?? 0) > 0);
                _selectedSeasonIndex = firstIdx >= 0 ? firstIdx : 0;
                final selectedSeason = _seasons[_selectedSeasonIndex];
                _episodes = _allEpisodes
                    .where((ep) => ep.seasonId == selectedSeason.id ||
                        (ep.parentIndexNumber ?? 1) == (selectedSeason.indexNumber ?? 1))
                    .toList();
              }
            }
          } catch (e) {
            debugPrint('[JellyfinDetails] Canonical series lookup failed: $e');
          }
        }

        // Build virtual seasons if we have episodes but no real seasons
        if (_seasons.isEmpty && _allEpisodes.isNotEmpty) {
          _usingVirtualSeasons = true;
          final seasonNumbers = <int>{};
          for (final ep in _allEpisodes) {
            seasonNumbers.add(ep.parentIndexNumber ?? 1);
          }
          final sorted = seasonNumbers.toList()..sort();
          if (sorted.length == 1) {
            _episodes = List.of(_allEpisodes);
            _seasons = [
              JellyfinItem(
                id: 'virtual_all',
                name: sorted.first == 0 ? 'Specials' : 'Season ${sorted.first}',
                type: 'Season',
                indexNumber: sorted.first,
              )
            ];
            _selectedSeasonIndex = 0;
          } else {
            _seasons = sorted
                .map((n) => JellyfinItem(
                    id: 'virtual_$n',
                    name: n == 0 ? 'Specials' : 'Season $n',
                    type: 'Season',
                    indexNumber: n))
                .toList();
            final firstIdx = _seasons.indexWhere((s) => (s.indexNumber ?? 0) > 0);
            _selectedSeasonIndex = firstIdx >= 0 ? firstIdx : 0;
            _episodes = _allEpisodes
                .where((ep) =>
                    (ep.parentIndexNumber ?? 1) == (_seasons[_selectedSeasonIndex].indexNumber ?? 1))
                .toList();
          }
        }
      } else {
        // Movie / single item — load details, then similar using detail's genres
        _details = await _jf.getItemDetails(widget.item.id);
        final detailGenre = _details!.genres.isNotEmpty ? _details!.genres.first : null;
        if (detailGenre != null) {
          try {
            _similarItems = await _jf.getItems(
              includeItemTypes: 'Movie',
              sortBy: 'Random',
              limit: 12,
              genres: detailGenre,
            );
            _similarItems.removeWhere((i) => i.id == widget.item.id);
          } catch (_) {}
        }
      }
    } catch (e) {
      _error = 'Failed to load details: $e';
      debugPrint('[JellyfinDetails] Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadEpisodes(int seasonIndex) async {
    if (seasonIndex < 0 || seasonIndex >= _seasons.length) return;
    setState(() {
      _isLoadingEpisodes = true;
      _selectedSeasonIndex = seasonIndex;
    });
    try {
      if (_usingVirtualSeasons) {
        final targetSeasonNum = _seasons[seasonIndex].indexNumber ?? 1;
        _episodes = _allEpisodes.where((ep) => (ep.parentIndexNumber ?? 1) == targetSeasonNum).toList();
      } else {
        _episodes = await _jf.getEpisodes(widget.item.id, seasonId: _seasons[seasonIndex].id);
      }
    } catch (e) {
      debugPrint('[JellyfinDetails] Episodes error: $e');
    }
    if (mounted) setState(() => _isLoadingEpisodes = false);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Playback
  // ═══════════════════════════════════════════════════════════════════════════

  void _playItem(JellyfinItem item) async {
    final result = await _jf.getStreamUrl(item.id);
    if (!mounted) return;
    final headers = _jf.streamHeaders;
    String title = item.name;
    if (item.type == 'Episode') {
      title = '${item.seriesName ?? widget.item.name} - S${item.parentIndexNumber ?? '?'}E${item.indexNumber ?? '?'} - ${item.name}';
    }
    _jf.reportPlaybackStart(item.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: result.url,
          title: title,
          headers: headers,
          externalSubtitles: _jf.lastSubtitles,
        ),
      ),
    ).then((popResult) {
      final pos = popResult is Duration ? popResult.inMicroseconds * 10 : 0;
      _jf.reportPlaybackStopped(item.id, pos);
      _jf.invalidatePlaybackCache();
      _loadDetails();
    });
  }

  void _playResume(JellyfinItem item) async {
    final posTicks = item.userData?['PlaybackPositionTicks'] as int? ?? 0;
    final result = await _jf.getStreamUrlWithResume(item.id, posTicks);
    if (!mounted) return;
    final headers = _jf.streamHeaders;
    String title = item.name;
    if (item.type == 'Episode') {
      title = '${item.seriesName ?? widget.item.name} - S${item.parentIndexNumber ?? '?'}E${item.indexNumber ?? '?'} - ${item.name}';
    }
    _jf.reportPlaybackStart(item.id);
    // Only pass startPosition for direct play — transcoded HLS already
    // starts at the requested offset, so seeking again would double-seek.
    final startPos = result.isTranscode ? null : Duration(microseconds: posTicks ~/ 10);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: result.url,
          title: title,
          headers: headers,
          startPosition: startPos,
          externalSubtitles: _jf.lastSubtitles,
        ),
      ),
    ).then((popResult) {
      final pos = popResult is Duration ? popResult.inMicroseconds * 10 : 0;
      _jf.reportPlaybackStopped(item.id, pos);
      _jf.invalidatePlaybackCache();
      _loadDetails();
    });
  }

  String _formatTicks(int ticks) {
    final totalSeconds = ticks ~/ 10000000;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.bgDark,
        body: Container(
          decoration: AppTheme.backgroundDecoration,
          child: const Center(child: CircularProgressIndicator(color: _jfBlue)),
        ),
      );
    }

    if (_error != null || _details == null) {
      return Scaffold(
        backgroundColor: AppTheme.bgDark,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text(_error ?? 'Unknown error',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _loadDetails,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: TextButton.styleFrom(foregroundColor: _jfBlue),
              ),
            ],
          ),
        ),
      );
    }

    final item = _details!;
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: CustomScrollView(
        slivers: [
          _buildBackdropHeader(item),
          SliverToBoxAdapter(child: _buildInfoSection(item)),
          if (item.type == 'Movie') SliverToBoxAdapter(child: _buildPlayButtons(item)),
          if (item.type == 'Series') ...[
            SliverToBoxAdapter(child: _buildSeasonSelector()),
            SliverToBoxAdapter(child: _buildEpisodeList()),
          ],
          if (_similarItems.isNotEmpty) SliverToBoxAdapter(child: _buildSimilarSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ─── Backdrop Header ─────────────────────────────────────────────────────

  Widget _buildBackdropHeader(JellyfinItem item) {
    final backdropUrl = item.backdropImageTags.isNotEmpty
        ? _jf.getBackdropUrl(item.id, tag: item.backdropImageTags.first)
        : (item.imageTags.containsKey('Primary')
            ? _jf.getPosterUrl(item.id, tag: item.imageTags['Primary'], maxWidth: 1200)
            : null);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return SliverAppBar(
      expandedHeight: isLandscape ? 280 : 440,
      pinned: true,
      backgroundColor: AppTheme.bgDark,
      surfaceTintColor: Colors.transparent,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
      actions: [
        // Favorite
        Padding(
          padding: const EdgeInsets.all(8),
          child: GestureDetector(
            onTap: () async {
              await _jf.toggleFavorite(item.id, item.isFavorite);
              if (mounted) _loadDetails();
            },
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Icon(
                item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: item.isFavorite ? Colors.redAccent : Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
        // Watched
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
          child: GestureDetector(
            onTap: () async {
              if (item.isPlayed) {
                await _jf.markUnplayed(item.id);
              } else {
                await _jf.markPlayed(item.id);
              }
              if (mounted) _loadDetails();
            },
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Icon(
                item.isPlayed ? Icons.visibility_rounded : Icons.visibility_off_outlined,
                color: item.isPlayed ? _jfBlue : Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop image
            if (backdropUrl != null)
              CachedNetworkImage(
                imageUrl: backdropUrl,
                fit: BoxFit.cover,
                placeholder: (c, u) => Container(color: AppTheme.bgDark),
                errorWidget: (c, u, e) => Container(color: AppTheme.bgDark),
              )
            else
              Container(color: AppTheme.bgDark),

            // Cinematic gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppTheme.bgDark.withValues(alpha: 0.15),
                    AppTheme.bgDark.withValues(alpha: 0.6),
                    AppTheme.bgDark.withValues(alpha: 0.95),
                    AppTheme.bgDark,
                  ],
                  stops: const [0.0, 0.25, 0.55, 0.8, 1.0],
                ),
              ),
            ),

            // Content overlay
            Positioned(
              bottom: 24, left: 20, right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _jfBlue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _jfBlue.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      item.type == 'Series' ? 'SERIES' : 'MOVIE',
                      style: const TextStyle(color: _jfBlue, fontSize: 10,
                          fontWeight: FontWeight.w700, letterSpacing: 1.2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Title
                  Text(item.name,
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: -0.5, height: 1.1)),
                  const SizedBox(height: 12),
                  // Meta chips
                  Wrap(
                    spacing: 8, runSpacing: 6,
                    children: [
                      if (item.productionYear != null)
                        _metaTag(Icons.calendar_today_rounded, '${item.productionYear}'),
                      if (item.runtime.isNotEmpty)
                        _metaTag(Icons.schedule_rounded, item.runtime),
                      if (item.officialRating != null)
                        _metaTag(Icons.shield_outlined, item.officialRating!),
                      if (item.communityRating != null)
                        _metaTag(Icons.star_rounded, item.communityRating!.toStringAsFixed(1),
                            iconColor: const Color(0xFFFFD700)),
                      if (item.status != null && item.type == 'Series')
                        _metaTag(
                          item.status == 'Ended'
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline_rounded,
                          item.status!,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaTag(IconData icon, String text, {Color iconColor = _jfBlue}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ─── Info Section ────────────────────────────────────────────────────────

  Widget _buildInfoSection(JellyfinItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Genres
          if (item.genres.isNotEmpty) ...[
            Wrap(
              spacing: 8, runSpacing: 6,
              children: item.genres.map((g) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _jfBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _jfBlue.withValues(alpha: 0.15)),
                ),
                child: Text(g,
                    style: const TextStyle(color: _jfBlue, fontSize: 11,
                        fontWeight: FontWeight.w600)),
              )).toList(),
            ),
            const SizedBox(height: 16),
          ],
          // Overview
          if (item.overview != null && item.overview!.isNotEmpty) ...[
            GestureDetector(
              onTap: () => setState(() => _overviewExpanded = !_overviewExpanded),
              child: AnimatedCrossFade(
                firstChild: Text(item.overview!,
                    maxLines: 4, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13.5, height: 1.6)),
                secondChild: Text(item.overview!,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13.5, height: 1.6)),
                crossFadeState: _overviewExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 250),
              ),
            ),
            if (item.overview!.length > 200)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _overviewExpanded = !_overviewExpanded),
                  child: Text(
                    _overviewExpanded ? 'Show less' : 'Show more',
                    style: const TextStyle(color: _jfBlue, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  // ─── Play Buttons (Movies) ──────────────────────────────────────────────

  Widget _buildPlayButtons(JellyfinItem item) {
    final hasProgress = item.playbackProgress > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          // Primary play button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: GestureDetector(
              onTap: () => _playItem(item),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_jfBlue, _jfBlueDark]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: _jfBlue.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(hasProgress ? Icons.replay_rounded : Icons.play_arrow_rounded,
                        color: Colors.white, size: 24),
                    const SizedBox(width: 10),
                    Text(hasProgress ? 'Play from Start' : 'Play',
                        style: const TextStyle(color: Colors.white, fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
          // Resume button
          if (hasProgress) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: GestureDetector(
                onTap: () => _playResume(item),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _jfBlue.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: _jfBlue, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Resume at ${_formatTicks(item.userData?['PlaybackPositionTicks'] as int? ?? 0)}',
                        style: const TextStyle(color: _jfBlue, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: item.playbackProgress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                valueColor: const AlwaysStoppedAnimation(_jfBlue),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Season Selector ────────────────────────────────────────────────────

  Widget _buildSeasonSelector() {
    if (_seasons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 14),
            child: Row(
              children: [
                Container(
                  width: 4, height: 18,
                  decoration: BoxDecoration(
                    color: _jfBlue, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 10),
                const Text('Seasons',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                        color: Colors.white, letterSpacing: -0.3)),
                const Spacer(),
                Text('${_episodes.length} episodes',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _seasons.length,
              itemBuilder: (_, index) {
                final season = _seasons[index];
                final isSelected = index == _selectedSeasonIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _HoverCard(
                    onTap: () => _loadEpisodes(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(colors: [_jfBlue, _jfBlueDark])
                            : null,
                        color: isSelected ? null : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(22),
                        border: isSelected
                            ? null
                            : Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        boxShadow: isSelected
                            ? [BoxShadow(color: _jfBlue.withValues(alpha: 0.3),
                                blurRadius: 12, offset: const Offset(0, 4))]
                            : null,
                      ),
                      child: Text(season.name,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.55),
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 13,
                          )),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Episode List ───────────────────────────────────────────────────────

  Widget _buildEpisodeList() {
    if (_isLoadingEpisodes) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: _jfBlue)),
      );
    }

    if (_episodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.movie_outlined, size: 40, color: Colors.white.withValues(alpha: 0.12)),
              const SizedBox(height: 12),
              Text('No episodes found',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: _episodes.map((ep) => _buildEpisodeCard(ep)).toList(),
      ),
    );
  }

  Widget _buildEpisodeCard(JellyfinItem ep) {
    final thumbUrl = ep.imageTags.containsKey('Primary')
        ? _jf.getImageUrl(ep.id, type: 'Primary', tag: ep.imageTags['Primary'], maxWidth: 400)
        : null;
    final hasProgress = ep.playbackProgress > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _HoverCard(
        onTap: () => _playItem(ep),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Thumbnail
                  Container(
                    width: 150, height: 85,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: _jfSurface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumbUrl != null)
                          CachedNetworkImage(
                            imageUrl: thumbUrl,
                            fit: BoxFit.cover,
                            placeholder: (c, u) => Shimmer.fromColors(
                              baseColor: _jfSurface, highlightColor: _jfSurfaceLight,
                              child: Container(color: _jfSurface)),
                            errorWidget: (c, u, e) =>
                                const Center(child: Icon(Icons.movie_rounded, color: Colors.white12)),
                          )
                        else
                          const Center(child: Icon(Icons.movie_rounded, color: Colors.white12, size: 28)),
                        // Play overlay
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                        // Played badge
                        if (ep.isPlayed)
                          Positioned(
                            top: 6, right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: _jfBlue, shape: BoxShape.circle),
                              child: const Icon(Icons.check_rounded, size: 9, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Info
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('E${ep.indexNumber ?? '?'}',
                              style: const TextStyle(color: _jfBlue, fontSize: 11,
                                  fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          const SizedBox(height: 3),
                          Text(ep.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          if (ep.overview != null && ep.overview!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(ep.overview!, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.35),
                                    fontSize: 11, height: 1.3)),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (ep.runtime.isNotEmpty)
                                Text(ep.runtime,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.25),
                                        fontSize: 10)),
                              if (hasProgress) ...[
                                const SizedBox(width: 8),
                                Text('${(ep.playbackProgress * 100).round()}%',
                                    style: const TextStyle(color: _jfBlue, fontSize: 10,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Resume icon
                  if (hasProgress)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _HoverCard(
                        onTap: () => _playResume(ep),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _jfBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _jfBlue.withValues(alpha: 0.2)),
                          ),
                          child: const Icon(Icons.fast_forward_rounded, color: _jfBlue, size: 18),
                        ),
                      ),
                    ),
                ],
              ),
              // Progress bar
              if (hasProgress)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
                  child: LinearProgressIndicator(
                    value: ep.playbackProgress,
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    valueColor: const AlwaysStoppedAnimation(_jfBlue),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Similar Items ──────────────────────────────────────────────────────

  Widget _buildSimilarSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
          child: Row(
            children: [
              Container(
                width: 4, height: 18,
                decoration: BoxDecoration(color: _jfBlue, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              const Text('You Might Also Like',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                      color: Colors.white, letterSpacing: -0.3)),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _similarItems.length,
            itemBuilder: (_, index) {
              final sim = _similarItems[index];
              final posterUrl = sim.imageTags.containsKey('Primary')
                  ? _jf.getPosterUrl(sim.id, tag: sim.imageTags['Primary'])
                  : null;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _HoverCard(
                  onTap: () {
                    Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => JellyfinDetailsScreen(item: sim)));
                  },
                  child: SizedBox(
                    width: 130,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: _jfSurface,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: posterUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: posterUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (c, u) => Shimmer.fromColors(
                                      baseColor: _jfSurface, highlightColor: _jfSurfaceLight,
                                      child: Container(color: _jfSurface)),
                                    errorWidget: (c, u, e) => const Center(
                                        child: Icon(Icons.movie_rounded, color: Colors.white12)),
                                  )
                                : const Center(child: Icon(Icons.movie_rounded, color: Colors.white12, size: 32)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(sim.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        if (sim.productionYear != null)
                          Text('${sim.productionYear}',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
