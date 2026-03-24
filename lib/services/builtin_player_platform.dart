import 'dart:io';

import 'package:flutter/services.dart';

/// Android Picture-in-Picture for the built-in player (MainActivity channel).
class BuiltinPlayerPlatform {
  static const _channel = MethodChannel('play_torrio/builtin_player');

  static Future<bool> enterPictureInPicture() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('enterPictureInPicture');
      return ok ?? false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
