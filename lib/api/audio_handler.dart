import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'audiobook_player_service.dart';
import 'music_player_service.dart';

enum AudioPlayerType { music, audiobook, video }

class PlayTorrioAudioHandler extends BaseAudioHandler with SeekHandler {
  final mk.Player _musicPlayer;
  AudioPlayerType _currentType = AudioPlayerType.music;
  dynamic _activePlayer;
  /// Built-in video player currently bound to [mediaItem] / Android Auto.
  mk.Player? _attachedVideoPlayer;
  final List<StreamSubscription<dynamic>> _videoSubs = [];

  PlayTorrioAudioHandler(this._musicPlayer) {
    _activePlayer = _musicPlayer;
    // Bind music player events
    _musicPlayer.stream.position.listen((p) => _updateState());
    _musicPlayer.stream.duration.listen((d) => _updateState());
    _musicPlayer.stream.playing.listen((pl) => _updateState());
    _musicPlayer.stream.buffering.listen((b) => _updateState());
    _musicPlayer.stream.completed.listen((c) => _updateState());
  }

  void setPlayerType(AudioPlayerType type, dynamic player) {
    if (_currentType == AudioPlayerType.video &&
        type != AudioPlayerType.video) {
      for (final s in _videoSubs) {
        s.cancel();
      }
      _videoSubs.clear();
      _attachedVideoPlayer = null;
    }
    _currentType = type;
    _activePlayer = player;
    _updateState();
  }

  /// Registers this [Player] with the system media session while built-in
  /// video is active (notification / lock screen / BT controls).
  void attachVideoPlayer(
    mk.Player p, {
    required String title,
    Uri? artUri,
    String? displaySubtitle,
    String? album,
    bool? isLive,
    Map<String, dynamic>? extras,
  }) {
    for (final s in _videoSubs) {
      s.cancel();
    }
    _videoSubs.clear();

    setPlayerType(AudioPlayerType.video, p);
    _attachedVideoPlayer = p;

    mediaItem.add(MediaItem(
      id: 'playtorrio_builtin_video_${p.hashCode}',
      title: title,
      displayTitle: title,
      displaySubtitle: displaySubtitle,
      artist: 'PlayTorrio',
      album: album ?? 'Video',
      artUri: artUri,
      isLive: isLive,
      extras: extras,
    ));

    void pushVideoState() {
      if (_currentType != AudioPlayerType.video || _activePlayer != p) return;
      final st = p.state;
      playbackState.add(PlaybackState(
        controls: [
          MediaControl.rewind,
          st.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.playPause,
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.stop,
          MediaAction.rewind,
          MediaAction.fastForward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: st.buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: st.playing,
        updatePosition: st.position,
        bufferedPosition: st.buffer,
        speed: st.rate,
      ));
    }

    void onDuration(Duration d) {
      final cur = mediaItem.value;
      if (cur != null && d > Duration.zero && cur.duration != d) {
        mediaItem.add(cur.copyWith(duration: d));
      }
      pushVideoState();
    }

    _videoSubs.addAll([
      p.stream.position.listen((_) => pushVideoState()),
      p.stream.duration.listen(onDuration),
      p.stream.playing.listen((_) => pushVideoState()),
      p.stream.buffering.listen((_) => pushVideoState()),
      p.stream.buffer.listen((_) => pushVideoState()),
    ]);
    pushVideoState();
  }

  /// If [onlyPlayer] is set, only detach when that same [mk.Player] is active
  /// (avoids [Navigator.pushReplacement] tearing down the new session).
  void detachVideoPlayer([mk.Player? onlyPlayer]) {
    if (onlyPlayer != null &&
        (_attachedVideoPlayer == null ||
            !identical(_attachedVideoPlayer, onlyPlayer))) {
      return;
    }
    for (final s in _videoSubs) {
      s.cancel();
    }
    _videoSubs.clear();
    _attachedVideoPlayer = null;
    if (_currentType != AudioPlayerType.video) return;
    setPlayerType(AudioPlayerType.music, _musicPlayer);
  }

  void _updateState() {
    if (_currentType != AudioPlayerType.music) return;

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _musicPlayer.state.playing ? MediaControl.pause : MediaControl.play,
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
      processingState: _musicPlayer.state.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: _musicPlayer.state.playing,
      updatePosition: _musicPlayer.state.position,
      bufferedPosition: _musicPlayer.state.buffer, // Media-kit uses .buffer not .position for buffering
      speed: _musicPlayer.state.rate,
    ));
  }

  @override
  Future<void> play() async {
    if (_currentType == AudioPlayerType.music) {
      MusicPlayerService().play();
    } else {
      await (_activePlayer as mk.Player).play();
    }
  }

  @override
  Future<void> pause() async {
    if (_currentType == AudioPlayerType.music) {
      MusicPlayerService().pause();
    } else {
      await (_activePlayer as mk.Player).pause();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_currentType == AudioPlayerType.music) {
      await _musicPlayer.seek(position);
    } else {
      await (_activePlayer as mk.Player).seek(position);
    }
  }

  Future<void> _seekVideoBy(Duration delta) async {
    final p = _activePlayer as mk.Player;
    var pos = p.state.position + delta;
    if (pos < Duration.zero) pos = Duration.zero;
    final dur = p.state.duration;
    if (dur > Duration.zero && pos > dur) pos = dur;
    await p.seek(pos);
  }

  @override
  Future<void> skipToNext() async {
    if (_currentType == AudioPlayerType.music) {
      MusicPlayerService().next();
    } else if (_currentType == AudioPlayerType.video) {
      await _seekVideoBy(const Duration(seconds: 30));
    } else {
      AudiobookPlayerService().skipToNextChapter();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentType == AudioPlayerType.music) {
      MusicPlayerService().previous();
    } else if (_currentType == AudioPlayerType.video) {
      await _seekVideoBy(const Duration(seconds: -30));
    } else {
      AudiobookPlayerService().skipToPreviousChapter();
    }
  }

  void updateState(PlaybackState state) {
    if (_currentType == AudioPlayerType.audiobook) {
      playbackState.add(state);
    }
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
  }

  @override
  Future<void> stop() async {
    if (_currentType == AudioPlayerType.video) {
      await (_activePlayer as mk.Player).pause();
      detachVideoPlayer(_attachedVideoPlayer);
      return super.stop();
    }
    if (_currentType == AudioPlayerType.music) {
      await _musicPlayer.stop();
    } else {
      await (_activePlayer as mk.Player).stop();
    }
    return super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    await super.onTaskRemoved();
  }
}
