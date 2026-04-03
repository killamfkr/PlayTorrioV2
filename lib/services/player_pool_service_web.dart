import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PlayerPoolService {
  static final PlayerPoolService _instance = PlayerPoolService._internal();
  factory PlayerPoolService() => _instance;
  PlayerPoolService._internal();

  bool _isReady = false;

  Future<void> warmUp() async {
    debugPrint('[PlayerPool] Web: pre-warm skipped');
  }

  ({Player player, VideoController controller}) getPlayer() {
    debugPrint('[PlayerPool] Web: creating player');
    final player = Player(
      configuration: const PlayerConfiguration(
        libass: true,
      ),
    );
    final controller = VideoController(player);
    return (player: player, controller: controller);
  }

  bool get isReady => _isReady;

  Future<void> dispose() async {
    _isReady = false;
  }
}
