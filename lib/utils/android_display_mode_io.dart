import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel _kDisplayChannel =
    MethodChannel('com.example.play_torrio_native/display');

/// Picks a [Display.Mode] whose refresh rate **divides evenly** into [contentFps]
/// (e.g. 23.976 → 24/48/120 Hz preferred over 60 Hz). Returns false if unsupported.
Future<bool> setPreferredVideoRefreshRate(double contentFps) async {
  if (!Platform.isAndroid) return false;
  try {
    final ok = await _kDisplayChannel.invokeMethod<bool>(
      'setPreferredVideoRefreshRate',
      {'fps': contentFps},
    );
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
