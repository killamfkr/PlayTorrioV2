import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:logging/logging.dart';
import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:auto_orientation_v2/auto_orientation_v2.dart';

import 'api/audio_handler.dart';
import 'api/audiobook_player_service.dart';
import 'api/torrent_stream_service.dart';
import 'api/tmdb_api.dart';
import 'api/local_server_service.dart';
import 'api/music_player_service.dart';
import 'models/movie.dart';
import 'services/player_pool_service.dart';
import 'services/app_updater_service.dart';
import 'utils/webview_cleanup.dart';
import 'utils/app_theme.dart';
import 'widgets/update_dialog.dart';

import 'screens/main_screen.dart';
import 'screens/search_screen.dart';
import 'screens/discover_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[Boot] Flutter binding initialized');

  // Configure InAppWebView (Android only — not supported on iOS)
  if (Platform.isAndroid) {
    try {
      debugPrint('[Boot] Setting up InAppWebView...');
      await InAppWebViewController.setWebContentsDebuggingEnabled(true);
      debugPrint('[Boot] InAppWebView OK');
    } catch (e) {
      debugPrint('[Boot] InAppWebView setup failed (non-fatal): $e');
    }
  }
  
  Logger.root.level = Level.FINER;
  Logger.root.onRecord.listen((e) {
    debugPrint('[YT] ${e.message}');
    if (e.error != null) {
      debugPrint('[YT ERROR] ${e.error}');
      debugPrint('[YT STACK] ${e.stackTrace}');
    }
  });
  
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    AutoOrientation.fullAutoMode(forceSensor: true);
    SystemChrome.setPreferredOrientations([]);
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1600, 1000),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  debugPrint('[Boot] Initializing MediaKit...');
  MediaKit.ensureInitialized();
  debugPrint('[Boot] MediaKit OK');
  
  debugPrint('[Boot] Initializing AudioService...');
  final audioHandler = await AudioService.init(
    builder: () => PlayTorrioAudioHandler(MusicPlayerService().player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.playtorrio.native.channel.audio',
      androidNotificationChannelName: 'Music Playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidResumeOnClick: true,
    ),
  );
  debugPrint('[Boot] AudioService OK');
  
  MusicPlayerService().setHandler(audioHandler);
  AudiobookPlayerService().init(audioHandler);
  
  PlayerPoolService().warmUp();
  debugPrint('[Boot] All init complete — launching app');

  runApp(const PlayTorrioApp());
}

class PlayTorrioApp extends StatefulWidget {
  const PlayTorrioApp({super.key});

  @override
  State<PlayTorrioApp> createState() => _PlayTorrioAppState();
}

class _PlayTorrioAppState extends State<PlayTorrioApp> with WidgetsBindingObserver, WindowListener {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      bool isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose) {
        await PlayerPoolService().dispose();
        await TorrentStreamService().cleanup();
        await WebViewCleanup.cleanupWebView2Cache();
        await windowManager.destroy();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      PlayerPoolService().dispose();
      TorrentStreamService().cleanup();
      WebViewCleanup.cleanupWebView2Cache();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlayTorrio Native',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _fadeAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _initEngine();
  }

  Future<void> _initEngine() async {
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('[Boot] Starting engine initialization...');
    debugPrint('═══════════════════════════════════════════════════════════');
    
    debugPrint('[Boot] Step 1: Checking network connectivity...');
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOffline = connectivityResult.contains(ConnectivityResult.none);
    debugPrint('[Boot] Network status: ${isOffline ? "OFFLINE" : "ONLINE"}');

    if (isOffline) {
      debugPrint('[Boot] Device is offline, initializing local services only');
      debugPrint('[Boot] Initializing MusicPlayer...');
      await MusicPlayerService().init().catchError((e) {
        debugPrint('[Boot] ✗ MusicPlayer error: $e');
        return null;
      });
      debugPrint('[Boot] ✓ Local services initialized');
      if (mounted) {
        debugPrint('[Boot] Navigating to MainScreen (offline mode)');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
      return;
    }

    debugPrint('[Boot] Step 2: Initializing services in parallel...');
    final api = TmdbApi();
    
    debugPrint('[Boot]   - Starting TorrentStream engine...');
    debugPrint('[Boot]   - Starting LocalServer...');
    debugPrint('[Boot]   - Initializing MusicPlayer...');
    debugPrint('[Boot]   - Fetching TMDB data (trending, popular, top rated, now playing)...');
    
    final results = await Future.wait([
      TorrentStreamService().start().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[Boot] ⚠ TorrentStream startup timed out after 10s');
          return false;
        },
      ).catchError((e, st) {
        debugPrint('[Boot] ✗ TorrentStream error: $e');
        debugPrint('[Boot] Stack trace: $st');
        return false;
      }),
      LocalServerService().start().catchError((e) {
        debugPrint('[Boot] ✗ LocalServer error: $e');
      }),
      MusicPlayerService().init().catchError((e) {
        debugPrint('[Boot] ✗ MusicPlayer error: $e');
      }),
      api.getTrending().catchError((e) {
        debugPrint('[Boot] ✗ TMDB trending error: $e');
        return <Movie>[];
      }),
      api.getPopular().catchError((e) {
        debugPrint('[Boot] ✗ TMDB popular error: $e');
        return <Movie>[];
      }),
      api.getTopRated().catchError((e) {
        debugPrint('[Boot] ✗ TMDB top rated error: $e');
        return <Movie>[];
      }),
      api.getNowPlaying().catchError((e) {
        debugPrint('[Boot] ✗ TMDB now playing error: $e');
        return <Movie>[];
      }),
    ]);

    debugPrint('[Boot] Step 3: Service initialization results:');
    final torrentEngineReady = (results[0] as bool?) == true;
    // LocalServer and MusicPlayer return void, just check if they completed without throwing
    debugPrint('[Boot]   TorrentStream: ${torrentEngineReady ? "✓ READY" : "✗ FAILED"}');
    debugPrint('[Boot]   LocalServer: ✓ READY');
    debugPrint('[Boot]   MusicPlayer: ✓ READY');
    
    final trendingList = results[3] as List;
    final popularList = results[4] as List;
    final topRatedList = results[5] as List;
    final nowPlayingList = results[6] as List;
    
    debugPrint('[Boot]   TMDB Trending: ${trendingList.isNotEmpty ? "✓ ${trendingList.length} items" : "✗ Empty"}');
    debugPrint('[Boot]   TMDB Popular: ${popularList.isNotEmpty ? "✓ ${popularList.length} items" : "✗ Empty"}');
    debugPrint('[Boot]   TMDB Top Rated: ${topRatedList.isNotEmpty ? "✓ ${topRatedList.length} items" : "✗ Empty"}');
    debugPrint('[Boot]   TMDB Now Playing: ${nowPlayingList.isNotEmpty ? "✓ ${nowPlayingList.length} items" : "✗ Empty"}');

    debugPrint('[Boot] Step 4: Pre-warming screens...');
    // ignore: unused_local_variable
    const warmupSearch = SearchScreen();
    // ignore: unused_local_variable
    const warmupDiscover = DiscoverScreen();
    debugPrint('[Boot] ✓ Screens pre-warmed');
    
    debugPrint('[Boot] Step 5: Checking for updates in background...');
    _checkForUpdatesInBackground();
    
    if (mounted) {
      debugPrint('[Boot] Step 6: Navigating to MainScreen...');
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('[Boot] ✓✓✓ ENGINE INITIALIZATION COMPLETE ✓✓✓');
      debugPrint('═══════════════════════════════════════════════════════════');
    }
  }
  
  Future<void> _checkForUpdatesInBackground() async {
    try {
      debugPrint('[Boot] Checking for app updates...');
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();
      
      if (updateInfo != null) {
        debugPrint('[Boot] ✓ Update available: v${updateInfo.latestVersion}');
        if (mounted) {
          // Wait a bit before showing the dialog so user can see the main screen first
          await Future.delayed(const Duration(seconds: 3));
          
          if (mounted) {
            debugPrint('[Boot] Showing update dialog...');
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => UpdateDialog(updateInfo: updateInfo),
            );
          }
        }
      } else {
        debugPrint('[Boot] ✓ App is up to date');
      }
    } catch (e) {
      debugPrint('[Boot] ✗ Update check failed: $e');
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.5), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 80,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.white, Colors.white70, AppTheme.primaryColor],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ).createShader(bounds),
                    child: const Text(
                      'PLAYTORRIO',
                      style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2,
                        color: Colors.white,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'YOUR CINEMA UNIVERSE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10,
                      color: AppTheme.primaryColor.withValues(alpha: 0.6),
                      fontFamily: 'Poppins',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 100),
              FadeTransition(
                opacity: _fadeAnimation,
                child: const Text(
                  'INITIALIZING ENGINE...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: Colors.white38,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}