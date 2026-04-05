import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'api/torrent_stream_service.dart';
import 'services/player_pool_service.dart';
import 'utils/webview_cleanup.dart';
import 'utils/app_theme.dart';
import 'utils/tv_guide_refresh.dart';
import 'platform_flags.dart';

import 'play_torrio_splash.dart';

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
    if (platformIsDesktop) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
  }

  @override
  void dispose() {
    if (platformIsDesktop) {
      windowManager.removeListener(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (platformIsDesktop) {
      final isPreventClose = await windowManager.isPreventClose();
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
    if (state == AppLifecycleState.resumed) {
      TvGuideRefresh.bump();
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
