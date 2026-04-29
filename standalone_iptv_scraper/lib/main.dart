import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'api/settings_service.dart';
import 'features/iptv/playtorrio_tv/screens/iptv_pt_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.init();
  MediaKit.ensureInitialized();
  runApp(const IptvScraperApp());
}

class IptvScraperApp extends StatelessWidget {
  const IptvScraperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.lightModeNotifier,
      builder: (_, light, __) {
        return MaterialApp(
          title: 'PT IPTV',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: light ? Brightness.light : Brightness.dark,
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1565C0),
              brightness: light ? Brightness.light : Brightness.dark,
            ),
          ),
          home: const IptvPtScreen(),
        );
      },
    );
  }
}
