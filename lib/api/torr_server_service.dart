// ============================================================================
//  TorrServerService - ULTRA-OPTIMIZED STREAMING ENGINE
//  Research-backed, beat-Stremio grade implementation.
//
//  KEY DISCOVERIES FROM SOURCE RESEARCH:
//  1. BTSets.PreloadCache = % of CacheSize that must fill BEFORE playback.
//     Default 50% of 64MB = 32MB. We drop this to 2% → ~10MB → INSTANT START.
//  2. BTSets.ReaderReadAHead = % of cache window that is AHEAD of reader.
//     95% means 95% ahead, 5% behind. Keep at 95 for max forward buffer.
//  3. BTSets.Strategy = 2 (RequestStrategyFastest) — undocumented in UI but
//     present in btsets.go — picks the fastest piece-request strategy.
//  4. BTSets.ResponsiveMode = true — CRITICAL: enables read-ahead priority
//     for the HTTP streaming reader. Without this, pieces are fetched in
//     torrent order, not reader order. MASSIVE buffering improvement.
//  5. _configureServer() was NEVER CALLED in the original start() — BIG BUG.
//  6. /echo endpoint is the TRUE health-check. /torrents can return 200 but
//     still have "BT client not connected" in body.
//  7. DisableUpload=true gives 100% bandwidth to download (leech mode).
//  8. DhtConnectionLimit=0 → unlimited DHT connections → more peers found.
//  9. ConnectionsLimit: we set 500 on desktop, 150 on mobile (balanced).
//  10. Priority payload format: list of ints where index matches file id,
//      value is priority (0=off, 1=normal). Confirm with server source.
//  11. TorrentDisconnectTimeout minimum is 30s (enforced by server). We set
//      86400 (24h) so the engine stays alive across app lifecycle.
//  12. The stream URL ?play param causes TorrServer to open the HTTP stream
//      immediately. ?m3u generates an M3U playlist instead.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'torrent_filter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public data types
// ─────────────────────────────────────────────────────────────────────────────

/// Rich torrent statistics object returned by [TorrServerService.getTorrentStats].
class TorrentStats {
  final double speedMbps;
  final int activePeers;
  final int totalPeers;
  final double cachePercent;
  final int loadedBytes;
  final int totalBytes;
  final String hash;
  final bool isConnected;

  const TorrentStats({
    required this.speedMbps,
    required this.activePeers,
    required this.totalPeers,
    required this.cachePercent,
    required this.loadedBytes,
    required this.totalBytes,
    required this.hash,
    required this.isConnected,
  });

  double get speedKbps => speedMbps * 1024;
  String get speedLabel => speedMbps >= 1.0
      ? '${speedMbps.toStringAsFixed(2)} MB/s'
      : '${speedKbps.toStringAsFixed(0)} KB/s';
  String get peersLabel => '$activePeers / $totalPeers';
  String get cacheLabel => '${cachePercent.toStringAsFixed(1)}%';
}

/// Engine lifecycle states.
enum EngineState { stopped, starting, configuring, ready, error }

// ─────────────────────────────────────────────────────────────────────────────
// TorrServerService
// ─────────────────────────────────────────────────────────────────────────────

class TorrServerService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final TorrServerService _instance = TorrServerService._internal();
  factory TorrServerService() => _instance;
  TorrServerService._internal();

  // ── Platform channel ───────────────────────────────────────────────────────
  static const _platform = MethodChannel('com.playtorrio.native/path');

  // ── Server config ──────────────────────────────────────────────────────────
  final int _port = 8090;
  final String _host = '127.0.0.1';
  String get _base => 'http://$_host:$_port';

  // ── State ──────────────────────────────────────────────────────────────────
  Process? _serverProcess;
  String? _extractedBinaryPath;
  EngineState _state = EngineState.stopped;
  EngineState get state => _state;

  /// Optional callback fired whenever engine state changes.
  void Function(EngineState state)? onStateChanged;

  /// Optional callback fired with engine log lines.
  void Function(String line)? onLogLine;

  // ── HTTP client (shared, keep-alive) ───────────────────────────────────────
  // Using a single client avoids TCP handshake overhead on every request.
  final _httpClient = http.Client();

  // ─────────────────────────────────────────────────────────────────────────
  // Platform-adaptive cache sizes
  // ─────────────────────────────────────────────────────────────────────────
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// RAM cache in bytes.
  /// Mobile: 512 MB  |  Desktop: 2 GB
  int get _cacheSize => _isMobile ? 512 * 1024 * 1024 : 2 * 1024 * 1024 * 1024;

  /// Maximum simultaneous peer connections.
  /// Mobile: 200  |  Desktop: 500
  int get _connectionsLimit => _isMobile ? 200 : 500;

  // ─────────────────────────────────────────────────────────────────────────
  // Tracker list — verified active trackers (Feb 2026)
  // ─────────────────────────────────────────────────────────────────────────
  static const List<String> _trackers = [
    // UDP trackers — fastest, smallest overhead
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.tracker.cl:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://tracker.moeking.me:6969/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.tiny-vps.com:6969/announce',
    'udp://tracker.openbittorrent.com:6969/announce',
    'udp://p4p.arenabg.com:1337/announce',
    'udp://tracker.cyberia.is:6969/announce',
    'udp://explodie.org:6969/announce',
    'udp://tracker.dler.org:6969/announce',
    'udp://opentracker.i2p.rocks:6969/announce',
    'udp://bt.oiia.moe:6969/announce',
    'udp://tracker1.bt.moack.co.kr:80/announce',
    'udp://tracker.bitsearch.to:1337/announce',
    'udp://movies.zsw.ca:6969/announce',
    'udp://tracker2.dler.org:80/announce',
    // HTTP trackers — higher latency but wider firewall compatibility
    'http://tracker.openbittorrent.com:80/announce',
    'http://tracker.opentrackr.org:1337/announce',
    'https://tracker.tamersunion.org:443/announce',
    'https://tracker.gbitt.info:443/announce',
    'https://tr.burnbit.com:443/announce',
  ];

  // ─────────────────────────────────────────────────────────────────────────
  // Binary discovery / extraction
  // ─────────────────────────────────────────────────────────────────────────

  Future<String> _getBinaryPath() async {
    _log('_getBinaryPath() called');
    if (_extractedBinaryPath != null) {
      final cached = File(_extractedBinaryPath!);
      if (await cached.exists()) {
        _log('  Using cached binary path: $_extractedBinaryPath');
        return _extractedBinaryPath!;
      }
      _log('  Cached path no longer exists, re-extracting...');
      _extractedBinaryPath = null; // stale cache — re-extract
    }

    // Android: the .so is placed in the native lib dir by the APK installer.
    if (Platform.isAndroid) {
      _log('  Platform: Android - looking for native library...');
      try {
        final String libDir =
            await _platform.invokeMethod('getNativeLibraryDir');
        _log('  Native library directory: $libDir');
        final candidates = [
          path.join(libDir, 'libtorrserver.so'),
          path.join(libDir, 'arm64-v8a', 'libtorrserver.so'),
          path.join(libDir, 'armeabi-v7a', 'libtorrserver.so'),
          path.join(libDir, 'arm64', 'libtorrserver.so'),
          path.join(libDir, 'arm', 'libtorrserver.so'),
        ];
        _log('  Checking ${candidates.length} candidate paths...');
        for (final p in candidates) {
          _log('    Checking: $p');
          if (await File(p).exists()) {
            _extractedBinaryPath = p;
            _log('  ✓ Binary found at: $p');
            return p;
          }
        }
        _log('  ✗ No binary found in any candidate path');
      } catch (e) {
        _log('  ✗ Native library dir error: $e');
      }
    }

    // Desktop / fallback: extract from Flutter assets.
    _log('  Platform: ${Platform.operatingSystem} - extracting from assets...');
    final (assetPath, binaryName) = _assetForPlatform();
    _log('  Asset path: $assetPath');
    _log('  Binary name: $binaryName');
    
    final tmpDir = await getTemporaryDirectory();
    _log('  Temp directory: ${tmpDir.path}');
    
    final extractedPath =
        path.join(tmpDir.path, 'torrserver_bin', binaryName);
    _log('  Target extraction path: $extractedPath');
    
    final extractedFile = File(extractedPath);

    // Re-use already-extracted binary if it exists.
    if (await extractedFile.exists()) {
      _log('  Binary already extracted, reusing...');
      // macOS: ensure quarantine is cleared and binary is signed on reuse too.
      if (Platform.isMacOS) {
        await _prepareMacOSBinary(extractedPath);
      }
      _extractedBinaryPath = extractedPath;
      return extractedPath;
    }

    _log('  Extracting binary from assets...');
    try {
      final byteData = await rootBundle.load(assetPath);
      _log('  ✓ Asset loaded: ${byteData.lengthInBytes} bytes');
      
      await Directory(path.dirname(extractedPath)).create(recursive: true);
      _log('  ✓ Directory created');
      
      await extractedFile.writeAsBytes(byteData.buffer.asUint8List());
      _log('  ✓ Binary written to disk');

      if (!Platform.isWindows) {
        _log('  Setting executable permissions (chmod 755)...');
        final chmodResult = await Process.run('chmod', ['755', extractedPath]);
        _log('  chmod exit code: ${chmodResult.exitCode}');
        if (chmodResult.exitCode != 0) {
          _log('  chmod stderr: ${chmodResult.stderr}');
        }
      }

      // macOS: remove quarantine attribute and ad-hoc sign the binary.
      // Without this, Gatekeeper / hardened runtime blocks execution of
      // binaries extracted at runtime (they inherit com.apple.quarantine).
      if (Platform.isMacOS) {
        await _prepareMacOSBinary(extractedPath);
      }

      _extractedBinaryPath = extractedPath;
      _log('  ✓ Binary ready at: $extractedPath');
      return extractedPath;
    } catch (e, st) {
      _log('  ✗ Failed to extract binary: $e');
      _log('  Stack trace: $st');
      rethrow;
    }
  }

  /// Removes quarantine attributes and ad-hoc signs a binary on macOS.
  /// Required because macOS Gatekeeper / hardened runtime blocks execution
  /// of unsigned binaries that were extracted at runtime.
  Future<void> _prepareMacOSBinary(String binaryPath) async {
    _log('  macOS: removing quarantine attribute...');
    final xattrResult = await Process.run('xattr', ['-cr', binaryPath]);
    _log('  xattr exit code: ${xattrResult.exitCode}');
    if (xattrResult.exitCode != 0) {
      _log('  xattr stderr: ${xattrResult.stderr}');
    }

    _log('  macOS: ad-hoc code signing the binary...');
    final codesignResult = await Process.run(
      'codesign',
      ['--sign', '-', '--force', '--preserve-metadata=entitlements', binaryPath],
    );
    _log('  codesign exit code: ${codesignResult.exitCode}');
    if (codesignResult.exitCode != 0) {
      _log('  codesign stderr: ${codesignResult.stderr}');
      // Try without --preserve-metadata as fallback
      _log('  macOS: retrying codesign without --preserve-metadata...');
      final fallbackResult = await Process.run(
        'codesign', ['--sign', '-', '--force', binaryPath],
      );
      _log('  codesign fallback exit code: ${fallbackResult.exitCode}');
      if (fallbackResult.exitCode != 0) {
        _log('  codesign fallback stderr: ${fallbackResult.stderr}');
      }
    }
  }

  (String, String) _assetForPlatform() {
    if (Platform.isWindows) {
      return ('assets/bin/windows/TorrServer.exe', 'TorrServer.exe');
    } else if (Platform.isMacOS) {
      return ('assets/bin/macos/TorrServer', 'TorrServer');
    } else if (Platform.isLinux) {
      return ('assets/bin/linux/TorrServer', 'TorrServer');
    } else if (Platform.isAndroid) {
      return ('assets/bin/android/TorrServer-arm64', 'TorrServer-arm64');
    } else if (Platform.isIOS) {
      return ('assets/bin/ios/TorrServer', 'TorrServer');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Server lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Starts TorrServer and applies the optimized streaming configuration.
  /// Safe to call multiple times — is a no-op if already running.
  Future<bool> start() async {
    _log('═══════════════════════════════════════════════════════════');
    _log('START CALLED - Current state: $_state');
    _log('═══════════════════════════════════════════════════════════');
    
    if (_state == EngineState.starting || _state == EngineState.configuring) {
      _log('Engine is already starting, waiting…');
      return await _waitForEcho(timeout: const Duration(seconds: 20));
    }

    // Fast-path: port already open and /echo responds — engine alive.
    if (await _isEchoAlive()) {
      _log('Engine already running on port $_port.');
      _setState(EngineState.ready);
      return true;
    }

    _setState(EngineState.starting);
    _log('State changed to: starting');

    try {
      _log('Step 1: Getting binary path...');
      final binary = await _getBinaryPath();
      _log('✓ Binary path: $binary');
      
      _log('Step 2: Resolving data directory...');
      final dataDir = await _resolveDataDir();
      _log('✓ Data directory: $dataDir');
      
      _log('Step 3: Creating data directory if needed...');
      await Directory(dataDir).create(recursive: true);
      _log('✓ Data directory ready');

      _log('Step 4: Building launch arguments...');
      final args = _buildLaunchArgs(dataDir);
      _log('✓ Arguments: ${args.join(' ')}');
      
      _log('Step 5: Checking binary permissions...');
      final binaryFile = File(binary);
      final exists = await binaryFile.exists();
      _log('  Binary exists: $exists');
      if (exists) {
        final stat = await binaryFile.stat();
        _log('  Binary size: ${stat.size} bytes');
        _log('  Binary modified: ${stat.modified}');
        if (!Platform.isWindows) {
          _log('  Checking if executable bit is set...');
          final result = await Process.run('ls', ['-la', binary]);
          _log('  Permissions: ${result.stdout}');
        }
      }
      
      _log('Step 6: Starting process...');
      _log('Command: $binary ${args.join(' ')}');

      _serverProcess = await Process.start(
        binary,
        args,
        runInShell: false,
        environment: _processEnvironment(),
      );

      _log('✓ Process started successfully!');
      _log('  PID: ${_serverProcess!.pid}');

      // Pipe stdout/stderr to our log callback.
      _serverProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _log('[TorrServer STDOUT] $line');
          });
      _serverProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _log('[TorrServer STDERR] $line');
          });

      // Monitor unexpected exit.
      _serverProcess!.exitCode.then((code) {
        _log('⚠ TorrServer process exited with code $code');
        if (_state != EngineState.stopped) {
          _setState(EngineState.error);
        }
      });

      _log('Step 7: Waiting for /echo endpoint to respond...');
      _setState(EngineState.configuring);
      final ready = await _waitForEcho(timeout: const Duration(seconds: 30));
      if (!ready) {
        _log('✗ Engine did not respond within 30s. Aborting.');
        _setState(EngineState.error);
        return false;
      }
      _log('✓ /echo endpoint responded!');

      _log('Step 8: Applying optimized configuration...');
      await _configureServer();

      _setState(EngineState.ready);
      _log('═══════════════════════════════════════════════════════════');
      _log('✓✓✓ ENGINE READY - TorrServer is fully operational! ✓✓✓');
      _log('═══════════════════════════════════════════════════════════');
      return true;
    } catch (e, st) {
      _log('✗✗✗ FAILED TO START ENGINE ✗✗✗');
      _log('Error: $e');
      _log('Stack trace:');
      _log('$st');
      _log('═══════════════════════════════════════════════════════════');
      _setState(EngineState.error);
      return false;
    }
  }

  List<String> _buildLaunchArgs(String dataDir) {
    final args = <String>[
      '-p', '$_port',
      '-d', dataDir,
      '-k',        // --dontkill: don't kill existing instance on port conflict
    ];
    // On Linux, provide a log path to avoid permission issues with default paths.
    if (Platform.isLinux) {
      args.addAll(['-l', path.join(dataDir, 'torrserver.log')]);
    }
    return args;
  }

  Map<String, String> _processEnvironment() {
    final env = Map<String, String>.from(Platform.environment);
    // On Linux, this hint tells the Go runtime to release memory more
    // aggressively back to the OS instead of holding onto virtual pages.
    // Documented TorrServer community tip for reducing memory footprint.
    if (Platform.isLinux) {
      env['GODEBUG'] = 'madvdontneed=1';
    }
    return env;
  }

  Future<String> _resolveDataDir() async {
    if (_isMobile) {
      final appDir = await getApplicationDocumentsDirectory();
      return path.join(appDir.path, 'torr_data');
    }
    
    // Desktop: Always use application support directory for writable data
    // This handles AppImage (read-only mount), Flatpak, Snap, and regular installs
    final appSupportDir = await getApplicationSupportDirectory();
    return path.join(appSupportDir.path, 'torr_data');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Health checks
  // ─────────────────────────────────────────────────────────────────────────

  /// Most reliable health check: GET /echo returns the server version string.
  /// This confirms the HTTP server AND the BT engine are both up.
  Future<bool> _isEchoAlive() async {
    try {
      _log('Checking /echo endpoint at $_base/echo...');
      final response = await _httpClient
          .get(Uri.parse('$_base/echo'))
          .timeout(const Duration(milliseconds: 800));
      final alive = response.statusCode == 200;
      _log('  /echo response: ${response.statusCode} - ${alive ? "ALIVE" : "NOT ALIVE"}');
      return alive;
    } catch (e) {
      _log('  /echo check failed: $e');
      return false;
    }
  }

  /// Poll /echo until it responds or [timeout] expires.
  Future<bool> _waitForEcho({
    Duration timeout = const Duration(seconds: 20),
    Duration interval = const Duration(milliseconds: 150),
  }) async {
    _log('Polling /echo endpoint (timeout: ${timeout.inSeconds}s, interval: ${interval.inMilliseconds}ms)...');
    final deadline = DateTime.now().add(timeout);
    int attempts = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempts++;
      _log('  Attempt $attempts...');
      if (await _isEchoAlive()) {
        _log('✓ /echo responded after $attempts attempts');
        return true;
      }
      await Future.delayed(interval);
    }
    _log('✗ /echo did not respond after $attempts attempts');
    return false;
  }

  /// Checks that /torrents responds AND that the BT client is connected.
  Future<bool> _isBtClientReady() async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_base/torrents'),
            headers: _jsonHeaders,
            body: jsonEncode({'action': 'list'}),
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return false;
      // BT client might not be connected yet — server says so explicitly.
      return !response.body.contains('BT client not connected');
    } catch (_) {
      return false;
    }
  }

  Future<bool> _waitForBtReady({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isBtClientReady()) return true;
      await Future.delayed(const Duration(milliseconds: 600));
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CRITICAL: Apply optimized BTSets configuration
  // ─────────────────────────────────────────────────────────────────────────
  // ORIGINAL BUG: _configureServer() was defined but NEVER called in start().
  // This means every user ran with 64MB cache and 25 connections (defaults).
  // We fix this by calling it immediately after /echo responds.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _configureServer() async {
    final settingsUri = Uri.parse('$_base/settings');
    _log('Applying optimized streaming configuration…');

    try {
      // Read current settings (we override everything, but this is good
      // practice to preserve any user-set fields we don't touch).
      Map<String, dynamic> current = {};
      try {
        final getResp = await _httpClient
            .post(
              settingsUri,
              headers: _jsonHeaders,
              body: jsonEncode({'action': 'get'}),
            )
            .timeout(const Duration(seconds: 5));
        if (getResp.statusCode == 200 && getResp.body.isNotEmpty) {
          current = jsonDecode(getResp.body) as Map<String, dynamic>;
        }
      } catch (e) {
        _log('Could not read existing settings: $e (using defaults)');
      }

      // ── CACHE ──────────────────────────────────────────────────────────
      // CacheSize: 512 MB mobile / 2 GB desktop. All in RAM — RAM is 10-100×
      // faster than flash/SSD for sequential streaming reads.
      current['CacheSize'] = _cacheSize;
      current['UseDisk'] = false;
      // Keep cache alive across drop/add cycles. When user switches episodes
      // we don't want to re-download the same pieces.
      current['RemoveCacheOnDrop'] = false;

      // ── PRELOAD & READ-AHEAD ───────────────────────────────────────────
      // PreloadCache: % of CacheSize that MUST fill before HTTP reader opens.
      // Default 50% = 256 MB wait → 30+ seconds before any frame appears.
      // Desktop: 1% of 2 GB → ~21 MB (mpv has its own 300 MB demuxer cache).
      // Mobile:  2% of 512 MB → ~10 MB (balanced for slower connections).
      // ResponsiveMode=true further prioritises pieces near reader position.
      current['PreloadCache'] = _isMobile ? 2 : 1;

      // ReaderReadAHead: of the active cache window, what % is ahead of
      // the current read position vs behind (for seeking).
      // 95% ahead / 5% behind = optimal for linear video streaming.
      // Clamped to 5–100 by server; do not set below 5.
      current['ReaderReadAHead'] = 95;

      // ── RESPONSIVE MODE ────────────────────────────────────────────────
      // CRITICAL. When true, the piece scheduler gives top priority to pieces
      // near the HTTP reader's current byte position. Without this, pieces
      // arrive in torrent-rarest-first order which is terrible for streaming.
      current['ResponsiveMode'] = true;

      // ── PIECE REQUEST STRATEGY ─────────────────────────────────────────
      // 0 = DuplicateRequestTimeout (default) — sends duplicate requests after
      //     timeout; safe but slow.
      // 1 = Fuzzing — random jitter; helps in adversarial swarms.
      // 2 = Fastest — requests from the peer with the lowest observed latency
      //     immediately, no waiting. Best for streaming where latency > throughput.
      current['Strategy'] = 2; // RequestStrategyFastest

      // ── CONNECTIONS ────────────────────────────────────────────────────
      // High peer count = better piece diversity = higher aggregate speed.
      current['ConnectionsLimit'] = _connectionsLimit;
      // 0 = unlimited DHT connections. More DHT = more peers found faster.
      current['DhtConnectionLimit'] = 0;
      // 0 = random port (avoids firewall port conflicts).
      current['PeersListenPort'] = 0;

      // ── PROTOCOL ───────────────────────────────────────────────────────
      // Keep all protocols enabled for maximum peer reach.
      current['DisableTCP'] = false;    // TCP: most reliable transport
      current['DisableUTP'] = false;    // UTP: congestion-friendly, needed in many ISPs
      current['DisableDHT'] = false;    // DHT: trackerless peer discovery
      current['DisablePEX'] = false;    // PEX: peer exchange, grows swarm fast
      current['EnableIPv6'] = false;    // IPv6: disable (causes issues on many Android ROMs)
      current['DisableUPNP'] = false;   // UPnP: auto port-forward through NAT

      // ── UPLOAD ─────────────────────────────────────────────────────────
      // Disable upload entirely. This is a streaming client, not a seeder.
      // All bandwidth goes to DOWNLOAD. This is the single highest-impact
      // setting for raw download speed improvement.
      current['DisableUpload'] = true;
      current['DownloadRateLimit'] = 0; // 0 = unlimited
      current['UploadRateLimit'] = 0;   // irrelevant since DisableUpload=true

      // ── TRACKERS ───────────────────────────────────────────────────────
      // RetrackersMode 1 = add retrackers to every torrent. This overlays
      // our boost trackers on top of whatever the magnet link contains.
      current['RetrackersMode'] = 1;

      // ── ENCRYPTION ─────────────────────────────────────────────────────
      // ForceEncrypt=false allows connections to both encrypted AND plaintext
      // peers. Some ISPs throttle BitTorrent regardless of encryption, but
      // forcing encryption cuts you off from ~40% of peers.
      current['ForceEncrypt'] = false;

      // ── TIMEOUT ────────────────────────────────────────────────────────
      // How long before an idle torrent is disconnected from its peers.
      // 86400 = 24 hours. Minimum enforced by server = 30 seconds.
      // Keep the engine hot across binge sessions.
      current['TorrentDisconnectTimeout'] = 86400;

      // ── FEATURES WE DON'T NEED ─────────────────────────────────────────
      current['EnableDLNA'] = false;          // no DLNA, save resources
      current['EnableRutorSearch'] = false;   // no search, save resources
      current['EnableTorznabSearch'] = false; // no Torznab, save resources
      current['EnableDebug'] = false;         // silence verbose logs in prod

      // ── PERSISTENCE ────────────────────────────────────────────────────
      // Store settings as human-readable JSON (not BoltDB binary).
      // Makes debugging much easier and survives DB migrations.
      current['StoreSettingsInJson'] = true;
      current['StoreViewedInJson'] = true;

      final payload = jsonEncode({'action': 'set', 'sets': current});
      _log('Sending settings payload: ${payload.substring(0, payload.length > 500 ? 500 : payload.length)}...');
      
      final setResp = await _httpClient
          .post(settingsUri, headers: _jsonHeaders, body: payload)
          .timeout(const Duration(seconds: 8));

      if (setResp.statusCode == 200) {
        _log('✓ Configuration applied successfully.');
        
        // Verify settings were actually applied by reading them back
        try {
          final verifyResp = await _httpClient
              .post(
                settingsUri,
                headers: _jsonHeaders,
                body: jsonEncode({'action': 'get'}),
              )
              .timeout(const Duration(seconds: 5));
          
          if (verifyResp.statusCode == 200 && verifyResp.body.isNotEmpty) {
            final applied = jsonDecode(verifyResp.body) as Map<String, dynamic>;
            _log('✓ Verified settings:');
            _log('  CacheSize: ${applied['CacheSize']} (expected: $_cacheSize)');
            _log('  PreloadCache: ${applied['PreloadCache']}% (expected: ${_isMobile ? 2 : 1}%)');
            _log('  ReaderReadAHead: ${applied['ReaderReadAHead']}% (expected: 95%)');
            _log('  ResponsiveMode: ${applied['ResponsiveMode']} (expected: true)');
            _log('  Strategy: ${applied['Strategy']} (expected: 2)');
            _log('  ConnectionsLimit: ${applied['ConnectionsLimit']} (expected: $_connectionsLimit)');
            _log('  DisableUpload: ${applied['DisableUpload']} (expected: true)');
            _log('  RetrackersMode: ${applied['RetrackersMode']} (expected: 1)');
          }
        } catch (e) {
          _log('Could not verify settings (non-fatal): $e');
        }
      } else {
        _log('⚠ Settings apply returned HTTP ${setResp.statusCode}: ${setResp.body}');
      }
    } catch (e) {
      _log('Configuration error (non-fatal): $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Magnet boosting
  // ─────────────────────────────────────────────────────────────────────────

  String _boostMagnet(String magnet) {
    // Parse existing trackers to avoid duplicates (set semantics).
    final existingTrackers = <String>{};
    final uri = Uri.tryParse(magnet);
    if (uri != null) {
      for (final tr in uri.queryParametersAll['tr'] ?? []) {
        existingTrackers.add(Uri.decodeComponent(tr));
      }
    }

    final buffer = StringBuffer(magnet);
    for (final tracker in _trackers) {
      if (!existingTrackers.contains(tracker)) {
        buffer.write('&tr=${Uri.encodeComponent(tracker)}');
      }
    }
    return buffer.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Hash extraction
  // ─────────────────────────────────────────────────────────────────────────

  String? _extractHash(String magnetOrHash) {
    // Already a bare hash (40 or 64 hex chars).
    if (RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(magnetOrHash) ||
        RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(magnetOrHash)) {
      return magnetOrHash.toLowerCase();
    }

    // Standard magnet URI.
    if (magnetOrHash.startsWith('magnet:?')) {
      final uri = Uri.tryParse(magnetOrHash);
      final xt = uri?.queryParameters['xt'] ?? '';
      if (xt.startsWith('urn:btih:')) {
        return xt.substring('urn:btih:'.length).toLowerCase();
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core: add torrent & get stream URL
  // ─────────────────────────────────────────────────────────────────────────

  /// Adds a torrent and returns a ready-to-play HTTP URL.
  ///
  /// [magnetLink] — magnet URI or info-hash string.
  /// [season] / [episode] — optional, for TV show file selection.
  ///
  /// Returns null if the engine is unreachable or metadata cannot be resolved.
  Future<String?> streamTorrent(
    String magnetLink, {
    int? season,
    int? episode,
    int? fileIdx, // Optional preferred file index hint from Stremio addon
  }) async {
    // Ensure engine is running.
    if (_state != EngineState.ready) {
      final started = await start();
      if (!started) {
        _log('Cannot stream: engine failed to start.');
        return null;
      }
    }

    final hash = _extractHash(magnetLink);
    if (hash == null) {
      _log('Cannot extract info-hash from: $magnetLink');
      return null;
    }

    final boostedMagnet = _boostMagnet(magnetLink);
    final torrentsUri = Uri.parse('$_base/torrents');

    // ── Step 1: Add torrent with BT-client-not-connected recovery ─────────
    final added = await _addTorrentWithRetry(
      torrentsUri: torrentsUri,
      magnet: boostedMagnet,
      hash: hash,
    );
    if (!added) {
      _log('Failed to add torrent $hash after retries.');
      return null;
    }

    // ── Step 2: Resolve file index ────────────────────────────────────────
    // Always poll for metadata — TorrServer must know the file list before it
    // can serve any stream. fileIdx from the Stremio addon is a preferred-file
    // hint used during selection, but does NOT skip the polling.
    _log('Polling metadata for $hash… (preferred fileIdx: $fileIdx)');
    final fileInfo = await _resolveFileIndex(
      torrentsUri: torrentsUri,
      hash: hash,
      season: season,
      episode: episode,
      preferredIdx: fileIdx,
    );

    if (fileInfo == null) {
      _log('Could not resolve a video file for $hash');
      return null;
    }

    // ── Step 3: Build and return the stream URL ────────────────────────────
    // ?play  → TorrServer opens the byte-range HTTP stream immediately.
    // Use the actual filename from the torrent for better codec detection
    // and proper MIME type handling by the server.
    final encodedFilename = Uri.encodeComponent(fileInfo.filename);
    final streamUrl = '$_base/stream/$encodedFilename?link=$hash&index=${fileInfo.index}&play';
    _log('Stream URL ready: $streamUrl');

    return streamUrl;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Add torrent with recovery
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> _addTorrentWithRetry({
    required Uri torrentsUri,
    required String magnet,
    required String hash,
  }) async {
    // First, check if this torrent is already known to the server.
    if (await _torrentExists(torrentsUri, hash)) {
      _log('Torrent $hash already in server DB.');
      return true;
    }

    for (int attempt = 0; attempt < 6; attempt++) {
      try {
        final response = await _httpClient
            .post(
              torrentsUri,
              headers: _jsonHeaders,
              body: jsonEncode({
                'action': 'add',
                'link': magnet,
                'save_to_db': false, // Don't pollute DB with streaming ephemera
              }),
            )
            .timeout(const Duration(seconds: 8));

        final body = response.body;

        // BT engine not connected yet — restart it.
        if (body.contains('BT client not connected')) {
          _log('BT client not connected on attempt $attempt — restarting…');
          await _restartBtEngine();
          continue;
        }

        if (response.statusCode == 200) {
          _log('Torrent add: OK');
          return true;
        }

        // 400 may mean torrent already exists.
        if (response.statusCode == 400) {
          if (await _torrentExists(torrentsUri, hash)) {
            _log('Torrent $hash already existed (400 → confirmed).');
            return true;
          }
        }

        // 500 — server-side error; wait for BT readiness.
        if (response.statusCode == 500) {
          _log('Server 500 on attempt $attempt — waiting for BT ready…');
          await _waitForBtReady(timeout: const Duration(seconds: 8));
        }

        _log('Add attempt $attempt failed: HTTP ${response.statusCode}');
      } catch (e) {
        _log('Add attempt $attempt threw: $e');
      }

      // Exponential backoff: 0.5s, 1s, 2s, 4s, 8s
      final delay = Duration(milliseconds: 500 * (1 << attempt.clamp(0, 4)));
      await Future.delayed(delay);
    }

    return false;
  }

  Future<bool> _torrentExists(Uri torrentsUri, String hash) async {
    try {
      final resp = await _httpClient
          .post(
            torrentsUri,
            headers: _jsonHeaders,
            body: jsonEncode({'action': 'get', 'hash': hash}),
          )
          .timeout(const Duration(seconds: 4));
      return resp.statusCode == 200 &&
          resp.body.isNotEmpty &&
          !resp.body.contains('null');
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Metadata resolution & file selection
  // ─────────────────────────────────────────────────────────────────────────

  /// Polls /torrents?action=get until file_stats appears, then selects the
  /// best video file, sets its download priority to 1 (active), and returns
  /// its index and filename.
  Future<({int index, String filename})?> _resolveFileIndex({
    required Uri torrentsUri,
    required String hash,
    int? season,
    int? episode,
    int? preferredIdx, // Stremio fileIdx hint — used when S/E match fails
    int maxPollMs = 30000, // 30 seconds total
  }) async {
    const pollInterval = Duration(milliseconds: 250);
    final deadline = DateTime.now().add(Duration(milliseconds: maxPollMs));
    int? bestIndex;
    String? bestFilename;
    bool priorityCommitted = false;

    while (DateTime.now().isBefore(deadline)) {
      try {
        final resp = await _httpClient
            .post(
              torrentsUri,
              headers: _jsonHeaders,
              body: jsonEncode({'action': 'get', 'hash': hash}),
            )
            .timeout(const Duration(seconds: 4));

        if (resp.statusCode != 200) {
          await Future.delayed(pollInterval);
          continue;
        }

        final data = jsonDecode(resp.body) as Map<String, dynamic>?;
        if (data == null) {
          await Future.delayed(pollInterval);
          continue;
        }

        // TorrServer uses 'file_stats' in newer versions, 'files' in older.
        final rawFiles =
            (data['file_stats'] ?? data['files']) as List<dynamic>?;
        if (rawFiles == null || rawFiles.isEmpty) {
          await Future.delayed(pollInterval);
          continue;
        }

        // ── File selection ─────────────────────────────────────────────
        final files = rawFiles.cast<Map<String, dynamic>>();
        int? bestEpisodeMatch;
        String? bestEpisodeFilename;
        int bestEpisodeSize = -1;
        int? largestVideo;
        String? largestVideoFilename;
        int largestSize = -1;

        for (final f in files) {
          final name = (f['path'] ?? f['name'] ?? '') as String;
          final size = (f['length'] ?? 0) as int;
          final id = f['id'] as int;

          if (!TorrentFilter.isVideoFile(name)) continue;

          if (season != null && episode != null) {
            if (TorrentFilter.isFileMatch(name, season, episode)) {
              // Multiple files can match (e.g. BTS clips vs actual episode).
              // Keep the largest one — it's almost certainly the real episode.
              if (size > bestEpisodeSize) {
                bestEpisodeSize = size;
                bestEpisodeMatch = id;
                bestEpisodeFilename = name;
              }
            }
          }

          if (size > largestSize) {
            largestSize = size;
            largestVideo = id;
            largestVideoFilename = name;
          }
        }

        // Priority order:
        // 1. S/E pattern match (most reliable for TV)
        // 2. preferredIdx from Stremio addon (addon knows exactly which file) - BUT only if it's a video file
        // 3. Largest video file (fallback)
        int? preferredFile;
        String? preferredFilename;
        if (preferredIdx != null) {
          // Find the file whose id matches preferredIdx AND is a video file
          final match = files.where((f) {
            final id = f['id'] as int;
            final name = (f['path'] ?? f['name'] ?? '') as String;
            return id == preferredIdx && TorrentFilter.isVideoFile(name);
          }).toList();
          if (match.isNotEmpty) {
            preferredFile = preferredIdx;
            preferredFilename = (match.first['path'] ?? match.first['name'] ?? '') as String;
            _log('Using preferredIdx $preferredIdx (validated as video file)');
          } else {
            _log('preferredIdx $preferredIdx is not a video file, ignoring');
          }
        }

        bestIndex = bestEpisodeMatch ?? preferredFile ?? largestVideo;
        bestFilename = bestEpisodeFilename ?? preferredFilename ?? largestVideoFilename;

        if (bestIndex != null && !priorityCommitted) {
          // ── Set download priority ──────────────────────────────────
          // Priority list: index = file position in list, value = priority.
          // 1 = normal, 0 = disabled (don't download).
          // We enable only the target file to concentrate bandwidth.
          final priorities = files.map((f) {
            return (f['id'] as int) == bestIndex ? 1 : 0;
          }).toList();

          try {
            await _httpClient.post(
              torrentsUri,
              headers: _jsonHeaders,
              body: jsonEncode({
                'action': 'set',
                'hash': hash,
                'priority': priorities,
              }),
            ).timeout(const Duration(seconds: 4));
            priorityCommitted = true;
            _log('Priority committed for file index $bestIndex.');
          } catch (e) {
            _log('Priority set error (non-fatal): $e');
          }

          // Return immediately after first successful priority commit.
          // We don't need to wait for the full 30-second window.
          if (bestFilename != null) {
            return (index: bestIndex, filename: bestFilename);
          }
        }
      } catch (e) {
        _log('Metadata poll error: $e');
      }

      await Future.delayed(pollInterval);
    }

    _log('Metadata timeout. Best index so far: $bestIndex');
    if (bestIndex != null && bestFilename != null) {
      return (index: bestIndex, filename: bestFilename);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Engine restart (BT client recovery)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _restartBtEngine() async {
    _log('Restarting BT engine…');
    await stop();
    await Future.delayed(const Duration(milliseconds: 800));
    await start();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Torrent management
  // ─────────────────────────────────────────────────────────────────────────

  /// Removes a torrent from TorrServer (stops seeding/leeching, frees cache).
  Future<void> removeTorrent(String magnetOrHash) async {
    final hash = _extractHash(magnetOrHash);
    if (hash == null) return;
    try {
      await _httpClient.post(
        Uri.parse('$_base/torrents'),
        headers: _jsonHeaders,
        body: jsonEncode({'action': 'rem', 'hash': hash}),
      ).timeout(const Duration(seconds: 5));
      _log('Removed torrent $hash.');
    } catch (e) {
      _log('Remove torrent error: $e');
    }
  }

  /// Drops a torrent (disconnects peers but keeps DB entry).
  Future<void> dropTorrent(String magnetOrHash) async {
    final hash = _extractHash(magnetOrHash);
    if (hash == null) return;
    try {
      await _httpClient.post(
        Uri.parse('$_base/torrents'),
        headers: _jsonHeaders,
        body: jsonEncode({'action': 'drop', 'hash': hash}),
      ).timeout(const Duration(seconds: 5));
      _log('Dropped torrent $hash.');
    } catch (e) {
      _log('Drop torrent error: $e');
    }
  }

  /// Lists all torrents in the server DB.
  Future<List<Map<String, dynamic>>> listTorrents() async {
    try {
      final resp = await _httpClient.post(
        Uri.parse('$_base/torrents'),
        headers: _jsonHeaders,
        body: jsonEncode({'action': 'list'}),
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return [];
      final decoded = jsonDecode(resp.body);
      if (decoded == null) return [];
      return List<Map<String, dynamic>>.from(decoded as List);
    } catch (e) {
      _log('List torrents error: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Rich statistics
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns rich stats for a torrent, or null if unavailable.
  Future<TorrentStats?> getTorrentStats(String magnetOrHash) async {
    final hash = _extractHash(magnetOrHash);
    if (hash == null) return null;

    try {
      final resp = await _httpClient.post(
        Uri.parse('$_base/torrents'),
        headers: _jsonHeaders,
        body: jsonEncode({'action': 'get', 'hash': hash}),
      ).timeout(const Duration(seconds: 4));

      if (resp.statusCode != 200 || resp.body.isEmpty) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>?;
      if (json == null) return null;

      final rawSpeed = (json['download_speed'] ?? 0.0) as num;
      final speedMbps = rawSpeed.toDouble() / 1024 / 1024;
      final activePeers = (json['active_peers'] ?? 0) as int;
      final totalPeers = (json['total_peers'] ?? 0) as int;
      final loadedBytes = (json['preload_size'] ?? 0) as int;
      final totalBytes = (json['total_size'] ?? 0) as int;
      final torrentHash = (json['hash'] ?? hash) as String;

      final cachePercent = totalBytes > 0
          ? (loadedBytes / totalBytes) * 100.0
          : 0.0;

      return TorrentStats(
        speedMbps: speedMbps,
        activePeers: activePeers,
        totalPeers: totalPeers,
        cachePercent: cachePercent,
        loadedBytes: loadedBytes,
        totalBytes: totalBytes,
        hash: torrentHash,
        isConnected: activePeers > 0,
      );
    } catch (e) {
      _log('Stats error: $e');
      return null;
    }
  }

  /// Convenience: poll stats at [interval] until [onStats] returns false or
  /// the returned [StreamSubscription] is cancelled.
  Stream<TorrentStats> statsStream(
    String magnetOrHash, {
    Duration interval = const Duration(seconds: 1),
  }) {
    final controller = StreamController<TorrentStats>();
    Timer? timer;

    controller.onListen = () {
      timer = Timer.periodic(interval, (_) async {
        final stats = await getTorrentStats(magnetOrHash);
        if (stats != null && !controller.isClosed) {
          controller.add(stats);
        }
      });
    };

    controller.onCancel = () {
      timer?.cancel();
      controller.close();
    };

    return controller.stream;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Server info
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the TorrServer version string (e.g. "MatriX.137").
  Future<String?> getServerVersion() async {
    try {
      final resp = await _httpClient
          .get(Uri.parse('$_base/echo'))
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) return resp.body.trim();
    } catch (_) {}
    return null;
  }

  /// Returns the M3U playlist URL for all files in a torrent.
  String m3uPlaylistUrl(String hash) => '$_base/stream/fname?link=$hash&m3u';

  /// Returns the stream URL for a specific file index.
  String fileStreamUrl(String hash, int fileIndex) =>
      '$_base/stream/video.mp4?link=$hash&index=$fileIndex&play';

  /// Returns a stream URL that resumes from last-watched position.
  String resumeStreamUrl(String hash, int fileIndex) =>
      '$_base/stream/video.mp4?link=$hash&index=$fileIndex&m3u&fromlast';

  // ─────────────────────────────────────────────────────────────────────────
  // Stop / cleanup
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    _setState(EngineState.stopped);
    _serverProcess?.kill();
    _serverProcess = null;
    await _killExternalProcesses();
    _log('Engine stopped.');
  }

  Future<void> cleanup() async {
    await stop();
    _httpClient.close();
  }

  Future<void> _killExternalProcesses() async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/T', '/IM', 'TorrServer.exe']);
      } else if (Platform.isAndroid || Platform.isLinux || Platform.isMacOS) {
        await Process.run('pkill', ['-9', '-f', 'TorrServer']);
      }
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  void _setState(EngineState s) {
    if (_state == s) return;
    _state = s;
    onStateChanged?.call(s);
  }

  void _log(String message) {
    debugPrint('[TorrServer] $message');
    onLogLine?.call(message);
  }
}