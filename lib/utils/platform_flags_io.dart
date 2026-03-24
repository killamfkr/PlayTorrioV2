import 'dart:io' show Platform;

import '../platform/android_tv_platform.dart';

/// Android phone / tablet (not TV): show Android Auto notice in Settings.
bool get showAndroidAutoSettingsDisclaimer =>
    Platform.isAndroid && !AndroidTvPlatform.isTv;
