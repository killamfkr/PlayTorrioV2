import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'audiobook_download_types.dart';
import 'audiobook_service.dart';

class AudiobookDownloadService {
  static final AudiobookDownloadService _instance =
      AudiobookDownloadService._internal();
  factory AudiobookDownloadService() => _instance;
  AudiobookDownloadService._internal();

  final ValueNotifier<Map<String, AudiobookDownloadProgress>> activeDownloads =
      ValueNotifier({});

  final Set<String> _cancelledIds = {};

  /// Legacy location (app private) — still scanned so older downloads appear.
  Future<String> get _legacyAppDocAudiobooksDir async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'audiobooks');
  }

  Future<void> _requestAndroidDownloadPermissions() async {
    if (!Platform.isAndroid) return;
    await Permission.audio.request();
    await Permission.storage.request();
  }

  /// Preferred on Android: **shared Downloads** (often under
  /// `/storage/emulated/0/Download/...` when the OS allows it), else app-accessible
  /// download dirs, else legacy app documents.
  Future<String> get _baseDir async {
    if (Platform.isAndroid) {
      await _requestAndroidDownloadPermissions();
      try {
        final ext = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (ext != null && ext.isNotEmpty) {
          final sub = Directory(p.join(ext.first.path, 'PlayTorrio', 'Audiobooks'));
          if (!await sub.exists()) await sub.create(recursive: true);
          debugPrint('[AudiobookDownload] Using external Downloads: ${sub.path}');
          return sub.path;
        }
      } catch (e) {
        debugPrint('[AudiobookDownload] external StorageDirectory.downloads: $e');
      }
      // Typical public Download path (visible in Files → Download) — may fail on
      // strict scoped storage without MANAGE_EXTERNAL_STORAGE; then we fall back.
      final publicRoot =
          Directory(p.join('/storage/emulated/0/Download', 'PlayTorrio', 'Audiobooks'));
      try {
        if (!await publicRoot.exists()) {
          await publicRoot.create(recursive: true);
        }
        final probe = File(p.join(publicRoot.path, '.playtorrio_write_probe'));
        await probe.writeAsString('1', flush: true);
        await probe.delete();
        debugPrint('[AudiobookDownload] Using public Download folder: ${publicRoot.path}');
        return publicRoot.path;
      } catch (e) {
        debugPrint('[AudiobookDownload] Public Download not writable: $e');
      }
      final dl = await getDownloadsDirectory();
      if (dl != null) {
        final sub = Directory(p.join(dl.path, 'PlayTorrio', 'Audiobooks'));
        if (!await sub.exists()) await sub.create(recursive: true);
        debugPrint('[AudiobookDownload] Using getDownloadsDirectory: ${sub.path}');
        return sub.path;
      }
    } else if (!Platform.isIOS) {
      final dl = await getDownloadsDirectory();
      if (dl != null) {
        final sub = Directory(p.join(dl.path, 'PlayTorrio', 'Audiobooks'));
        if (!await sub.exists()) await sub.create(recursive: true);
        return sub.path;
      }
    }

    final legacy = await _legacyAppDocAudiobooksDir;
    final audiobooksDir = Directory(legacy);
    if (!await audiobooksDir.exists()) {
      await audiobooksDir.create(recursive: true);
    }
    debugPrint('[AudiobookDownload] Using app documents: ${audiobooksDir.path}');
    return audiobooksDir.path;
  }

  /// All roots that may contain downloaded books (merge + dedupe by id).
  Future<List<String>> _allAudiobookBaseDirs() async {
    final bases = <String>{};
    bases.add(await _baseDir);
    bases.add(await _legacyAppDocAudiobooksDir);
    if (Platform.isAndroid) {
      final public = '/storage/emulated/0/Download/PlayTorrio/Audiobooks';
      if (await Directory(public).exists()) bases.add(public);
      try {
        final ext = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (ext != null && ext.isNotEmpty) {
          final ed = p.join(ext.first.path, 'PlayTorrio', 'Audiobooks');
          if (await Directory(ed).exists()) bases.add(ed);
        }
      } catch (_) {}
      final gd = await getDownloadsDirectory();
      if (gd != null) {
        final gds = p.join(gd.path, 'PlayTorrio', 'Audiobooks');
        if (await Directory(gds).exists()) bases.add(gds);
      }
    }
    return bases.toList();
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  }

  void _updateProgress(String id, AudiobookDownloadProgress progress) {
    final map = Map<String, AudiobookDownloadProgress>.from(activeDownloads.value);
    map[id] = progress;
    activeDownloads.value = map;
  }

  void _removeProgress(String id) {
    final map = Map<String, AudiobookDownloadProgress>.from(activeDownloads.value);
    map.remove(id);
    activeDownloads.value = map;
  }

  Future<void> downloadBook(
    Audiobook book,
    List<AudiobookChapter> chapters,
  ) async {
    final id = book.audioBookId;

    // Don't start if already downloading
    if (activeDownloads.value.containsKey(id)) return;

    _cancelledIds.remove(id);

    final base = await _baseDir;
    final bookDir = Directory(p.join(base, _sanitizeFileName(id)));
    if (await bookDir.exists()) {
      await bookDir.delete(recursive: true);
    }
    await bookDir.create(recursive: true);

    _updateProgress(
      id,
      AudiobookDownloadProgress(
        audioBookId: id,
        book: book,
        totalChapters: chapters.length + 1, // +1 for cover
        completedChapters: 0,
        status: 'downloading',
      ),
    );

    try {
      // 1. Download cover image
      final coverPath = p.join(bookDir.path, 'cover.jpg');
      await _downloadCover(book.thumbUrl, book.coverImage, coverPath);

      if (_cancelledIds.contains(id)) {
        await _cleanup(bookDir, id);
        return;
      }

      _updateProgress(
        id,
        AudiobookDownloadProgress(
          audioBookId: id,
          book: book,
          totalChapters: chapters.length + 1,
          completedChapters: 1,
          status: 'downloading',
        ),
      );

      // 2. Download all chapters
      List<DownloadedChapter> downloadedChapters = [];
      int totalSize = 0;

      for (int i = 0; i < chapters.length; i++) {
        if (_cancelledIds.contains(id)) {
          await _cleanup(bookDir, id);
          return;
        }

        final chapter = chapters[i];
        final ext = _getFileExtension(chapter.url, book.source);
        final fileName = 'chapter_$i$ext';
        final filePath = p.join(bookDir.path, fileName);

        final bytes = await _downloadChapter(chapter, book.source);

        if (_cancelledIds.contains(id)) {
          await _cleanup(bookDir, id);
          return;
        }

        if (bytes != null && bytes.isNotEmpty) {
          await File(filePath).writeAsBytes(bytes);
          totalSize += bytes.length;
          downloadedChapters.add(DownloadedChapter(
            title: chapter.title,
            filePath: filePath,
            sizeBytes: bytes.length,
          ));
        } else {
          // Save empty placeholder so indexing stays consistent
          downloadedChapters.add(DownloadedChapter(
            title: chapter.title,
            filePath: filePath,
            sizeBytes: 0,
          ));
        }

        _updateProgress(
          id,
          AudiobookDownloadProgress(
            audioBookId: id,
            book: book,
            totalChapters: chapters.length + 1,
            completedChapters: i + 2, // +1 cover, +1 for this chapter
            status: 'downloading',
          ),
        );
      }

      // 3. Save metadata
      final metadata = DownloadedAudiobook(
        book: book,
        chapters: downloadedChapters,
        coverPath: coverPath,
        totalSizeBytes: totalSize,
        downloadedAt: DateTime.now(),
      );

      final metadataFile = File(p.join(bookDir.path, 'metadata.json'));
      await metadataFile.writeAsString(json.encode(metadata.toJson()));

      _updateProgress(
        id,
        AudiobookDownloadProgress(
          audioBookId: id,
          book: book,
          totalChapters: chapters.length + 1,
          completedChapters: chapters.length + 1,
          status: 'completed',
        ),
      );

      // Remove from active after short delay so UI can show completion
      Future.delayed(const Duration(seconds: 2), () => _removeProgress(id));
    } catch (e) {
      debugPrint('[AudiobookDownload] Error downloading $id: $e');
      _updateProgress(
        id,
        AudiobookDownloadProgress(
          audioBookId: id,
          book: book,
          totalChapters: chapters.length + 1,
          completedChapters: 0,
          status: 'failed',
          error: e.toString(),
        ),
      );
    }
  }

  // Track individual chapter downloads: key = "audioBookId_chapterIndex"
  final ValueNotifier<Set<String>> downloadingChapters = ValueNotifier({});
  final ValueNotifier<Set<String>> downloadedChapterKeys = ValueNotifier({});

  Future<void> cancelDownload(String audioBookId) async {
    _cancelledIds.add(audioBookId);
    _removeProgress(audioBookId);
    for (final base in await _allAudiobookBaseDirs()) {
      final bookDir = Directory(p.join(base, _sanitizeFileName(audioBookId)));
      try {
        if (await bookDir.exists()) await bookDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _cleanup(Directory dir, String id) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    _removeProgress(id);
    _cancelledIds.remove(id);
  }

  String _chapterKey(String audioBookId, int index) => '${audioBookId}_$index';

  Future<void> downloadSingleChapter(
    Audiobook book,
    AudiobookChapter chapter,
    int chapterIndex,
  ) async {
    final key = _chapterKey(book.audioBookId, chapterIndex);

    // Skip if already downloading or downloaded
    if (downloadingChapters.value.contains(key)) return;
    if (downloadedChapterKeys.value.contains(key)) return;

    // Mark as downloading
    downloadingChapters.value = {...downloadingChapters.value, key};

    try {
      final base = await _baseDir;
      final bookDir = Directory(p.join(base, _sanitizeFileName(book.audioBookId)));
      if (!await bookDir.exists()) {
        await bookDir.create(recursive: true);
      }

      // Download cover if not present
      final coverPath = p.join(bookDir.path, 'cover.jpg');
      if (!File(coverPath).existsSync()) {
        await _downloadCover(book.thumbUrl, book.coverImage, coverPath);
      }

      // Download the chapter
      final ext = _getFileExtension(chapter.url, book.source);
      final fileName = 'chapter_$chapterIndex$ext';
      final filePath = p.join(bookDir.path, fileName);

      final bytes = await _downloadChapter(chapter, book.source);

      if (bytes != null && bytes.isNotEmpty) {
        await File(filePath).writeAsBytes(bytes);

        // Update or create metadata
        await _upsertChapterMetadata(book, bookDir.path, chapterIndex, chapter.title, fileName, bytes.length);
      }

      // Mark as downloaded
      downloadedChapterKeys.value = {...downloadedChapterKeys.value, key};
    } catch (e) {
      debugPrint('[AudiobookDownload] Single chapter error: $e');
    } finally {
      final updated = {...downloadingChapters.value};
      updated.remove(key);
      downloadingChapters.value = updated;
    }
  }

  Future<void> _upsertChapterMetadata(
    Audiobook book,
    String bookDirPath,
    int chapterIndex,
    String chapterTitle,
    String fileName,
    int sizeBytes,
  ) async {
    final metaFile = File(p.join(bookDirPath, 'metadata.json'));
    Map<String, dynamic> data;

    if (await metaFile.exists()) {
      data = json.decode(await metaFile.readAsString());
    } else {
      data = {
        'book': book.toJson(),
        'chapters': [],
        'coverFile': 'cover.jpg',
        'totalSizeBytes': 0,
        'downloadedAt': DateTime.now().millisecondsSinceEpoch,
      };
    }

    final chapters = (data['chapters'] as List).cast<Map<String, dynamic>>();

    // Remove existing entry for this chapter if any
    chapters.removeWhere((c) => c['file'] == fileName);
    chapters.add({
      'title': chapterTitle,
      'file': fileName,
      'sizeBytes': sizeBytes,
    });

    // Sort by chapter index (extracted from filename)
    chapters.sort((a, b) {
      final aIdx = int.tryParse(RegExp(r'chapter_(\d+)').firstMatch(a['file'] ?? '')?.group(1) ?? '0') ?? 0;
      final bIdx = int.tryParse(RegExp(r'chapter_(\d+)').firstMatch(b['file'] ?? '')?.group(1) ?? '0') ?? 0;
      return aIdx.compareTo(bIdx);
    });

    int totalSize = 0;
    for (final c in chapters) {
      totalSize += (c['sizeBytes'] as int? ?? 0);
    }

    data['chapters'] = chapters;
    data['totalSizeBytes'] = totalSize;
    data['downloadedAt'] = DateTime.now().millisecondsSinceEpoch;

    await metaFile.writeAsString(json.encode(data));
  }

  Future<void> checkDownloadedChapters(String audioBookId, int totalChapters) async {
    final newKeys = <String>{};
    for (final base in await _allAudiobookBaseDirs()) {
      final metaFile = File(
          p.join(base, _sanitizeFileName(audioBookId), 'metadata.json'));
      if (!metaFile.existsSync()) continue;
      try {
        final data = json.decode(await metaFile.readAsString());
        final chapters = (data['chapters'] as List).cast<Map<String, dynamic>>();
        for (final c in chapters) {
          final match = RegExp(r'chapter_(\d+)').firstMatch(c['file'] ?? '');
          if (match != null && (c['sizeBytes'] as int? ?? 0) > 0) {
            newKeys.add(_chapterKey(audioBookId, int.parse(match.group(1)!)));
          }
        }
      } catch (_) {}
    }
    if (newKeys.isEmpty) return;
    downloadedChapterKeys.value = {...downloadedChapterKeys.value, ...newKeys};
  }

  Future<void> _downloadCover(
      String primaryUrl, String fallbackUrl, String savePath) async {
    try {
      final response = await http.get(Uri.parse(primaryUrl), headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      });
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await File(savePath).writeAsBytes(response.bodyBytes);
        return;
      }
    } catch (_) {}

    // Try fallback
    try {
      if (fallbackUrl.isNotEmpty && fallbackUrl != primaryUrl) {
        final response = await http.get(Uri.parse(fallbackUrl), headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        });
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await File(savePath).writeAsBytes(response.bodyBytes);
        }
      }
    } catch (_) {}
  }

  String _getFileExtension(String url, String? source) {
    if (source == 'tokybook') return '.ts'; // HLS segments concatenated
    // Extract extension from URL
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    if (path.endsWith('.mp3')) return '.mp3';
    if (path.endsWith('.m4a')) return '.m4a';
    if (path.endsWith('.ogg')) return '.ogg';
    if (path.endsWith('.aac')) return '.aac';
    if (path.endsWith('.wav')) return '.wav';
    if (path.endsWith('.flac')) return '.flac';
    return '.mp3'; // Default for most scraped sources
  }

  Future<Uint8List?> _downloadChapter(
      AudiobookChapter chapter, String? source) async {
    if (source == 'tokybook') {
      return _downloadHlsChapter(chapter);
    }
    return _downloadDirectChapter(chapter);
  }

  Future<Uint8List?> _downloadDirectChapter(AudiobookChapter chapter) async {
    try {
      final response = await http.get(
        Uri.parse(chapter.url),
        headers: chapter.headers ?? {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('[AudiobookDownload] Direct download error: $e');
    }
    return null;
  }

  Future<Uint8List?> _downloadHlsChapter(AudiobookChapter chapter) async {
    try {
      // The chapter URL is a proxy URL pointing to an M3U8
      // Fetch the M3U8 playlist
      final m3u8Response = await http.get(Uri.parse(chapter.url));
      if (m3u8Response.statusCode != 200) return null;

      final m3u8Content = m3u8Response.body;
      final lines = m3u8Content.split('\n');

      // Extract segment URLs (non-empty, non-comment lines)
      final segmentUrls = lines
          .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('#'))
          .toList();

      if (segmentUrls.isEmpty) return null;

      // Download all segments and concatenate
      final BytesBuilder builder = BytesBuilder(copy: false);

      for (final segmentUrl in segmentUrls) {
        final segResponse = await http.get(Uri.parse(segmentUrl));
        if (segResponse.statusCode == 200) {
          builder.add(segResponse.bodyBytes);
        }
      }

      return builder.toBytes();
    } catch (e) {
      debugPrint('[AudiobookDownload] HLS download error: $e');
    }
    return null;
  }

  // --- Query downloaded books ---

  Future<List<DownloadedAudiobook>> getDownloadedBooks() async {
    final byId = <String, DownloadedAudiobook>{};
    for (final base in await _allAudiobookBaseDirs()) {
      final dir = Directory(base);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is! Directory) continue;
        final metaFile = File(p.join(entity.path, 'metadata.json'));
        if (!await metaFile.exists()) continue;
        try {
          final content = await metaFile.readAsString();
          final data = json.decode(content) as Map<String, dynamic>;
          final book = DownloadedAudiobook.fromJson(data, entity.path);
          final id = book.book.audioBookId;
          final existing = byId[id];
          if (existing == null || book.downloadedAt.isAfter(existing.downloadedAt)) {
            byId[id] = book;
          }
        } catch (e) {
          debugPrint('[AudiobookDownload] Error reading metadata: $e');
        }
      }
    }
    final books = byId.values.toList();
    books.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return books;
  }

  Future<bool> isBookDownloaded(String audioBookId) async {
    for (final base in await _allAudiobookBaseDirs()) {
      final metaFile =
          File(p.join(base, _sanitizeFileName(audioBookId), 'metadata.json'));
      if (await metaFile.exists()) return true;
    }
    return false;
  }

  Future<DownloadedAudiobook?> getDownloadedBook(String audioBookId) async {
    DownloadedAudiobook? best;
    for (final base in await _allAudiobookBaseDirs()) {
      final bookDir = Directory(p.join(base, _sanitizeFileName(audioBookId)));
      final metaFile = File(p.join(bookDir.path, 'metadata.json'));
      if (!await metaFile.exists()) continue;
      try {
        final content = await metaFile.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        final book = DownloadedAudiobook.fromJson(data, bookDir.path);
        if (best == null || book.downloadedAt.isAfter(best.downloadedAt)) {
          best = book;
        }
      } catch (e) {
        debugPrint('[AudiobookDownload] Error reading metadata: $e');
      }
    }
    return best;
  }

  Future<void> deleteBook(String audioBookId) async {
    for (final base in await _allAudiobookBaseDirs()) {
      final bookDir = Directory(p.join(base, _sanitizeFileName(audioBookId)));
      if (await bookDir.exists()) {
        try {
          await bookDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
}
