import 'package:flutter/foundation.dart';

import '../models/movie.dart';
import 'movie_download_types.dart';

/// Web stub — movie downloads need a filesystem.
class MovieDownloadService {
  static final MovieDownloadService _instance = MovieDownloadService._internal();
  factory MovieDownloadService() => _instance;
  MovieDownloadService._internal();

  final ValueNotifier<Map<String, MovieDownloadProgress>> activeDownloads =
      ValueNotifier({});

  Future<List<DownloadedMovie>> listDownloaded() async => const [];

  Future<String?> startStremioDownload({
    required Map<String, dynamic> stream,
    required Movie movie,
    int? season,
    int? episode,
  }) async {
    debugPrint('[MovieDownload] Not supported on web');
    return null;
  }

  void cancel(String id) {}

  Future<bool> deleteDownload(String id) async => false;

  Future<String?> downloadsDirectoryPath() async => null;

  bool canDownloadStream(Map<String, dynamic> stream) => false;
}
