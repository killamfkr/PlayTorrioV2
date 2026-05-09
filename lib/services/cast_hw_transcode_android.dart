import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/local_server_service.dart';

/// Tracks an active phone-side transcode session so we can tear down FFmpeg + routes when Cast stops.
class CastHwTranscodeCoordinator {
  CastHwTranscodeCoordinator._();
  static final CastHwTranscodeCoordinator instance = CastHwTranscodeCoordinator._();

  String? _sessionId;

  void bind(String sessionId) {
    _sessionId = sessionId;
  }

  Future<void> disposeActive() async {
    final id = _sessionId;
    _sessionId = null;
    if (id == null) return;
    try {
      LocalServerService().unregisterCastHwSession(id);
    } catch (_) {}
    if (!kIsWeb && Platform.isAndroid) {
      await CastHwTranscodeAndroid.stop(id);
    }
  }
}

/// Android-only FFmpeg Kit bridge (hardware **Encoder**: `h264_mediacodec`).
class CastHwTranscodeAndroid {
  CastHwTranscodeAndroid._();

  static const MethodChannel _ch = MethodChannel('playtorrio/cast_hw_transcode');

  static Future<CastHwStartResult?> start({
    required String inputUrl,
    Map<String, String>? headers,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final raw = await _ch.invokeMethod<Map<Object?, Object?>>('start', {
        'inputUrl': inputUrl,
        if (headers != null && headers.isNotEmpty) 'headers': headers,
      });
      if (raw == null) return null;
      final sid = raw['sessionId']?.toString();
      final playlist = raw['playlistPath']?.toString();
      final dir = raw['outputDir']?.toString();
      if (sid == null || playlist == null || dir == null) return null;
      return CastHwStartResult(sessionId: sid, playlistPath: playlist, outputDir: dir);
    } catch (e, st) {
      debugPrint('[CastHw] start failed: $e\n$st');
      return null;
    }
  }

  static Future<void> stop(String sessionId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<void>('stop', {'sessionId': sessionId});
    } catch (_) {}
  }

  static Future<String?> failureReason(String sessionId) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>('failureReason', {'sessionId': sessionId});
    } catch (_) {
      return null;
    }
  }
}

class CastHwStartResult {
  final String sessionId;
  final String playlistPath;
  final String outputDir;

  CastHwStartResult({
    required this.sessionId,
    required this.playlistPath,
    required this.outputDir,
  });

  Future<bool> waitUntilReady({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final playlistFile = File(playlistPath);
    while (DateTime.now().isBefore(deadline)) {
      final fail = await CastHwTranscodeAndroid.failureReason(sessionId);
      if (fail != null && fail.isNotEmpty && fail != 'cancelled') {
        debugPrint('[CastHw] encoder failed early: $fail');
        return false;
      }
      try {
        if (playlistFile.existsSync()) {
          final txt = playlistFile.readAsStringSync();
          if (txt.contains('#EXTINF')) {
            return true;
          }
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
    return false;
  }
}

/// Returns an LAN `http://…/cast-hw/…/index.m3u8` URL, or `null` if HW transcode is unavailable.
Future<String?> androidHwTranscodeCastUrlIfEnabled({
  required String inputUrl,
  Map<String, String>? headers,
  required bool enabled,
}) async {
  if (!enabled || kIsWeb || !Platform.isAndroid) return null;
  final trimmed = inputUrl.trim();
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    return null;
  }
  await LocalServerService().start();
  final ls = LocalServerService();
  if (ls.port <= 0) return null;

  final started = await CastHwTranscodeAndroid.start(
    inputUrl: trimmed,
    headers: headers,
  );
  if (started == null) return null;

  final ok = await started.waitUntilReady();
  if (!ok) {
    await CastHwTranscodeAndroid.stop(started.sessionId);
    return null;
  }

  final lan = await ls.preferredLanIpv4();
  if (lan == null) {
    await CastHwTranscodeAndroid.stop(started.sessionId);
    return null;
  }

  ls.registerCastHwSession(started.sessionId, started.outputDir);
  CastHwTranscodeCoordinator.instance.bind(started.sessionId);
  return 'http://$lan:${ls.port}/cast-hw/${started.sessionId}/index.m3u8';
}
