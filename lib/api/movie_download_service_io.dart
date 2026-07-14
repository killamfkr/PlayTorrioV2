import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie.dart';
import '../utils/stremio_stream_headers.dart';
import 'debrid_api.dart';
import 'movie_download_types.dart';
import 'settings_service.dart';
import 'torrent_stream_service.dart';

class MovieDownloadService {
  static final MovieDownloadService _instance = MovieDownloadService._internal();
  factory MovieDownloadService() => _instance;
  MovieDownloadService._internal();

  static const _prefsIndexKey = 'movie_downloads_index_v1';

  final ValueNotifier<Map<String, MovieDownloadProgress>> activeDownloads =
      ValueNotifier({});
  final Set<String> _cancelledIds = {};
  final SettingsService _settings = SettingsService();

  bool canDownloadStream(Map<String, dynamic> stream) {
    final external = stream['externalUrl']?.toString();
    if (external != null && external.isNotEmpty) return false;
    final url = stream['url']?.toString();
    if (url != null && url.isNotEmpty) {
      return !_looksLikeHls(url);
    }
    final hash = stream['infoHash']?.toString();
    return hash != null && hash.isNotEmpty;
  }

  Future<String?> downloadsDirectoryPath() async => _baseDir;

  Future<List<DownloadedMovie>> listDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsIndexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List;
      final out = <DownloadedMovie>[];
      for (final item in list) {
        if (item is! Map) continue;
        final m = DownloadedMovie.fromJson(Map<String, dynamic>.from(item));
        if (await File(m.filePath).exists()) {
          out.add(m);
        }
      }
      if (out.length != list.length) {
        await _saveIndex(out);
      }
      return out;
    } catch (e) {
      debugPrint('[MovieDownload] list index: $e');
      return [];
    }
  }

  Future<bool> deleteDownload(String id) async {
    final items = await listDownloaded();
    DownloadedMovie? match;
    for (final m in items) {
      if (m.id == id) {
        match = m;
        break;
      }
    }
    if (match == null) return false;
    try {
      final f = File(match.filePath);
      if (await f.exists()) await f.delete();
      final meta = File('${match.filePath}.json');
      if (await meta.exists()) await meta.delete();
    } catch (e) {
      debugPrint('[MovieDownload] delete file: $e');
    }
    final remaining = items.where((m) => m.id != id).toList();
    await _saveIndex(remaining);
    return true;
  }

  void cancel(String id) {
    _cancelledIds.add(id);
    final cur = activeDownloads.value[id];
    if (cur != null) {
      _updateProgress(
        cur.copyWith(status: 'cancelled', error: 'Cancelled'),
      );
    }
  }

  /// Returns the download id when accepted, or null if rejected.
  Future<String?> startStremioDownload({
    required Map<String, dynamic> stream,
    required Movie movie,
    int? season,
    int? episode,
  }) async {
    if (!canDownloadStream(stream)) {
      debugPrint('[MovieDownload] Stream not downloadable');
      return null;
    }

    final id = _downloadId(stream, movie, season, episode);
    if (activeDownloads.value.containsKey(id)) return id;

    final sourceLabel = (stream['title'] ?? stream['name'] ?? stream['_addonName'] ?? 'Stremio')
        .toString();

    _cancelledIds.remove(id);
    _updateProgress(MovieDownloadProgress(
      id: id,
      title: _displayTitle(movie, season, episode),
      status: 'downloading',
      progress: 0,
    ));

    unawaited(() async {
      String? magnetForCleanup;
      try {
        final resolved = await _resolveHttpSource(
          stream: stream,
          movie: movie,
          season: season,
          episode: episode,
        );
        if (resolved == null) {
          _updateProgress(MovieDownloadProgress(
            id: id,
            title: _displayTitle(movie, season, episode),
            status: 'error',
            error: 'Could not resolve a downloadable file URL '
                '(HLS playlists and external links are not supported).',
          ));
          return;
        }
        magnetForCleanup = resolved.magnetToCleanup;

        if (_cancelledIds.contains(id)) {
          _cleanupTorrent(magnetForCleanup);
          _removeProgress(id);
          return;
        }

        final saved = await _downloadHttpToFile(
          id: id,
          title: _displayTitle(movie, season, episode),
          url: resolved.url,
          headers: resolved.headers,
          preferredName: resolved.fileNameHint ??
              _sanitizeFileName(_displayTitle(movie, season, episode)),
          extHint: resolved.extHint,
        );

        _cleanupTorrent(magnetForCleanup);

        if (_cancelledIds.contains(id)) {
          if (saved != null) {
            try {
              await File(saved.path).delete();
            } catch (_) {}
          }
          _removeProgress(id);
          return;
        }

        if (saved == null) {
          _updateProgress(MovieDownloadProgress(
            id: id,
            title: _displayTitle(movie, season, episode),
            status: 'error',
            error: 'Download failed',
          ));
          return;
        }

        final entry = DownloadedMovie(
          id: id,
          title: movie.title,
          posterPath: movie.posterPath.isNotEmpty ? movie.posterPath : null,
          filePath: saved.path,
          sizeBytes: saved.lengthSync(),
          downloadedAt: DateTime.now(),
          mediaType: movie.mediaType,
          season: season,
          episode: episode,
          sourceLabel: sourceLabel,
        );
        await _appendIndex(entry);
        await File('${saved.path}.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(entry.toJson()),
        );

        _updateProgress(MovieDownloadProgress(
          id: id,
          title: entry.displayTitle,
          status: 'completed',
          progress: 1,
          downloadedBytes: entry.sizeBytes,
          totalBytes: entry.sizeBytes,
          filePath: entry.filePath,
        ));
      } catch (e, st) {
        debugPrint('[MovieDownload] failed: $e\n$st');
        _cleanupTorrent(magnetForCleanup);
        _updateProgress(MovieDownloadProgress(
          id: id,
          title: _displayTitle(movie, season, episode),
          status: 'error',
          error: e.toString(),
        ));
      }
    }());

    return id;
  }

  // ── Resolve stream → HTTP ────────────────────────────────────────────────

  Future<_ResolvedSource?> _resolveHttpSource({
    required Map<String, dynamic> stream,
    required Movie movie,
    int? season,
    int? episode,
  }) async {
    final direct = stream['url']?.toString();
    if (direct != null && direct.isNotEmpty) {
      if (_looksLikeHls(direct)) return null;
      final headers = stremioProxyRequestHeadersFromStream(stream);
      return _ResolvedSource(
        url: direct,
        headers: headers.isEmpty ? null : headers,
        extHint: _extFromUrl(direct),
        fileNameHint: _fileNameFromUrl(direct),
      );
    }

    final infoHash = stream['infoHash']?.toString();
    if (infoHash == null || infoHash.isEmpty) return null;

    final magnet = _magnetFromStream(stream);
    final useDebrid = await _settings.useDebridForStreams();
    final debridService = await _settings.getDebridService();

    if (useDebrid && debridService != 'None') {
      final files = await DebridApi().resolveByService(
        debridService,
        magnet,
        season: movie.mediaType == 'tv' ? season : null,
        episode: movie.mediaType == 'tv' ? episode : null,
      );
      if (files.isEmpty) return null;
      final file = files.first;
      if (_looksLikeHls(file.downloadUrl)) return null;
      return _ResolvedSource(
        url: file.downloadUrl,
        extHint: _extFromName(file.filename) ?? _extFromUrl(file.downloadUrl),
        fileNameHint: _stripExt(file.filename),
      );
    }

    final url = await TorrentStreamService().streamTorrent(
      magnet,
      season: movie.mediaType == 'tv' ? season : null,
      episode: movie.mediaType == 'tv' ? episode : null,
    );
    if (url == null || url.isEmpty) return null;
    return _ResolvedSource(
      url: url,
      magnetToCleanup: magnet,
      extHint: 'mkv',
      fileNameHint: _sanitizeFileName(_displayTitle(movie, season, episode)),
    );
  }

  String _magnetFromStream(Map<String, dynamic> stream) {
    final infoHash = stream['infoHash'] as String;
    final streamTitle = (stream['title'] ?? stream['name'] ?? '').toString();
    final dn =
        streamTitle.isNotEmpty ? '&dn=${Uri.encodeComponent(streamTitle)}' : '';
    final trackerParams = StringBuffer();
    final sources = stream['sources'];
    if (sources is List) {
      for (final src in sources) {
        if (src is String && src.startsWith('tracker:')) {
          final tracker = src.substring('tracker:'.length);
          trackerParams.write('&tr=${Uri.encodeComponent(tracker)}');
        }
      }
    }
    return 'magnet:?xt=urn:btih:$infoHash$dn$trackerParams';
  }

  void _cleanupTorrent(String? magnet) {
    if (magnet == null || magnet.isEmpty) return;
    try {
      TorrentStreamService().removeTorrent(magnet);
    } catch (e) {
      debugPrint('[MovieDownload] torrent cleanup: $e');
    }
  }

  // ── HTTP download ────────────────────────────────────────────────────────

  Future<File?> _downloadHttpToFile({
    required String id,
    required String title,
    required String url,
    Map<String, String>? headers,
    required String preferredName,
    String? extHint,
  }) async {
    final base = await _baseDir;
    final ext = (extHint != null && extHint.isNotEmpty)
        ? extHint
        : (_extFromUrl(url) ?? 'mp4');
    final fileName = '${_sanitizeFileName(preferredName)}.$ext';
    final outPath = p.join(base, fileName);
    final tmpPath = '$outPath.part';
    final out = File(outPath);
    final tmp = File(tmpPath);
    if (await tmp.exists()) await tmp.delete();

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      if (headers != null) req.headers.addAll(headers);
      // Some local torrent streams expect a browser UA.
      req.headers.putIfAbsent(
        'User-Agent',
        () =>
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
      );

      final resp = await client.send(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final total = resp.contentLength;
      var downloaded = 0;
      final sink = tmp.openWrite();
      await for (final chunk in resp.stream) {
        if (_cancelledIds.contains(id)) {
          await sink.close();
          if (await tmp.exists()) await tmp.delete();
          return null;
        }
        sink.add(chunk);
        downloaded += chunk.length;
        final progress = (total != null && total > 0)
            ? (downloaded / total).clamp(0.0, 1.0)
            : 0.0;
        _updateProgress(MovieDownloadProgress(
          id: id,
          title: title,
          status: 'downloading',
          progress: progress,
          downloadedBytes: downloaded,
          totalBytes: total,
        ));
      }
      await sink.flush();
      await sink.close();

      if (await out.exists()) await out.delete();
      await tmp.rename(outPath);
      return File(outPath);
    } finally {
      client.close();
    }
  }

  // ── Storage helpers ──────────────────────────────────────────────────────

  Future<void> _requestAndroidDownloadPermissions() async {
    if (!Platform.isAndroid) return;
    await Permission.storage.request();
  }

  Future<String> get _baseDir async {
    if (Platform.isAndroid) {
      await _requestAndroidDownloadPermissions();
      try {
        final ext =
            await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (ext != null && ext.isNotEmpty) {
          final sub = Directory(p.join(ext.first.path, 'PlayTorrio', 'Movies'));
          if (!await sub.exists()) await sub.create(recursive: true);
          return sub.path;
        }
      } catch (e) {
        debugPrint('[MovieDownload] external downloads: $e');
      }
      final publicRoot = Directory(
        p.join('/storage/emulated/0/Download', 'PlayTorrio', 'Movies'),
      );
      try {
        if (!await publicRoot.exists()) {
          await publicRoot.create(recursive: true);
        }
        final probe = File(p.join(publicRoot.path, '.playtorrio_write_probe'));
        await probe.writeAsString('1', flush: true);
        await probe.delete();
        return publicRoot.path;
      } catch (e) {
        debugPrint('[MovieDownload] public Download not writable: $e');
      }
    }

    final dl = await getDownloadsDirectory();
    if (dl != null) {
      final sub = Directory(p.join(dl.path, 'PlayTorrio', 'Movies'));
      if (!await sub.exists()) await sub.create(recursive: true);
      return sub.path;
    }

    final docs = await getApplicationDocumentsDirectory();
    final sub = Directory(p.join(docs.path, 'PlayTorrio', 'Movies'));
    if (!await sub.exists()) await sub.create(recursive: true);
    return sub.path;
  }

  Future<void> _appendIndex(DownloadedMovie entry) async {
    final items = await listDownloaded();
    items.removeWhere((m) => m.id == entry.id);
    items.insert(0, entry);
    await _saveIndex(items);
  }

  Future<void> _saveIndex(List<DownloadedMovie> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsIndexKey,
      json.encode(items.map((e) => e.toJson()).toList()),
    );
  }

  void _updateProgress(MovieDownloadProgress progress) {
    final map =
        Map<String, MovieDownloadProgress>.from(activeDownloads.value);
    map[progress.id] = progress;
    activeDownloads.value = map;
  }

  void _removeProgress(String id) {
    final map =
        Map<String, MovieDownloadProgress>.from(activeDownloads.value);
    map.remove(id);
    activeDownloads.value = map;
  }

  String _downloadId(
    Map<String, dynamic> stream,
    Movie movie,
    int? season,
    int? episode,
  ) {
    final key = stream['url']?.toString() ??
        stream['infoHash']?.toString() ??
        stream['title']?.toString() ??
        'unknown';
    final ep = (season != null && episode != null) ? '_S${season}_E$episode' : '';
    return 'm${movie.id}$ep_${key.hashCode.abs()}';
  }

  String _displayTitle(Movie movie, int? season, int? episode) {
    if (movie.mediaType == 'tv' && season != null && episode != null) {
      return '${movie.title} S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
    }
    return movie.title;
  }

  String _sanitizeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (cleaned.isEmpty) return 'movie';
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  bool _looksLikeHls(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('format=m3u8');
  }

  String? _extFromUrl(String url) {
    try {
      final path = Uri.parse(url).path;
      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      if (ext.isEmpty) return null;
      if (ext.length > 5) return null;
      if (ext == 'm3u8' || ext == 'm3u') return null;
      return ext;
    } catch (_) {
      return null;
    }
  }

  String? _extFromName(String name) {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    if (ext.isEmpty || ext.length > 5) return null;
    return ext;
  }

  String? _fileNameFromUrl(String url) {
    try {
      final base = p.basenameWithoutExtension(Uri.parse(url).path);
      if (base.isEmpty || base == '/') return null;
      return _sanitizeFileName(Uri.decodeComponent(base));
    } catch (_) {
      return null;
    }
  }

  String _stripExt(String name) {
    final without = p.basenameWithoutExtension(name);
    return _sanitizeFileName(without.isEmpty ? name : without);
  }
}

class _ResolvedSource {
  final String url;
  final Map<String, String>? headers;
  final String? magnetToCleanup;
  final String? extHint;
  final String? fileNameHint;

  const _ResolvedSource({
    required this.url,
    this.headers,
    this.magnetToCleanup,
    this.extHint,
    this.fileNameHint,
  });
}

extension on MovieDownloadProgress {
  MovieDownloadProgress copyWith({
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? status,
    String? error,
    String? filePath,
  }) {
    return MovieDownloadProgress(
      id: id,
      title: title,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      error: error ?? this.error,
      filePath: filePath ?? this.filePath,
    );
  }
}
