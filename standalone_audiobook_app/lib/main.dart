import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
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

/// Set when [AudioService.init] fails in [main]; shown once on the home screen.
String? audiobookAudioInitWarning;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  AudiobookPlayerService().ensurePlayerListeners();

  await _configureAudioSession();
  if (platformIsAndroid) {
    await Permission.notification.request();
  }

  try {
    final audioHandler = await AudioService.init(
      builder: () => PlayTorrioAudioHandler(MusicPlayerService().player),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.playtorrio.stories.channel.audio',
        androidNotificationChannelName: 'Stories playback',
        androidNotificationChannelDescription:
            'Playback controls and now playing for Stories',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
        androidResumeOnClick: true,
        preloadArtwork: true,
        fastForwardInterval: const Duration(seconds: 30),
        rewindInterval: const Duration(seconds: 15),
      ),
    );
    MusicPlayerService().setHandler(audioHandler);
    AudiobookPlayerService().attachHandler(audioHandler);
    debugPrint('[Stories] AudioService ready');
  } catch (e, st) {
    debugPrint('[Stories] AudioService failed: $e\n$st');
    audiobookAudioInitWarning =
        'Lock-screen notification unavailable ($e). Rebuild after running tool/patch_android.sh.';
  }

  runApp(const StoriesApp());
}

class StoriesApp extends StatelessWidget {
  const StoriesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stories',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.materialTheme,
      home: const StoriesBootstrapScreen(),
    );
  }
}

/// Starts torrent/proxy engines, then opens the library.
class StoriesBootstrapScreen extends StatefulWidget {
  const StoriesBootstrapScreen({super.key});

  @override
  State<StoriesBootstrapScreen> createState() => _StoriesBootstrapScreenState();
}

class _StoriesBootstrapScreenState extends State<StoriesBootstrapScreen> {
  bool _ready = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() => _status = 'Opening your library…');

    await Future.wait([
      LocalServerService().start().catchError((Object e) {
        debugPrint('[Stories] LocalServer failed: $e');
      }),
      TorrentStreamService()
          .start()
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () {
              debugPrint('[Stories] Torrent engine timed out');
              return false;
            },
          )
          .catchError((Object e, StackTrace st) {
            debugPrint('[Stories] Torrent engine failed: $e\n$st');
            return false;
          }),
    ]);

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return AudiobookScreen(initWarning: audiobookAudioInitWarning);
    }

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/icon/icon.png',
                width: 88,
                height: 88,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 28),
            Text('Stories', style: AppTheme.displayTitle.copyWith(fontSize: 36)),
            const SizedBox(height: 8),
            Text(
              'Your audiobook library',
              style: AppTheme.sectionTitle.copyWith(letterSpacing: 0.4),
            ),
            const SizedBox(height: 36),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primaryColor,
              ),
            ),
            if (_status != null) ...[
              const SizedBox(height: 18),
              Text(_status!, style: Theme.of(context).textTheme.bodySmall),
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
    debugPrint('[Stories] AudioSession: $e');
  }
}
