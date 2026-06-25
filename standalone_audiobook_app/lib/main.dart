import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api/audiobook_player_service.dart';
import 'api/audio_handler.dart';
import 'api/local_server_service.dart';
import 'api/music_player_service.dart';
import 'api/torrent_stream_service.dart';
import 'platform_flags.dart';
import 'screens/audiobook_screen.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const AudiobookApp());
}

class AudiobookApp extends StatelessWidget {
  const AudiobookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audiobooks',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppTheme.bgDark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.primaryColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const AudiobookBootstrapScreen(),
    );
  }
}

/// Shows UI immediately, then initializes background services (torrent, proxy, audio).
class AudiobookBootstrapScreen extends StatefulWidget {
  const AudiobookBootstrapScreen({super.key});

  @override
  State<AudiobookBootstrapScreen> createState() =>
      _AudiobookBootstrapScreenState();
}

class _AudiobookBootstrapScreenState extends State<AudiobookBootstrapScreen> {
  bool _ready = false;
  String? _status;
  String? _initWarning;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    AudiobookPlayerService().ensurePlayerListeners();

    setState(() => _status = 'Starting audio…');

    await _configureAudioSession();
    if (platformIsAndroid) {
      await Permission.notification.request();
    }

    try {
      final audioHandler = await AudioService.init(
        builder: () => PlayTorrioAudioHandler(MusicPlayerService().player),
        config: AudioServiceConfig(
          androidNotificationChannelId:
              'com.playtorrio.audiobook.channel.audio',
          androidNotificationChannelName: 'Audiobook playback',
          androidNotificationChannelDescription:
              'Playback controls and now playing for audiobooks',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: false,
          androidResumeOnClick: true,
          preloadArtwork: true,
          fastForwardInterval: const Duration(seconds: 30),
          rewindInterval: const Duration(seconds: 15),
        ),
      ).timeout(const Duration(seconds: 15));
      MusicPlayerService().setHandler(audioHandler);
      AudiobookPlayerService().attachHandler(audioHandler);
    } catch (e, st) {
      debugPrint('[AudiobookBootstrap] AudioService failed: $e\n$st');
      _initWarning =
          'Lock-screen notification unavailable; in-app playback still works.';
    }

    if (!mounted) return;
    setState(() => _status = 'Starting local services…');

    await Future.wait([
      LocalServerService().start().catchError((Object e) {
        debugPrint('[AudiobookBootstrap] LocalServer failed: $e');
      }),
      TorrentStreamService()
          .start()
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () {
              debugPrint('[AudiobookBootstrap] Torrent engine timed out');
              return false;
            },
          )
          .catchError((Object e, StackTrace st) {
            debugPrint('[AudiobookBootstrap] Torrent engine failed: $e\n$st');
            return false;
          }),
    ]);

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return AudiobookScreen(initWarning: _initWarning);
    }

    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded,
                size: 72, color: AppTheme.primaryColor),
            const SizedBox(height: 24),
            const Text(
              'Audiobooks',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: AppTheme.primaryColor),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Text(
                _status!,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _configureAudioSession() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));
    await session.setActive(true);
  } catch (e) {
    debugPrint('[AudiobookBootstrap] AudioSession: $e');
  }
}
