class IptvSeries {
  final int seriesId;
  final String name;
  final String? cover;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? lastModified;
  final String? rating;
  final String? rating5based;
  final List<String> backdropPath;
  final String? youtubeTrailer;
  final String? episodeRunTime;
  final String categoryId;

  const IptvSeries({
    required this.seriesId,
    required this.name,
    this.cover,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.lastModified,
    this.rating,
    this.rating5based,
    this.backdropPath = const [],
    this.youtubeTrailer,
    this.episodeRunTime,
    this.categoryId = '0',
  });

  factory IptvSeries.fromJson(Map<String, dynamic> json) {
    List<String> backdrops = [];
    try {
      final bp = json['backdrop_path'];
      if (bp is List) {
        backdrops = bp.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}

    return IptvSeries(
      seriesId: int.tryParse(json['series_id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? 'Unknown Series',
      cover: json['cover']?.toString(),
      plot: json['plot']?.toString(),
      cast: json['cast']?.toString(),
      director: json['director']?.toString(),
      genre: json['genre']?.toString(),
      releaseDate: json['releaseDate']?.toString(),
      lastModified: json['last_modified']?.toString(),
      rating: json['rating']?.toString(),
      rating5based: json['rating_5based']?.toString(),
      backdropPath: backdrops,
      youtubeTrailer: json['youtube_trailer']?.toString(),
      episodeRunTime: json['episode_run_time']?.toString(),
      categoryId: json['category_id']?.toString() ?? '0',
    );
  }
}

class SeriesInfo {
  final SeriesInfoData info;
  final Map<String, SeasonInfo> seasons;
  final Map<String, List<IptvEpisode>> episodes;

  const SeriesInfo({
    required this.info,
    this.seasons = const {},
    this.episodes = const {},
  });

  List<String> get seasonNumbers {
    final keys = episodes.keys.toList();
    keys.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return keys;
  }

  factory SeriesInfo.fromJson(Map<String, dynamic> json) {
    final infoData = SeriesInfoData.fromJson(json['info'] ?? {});

    // Parse seasons
    final Map<String, SeasonInfo> seasonsMap = {};
    try {
      final seasonsRaw = json['seasons'];
      if (seasonsRaw is List) {
        for (final s in seasonsRaw) {
          if (s is Map<String, dynamic>) {
            final season = SeasonInfo.fromJson(s);
            seasonsMap[season.seasonNumber.toString()] = season;
          }
        }
      } else if (seasonsRaw is Map) {
        for (final entry in seasonsRaw.entries) {
          if (entry.value is Map) {
            final season = SeasonInfo.fromJson(Map<String, dynamic>.from(entry.value));
            seasonsMap[entry.key.toString()] = season;
          }
        }
      }
    } catch (_) {}

    // Parse episodes (Map<String, List<dynamic>>)
    final Map<String, List<IptvEpisode>> episodesMap = {};
    try {
      final episodesRaw = json['episodes'];
      if (episodesRaw is Map) {
        for (final entry in episodesRaw.entries) {
          final seasonNum = entry.key.toString();
          if (entry.value is List) {
            episodesMap[seasonNum] = (entry.value as List)
                .map((e) => IptvEpisode.fromJson(Map<String, dynamic>.from(e)))
                .toList();
          }
        }
      }
    } catch (_) {}

    return SeriesInfo(
      info: infoData,
      seasons: seasonsMap,
      episodes: episodesMap,
    );
  }
}

class SeriesInfoData {
  final String? name;
  final String? cover;
  final String? plot;
  final String? cast;
  final String? director;
  final String? genre;
  final String? releaseDate;
  final String? rating;
  final List<String> backdropPath;
  final String? youtubeTrailer;

  const SeriesInfoData({
    this.name,
    this.cover,
    this.plot,
    this.cast,
    this.director,
    this.genre,
    this.releaseDate,
    this.rating,
    this.backdropPath = const [],
    this.youtubeTrailer,
  });

  factory SeriesInfoData.fromJson(Map<String, dynamic> json) {
    List<String> backdrops = [];
    try {
      final bp = json['backdrop_path'];
      if (bp is List) {
        backdrops = bp.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}

    return SeriesInfoData(
      name: json['name']?.toString(),
      cover: json['cover']?.toString(),
      plot: json['plot']?.toString(),
      cast: json['cast']?.toString(),
      director: json['director']?.toString(),
      genre: json['genre']?.toString(),
      releaseDate: json['releaseDate']?.toString(),
      rating: json['rating']?.toString(),
      backdropPath: backdrops,
      youtubeTrailer: json['youtube_trailer']?.toString(),
    );
  }
}

class SeasonInfo {
  final int? id;
  final String? airDate;
  final int? episodeCount;
  final String? name;
  final String? overview;
  final int seasonNumber;
  final String? cover;
  final String? coverBig;

  const SeasonInfo({
    this.id,
    this.airDate,
    this.episodeCount,
    this.name,
    this.overview,
    this.seasonNumber = 1,
    this.cover,
    this.coverBig,
  });

  factory SeasonInfo.fromJson(Map<String, dynamic> json) {
    return SeasonInfo(
      id: int.tryParse(json['id']?.toString() ?? ''),
      airDate: json['air_date']?.toString(),
      episodeCount: int.tryParse(json['episode_count']?.toString() ?? ''),
      name: json['name']?.toString(),
      overview: json['overview']?.toString(),
      seasonNumber: int.tryParse(json['season_number']?.toString() ?? '') ?? 1,
      cover: json['cover']?.toString(),
      coverBig: json['cover_big']?.toString(),
    );
  }
}

class IptvEpisode {
  final int id;
  final int episodeNum;
  final String title;
  final String containerExtension;
  final EpisodeInfo? info;
  final String? added;
  final int season;
  final String? directSource;

  const IptvEpisode({
    required this.id,
    this.episodeNum = 0,
    required this.title,
    this.containerExtension = 'mp4',
    this.info,
    this.added,
    this.season = 1,
    this.directSource,
  });

  factory IptvEpisode.fromJson(Map<String, dynamic> json) {
    return IptvEpisode(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      episodeNum: int.tryParse(json['episode_num']?.toString() ?? '') ?? 0,
      title: json['title']?.toString() ?? 'Episode',
      containerExtension: json['container_extension']?.toString() ?? 'mp4',
      info: json['info'] != null ? EpisodeInfo.fromJson(Map<String, dynamic>.from(json['info'])) : null,
      added: json['added']?.toString(),
      season: int.tryParse(json['season']?.toString() ?? '') ?? 1,
      directSource: json['direct_source']?.toString(),
    );
  }
}

class EpisodeInfo {
  final String? movieImage;
  final String? plot;
  final String? releaseDate;
  final String? rating;
  final String? duration;
  final int? durationSecs;
  final List<Map<String, dynamic>> subtitles;

  const EpisodeInfo({
    this.movieImage,
    this.plot,
    this.releaseDate,
    this.rating,
    this.duration,
    this.durationSecs,
    this.subtitles = const [],
  });

  factory EpisodeInfo.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> subs = [];
    try {
      final s = json['subtitles'];
      if (s is List) {
        subs = s.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    return EpisodeInfo(
      movieImage: json['movie_image']?.toString(),
      plot: json['plot']?.toString(),
      releaseDate: json['releasedate']?.toString(),
      rating: json['rating']?.toString(),
      duration: json['duration']?.toString(),
      durationSecs: int.tryParse(json['duration_secs']?.toString() ?? ''),
      subtitles: subs,
    );
  }
}
