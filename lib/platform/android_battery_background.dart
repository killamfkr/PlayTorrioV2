import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android: ask the user to allow unrestricted battery so playback/torrents
/// are less likely to be killed in the background.
class AndroidBatteryBackground {
  AndroidBatteryBackground._();

  static const MethodChannel _channel = MethodChannel('play_torrio/platform');
  static const _prefsKeyLastVc = 'android_battery_nudge_last_build';

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb) return true;
    try {
      final v = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return v == true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> openBatteryOptimizationRequest() async {
    try {
      final v = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return v == true;
    } catch (_) {
      return false;
    }
  }

  /// After each versionCode bump, nudge once on cold start if still battery-restricted.
  static Future<void> requestAfterUpgradeIfNeeded() async {
    if (kIsWeb) return;
    try {
      if (await isIgnoringBatteryOptimizations()) return;
      final info = await PackageInfo.fromPlatform();
      final vc = int.tryParse(info.buildNumber) ?? 0;
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_prefsKeyLastVc) ?? 0;
      if (vc <= last) return;
      await prefs.setInt(_prefsKeyLastVc, vc);
      await openBatteryOptimizationRequest();
    } catch (_) {}
  }
}
