import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:logging/logging.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:auto_orientation_v2/auto_orientation_v2.dart';

import 'api/audio_handler.dart';
import 'api/audiobook_player_service.dart';
import 'api/debrid_api.dart';
import 'api/settings_service.dart';
import 'services/watch_history_service.dart';
import 'api/music_player_service.dart';
import 'api/stremio_service.dart';
import 'utils/dlstreams_top_home.dart';
import 'play_torrio_app.dart';
import 'utils/device_profile.dart';
import 'utils/tv_settings_remote_service.dart';
import 'platform_flags.dart';
import 'services/playtorrio_cast_service.dart';
import 'services/playtorrio_cloud_sync_service.dart';

void setupAppLogging() {
  Logger.root.level = Level.FINER;
  Logger.root.onRecord.listen((e) {
    debugPrint('[YT] ${e.message}');
    if (e.error != null) {
      debugPrint('[YT ERROR] ${e.error}');
      debugPrint('[YT STACK] ${e.stackTrace}');
    }
  });
}

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[Boot] Flutter binding initialized');
  await DeviceProfile.initAndroidProfile();
  await TvSettingsRemoteService().ensureStarted();
  if (platformIsAndroid || platformIsIOS) {
    await PlaytorrioCastService.instance.initialize();
  }

  if (platformIsAndroid) {
    try {
      debugPrint('[Boot] Setting up InAppWebView...');
      await InAppWebViewController.setWebContentsDebuggingEnabled(true);
      debugPrint('[Boot] InAppWebView OK');
    } catch (e) {
      debugPrint('[Boot] InAppWebView setup failed (non-fatal): $e');
    }
  }

  setupAppLogging();

  if (platformIsAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (DeviceProfile.isAndroidTv) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      AutoOrientation.fullAutoMode(forceSensor: true);
      await SystemChrome.setPreferredOrientations([]);
    }
  }

  if (platformIsDesktop) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
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
      androidNotificationChannelName: 'Media playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidResumeOnClick: true,
    ),
  );
  debugPrint('[Boot] AudioService OK');

  MusicPlayerService().setHandler(audioHandler);
  AudiobookPlayerService().init(audioHandler);

  await SettingsService().initLightMode();
  await SettingsService().getBuiltinPlayerSubtitlesEnabled();

  await WatchHistoryService.ensureProfileFromSettings();

  await _ensureBundledStremioAddons();

  DebridApi.onDebridKeysChanged = () {
    unawaited(PlaytorrioCloudSyncService.instance.scheduleDebridPush());
  };

  // Restore from cloud when the profile gate is not used (TV, or user disabled gate),
  // so data is not only synced on the phone profile picker.
  unawaited(() async {
    if (kIsWeb) return;
    try {
      if (DeviceProfile.isAndroidTv) {
        await PlaytorrioCloudSyncService.instance.pullOnStartup();
        return;
      }
      final showGate = await SettingsService().getPlaytorrioProfileGateEnabled();
      if (!showGate) {
        await PlaytorrioCloudSyncService.instance.pullOnStartup();
      }
    } catch (e) {
      debugPrint('[Boot] cloud pull: $e');
    }
  }());

  runApp(const PlayTorrioApp());
}

/// Pre-installs community addons we curate in the app (user can remove in Settings).
Future<void> _ensureBundledStremioAddons() async {
  if (!platformIsAndroid && !platformIsIOS) return;
  try {
    final settings = SettingsService();
    final existing = await settings.getStremioAddons();
    final hasDlstreams = existing.any(
      (a) => '${a['baseUrl']}'.toLowerCase().contains('dlstreams.top'),
    );
    if (hasDlstreams) return;
    final fetched = await StremioService().fetchManifest(kDlstreamsTopManifestUrl);
    if (fetched == null) {
      debugPrint('[Boot] dlstreams.top manifest not available (skipped)');
      return;
    }
    await settings.saveStremioAddon(fetched);
    debugPrint('[Boot] Bundled Stremio addon: dlstreams.top');
  } catch (e) {
    debugPrint('[Boot] Bundled Stremio addons: $e');
  }
}
