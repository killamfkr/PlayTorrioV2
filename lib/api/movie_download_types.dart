class MovieDownloadProgress {
  final String id;
  final String title;
  final double progress;
  final int downloadedBytes;
  final int? totalBytes;
  final String status; // downloading | completed | error | cancelled
  final String? error;
  final String? filePath;

  const MovieDownloadProgress({
    required this.id,
    required this.title,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.totalBytes,
    required this.status,
    this.error,
    this.filePath,
  });
}

class DownloadedMovie {
  final String id;
  final String title;
  final String? posterPath;
  final String filePath;
  final int sizeBytes;
  final DateTime downloadedAt;
  final String mediaType;
  final int? season;
  final int? episode;
  final String? sourceLabel;

  const DownloadedMovie({
    required this.id,
    required this.title,
    this.posterPath,
    required this.filePath,
    required this.sizeBytes,
    required this.downloadedAt,
    required this.mediaType,
    this.season,
    this.episode,
    this.sourceLabel,
  });

  factory DownloadedMovie.fromJson(Map<String, dynamic> json) {
    return DownloadedMovie(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled',
      posterPath: json['posterPath']?.toString(),
      filePath: json['filePath']?.toString() ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      downloadedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['downloadedAt'] as num?)?.toInt() ?? 0,
      ),
      mediaType: json['mediaType']?.toString() ?? 'movie',
      season: (json['season'] as num?)?.toInt(),
      episode: (json['episode'] as num?)?.toInt(),
      sourceLabel: json['sourceLabel']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'posterPath': posterPath,
        'filePath': filePath,
        'sizeBytes': sizeBytes,
        'downloadedAt': downloadedAt.millisecondsSinceEpoch,
        'mediaType': mediaType,
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
        if (sourceLabel != null) 'sourceLabel': sourceLabel,
      };

  String get displayTitle {
    if (mediaType == 'tv' && season != null && episode != null) {
      return '$title · S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
    }
    return title;
  }
}
