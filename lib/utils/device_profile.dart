import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Runtime device traits from the native embedder (Android TV, etc.).
class DeviceProfile {
  DeviceProfile._();

  static const MethodChannel _channel =
      MethodChannel('com.example.play_torrio_native/device');

  static bool _androidTv = false;
  static bool _inited = false;

  /// True when running as a leanback / television UI mode on Android.
  static bool get isAndroidTv => _androidTv;

  /// Call once after [WidgetsFlutterBinding.ensureInitialized].
  static Future<void> initAndroidProfile() async {
    if (_inited) return;
    _inited = true;
    if (!Platform.isAndroid) return;
    try {
      final v = await _channel.invokeMethod<bool>('isAndroidTv');
      _androidTv = v ?? false;
    } catch (_) {
      _androidTv = false;
    }
  }

  /// [BackdropFilter] blur is very expensive on Android TV GPUs; keep the same
  /// clip and frosted colors but skip the per-frame blur sampling.
  static Widget backdropBlurOrPlain({
    required Widget child,
    required double sigma,
    required BorderRadius borderRadius,
  }) {
    if (isAndroidTv) {
      return ClipRRect(borderRadius: borderRadius, child: child);
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}
