import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// No-op: main app hooks into AudioService. Standalone build skips media session.
void attachBuiltInVideoMediaSession(
  Player player, {
  required String title,
  String? posterPath,
  String? displaySubtitle,
  String? album,
  bool? isLive,
  Map<String, dynamic>? extras,
}) {}

void detachBuiltInVideoMediaSession(Player player) {}
