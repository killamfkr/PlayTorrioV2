import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/trakt_service.dart';

/// Persisted "My List" service — stores movies & shows the user bookmarks.
/// Works with both TMDB [Movie] objects and Stremio catalog Map items.
///
/// Each entry is a JSON map with a unified shape:
///   {
///     "uniqueId":    "tmdb_12345"  |  "stremio_tt12345"  |  "custom_...",
///     "tmdbId":      12345         |  null,
///     "imdbId":      "tt12345"     |  null,
///     "title":       "...",
///     "posterPath":  "...",        // relative TMDB path or full URL
///     "mediaType":   "movie" | "tv" | "series",
///     "voteAverage": 7.5,
///     "releaseDate": "2025-01-01",
///     "source":      "tmdb" | "stremio",
///     "stremioType": "movie" | "series" | null,
///     "addedAt":     1700000000000 (epoch ms),
///   }
class MyListService {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final MyListService _instance = MyListService._internal();
  factory MyListService() => _instance;
  MyListService._internal() { _init(); }

  static const String _key = 'my_list_items';

  final _controller = StreamController<List<Map<String, dynamic>>>.broadcast();
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  /// Reactive stream of the current list.
  Stream<List<Map<String, dynamic>>> get stream => _controller.stream;

  /// Synchronous snapshot (empty until first load finishes).
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  /// Change notifier that widgets can listen to for rebuilds.
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  // ── Init ───────────────────────────────────────────────────────────────
  Future<void> _init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        _items = List<Map<String, dynamic>>.from(
          (json.decode(raw) as List).map((e) => Map<String, dynamic>.from(e)),
        );
      } catch (e) {
        debugPrint('[MyList] Failed to decode: $e');
        _items = [];
      }
    }
    _loaded = true;
    _notify();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(_items));
    _notify();
  }

  void _notify() {
    _controller.add(List.unmodifiable(_items));
    changeNotifier.value++;
  }

  // ── Unique ID helpers ──────────────────────────────────────────────────
  /// Build a unique ID from a TMDB Movie.
  static String movieId(int tmdbId, String mediaType) => 'tmdb_${mediaType}_$tmdbId';

  /// Build a unique ID from a Stremio catalog item Map.
  static String stremioItemId(Map<String, dynamic> item) {
    final id = item['imdb_id']?.toString() ??
        item['imdbId']?.toString() ??
        item['id']?.toString() ??
        item['name']?.toString() ??
        '';
    final type = item['type']?.toString() ?? 'unknown';
    return 'stremio_${type}_$id';
  }

  // ── Public API ─────────────────────────────────────────────────────────

  /// Whether the given unique ID is already in the list.
  bool contains(String uniqueId) {
    return _items.any((e) => e['uniqueId'] == uniqueId);
  }

  /// Add a TMDB Movie to the list. No-op if already present.
  Future<void> addMovie({
    required int tmdbId,
    String? imdbId,
    required String title,
    required String posterPath,
    required String mediaType,
    double voteAverage = 0,
    String releaseDate = '',
  }) async {
    await _ensureLoaded();
    final uid = movieId(tmdbId, mediaType);
    if (contains(uid)) return;
    _items.insert(0, {
      'uniqueId': uid,
      'tmdbId': tmdbId,
      'imdbId': imdbId,
      'title': title,
      'posterPath': posterPath,
      'mediaType': mediaType,
      'voteAverage': voteAverage,
      'releaseDate': releaseDate,
      'source': 'tmdb',
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _save();
    // Sync to Trakt in background
    _traktAdd(tmdbId, imdbId, mediaType);
  }

  /// Add a Stremio catalog item (Map) to the list.
  Future<void> addStremioItem(Map<String, dynamic> item) async {
    await _ensureLoaded();
    final uid = stremioItemId(item);
    if (contains(uid)) return;
    _items.insert(0, {
      'uniqueId': uid,
      'tmdbId': null,
      'imdbId': item['imdb_id'] ?? item['imdbId'] ?? item['id'],
      'title': item['name']?.toString() ?? 'Unknown',
      'posterPath': item['poster']?.toString() ?? '',
      'mediaType': item['type']?.toString() ?? 'movie',
      'voteAverage': double.tryParse(item['imdbRating']?.toString() ?? '') ?? 0,
      'releaseDate': item['releaseInfo']?.toString() ?? '',
      'source': 'stremio',
      'stremioType': item['type']?.toString(),
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _save();
    // Sync to Trakt in background
    final imdb = item['imdb_id']?.toString() ?? item['imdbId']?.toString();
    _traktAdd(null, imdb, item['type']?.toString() ?? 'movie');
  }

  /// Remove by unique ID.
  Future<void> remove(String uniqueId) async {
    await _ensureLoaded();
    // Capture ids before removing for Trakt sync
    final item = _items.cast<Map<String, dynamic>?>().firstWhere(
      (e) => e?['uniqueId'] == uniqueId,
      orElse: () => null,
    );
    final tmdbId = item?['tmdbId'] as int?;
    final imdbId = item?['imdbId']?.toString();
    final mediaType = item?['mediaType']?.toString() ?? 'movie';
    _items.removeWhere((e) => e['uniqueId'] == uniqueId);
    await _save();
    // Sync removal to Trakt in background
    _traktRemove(tmdbId, imdbId, mediaType);
  }

  /// Toggle: add if missing, remove if present. Returns true if now in list.
  Future<bool> toggleMovie({
    required int tmdbId,
    String? imdbId,
    required String title,
    required String posterPath,
    required String mediaType,
    double voteAverage = 0,
    String releaseDate = '',
  }) async {
    final uid = movieId(tmdbId, mediaType);
    if (contains(uid)) {
      await remove(uid);
      return false;
    } else {
      await addMovie(
        tmdbId: tmdbId,
        imdbId: imdbId,
        title: title,
        posterPath: posterPath,
        mediaType: mediaType,
        voteAverage: voteAverage,
        releaseDate: releaseDate,
      );
      return true;
    }
  }

  /// Toggle a Stremio item. Returns true if now in list.
  Future<bool> toggleStremioItem(Map<String, dynamic> item) async {
    final uid = stremioItemId(item);
    if (contains(uid)) {
      await remove(uid);
      return false;
    } else {
      await addStremioItem(item);
      return true;
    }
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await _init();
  }

  // ── Trakt background sync ─────────────────────────────────────────────
  void _traktAdd(int? tmdbId, String? imdbId, String mediaType) {
    if (tmdbId == null && imdbId == null) return;
    TraktService().isLoggedIn().then((loggedIn) {
      if (loggedIn) {
        TraktService().addToWatchlist(
          tmdbId: tmdbId,
          imdbId: imdbId,
          mediaType: mediaType,
        );
      }
    });
  }

  void _traktRemove(int? tmdbId, String? imdbId, String mediaType) {
    if (tmdbId == null && imdbId == null) return;
    TraktService().isLoggedIn().then((loggedIn) {
      if (loggedIn) {
        TraktService().removeFromWatchlist(
          tmdbId: tmdbId,
          imdbId: imdbId,
          mediaType: mediaType,
        );
      }
    });
  }
}
