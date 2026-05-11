import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audiobook_service.dart';
import 'audiobook_prefs_keys.dart';
import 'audio_handler.dart';
import 'torrent_stream_service.dart';
import '../services/playtorrio_cloud_sync_service.dart';

class AudiobookPlayerService {
  static final AudiobookPlayerService _instance = AudiobookPlayerService._internal();
  factory AudiobookPlayerService() => _instance;
  AudiobookPlayerService._internal();

  /// Headers for libtorrent's loopback HTTP stream (mpv is picky without these).
  static const Map<String, String> magnetStreamHttpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': '*/*',
  };

  final Player _player = Player();
  PlayTorrioAudioHandler? _handler;
  
  // State
  final ValueNotifier<Audiobook?> currentBook = ValueNotifier<Audiobook?>(null);
  final ValueNotifier<int> currentChapterIndex = ValueNotifier<int>(0);
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isBuffering = ValueNotifier<bool>(false);
  final ValueNotifier<bool> autoplay = ValueNotifier<bool>(true);
  
  List<AudiobookChapter> _currentChapters = [];
  final List<StreamSubscription> _subscriptions = [];
  bool _isResuming = false;

  void init(BaseAudioHandler handler) {
    _handler = handler as PlayTorrioAudioHandler;
    
    _subscriptions.add(_player.stream.position.listen((p) {
      position.value = p;
      _updateSystemState();
      // Only save if we are not currently in the middle of a resume seek
      if (!_isResuming && p > Duration.zero) {
        _saveProgress();
      }
    }));
    
    _subscriptions.add(_player.stream.duration.listen((d) {
      duration.value = d;
      _updateSystemState();
    }));
    
    _subscriptions.add(_player.stream.playing.listen((pl) {
      isPlaying.value = pl;
      _updateSystemState();
    }));
    
    _subscriptions.add(_player.stream.buffering.listen((b) {
      isBuffering.value = b;
      _updateSystemState();
    }));

    _subscriptions.add(_player.stream.completed.listen((completed) {
      if (completed && autoplay.value) {
        final nextIdx = currentChapterIndex.value + 1;
        if (nextIdx < _currentChapters.length) {
          unawaited(changeChapter(nextIdx));
        }
      }
    }));
  }

  void _updateSystemState() {
    if (_handler == null || currentBook.value == null) return;
    
    _handler!.updateState(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        isPlaying.value ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.playPause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: isBuffering.value ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: isPlaying.value,
      updatePosition: position.value,
      bufferedPosition: position.value,
      speed: _player.state.rate,
    ));
  }

  Future<void> loadBook(Audiobook book, List<AudiobookChapter> chapters, {int initialChapter = 0, Duration? resumePosition}) async {
    _isResuming = resumePosition != null && resumePosition > Duration.zero;
    currentBook.value = book;
    _currentChapters = chapters;
    currentChapterIndex.value = initialChapter;
    
    _handler?.setPlayerType(AudioPlayerType.audiobook, _player);
    
    String artist = 'Tokybook';
    if (book.source == 'audiozaic') artist = 'Audiozaic';
    if (book.source == 'goldenaudiobook') artist = 'GoldenAudiobook';
    if (book.source == 'appaudiobooks') artist = 'AppAudiobooks';
    if (book.source == 'magnet') artist = 'Torrent';
    if (book.source == 'audiobookbay') artist = 'Audiobook Bay';

    String art = book.thumbUrl.trim();
    if (art.isEmpty) art = book.coverImage.trim();

    _handler?.updateMediaItem(MediaItem(
      id: book.audioBookId,
      album: 'Audiobook',
      title: book.title,
      artist: artist,
      duration: null,
      artUri: art.isEmpty ? null : Uri.tryParse(art),
    ));

    // Optimize for streaming audiobooks
    if (_player.platform is NativePlayer) {
      final p = _player.platform as NativePlayer;
      await p.setProperty('hr-seek', 'yes'); // 'yes' is faster than 'always' for streams
      await p.setProperty('cache', 'yes');
      await p.setProperty('demuxer-max-bytes', '50000000'); // 50MB cache
      await p.setProperty('demuxer-max-back-bytes', '50000000');
      await p.setProperty('demuxer-readahead-secs', '30');
      if (book.source == 'magnet' || book.source == 'audiobookbay') {
        await p.setProperty('force-seekable', 'yes');
      }
    }

    final media = await _mediaForChapter(book, chapters[initialChapter]);

    // Open without auto-playing first to allow seek to settle
    await _player.open(media, play: false);
    
    if (_isResuming) {
      debugPrint('AudiobookPlayerService: Resuming at $resumePosition');

      final initialCh = chapters[initialChapter];
      final torrentResume = (book.source == 'magnet' ||
              book.source == 'audiobookbay') &&
          book.magnetLink != null &&
          book.magnetLink!.trim().isNotEmpty &&
          initialCh.torrentFileIndex != null;

      if (torrentResume) {
        // Torrent-backed HTTP streams often report duration=0 until buffered;
        // waiting on duration causes seeks to be skipped after the short timeout.
        await Future.delayed(const Duration(milliseconds: 2800));
        await _player.seek(resumePosition!);
        await Future.delayed(const Duration(milliseconds: 700));
        await _player.seek(resumePosition!);
        await Future.delayed(const Duration(milliseconds: 700));
      } else {
        // Wait for duration (direct URLs) before seeking.
        final ready = Completer<void>();
        late StreamSubscription<Duration> durSub;
        durSub = _player.stream.duration.listen((d) {
          if (d > Duration.zero && !ready.isCompleted) {
            ready.complete();
          }
        });

        await ready.future.timeout(const Duration(seconds: 12),
            onTimeout: () {});
        await durSub.cancel();

        await _player.seek(resumePosition!);
        await Future.delayed(const Duration(milliseconds: 800));
      }
      _isResuming = false;
    }

    _player.play();
  }

  Future<Media> _mediaForChapter(Audiobook book, AudiobookChapter ch) async {
    final magnet = book.magnetLink;
    final torrentBacked = (book.source == 'magnet' || book.source == 'audiobookbay') &&
        magnet != null &&
        magnet.isNotEmpty &&
        ch.torrentFileIndex != null;
    if (!torrentBacked) {
      final headers = ch.headers ?? const <String, String>{};
      return Media(ch.url, httpHeaders: headers);
    }

    final torrent = TorrentStreamService();
    final started = await torrent.start();
    if (!started) {
      throw Exception('Torrent engine failed to start');
    }
    torrent.stopAudiobookStreamsForMagnet(magnet);
    final url = await torrent.streamAudiobookFile(
      magnet,
      ch.torrentFileIndex!,
      allowNonStreamable: true,
      stopSiblingStreams: false,
      fileNameHint: ch.title,
    );
    if (url == null || url.isEmpty) {
      throw Exception('Could not stream torrent file: ${ch.title}');
    }
    final merged = Map<String, String>.from(magnetStreamHttpHeaders);
    if (ch.headers != null) {
      merged.addAll(ch.headers!);
    }
    return Media(url, httpHeaders: merged);
  }

  void playOrPause() => _player.playOrPause();
  void seek(Duration p) => _player.seek(p);
  void setRate(double r) => _player.setRate(r);

  void skipToNextChapter() {
    final nextIdx = currentChapterIndex.value + 1;
    if (nextIdx < _currentChapters.length) {
      unawaited(changeChapter(nextIdx));
    }
  }

  void skipToPreviousChapter() {
    final prevIdx = currentChapterIndex.value - 1;
    if (prevIdx >= 0) {
      unawaited(changeChapter(prevIdx));
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _updateSystemState();
  }

  Future<void> changeChapter(int index) async {
    if (index < 0 || index >= _currentChapters.length) return;
    currentChapterIndex.value = index;
    final book = currentBook.value;
    if (book == null) return;
    try {
      final media = await _mediaForChapter(book, _currentChapters[index]);
      await _player.open(media);
      _player.play();
    } catch (e, st) {
      debugPrint('AudiobookPlayerService.changeChapter: $e\n$st');
    }
  }

  // --- Persistence (History) ---

  Future<void> _saveProgress() async {
    if (currentBook.value == null || _isResuming) return;
    final prefs = await SharedPreferences.getInstance();
    
    List<String> historyStrings =
        prefs.getStringList(AudiobookPrefsKeys.history) ?? [];
    List<Map<String, dynamic>> history = historyStrings
        .map((s) => json.decode(s) as Map<String, dynamic>)
        .toList();

    final bookData = {
      'book': currentBook.value!.toJson(),
      'chapterIndex': currentChapterIndex.value,
      'positionMs': position.value.inMilliseconds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    history.removeWhere((item) => item['book']['audioBookId'] == currentBook.value!.audioBookId);
    history.insert(0, bookData);
    
    if (history.length > 10) history = history.sublist(0, 10);

    await prefs.setStringList(
      AudiobookPrefsKeys.history,
      history.map((e) => json.encode(e)).toList(),
    );
    PlaytorrioCloudSyncService.instance.scheduleDebouncedSettingsPush();
  }

  Future<void> saveManualProgress() async {
    await _saveProgress();
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList(AudiobookPrefsKeys.history) ?? [];
    return history.map((s) => json.decode(s) as Map<String, dynamic>).toList();
  }

  Future<void> removeFromHistory(String audioBookId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> historyStrings = prefs.getStringList(AudiobookPrefsKeys.history) ?? [];
    historyStrings.removeWhere((s) {
      final data = json.decode(s);
      return data['book']['audioBookId'] == audioBookId;
    });
    await prefs.setStringList(AudiobookPrefsKeys.history, historyStrings);
    PlaytorrioCloudSyncService.instance.scheduleSettingsPush();
  }

  // --- Liked Books ---

  Future<List<Audiobook>> getLikedBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> liked = prefs.getStringList(AudiobookPrefsKeys.liked) ?? [];
    return liked.map((s) => Audiobook.fromJson(json.decode(s))).toList();
  }

  Future<bool> isBookLiked(String audioBookId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> liked = prefs.getStringList(AudiobookPrefsKeys.liked) ?? [];
    return liked.any((s) => json.decode(s)['audioBookId'] == audioBookId);
  }

  Future<void> toggleLikeBook(Audiobook book) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> likedStrings = prefs.getStringList(AudiobookPrefsKeys.liked) ?? [];
    
    final index = likedStrings.indexWhere((s) => json.decode(s)['audioBookId'] == book.audioBookId);
    
    if (index >= 0) {
      likedStrings.removeAt(index);
    } else {
      likedStrings.add(json.encode(book.toJson()));
    }
    
    await prefs.setStringList(AudiobookPrefsKeys.liked, likedStrings);
    PlaytorrioCloudSyncService.instance.scheduleSettingsPush();
  }

  void dispose() {
    for (var s in _subscriptions) { s.cancel(); }
    _player.dispose();
  }
}
