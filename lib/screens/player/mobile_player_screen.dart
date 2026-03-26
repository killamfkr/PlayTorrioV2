import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:auto_orientation_v2/auto_orientation_v2.dart';

import '../../api/subtitle_api.dart';
import '../../services/watch_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/trakt_service.dart';
import '../../api/torrent_stream_service.dart';
import '../../api/stream_extractor.dart';
import '../../api/webstreamr_service.dart';
import '../../api/arabic_service.dart';
import '../../api/stremio_service.dart';
import '../../api/stream_providers.dart';
import '../../api/settings_service.dart';
import '../../api/debrid_api.dart';
import '../../api/torrent_api.dart';
import '../../api/torrent_filter.dart';
import '../../api/tmdb_service.dart';
import '../../models/movie.dart';
import '../../models/stream_source.dart';
import '../player_screen.dart';
import 'utils.dart';
import 'menus.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  GLASS PRIMITIVES  (mobile — press feedback only, no hover)
// ─────────────────────────────────────────────────────────────────────────────

// ── _SolidGlass ──────────────────────────────────────────────────────────────
// Used for ALL buttons/pills. No BackdropFilter — zero extra GPU layers.
// Slightly higher base opacity (0.72) so it reads clearly on black without
// needing blur to give it body.
class _SolidGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final bool pressed;

  const _SolidGlass({
    required this.child,
    this.radius = 12,
    this.padding,
    this.tint,
    this.pressed = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = tint ?? const Color(0xFF1C1C1E);
    final fillOpacity = pressed ? 0.88 : 0.72;
    final borderOpacity = pressed ? 0.32 : 0.18;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: fillOpacity),
            base.withValues(alpha: fillOpacity - 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: borderOpacity),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── _BlurGlass ───────────────────────────────────────────────────────────────
// Used ONLY for large/decorative elements (title pill, play button, tooltip,
// side indicators) — at most 2-3 on screen at once, so cost is acceptable.
class _BlurGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  const _BlurGlass({
    required this.child,
    this.radius = 12,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 0.8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Glass icon button — touch-friendly 44px default, press animation.
class _GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final bool active;

  const _GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 20,
    this.iconColor,
    this.active = false,
  });

  @override
  State<_GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<_GlassIconButton> {
  bool _pressed = false;

  Color get _tint {
    if (widget.active) return const Color(0xFF6A0DAD);
    if (_pressed) return const Color(0xFF2A2A2E);
    return const Color(0xFF1C1C1E);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.86 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: _SolidGlass(                          // ← no blur
          radius: widget.size / 2,
          tint: _tint,
          pressed: _pressed,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: widget.iconColor ??
                  (widget.active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.85)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass pill button — used for HW badge and aspect ratio label.
class _GlassPillButton extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  final Color? accent;

  const _GlassPillButton({
    required this.text,
    required this.onTap,
    this.accent,
  });

  @override
  State<_GlassPillButton> createState() => _GlassPillButtonState();
}

class _GlassPillButtonState extends State<_GlassPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: _SolidGlass(                          // ← no blur
          radius: 20,
          tint: widget.accent ?? const Color(0xFF1C1C1E),
          pressed: _pressed,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            widget.text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: _pressed ? 1.0 : 0.88),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Center play/pause button with press animation.
class _GlassPlayPause extends StatefulWidget {
  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onPressed;

  const _GlassPlayPause({
    required this.isPlaying,
    required this.isBuffering,
    required this.onPressed,
  });

  @override
  State<_GlassPlayPause> createState() => _GlassPlayPauseState();
}

class _GlassPlayPauseState extends State<_GlassPlayPause> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isBuffering) {
      return _BlurGlass(                             // ← blur OK, only 1 on screen
        radius: 40,
        child: const SizedBox(
          width: 80,
          height: 80,
          child: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: _BlurGlass(                           // ← blur OK, only 1 on screen
          radius: 40,
          child: SizedBox(
            width: 80,
            height: 80,
            child: Icon(
              widget.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 44,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient vignette at top / bottom edges.
class _OverlayGradient extends StatelessWidget {
  final bool isTop;
  const _OverlayGradient({required this.isTop});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
          end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.75),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HARDWARE DECODE MODE  (3-mode cycle)
// ─────────────────────────────────────────────────────────────────────────────

enum _HwDecMode { autoSafe, autoCopy, software }

extension _HwDecModeX on _HwDecMode {
  /// The mpv property value for this mode.
  String get mpvValue => switch (this) {
        _HwDecMode.autoSafe => 'auto-safe',
        _HwDecMode.autoCopy => 'auto-copy',
        _HwDecMode.software => 'no',
      };

  /// Short label shown on the badge pill.
  String get label => switch (this) {
        _HwDecMode.autoSafe => 'HW+',
        _HwDecMode.autoCopy => 'COPY',
        _HwDecMode.software => 'SW',
      };

  String get description => switch (this) {
        _HwDecMode.autoSafe => 'Hardware Decoding: ON (GPU, safe)',
        _HwDecMode.autoCopy => 'Hardware Decoding: ON (copy-back)',
        _HwDecMode.software => 'Hardware Decoding: OFF (CPU)',
      };

  _HwDecMode get next => switch (this) {
        _HwDecMode.autoSafe => _HwDecMode.autoCopy,
        _HwDecMode.autoCopy => _HwDecMode.software,
        _HwDecMode.software => _HwDecMode.autoSafe,
      };

  Color get accent => switch (this) {
        _HwDecMode.autoSafe => const Color(0xFF7C3AED),
        _HwDecMode.autoCopy => const Color(0xFF0EA5E9),
        _HwDecMode.software => const Color(0xFF3A3A3C),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
//  MOBILE PLAYER SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class MobilePlayerScreen extends StatefulWidget {
  final String mediaPath;
  final String title;
  final String? audioUrl;
  final Map<String, String>? headers;
  final Movie? movie;
  final int? selectedSeason;
  final int? selectedEpisode;
  final String? magnetLink;
  final String? activeProvider;
  final Duration? startPosition;
  final List<StreamSource>? sources;
  final int? fileIndex;
  final List<Map<String, dynamic>>? externalSubtitles;
  final String? stremioId;
  final String? stremioAddonBaseUrl;
  final Map<String, dynamic>? providers;

  const MobilePlayerScreen({
    super.key,
    required this.mediaPath,
    required this.title,
    this.audioUrl,
    this.headers,
    this.movie,
    this.selectedSeason,
    this.selectedEpisode,
    this.magnetLink,
    this.activeProvider,
    this.startPosition,
    this.sources,
    this.fileIndex,
    this.externalSubtitles,
    this.stremioId,
    this.stremioAddonBaseUrl,
    this.providers,
  });

  @override
  State<MobilePlayerScreen> createState() => _MobilePlayerScreenState();
}

class _MobilePlayerScreenState extends State<MobilePlayerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Player ──────────────────────────────────────────────────────────────
  late final Player _player;
  late final VideoController _controller;
  bool _disposed = false;
  bool _hasError = false;
  String _errorMessage = '';

  // ── UI State ─────────────────────────────────────────────────────────────
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideTimer;
  BoxFit _videoFit = BoxFit.contain;

  // ── Resume ────────────────────────────────────────────────────────────────
  bool _hasInitialSeek = false;

  // ── Stream Subscriptions ──────────────────────────────────────────────────
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;

  // ── Value Notifiers ───────────────────────────────────────────────────────
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _bufferedNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isBufferingNotifier = ValueNotifier(false);

  // ── Gesture State ─────────────────────────────────────────────────────────
  double _volume = 50.0;       // 0–150 (mpv supports >100%)
  double _brightness = 0.0;    // -100..100 (mpv video brightness)
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;
  Timer? _indicatorHideTimer;

  // ── Double-tap ripple ─────────────────────────────────────────────────────
  late final AnimationController _rippleController;
  late final Animation<double> _rippleScale;
  late final Animation<double> _rippleOpacity;
  bool _showRipple = false;
  bool _isForward = true;
  Offset _ripplePosition = Offset.zero;

  // ── Subtitles ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _externalSubtitles = [];

  // ── Provider switching ────────────────────────────────────────────────────
  String? _currentProvider;
  List<StreamSource>? _currentSources;
  String? _currentUrl;
  int _currentFallbackSourceIndex = 0;
  bool _isSwitchingProvider = false;
  bool _isInitPlaybackRunning = false;
  bool _isFetchingSubs = false;
  String? _selectedExternalSubUrl;

  // ── Feature State ─────────────────────────────────────────────────────────
  _HwDecMode _hwDecMode = _HwDecMode.autoSafe;
  bool _loopEnabled = false;
  double _subtitleDelay = 0.0;
  double _subtitleSize = 24.0;
  final double _subtitleBottomPadding = 24.0;

  // ── Next Episode State ────────────────────────────────────────────────────
  bool _isLoadingNextEp = false;
  bool _nearEndOfEpisode = false;

  // ─────────────────────────────────────────────────────────────────────────
  //  LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // ── Provider initialization ──────────────────────────────────────────
    _currentProvider = widget.activeProvider;
    _currentSources = widget.sources;
    _currentUrl = widget.mediaPath;

    // ── Lifecycle Observer ───────────────────────────────────────────────
    WidgetsBinding.instance.addObserver(this);

    // ── System UI ────────────────────────────────────────────────────────
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    AutoOrientation.fullAutoMode(forceSensor: true);
    SystemChrome.setPreferredOrientations([]);
    WakelockPlus.enable();

    // ── Player ───────────────────────────────────────────────────────────
    _player = Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.warn,
        // libass disabled — Flutter renders subtitles via SubtitleViewConfiguration
        libass: false,
      ),
    );

    // androidAttachSurfaceAfterVideoParameters: false fixes a blank-screen
    // race condition on some Android devices where the surface is attached
    // before mpv has negotiated video dimensions.
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    // ── Ripple animation ─────────────────────────────────────────────────
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _rippleScale = Tween<double>(begin: 0.4, end: 1.6).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
    _rippleOpacity = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
    _rippleController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _showRipple = false);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initPlayback();
      _startHideTimer();
      _fetchSubtitles();
      // Trakt scrobble start
      if (widget.movie != null) {
        TraktService().scrobbleStart(
          tmdbId: widget.movie!.id,
          mediaType: widget.movie!.mediaType,
          season: widget.selectedSeason,
          episode: widget.selectedEpisode,
          progressPercent: 0,
        );
      }
    });
  }

  @override
  void dispose() {
    _saveWatchHistory();

    // Restore free rotation when leaving the player.
    AutoOrientation.fullAutoMode(forceSensor: true);
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _indicatorHideTimer?.cancel();
    _rippleController.dispose();

    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();

    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _bufferedNotifier.dispose();
    _isPlayingNotifier.dispose();
    _isBufferingNotifier.dispose();

    _player.dispose();

    // Remove torrent from engine on player exit (use magnetLink for hash,
    // fall back to mediaPath which may be a stream URL).
    final torrentId = widget.magnetLink ?? widget.mediaPath;
    TorrentStreamService().removeTorrent(torrentId);

    WakelockPlus.disable();

    super.dispose();
  }

  /// Rotate back to portrait & restore system UI BEFORE popping,
  /// so the details page never sees stale landscape dimensions.
  Future<void> _exitPlayer() async {
    _saveWatchHistory();
    AutoOrientation.fullAutoMode(forceSensor: true);
    await SystemChrome.setPreferredOrientations([]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Save progress when app goes to background or is paused
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveWatchHistory();
    }
  }

  void _saveWatchHistory() {
    final pos = _positionNotifier.value.inMilliseconds;
    final dur = _durationNotifier.value.inMilliseconds;

    // Save anime watch position
    if (widget.activeProvider != null &&
        widget.activeProvider!.startsWith('anime_') &&
        pos > 10000 && dur > 0) {
      _saveAnimeWatchPosition(pos, dur);
    }

    if (widget.movie == null) return;
    if (pos > 10000 && dur > 0) {
      final isTorrent = widget.magnetLink != null;
      final isStremioDirect = widget.activeProvider == 'stremio_direct';
      final String method;
      final String sourceId;
      if (isTorrent) {
        method = 'torrent';
        sourceId = widget.magnetLink!;
      } else if (isStremioDirect) {
        method = 'stremio_direct';
        sourceId = widget.mediaPath;
      } else if (widget.activeProvider == 'amri') {
        method = 'amri';
        sourceId = widget.mediaPath;
      } else if (widget.activeProvider != null) {
        method = 'stream';
        sourceId = widget.activeProvider!;
      } else {
        method = 'amri';
        sourceId = widget.mediaPath;
      }
      WatchHistoryService().saveProgress(
        tmdbId: widget.movie!.id,
        imdbId: widget.movie!.imdbId,
        title: widget.title,
        posterPath: widget.movie!.posterPath,
        method: method,
        sourceId: sourceId,
        position: pos,
        duration: dur,
        season: widget.selectedSeason,
        episode: widget.selectedEpisode,
        episodeTitle: widget.selectedEpisode != null
            ? 'Episode ${widget.selectedEpisode}'
            : null,
        magnetLink: widget.magnetLink,
        fileIndex: widget.fileIndex,
        streamUrl: isStremioDirect ? widget.mediaPath : null,
        stremioId: widget.stremioId,
        stremioAddonBaseUrl: widget.stremioAddonBaseUrl,
        stremioType: widget.movie!.mediaType == 'tv' ? 'series' : 'movie',
        mediaType: widget.movie!.mediaType,
      );

      // Trakt scrobble — fire and forget
      final progressPercent = dur > 0 ? (pos / dur * 100) : 0.0;
      TraktService().scrobbleStop(
        tmdbId: widget.movie!.id,
        mediaType: widget.movie!.mediaType,
        season: widget.selectedSeason,
        episode: widget.selectedEpisode,
        progressPercent: progressPercent,
      );
    }
  }

  void _saveAnimeWatchPosition(int posMs, int durMs) {
    SharedPreferences.getInstance().then((prefs) {
      final list = prefs.getStringList('anime_watch_history') ?? [];
      for (int i = 0; i < list.length; i++) {
        final entry = jsonDecode(list[i]) as Map<String, dynamic>;
        // Match by title which contains the anime name + episode
        // The most recent entry (index 0) is the one currently playing
        if (i == 0) {
          entry['position'] = posMs;
          entry['duration'] = durMs;
          list[i] = jsonEncode(entry);
          prefs.setStringList('anime_watch_history', list);
          break;
        }
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PLAYBACK INITIALIZATION
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initPlayback() async {
    if (_disposed) return;
    if (_isInitPlaybackRunning) return; // Prevent re-entrant calls during async extraction
    _isInitPlaybackRunning = true;
    
    try {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    // 1. Try sources in current provider list
    if (_currentSources != null && _currentSources!.isNotEmpty) {
      while (_currentFallbackSourceIndex < _currentSources!.length) {
        final i = _currentFallbackSourceIndex;
        var source = _currentSources![i];
        debugPrint('[Player] Trying source ${i + 1}/${_currentSources!.length}: ${source.title}');

        // Arabic embed sources need on-demand extraction first
        if (_currentProvider == 'arabic' && source.type == 'arabic_embed') {
          debugPrint('[Player] Extracting arabic embed: ${source.title}');
          final result = await ArabicService.extractStreamUrl(source.url);
          if (result == null) {
            debugPrint('[Player] Arabic extract failed for ${source.title}');
            _currentFallbackSourceIndex++;
            continue;
          }
          // Update the source with the real stream URL
          source = StreamSource(
            url: result.url,
            title: source.title,
            type: result.url.contains('.m3u8') ? 'hls' : result.url.contains('.mpd') ? 'dash' : 'mp4',
          );
          _currentSources![i] = source;
        }
        
        try {
          _subscribeToStreams();
          await _configureMpvProperties();
          final srcHeaders = source.headers ?? widget.headers;
          await _player.open(Media(source.url, httpHeaders: srcHeaders));
          // Update mpv referrer for this specific source
          if (source.headers != null && _player.platform is NativePlayer) {
            final ref = source.headers!['Referer'] ?? source.headers!['referer'];
            if (ref != null) await (_player.platform as NativePlayer).setProperty('referrer', ref);
          }
          _player.setVolume(_volume);
          setState(() {
            _currentUrl = source.url;
          });
          return; // Opened successfully (might still error out during buffering)
        } catch (e) {
          debugPrint('[Player] Source $i catch error: $e');
          _currentFallbackSourceIndex++;
        }
      }
      
      // If we finished the loop, all sources in current provider failed
      await _autoFallbackToNextProvider();
    } else {
      // No sources list, just try the primary mediaPath
      int retryCount = 0;
      const maxRetries = 2;
      
      while (retryCount < maxRetries) {
        try {
          _subscribeToStreams();
          await _configureMpvProperties();
          await _player.open(Media(widget.mediaPath, httpHeaders: widget.headers));
          _player.setVolume(_volume);
          return;
        } catch (e) {
          retryCount++;
          if (retryCount >= maxRetries) {
            await _autoFallbackToNextProvider();
            return;
          }
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }
    }
    } finally {
      _isInitPlaybackRunning = false;
    }
  }

  Future<void> _autoFallbackToNextProvider() async {
    if (widget.providers == null || widget.providers!.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = 'All sources and providers failed.';
      });
      return;
    }

    final providerKeys = widget.providers!.keys.toList();
    int currentIndex = providerKeys.indexOf(_currentProvider ?? '');
    
    // Try the next provider in the list
    for (int i = currentIndex + 1; i < providerKeys.length; i++) {
      final nextKey = providerKeys[i];
      debugPrint('[Player] Auto-falling back to provider: $nextKey');
      
      final success = await _silentSwitchProvider(nextKey);
      if (success) return;
    }

    // If we're here, everything failed
    if (mounted) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Could not find any working stream from any provider.';
      });
    }
  }

  /// Switches provider without showing full error UI on failure, returns success
  Future<bool> _silentSwitchProvider(String newProvider) async {
    try {
      final provider = widget.providers![newProvider];
      String? streamUrl;
      Map<String, String>? headers;
      List<StreamSource>? sources;

      if (newProvider == 'webstreamr' && widget.movie?.imdbId != null) {
        final webStreamr = WebStreamrService();
        final webStreamrSources = await webStreamr.getStreams(
          imdbId: widget.movie!.imdbId!,
          isMovie: widget.movie!.mediaType == 'movie',
          season: widget.selectedSeason,
          episode: widget.selectedEpisode,
        );
        if (webStreamrSources.isNotEmpty) {
          streamUrl = webStreamrSources.first.url;
          sources = webStreamrSources;
        }
      } else {
        final String providerUrl;
        if (widget.movie!.mediaType == 'tv') {
          providerUrl = provider['tv'](
            widget.movie!.id.toString(),
            widget.selectedSeason,
            widget.selectedEpisode,
          );
        } else {
          providerUrl = provider['movie'](widget.movie!.id.toString());
        }
        
        final extractor = StreamExtractor();
        final result = await extractor.extract(providerUrl);
        if (result != null && result.url.isNotEmpty) {
          streamUrl = result.url;
          headers = result.headers;
          sources = result.sources;
        }
      }
      
      if (streamUrl != null && streamUrl.isNotEmpty) {
        final currentPos = _positionNotifier.value;
        await _player.open(Media(streamUrl, httpHeaders: headers));
        if (currentPos.inSeconds > 0) await _player.seek(currentPos);
        
        setState(() {
          _currentProvider = newProvider;
          _currentSources = sources;
          _currentUrl = streamUrl;
          _currentFallbackSourceIndex = 0; // Reset for the new provider
          _hasError = false;
          _errorMessage = '';
        });
        return true;
      }
    } catch (e) {
      debugPrint('[Player] Silent fallback to $newProvider failed: $e');
    }
    return false;
  }

  void _subscribeToStreams() {
    _positionSub = _player.stream.position.listen((pos) {
      if (_disposed) return;
      _positionNotifier.value = pos;

      // Near-end detection for next episode button
      if (_isNextEpisodeAvailable && !_nearEndOfEpisode) {
        final dur = _durationNotifier.value;
        if (dur.inSeconds > 0) {
          final remaining = dur - pos;
          final threshold = dur.inMinutes < 10
              ? Duration(seconds: (dur.inSeconds * 0.05).round())
              : const Duration(minutes: 2);
          if (remaining <= threshold) {
            setState(() => _nearEndOfEpisode = true);
          }
        }
      }
    });

    _durationSub = _player.stream.duration.listen((dur) {
      if (_disposed) return;
      _durationNotifier.value = dur;
      if (!_hasInitialSeek &&
          dur.inSeconds > 0 &&
          widget.startPosition != null) {
        _hasInitialSeek = true;
        // mpv 'start' property handles the initial seek natively (set in
        // _configureMpvProperties). Fire a deferred seek as a safety net in
        // case the property was ignored (e.g. live streams, non-seekable src).
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_disposed) return;
          final currentPos = _positionNotifier.value;
          // Only seek if the player didn't already land near the target
          // (i.e. the 'start' property worked).
          final target = widget.startPosition!;
          if ((currentPos - target).abs() > const Duration(seconds: 5)) {
            _player.seek(target);
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Resumed from ${formatDuration(widget.startPosition!)}'),
            duration: const Duration(seconds: 2),
          ));
        }
      }
    });

    _bufferSub = _player.stream.buffer.listen((buf) {
      if (_disposed) return;
      _bufferedNotifier.value = buf;
    });

    _playingSub = _player.stream.playing.listen((playing) {
      if (_disposed) return;
      _isPlayingNotifier.value = playing;
      if (playing) _startHideTimer();
    });

    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (_disposed) return;
      _isBufferingNotifier.value = buffering;
    });

    // Surface only fatal errors — transient network blips are handled by mpv
    _errorSub = _player.stream.error.listen((err) {
      if (_disposed || err.isEmpty) return;
      
      // Ignore non-fatal audio errors (video continues playing)
      if (err.contains('Error decoding audio') ||
          err.contains('Failed to initialize a decoder for codec')) {
        return;
      }
      
      debugPrint('🔴 [MobilePlayer] $err');
      
      if (err.contains('Failed') || err.contains('No such file')) {
        if (_isInitPlaybackRunning) {
          debugPrint('[Player] Ignoring stale error — _initPlayback already running');
          return;
        }
        debugPrint('[Player] Fatal error detected on source $_currentFallbackSourceIndex, progressing fallback...');
        _currentFallbackSourceIndex++;
        _initPlayback();
      }
    });

    _completedSub = _player.stream.completed.listen((completed) {
      if (_disposed || !completed) return;
      // Show controls when playback finishes so user can navigate away
      if (mounted) setState(() => _showControls = true);
    });
  }

  Future<void> _configureMpvProperties() async {
    if (_player.platform is! NativePlayer) return;
    final mpv = _player.platform as NativePlayer;

    // ── Decoding ─────────────────────────────────────────────────────────
    // auto-safe on mobile: uses MediaCodec (Android) / VideoToolbox (iOS),
    // whitelisted to formats each platform reliably supports.
    await mpv.setProperty('hwdec', _hwDecMode.mpvValue);

    // Zero-copy direct rendering — decoder writes straight to GPU texture.
    // Big win on mobile for battery + throughput on H.265/4K content.
    await mpv.setProperty('vd-lavc-dr', 'yes');

    // Auto thread count (0 = let mpv decide). On mobile 4–8 cores typical.
    await mpv.setProperty('vd-lavc-threads', '0');

    // ── Audio Codec Fallback ──────────────────────────────────────────────
    // Continue playback even if audio codec is unsupported (e.g., TrueHD).
    // User can switch to alternate audio track from the menu.
    await mpv.setProperty('ad-lavc-downmix', 'no');
    await mpv.setProperty('audio-fallback-to-null', 'yes');

    // Flutter renders subtitles — kill mpv's own OSD overlay.
    await mpv.setProperty('sub-visibility', 'no');
    await mpv.setProperty('sub-auto', 'all');

    // ── Video Sync ────────────────────────────────────────────────────────
    // On mobile we use audio sync (not display-resample).
    // display-resample requires a stable vsync signal from the display driver
    // which is unreliable on Android and drains battery unnecessarily.
    // audio sync gives smooth playback tied to the audio clock instead.
    await mpv.setProperty('video-sync', 'audio');

    // ── Adaptive Streaming (HLS/DASH) ─────────────────────────────────────
    // Always pick the highest bitrate variant in multi-quality playlists.
    await mpv.setProperty('hls-bitrate', 'max');

    // ── Network / Cache ───────────────────────────────────────────────────
    await mpv.setProperty('network-timeout', '30');
    await mpv.setProperty('tls-verify', 'no');

    // 150 MiB forward cache (less than desktop's 300 MiB — spare mobile RAM).
    await mpv.setProperty('cache', 'yes');
    await mpv.setProperty('cache-secs', '120');
    await mpv.setProperty('demuxer-max-bytes', '150MiB');
    await mpv.setProperty('demuxer-readahead-secs', '120');

    // 30 MiB back-buffer so backward seeks don't require a full rebuffer.
    await mpv.setProperty('demuxer-max-back-bytes', '30MiB');

    // We supply our own URL — no yt-dlp needed.
    await mpv.setProperty('ytdl', 'no');

    // Allow volume boosting up to 150% for quiet sources.
    await mpv.setProperty('volume-max', '150');

    // ── External Audio ────────────────────────────────────────────────────
    if (widget.audioUrl != null) {
      await mpv.setProperty('audio-file', widget.audioUrl!);
    }

    // ── HTTP Headers ──────────────────────────────────────────────────────
    if (widget.headers != null) {
      final referer =
          widget.headers!['Referer'] ?? widget.headers!['referer'];
      if (referer != null) await mpv.setProperty('referrer', referer);

      final ua =
          widget.headers!['User-Agent'] ?? widget.headers!['user-agent'];
      if (ua != null) await mpv.setProperty('user-agent', ua);
    }

    // ── Resume Position ──────────────────────────────────────────────────
    // Set mpv's native 'start' property so it begins playback at the saved
    // position. This is far more reliable on Android than seeking after open,
    // because the post-open seek can be silently dropped before the demuxer
    // is fully initialised.
    if (widget.startPosition != null && !_hasInitialSeek) {
      final secs = widget.startPosition!.inMilliseconds / 1000.0;
      await mpv.setProperty('start', '+${secs.toStringAsFixed(3)}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  HW DECODE CYCLE
  // ─────────────────────────────────────────────────────────────────────────

  void _cycleHwDec() {
    final next = _hwDecMode.next;
    setState(() => _hwDecMode = next);
    if (_player.platform is NativePlayer) {
      (_player.platform as NativePlayer)
          .setProperty('hwdec', next.mpvValue);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(next.description),
      duration: const Duration(seconds: 2),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  UI HIDE TIMER
  // ─────────────────────────────────────────────────────────────────────────

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_isPlayingNotifier.value) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_disposed) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _showControls = !_isLocked;
    });
    if (!_isLocked) _startHideTimer();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  GESTURE HANDLERS
  // ─────────────────────────────────────────────────────────────────────────

  void _handleDoubleTap(TapDownDetails details, bool isRight) {
    if (_isLocked) return;
    setState(() {
      _showRipple = true;
      _isForward = isRight;
      _ripplePosition = details.localPosition;
    });
    _rippleController.forward(from: 0.0);
    
    // Calculate new position and clamp to valid range
    final currentPos = _positionNotifier.value;
    final duration = _durationNotifier.value;
    final delta = isRight ? const Duration(seconds: 10) : const Duration(seconds: -10);
    var newPos = currentPos + delta;
    
    // Clamp to valid range [0, duration]
    if (newPos < Duration.zero) {
      newPos = Duration.zero;
    } else if (newPos > duration) {
      newPos = duration;
    }
    
    _player.seek(newPos);
    _startHideTimer();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double width) {
    if (_isLocked) return;

    final isRight = details.localPosition.dx > width / 2;
    // delta is inverted: drag up = positive = increase
    final delta = -details.primaryDelta! / 3;

    if (isRight) {
      _volume = (_volume + delta).clamp(0.0, 150.0);
      _player.setVolume(_volume);
      setState(() {
        _showVolumeIndicator = true;
        _showBrightnessIndicator = false;
      });
    } else {
      _brightness = (_brightness + delta).clamp(-100.0, 100.0);
      if (_player.platform is NativePlayer) {
        (_player.platform as NativePlayer)
            .setProperty('brightness', _brightness.toInt().toString());
      }
      setState(() {
        _showBrightnessIndicator = true;
        _showVolumeIndicator = false;
      });
    }

    _indicatorHideTimer?.cancel();
    _indicatorHideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _showVolumeIndicator = false;
          _showBrightnessIndicator = false;
        });
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  ASPECT RATIO
  // ─────────────────────────────────────────────────────────────────────────

  String get _videoFitLabel => switch (_videoFit) {
        BoxFit.contain => 'FIT',
        BoxFit.cover => 'CROP',
        BoxFit.fill => 'FILL',
        _ => 'FIT',
      };

  void _cycleAspectRatio() {
    setState(() {
      if (_videoFit == BoxFit.contain) {
        _videoFit = BoxFit.cover;
      } else if (_videoFit == BoxFit.cover) {
        _videoFit = BoxFit.fill;
      } else {
        _videoFit = BoxFit.contain;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Aspect Ratio: $_videoFitLabel'),
        duration: const Duration(seconds: 1)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  SUBTITLES
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchSubtitles() async {
    // Pre-populate with Jellyfin subtitles if provided
    final jellyfinSubs = widget.externalSubtitles ?? [];
    if (jellyfinSubs.isNotEmpty) {
      if (mounted) setState(() => _externalSubtitles = List<Map<String, dynamic>>.from(jellyfinSubs));
    }

    if (widget.movie == null) return;
    if (mounted) setState(() => _isFetchingSubs = true);

    final stream = SubtitleApi.fetchSubtitlesStream(
      tmdbId: widget.movie!.id,
      imdbId: widget.movie!.imdbId,
      season: widget.selectedSeason,
      episode: widget.selectedEpisode,
    );

    stream.listen(
      (subs) { if (mounted) setState(() => _externalSubtitles = [...jellyfinSubs, ...subs]); },
      onDone: () { if (mounted) setState(() => _isFetchingSubs = false); },
    );
  }

  void _showSubtitlesMenu() {
    String searchQuery = '';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E0E0E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          final current = _player.state.track.subtitle;

          final embedded =
              _player.state.tracks.subtitle.where((t) {
            final isExternal = t.id.startsWith('http');
            final isKnownExternal = _externalSubtitles
                .any((s) => s['display'] == t.title && s['language'] == t.language);
            final matchesSearch = searchQuery.isEmpty ||
                (t.title?.toLowerCase().contains(searchQuery.toLowerCase()) ??
                    false) ||
                (t.language?.toLowerCase().contains(searchQuery.toLowerCase()) ??
                    false);
            return t.id != 'no' && !isExternal && !isKnownExternal && matchesSearch;
          }).toList();

          final online = _externalSubtitles.where((s) {
            final display = s['display'] ?? 'Unknown';
            final lang = s['language'] ?? '';
            return searchQuery.isEmpty ||
                display.toLowerCase().contains(searchQuery.toLowerCase()) ||
                lang.toLowerCase().contains(searchQuery.toLowerCase());
          }).toList();

          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 16, right: 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Subtitles',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          color: Colors.white54, size: 20),
                      tooltip: 'Subtitle settings',
                      onPressed: _showSubtitleSettings,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search subtitles...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  ),
                  onChanged: (v) => setModalState(() => searchQuery = v),
                ),
              ),
              if (_isFetchingSubs)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: LinearProgressIndicator(
                      color: Color(0xFF7C3AED),
                      backgroundColor: Colors.white10),
                ),
              Expanded(
                child: ListView(children: [
                  ListTile(
                    leading:
                        const Icon(Icons.close, color: Colors.white70),
                    title: const Text('Off',
                        style: TextStyle(color: Colors.white)),
                    trailing: current.id == 'no'
                        ? const Icon(Icons.check, color: Color(0xFF7C3AED))
                        : null,
                    onTap: () {
                      _selectedExternalSubUrl = null;
                      _player.setSubtitleTrack(SubtitleTrack.no());
                      Navigator.pop(context);
                    },
                  ),
                  if (embedded.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('EMBEDDED',
                          style: TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    ...embedded.map((t) {
                      final sel = t.id == current.id &&
                          _selectedExternalSubUrl == null;
                      return ListTile(
                        title: Text(
                            t.title ?? t.language ?? 'Track ${t.id}',
                            style: TextStyle(
                                color: sel
                                    ? const Color(0xFF7C3AED)
                                    : Colors.white,
                                fontWeight: sel
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        trailing: sel
                            ? const Icon(Icons.check,
                                color: Color(0xFF7C3AED))
                            : null,
                        onTap: () {
                          _selectedExternalSubUrl = null;
                          _player.setSubtitleTrack(t);
                          Navigator.pop(context);
                        },
                      );
                    }),
                  ],
                  if (online.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('ONLINE',
                          style: TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    ...online.map((s) {
                      final sel = s['url'] == _selectedExternalSubUrl;
                      return ListTile(
                        title: Text(s['display'] ?? 'Unknown',
                            style: TextStyle(
                                color: sel
                                    ? const Color(0xFF7C3AED)
                                    : Colors.white,
                                fontWeight: sel
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        subtitle: Text(s['language'] ?? '',
                            style: TextStyle(
                                color: sel
                                    ? const Color(0xFF7C3AED)
                                        .withValues(alpha: 0.7)
                                    : Colors.white54,
                                fontSize: 12)),
                        trailing: sel
                            ? const Icon(Icons.check,
                                color: Color(0xFF7C3AED))
                            : null,
                        onTap: () {
                          _selectedExternalSubUrl = s['url'];
                          _player.setSubtitleTrack(SubtitleTrack.uri(
                              s['url'],
                              title: s['display'],
                              language: s['language']));
                          Navigator.pop(context);
                        },
                      );
                    }),
                  ],
                  if (embedded.isEmpty && online.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: Text('No subtitles found',
                              style:
                                  TextStyle(color: Colors.white54))),
                    ),
                ]),
              ),
            ]),
          );
        });
      },
    );
  }

  void _showSubtitleSettings() {
    showDialog(
      context: context,
      builder: (context) =>
          StatefulBuilder(builder: (context, setDialog) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121212),
          title: const Text('Subtitle Settings',
              style: TextStyle(color: Colors.white)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const SizedBox(
                  width: 54,
                  child:
                      Text('Size', style: TextStyle(color: Colors.white70))),
              Expanded(
                child: Slider(
                  value: _subtitleSize,
                  min: 10, max: 50,
                  thumbColor: const Color(0xFF7C3AED),
                  onChanged: (v) {
                    setDialog(() => _subtitleSize = v);
                    setState(() {});
                  },
                ),
              ),
              Text('${_subtitleSize.toInt()}',
                  style: const TextStyle(color: Colors.white)),
            ]),
            Row(children: [
              const SizedBox(
                  width: 54,
                  child: Text('Delay',
                      style: TextStyle(color: Colors.white70))),
              Expanded(
                child: Slider(
                  value: _subtitleDelay,
                  min: -10.0, max: 10.0,
                  thumbColor: const Color(0xFF7C3AED),
                  onChanged: (v) {
                    setDialog(() => _subtitleDelay = v);
                    if (_player.platform is NativePlayer) {
                      (_player.platform as NativePlayer)
                          .setProperty('sub-delay', v.toString());
                    }
                  },
                ),
              ),
              SizedBox(
                  width: 44,
                  child: Text('${_subtitleDelay.toStringAsFixed(1)}s',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12))),
            ]),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close',
                    style: TextStyle(color: Color(0xFF7C3AED)))),
          ],
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  AUDIO MENU
  // ─────────────────────────────────────────────────────────────────────────

  void _showAudioMenu() {
    final tracks =
        _player.state.tracks.audio.where((t) => t.id != 'no').toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E0E0E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Audio Tracks',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          if (tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No audio tracks found',
                  style: TextStyle(color: Colors.white54)),
            )
          else
            ...tracks.map((t) => ListTile(
                  leading: const Icon(Icons.audiotrack,
                      color: Colors.white70),
                  title: Text(t.title ?? t.language ?? 'Track ${t.id}',
                      style: const TextStyle(color: Colors.white)),
                  trailing: t.id == _player.state.track.audio.id
                      ? const Icon(Icons.check,
                          color: Color(0xFF7C3AED))
                      : null,
                  onTap: () {
                    _player.setAudioTrack(t);
                    Navigator.pop(context);
                  },
                )),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  SOURCE SELECTION (for Amri provider)
  // ─────────────────────────────────────────────────────────────────────────

  void _showSourcesMenu() {
    if (_currentSources == null || _currentSources!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No sources available'),
        duration: Duration(seconds: 1),
      ));
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E0E0E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Video Sources',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _currentSources!.length,
              itemBuilder: (context, index) {
                final source = _currentSources![index];
                final isCurrent = source.url == _currentUrl;
                return ListTile(
                  leading: Icon(
                    Icons.play_circle_outline,
                    color: isCurrent ? const Color(0xFF7C3AED) : Colors.white70,
                  ),
                  title: Text(
                    source.title,
                    style: TextStyle(
                      color: isCurrent ? const Color(0xFF7C3AED) : Colors.white,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    source.type.toUpperCase(),
                    style: TextStyle(
                      color: isCurrent 
                          ? const Color(0xFF7C3AED).withValues(alpha: 0.7)
                          : Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                  trailing: isCurrent
                      ? const Icon(Icons.check, color: Color(0xFF7C3AED))
                      : null,
                  onTap: () async {
                    Navigator.pop(context);
                    if (!isCurrent) {
                      // Save current position
                      final currentPos = _positionNotifier.value;
                      final messenger = ScaffoldMessenger.of(context);

                      // Arabic provider: extract on-demand from embed URL
                      if (_currentProvider == 'arabic' && source.type == 'arabic_embed') {
                        messenger.showSnackBar(SnackBar(
                          content: Text('Extracting ${source.title}...'),
                          duration: const Duration(seconds: 30),
                        ));
                        final result = await ArabicService.extractStreamUrl(source.url);
                        if (!mounted) return;
                        messenger.hideCurrentSnackBar();
                        if (result == null) {
                          messenger.showSnackBar(SnackBar(
                            content: Text('Failed to extract ${source.title}'),
                            duration: const Duration(seconds: 2),
                          ));
                          return;
                        }
                        await _player.open(
                          Media(result.url, httpHeaders: result.headers),
                        );
                        // Update the source entry with the extracted stream URL
                        _currentSources![index] = StreamSource(
                          url: result.url,
                          title: source.title,
                          type: result.url.contains('.m3u8') ? 'hls' : result.url.contains('.mpd') ? 'dash' : 'mp4',
                        );
                        setState(() {
                          _currentUrl = result.url;
                          _currentFallbackSourceIndex = 0;
                          _hasError = false;
                          _errorMessage = '';
                        });
                      } else {
                        // Normal direct switch — use per-source headers if available
                        final srcHeaders = source.headers ?? widget.headers;
                        if (source.headers != null && _player.platform is NativePlayer) {
                          final ref = source.headers!['Referer'] ?? source.headers!['referer'];
                          if (ref != null) await (_player.platform as NativePlayer).setProperty('referrer', ref);
                        }
                        await _player.open(
                          Media(source.url, httpHeaders: srcHeaders),
                        );
                        setState(() {
                          _currentUrl = source.url;
                          _currentFallbackSourceIndex = 0;
                          _hasError = false;
                          _errorMessage = '';
                        });
                      }
                      
                      // Seek to saved position
                      if (currentPos.inSeconds > 0) {
                        await _player.seek(currentPos);
                      }
                      
                      if (mounted) {
                        messenger.showSnackBar(SnackBar(
                          content: Text('Switched to ${source.title}'),
                          duration: const Duration(seconds: 2),
                        ));
                      }
                    }
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _showProviderMenu() {
    if (widget.providers == null || widget.providers!.isEmpty || widget.movie == null) {
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E0E0E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Switch Provider',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.providers!.length,
              itemBuilder: (context, index) {
                final key = widget.providers!.keys.elementAt(index);
                final provider = widget.providers![key];
                final isCurrent = key == _currentProvider;
                return ListTile(
                  leading: Icon(
                    Icons.stream_rounded,
                    color: isCurrent ? const Color(0xFF7C3AED) : Colors.white70,
                  ),
                  title: Text(
                    provider['name'],
                    style: TextStyle(
                      color: isCurrent ? const Color(0xFF7C3AED) : Colors.white,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isCurrent
                      ? const Icon(Icons.check, color: Color(0xFF7C3AED))
                      : null,
                  onTap: () async {
                    Navigator.pop(context);
                    if (!isCurrent) {
                      await _switchProvider(key);
                    }
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _switchProvider(String newProvider) async {
    if (_isSwitchingProvider) return;
    
    setState(() => _isSwitchingProvider = true);
    
    final currentPos = _positionNotifier.value;
    final messenger = ScaffoldMessenger.of(context);
    
    try {
      final provider = widget.providers![newProvider];
      
      messenger.showSnackBar(SnackBar(
        content: Text('Extracting from ${provider['name']}...'),
        duration: const Duration(seconds: 2),
      ));

      String? streamUrl;
      Map<String, String>? headers;
      List<StreamSource>? sources;

      if (newProvider == 'webstreamr' && widget.movie?.imdbId != null) {
        final webStreamr = WebStreamrService();
        final webStreamrSources = await webStreamr.getStreams(
          imdbId: widget.movie!.imdbId!,
          isMovie: widget.movie!.mediaType == 'movie',
          season: widget.selectedSeason,
          episode: widget.selectedEpisode,
        );
        if (webStreamrSources.isNotEmpty) {
          streamUrl = webStreamrSources.first.url;
          sources = webStreamrSources;
        }
      } else {
        final String providerUrl;
        if (widget.movie!.mediaType == 'tv') {
          providerUrl = provider['tv'](
            widget.movie!.id.toString(),
            widget.selectedSeason,
            widget.selectedEpisode,
          );
        } else {
          providerUrl = provider['movie'](widget.movie!.id.toString());
        }
        
        final extractor = StreamExtractor();
        final result = await extractor.extract(providerUrl);
        if (result != null && result.url.isNotEmpty) {
          streamUrl = result.url;
          headers = result.headers;
          sources = result.sources;
        }
      }
      
      if (streamUrl != null && streamUrl.isNotEmpty) {
        await _player.open(
          Media(streamUrl, httpHeaders: headers),
        );
        
        if (currentPos.inSeconds > 0) {
          await _player.seek(currentPos);
        }
        
        setState(() {
          _currentProvider = newProvider;
          _currentSources = sources;
          _currentUrl = streamUrl;
          _currentFallbackSourceIndex = 0; // Reset index on manual switch
          _hasError = false;
          _errorMessage = '';
        });
        
        if (mounted) {
          messenger.showSnackBar(SnackBar(
            content: Text('Switched to ${provider['name']}'),
            duration: const Duration(seconds: 2),
          ));
        }
      } else {
        if (mounted) {
          messenger.showSnackBar(SnackBar(
            content: Text('Failed to extract from ${provider['name']}'),
            duration: const Duration(seconds: 2),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Error switching provider: $e'),
          duration: const Duration(seconds: 2),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _isSwitchingProvider = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  MISC
  // ─────────────────────────────────────────────────────────────────────────

  void _toggleLoop() {
    setState(() => _loopEnabled = !_loopEnabled);
    _player.setPlaylistMode(
        _loopEnabled ? PlaylistMode.single : PlaylistMode.none);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Loop: ${_loopEnabled ? "ON" : "OFF"}'),
        duration: const Duration(seconds: 1)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  NEXT EPISODE
  // ─────────────────────────────────────────────────────────────────────────

  bool get _isNextEpisodeAvailable =>
      widget.movie != null &&
      widget.movie!.mediaType == 'tv' &&
      widget.selectedSeason != null &&
      widget.selectedEpisode != null;

  bool get _showNextEpButton =>
      _isNextEpisodeAvailable && (_nearEndOfEpisode || _isLoadingNextEp);

  Future<void> _nextEpisode() async {
    if (!_isNextEpisodeAvailable || _isLoadingNextEp) return;

    setState(() => _isLoadingNextEp = true);

    try {
      final tmdb = TmdbService();
      final tvId = widget.movie!.id;
      int nextSeason = widget.selectedSeason!;
      int nextEpisode = widget.selectedEpisode! + 1;

      // Check if next episode exists in current season
      final seasonData = await tmdb.getTvSeasonDetails(tvId, nextSeason);
      final episodes = seasonData['episodes'] as List<dynamic>? ?? [];
      final maxEp = episodes.isNotEmpty
          ? episodes.map((e) => e['episode_number'] as int).reduce((a, b) => a > b ? a : b)
          : 0;

      if (nextEpisode > maxEp) {
        // Try next season
        final totalSeasons = await tmdb.getTvSeasonCount(tvId);
        if (nextSeason < totalSeasons) {
          nextSeason++;
          nextEpisode = 1;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No more episodes available')),
            );
          }
          setState(() => _isLoadingNextEp = false);
          return;
        }
      }

      debugPrint('[NextEp] Playing S${nextSeason}E$nextEpisode');

      // Save current watch history before switching
      _saveWatchHistory();

      String? streamUrl;
      String? magnetLink;
      int? fileIndex;
      Map<String, String>? headers;
      String? activeProvider = widget.activeProvider;

      final isTorrent = widget.magnetLink != null &&
          widget.activeProvider != 'stremio_direct';
      final isStremioDirect = widget.activeProvider == 'stremio_direct';
      final isWebStreamr = widget.activeProvider == 'webstreamr';
      final isAmri = widget.activeProvider == 'amri';

      if (isStremioDirect && widget.stremioAddonBaseUrl != null) {
        // ── Stremio addon: re-fetch streams for next episode ──────────
        final stremio = StremioService();
        final stremioId = widget.stremioId ?? widget.movie!.imdbId;
        if (stremioId == null) throw Exception('No Stremio ID available');

        final epId = '$stremioId:$nextSeason:$nextEpisode';
        final streams = await stremio.getStreams(
          baseUrl: widget.stremioAddonBaseUrl!,
          type: 'series',
          id: epId,
        );

        if (streams.isEmpty) throw Exception('No streams found for S${nextSeason}E$nextEpisode');

        final stream = streams.first as Map<String, dynamic>;

        if (stream['url'] != null) {
          streamUrl = stream['url'] as String;
          final proxyHeaders = stream['behaviorHints']?['proxyHeaders']?['request'];
          if (proxyHeaders is Map) {
            headers = Map<String, String>.from(proxyHeaders);
          }
        } else if (stream['infoHash'] != null) {
          // Stremio returned a torrent hash — resolve it
          final infoHash = stream['infoHash'] as String;
          final streamTitle = (stream['title'] ?? stream['name'] ?? '').toString();
          final dn = streamTitle.isNotEmpty ? '&dn=${Uri.encodeComponent(streamTitle)}' : '';
          final sourcesList = stream['sources'];
          final trackerParams = StringBuffer();
          if (sourcesList is List) {
            for (final src in sourcesList) {
              if (src is String && src.startsWith('tracker:')) {
                trackerParams.write('&tr=${Uri.encodeComponent(src.substring(8))}');
              }
            }
          }
          magnetLink = 'magnet:?xt=urn:btih:$infoHash$dn$trackerParams';

          final settings = SettingsService();
          final useDebrid = await settings.useDebridForStreams();
          final debridService = await settings.getDebridService();

          if (useDebrid && debridService != 'None') {
            final debrid = DebridApi();
            final files = debridService == 'Real-Debrid'
                ? await debrid.resolveRealDebrid(magnetLink)
                : await debrid.resolveTorBox(magnetLink);
            if (files.isNotEmpty) {
              final s = 'S${nextSeason.toString().padLeft(2, '0')}';
              final e = 'E${nextEpisode.toString().padLeft(2, '0')}';
              final match = files.where((f) =>
                  f.filename.toUpperCase().contains(s) &&
                  f.filename.toUpperCase().contains(e)).toList();
              if (match.isNotEmpty) {
                fileIndex = files.indexOf(match.first);
                streamUrl = match.first.downloadUrl;
              } else {
                files.sort((a, b) => b.filesize.compareTo(a.filesize));
                streamUrl = files.first.downloadUrl;
              }
            }
          } else {
            streamUrl = await TorrentStreamService().streamTorrent(
              magnetLink,
              season: nextSeason,
              episode: nextEpisode,
            );
            if (streamUrl != null) {
              final idx = Uri.parse(streamUrl).queryParameters['index'];
              if (idx != null) fileIndex = int.tryParse(idx);
            }
          }
          activeProvider = 'torrent';
        }
      } else if (isTorrent) {
        // ── Torrent: re-search for next episode ───────────────────────
        final s = nextSeason.toString().padLeft(2, '0');
        final e = nextEpisode.toString().padLeft(2, '0');
        final query = '${widget.movie!.title} S${s}E$e';
        debugPrint('[NextEp] Searching torrents: $query');

        final torrentApi = TorrentApi();
        final results = await torrentApi.searchTorrents(query);
        final filtered = await TorrentFilter.filterTorrentsAsync(
          results,
          widget.movie!.title,
          requiredSeason: nextSeason,
          requiredEpisode: nextEpisode,
        );

        if (filtered.isEmpty) throw Exception('No torrents found for S${s}E$e');

        // Pick best result (highest seeders)
        filtered.sort((a, b) => b.seeders.compareTo(a.seeders));
        magnetLink = filtered.first.magnet;

        final settings = SettingsService();
        final useDebrid = await settings.useDebridForStreams();
        final debridService = await settings.getDebridService();

        if (useDebrid && debridService != 'None') {
          final debrid = DebridApi();
          final files = debridService == 'Real-Debrid'
              ? await debrid.resolveRealDebrid(magnetLink)
              : await debrid.resolveTorBox(magnetLink);
          if (files.isNotEmpty) {
            final sStr = 'S${s}';
            final eStr = 'E${e}';
            final match = files.where((f) =>
                f.filename.toUpperCase().contains(sStr) &&
                f.filename.toUpperCase().contains(eStr)).toList();
            if (match.isNotEmpty) {
              fileIndex = files.indexOf(match.first);
              streamUrl = match.first.downloadUrl;
            } else {
              files.sort((a, b) => b.filesize.compareTo(a.filesize));
              streamUrl = files.first.downloadUrl;
            }
          }
        } else {
          streamUrl = await TorrentStreamService().streamTorrent(
            magnetLink,
            season: nextSeason,
            episode: nextEpisode,
          );
          if (streamUrl != null) {
            final idx = Uri.parse(streamUrl).queryParameters['index'];
            if (idx != null) fileIndex = int.tryParse(idx);
          }
        }
      } else if (isWebStreamr) {
        // ── WebStreamr: fetch next episode streams ────────────────────
        final imdbId = widget.movie!.imdbId;
        if (imdbId == null || imdbId.isEmpty) throw Exception('No IMDB ID for WebStreamr');

        final webStreamr = WebStreamrService();
        final sources = await webStreamr.getStreams(
          imdbId: imdbId,
          isMovie: false,
          season: nextSeason,
          episode: nextEpisode,
        );
        if (sources.isEmpty) throw Exception('No WebStreamr sources for S${nextSeason}E$nextEpisode');
        streamUrl = sources.first.url;
      } else if (isAmri) {
        // ── AMRI: re-extract for next episode ─────────────────────────
        final extractor = StreamExtractor();
        final result = await extractor.extractWithAmri(
          tmdbId: widget.movie!.id.toString(),
          isMovie: false,
          season: nextSeason,
          episode: nextEpisode,
        );
        if (result == null) throw Exception('AMRI extraction failed for S${nextSeason}E$nextEpisode');
        streamUrl = result.url;
        headers = result.headers.isNotEmpty ? result.headers : null;
      } else if (widget.activeProvider != null) {
        // ── Stream provider (vidlink, vixsrc, etc.) ───────────────────
        final provider = StreamProviders.providers[widget.activeProvider];
        if (provider == null || provider['tv'] == null) {
          throw Exception('Provider ${widget.activeProvider} does not support TV');
        }

        final providerUrl = provider['tv'](
          widget.movie!.id.toString(),
          nextSeason,
          nextEpisode,
        );
        final extractor = StreamExtractor();
        final result = await extractor.extract(providerUrl, timeout: const Duration(seconds: 20));
        if (result == null) throw Exception('Extraction failed for S${nextSeason}E$nextEpisode');
        streamUrl = result.url;
        headers = result.headers.isNotEmpty ? result.headers : null;
      }

      if (streamUrl == null || streamUrl.isEmpty) {
        throw Exception('Could not find stream for S${nextSeason}E$nextEpisode');
      }

      if (!mounted) return;

      // Navigate to new player with next episode
      final nextTitle = '${widget.movie!.title} - S$nextSeason E$nextEpisode';
      final navigator = Navigator.of(context);
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            streamUrl: streamUrl!,
            title: nextTitle,
            headers: headers,
            movie: widget.movie,
            selectedSeason: nextSeason,
            selectedEpisode: nextEpisode,
            magnetLink: magnetLink,
            fileIndex: fileIndex,
            activeProvider: activeProvider,
            stremioId: widget.stremioId,
            stremioAddonBaseUrl: widget.stremioAddonBaseUrl,
            providers: widget.providers,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NextEp] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Next episode error: $e')),
        );
        setState(() => _isLoadingNextEp = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _exitPlayer();
      },
      child: Theme(
        data: ThemeData.dark(),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Video ─────────────────────────────────────────────────
              Video(
                controller: _controller,
                controls: NoVideoControls,
                fit: _videoFit,
                fill: Colors.black,
                subtitleViewConfiguration: SubtitleViewConfiguration(
                  style: TextStyle(
                    height: 1.4,
                    fontSize: _subtitleSize,
                    letterSpacing: 0.0,
                    wordSpacing: 0.0,
                    color: Colors.white,
                    fontWeight: FontWeight.normal,
                    backgroundColor: const Color(0xAA000000),
                    shadows: const [
                      Shadow(
                          blurRadius: 10,
                          color: Colors.black,
                          offset: Offset.zero)
                    ],
                  ),
                  textAlign: TextAlign.center,
                  padding: EdgeInsets.fromLTRB(
                      24, 0, 24, _subtitleBottomPadding),
                ),
              ),

              // ── 2. Gesture layer ─────────────────────────────────────────
              LayoutBuilder(builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onDoubleTapDown: (d) {
                    _handleDoubleTap(
                        d, d.localPosition.dx > constraints.maxWidth / 2);
                  },
                  onVerticalDragUpdate: (d) =>
                      _onVerticalDragUpdate(d, constraints.maxWidth),
                  onLongPressStart: (_) {
                    if (!_isLocked) _player.setRate(2.0);
                  },
                  onLongPressEnd: (_) {
                    if (!_isLocked) _player.setRate(1.0);
                  },
                  child: Container(color: Colors.transparent),
                );
              }),

              // ── 3. Double-tap ripple ──────────────────────────────────────
              if (_showRipple)
                Positioned(
                  left: _isForward
                      ? null
                      : _ripplePosition.dx - 50,
                  right: _isForward
                      ? (MediaQuery.of(context).size.width -
                              _ripplePosition.dx) -
                          50
                      : null,
                  top: _ripplePosition.dy - 50,
                  child: IgnorePointer(
                    child: FadeTransition(
                      opacity: _rippleOpacity,
                      child: ScaleTransition(
                        scale: _rippleScale,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              _isForward ? '+10s' : '-10s',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── 4. Controls overlay ───────────────────────────────────────
              AnimatedOpacity(
                opacity: (_showControls && !_isLocked) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !(_showControls && !_isLocked),
                  child: _buildControlsOverlay(),
                ),
              ),

              // ── 5. Lock button (always visible when locked + controls shown)
              if (_isLocked)
                Positioned(
                  bottom:
                      MediaQuery.of(context).padding.bottom + 72,
                  left: 12,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: _GlassIconButton(
                      icon: Icons.lock_rounded,
                      onPressed: _toggleLock,
                      iconColor: Colors.amber,
                    ),
                  ),
                ),

              // ── 6. Volume indicator ───────────────────────────────────────
              if (_showVolumeIndicator)
                Positioned(
                  right: 20,
                  top: 0, bottom: 0,
                  child: Center(
                      child: _SideIndicator(
                          icon: Icons.volume_up_rounded,
                          value: _volume / 150.0)),
                ),

              // ── 7. Brightness indicator ───────────────────────────────────
              if (_showBrightnessIndicator)
                Positioned(
                  left: 20,
                  top: 0, bottom: 0,
                  child: Center(
                      child: _SideIndicator(
                          icon: Icons.light_mode_rounded,
                          value: _brightness)),
                ),

              // ── 8. Next Episode Overlay ──────────────────────────────
              if (_showNextEpButton)
                Positioned(
                  bottom: 120,
                  right: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoadingNextEp ? null : _nextEpisode,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (_isLoadingNextEp)
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                            )
                          else
                            const Text(
                              'Next Episode',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded,
                              color: Colors.white, size: 18),
                        ]),
                      ),
                    ),
                  ),
                ),

              // ── 9. Embedded Error Overlay ───────────────────────────────
              if (_hasError) _buildEmbeddedError(),
              ],
              ),
              ),
              ),
              );
              }

              Widget _buildEmbeddedError() {
              return Container(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
              'Playback Failed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              ),
              const SizedBox(height: 8),
              Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GlassPillButton(
                    text: 'Retry',
                    onTap: _initPlayback,
                  ),
                  if (_currentProvider == 'arabic' && _currentSources != null && _currentSources!.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    _GlassPillButton(
                      text: 'Switch Source',
                      onTap: _showSourcesMenu,
                    ),
                  ],
                  const SizedBox(width: 12),
                  _GlassPillButton(
                    text: 'Switch Provider',
                    onTap: _showProviderMenu,
                  ),
                ],
              ),              ],
              ),
              ),
              );
              }

  Widget _buildControlsOverlay() {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final btnSize = isPortrait ? 34.0 : 40.0;
    final iconSz = isPortrait ? 16.0 : 18.0;
    final gap = isPortrait ? 4.0 : 6.0;

    return Stack(children: [
      // ── Gradients ────────────────────────────────────────────────────────
      const Positioned(
          top: 0, left: 0, right: 0,
          child: _OverlayGradient(isTop: true)),
      const Positioned(
          bottom: 0, left: 0, right: 0,
          child: _OverlayGradient(isTop: false)),

      // ── TOP BAR ──────────────────────────────────────────────────────────
      Positioned(
        top: 0, left: 0, right: 0,
        child: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              _GlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onPressed: _exitPlayer,
                size: btnSize, iconSize: iconSz,
              ),
              SizedBox(width: isPortrait ? 6 : 10),
              // Title pill
              Expanded(
                child: _BlurGlass(               // ← blur OK, only 1
                  radius: 20,
                  padding: EdgeInsets.symmetric(
                      horizontal: isPortrait ? 10 : 14, vertical: 8),
                  child: Text(
                    widget.title,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: isPortrait ? 12 : 13,
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox(width: gap),
              // HW mode badge
              if (!isPortrait)
                _GlassPillButton(
                  text: _hwDecMode.label,
                  onTap: _cycleHwDec,
                  accent: _hwDecMode.accent,
                ),
              if (!isPortrait) SizedBox(width: gap),
              _GlassIconButton(
                icon: Icons.music_note_outlined,
                onPressed: _showAudioMenu,
                size: btnSize, iconSize: iconSz,
              ),
              SizedBox(width: gap),
              _GlassIconButton(
                icon: Icons.subtitles_outlined,
                onPressed: _showSubtitlesMenu,
                size: btnSize, iconSize: iconSz,
              ),
              // Show sources button for providers with multiple sources
              if ((_currentProvider == 'amri' || _currentProvider == 'webstreamr' || _currentProvider == 'arabic') && _currentSources != null && _currentSources!.isNotEmpty) ...[
                SizedBox(width: gap),
                _GlassIconButton(
                  icon: Icons.video_library_outlined,
                  onPressed: _showSourcesMenu,
                  size: btnSize, iconSize: iconSz,
                ),
              ],
            ]),
          ),
        ),
      ),

      // ── CENTER PLAY/PAUSE ─────────────────────────────────────────────────
      Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: _isBufferingNotifier,
          builder: (context, buffering, _) =>
              ValueListenableBuilder<bool>(
            valueListenable: _isPlayingNotifier,
            builder: (context, playing, _) => _GlassPlayPause(
              isPlaying: playing,
              isBuffering: buffering,
              onPressed: () {
                playing ? _player.pause() : _player.play();
                _startHideTimer();
              },
            ),
          ),
        ),
      ),

      // ── BOTTOM SECTION ────────────────────────────────────────────────────
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child:
                Column(mainAxisSize: MainAxisSize.min, children: [
              // ── Icon row ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: lock / speed / loop (+ HW badge in portrait)
                  Row(children: [
                    _GlassIconButton(
                      icon: _isLocked
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      onPressed: _toggleLock,
                      active: _isLocked,
                      size: btnSize, iconSize: iconSz,
                    ),
                    SizedBox(width: gap),
                    _GlassIconButton(
                      icon: Icons.speed_outlined,
                      onPressed: () => showSpeedMenu(
                          context,
                          _player.state.rate,
                          (s) => _player.setRate(s)),
                      size: btnSize, iconSize: iconSz,
                    ),
                    SizedBox(width: gap),
                    _GlassIconButton(
                      icon: _loopEnabled
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      onPressed: _toggleLoop,
                      active: _loopEnabled,
                      size: btnSize, iconSize: iconSz,
                    ),
                    if (isPortrait) ...[
                      SizedBox(width: gap),
                      _GlassPillButton(
                        text: _hwDecMode.label,
                        onTap: _cycleHwDec,
                        accent: _hwDecMode.accent,
                      ),
                    ],
                  ]),

                  // Right: copy URL / subtitle settings / aspect ratio / provider switcher
                  Row(children: [
                    // Show provider switcher only when providers are available and not using torrent/stremio
                    if (widget.providers != null && widget.providers!.isNotEmpty && 
                        widget.magnetLink == null && widget.activeProvider != 'stremio_direct') ...[
                      _GlassIconButton(
                        icon: Icons.swap_horiz_rounded,
                        onPressed: _isSwitchingProvider ? () {} : _showProviderMenu,
                        size: btnSize, iconSize: iconSz,
                      ),
                      SizedBox(width: gap),
                    ],
                    _GlassIconButton(
                      icon: Icons.link_rounded,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: widget.mediaPath));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Stream URL copied to clipboard')),
                          );
                        }
                      },
                      size: btnSize, iconSize: iconSz,
                    ),
                    SizedBox(width: gap),
                    // Aspect ratio pill — shows current mode
                    _GlassPillButton(
                      text: _videoFitLabel,
                      onTap: _cycleAspectRatio,
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 8),

              // ── Seekbar row ───────────────────────────────────────────
              Row(children: [
                ValueListenableBuilder<Duration>(
                  valueListenable: _positionNotifier,
                  builder: (context, pos, _) => SizedBox(
                    width: 56,
                    child: Text(
                      formatDuration(pos),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontFamily: 'monospace'),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: _durationNotifier,
                    builder: (context, duration, _) =>
                        ValueListenableBuilder<Duration>(
                      valueListenable: _positionNotifier,
                      builder: (context, position, _) =>
                          ValueListenableBuilder<Duration>(
                        valueListenable: _bufferedNotifier,
                        builder: (context, buffered, _) =>
                            _MobileSeekbar(
                          duration: duration,
                          position: position,
                          bufferedPosition: buffered,
                          onSeek: (t) {
                            _player.seek(t);
                            _startHideTimer();
                          },
                          onDragStart: () => _hideTimer?.cancel(),
                          onDragEnd: _startHideTimer,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<Duration>(
                  valueListenable: _durationNotifier,
                  builder: (context, dur, _) => SizedBox(
                    width: 56,
                    child: Text(
                      formatDuration(dur),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }

}

// ─────────────────────────────────────────────────────────────────────────────
//  MOBILE SEEKBAR  — touch-friendly, no tooltip (no hover on mobile)
// ─────────────────────────────────────────────────────────────────────────────

class _MobileSeekbar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final void Function(Duration) onSeek;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  const _MobileSeekbar({
    required this.duration,
    required this.position,
    required this.bufferedPosition,
    required this.onSeek,
    required this.onDragStart,
    required this.onDragEnd,
  });

  @override
  State<_MobileSeekbar> createState() => _MobileSeekbarState();
}

class _MobileSeekbarState extends State<_MobileSeekbar> {
  bool _isDragging = false;
  double _dragFrac = 0.0;
  double _trackWidth = 0.0;

  double get _playFrac {
    final total = widget.duration.inMilliseconds.toDouble();
    if (total <= 0) return 0;
    if (_isDragging) return _dragFrac;
    return (widget.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  double get _bufFrac {
    final total = widget.duration.inMilliseconds.toDouble();
    if (total <= 0) return 0;
    return (widget.bufferedPosition.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Duration get _dragTime {
    final total = widget.duration.inMilliseconds.toDouble();
    return Duration(milliseconds: (_dragFrac * total).round());
  }

  double _fracFromLocal(double dx) =>
      (dx / _trackWidth).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) {
        widget.onDragStart();
        setState(() {
          _isDragging = true;
          _dragFrac = _fracFromLocal(d.localPosition.dx);
        });
      },
      onHorizontalDragUpdate: (d) => setState(() {
        _dragFrac = _fracFromLocal(d.localPosition.dx);
      }),
      onHorizontalDragEnd: (_) {
        final total = widget.duration.inMilliseconds.toDouble();
        widget.onSeek(
            Duration(milliseconds: (_dragFrac * total).round()));
        widget.onDragEnd();
        setState(() => _isDragging = false);
      },
      onTapUp: (d) {
        final total = widget.duration.inMilliseconds.toDouble();
        widget.onSeek(Duration(
            milliseconds:
                (_fracFromLocal(d.localPosition.dx) * total).round()));
      },
      // 32px tall hit area — much easier to grab on touch
      child: SizedBox(
        height: 32,
        child: Align(
          alignment: Alignment.center,
          child: LayoutBuilder(builder: (context, constraints) {
            _trackWidth = constraints.maxWidth;

            final trackH = _isDragging ? 6.0 : 3.5;
            final thumbR = _isDragging ? 8.0 : 5.5;
            final playPx =
                (_playFrac * _trackWidth).clamp(0.0, _trackWidth);

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                // Background
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  height: trackH,
                  width: _trackWidth,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(trackH),
                  ),
                ),
                // Buffered
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: trackH,
                  width: (_bufFrac * _trackWidth).clamp(0.0, _trackWidth),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(trackH),
                  ),
                ),
                // Played
                AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  curve: Curves.easeOut,
                  height: trackH,
                  width: playPx,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(trackH),
                  ),
                ),
                // Thumb dot
                Positioned(
                  left: playPx - thumbR,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 130),
                    curve: Curves.easeOut,
                    width: thumbR * 2,
                    height: thumbR * 2,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: _isDragging
                          ? [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.35),
                                blurRadius: 8,
                              )
                            ]
                          : [],
                    ),
                  ),
                ),
                // Drag time label — floats above thumb while dragging
                if (_isDragging &&
                    widget.duration.inMilliseconds > 0)
                  Positioned(
                    left: (playPx - 36).clamp(
                        0.0, _trackWidth - 72),
                    top: -34,
                    child: _BlurGlass(           // ← blur OK, only while dragging
                      radius: 8,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: SizedBox(
                        width: 56,
                        child: Text(
                          formatDuration(_dragTime),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SIDE INDICATOR  (volume / brightness vertical pill)
// ─────────────────────────────────────────────────────────────────────────────

/// Replaces VolumeBrightnessIndicator from shared_widgets — self-contained.
class _SideIndicator extends StatelessWidget {
  final IconData icon;
  final double value; // 0.0 – 1.0

  const _SideIndicator({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return _BlurGlass(                               // ← blur OK, shown 1 at a time
      radius: 20,
      child: SizedBox(
        width: 44,
        height: 160,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 6),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                child: RotatedBox(
                  quarterTurns: -1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value.clamp(0.0, 1.0),
                      backgroundColor: Colors.white24,
                      color: Colors.white,
                      minHeight: 4,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${(value * 100).round()}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}