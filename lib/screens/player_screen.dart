import 'dart:io';
import 'package:flutter/material.dart';
import 'package:play_torrio_native/models/movie.dart';
import 'package:play_torrio_native/models/stream_source.dart';
import '../services/external_player_service.dart';
import '../api/settings_service.dart';
import 'player/mobile_player_screen.dart';
import 'player/desktop_player_screen.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String? audioUrl;
  final String title;
  final String? magnetLink;
  final Map<String, String>? headers;
  final Movie? movie;
  final Map<String, dynamic>? providers;
  final String? activeProvider;
  final int? selectedSeason;
  final int? selectedEpisode;
  final Duration? startPosition;
  final List<StreamSource>? sources;
  final int? fileIndex;
  final List<Map<String, dynamic>>? externalSubtitles;
  final String? stremioId;
  final String? stremioAddonBaseUrl;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    this.audioUrl,
    required this.title,
    this.magnetLink,
    this.headers,
    this.movie,
    this.providers,
    this.activeProvider,
    this.selectedSeason,
    this.selectedEpisode,
    this.startPosition,
    this.sources,
    this.fileIndex,
    this.externalSubtitles,
    this.stremioId,
    this.stremioAddonBaseUrl,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _useExternalPlayer = false;
  bool _externalLaunched = false;
  bool _checkingPlayer = true;
  String _externalPlayerName = '';

  @override
  void initState() {
    super.initState();
    _checkExternalPlayer();
  }

  Future<void> _checkExternalPlayer() async {
    final playerName = await SettingsService().getExternalPlayer();
    final isExternal = playerName != 'Built-in Player';

    if (!mounted) return;

    if (isExternal) {
      setState(() {
        _useExternalPlayer = true;
        _externalPlayerName = playerName;
        _checkingPlayer = false;
      });
      _launchExternal();
    } else {
      setState(() {
        _useExternalPlayer = false;
        _checkingPlayer = false;
      });
    }
  }

  Future<void> _launchExternal() async {
    final success = await ExternalPlayerService.launch(
      url: widget.streamUrl,
      title: widget.title,
      headers: widget.headers,
      context: context,
    );

    if (!mounted) return;

    if (success) {
      setState(() => _externalLaunched = true);
    } else {
      // Player not found — fall back to built-in player
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_externalPlayerName not found. Using built-in player.',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.orange.shade900,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _useExternalPlayer = false;
        _externalLaunched = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Still checking settings
    if (_checkingPlayer) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
        ),
      );
    }

    // External player mode — show a "playing externally" screen
    if (_useExternalPlayer) {
      return _ExternalPlayerWaitScreen(
        title: widget.title,
        playerName: _externalPlayerName,
        streamUrl: widget.streamUrl,
        launched: _externalLaunched,
        onRelaunch: _launchExternal,
        onSwitchBuiltIn: () {
          setState(() {
            _useExternalPlayer = false;
            _externalLaunched = false;
          });
        },
      );
    }

    // Built-in player
    if (Platform.isAndroid || Platform.isIOS) {
      return MobilePlayerScreen(
        mediaPath: widget.streamUrl,
        title: widget.title,
        audioUrl: widget.audioUrl,
        headers: widget.headers,
        movie: widget.movie,
        selectedSeason: widget.selectedSeason,
        selectedEpisode: widget.selectedEpisode,
        magnetLink: widget.magnetLink,
        activeProvider: widget.activeProvider,
        startPosition: widget.startPosition,
        sources: widget.sources,
        fileIndex: widget.fileIndex,
        externalSubtitles: widget.externalSubtitles,
        stremioId: widget.stremioId,
        stremioAddonBaseUrl: widget.stremioAddonBaseUrl,
        providers: widget.providers,
      );
    } else {
      return DesktopPlayerScreen(
        mediaPath: widget.streamUrl,
        title: widget.title,
        audioUrl: widget.audioUrl,
        headers: widget.headers,
        movie: widget.movie,
        selectedSeason: widget.selectedSeason,
        selectedEpisode: widget.selectedEpisode,
        magnetLink: widget.magnetLink,
        activeProvider: widget.activeProvider,
        startPosition: widget.startPosition,
        sources: widget.sources,
        fileIndex: widget.fileIndex,
        externalSubtitles: widget.externalSubtitles,
        stremioId: widget.stremioId,
        stremioAddonBaseUrl: widget.stremioAddonBaseUrl,
        providers: widget.providers,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  EXTERNAL PLAYER WAIT SCREEN
//
//  Shown while the video is playing in an external app. Keeps the app alive
//  (and the torrent engine streaming) while the user watches elsewhere.
// ─────────────────────────────────────────────────────────────────────────────

class _ExternalPlayerWaitScreen extends StatelessWidget {
  final String title;
  final String playerName;
  final String streamUrl;
  final bool launched;
  final VoidCallback onRelaunch;
  final VoidCallback onSwitchBuiltIn;

  const _ExternalPlayerWaitScreen({
    required this.title,
    required this.playerName,
    required this.streamUrl,
    required this.launched,
    required this.onRelaunch,
    required this.onSwitchBuiltIn,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.open_in_new_rounded,
                    color: Color(0xFF7C3AED),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  launched ? 'Playing in $playerName' : 'Launching $playerName...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Subtitle
                Text(
                  title,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Info text
                Text(
                  launched
                      ? 'The stream is being kept alive.\nYou can go back when you\'re done watching.'
                      : 'Opening the video in the external player...',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Action buttons
                if (launched) ...[
                  // Re-launch button
                  SizedBox(
                    width: 260,
                    child: OutlinedButton.icon(
                      onPressed: onRelaunch,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: Text('Re-launch in $playerName'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7C3AED),
                        side: const BorderSide(color: Color(0xFF7C3AED)),
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Switch to built-in button
                  SizedBox(
                    width: 260,
                    child: TextButton.icon(
                      onPressed: onSwitchBuiltIn,
                      icon: const Icon(Icons.play_circle_outline, size: 20),
                      label: const Text('Use Built-in Player Instead'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 20),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Back button
                SizedBox(
                  width: 260,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    label: const Text('Go Back'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
