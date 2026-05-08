// kisskh.co (Asian Drama) hub — mirrors `AnimeArabicScreen` visual style.
// Hero carousel + ambient gradient backdrop + continue-watching rail
// + multiple horizontal poster rails sourced from kisskh's category APIs.

import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../api/kisskh_service.dart';
import '../utils/app_theme.dart';
import '../widgets/horizontal_scroller.dart';
import '../widgets/hover_scale.dart';
import 'asian_drama_details_screen.dart';
import 'asian_drama_explore_screen.dart';
import 'asian_drama_player_screen.dart';
import 'asian_drama_search_screen.dart';

class AsianDramaScreen extends StatefulWidget {
  const AsianDramaScreen({super.key});

  @override
  State<AsianDramaScreen> createState() => _AsianDramaScreenState();
}

class _AsianDramaScreenState extends State<AsianDramaScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final KissKhService _service = KissKhService();
  final PageController _heroCtrl = PageController();
  final ScrollController _scroll = ScrollController();

  Timer? _heroTimer;
  int _heroIndex = 0;

  KdramaHomeFeed? _feed;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _continueWatching = [];

  Color _ambientPrimary = AppTheme.primaryColor;
  Color _ambientSecondary = AppTheme.accentColor;
  final Map<int, ({Color primary, Color secondary})> _ambientCache = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppTheme.themeNotifier.addListener(_onTheme);
    KissKhService.watchHistoryRevision.addListener(_onHistoryChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppTheme.themeNotifier.removeListener(_onTheme);
    KissKhService.watchHistoryRevision.removeListener(_onHistoryChanged);
    _heroTimer?.cancel();
    _heroCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTheme() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshHistory();
    }
  }

  void _onHistoryChanged() => _refreshHistory();

  Future<void> _refreshHistory() async {
    try {
      final list = await _service.getWatchHistory();
      if (!mounted) return;
      setState(() => _continueWatching = list.take(10).toList());
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getHome(),
        _service.getWatchHistory(),
      ]);
      if (!mounted) return;
      final feed = results[0] as KdramaHomeFeed;
      setState(() {
        _feed = feed;
        _continueWatching =
            (results[1] as List<Map<String, dynamic>>).take(10).toList();
        _loading = false;
      });
      final pool = _spotlight;
      if (pool.isNotEmpty) {
        _extractAmbient(pool.first);
        _startHeroTimer(pool.length);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<KdramaCard> get _spotlight {
    final f = _feed;
    if (f == null) return const [];
    if (f.spotlight.isNotEmpty) return f.spotlight.take(8).toList();
    if (f.latest.isNotEmpty) return f.latest.take(8).toList();
    return f.trending.take(8).toList();
  }

  void _startHeroTimer(int count) {
    _heroTimer?.cancel();
    if (count < 2) return;
    _heroTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || !_heroCtrl.hasClients) return;
      final next = (_heroIndex + 1) % count;
      _heroCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 1000),
        curve: Curves.fastOutSlowIn,
      );
    });
  }

  Future<void> _extractAmbient(KdramaCard a) async {
    if (_ambientCache.containsKey(a.id)) {
      final c = _ambientCache[a.id]!;
      if (!mounted) return;
      setState(() {
        _ambientPrimary = c.primary;
        _ambientSecondary = c.secondary;
      });
      return;
    }
    if (a.cover.isEmpty) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(a.cover),
        size: const Size(180, 100),
        maximumColorCount: 12,
      );
      if (!mounted) return;
      final p = palette.dominantColor?.color ?? AppTheme.primaryColor;
      final s = palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          AppTheme.accentColor;
      _ambientCache[a.id] = (primary: p, secondary: s);
      setState(() {
        _ambientPrimary = p;
        _ambientSecondary = s;
      });
    } catch (_) {}
  }

  void _openDetails(KdramaCard a) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AsianDramaDetailsScreen(drama: a),
      ),
    ).then((_) => _refreshHistory());
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AsianDramaSearchScreen()),
    );
  }

  void _openExplore() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AsianDramaExploreScreen()),
    );
  }

  Future<void> _resumeWatch(Map<String, dynamic> entry) async {
    try {
      final id = (entry['id'] as num).toInt();
      final epNum = (entry['episodeNumber'] as num?)?.toDouble() ?? 1.0;
      final title = entry['title'] as String? ?? '';
      final cover = entry['cover'] as String? ?? '';
      final posMs = (entry['positionMs'] as num?)?.toInt() ?? 0;
      final durMs = (entry['durationMs'] as num?)?.toInt() ?? 0;
      Duration? startPosition;
      if (posMs > 5000) {
        final clamped = (durMs > 0 && posMs > durMs - 30000)
            ? (durMs - 30000)
            : posMs;
        startPosition =
            Duration(milliseconds: (clamped - 3000).clamp(0, 1 << 31));
      }

      final card = KdramaCard(id: id, title: title, cover: cover);
      final details = await _service.getDetails(id);
      if (!mounted) return;
      KdramaEpisode? ep;
      try {
        ep = details.episodes.firstWhere((e) => e.number == epNum);
      } catch (_) {}
      ep ??= details.episodes.isNotEmpty ? details.episodes.first : null;
      if (ep == null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AsianDramaDetailsScreen(drama: card),
          ),
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AsianDramaPlayerScreen(
            drama: card,
            episode: ep!,
            allEpisodes: details.episodes,
            startPosition: startPosition,
          ),
        ),
      ).then((_) => _refreshHistory());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Resume failed: $e'),
        ),
      );
    }
  }

  Future<void> _removeFromHistory(Map<String, dynamic> entry) async {
    final id = (entry['id'] as num?)?.toInt();
    if (id == null) return;
    await _service.removeFromHistory(id);
  }

  // ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<AppThemePreset>(
      valueListenable: AppTheme.themeNotifier,
      builder: (context, _, _) {
        return Scaffold(
          backgroundColor: AppTheme.bgDark,
          body: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryColor,
                  ),
                )
              : _error != null
                  ? _buildError()
                  : Stack(
                      children: [
                        _buildAmbientBackdrop(),
                        RefreshIndicator(
                          color: AppTheme.primaryColor,
                          backgroundColor: AppTheme.bgCard,
                          onRefresh: _load,
                          child: CustomScrollView(
                            controller: _scroll,
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            slivers: [
                              SliverAppBar(
                                pinned: false,
                                floating: true,
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                                title: const Text(
                                  'Asian Drama',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                actions: [
                                  IconButton(
                                    icon: const Icon(Icons.tune_rounded,
                                        color: Colors.white),
                                    tooltip: 'Explore',
                                    onPressed: _openExplore,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.search,
                                        color: Colors.white),
                                    onPressed: _openSearch,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                              SliverToBoxAdapter(child: _buildHero()),
                              if (_continueWatching.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _buildContinueWatching(),
                                ),
                              if ((_feed?.latest ?? const [])
                                  .isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _buildEpisodeRail(
                                    title: 'Latest Update',
                                    subtitle: 'Newest episodes',
                                    icon: Icons.skip_next_rounded,
                                    items: _feed!.latest,
                                  ),
                                ),
                              if ((_feed?.trending ?? const []).isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _Rail(
                                    title: 'Trending',
                                    icon: Icons.trending_up_rounded,
                                    items: _feed!.trending,
                                    onTap: _openDetails,
                                  ),
                                ),
                              if ((_feed?.topRated ?? const [])
                                  .isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _Rail(
                                    title: 'Top Rated',
                                    icon: Icons.leaderboard_rounded,
                                    items: _feed!.topRated,
                                    onTap: _openDetails,
                                    showRank: true,
                                  ),
                                ),
                              if ((_feed?.mostViewed ?? const [])
                                  .isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _Rail(
                                    title: 'Most Viewed',
                                    icon: Icons.visibility_rounded,
                                    items: _feed!.mostViewed,
                                    onTap: _openDetails,
                                  ),
                                ),
                              if ((_feed?.anime ?? const []).isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _Rail(
                                    title: 'Anime',
                                    icon: Icons.auto_awesome_rounded,
                                    items: _feed!.anime,
                                    onTap: _openDetails,
                                  ),
                                ),
                              if ((_feed?.upcoming ?? const []).isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _Rail(
                                    title: 'Upcoming',
                                    icon: Icons.event_rounded,
                                    items: _feed!.upcoming,
                                    onTap: _openDetails,
                                  ),
                                ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 80),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
        );
      },
    );
  }

  // ─── Error ────────────────────────────────────────────────────
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                color: AppTheme.primaryColor, size: 56),
            const SizedBox(height: 14),
            Text(
              'Failed to load:\n$_error',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Ambient backdrop ────────────────────────────────────────
  Widget _buildAmbientBackdrop() {
    return Positioned.fill(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        child: Stack(
          children: [
            Container(color: AppTheme.bgDark),
            Positioned(
              top: -120,
              right: -160,
              child: Container(
                width: 520,
                height: 520,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _ambientPrimary.withValues(alpha: 0.40),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -140,
              left: -160,
              child: Container(
                width: 480,
                height: 480,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _ambientSecondary.withValues(alpha: 0.30),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Container(color: AppTheme.bgDark.withValues(alpha: 0.35)),
          ],
        ),
      ),
    );
  }

  // ─── Hero carousel ───────────────────────────────────────────
  Widget _buildHero() {
    final pool = _spotlight;
    if (pool.isEmpty) return const SizedBox.shrink();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final h = MediaQuery.of(context).size.height * 0.65;

    return SizedBox(
      height: h,
      child: Stack(
        children: [
          PageView.builder(
            controller: _heroCtrl,
            itemCount: pool.length,
            onPageChanged: (i) {
              setState(() => _heroIndex = i);
              _extractAmbient(pool[i]);
            },
            itemBuilder: (_, i) => _buildHeroSlide(pool[i], isLandscape),
          ),
          Positioned(
            bottom: 22,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pool.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 3,
                  width: i == _heroIndex ? 28 : 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: i == _heroIndex
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSlide(KdramaCard a, bool isLandscape) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (a.cover.isNotEmpty)
          CachedNetworkImage(
            imageUrl: a.cover,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            placeholder: (_, _) => Container(color: AppTheme.bgCard),
            errorWidget: (_, _, _) => Container(color: AppTheme.bgCard),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.transparent,
                AppTheme.bgDark.withValues(alpha: 0.3),
                AppTheme.bgDark.withValues(alpha: 0.85),
                AppTheme.bgDark,
              ],
              stops: const [0.0, 0.25, 0.55, 0.8, 1.0],
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 60,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                a.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isLandscape ? 36 : 28,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  letterSpacing: -0.5,
                  shadows: [
                    Shadow(
                      blurRadius: 20,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (a.label != null && a.label!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFFB300),
                            Color(0xFFFF8F00),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        a.label!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (a.episodesCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${a.episodesCount} EP',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () => _openDetails(a),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 28, vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                color: Colors.black, size: 26),
                            SizedBox(width: 6),
                            Text(
                              'Watch',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _frostedPill(
                    icon: Icons.info_outline_rounded,
                    label: 'Details',
                    onTap: () => _openDetails(a),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _frostedPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withValues(alpha: 0.12),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Continue Watching ────────────────────────────────────────
  Widget _buildContinueWatching() {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.history_rounded,
                      color: AppTheme.primaryColor, size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Continue Watching',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          HorizontalScroller(
            height: 175,
            itemCount: _continueWatching.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (_, i) {
              final entry = _continueWatching[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _continueCard(entry),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _continueCard(Map<String, dynamic> entry) {
    final cover = entry['cover'] as String?;
    final title = entry['title'] as String? ?? '';
    final epNum = (entry['episodeNumber'] as num?)?.toDouble() ?? 1.0;
    final totalEps = (entry['totalEpisodes'] as num?)?.toInt() ?? 0;
    final posMs = (entry['positionMs'] as num?)?.toInt() ?? 0;
    final durMs = (entry['durationMs'] as num?)?.toInt() ?? 0;
    final progress = (durMs > 0) ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    final epLabel = epNum == epNum.truncateToDouble()
        ? epNum.toInt().toString()
        : epNum.toString();

    return SizedBox(
      width: 270,
      child: HoverScale(
        onTap: () => _resumeWatch(entry),
        onLongPress: () async {
          await _removeFromHistory(entry);
        },
        radius: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null && cover.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: AppTheme.bgCard),
                        errorWidget: (_, _, _) =>
                            Container(color: AppTheme.bgCard),
                      )
                    else
                      Container(color: AppTheme.bgCard),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.5, 1.0],
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 28),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'EP $epLabel${totalEps > 0 ? ' / $totalEps' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _removeFromHistory(entry),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (progress > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation(
                              AppTheme.primaryColor),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Episode rail (latest landscape thumbs) ──────────────────
  Widget _buildEpisodeRail({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<KdramaCard> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      color: AppTheme.primaryColor, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          HorizontalScroller(
            height: 175,
            itemCount: items.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (_, i) {
              final item = items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _episodeRailCard(item),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _episodeRailCard(KdramaCard a) {
    return SizedBox(
      width: 270,
      child: HoverScale(
        onTap: () => _openDetails(a),
        radius: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (a.cover.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: a.cover,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: AppTheme.bgCard),
                        errorWidget: (_, _, _) =>
                            Container(color: AppTheme.bgCard),
                      )
                    else
                      Container(color: AppTheme.bgCard),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.78),
                          ],
                          stops: const [0.45, 1.0],
                        ),
                      ),
                    ),
                    if (a.episodesCount > 0)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'EP ${a.episodesCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: Text(
                        a.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Generic poster rail
// ════════════════════════════════════════════════════════════════════
class _Rail extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<KdramaCard> items;
  final void Function(KdramaCard) onTap;
  final bool showRank;

  const _Rail({
    required this.title,
    required this.icon,
    required this.items,
    required this.onTap,
    this.showRank = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon,
                      color: AppTheme.primaryColor, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          HorizontalScroller(
            height: 220,
            itemCount: items.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (_, i) {
              final c = items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _PosterCard(
                  card: c,
                  rank: showRank ? i + 1 : null,
                  onTap: () => onTap(c),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final KdramaCard card;
  final int? rank;
  final VoidCallback onTap;

  const _PosterCard({
    required this.card,
    required this.onTap,
    this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: HoverScale(
        onTap: onTap,
        radius: 10,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (card.cover.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: card.cover,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: AppTheme.bgCard),
                        errorWidget: (_, _, _) =>
                            Container(color: AppTheme.bgCard),
                      )
                    else
                      Container(color: AppTheme.bgCard),
                    if (card.label != null && card.label!.isNotEmpty)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            card.label!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if (card.episodesCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFFB300),
                                Color(0xFFFF8F00),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'EP ${card.episodesCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    if (rank != null)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Text(
                          '#$rank',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.7),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              card.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
