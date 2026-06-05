import 'package:flutter/foundation.dart';

/// In the standalone app we skip native Android TV detection (no custom channel).
/// The IPTV player treats this like a non-TV phone/tablet.
class DeviceProfile {
  DeviceProfile._();

  static bool _inited = false;
  static const bool isAndroidTv = false;

  static Future<void> initAndroidProfile() async {
    if (_inited) return;
    _inited = true;
  }
}
