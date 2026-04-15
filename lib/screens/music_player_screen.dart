import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import '../api/music_player_service.dart';
import '../api/music_service.dart';
import '../api/music_storage_service.dart';
import '../api/music_downloader_service.dart';
import '../api/lyrics_service.dart';
import '../utils/app_theme.dart';
import '../widgets/local_file_image.dart';

enum PlayerView { art, lyrics, related }

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final MusicPlayerService player = MusicPlayerService();
  final MusicService _musicService = MusicService();
  final MusicStorageService _storage = MusicStorageService();
  final MusicDownloaderService _downloader = MusicDownloaderService();

  PlayerView _currentView = PlayerView.art;
  List<MusicTrack> _relatedTracks = [];
  bool _isLoadingRelated = false;
  int _lastActiveIndex = -1;
  final Map<int, GlobalKey> _lyricKeys = {};
  double? _dragValue;

  final ScrollController _lyricsScrollController = ScrollController();
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lyricsScrollController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  void _switchView(PlayerView view) async {
    setState(() {
      _currentView = view;
      if (view == PlayerView.lyrics) {
        _lastActiveIndex = -1;
        _lyricKeys.clear();
      }
    });

    final track = player.currentTrack.value;
    if (track == null) return;

    if (view == PlayerView.related && _relatedTracks.isEmpty) {
      setState(() => _isLoadingRelated = true);
      final related = await _musicService.searchTracks(track.artist);
      if (mounted) {
        setState(() {
          _relatedTracks = related.where((t) => t.id != track.id).toList();
          _isLoadingRelated = false;
        });
      }
    }
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF080812),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.keyboard_arrow_down_rounded, size: 26),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Like button
          ValueListenableBuilder<MusicTrack?>(
            valueListenable: player.currentTrack,
            builder: (context, track, _) {
              if (track == null) return const SizedBox.shrink();
              return FutureBuilder<bool>(
                future: _storage.isLiked(track.id),
                builder: (context, snapshot) {
                  final isLiked = snapshot.data ?? false;
                  return IconButton(
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                      child: Icon(
                        isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        key: ValueKey(isLiked),
                        color: isLiked ? Colors.pinkAccent : Colors.white.withValues(alpha: 0.6),
                        size: 22,
                      ),
                    ),
                    onPressed: () async {
                      if (isLiked) {
                        await _storage.removeLikedSong(track.id);
                      } else {
                        await _storage.saveLikedSong(track);
                      }
                      setState(() {});
                    },
                  );
                },
              );
            },
          ),
          // Download button
          ValueListenableBuilder<MusicTrack?>(
            valueListenable: player.currentTrack,
            builder: (context, track, _) {
              if (track == null) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(Icons.download_rounded, color: Colors.white.withValues(alpha: 0.6), size: 22),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final success = await _downloader.downloadTrack(track);
                  if (mounted) {
                    messenger.showSnackBar(SnackBar(
                      content: Text(success ? 'Added to download queue...' : 'Already in download queue'),
                      backgroundColor: const Color(0xFF1A1030),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ));
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ValueListenableBuilder<MusicTrack?>(
        valueListenable: player.currentTrack,
        builder: (context, track, child) {
          if (track == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text('No song playing', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                ],
              ),
            );
          }

          return Stack(
            children: [
              // Background: blurred album art
              Positioned.fill(
                child: _buildCoverImage(track.cover),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.5),
                          const Color(0xFF080812).withValues(alpha: 0.85),
                          const Color(0xFF080812),
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // Content
              SafeArea(
                bottom: false,
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 600),
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableWidth = constraints.maxWidth;
                        return Column(
                          children: [
                            const SizedBox(height: 8),
                            _buildViewSwitcher(),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 350),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: LayoutBuilder(
                          builder: (context, innerConstraints) {
                            return _buildCurrentView(track, availableWidth, innerConstraints.maxHeight);
                          },
                        ),
                              ),
                            ),
                            _buildPlayerControls(track),
                            const SizedBox(height: 40),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  VIEW SWITCHER
  // ─────────────────────────────────────────────

  Widget _buildViewSwitcher() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewTab('Art', PlayerView.art, Icons.album_rounded),
          _viewTab('Lyrics', PlayerView.lyrics, Icons.lyrics_rounded),
          _viewTab('Related', PlayerView.related, Icons.explore_rounded),
        ],
      ),
    );
  }

  Widget _viewTab(String label, PlayerView view, IconData icon) {
    final isSelected = _currentView == view;
    return GestureDetector(
      onTap: () => _switchView(view),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.white38),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white38,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentView(MusicTrack track, double availableWidth, [double? availableHeight]) {
    switch (_currentView) {
      case PlayerView.art:
        return _buildArtView(track, availableWidth, availableHeight);
      case PlayerView.lyrics:
        return _buildLyricsView();
      case PlayerView.related:
        return _buildRelatedView(availableWidth);
    }
  }

  // ─────────────────────────────────────────────
  //  ART VIEW
  // ─────────────────────────────────────────────

  Widget _buildArtView(MusicTrack track, double availableWidth, [double? availableHeight]) {
    // Reserve ~120px for title/artist/album text + spacing
    final maxArtFromHeight = (availableHeight != null) ? (availableHeight - 120).clamp(100.0, 360.0) : 360.0;
    final artSize = (availableWidth * 0.82).clamp(180.0, maxArtFromHeight);

    return Column(
      key: const ValueKey('art'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Album art with animated glow
        AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15 + (_glowController.value * 0.15)),
                    blurRadius: 40 + (_glowController.value * 20),
                    spreadRadius: 5 + (_glowController.value * 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Hero(
            tag: 'track-art',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: _buildCoverImage(track.cover, width: artSize, height: artSize),
            ),
          ),
        ),
        const SizedBox(height: 36),
        // Track info
        Text(
          track.title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5, height: 1.2),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          track.artist,
          style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.5), letterSpacing: 0.2),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (track.album.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            track.album,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.3)),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  LYRICS VIEW
  // ─────────────────────────────────────────────

  Widget _buildLyricsView() {
    return ValueListenableBuilder<List<LyricLine>?>(
      key: const ValueKey('lyrics'),
      valueListenable: player.lyrics,
      builder: (context, lyricsList, _) {
        if (lyricsList == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 36, height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.primaryColor.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Loading lyrics...', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 14)),
              ],
            ),
          );
        }

        if (lyricsList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lyrics_outlined, size: 48, color: Colors.white.withValues(alpha: 0.15)),
                const SizedBox(height: 16),
                Text('No lyrics available', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 15)),
              ],
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final double viewportHeight = constraints.maxHeight;

            return ValueListenableBuilder<Duration>(
              valueListenable: player.position,
              builder: (context, position, child) {
                int activeIndex = -1;
                for (int i = 0; i < lyricsList.length; i++) {
                  if (position >= lyricsList[i].startTime) {
                    activeIndex = i;
                  } else {
                    break;
                  }
                }

                if (activeIndex != _lastActiveIndex) {
                  _lastActiveIndex = activeIndex;
                  if (activeIndex != -1) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final key = _lyricKeys[activeIndex];
                      if (key != null && key.currentContext != null) {
                        Scrollable.ensureVisible(
                          key.currentContext!,
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeInOutCubic,
                          alignment: 0.4,
                        );
                      }
                    });
                  }
                }

                return ListView.builder(
                  controller: _lyricsScrollController,
                  padding: EdgeInsets.symmetric(vertical: viewportHeight / 2.5),
                  itemCount: lyricsList.length,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final isActive = index == activeIndex;
                    _lyricKeys[index] ??= GlobalKey();

                    return GestureDetector(
                      onTap: () {
                        // Tap to seek to this lyric line
                        player.seek(lyricsList[index].startTime);
                      },
                      child: Container(
                        key: _lyricKeys[index],
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            fontSize: isActive ? 28 : 22,
                            fontWeight: FontWeight.w700,
                            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.12),
                            fontFamily: 'Poppins',
                            height: 1.35,
                            letterSpacing: -0.3,
                            shadows: isActive
                                ? [
                                    Shadow(color: AppTheme.primaryColor.withValues(alpha: 0.5), blurRadius: 20),
                                    Shadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 10, offset: const Offset(0, 3)),
                                  ]
                                : null,
                          ),
                          textAlign: TextAlign.center,
                          child: Text(lyricsList[index].text),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  //  RELATED VIEW
  // ─────────────────────────────────────────────

  Widget _buildRelatedView(double availableWidth) {
    if (_isLoadingRelated) {
      return Center(
        key: const ValueKey('related-loading'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 36, height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primaryColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text('Finding related tracks...', style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
          ],
        ),
      );
    }

    if (_relatedTracks.isEmpty) {
      return Center(
        key: const ValueKey('related-empty'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            Text('No related tracks found', style: TextStyle(color: Colors.white.withValues(alpha: 0.35))),
          ],
        ),
      );
    }

    int crossAxisCount = 2;
    if (availableWidth > 500) crossAxisCount = 3;

    return GridView.builder(
      key: const ValueKey('related'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _relatedTracks.length,
      itemBuilder: (context, index) {
        final t = _relatedTracks[index];
        return _buildRelatedCard(t, _relatedTracks);
      },
    );
  }

  Widget _buildRelatedCard(MusicTrack track, List<MusicTrack> queue) {
    return _PlayerHoverScaleCard(
      onTap: () {
        player.playTrack(track, newPlaylist: queue);
        setState(() {
          _currentView = PlayerView.art;
          _relatedTracks = [];
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: track.cover,
                    fit: BoxFit.cover,
                    errorWidget: (c, u, e) => Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: const Icon(Icons.music_note_rounded, color: Colors.white24),
                    ),
                  ),
                  // Play overlay
                  Positioned(
                    bottom: 6, right: 6,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF9C6FFF)]),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.4), blurRadius: 8)],
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 1),
                  Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.4))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  PLAYER CONTROLS
  // ─────────────────────────────────────────────

  Widget _buildPlayerControls(MusicTrack track) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      child: Column(
        children: [
          // Progress bar
          ValueListenableBuilder<Duration>(
            valueListenable: player.position,
            builder: (context, pos, child) {
              return ValueListenableBuilder<Duration>(
                valueListenable: player.duration,
                builder: (context, dur, child) {
                  final dValue = dur.inSeconds.toDouble();
                  final pValue = pos.inSeconds.toDouble();
                  final safePValue = pValue.clamp(0.0, dValue > 0 ? dValue : 1.0);

                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppTheme.primaryColor,
                          inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                          thumbColor: Colors.white,
                          trackHeight: 4,
                          overlayShape: SliderComponentShape.noOverlay,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        ),
                        child: Slider(
                          value: _dragValue ?? safePValue,
                          max: dValue > 0 ? dValue : 1.0,
                          onChanged: (v) => setState(() => _dragValue = v),
                          onChangeEnd: (v) {
                            player.seek(Duration(seconds: v.toInt()));
                            setState(() => _dragValue = null);
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(pos), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35), fontWeight: FontWeight.w500)),
                          Text(_formatDuration(dur), style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35), fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Shuffle
              ValueListenableBuilder<bool>(
                valueListenable: player.isShuffleEnabled,
                builder: (context, enabled, _) => _buildControlIcon(
                  Icons.shuffle_rounded,
                  onTap: () => player.toggleShuffle(),
                  isActive: enabled,
                  size: 22,
                ),
              ),
              // Previous
              _buildControlIcon(Icons.skip_previous_rounded, onTap: () => player.previous(), size: 36),
              // Play/Pause
              ValueListenableBuilder<bool>(
                valueListenable: player.isBuffering,
                builder: (context, buffering, _) {
                  if (buffering) {
                    return Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 28, height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        ),
                      ),
                    );
                  }
                  return ValueListenableBuilder<bool>(
                    valueListenable: player.isPlaying,
                    builder: (context, playing, _) => GestureDetector(
                      onTap: () => player.togglePlay(),
                      child: Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF8C5FFF), Color(0xFF6B3FDF)],
                          ),
                          boxShadow: [
                            BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Next
              _buildControlIcon(Icons.skip_next_rounded, onTap: () => player.next(), size: 36),
              // Loop
              ValueListenableBuilder<PlaylistMode>(
                valueListenable: player.loopMode,
                builder: (context, mode, _) {
                  IconData icon = Icons.repeat_rounded;
                  bool isActive = mode != PlaylistMode.none;
                  if (mode == PlaylistMode.single) icon = Icons.repeat_one_rounded;
                  return _buildControlIcon(icon, onTap: () => player.toggleLoop(), isActive: isActive, size: 22);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlIcon(IconData icon, {required VoidCallback onTap, bool isActive = false, double size = 24}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: size,
          color: isActive ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.65),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────

  Widget _buildCoverImage(String cover, {double? width, double? height}) {
    if (cover.isEmpty) {
      return Container(
        width: width, height: height,
        color: Colors.white.withValues(alpha: 0.05),
        child: const Icon(Icons.music_note_rounded, color: Colors.white24),
      );
    }
    if (cover.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: cover,
        width: width, height: height,
        fit: BoxFit.cover,
        errorWidget: (c, u, e) => Container(
          width: width, height: height,
          color: Colors.white.withValues(alpha: 0.05),
          child: const Icon(Icons.music_note_rounded, color: Colors.white24),
        ),
      );
    }
    return localFileImageOrFallback(
      path: cover,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

// ─────────────────────────────────────────────
//  HOVER SCALE CARD  (shared hover effect)
// ─────────────────────────────────────────────
class _PlayerHoverScaleCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _PlayerHoverScaleCard({required this.child, this.onTap});
  @override
  State<_PlayerHoverScaleCard> createState() => _PlayerHoverScaleCardState();
}

class _PlayerHoverScaleCardState extends State<_PlayerHoverScaleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onEnter(PointerEvent _) {
    _ctrl.forward();
    setState(() => _hovered = true);
  }

  void _onExit(PointerEvent _) {
    _ctrl.reverse();
    setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
