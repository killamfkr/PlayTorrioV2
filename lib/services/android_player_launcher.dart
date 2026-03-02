import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

/// Android-specific intent launcher using android_intent_plus.
class AndroidPlayerLauncher {
  /// Launch a video URL in an external Android player via ACTION_VIEW.
  /// [packageName] null = system chooser dialog.
  static Future<bool> launch({
    required String url,
    String? packageName,
    String? title,
    Map<String, dynamic>? extras,
  }) async {
    if (!Platform.isAndroid) return false;

    try {
      final arguments = <String, dynamic>{};
      if (title != null) arguments['title'] = title;
      if (extras != null) arguments.addAll(extras);

      final intent = AndroidIntent(
        action: 'action_view',
        data: url,
        type: 'video/*',
        package: packageName,
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        arguments: arguments.isNotEmpty ? arguments : null,
      );

      await intent.launch();
      debugPrint('[AndroidPlayerLauncher] Launched ${packageName ?? "system chooser"} with $url');
      return true;
    } catch (e) {
      debugPrint('[AndroidPlayerLauncher] Error: $e');
      return false;
    }
  }
}
