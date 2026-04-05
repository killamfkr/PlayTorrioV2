import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'music_service.dart';

class MusicPlaylist {
  final String name;
  final List<MusicTrack> tracks;

  MusicPlaylist({required this.name, required this.tracks});

  Map<String, dynamic> toJson() => {
    'name': name,
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    return MusicPlaylist(
      name: json['name'],
      tracks: (json['tracks'] as List).map((t) => MusicTrack(
        id: t['id'],
        title: t['title'],
        artist: t['artist'],
        album: t['album'],
        cover: t['cover'],
        duration: t['duration'],
        localPath: t['localPath'],
      )).toList(),
    );
  }
}

class MusicStorageService {
  static final MusicStorageService _instance = MusicStorageService._internal();
  factory MusicStorageService() => _instance;
  MusicStorageService._internal();

  static const String prefsLikedSongsKey = 'music_liked_songs';
  static const String prefsPlaylistsKey = 'music_playlists';

  final ValueNotifier<List<MusicTrack>> likedSongs = ValueNotifier<List<MusicTrack>>([]);
  final ValueNotifier<List<MusicTrack>> downloadedTracks = ValueNotifier<List<MusicTrack>>([]);
  
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    
    likedSongs.value = await getLikedSongs();
    downloadedTracks.value = await getDownloadedTracks();
  }

  // --- Downloaded Tracks ---

  Future<void> saveDownloadedTrack(MusicTrack track) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> downloaded = prefs.getStringList('music_downloaded_tracks') ?? [];
    
    final exists = downloaded.any((s) {
      try {
        return jsonDecode(s)['id'] == track.id;
      } catch (e) {
        return false;
      }
    });

    if (!exists) {
      downloaded.insert(0, jsonEncode(track.toJson()));
      await prefs.setStringList('music_downloaded_tracks', downloaded);
      downloadedTracks.value = await getDownloadedTracks(); // Update notifier
    }
  }

  Future<List<MusicTrack>> getDownloadedTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> downloaded = prefs.getStringList('music_downloaded_tracks') ?? [];
    return downloaded.map((s) => MusicTrack.fromJson(jsonDecode(s))).toList();
  }

  Future<void> removeDownloadedTrack(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> downloaded = prefs.getStringList('music_downloaded_tracks') ?? [];
    downloaded.removeWhere((s) {
      try {
        return jsonDecode(s)['id'] == id;
      } catch (e) {
        return false;
      }
    });
    await prefs.setStringList('music_downloaded_tracks', downloaded);
    downloadedTracks.value = await getDownloadedTracks(); // Update notifier
  }

  // --- Liked Songs ---

  Future<void> saveLikedSong(MusicTrack track) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> liked = prefs.getStringList('prefsLikedSongsKey') ?? [];
    
    final exists = liked.any((s) {
      try {
        return jsonDecode(s)['id'] == track.id;
      } catch (e) {
        return false;
      }
    });

    if (!exists) {
      liked.insert(0, jsonEncode(track.toJson()));
      await prefs.setStringList('prefsLikedSongsKey', liked);
      likedSongs.value = await getLikedSongs(); // Update notifier
    }
  }

  Future<void> removeLikedSong(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> liked = prefs.getStringList('prefsLikedSongsKey') ?? [];
    liked.removeWhere((s) {
      try {
        return jsonDecode(s)['id'] == id;
      } catch (e) {
        return false;
      }
    });
    await prefs.setStringList('prefsLikedSongsKey', liked);
    likedSongs.value = await getLikedSongs(); // Update notifier
  }

  Future<bool> isLiked(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> liked = prefs.getStringList('prefsLikedSongsKey') ?? [];
    return liked.any((s) {
      try {
        return jsonDecode(s)['id'] == id;
      } catch (e) {
        return false;
      }
    });
  }

  Future<List<MusicTrack>> getLikedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> liked = prefs.getStringList('prefsLikedSongsKey') ?? [];
    return liked.map((s) => MusicTrack.fromJson(jsonDecode(s))).toList();
  }

  // --- Playlists ---

  Future<void> savePlaylist(MusicPlaylist playlist) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> playlists = prefs.getStringList('prefsPlaylistsKey') ?? [];
    
    final index = playlists.indexWhere((p) {
      try {
        return MusicPlaylist.fromJson(jsonDecode(p)).name == playlist.name;
      } catch (e) {
        return false;
      }
    });

    if (index != -1) {
      playlists[index] = jsonEncode(playlist.toJson());
    } else {
      playlists.add(jsonEncode(playlist.toJson()));
    }
    
    await prefs.setStringList('prefsPlaylistsKey', playlists);
  }

  Future<List<MusicPlaylist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> playlists = prefs.getStringList('prefsPlaylistsKey') ?? [];
    return playlists.map((p) => MusicPlaylist.fromJson(jsonDecode(p))).toList();
  }

  Future<void> saveAlbum(MusicAlbum album) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> albums = prefs.getStringList('music_albums') ?? [];
    
    final albumJson = jsonEncode(album.toJson());

    // Check if album is already saved (by ID)
    final exists = albums.any((a) {
      try {
        return jsonDecode(a)['id'] == album.id;
      } catch (e) {
        return false;
      }
    });

    if (!exists) {
      albums.add(albumJson);
      await prefs.setStringList('music_albums', albums);
    }
  }

  Future<List<MusicAlbum>> getSavedAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> albums = prefs.getStringList('music_albums') ?? [];
    return albums.map((a) {
      final data = jsonDecode(a);
      return MusicAlbum(
        id: data['id'],
        title: data['title'],
        artist: data['artist'],
        cover: data['cover'],
        nbTracks: data['nbTracks'],
      );
    }).toList();
  }

  Future<void> deletePlaylist(String name) async {
     final prefs = await SharedPreferences.getInstance();
     final List<String> playlists = prefs.getStringList('prefsPlaylistsKey') ?? [];
     playlists.removeWhere((p) => MusicPlaylist.fromJson(jsonDecode(p)).name == name);
     await prefs.setStringList('prefsPlaylistsKey', playlists);
  }

  Future<void> unsaveAlbum(String id) async {
     final prefs = await SharedPreferences.getInstance();
     final List<String> albums = prefs.getStringList('music_albums') ?? [];
     albums.removeWhere((a) => jsonDecode(a)['id'] == id);
     await prefs.setStringList('music_albums', albums);
  }
}
