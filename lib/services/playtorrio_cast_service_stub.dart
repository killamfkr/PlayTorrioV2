import 'package:flutter/material.dart';

/// Web stub — Chromecast sender is not available in the browser build.
class PlaytorrioCastService {
  PlaytorrioCastService._();
  static final PlaytorrioCastService instance = PlaytorrioCastService._();

  Future<void> initialize() async {}

  bool get isInitialized => false;

  Stream<bool> get isCastingActiveStream => Stream<bool>.value(false);

  bool get isCastingActiveNow => false;

  String? get connectedCastDeviceName => null;

  Future<void> stopCasting() async {}

  Future<void> retryInitialize() async {}

  bool eligibleForCastUi({
    required String mediaPath,
    String? magnetLink,
  }) =>
      false;

  Future<void> openCastSheet({
    required BuildContext context,
    required String streamUrl,
    required String title,
    String? subtitle,
    String? posterUrl,
    required bool liveStream,
    Duration startPosition = Duration.zero,
    Map<String, String>? headers,
    VoidCallback? onCastStarted,
  }) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chromecast is not available in this build.')),
    );
  }
}
