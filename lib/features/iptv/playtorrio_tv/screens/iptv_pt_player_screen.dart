import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../data/models.dart';

/// Single source for the IPTV player.
class IptvPlaySource {
  final String url;
  final String label;
  const IptvPlaySource({required this.url, required this.label});
}

/// Dedicated IPTV player using libmpv (media_kit). Includes:
///   • Watchdog (3 detectors): long buffering, frozen position, ready-but-not-playing
///   • Tiered recovery: seek-zero → reload → stop+open → recreate
///   • Multi-source rotation
///   • Backoff retries with healthy-streak reset
///   • Pretty responsive overlay UI
class IptvPtPlayerScreen extends StatefulWidget {
  final List<IptvPlaySource> sources;
  final String title;
  final String? subtitle;
  final String? logoUrl;

  const IptvPtPlayerScreen({
    super.key,
    required this.sources,
    required this.title,
    this.subtitle,
    this.logoUrl,
  });

  /// Convenience: build for a single Xtream stream.
  factory IptvPtPlayerScreen.singleStream({
    Key? key,
    required String url,
    required IptvStream stream,
    String? portalName,
  }) =>
      IptvPtPlayerScreen(
        key: key,
        sources: [IptvPlaySource(url: url, label: portalName ?? 'Source 1')],
        title: stream.name,
        subtitle: portalName,
        logoUrl: stream.icon,
      );

  /// Convenience: build for a list of channel hits (multi-source).
  factory IptvPtPlayerScreen.fromHits({
    Key? key,
    required List<ChannelHit> hits,
    required String title,
    String? logoUrl,
  }) =>
      IptvPtPlayerScreen(
        key: key,
        title: title,
        logoUrl: logoUrl,
        sources: hits
            .asMap()
            .entries
            .map((e) => IptvPlaySource(
                  url: e.value.streamUrl,
                  label: e.value.portal.name.isNotEmpty
                      ? e.value.portal.name
                      : 'Source ${e.key + 1}',
                ))
            .toList(),
      );

  @override
  State<IptvPtPlayerScreen> createState() => _IptvPtPlayerScreenState();
}

class _IptvPtPlayerScreenState extends State<IptvPtPlayerScreen>
    with WidgetsBindingObserver {
  late Player _player;
  late VideoController _controller;

  StreamSubscription? _posSub, _playingSub, _bufferingSub, _errorSub;

  int _sourceIdx = 0;
  bool _playing = false;
  bool _buffering = false;
  bool _userPlayWhenReady = true;
  String? _statusBanner;
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  // Watchdog state
  Timer? _watchdog;
  Duration _lastPos = Duration.zero;
  DateTime _lastPosChange = DateTime.now();
  DateTime? _bufferingSince;
  DateTime? _readyNotPlayingSince;

  // Audio state
  double _volume = 100.0; // 0..100 (mpv scale)
  double _volumeBeforeMute = 100.0;
  bool _muted = false;
  bool _showVolumeSlider = false;
  Timer? _hideVolumeTimer;

  // Fullscreen state (desktop only — mobile is permanently immersive)
  bool _isFullscreen = false;
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  // Retry state
  int _retryAttempt = 0;
  DateTime? _lastRecoveryAt;
  // When the user explicitly paused (so play-after-pause can rejoin live edge)
  DateTime? _pausedAt;
  // How long a pause must be before we treat resume as "rejoin live" (full reload)
  static const Duration _liveRejoinThreshold = Duration(seconds: 2);
  final List<int> _backoffMs = const [500, 1000, 2000, 3000, 4000, 6000, 8000, 8000];
  static const int _maxRetries = 8;
  static const Duration _healthyStreakNeeded = Duration(seconds: 6);

  static const _ua = 'VLC/3.0.20 LibVLC/3.0.20';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initOrientationAndChrome();
    WakelockPlus.enable();
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _controller = VideoController(_player);
    _bind();
    _applyMpvTunables();
    _openCurrent();
    _startWatchdog();
    _scheduleHideControls();
  }

  /// Set libmpv/FFmpeg properties that turn media_kit into a real IPTV player.
  /// Sources: mpv issue #5793, char101 reload-on-stall pattern, FFmpeg
  /// reconnect_* options. Tested for HLS / MPEG-TS / RTSP / Xtream live.
  Future<void> _applyMpvTunables() async {
    try {
      final p = _player.platform;
      if (p is! NativePlayer) return;

      // Network: fail fast so the watchdog can step in
      await p.setProperty('network-timeout', '15');

      // Cache: small live-buffer; never pause on underrun (just let it skip)
      await p.setProperty('cache', 'yes');
      await p.setProperty('cache-secs', '10');
      await p.setProperty('demuxer-readahead-secs', '5');
      await p.setProperty('demuxer-max-bytes', '50000000');
      await p.setProperty('demuxer-max-back-bytes', '10000000');
      await p.setProperty('cache-pause', 'no');
      await p.setProperty('cache-pause-initial', 'no');

      // Don't quit on EOF / brief disconnect — let us recover
      await p.setProperty('keep-open', 'yes');
      await p.setProperty('keep-open-pause', 'no');

      // HLS: pick best variant
      await p.setProperty('hls-bitrate', 'max');

      // RTSP over TCP — way more reliable on flaky networks
      await p.setProperty('rtsp-transport', 'tcp');

      // Many Xtream panels gate streams on a VLC user-agent
      await p.setProperty('user-agent', _ua);

      // FFmpeg reconnect knobs (the proven set from gist + alexishuxley)
      await p.setProperty(
        'stream-lavf-o',
        'reconnect=1,'
            'reconnect_at_eof=1,'
            'reconnect_streamed=1,'
            'reconnect_delay_max=5,'
            'reconnect_on_network_error=1,'
            'reconnect_on_http_error=4xx\\,5xx',
      );

      // Low-latency MPEG-TS / HLS demux. Probesize/analyzeduration must be
      // big enough for ffmpeg to detect real frame rate & codec params on
      // junk Xtream streams — too small => wrong fps / laggy decode.
      //   probesize=5MB, analyzeduration=5s   (mpv low-latency-ish defaults)
      //   nobuffer + discardcorrupt           — keep latency low, drop junk.
      // NOTE: HLS-only options (live_start_index, m3u8_hold_counters,
      // seg_max_retry, max_reload) are NOT set here — when the stream isn't
      // HLS, libavformat rejects them and mpv prints noisy errors that our
      // watchdog mistakes for stream failures.
      await p.setProperty(
        'demuxer-lavf-o',
        'fflags=+nobuffer+discardcorrupt,'
            'probesize=5000000,'
            'analyzeduration=5000000',
      );
    } catch (e) {
      debugPrint('[IPTV Player] tunables failed: $e');
    }
  }

  Future<void> _initOrientationAndChrome() async {
    // Don't auto-enter fullscreen or force landscape — the player opens in a
    // normal window/portrait, and the user enters fullscreen explicitly via
    // the fullscreen button.
    _isFullscreen = false;
  }

  Future<void> _toggleFullscreen() async {
    if (_isDesktop) {
      try {
        final isFull = await windowManager.isFullScreen();
        if (isFull) {
          // Leaving fullscreen — also drop maximize so the user gets a real window.
          await windowManager.setFullScreen(false);
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          }
        } else {
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          }
          await windowManager.setFullScreen(true);
        }
        if (mounted) setState(() => _isFullscreen = !isFull);
      } catch (_) {}
    } else {
      final goFull = !_isFullscreen;
      await SystemChrome.setEnabledSystemUIMode(
        goFull ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      await SystemChrome.setPreferredOrientations(
        goFull
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : DeviceOrientation.values,
      );
      if (mounted) setState(() => _isFullscreen = goFull);
    }
    _scheduleHideControls();
  }

  void _bind() {
    _posSub = _player.stream.position.listen((pos) {
      if (!mounted) return;
      if (pos != _lastPos) {
        _lastPos = pos;
        _lastPosChange = DateTime.now();
        // Healthy streak — reset retry count if we've been ticking smoothly
        if (_retryAttempt > 0 &&
            DateTime.now().difference(_lastPosChange) <
                const Duration(milliseconds: 200) &&
            _statusBanner == null) {
          // we'll evaluate streak in watchdog
        }
      }
    });
    _playingSub = _player.stream.playing.listen((p) {
      if (!mounted) return;
      setState(() => _playing = p);
      if (p) {
        _readyNotPlayingSince = null;
      } else if (_userPlayWhenReady) {
        _readyNotPlayingSince = DateTime.now();
      }
    });
    _bufferingSub = _player.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() => _buffering = b);
      if (b) {
        _bufferingSince ??= DateTime.now();
      } else {
        _bufferingSince = null;
      }
    });
    _errorSub = _player.stream.error.listen((err) {
      final msg = err.toString();
      debugPrint('[IPTV Player] error: $msg');
      // Benign mpv chatter we don't want to restart the stream over:
      //  - "Cannot seek in this stream" / "force-seekable=yes"  → pure-live
      //    stream, the live-edge seek failed (harmless).
      //  - "Expected '=' and a value"                          → libav option
      //    parser warning for HLS-only opts on a non-HLS stream.
      final lower = msg.toLowerCase();
      if (lower.contains('cannot seek') ||
          lower.contains('force-seekable') ||
          lower.contains("expected '=' and a value")) {
        return;
      }
      _triggerRecovery(reason: 'error: $msg');
    });
  }

  Future<void> _openCurrent() async {
    final src = widget.sources[_sourceIdx];
    // Connect silently — no banner. The buffering indicator (if any) will
    // appear naturally while the stream loads.
    try {
      await _player.open(
        Media(src.url, httpHeaders: const {'User-Agent': _ua}),
      );
      await _player.play();
      _userPlayWhenReady = true;
      _pausedAt = null;
      _lastPos = Duration.zero;
      _lastPosChange = DateTime.now();
      // For HLS streams that DO expose a DVR window, jump to the live edge
      // shortly after open so we never replay stale buffered packets.
      _scheduleJumpToLive();
      // Clear banner after a short successful run
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        if (_playing && !_buffering) {
          setState(() => _statusBanner = null);
        }
      });
    } catch (e) {
      _triggerRecovery(reason: 'open failed: $e');
    }
  }

  /// Best-effort jump to the live edge after a (re)open.
  /// Only fires when the stream actually exposes a DVR window (seekable=yes
  /// AND a finite duration). On pure-live streams seeking emits a noisy
  /// "Cannot seek in this stream / force-seekable=yes" error that the
  /// watchdog would otherwise treat as a failure.
  void _scheduleJumpToLive() {
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      try {
        final p = _player.platform;
        if (p is! NativePlayer) return;

        final seekableRaw = await p.getProperty('seekable');
        final durRaw = await p.getProperty('duration');
        final isSeekable = seekableRaw.toString().toLowerCase() == 'yes';
        final dur = double.tryParse(durRaw.toString()) ?? 0.0;
        if (!isSeekable || dur <= 0) {
          // Pure live — nothing to seek to.
          return;
        }

        // Drop any data that piled up while paused / mid-recovery, then
        // jump to the live edge of the DVR window.
        await p.command(['drop-buffers']);
        await p.command(['seek', '99999', 'absolute']);
      } catch (_) {
        // Best-effort — ignore.
      }
    });
  }

  void _startWatchdog() {
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();

      // Healthy streak resets retry counter
      if (_retryAttempt > 0 &&
          _playing &&
          !_buffering &&
          now.difference(_lastPosChange) < const Duration(milliseconds: 1500) &&
          _lastRecoveryAt != null &&
          now.difference(_lastRecoveryAt!) > _healthyStreakNeeded) {
        debugPrint('[IPTV Watchdog] healthy streak — resetting retries');
        _retryAttempt = 0;
        _lastRecoveryAt = null;
        if (mounted) setState(() => _statusBanner = null);
      }

      // Detector 1: long buffering
      if (_userPlayWhenReady &&
          _bufferingSince != null &&
          now.difference(_bufferingSince!) > const Duration(milliseconds: 6000)) {
        _triggerRecovery(reason: 'buffering > 6s');
        return;
      }
      // Detector 2: position frozen while playing
      if (_playing &&
          now.difference(_lastPosChange) > const Duration(milliseconds: 5000)) {
        _triggerRecovery(reason: 'position frozen > 5s');
        return;
      }
      // Detector 3: should be playing but isn't
      if (_userPlayWhenReady &&
          !_playing &&
          _readyNotPlayingSince != null &&
          now.difference(_readyNotPlayingSince!) >
              const Duration(milliseconds: 5000)) {
        _triggerRecovery(reason: 'not playing > 5s');
      }
    });
  }

  bool _recoveryInFlight = false;
  Future<void> _triggerRecovery({required String reason}) async {
    if (_recoveryInFlight) return;
    final now = DateTime.now();
    if (_lastRecoveryAt != null &&
        now.difference(_lastRecoveryAt!) <
            const Duration(milliseconds: 1500)) {
      return; // throttle
    }
    _recoveryInFlight = true;
    _lastRecoveryAt = now;
    debugPrint('[IPTV Watchdog] recovery (#${_retryAttempt + 1}): $reason');

    try {
      if (_retryAttempt >= _maxRetries) {
        // Rotate source
        if (_sourceIdx < widget.sources.length - 1) {
          _sourceIdx++;
          _retryAttempt = 0;
          if (mounted) {
            setState(() =>
                _statusBanner = 'Switching to ${widget.sources[_sourceIdx].label}…');
          }
          await _openCurrent();
        } else {
          if (mounted) {
            setState(() => _statusBanner = 'Unable to connect.');
          }
        }
        return;
      }

      _retryAttempt++;
      final delayIdx = (_retryAttempt - 1).clamp(0, _backoffMs.length - 1);
      final delay = _backoffMs[delayIdx];
      // Reconnect silently in the background — no UI banner.

      await Future.delayed(Duration(milliseconds: delay));

      if (_retryAttempt <= 2) {
        try {
          await _player.seek(Duration.zero);
        } catch (_) {}
        try {
          await _player.open(
            Media(widget.sources[_sourceIdx].url,
                httpHeaders: const {'User-Agent': _ua}),
          );
          await _player.play();
        } catch (_) {}
      } else if (_retryAttempt <= 4) {
        try {
          await _player.stop();
        } catch (_) {}
        try {
          await _player.open(
            Media(widget.sources[_sourceIdx].url,
                httpHeaders: const {'User-Agent': _ua}),
          );
          await _player.play();
        } catch (_) {}
      } else {
        // Recreate
        try {
          await _disposePlayer();
          _player = Player(
            configuration: const PlayerConfiguration(
              bufferSize: 32 * 1024 * 1024,
              logLevel: MPVLogLevel.warn,
            ),
          );
          _controller = VideoController(_player);
          _bind();
          await _applyMpvTunables();
          await _player.open(
            Media(widget.sources[_sourceIdx].url,
                httpHeaders: const {'User-Agent': _ua}),
          );
          await _player.play();
          if (mounted) setState(() {});
        } catch (e) {
          debugPrint('[IPTV] recreate failed: $e');
        }
      }
      _bufferingSince = null;
      _readyNotPlayingSince = null;
      _lastPos = Duration.zero;
      _lastPosChange = DateTime.now();
    } finally {
      _recoveryInFlight = false;
    }
  }

  Future<void> _disposePlayer() async {
    await _posSub?.cancel();
    await _playingSub?.cancel();
    await _bufferingSub?.cancel();
    await _errorSub?.cancel();
    try {
      await _player.dispose();
    } catch (_) {}
  }

  void _switchSource(int idx) async {
    if (idx == _sourceIdx) return;
    setState(() {
      _sourceIdx = idx;
      _retryAttempt = 0;
    });
    await _openCurrent();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer =
        Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchdog?.cancel();
    _hideControlsTimer?.cancel();
    _hideVolumeTimer?.cancel();
    _disposePlayer();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (_isDesktop) {
      // Restore a normal (non-fullscreen, non-maximized) window when leaving.
      Future.microtask(() async {
        try {
          if (await windowManager.isFullScreen()) {
            await windowManager.setFullScreen(false);
          }
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          }
        } catch (_) {}
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.shortestSide < 600;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video
            Center(
              child: Video(
                controller: _controller,
                fit: BoxFit.contain,
                controls: NoVideoControls,
              ),
            ),
            // Reconnect/buffering banner
            if (_buffering || _statusBanner != null) _buildBanner(),
            // Top bar + bottom controls
            AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: _controlsVisible ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _buildOverlay(compact),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _statusBanner ?? 'Buffering…',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(bool compact) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black87,
            Colors.transparent,
            Colors.transparent,
            Colors.black87,
          ],
          stops: [0, 0.25, 0.7, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(compact),
            const Spacer(),
            _buildBottomBar(compact),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool compact) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          if ((widget.logoUrl ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  widget.logoUrl!,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.bebasNeue(
                    color: Colors.white,
                    fontSize: compact ? 18 : 22,
                    letterSpacing: 1,
                  ),
                ),
                if ((widget.subtitle ?? '').isNotEmpty)
                  Text(
                    widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.sources.length > 1) ...[
            const SizedBox(width: 8),
            _SourceChip(
              label: widget.sources[_sourceIdx].label,
              onTap: _showSourcePicker,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool compact) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 24, vertical: compact ? 12 : 18),
      child: Row(
        children: [
          _RoundIcon(
            icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            big: true,
            onTap: () async {
              if (_playing) {
                _userPlayWhenReady = false;
                _pausedAt = DateTime.now();
                await _player.pause();
              } else {
                _userPlayWhenReady = true;
                final pausedFor = _pausedAt == null
                    ? Duration.zero
                    : DateTime.now().difference(_pausedAt!);
                _pausedAt = null;
                if (pausedFor >= _liveRejoinThreshold) {
                  // Long pause on a live stream → buffered data is stale.
                  // Reload the source so we rejoin at the live edge instead of
                  // replaying packets from when the user first hit play.
                  await _openCurrent();
                } else {
                  await _player.play();
                }
              }
              _scheduleHideControls();
            },
          ),
          const SizedBox(width: 14),
          _RoundIcon(
            icon: Icons.replay_rounded,
            onTap: () async {
              _retryAttempt = 0;
              await _openCurrent();
              _scheduleHideControls();
            },
          ),
          const SizedBox(width: 14),
          // Mute toggle
          _RoundIcon(
            icon: _muted || _volume == 0
                ? Icons.volume_off_rounded
                : (_volume < 40
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded),
            onTap: _toggleMute,
            onLongPress: () {
              setState(() => _showVolumeSlider = !_showVolumeSlider);
              _scheduleHideVolumeSlider();
              _scheduleHideControls();
            },
          ),
          // Volume slider (responsive: shrinks on small screens)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: SizedBox(
              width: _showVolumeSlider ? (compact ? 110 : 160) : 0,
              child: ClipRect(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF00E5FF),
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: const Color(0x3300E5FF),
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: _volume.clamp(0.0, 100.0),
                      min: 0,
                      max: 100,
                      onChanged: (v) {
                        setState(() {
                          _volume = v;
                          _muted = v == 0;
                        });
                        _player.setVolume(v);
                        _scheduleHideVolumeSlider();
                        _scheduleHideControls();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (widget.sources.length > 1)
            _RoundIcon(
              icon: Icons.swap_horiz_rounded,
              onTap: _showSourcePicker,
            ),
          if (widget.sources.length > 1) const SizedBox(width: 14),
          _RoundIcon(
            icon: _isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            onTap: _toggleFullscreen,
          ),
        ],
      ),
    );
  }

  void _toggleMute() {
    setState(() {
      if (_muted || _volume == 0) {
        _muted = false;
        _volume = _volumeBeforeMute > 0 ? _volumeBeforeMute : 100.0;
      } else {
        _volumeBeforeMute = _volume;
        _muted = true;
        _volume = 0;
      }
      _showVolumeSlider = true;
    });
    _player.setVolume(_volume);
    _scheduleHideVolumeSlider();
    _scheduleHideControls();
  }

  void _scheduleHideVolumeSlider() {
    _hideVolumeTimer?.cancel();
    _hideVolumeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showVolumeSlider = false);
    });
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Choose source',
                  style: GoogleFonts.bebasNeue(
                    color: Colors.white,
                    fontSize: 22,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.sources.length,
                  itemBuilder: (_, i) {
                    final s = widget.sources[i];
                    final active = i == _sourceIdx;
                    return ListTile(
                      leading: Icon(
                        active ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: active ? const Color(0xFF00E5FF) : Colors.white54,
                      ),
                      title: Text(
                        s.label,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      subtitle: Text(
                        s.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _switchSource(i);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool big;
  const _RoundIcon({
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = big ? 56.0 : 44.0;
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: big ? 32 : 22),
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SourceChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz_rounded,
                color: Color(0xFF00E5FF), size: 16),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
