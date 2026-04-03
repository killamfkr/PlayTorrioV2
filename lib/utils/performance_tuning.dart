import 'package:flutter/foundation.dart';

import '../platform_flags.dart';
import 'app_theme.dart';

/// Central rules for skipping expensive GPU work (Android Mali/Adreno, lite mode).
class PerformanceTuning {
  PerformanceTuning._();

  static bool get isAndroidNative => !kIsWeb && platformIsAndroid;

  /// [BackdropFilter] blur: very expensive on many Android GPUs.
  static bool get skipBackdropBlur => isAndroidNative || AppTheme.isLightMode;

  /// Extra radial glow layers in [MainScreen] shell.
  static bool get skipAmbientShellGlows => isAndroidNative || AppTheme.isLightMode;

  /// Bottom navigation frosted bar blur.
  static bool get skipBottomNavBlur => isAndroidNative || AppTheme.isLightMode;
}
