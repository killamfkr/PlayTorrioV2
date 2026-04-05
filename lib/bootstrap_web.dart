import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';

import 'api/settings_service.dart';
import 'play_torrio_app.dart';

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
  debugPrint('[Boot] Web entry');
  setupAppLogging();

  MediaKit.ensureInitialized();

  await SettingsService().initLightMode();
  await SettingsService().getBuiltinPlayerSubtitlesEnabled();

  runApp(const PlayTorrioApp());
}
