import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audiobook_service.dart';
import 'audio_handler.dart';

class AudiobookPlayerService {
  static final AudiobookPlayerService _instance = AudiobookPlayerService._internal();
  factory AudiobookPlayerService() => _instance;
  AudiobookPlayerService._internal();

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
          changeChapter(nextIdx);
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

    _handler?.updateMediaItem(MediaItem(
      id: book.audioBookId,
      album: 'Audiobook',
      title: book.title,
      artist: artist,
      duration: null,
      artUri: Uri.tryParse(book.thumbUrl),
    ));

    // Optimize for streaming audiobooks
    if (_player.platform is NativePlayer) {
      final p = _player.platform as NativePlayer;
      await p.setProperty('hr-seek', 'yes'); // 'yes' is faster than 'always' for streams
      await p.setProperty('cache', 'yes');
      await p.setProperty('demuxer-max-bytes', '50000000'); // 50MB cache
      await p.setProperty('demuxer-max-back-bytes', '50000000');
      await p.setProperty('demuxer-readahead-secs', '30');
    }

    // Open without auto-playing first to allow seek to settle
    await _player.open(Media(chapters[initialChapter].url, httpHeaders: chapters[initialChapter].headers), play: false);
    
    if (_isResuming) {
      debugPrint('AudiobookPlayerService: Resuming at $resumePosition');
      
      // Wait for duration to be valid (stream meta loaded)
      Completer<void> ready = Completer();
      late StreamSubscription durSub;
      durSub = _player.stream.duration.listen((d) {
        if (d > Duration.zero && !ready.isCompleted) {
          ready.complete();
        }
      });

      // Timeout after 8s
      await ready.future.timeout(const Duration(seconds: 8), onTimeout: () {});
      await durSub.cancel();

      // Perform the seek
      await _player.seek(resumePosition!);
      
      // Small buffer delay before allowing saves and starting playback
      await Future.delayed(const Duration(milliseconds: 800));
      _isResuming = false;
    }
    
    _player.play();
  }

  void playOrPause() => _player.playOrPause();
  void seek(Duration p) => _player.seek(p);
  void setRate(double r) => _player.setRate(r);

  void skipToNextChapter() {
    final nextIdx = currentChapterIndex.value + 1;
    if (nextIdx < _currentChapters.length) {
      changeChapter(nextIdx);
    }
  }

  void skipToPreviousChapter() {
    final prevIdx = currentChapterIndex.value - 1;
    if (prevIdx >= 0) {
      changeChapter(prevIdx);
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _updateSystemState();
  }

  Future<void> changeChapter(int index) async {
    if (index < 0 || index >= _currentChapters.length) return;
    currentChapterIndex.value = index;
    await _player.open(Media(_currentChapters[index].url, httpHeaders: _currentChapters[index].headers));
    _player.play();
  }

  // --- Persistence (History) ---

  Future<void> _saveProgress() async {
    if (currentBook.value == null || _isResuming) return;
    final prefs = await SharedPreferences.getInstance();
    
    List<String> historyStrings = prefs.getStringList('audiobook_history') ?? [];
    List<Map<String, dynamic>> history = historyStrings.map((s) => json.decode(s) as Map<String, dynamic>).toList();

    final bookData = {
      'book': currentBook.value!.toJson(),
      'chapterIndex': currentChapterIndex.value,
      'positionMs': position.value.inMilliseconds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    history.removeWhere((item) => item['book']['audioBookId'] == currentBook.value!.audioBookId);
    history.insert(0, bookData);
    
    if (history.length > 10) history = history.sublist(0, 10);

    await prefs.setStringList('audiobook_history', history.map((e) => json.encode(e)).toList());
  }

  Future<void> saveManualProgress() async {
    await _saveProgress();
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList('audiobook_history') ?? [];
    return history.map((s) => json.decode(s) as Map<String, dynamic>).toList();
  }

  Future<void> removeFromHistory(String audioBookId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> historyStrings = prefs.getStringList('audiobook_history') ?? [];
    historyStrings.removeWhere((s) {
      final data = json.decode(s);
      return data['book']['audioBookId'] == audioBookId;
    });
    await prefs.setStringList('audiobook_history', historyStrings);
  }

  // --- Liked Books ---

  Future<List<Audiobook>> getLikedBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> liked = prefs.getStringList('audiobook_liked') ?? [];
    return liked.map((s) => Audiobook.fromJson(json.decode(s))).toList();
  }

  Future<bool> isBookLiked(String audioBookId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> liked = prefs.getStringList('audiobook_liked') ?? [];
    return liked.any((s) => json.decode(s)['audioBookId'] == audioBookId);
  }

  Future<void> toggleLikeBook(Audiobook book) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> likedStrings = prefs.getStringList('audiobook_liked') ?? [];
    
    final index = likedStrings.indexWhere((s) => json.decode(s)['audioBookId'] == book.audioBookId);
    
    if (index >= 0) {
      likedStrings.removeAt(index);
    } else {
      likedStrings.add(json.encode(book.toJson()));
    }
    
    await prefs.setStringList('audiobook_liked', likedStrings);
  }

  void dispose() {
    for (var s in _subscriptions) { s.cancel(); }
    _player.dispose();
  }
}
