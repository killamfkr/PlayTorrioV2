import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/jellyfin_service.dart';
import '../utils/app_theme.dart';
import 'player_screen.dart';

class JellyfinDetailsScreen extends StatefulWidget {
  final JellyfinItem item;
  const JellyfinDetailsScreen({super.key, required this.item});

  @override
  State<JellyfinDetailsScreen> createState() => _JellyfinDetailsScreenState();
}

class _JellyfinDetailsScreenState extends State<JellyfinDetailsScreen>
    with SingleTickerProviderStateMixin {
  final JellyfinService _jf = JellyfinService();

  JellyfinItem? _details;
  bool _isLoading = true;
  String? _error;

  // TV Shows
  List<JellyfinItem> _seasons = [];
  List<JellyfinItem> _episodes = [];
  List<JellyfinItem> _allEpisodes = []; // cache used when seasons come from episode grouping
  bool _usingVirtualSeasons = false;   // true when seasons were synthesised from episodes
  int _selectedSeasonIndex = 0;
  bool _isLoadingEpisodes = false;

  // Similar items
  List<JellyfinItem> _similarItems = [];

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
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
      _details = await _jf.getItemDetails(widget.item.id);

      if (_details!.type == 'Series') {
        try {
          _seasons = await _jf.getSeasons(widget.item.id);
          if (_seasons.isNotEmpty) {
            // Find first non-specials season, or just pick first
            final firstIdx = _seasons.indexWhere((s) => (s.indexNumber ?? 0) > 0);
            _selectedSeasonIndex = firstIdx >= 0 ? firstIdx : 0;
            try {
              await _loadEpisodes(_selectedSeasonIndex);
            } catch (e) {
              debugPrint('[JellyfinDetails] Episodes load error: $e');
            }
          }
        } catch (e) {
          debugPrint('[JellyfinDetails] Seasons load error (non-fatal): $e');
          _seasons = [];
        }

        // Fallback: if no real seasons in DB, fetch all episodes two ways:
        // 1. /Shows/{id}/Episodes (no seasonId filter)
        // 2. /Items?seriesId={id}&includeItemTypes=Episode (broader search)
        if (_seasons.isEmpty) {
          try {
            _allEpisodes = await _jf.getEpisodes(widget.item.id);
          } catch (e) {
            debugPrint('[JellyfinDetails] Shows/Episodes fallback failed: $e');
          }
          // Secondary fallback via Items endpoint
          if (_allEpisodes.isEmpty) {
            try {
              _allEpisodes = await _jf.getEpisodesByItems(widget.item.id);
              debugPrint('[JellyfinDetails] Items endpoint returned ${_allEpisodes.length} episodes');
            } catch (e) {
              debugPrint('[JellyfinDetails] Items episodes fallback failed: $e');
            }
          }

          // Final fallback: the item from search may be a virtual/plugin copy
          // that has no season hierarchy in Jellyfin's DB. Search within
          // tvshows libraries by name to find the canonical item ID that does.
          if (_allEpisodes.isEmpty && _details != null) {
            try {
              final canonicalId = await _jf.findCanonicalSeriesId(
                _details!.name,
                excludeId: widget.item.id,
              );
              if (canonicalId != null) {
                debugPrint('[JellyfinDetails] Using canonical ID: $canonicalId '
                    'instead of search result ID: ${widget.item.id}');
                // Retry the full season+episodes flow with the canonical ID
                final seasons = await _jf.getSeasons(canonicalId);
                if (seasons.isNotEmpty) {
                  _seasons = seasons;
                  final firstIdx = _seasons.indexWhere((s) => (s.indexNumber ?? 0) > 0);
                  _selectedSeasonIndex = firstIdx >= 0 ? firstIdx : 0;
                  await _loadEpisodesById(canonicalId, _seasons[_selectedSeasonIndex].id);
                }
              }
            } catch (e) {
              debugPrint('[JellyfinDetails] Canonical series lookup failed: $e');
            }
          }
          if (_allEpisodes.isNotEmpty) {
            _usingVirtualSeasons = true;
            final seasonNumbers = <int>{};
            for (final ep in _allEpisodes) {
              seasonNumbers.add(ep.parentIndexNumber ?? 1);
            }
            final sorted = seasonNumbers.toList()..sort();
            // If everything is in one implicit season OR parentIndexNumber is
            // all null, just show all episodes without a season selector.
            if (sorted.length == 1) {
              _episodes = List.of(_allEpisodes);
              // Put a single 'All Episodes' season chip so the UI isn't blank
              _seasons = [JellyfinItem(
                id: 'virtual_all',
                name: sorted.first == 0 ? 'Specials' : 'Season ${sorted.first}',
                type: 'Season',
                indexNumber: sorted.first,
              )];
              _selectedSeasonIndex = 0;
            } else {
              _seasons = sorted.map((n) => JellyfinItem(
                id: 'virtual_$n',
                name: n == 0 ? 'Specials' : 'Season $n',
                type: 'Season',
                indexNumber: n,
              )).toList();
              final firstIdx = _seasons.indexWhere((s) => (s.indexNumber ?? 0) > 0);
              _selectedSeasonIndex = firstIdx >= 0 ? firstIdx : 0;
              _episodes = _allEpisodes.where((ep) =>
                (ep.parentIndexNumber ?? 1) == (_seasons[_selectedSeasonIndex].indexNumber ?? 1)
              ).toList();
            }
            debugPrint('[JellyfinDetails] Virtual seasons: ${_seasons.length} seasons, '
                '${_allEpisodes.length} total episodes');
          }
        }
      }

      // Load similar items
      try {
        final parentLib = _details!.type == 'Series' ? 'Series' : 'Movie';
        _similarItems = await _jf.getItems(
          includeItemTypes: parentLib,
          sortBy: 'Random',
          limit: 12,
          genres: _details!.genres.isNotEmpty ? _details!.genres.first : null,
        );
        // Remove self
        _similarItems.removeWhere((i) => i.id == widget.item.id);
      } catch (_) {}
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
        // Filter from the already-fetched full episode list
        final targetSeasonNum = _seasons[seasonIndex].indexNumber ?? 1;
        _episodes = _allEpisodes.where((ep) =>
          (ep.parentIndexNumber ?? 1) == targetSeasonNum
        ).toList();
      } else {
        _episodes = await _jf.getEpisodes(
          widget.item.id,
          seasonId: _seasons[seasonIndex].id,
        );
      }
    } catch (e) {
      debugPrint('[JellyfinDetails] Episodes error: $e');
    }
    if (mounted) setState(() => _isLoadingEpisodes = false);
  }

  /// Like [_loadEpisodes] but uses an explicit [seriesId] and [seasonId].
  /// Used when a canonical series ID was resolved from the library to replace
  /// the virtual item ID that came from a global search.
  Future<void> _loadEpisodesById(String seriesId, String? seasonId) async {
    setState(() => _isLoadingEpisodes = true);
    try {
      _episodes = await _jf.getEpisodes(seriesId, seasonId: seasonId);
    } catch (e) {
      debugPrint('[JellyfinDetails] _loadEpisodesById error: $e');
    }
    if (mounted) setState(() => _isLoadingEpisodes = false);
  }

  void _playItem(JellyfinItem item) async {
    final url = await _jf.getStreamUrl(item.id);
    if (!mounted) return;
    final headers = _jf.streamHeaders;
    String title = item.name;
    if (item.type == 'Episode') {
      title = '${item.seriesName ?? widget.item.name} - S${item.parentIndexNumber ?? '?'}E${item.indexNumber ?? '?'} - ${item.name}';
    }

    // Report playback start
    _jf.reportPlaybackStart(item.id);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: url,
          title: title,
          headers: headers,
          externalSubtitles: _jf.lastSubtitles,
        ),
      ),
    ).then((_) {
      // When player exits, report stopped (we don't have exact position, so pass 0)
      _jf.reportPlaybackStopped(item.id, 0);
      // Refresh details to update watched state
      _loadDetails();
    });
  }

  void _playResume(JellyfinItem item) async {
    final posTicks = item.userData?['PlaybackPositionTicks'] as int? ?? 0;
    final url = await _jf.getStreamUrlWithResume(item.id, posTicks);
    if (!mounted) return;
    final headers = _jf.streamHeaders;
    String title = item.name;
    if (item.type == 'Episode') {
      title = '${item.seriesName ?? widget.item.name} - S${item.parentIndexNumber ?? '?'}E${item.indexNumber ?? '?'} - ${item.name}';
    }

    _jf.reportPlaybackStart(item.id);

    final startPos = Duration(microseconds: posTicks ~/ 10);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: url,
          title: title,
          headers: headers,
          startPosition: startPos,
          externalSubtitles: _jf.lastSubtitles,
        ),
      ),
    ).then((_) {
      _jf.reportPlaybackStopped(item.id, 0);
      _loadDetails();
    });
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
          child: const Center(
            child: CircularProgressIndicator(color: Color(0xFF00A4DC)),
          ),
        ),
      );
    }

    if (_error != null || _details == null) {
      return Scaffold(
        backgroundColor: AppTheme.bgDark,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(child: Text(_error ?? 'Unknown error', style: const TextStyle(color: Colors.white))),
      );
    }

    final item = _details!;
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: CustomScrollView(
        slivers: [
          _buildBackdropHeader(item),
          SliverToBoxAdapter(child: _buildInfoSection(item)),
          if (item.type == 'Movie') SliverToBoxAdapter(child: _buildPlayButton(item)),
          if (item.type == 'Series') ...[
            SliverToBoxAdapter(child: _buildSeasonSelector()),
            SliverToBoxAdapter(child: _buildEpisodeList()),
          ],
          if (_similarItems.isNotEmpty) SliverToBoxAdapter(child: _buildSimilarSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
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

    return SliverAppBar(
      expandedHeight: MediaQuery.of(context).orientation == Orientation.landscape ? 260 : 420,
      pinned: true,
      backgroundColor: AppTheme.bgDark,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        // Favorite button
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: item.isFavorite ? Colors.redAccent : Colors.white,
              size: 22,
            ),
          ),
          onPressed: () async {
            await _jf.toggleFavorite(item.id, item.isFavorite);
            _loadDetails();
          },
        ),
        // Watched toggle
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.isPlayed ? Icons.visibility : Icons.visibility_off_outlined,
              color: item.isPlayed ? const Color(0xFF00A4DC) : Colors.white,
              size: 22,
            ),
          ),
          onPressed: () async {
            if (item.isPlayed) {
              await _jf.markUnplayed(item.id);
            } else {
              await _jf.markPlayed(item.id);
            }
            _loadDetails();
          },
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (backdropUrl != null)
              CachedNetworkImage(
                imageUrl: backdropUrl,
                fit: BoxFit.cover,
                placeholder: (c, u) => Container(color: AppTheme.bgDark),
                errorWidget: (c, u, e) => Container(color: AppTheme.bgDark),
              )
            else
              Container(color: AppTheme.bgDark),

            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppTheme.bgDark.withValues(alpha: 0.3),
                    AppTheme.bgDark.withValues(alpha: 0.8),
                    AppTheme.bgDark,
                  ],
                  stops: const [0.0, 0.4, 0.7, 1.0],
                ),
              ),
            ),

            // Title at bottom
            Positioned(
              bottom: 16,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Meta row
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (item.productionYear != null)
                        _metaChip(Icons.calendar_today, '${item.productionYear}'),
                      if (item.runtime.isNotEmpty)
                        _metaChip(Icons.schedule, item.runtime),
                      if (item.officialRating != null)
                        _metaChip(Icons.shield_outlined, item.officialRating!),
                      if (item.communityRating != null)
                        _metaChip(Icons.star_rounded, item.communityRating!.toStringAsFixed(1),
                            iconColor: const Color(0xFFFFD700)),
                      if (item.status != null && item.type == 'Series')
                        _metaChip(
                          item.status == 'Ended' ? Icons.stop_circle_outlined : Icons.play_circle_outline,
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

  Widget _metaChip(IconData icon, String text, {Color iconColor = const Color(0xFF00A4DC)}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ─── Info Section ────────────────────────────────────────────────────────

  Widget _buildInfoSection(JellyfinItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Genres
          if (item.genres.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: item.genres.map((g) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A4DC).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00A4DC).withValues(alpha: 0.25)),
                ),
                child: Text(g,
                    style: const TextStyle(color: Color(0xFF00A4DC), fontSize: 11, fontWeight: FontWeight.w500)),
              )).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Overview
          if (item.overview != null && item.overview!.isNotEmpty)
            Text(
              item.overview!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13.5,
                height: 1.6,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── Play Button (Movies) ───────────────────────────────────────────────

  Widget _buildPlayButton(JellyfinItem item) {
    final hasProgress = item.playbackProgress > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          // Primary play button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => _playItem(item),
              icon: Icon(hasProgress ? Icons.replay : Icons.play_arrow_rounded, size: 26),
              label: Text(
                hasProgress ? 'Play from Beginning' : 'Play',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A4DC),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
          // Resume button
          if (hasProgress) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _playResume(item),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: Text(
                  'Resume at ${_formatTicks(item.userData?['PlaybackPositionTicks'] as int? ?? 0)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00A4DC),
                  side: const BorderSide(color: Color(0xFF00A4DC), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: item.playbackProgress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00A4DC)),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text('Seasons',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _seasons.length,
              itemBuilder: (context, index) {
                final season = _seasons[index];
                final isSelected = index == _selectedSeasonIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _loadEpisodes(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [Color(0xFF00A4DC), Color(0xFF0077B6)])
                            : null,
                        color: isSelected ? null : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(22),
                        border: isSelected
                            ? null
                            : Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF00A4DC).withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        season.name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
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
        child: Center(child: CircularProgressIndicator(color: Color(0xFF00A4DC))),
      );
    }

    if (_episodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text('No episodes found',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
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

    return GestureDetector(
      onTap: () => _playItem(ep),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Thumbnail
                Container(
                  width: 160,
                  height: 90,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
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
                            baseColor: AppTheme.bgCard,
                            highlightColor: Colors.white10,
                            child: Container(color: AppTheme.bgCard),
                          ),
                          errorWidget: (c, u, e) =>
                              const Center(child: Icon(Icons.movie, color: Colors.white24)),
                        )
                      else
                        const Center(child: Icon(Icons.movie, color: Colors.white24, size: 36)),

                      // Play overlay
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 24),
                        ),
                      ),

                      // Played badge
                      if (ep.isPlayed)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Color(0xFF00A4DC),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),

                // Info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Episode ${ep.indexNumber ?? '?'}',
                          style: TextStyle(
                            color: const Color(0xFF00A4DC),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          ep.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (ep.overview != null && ep.overview!.isNotEmpty)
                          Text(
                            ep.overview!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        const SizedBox(height: 4),
                        if (ep.runtime.isNotEmpty)
                          Text(
                            ep.runtime,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Resume button for this ep
                if (hasProgress)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => _playResume(ep),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A4DC).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.fast_forward_rounded,
                            color: Color(0xFF00A4DC), size: 20),
                      ),
                    ),
                  ),
              ],
            ),

            // Progress bar
            if (hasProgress)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                child: LinearProgressIndicator(
                  value: ep.playbackProgress,
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF00A4DC)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Similar Items ──────────────────────────────────────────────────────

  Widget _buildSimilarSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text('You Might Also Like',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _similarItems.length,
            itemBuilder: (context, index) {
              final sim = _similarItems[index];
              final posterUrl = sim.imageTags.containsKey('Primary')
                  ? _jf.getPosterUrl(sim.id, tag: sim.imageTags['Primary'])
                  : null;
              return GestureDetector(
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => JellyfinDetailsScreen(item: sim)),
                  );
                },
                child: Container(
                  width: 130,
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: posterUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: posterUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (c, u) => Container(color: AppTheme.bgCard),
                                  errorWidget: (c, u, e) => const Center(
                                      child: Icon(Icons.broken_image, color: Colors.white24)),
                                )
                              : const Center(
                                  child: Icon(Icons.movie, size: 36, color: Colors.white24)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sim.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      if (sim.productionYear != null)
                        Text('${sim.productionYear}',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  String _formatTicks(int ticks) {
    final totalSeconds = ticks ~/ 10000000;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
