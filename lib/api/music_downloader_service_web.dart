import 'package:flutter/foundation.dart';

import 'music_service.dart' show MusicTrack;

/// Web: saving tracks to device storage is not supported.
class MusicDownloaderService {
  static final MusicDownloaderService _instance = MusicDownloaderService._internal();
  factory MusicDownloaderService() => _instance;
  MusicDownloaderService._internal();

  Future<bool> downloadTrack(MusicTrack track) async {
    debugPrint('[Downloader] Web: downloads not supported');
    return false;
  }
}
