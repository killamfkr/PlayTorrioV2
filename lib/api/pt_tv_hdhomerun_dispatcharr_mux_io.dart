import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

/// Plex HDHomeRun DVR expects **MPEG-TS** on the tune URL (see Dispatcharr,
/// plex-dvr-hls, etc.). Plain HLS/proxy playlists often fail to tune/play.
///
/// When this is `true`, [tryPtTvDispatcharrMpegTsRemux] remuxes the IPTV URL
/// through bundled FFmpeg (`-c copy -f mpegts`) to match that model.
bool get ptTvDispatcharrMpegTsRemuxSupported =>
    !kIsWeb &&
    (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// Dispatcharr-style MPEG-TS byte stream for a single HTTP GET, or `null` to
/// fall back to the legacy HTTP proxy path.
Future<Response?> tryPtTvDispatcharrMpegTsRemux({
  required Request request,
  required String inputUrl,
}) async {
  if (request.method != 'GET') return null;
  if (!ptTvDispatcharrMpegTsRemuxSupported) return null;

  String? pipeNullable;
  FFmpegSession? session;
  try {
    await FFmpegKitConfig.init();
    final pipeObj = await FFmpegKitConfig.registerNewFFmpegPipe();
    if (pipeObj == null || pipeObj.isEmpty) return null;
    final pipe = pipeObj;
    pipeNullable = pipe;

    final u = Uri.parse(inputUrl);
    final o = '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
    const ua =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    final hdr = 'User-Agent: $ua\r\nReferer: $o/\r\nOrigin: $o\r\n';

    final args = <String>[
      '-hide_banner',
      '-loglevel', 'error',
      '-nostdin',
      '-rw_timeout', '20000000',
      '-reconnect', '1',
      '-reconnect_streamed', '1',
      '-reconnect_delay_max', '5',
      '-headers',
      hdr,
      '-i',
      inputUrl,
      '-map',
      '0',
      '-c',
      'copy',
      '-f',
      'mpegts',
      '-muxdelay',
      '0',
      '-flush_packets',
      '1',
      pipe,
    ];

    session = await FFmpegKit.executeWithArgumentsAsync(args);
    final sid = session!.getSessionId();

    Stream<List<int>> mpegTsBytes() async* {
      try {
        await for (final chunk in File(pipe).openRead()) {
          yield chunk;
        }
      } finally {
        try {
          await FFmpegKit.cancel(sid);
        } catch (_) {}
        try {
          await FFmpegKitConfig.closeFFmpegPipe(pipe);
        } catch (_) {}
      }
    }

    return Response(
      200,
      body: mpegTsBytes(),
      headers: {
        'Content-Type': 'video/mp2t',
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'no-store',
        'Connection': 'close',
      },
    );
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[PtTvHdhr] Dispatcharr-style remux init failed: $e\n$st');
    }
    try {
      if (session != null) {
        await FFmpegKit.cancel(session.getSessionId());
      }
    } catch (_) {}
    try {
      if (pipeNullable != null) {
        await FFmpegKitConfig.closeFFmpegPipe(pipeNullable!);
      }
    } catch (_) {}
    return null;
  }
}
