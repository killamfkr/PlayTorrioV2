import 'dart:io';

import 'package:flutter/services.dart';

/// Android TV / Fire TV detection via [MainActivity] (leanback, television UI mode).
class AndroidTvPlatform {
  AndroidTvPlatform._();

  static const MethodChannel _channel = MethodChannel('play_torrio/platform');

  /// Set in [initAndroid] before [runApp]. Safe to read from widgets after boot.
  static bool isTv = false;

  /// Call once after [WidgetsFlutterBinding.ensureInitialized] on Android.
  static Future<void> initAndroid() async {
    if (!Platform.isAndroid) {
      isTv = false;
      return;
    }
    try {
      final v = await _channel.invokeMethod<bool>('isAndroidTv');
      isTv = v == true;
    } catch (_) {
      isTv = false;
    }
  }
}
