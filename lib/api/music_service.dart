import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../services/youtube_audio_extractor.dart';

class _CachedUrl {
  final String url;
  final DateTime cachedAt;
  _CachedUrl(this.url) : cachedAt = DateTime.now();
  bool get isExpired => DateTime.now().difference(cachedAt).inHours >= 5;
}

class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String cover;
  final int duration;
  final String? localPath;

  MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.cover,
    required this.duration,
    this.localPath,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    final artistObj = json['artist'];
    final albumObj = json['album'];
    
    // Check if this is a raw API response or our saved JSON
    String artistName = 'Unknown Artist';
    if (artistObj is Map) {
      artistName = artistObj['name'] ?? 'Unknown Artist';
    } else if (artistObj is String) {
      artistName = artistObj;
    }

    String albumTitle = '';
    String coverUrl = '';
    if (albumObj is Map) {
      albumTitle = albumObj['title'] ?? '';
      coverUrl = albumObj['cover_xl'] ?? albumObj['cover_big'] ?? albumObj['cover_medium'] ?? albumObj['cover_small'] ?? '';
    } else if (albumObj is String) {
      albumTitle = albumObj;
      coverUrl = json['cover'] ?? '';
    }

    return MusicTrack(
      id: json['id'].toString(),
      title: json['title'] ?? 'Unknown Title',
      artist: artistName,
      album: albumTitle,
      cover: coverUrl.isNotEmpty ? coverUrl : (json['cover'] ?? ''),
      duration: json['duration'] ?? 0,
      localPath: json['localPath'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'cover': cover,
    'duration': duration,
    'localPath': localPath,
  };
}

class MusicAlbum {
  final String id;
  final String title;
  final String artist;
  final String cover;
  final int? nbTracks;

  MusicAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.cover,
    this.nbTracks,
  });

  factory MusicAlbum.fromJson(Map<String, dynamic> json) {
    final artistObj = json['artist'] ?? {};

    return MusicAlbum(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      artist: artistObj['name'] ?? 'Unknown Artist',
      cover: json['cover_xl'] ?? json['cover_big'] ?? json['cover_medium'] ?? json['cover_small'] ?? '',
      nbTracks: json['nb_tracks'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'cover': cover,
    'nbTracks': nbTracks,
  };
}

class MusicService {
  final _yt = YoutubeExplode();
  static const String _proxyUrl = 'https://deezer-proxy.aymanisthedude1.workers.dev/?url=';

  // Caches for fast playback
  final Map<String, String> _videoIdCache = {};
  final Map<String, _CachedUrl> _streamUrlCache = {};

  /// Generic retry wrapper — retries up to [maxRetries] times with exponential backoff
  Future<T> _withRetry<T>(Future<T> Function() fn, T fallback, {int maxRetries = 5}) async {
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await fn();
        // For lists, treat empty as "no data" and retry
        if (result is List && result.isEmpty && attempt < maxRetries) {
          debugPrint('MusicService: Attempt $attempt returned empty, retrying...');
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }
        return result;
      } catch (e) {
        debugPrint('MusicService: Attempt $attempt failed: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
    return fallback;
  }

  Future<List<MusicTrack>> searchTracks(String query) => _withRetry(() async {
    final targetUri = Uri.https('api.deezer.com', '/search', {'q': query});
    final proxiedUrl = '$_proxyUrl${Uri.encodeComponent(targetUri.toString())}';
    
    final response = await http.get(Uri.parse(proxiedUrl));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final items = data['data'] as List;
      return items.map((item) => MusicTrack.fromJson(item)).toList();
    }
    return <MusicTrack>[];
  }, <MusicTrack>[]);

  Future<List<MusicTrack>> getTrendingTracks({int index = 0, int limit = 20}) => _withRetry(() async {
    final targetUri = Uri.https('api.deezer.com', '/chart/0/tracks', {
      'index': index.toString(),
      'limit': limit.toString(),
    });
    final proxiedUrl = '$_proxyUrl${Uri.encodeComponent(targetUri.toString())}';
    
    final response = await http.get(Uri.parse(proxiedUrl));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final items = data['data'] as List;
      return items.map((item) => MusicTrack.fromJson(item)).toList();
    }
    return <MusicTrack>[];
  }, <MusicTrack>[]);

  Future<List<MusicAlbum>> searchAlbums(String query) => _withRetry(() async {
    final targetUri = Uri.https('api.deezer.com', '/search/album', {'q': query});
    final proxiedUrl = '$_proxyUrl${Uri.encodeComponent(targetUri.toString())}';
    
    final response = await http.get(Uri.parse(proxiedUrl));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final albums = data['data'] as List;
      return albums.map((item) => MusicAlbum.fromJson(item)).toList();
    }
    return <MusicAlbum>[];
  }, <MusicAlbum>[]);

  Future<List<MusicTrack>> getAlbumTracks(String albumId) => _withRetry(() async {
    final targetUrl = 'https://api.deezer.com/album/$albumId';
    final proxiedUrl = '$_proxyUrl${Uri.encodeComponent(targetUrl)}';
    
    final albumResponse = await http.get(Uri.parse(proxiedUrl));
    if (albumResponse.statusCode == 200) {
      final albumData = json.decode(albumResponse.body);
      final items = albumData['tracks']['data'] as List;
      
      return items.map((trackJson) {
         trackJson['album'] = {
           'title': albumData['title'],
           'cover_xl': albumData['cover_xl'],
           'cover_big': albumData['cover_big'],
           'cover_medium': albumData['cover_medium'],
           'cover_small': albumData['cover_small'],
         };
         return MusicTrack.fromJson(trackJson);
      }).toList();
    }
    return <MusicTrack>[];
  }, <MusicTrack>[]);

  Future<List<MusicTrack>> getRelatedTracks(String trackId) => _withRetry(() async {
    final targetUrl = 'https://api.deezer.com/track/$trackId/related';
    final proxiedUrl = '$_proxyUrl${Uri.encodeComponent(targetUrl)}';
    
    final response = await http.get(Uri.parse(proxiedUrl));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final items = data['data'];
      if (items is List) {
        return items.map((item) => MusicTrack.fromJson(item)).toList();
      }
    }
    return <MusicTrack>[];
  }, <MusicTrack>[]);

  Future<String?> getYoutubeVideoId(String title, String artist) async {
    final cacheKey = '$title|$artist';
    if (_videoIdCache.containsKey(cacheKey)) {
      debugPrint('MusicService: Video ID cache hit for "$title"');
      return _videoIdCache[cacheKey];
    }

    // Fast path: YouTube results-page HTML + regex (ported from PlayTorrio TV).
    try {
      final fastId = await YoutubeAudioExtractor.instance
          .searchVideoId(title, artist);
      if (fastId != null) {
        _videoIdCache[cacheKey] = fastId;
        debugPrint('MusicService: Fast videoId match for "$title"');
        return fastId;
      }
    } catch (e) {
      debugPrint('MusicService: Fast search failed: $e');
    }

    // Fallback: youtube_explode_dart full search.
    try {
      final searchQuery = '$title - $artist lyrics';
      final searchList = await _yt.search.search(searchQuery);
      if (searchList.isNotEmpty) {
        for (final video in searchList) {
          if (video.duration != null && video.duration!.inSeconds > 60) {
            _videoIdCache[cacheKey] = video.id.value;
            return video.id.value;
          }
        }
        _videoIdCache[cacheKey] = searchList.first.id.value;
        return searchList.first.id.value;
      }
    } catch (e) {
      debugPrint('MusicService: YouTube matching error: $e');
    }
    return null;
  }

  /// Fast stream URL fetching for playback — uses shared instance for cookie persistence
  Future<String?> getYoutubeStreamUrl(String videoId) async {
    final cached = _streamUrlCache[videoId];
    if (cached != null && !cached.isExpired) {
      debugPrint('MusicService: Stream URL cache hit');
      return cached.url;
    }

    // Fast path: direct InnerTube call (ported from PlayTorrio TV).
    try {
      final fastUrl =
          await YoutubeAudioExtractor.instance.getAudioUrl(videoId);
      if (fastUrl != null) {
        _streamUrlCache[videoId] = _CachedUrl(fastUrl);
        debugPrint('MusicService: Got stream URL via fast extractor');
        return fastUrl;
      }
    } catch (e) {
      debugPrint('MusicService: Fast extractor failed: $e');
    }

    // Fallback: youtube_explode_dart.
    final clientSets = [
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.tv],
    ];

    for (final clients in clientSets) {
      try {
        final manifest = await _yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: clients,
        );
        final audioStreams = manifest.audioOnly.toList();
        if (audioStreams.isEmpty) continue;
        audioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        final url = audioStreams.first.url.toString();
        _streamUrlCache[videoId] = _CachedUrl(url);
        debugPrint('MusicService: Got stream URL via ${clients.first}');
        return url;
      } catch (e) {
        debugPrint('MusicService: ${clients.first} failed: $e');
      }
    }

    debugPrint('MusicService: All clients failed for $videoId');
    return null;
  }

  Future<StreamManifest?> getYoutubeManifest(String videoId) async {
    final clientSets = [
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.tv],
    ];

    for (final clients in clientSets) {
      try {
        return await _yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: clients,
        );
      } catch (e) {
        debugPrint('MusicService: ${clients.first} manifest failed: $e');
      }
    }
    return null;
  }

  YoutubeExplode get yt => _yt;

  void dispose() {
    _yt.close();
  }
}
