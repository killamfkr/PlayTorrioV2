import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'music_service.dart';
import 'music_storage_service.dart';
import 'audio_handler.dart';
import 'lyrics_service.dart';

class MusicPlayerService {
  static final MusicPlayerService _instance = MusicPlayerService._internal();
  factory MusicPlayerService() => _instance;
  MusicPlayerService._internal();

  final Player _player = Player();
  final MusicService _musicService = MusicService();
  final MusicStorageService _storageService = MusicStorageService();
  PlayTorrioAudioHandler? _handler;
  final LyricsService _lyricsService = LyricsService();

  Player get player => _player;

  void setHandler(BaseAudioHandler handler) {
    _handler = handler as PlayTorrioAudioHandler;
  }

  final ValueNotifier<MusicTrack?> currentTrack = ValueNotifier<MusicTrack?>(null);
  final ValueNotifier<List<MusicTrack>> playlist = ValueNotifier<List<MusicTrack>>([]);
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<bool> isBuffering = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isShuffleEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<PlaylistMode> loopMode = ValueNotifier<PlaylistMode>(PlaylistMode.none);
  final ValueNotifier<bool> isFullScreenVisible = ValueNotifier<bool>(false);
  final ValueNotifier<List<LyricLine>?> lyrics = ValueNotifier<List<LyricLine>?>(null);
  final ValueNotifier<Widget?> bottomWidget = ValueNotifier<Widget?>(null);

  int _currentIndex = -1;
  bool _initialized = false;
  // ignore: unused_field
  bool _isManuallyPaused = false;
  bool _isLoadingTrack = false;
  final Set<String> _shufflePlayedIds = {};
  final Random _random = Random();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    
    // Configure audio session
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Listen for interruptions (Phone calls, other apps starting media)
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            // Optional: Lower volume
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            pause();
            break;
        }
      }
    });

    // Listen for "becoming noisy" (Headphones unplugged)
    session.becomingNoisyEventStream.listen((_) => pause());

    // Initialize storage notifiers
    await _storageService.init();

    // Listen to player state streams
    _player.stream.playing.listen((p) {
      isPlaying.value = p;
      // Request audio focus when starting to play
      if (p) {
        AudioSession.instance.then((s) => s.setActive(true));
      }
    });
    _player.stream.buffering.listen((b) => isBuffering.value = b);
    _player.stream.position.listen((p) => position.value = p);
    _player.stream.duration.listen((d) => duration.value = d);
    _player.stream.playlistMode.listen((m) => loopMode.value = m);

    _player.stream.completed.listen((completed) {
      if (completed && !_isLoadingTrack) {
        next();
      }
    });
  }

  Future<void> playTrack(MusicTrack track, {List<MusicTrack>? newPlaylist}) async {
    debugPrint('MusicPlayerService: Preparing to play: ${track.title} by ${track.artist}');
    
    _isLoadingTrack = true;
    try {
      // 0. Set session active immediately
      final session = await AudioSession.instance;
      await session.setActive(true);

      await _player.stop();

      if (newPlaylist != null) {
        playlist.value = newPlaylist;
        _currentIndex = newPlaylist.indexWhere((t) => t.id == track.id);
        // Reset shuffle tracking for new playlist
        _shufflePlayedIds.clear();
      }

      // Mark this track as played for shuffle
      if (isShuffleEnabled.value) {
        _shufflePlayedIds.add(track.id);
      }

      currentTrack.value = track;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      _isManuallyPaused = false;
      lyrics.value = null;

      // Update notification metadata
      _handler?.updateMediaItem(MediaItem(
        id: track.id,
        album: track.album,
        title: track.title,
        artist: track.artist,
        displayTitle: track.title,
        displaySubtitle: track.artist,
        duration: Duration(seconds: track.duration),
        artUri: track.cover.startsWith('http') 
            ? Uri.tryParse(track.cover) 
            : Uri.file(track.cover),
      ));

      _fetchLyricsForTrack(track);

      // 1. Local Offline Playback
      if (track.localPath != null) {
        final file = File(track.localPath!);
        if (await file.exists()) {
          debugPrint('MusicPlayerService: Playing from local storage');
          await _player.open(Media(track.localPath!));
          _prefetchNext();
          return;
        }
      }

      // 2. YouTube Match
      final videoId = await _musicService.getYoutubeVideoId(track.title, track.artist);
      if (videoId == null) {
        debugPrint('MusicPlayerService: No YouTube match');
        return;
      }

      // 3. Manifest
      final manifest = await _musicService.getYoutubeManifest(videoId);
      if (manifest == null) {
        debugPrint('MusicPlayerService: Failed manifest');
        return;
      }

      // SELECT HIGHEST BITRATE MANUALLY
      final audioStreams = manifest.audioOnly.toList();
      audioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      final streamUri = audioStreams.first.url;

      await _player.open(Media(streamUri.toString()));
      _prefetchNext();
      
    } catch (e) {
      debugPrint('MusicPlayerService: Error playing track: $e');
    } finally {
      Future.delayed(const Duration(milliseconds: 1500), () {
        _isLoadingTrack = false;
      });
    }
  }

  void _fetchLyricsForTrack(MusicTrack track) async {
    try {
      final localLyrics = await _lyricsService.getLocalLyrics(track);
      if (localLyrics != null) {
        lyrics.value = localLyrics;
        return;
      }

      final onlineLyrics = await _lyricsService.getSyncedLyrics(
        trackName: track.title,
        artistName: track.artist,
        albumName: track.album,
        durationSeconds: track.duration,
      );
      
      if (onlineLyrics != null) {
        lyrics.value = onlineLyrics;
      } else {
        lyrics.value = []; // Explicitly mark as not found
      }
    } catch (e) {
      debugPrint('MusicPlayerService: Error fetching lyrics: $e');
      lyrics.value = []; // Mark as not found on error too
    }
  }

  void _prefetchNext() async {
    if (playlist.value.isEmpty || _currentIndex == -1) return;
    final nextIndex = (_currentIndex + 1) % playlist.value.length;
    final nextTrack = playlist.value[nextIndex];
    await _musicService.getYoutubeVideoId(nextTrack.title, nextTrack.artist);
  }

  void play() => _player.play();
  void pause() => _player.pause();
  void togglePlay() => _player.playOrPause();

  Future<void> stop() async {
    await _player.stop();
    currentTrack.value = null;
    playlist.value = [];
    _currentIndex = -1;
    isPlaying.value = false;
    _handler?.stop();
  }

  void toggleShuffle() async {
    isShuffleEnabled.value = !isShuffleEnabled.value;
    _shufflePlayedIds.clear();
    // Mark current song as played so it won't be picked next
    if (isShuffleEnabled.value && currentTrack.value != null) {
      _shufflePlayedIds.add(currentTrack.value!.id);
    }
  }

  void toggleLoop() async {
    final modes = [PlaylistMode.none, PlaylistMode.loop, PlaylistMode.single];
    final nextIndex = (modes.indexOf(_player.state.playlistMode) + 1) % modes.length;
    await _player.setPlaylistMode(modes[nextIndex]);
  }

  void seek(Duration pos) => _player.seek(pos);

  void next() {
    if (playlist.value.isEmpty) return;

    if (isShuffleEnabled.value) {
      // Build list of unplayed indices, excluding the current track
      final unplayed = <int>[];
      for (int i = 0; i < playlist.value.length; i++) {
        if (!_shufflePlayedIds.contains(playlist.value[i].id)) {
          unplayed.add(i);
        }
      }

      if (unplayed.isEmpty) {
        // All songs have been played — stop playback
        pause();
        return;
      }

      final nextIndex = unplayed[_random.nextInt(unplayed.length)];
      _currentIndex = nextIndex;
      _shufflePlayedIds.add(playlist.value[nextIndex].id);
      playTrack(playlist.value[nextIndex]);
    } else {
      _currentIndex = (_currentIndex + 1) % playlist.value.length;
      playTrack(playlist.value[_currentIndex]);
    }
  }

  void previous() {
    if (playlist.value.isEmpty) return;
    _currentIndex = (_currentIndex - 1) % playlist.value.length;
    if (_currentIndex < 0) _currentIndex = playlist.value.length - 1;
    playTrack(playlist.value[_currentIndex]);
  }

  /// Built-in video (background playback): lock screen / shade controls via [AudioService].
  void attachBuiltInVideoForNotifications(Player player, String title) {
    _handler?.attachBuiltInVideoPlayer(player, title);
  }

  void detachBuiltInVideoFromNotifications() {
    _handler?.detachBuiltInVideoPlayer();
  }

  void dispose() {
    _player.dispose();
    _musicService.dispose();
  }
}
