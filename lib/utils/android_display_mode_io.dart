import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel _kDisplayChannel =
    MethodChannel('com.example.play_torrio_native/display');

/// Requests a [WindowManager] display mode whose refresh rate is closest to
/// [fps] (e.g. 23.976 → 24 Hz mode on many TVs). Returns false if unsupported.
Future<bool> setPreferredVideoRefreshRate(double fps) async {
  if (!Platform.isAndroid) return false;
  try {
    final ok = await _kDisplayChannel
        .invokeMethod<bool>('setPreferredVideoRefreshRate', {'fps': fps});
    return ok ?? false;
  } catch (_) {
    return false;
  }
}

/// Restores default display mode (preferredDisplayModeId / refresh rate 0).
Future<void> clearPreferredVideoDisplayMode() async {
  if (!Platform.isAndroid) return;
  try {
    await _kDisplayChannel.invokeMethod<void>('clearPreferredDisplayMode');
  } catch (_) {}
}
