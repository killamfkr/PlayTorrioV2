import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stand-in for PlayTorrio [SettingsService] (IPTV player + optional light theme).
class SettingsService {
  SettingsService();

  static const _bgKey = 'iptv_scraper_continue_playback_bg';
  static const _lightKey = 'iptv_scraper_light_mode';

  static final ValueNotifier<bool> continuePlaybackInBackgroundNotifier =
      ValueNotifier<bool>(true);

  static final ValueNotifier<bool> lightModeNotifier = ValueNotifier<bool>(false);

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    continuePlaybackInBackgroundNotifier.value = p.getBool(_bgKey) ?? true;
    lightModeNotifier.value = p.getBool(_lightKey) ?? false;
  }

  Future<bool> continuePlaybackInBackground() async {
    return continuePlaybackInBackgroundNotifier.value;
  }
}
