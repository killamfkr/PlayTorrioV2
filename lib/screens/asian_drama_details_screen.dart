// Asian Drama details screen — kisskh.co.
// Sliver app bar with blurred backdrop, title block with chips,
// expandable synopsis, action row (Play / Resume / Clear), and a
// chunked episode grid (50 per chunk with popup paginator for large
// shows like One Piece).

import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/kisskh_service.dart';
import '../utils/app_theme.dart';
import '../widgets/hover_scale.dart';
import 'asian_drama_player_screen.dart';

class AsianDramaDetailsScreen extends StatefulWidget {
  final KdramaCard drama;
  const AsianDramaDetailsScreen({super.key, required this.drama});

  @override
  State<AsianDramaDetailsScreen> createState() =>
      _AsianDramaDetailsScreenState();
}

class _AsianDramaDetailsScreenState extends State<AsianDramaDetailsScreen> {
  final KissKhService _service = KissKhService();
  KdramaDetails? _details;
  Map<String, dynamic>? _progress;
  bool _loading = true;
  String? _error;
  bool _synopsisExpanded = false;

  static const int _chunkSize = 50;
  int _activeChunk = 0;

  @override
  void initState() {
    super.initState();
    KissKhService.watchHistoryRevision.addListener(_onHistoryChanged);
    _load();
  }

  @override
  void dispose() {
    KissKhService.watchHistoryRevision.removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() => _refreshProgress();

  Future<void> _refreshProgress() async {
    try {
      final p = await _service.getProgress(widget.drama.id);
      if (!mounted) return;
      setState(() => _progress = p);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getDetails(widget.drama.id),
        _service.getProgress(widget.drama.id),
      ]);
      if (!mounted) return;
      setState(() {
        _details = results[0] as KdramaDetails;
        _progress = results[1] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _play(KdramaEpisode ep, {Duration? startPosition}) {
    final det = _details!;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AsianDramaPlayerScreen(
          drama: det.toCard(),
          episode: ep,
          allEpisodes: det.episodes,
          startPosition: startPosition,
        ),
      ),
    ).then((_) => _refreshProgress());
  }

  void _playFirst() {
    final det = _details;
    if (det == null || det.episodes.isEmpty) return;
    _play(det.episodes.first);
  }

  void _resume() {
    final det = _details;
    final p = _progress;
    if (det == null || p == null) return;
    final epNum = (p['episodeNumber'] as num?)?.toDouble() ?? 1.0;
    final posMs = (p['positionMs'] as num?)?.toInt() ?? 0;
    final durMs = (p['durationMs'] as num?)?.toInt() ?? 0;
    KdramaEpisode? ep;
    try {
      ep = det.episodes.firstWhere((e) => e.number == epNum);
    } catch (_) {}
    ep ??= det.episodes.isNotEmpty ? det.episodes.first : null;
    if (ep == null) return;
    Duration? start;
    if (posMs > 5000) {
      final clamped = (durMs > 0 && posMs > durMs - 30000)
          ? (durMs - 30000)
          : posMs;
      start = Duration(milliseconds: (clamped - 3000).clamp(0, 1 << 31));
    }
    _play(ep, startPosition: start);
  }

  Future<void> _clearProgress() async {
    await _service.removeFromHistory(widget.drama.id);
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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
                  : CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        _buildSliverAppBar(),
                        SliverToBoxAdapter(child: _buildTitleBlock()),
                        SliverToBoxAdapter(child: _buildActionRow()),
                        SliverToBoxAdapter(child: _buildSynopsis()),
                        SliverToBoxAdapter(child: _buildMetaGrid()),
                        SliverToBoxAdapter(child: _buildEpisodesHeader()),
                        _buildEpisodesGrid(),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 80),
                        ),
                      ],
                    ),
        );
      },
    );
  }

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
        ),
      ),
    );
  }

  // ─── Sliver app bar (backdrop) ───────────────────────────────
  Widget _buildSliverAppBar() {
    final det = _details!;
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      stretch: true,
      backgroundColor: AppTheme.bgDark,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        background: _buildBackdrop(det),
      ),
    );
  }

  Widget _buildBackdrop(KdramaDetails det) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (det.cover.isNotEmpty)
          CachedNetworkImage(
            imageUrl: det.cover,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            placeholder: (_, _) => Container(color: AppTheme.bgCard),
            errorWidget: (_, _, _) => Container(color: AppTheme.bgCard),
          ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(color: Colors.black.withValues(alpha: 0.15)),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                AppTheme.bgDark.withValues(alpha: 0.4),
                AppTheme.bgDark,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Title + chips ────────────────────────────────────────────
  Widget _buildTitleBlock() {
    final det = _details!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            det.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (det.year != null) _chip(det.year!),
              if (det.country.isNotEmpty) _chip(det.country),
              if (det.type.isNotEmpty) _chip(det.type),
              if (det.status.isNotEmpty)
                _chip(det.status, accent: AppTheme.primaryColor),
              if (det.episodesCount > 0) _chip('${det.episodesCount} EP'),
              if (det.label != null && det.label!.isNotEmpty)
                _chip(det.label!,
                    accent: const Color(0xFFFF8F00)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, {Color? accent}) {
    final c = accent ?? Colors.white.withValues(alpha: 0.18);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent != null
            ? c.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.08),
        border: Border.all(
          color: accent != null
              ? c.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.18),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent != null ? c : Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // ─── Action row ──────────────────────────────────────────────
  Widget _buildActionRow() {
    final hasResume = _progress != null;
    final epLabel = hasResume
        ? () {
            final n = (_progress!['episodeNumber'] as num?)?.toDouble() ?? 1.0;
            return n == n.truncateToDouble()
                ? n.toInt().toString()
                : n.toString();
          }()
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          if (hasResume)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _resume,
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: Text(
                  'Resume EP $epLabel',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _playFirst,
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text(
                  'Play',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          if (hasResume) ...[
            const SizedBox(width: 10),
            IconButton(
              onPressed: _clearProgress,
              tooltip: 'Clear progress',
              icon: const Icon(Icons.delete_outline_rounded),
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Synopsis ────────────────────────────────────────────────
  Widget _buildSynopsis() {
    final desc = _details!.description.trim();
    if (desc.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Synopsis',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedCrossFade(
            crossFadeState: _synopsisExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            firstChild: Text(
              desc,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            secondChild: Text(
              desc,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
          if (desc.length > 220)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    setState(() => _synopsisExpanded = !_synopsisExpanded),
                child: Text(
                  _synopsisExpanded ? 'Show less' : 'Show more',
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Meta grid ───────────────────────────────────────────────
  Widget _buildMetaGrid() {
    final det = _details!;
    final entries = <(String, String)>[
      if (det.releaseDate.isNotEmpty)
        ('Released', _formatDate(det.releaseDate)),
      if (det.country.isNotEmpty) ('Country', det.country),
      if (det.type.isNotEmpty) ('Type', det.type),
      if (det.status.isNotEmpty) ('Status', det.status),
      if (det.episodesCount > 0)
        ('Episodes', '${det.episodesCount}'),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Info',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            entries[i].$1,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entries[i].$2,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i != entries.length - 1)
                    Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    if (iso.length < 10) return iso;
    return iso.substring(0, 10);
  }

  // ─── Episodes header w/ chunk paginator ──────────────────────
  Widget _buildEpisodesHeader() {
    final eps = _details!.episodes;
    if (eps.isEmpty) return const SizedBox.shrink();
    final chunkCount = (eps.length / _chunkSize).ceil();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 8),
      child: Row(
        children: [
          const Text(
            'Episodes',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${eps.length}',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
          if (chunkCount > 1)
            PopupMenuButton<int>(
              color: AppTheme.bgCard,
              initialValue: _activeChunk,
              onSelected: (v) => setState(() => _activeChunk = v),
              itemBuilder: (_) => List.generate(chunkCount, (i) {
                final start = i * _chunkSize + 1;
                final end =
                    ((i + 1) * _chunkSize).clamp(0, eps.length);
                return PopupMenuItem<int>(
                  value: i,
                  child: Text(
                    'EP $start – $end',
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'EP ${_activeChunk * _chunkSize + 1} – '
                      '${((_activeChunk + 1) * _chunkSize).clamp(0, eps.length)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more_rounded,
                        color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEpisodesGrid() {
    final eps = _details!.episodes;
    if (eps.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No episodes available yet.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    final start = _activeChunk * _chunkSize;
    final end = ((_activeChunk + 1) * _chunkSize).clamp(0, eps.length);
    final slice = eps.sublist(start, end);

    final epNum = (_progress?['episodeNumber'] as num?)?.toDouble();

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.6,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            final ep = slice[i];
            final isActive = epNum != null && ep.number == epNum;
            return HoverScale(
              onTap: () => _play(ep),
              radius: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.primaryColor.withValues(alpha: 0.25)
                      : AppTheme.bgCard.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? AppTheme.primaryColor.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ep.displayNumber,
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.92),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'EP',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          childCount: slice.length,
        ),
      ),
    );
  }
}
