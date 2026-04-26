class IptvMovie {
  final int num;
  final String name;
  final String streamType;
  final int streamId;
  final String? streamIcon;
  final String? added;
  final String categoryId;
  final String containerExtension;
  final String? customSid;
  final String? directSource;
  final double? rating;
  final String? rating5based;

  const IptvMovie({
    this.num = 0,
    required this.name,
    this.streamType = 'movie',
    this.streamId = 0,
    this.streamIcon,
    this.added,
    this.categoryId = '0',
    this.containerExtension = 'mp4',
    this.customSid,
    this.directSource,
    this.rating,
    this.rating5based,
  });

  factory IptvMovie.fromJson(Map<String, dynamic> json) {
    return IptvMovie(
      num: int.tryParse(json['num']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? 'Unknown Movie',
      streamType: json['stream_type']?.toString() ?? 'movie',
      streamId: int.tryParse(json['stream_id']?.toString() ?? '') ?? 0,
      streamIcon: json['stream_icon']?.toString(),
      added: json['added']?.toString(),
      categoryId: json['category_id']?.toString() ?? '0',
      containerExtension: json['container_extension']?.toString() ?? 'mp4',
      customSid: json['custom_sid']?.toString(),
      directSource: json['direct_source']?.toString(),
      rating: double.tryParse(json['rating']?.toString() ?? ''),
      rating5based: json['rating_5based']?.toString(),
    );
  }
}

class VodInfo {
  final VodInfoData info;
  final VodMovieData movieData;

  const VodInfo({required this.info, required this.movieData});

  factory VodInfo.fromJson(Map<String, dynamic> json) {
    return VodInfo(
      info: VodInfoData.fromJson(json['info'] ?? {}),
      movieData: VodMovieData.fromJson(json['movie_data'] ?? {}),
    );
  }
}

class VodInfoData {
  final String? movieImage;
  final String? genre;
  final String? plot;
  final String? cast;
  final String? director;
  final String? rating;
  final String? releaseDate;
  final String? duration;
  final int? durationSecs;
  final String? bitrate;
  final String? youtubeTrailer;
  final String? tmdbId;
  final List<String> backdropPath;
  final List<Map<String, dynamic>> subtitles;

  const VodInfoData({
    this.movieImage,
    this.genre,
    this.plot,
    this.cast,
    this.director,
    this.rating,
    this.releaseDate,
    this.duration,
    this.durationSecs,
    this.bitrate,
    this.youtubeTrailer,
    this.tmdbId,
    this.backdropPath = const [],
    this.subtitles = const [],
  });

  factory VodInfoData.fromJson(Map<String, dynamic> json) {
    List<String> backdrops = [];
    try {
      final bp = json['backdrop_path'];
      if (bp is List) {
        backdrops = bp.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}

    List<Map<String, dynamic>> subs = [];
    try {
      final s = json['subtitles'];
      if (s is List) {
        subs = s.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    return VodInfoData(
      movieImage: json['movie_image']?.toString(),
      genre: json['genre']?.toString(),
      plot: json['plot']?.toString(),
      cast: json['cast']?.toString(),
      director: json['director']?.toString(),
      rating: json['rating']?.toString(),
      releaseDate: json['releasedate']?.toString(),
      duration: json['duration']?.toString(),
      durationSecs: int.tryParse(json['duration_secs']?.toString() ?? ''),
      bitrate: json['bitrate']?.toString(),
      youtubeTrailer: json['youtube_trailer']?.toString(),
      tmdbId: json['tmdb_id']?.toString(),
      backdropPath: backdrops,
      subtitles: subs,
    );
  }
}

class VodMovieData {
  final int streamId;
  final String name;
  final String? added;
  final String categoryId;
  final String containerExtension;

  const VodMovieData({
    required this.streamId,
    required this.name,
    this.added,
    this.categoryId = '0',
    this.containerExtension = 'mp4',
  });

  factory VodMovieData.fromJson(Map<String, dynamic> json) {
    return VodMovieData(
      streamId: int.tryParse(json['stream_id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      added: json['added']?.toString(),
      categoryId: json['category_id']?.toString() ?? '0',
      containerExtension: json['container_extension']?.toString() ?? 'mp4',
    );
  }
}
