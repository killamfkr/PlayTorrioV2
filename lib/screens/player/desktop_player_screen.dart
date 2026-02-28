import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'utils.dart';
import 'menus.dart';

import '../../models/movie.dart';
import '../../models/stream_source.dart';
import '../../api/subtitle_api.dart';
import '../../api/torr_server_service.dart';
import '../../api/stream_extractor.dart';
import '../../services/watch_history_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  GLASSY WIDGET PRIMITIVES  (MPVEx-style frosted black glass)
// ─────────────────────────────────────────────────────────────────────────────

/// A rounded glassy container – the visual base for every button / chip.
/// [hovered] brightens the glass slightly for Windows hover feedback.
class _Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final bool hovered;

  const _Glass({
    required this.child,
    this.radius = 12,
    this.padding,
    this.tint,
    this.hovered = false,
  });

  @override
  Widget build(BuildContext context) {
    // Base fill: 0.55 so the glass reads clearly even on pure black.
    // On hover bump to 0.72 for a crisp lift effect.
    final fillOpacity = hovered ? 0.72 : 0.55;
    final borderOpacity = hovered ? 0.30 : 0.16;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            // Layered fill: tint + a constant white shimmer so it's never
            // invisible even when the video behind it is also black.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                (tint ?? const Color(0xFF1C1C1E)).withValues(alpha: fillOpacity),
                (tint ?? Colors.black).withValues(alpha: fillOpacity - 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: borderOpacity),
              width: 0.8,
            ),
            // Subtle box-shadow so button lifts off the background
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: hovered ? 0.55 : 0.35),
                blurRadius: hovered ? 12 : 6,
                spreadRadius: 0,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Glassy icon button with hover + press feedback (Windows-friendly).
class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final bool active;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 38,
    this.iconSize = 18,
    this.iconColor,
    this.active = false,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  Color get _tint {
    if (widget.active) return const Color(0xFF6A0DAD);
    if (_pressed)      return const Color(0xFF2A2A2E);
    return const Color(0xFF1C1C1E);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() { _hovered = false; _pressed = false; }),
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp:   (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: _Glass(
            radius: widget.size / 2,
            tint: _tint,
            hovered: _hovered,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: widget.iconColor ??
                    (widget.active
                        ? Colors.white
                        : _hovered
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.80)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glassy pill / chip button with hover + press feedback.
class GlassPillButton extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  final Color? accent;

  const GlassPillButton({
    super.key,
    required this.text,
    required this.onTap,
    this.accent,
  });

  @override
  State<GlassPillButton> createState() => _GlassPillButtonState();
}

class _GlassPillButtonState extends State<GlassPillButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() { _hovered = false; _pressed = false; }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) => setState(() => _pressed = false),
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.90 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: _Glass(
            radius: 20,
            tint: widget.accent ?? const Color(0xFF1C1C1E),
            hovered: _hovered,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              widget.text,
              style: TextStyle(
                color: widget.accent != null
                    ? Colors.white
                    : _hovered
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.80),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Center play/pause big button with hover + press feedback.
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
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isBuffering) {
      return _Glass(
        radius: 40,
        hovered: false,
        child: const SizedBox(
          width: 80,
          height: 80,
          child: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() { _hovered = false; _pressed = false; }),
      child: GestureDetector(
        onTap: widget.onPressed,
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) => setState(() => _pressed = false),
        onTapCancel: ()  => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.88 : (_hovered ? 1.08 : 1.0),
          duration: const Duration(milliseconds: 100),
          child: _Glass(
            radius: 40,
            hovered: _hovered,
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
      ),
    );
  }
}

/// Gradient overlay at top or bottom of the video
class _OverlayGradient extends StatelessWidget {
  final bool isTop;
  const _OverlayGradient({required this.isTop});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
          end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HARDWARE DECODE MODE
// ─────────────────────────────────────────────────────────────────────────────

enum _HwDecMode {
  /// auto-safe: whitelisted GPU decoders, safe fallback chain. Best for most users.
  autoSafe,

  /// auto-copy: GPU decodes → copies back to RAM. Compatible with video filters.
  autoCopy,

  /// no: pure software/CPU decoding. Always works, highest CPU, most compatible.
  software,
}

extension _HwDecModeX on _HwDecMode {
  String get mpvValue => switch (this) {
        _HwDecMode.autoSafe => 'auto-safe',
        _HwDecMode.autoCopy => 'auto-copy',
        _HwDecMode.software => 'no',
      };

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
        _HwDecMode.software => Colors.white24,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
//  DESKTOP PLAYER SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class DesktopPlayerScreen extends StatefulWidget {
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

  const DesktopPlayerScreen({
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
  State<DesktopPlayerScreen> createState() => _DesktopPlayerScreenState();
}

class _DesktopPlayerScreenState extends State<DesktopPlayerScreen>
    with WindowListener, WidgetsBindingObserver {
  // ── Player ──────────────────────────────────────────────────────────────
  late final Player _player;
  late final VideoController _controller;
  bool _disposed = false;
  bool _hasError = false;
  String _errorMessage = '';

  // ── UI State ─────────────────────────────────────────────────────────────
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isFullscreen = false;
  BoxFit _videoFit = BoxFit.contain;

  // ── Resume State ─────────────────────────────────────────────────────────
  bool _hasInitialSeek = false;

  // ── Stream Subscriptions ─────────────────────────────────────────────────
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;

  // ── Value Notifiers (rebuild only what's needed, no full setState) ────────
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _bufferedNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isBufferingNotifier = ValueNotifier(false);
  final ValueNotifier<double> _volumeNotifier = ValueNotifier(100.0);

  // ── Subtitles ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _externalSubtitles = [];
  bool _isFetchingSubs = false;

  // ── Provider switching ────────────────────────────────────────────────────
  String? _currentProvider;
  bool _isSwitchingProvider = false;

  // ── Feature State ────────────────────────────────────────────────────────
  _HwDecMode _hwDecMode = _HwDecMode.autoSafe;
  bool _loopEnabled = false;
  double _subtitleDelay = 0.0;
  double _subtitleSize = 44.0;
  // ignore: unused_field
  final double _subtitleBottomPadding = 24.0;

  // ─────────────────────────────────────────────────────────────────────────
  //  LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    
    // ── Provider initialization ──────────────────────────────────────────
    _currentProvider = widget.activeProvider;
    
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);

    // ── Create player with minimal overhead config ────────────────────────
    _player = Player(
      configuration: const PlayerConfiguration(
        // Silence noisy logs; use MPVLogLevel.warn for prod
        logLevel: MPVLogLevel.warn,
        // We render our own subtitles via Flutter SubtitleViewConfiguration
        libass: false,
      ),
    );

    // ── VideoController: force hardware-accelerated texture output ─────────
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initPlayback();
      _startHideTimer();
      _fetchSubtitles();
    });
  }

  @override
  void dispose() {
    // ── Save watch history before anything else ───────────────────────────
    _saveWatchHistory();

    _disposed = true;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();

    // Cancel all subscriptions
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _volumeSub?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();

    // Dispose value notifiers
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _bufferedNotifier.dispose();
    _isPlayingNotifier.dispose();
    _isBufferingNotifier.dispose();
    _volumeNotifier.dispose();

    _player.dispose();

    // Cleanup torrent from engine (no-op if not a torrent stream)
    TorrServerService().removeTorrent(widget.mediaPath);

    super.dispose();
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
    if (widget.movie == null) return;
    final pos = _positionNotifier.value.inMilliseconds;
    final dur = _durationNotifier.value.inMilliseconds;
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
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PLAYBACK INITIALIZATION
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initPlayback() async {
    if (_disposed) return;
    
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      try {
        _subscribeToStreams();
        await _configureMpvProperties();
        await _player.open(
          Media(widget.mediaPath, httpHeaders: widget.headers),
        );
        return; // Success, exit
      } catch (e) {
        retryCount++;
        debugPrint('[Player] Open failed (attempt $retryCount/$maxRetries): $e');
        
        if (retryCount < maxRetries) {
          // Wait before retry with exponential backoff
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        } else {
          // All retries failed, show error
          if (!mounted || _disposed) return;
          setState(() {
            _hasError = true;
            _errorMessage = e.toString();
          });
        }
      }
    }
  }

  void _subscribeToStreams() {
    // Position – drives seekbar & watch-history
    _positionSub = _player.stream.position.listen((pos) {
      if (_disposed) return;
      _positionNotifier.value = pos;
    });

    // Duration – triggers auto-resume on first valid duration
    _durationSub = _player.stream.duration.listen((dur) {
      if (_disposed) return;
      _durationNotifier.value = dur;
      if (!_hasInitialSeek && dur.inSeconds > 0 && widget.startPosition != null) {
        _hasInitialSeek = true;
        _player.seek(widget.startPosition!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Resumed from ${formatDuration(widget.startPosition!)}'),
            duration: const Duration(seconds: 2),
          ));
        }
      }
    });

    // Buffered position – shows how far ahead is cached
    _bufferSub = _player.stream.buffer.listen((buf) {
      if (_disposed) return;
      _bufferedNotifier.value = buf;
    });

    // Playing state
    _playingSub = _player.stream.playing.listen((playing) {
      if (_disposed) return;
      _isPlayingNotifier.value = playing;
      if (playing) _startHideTimer();
    });

    // Buffering spinner
    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (_disposed) return;
      _isBufferingNotifier.value = buffering;
    });

    // Volume sync (e.g. hardware media keys)
    _volumeSub = _player.stream.volume.listen((vol) {
      if (_disposed) return;
      _volumeNotifier.value = vol;
    });

    // Error recovery – log & surface to UI
    _errorSub = _player.stream.error.listen((err) {
      if (_disposed || err.isEmpty) return;
      debugPrint('🔴 Player error: $err');
      
      // Ignore audio decoder errors (user can switch to alternate audio track)
      if (err.contains('Failed to initialize a decoder for codec')) {
        debugPrint('⚠️ Audio codec not supported, continuing with video only');
        return;
      }
      
      // Only surface fatal errors to UI (connection failures are often transient)
      if (err.contains('Failed') || err.contains('No such file')) {
        if (mounted) setState(() { _hasError = true; _errorMessage = err; });
      }
    });

    // Completion – could trigger next-episode logic here in the future
    _completedSub = _player.stream.completed.listen((completed) {
      if (_disposed || !completed) return;
      debugPrint('✅ Playback completed');
    });
  }

  Future<void> _configureMpvProperties() async {
    if (_player.platform is! NativePlayer) return;
    final mpv = _player.platform as NativePlayer;

    // ── Decoding ─────────────────────────────────────────────────────────
    // auto-safe: tries whitelisted GPU decoders, falls back gracefully.
    // This is the officially recommended hwdec mode by mpv developers.
    await mpv.setProperty('hwdec', _hwDecMode.mpvValue);

    // Zero-copy direct rendering from decoder to GPU texture when possible.
    // Reduces RAM usage and improves throughput, especially on 4K/HEVC.
    await mpv.setProperty('vd-lavc-dr', 'yes');

    // Let mpv pick the optimal thread count automatically (0 = auto).
    await mpv.setProperty('vd-lavc-threads', '0');

    // ── Audio Codec Fallback ──────────────────────────────────────────────
    // Continue playback even if audio codec is unsupported (e.g., TrueHD).
    // User can switch to alternate audio track from the menu.
    await mpv.setProperty('ad-lavc-downmix', 'no');
    await mpv.setProperty('audio-fallback-to-null', 'yes');

    // Disable built-in OSD / subtitle rendering – Flutter renders them.
    await mpv.setProperty('sub-visibility', 'no');
    await mpv.setProperty('sub-auto', 'all');

    // ── Video Sync & Smoothness ───────────────────────────────────────────
    // display-resample: syncs to the monitor's refresh rate, eliminates judder.
    // This is the best sync mode for desktop displays.
    await mpv.setProperty('video-sync', 'display-resample');

    // Temporal interpolation to smooth out frame pacing between display frames.
    // Significantly reduces judder on 24fps content on 60Hz+ monitors.
    await mpv.setProperty('interpolation', 'yes');
    await mpv.setProperty('tscale', 'oversample'); // lightweight interpolation

    // ── Network / Streaming ───────────────────────────────────────────────
    await mpv.setProperty('network-timeout', '30');
    await mpv.setProperty('tls-verify', 'no'); // for self-signed / CDN certs

    // Cache: 300 MB in memory, read 120 s ahead.
    // This dramatically reduces rebuffering on variable-bitrate streams.
    await mpv.setProperty('cache', 'yes');
    await mpv.setProperty('cache-secs', '120');
    await mpv.setProperty('demuxer-max-bytes', '300MiB');
    await mpv.setProperty('demuxer-readahead-secs', '120');

    // How far back the demuxer keeps decoded data (for backward seeks).
    await mpv.setProperty('demuxer-max-back-bytes', '50MiB');

    // Prevent yt-dlp from being invoked (we supply our own URL).
    await mpv.setProperty('ytdl', 'no');

    // ── Volume ────────────────────────────────────────────────────────────
    // Allow boosting volume above 100% (up to 150%) for quiet sources.
    await mpv.setProperty('volume-max', '150');

    // ── External Audio Track ──────────────────────────────────────────────
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
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  HARDWARE DECODE CYCLE
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
  //  SUBTITLE MANAGEMENT
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E0E0E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8),
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(builder: (context, setModalState) {
          final current = _player.state.track.subtitle;

          final embedded = _player.state.tracks.subtitle.where((t) {
            final isExternal = t.id.startsWith('http');
            final matchesSearch = searchQuery.isEmpty ||
                (t.title?.toLowerCase().contains(searchQuery.toLowerCase()) ??
                    false) ||
                (t.language?.toLowerCase().contains(searchQuery.toLowerCase()) ??
                    false);
            return t.id != 'no' && !isExternal && matchesSearch;
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 0),
                  ),
                  onChanged: (v) => setModalState(() => searchQuery = v),
                ),
              ),
              if (_isFetchingSubs)
                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        ? const Icon(Icons.check,
                            color: Color(0xFF7C3AED))
                        : null,
                    onTap: () {
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
                      final sel = t.id == current.id;
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
                      final sel = s['url'] == current.id;
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
      builder: (context) => StatefulBuilder(builder: (context, setDialog) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121212),
          title: const Text('Subtitle Settings',
              style: TextStyle(color: Colors.white)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Size ──────────────────────────────────────────────────────
            Row(children: [
              const SizedBox(
                  width: 60,
                  child: Text('Size',
                      style: TextStyle(color: Colors.white70))),
              Expanded(
                child: Slider(
                  value: _subtitleSize,
                  min: 20, max: 80,
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
            // ── Delay ─────────────────────────────────────────────────────
            Row(children: [
              const SizedBox(
                  width: 60,
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
  //  AUDIO
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
                  title: Text(
                      t.title ?? t.language ?? 'Track ${t.id}',
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
    if (widget.sources == null || widget.sources!.isEmpty) {
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
              itemCount: widget.sources!.length,
              itemBuilder: (context, index) {
                final source = widget.sources![index];
                final isCurrent = source.url == widget.mediaPath;
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
                      
                      // Switch to new source
                      await _player.open(
                        Media(source.url, httpHeaders: widget.headers),
                      );
                      
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

  // ─────────────────────────────────────────────────────────────────────────
  //  MISC CONTROLS
  // ─────────────────────────────────────────────────────────────────────────

  void _toggleLoop() {
    setState(() => _loopEnabled = !_loopEnabled);
    _player.setPlaylistMode(
        _loopEnabled ? PlaylistMode.single : PlaylistMode.none);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Loop: ${_loopEnabled ? "ON" : "OFF"}'),
        duration: const Duration(seconds: 1)));
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
      final String url;
      
      if (widget.movie!.mediaType == 'tv') {
        url = provider['tv'](
          widget.movie!.id.toString(),
          widget.selectedSeason,
          widget.selectedEpisode,
        );
      } else {
        url = provider['movie'](widget.movie!.id.toString());
      }
      
      messenger.showSnackBar(SnackBar(
        content: Text('Extracting from ${provider['name']}...'),
        duration: const Duration(seconds: 2),
      ));
      
      final extractor = StreamExtractor();
      final result = await extractor.extract(url);
      
      if (result != null && result.url.isNotEmpty) {
        await _player.open(
          Media(result.url, httpHeaders: result.headers),
        );
        
        if (currentPos.inSeconds > 0) {
          await _player.seek(currentPos);
        }
        
        setState(() {
          _currentProvider = newProvider;
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
  //  UI AUTO-HIDE
  // ─────────────────────────────────────────────────────────────────────────

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_isPlayingNotifier.value) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_disposed) setState(() => _showControls = false);
    });
  }

  void _onMouseMove() {
    if (!_showControls) setState(() => _showControls = true);
    _startHideTimer();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  FULLSCREEN
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _toggleFullscreen() async {
    final isFull = await windowManager.isFullScreen();
    if (!isFull && await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    await windowManager.setFullScreen(!isFull);
    if (mounted) setState(() => _isFullscreen = !isFull);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  KEYBOARD SHORTCUTS
  // ─────────────────────────────────────────────────────────────────────────

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    _onMouseMove();

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space) {
      _player.playOrPause();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      final delta = HardwareKeyboard.instance.isShiftPressed
          ? const Duration(seconds: -30)
          : const Duration(seconds: -5);
      var newPos = _positionNotifier.value + delta;
      if (newPos < Duration.zero) newPos = Duration.zero;
      if (newPos > _durationNotifier.value) newPos = _durationNotifier.value;
      _player.seek(newPos);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      final delta = HardwareKeyboard.instance.isShiftPressed
          ? const Duration(seconds: 30)
          : const Duration(seconds: 5);
      var newPos = _positionNotifier.value + delta;
      if (newPos < Duration.zero) newPos = Duration.zero;
      if (newPos > _durationNotifier.value) newPos = _durationNotifier.value;
      _player.seek(newPos);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _player.setVolume((_volumeNotifier.value + 5).clamp(0, 150));
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _player.setVolume((_volumeNotifier.value - 5).clamp(0, 150));
    } else if (key == LogicalKeyboardKey.keyM) {
      _player.setVolume(_volumeNotifier.value > 0 ? 0.0 : 100.0);
    } else if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (key == LogicalKeyboardKey.escape) {
      windowManager.setFullScreen(false);
      if (mounted) setState(() => _isFullscreen = false);
    } else if (key == LogicalKeyboardKey.keyL) {
      _toggleLoop();
    } else {
      return false;
    }
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  ASPECT RATIO CYCLE
  // ─────────────────────────────────────────────────────────────────────────

  /// Short label shown on the pill button for the current fit mode.
  String get _videoFitLabel => switch (_videoFit) {
        BoxFit.contain => 'FIT',
        BoxFit.cover   => 'CROP',
        BoxFit.fill    => 'FILL',
        _              => 'FIT',
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
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_hasError) return _buildErrorScreen();

    return Theme(
        data: ThemeData.dark(),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: MouseRegion(
            onHover: (_) => _onMouseMove(),
            cursor: _showControls
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Video ────────────────────────────────────────────────
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

                // ── Controls Overlay ─────────────────────────────────────
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _buildControlsOverlay(),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildControlsOverlay() {
    return Stack(children: [
      // ── Gradient vignettes ─────────────────────────────────────────────
      const Positioned(
          top: 0, left: 0, right: 0,
          child: _OverlayGradient(isTop: true)),
      const Positioned(
          bottom: 0, left: 0, right: 0,
          child: _OverlayGradient(isTop: false)),

      // ── TOP BAR ────────────────────────────────────────────────────────
      Positioned(
        top: 0, left: 0, right: 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            GlassIconButton(
              icon: Icons.close_rounded,
              onPressed: () async {
                // Exit fullscreen if currently fullscreen
                if (_isFullscreen) {
                  await windowManager.setFullScreen(false);
                  setState(() => _isFullscreen = false);
                }
                _saveWatchHistory();
                if (mounted) Navigator.of(context).pop();
              },
              size: 38, iconSize: 18,
            ),
            const SizedBox(width: 10),
            // Title pill
            Expanded(
              child: _Glass(
                radius: 20,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                child: Text(
                  widget.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // HW decode mode badge
            GlassPillButton(
              text: _hwDecMode.label,
              onTap: _cycleHwDec,
              accent: _hwDecMode.accent,
            ),
            const SizedBox(width: 6),
            GlassIconButton(
              icon: Icons.music_note_outlined,
              onPressed: _showAudioMenu,
            ),
            const SizedBox(width: 6),
            GlassIconButton(
              icon: Icons.subtitles_outlined,
              onPressed: _showSubtitlesMenu,
            ),
            // Show sources button only for Amri provider
            if (widget.activeProvider == 'amri' && widget.sources != null && widget.sources!.isNotEmpty) ...[
              const SizedBox(width: 6),
              GlassIconButton(
                icon: Icons.video_library_outlined,
                onPressed: _showSourcesMenu,
              ),
            ],
          ]),
        ),
      ),

      // ── CENTER PLAY/PAUSE ──────────────────────────────────────────────
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
                _player.playOrPause();
                _onMouseMove();
              },
            ),
          ),
        ),
      ),

      // ── BOTTOM CONTROLS ────────────────────────────────────────────────
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Icon row ───────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: speed / loop
                Row(children: [
                  GlassIconButton(
                    icon: Icons.speed_outlined,
                    onPressed: () => showSpeedMenu(
                        context, _player.state.rate,
                        (s) => _player.setRate(s)),
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: _loopEnabled
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    onPressed: _toggleLoop,
                    active: _loopEnabled,
                  ),
                ]),

                // Center: volume
                Row(children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _volumeNotifier,
                    builder: (context, vol, _) => GlassIconButton(
                      icon: vol == 0
                          ? Icons.volume_off_rounded
                          : vol < 50
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                      onPressed: () => _player
                          .setVolume(vol > 0 ? 0.0 : 100.0),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 90,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _volumeNotifier,
                      builder: (context, vol, _) => SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape:
                              const RoundSliderThumbShape(
                                  enabledThumbRadius: 5.5),
                          overlayShape:
                              const RoundSliderOverlayShape(
                                  overlayRadius: 10),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: vol,
                          min: 0, max: 150,
                          onChanged: (v) => _player.setVolume(v),
                        ),
                      ),
                    ),
                  ),
                ]),

                // Right: provider switcher / copy URL / subtitle settings / aspect / fullscreen
                Row(children: [
                  // Show provider switcher only when providers are available and not using torrent/stremio
                  if (widget.providers != null && widget.providers!.isNotEmpty && 
                      widget.magnetLink == null && widget.activeProvider != 'stremio_direct') ...[
                    GlassIconButton(
                      icon: Icons.swap_horiz_rounded,
                      onPressed: _isSwitchingProvider ? () {} : _showProviderMenu,
                    ),
                    const SizedBox(width: 8),
                  ],
                  GlassIconButton(
                    icon: Icons.link_rounded,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: widget.mediaPath));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Stream URL copied to clipboard')),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  // Aspect ratio pill – shows current mode so it's obvious
                  GlassPillButton(
                    text: _videoFitLabel,
                    onTap: _cycleAspectRatio,
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: _isFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    onPressed: _toggleFullscreen,
                  ),
                ]),
              ],
            ),
            const SizedBox(height: 8),

            // ── Seekbar row ────────────────────────────────────────────
            Row(children: [
              // Current time
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

              // Seekbar
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
                          _GlassSeekbar(
                        duration: duration,
                        position: position,
                        bufferedPosition: buffered,
                        onSeek: (t) {
                          _player.seek(t);
                          _onMouseMove();
                        },
                        onDragStart: () => _hideTimer?.cancel(),
                        onDragEnd: _startHideTimer,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),
              // Total duration
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
            const SizedBox(height: 4),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 52),
          const SizedBox(height: 16),
          const Text('Playback Error',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_errorMessage,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED)),
              onPressed: () {
                setState(() { _hasError = false; _errorMessage = ''; });
                _initPlayback();
              },
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back',
                  style: TextStyle(color: Colors.white)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  GLASSY SEEKBAR  — hover tooltip + preview line + smooth thumb
// ─────────────────────────────────────────────────────────────────────────────

class _GlassSeekbar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final Duration bufferedPosition;
  final void Function(Duration) onSeek;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  const _GlassSeekbar({
    required this.duration,
    required this.position,
    required this.bufferedPosition,
    required this.onSeek,
    required this.onDragStart,
    required this.onDragEnd,
  });

  @override
  State<_GlassSeekbar> createState() => _GlassSeekbarState();
}

class _GlassSeekbarState extends State<_GlassSeekbar> {
  bool   _isDragging  = false;
  bool   _hovering    = false;
  double _dragFrac    = 0.0; // 0..1 fraction while dragging
  double _hoverFrac   = 0.0; // 0..1 fraction of cursor position
  double _trackWidth  = 0.0; // cached from LayoutBuilder

  // ── Fractions ───────────────────────────────────────────────────────────
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

  // ── Time at hover position ───────────────────────────────────────────────
  Duration get _hoverTime {
    final total = widget.duration.inMilliseconds.toDouble();
    return Duration(milliseconds: (_hoverFrac * total).round());
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  double _fracFromLocal(double dx) =>
      (dx / _trackWidth).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final active = _hovering || _isDragging;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (e) => setState(() {
        _hovering  = true;
        _hoverFrac = _fracFromLocal(e.localPosition.dx);
      }),
      onHover: (e) => setState(() {
        _hoverFrac = _fracFromLocal(e.localPosition.dx);
      }),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          widget.onDragStart();
          setState(() {
            _isDragging = true;
            _dragFrac   = _fracFromLocal(d.localPosition.dx);
            _hoverFrac  = _dragFrac;
          });
        },
        onHorizontalDragUpdate: (d) => setState(() {
          _dragFrac  = _fracFromLocal(d.localPosition.dx);
          _hoverFrac = _dragFrac;
        }),
        onHorizontalDragEnd: (_) {
          final total = widget.duration.inMilliseconds.toDouble();
          widget.onSeek(Duration(milliseconds: (_dragFrac * total).round()));
          widget.onDragEnd();
          setState(() => _isDragging = false);
        },
        onTapUp: (d) {
          final total = widget.duration.inMilliseconds.toDouble();
          final frac  = _fracFromLocal(d.localPosition.dx);
          widget.onSeek(Duration(milliseconds: (frac * total).round()));
        },
        // Extra vertical hit area so the thin bar is easy to grab
        child: SizedBox(
          height: 28,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 20,
              child: LayoutBuilder(builder: (context, constraints) {
                _trackWidth = constraints.maxWidth;

                // ── track height animates from 3 → 6 on active ────────────
                final trackH = active ? 6.0 : 3.0;
                // ── thumb radius: 0 → 7 on active, centred on playhead ────
                final thumbR = active ? 7.0 : 0.0;
                // ── playhead + hover pixel positions ─────────────────────
                final playPx  = (_playFrac  * _trackWidth).clamp(0.0, _trackWidth);
                final hoverPx = (_hoverFrac * _trackWidth).clamp(0.0, _trackWidth);

                // ── Tooltip horizontal clamp so it never overflows ─────────
                const tipW     = 72.0;
                final tipLeft  = (hoverPx - tipW / 2).clamp(0.0, _trackWidth - tipW);

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    // ── Background track ────────────────────────────────
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      height: trackH,
                      width: _trackWidth,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(trackH),
                      ),
                    ),

                    // ── Buffered ─────────────────────────────────────────
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      height: trackH,
                      width: (_bufFrac * _trackWidth).clamp(0.0, _trackWidth),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(trackH),
                      ),
                    ),

                    // ── Played ───────────────────────────────────────────
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

                    // ── Hover preview line (ghosted, thin) ───────────────
                    if (active)
                      Positioned(
                        left: hoverPx - 1,
                        child: AnimatedOpacity(
                          opacity: active ? 0.45 : 0.0,
                          duration: const Duration(milliseconds: 120),
                          child: Container(
                            width: 1.5,
                            height: trackH + 4,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),

                    // ── Playhead thumb dot ───────────────────────────────
                    Positioned(
                      left: playPx - thumbR,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        width:  thumbR * 2,
                        height: thumbR * 2,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: active
                              ? [BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  blurRadius: 6,
                                )]
                              : [],
                        ),
                      ),
                    ),

                    // ── Hover tooltip: glassy pill above cursor ──────────
                    if (active && widget.duration.inMilliseconds > 0)
                      Positioned(
                        top: -38,
                        left: tipLeft,
                        child: AnimatedOpacity(
                          opacity: active ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 120),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                              child: Container(
                                width: tipW,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1C1C1E).withValues(alpha: 0.82),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    width: 0.6,
                                  ),
                                ),
                                child: Text(
                                  formatDuration(_hoverTime),
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
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}