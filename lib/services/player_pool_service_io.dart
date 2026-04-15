import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Pre-warms media_kit players during app startup for instant playback
class PlayerPoolService {
  static final PlayerPoolService _instance = PlayerPoolService._internal();
  factory PlayerPoolService() => _instance;
  PlayerPoolService._internal();

  Player? _warmPlayer;
  bool _isReady = false;

  /// Pre-warm a player during app initialization (DISABLED)
  Future<void> warmUp() async {
    debugPrint('[PlayerPool] Pre-warming DISABLED - players created on demand');
    return;
  }

  /// Get a fresh player (pre-warming disabled)
  ({Player player, VideoController controller}) getPlayer() {
    debugPrint('[PlayerPool] Creating fresh player');
    final player = Player(
      configuration: PlayerConfiguration(
        libass: !Platform.isAndroid,
      ),
    );
    
    final controller = VideoController(player);
    
    return (player: player, controller: controller);
  }

  /// Check if a warm player is ready
  bool get isReady => _isReady;

  /// Dispose the warm player (call on app shutdown)
  Future<void> dispose() async {
    if (_warmPlayer != null) {
      debugPrint('[PlayerPool] Disposing warm player');
      await _warmPlayer!.dispose();
      _warmPlayer = null;
      _isReady = false;
    }
  }
}
