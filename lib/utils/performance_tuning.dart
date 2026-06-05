import 'package:flutter/foundation.dart';

import '../platform_flags.dart';
import 'app_theme.dart';
import 'device_profile.dart';

/// Central rules for skipping expensive GPU work (Android Mali/Adreno, lite mode).
class PerformanceTuning {
  PerformanceTuning._();

  static bool get isAndroidNative => !kIsWeb && platformIsAndroid;

  /// Leanback / Android TV — weaker SoCs; extra home-shell optimizations.
  static bool get isAndroidTvLeanback =>
      isAndroidNative && DeviceProfile.isAndroidTv;

  /// [BackdropFilter] blur: very expensive on many Android GPUs.
  static bool get skipBackdropBlur => isAndroidNative || AppTheme.isLightMode;

  /// Extra radial glow layers in [MainScreen] shell.
  static bool get skipAmbientShellGlows => isAndroidNative || AppTheme.isLightMode;

  /// Bottom navigation frosted bar blur.
  static bool get skipBottomNavBlur => isAndroidNative || AppTheme.isLightMode;

  /// Home hero auto-rotate — costly on TV; also avoids index drift vs. [PageView].
  static bool get skipHomeHeroAutoAdvance => isAndroidTvLeanback;

  static bool get skipHomeAmbientGlows =>
      AppTheme.isLightMode || isAndroidTvLeanback;
}
