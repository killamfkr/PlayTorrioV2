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

  mk.Player? _videoPlayer;
  final List<StreamSubscription<dynamic>> _videoSubscriptions = [];

  PlayTorrioAudioHandler(this._musicPlayer) {
    _activePlayer = _musicPlayer;
    // Bind music player events
    _musicPlayer.stream.position.listen((p) => _updateState());
    _musicPlayer.stream.duration.listen((d) => _updateState());
    _musicPlayer.stream.playing.listen((pl) => _updateState());
    _musicPlayer.stream.buffering.listen((b) => _updateState());
    _musicPlayer.stream.completed.listen((c) => _updateState());
  }

  void _cancelVideoSubscriptions() {
    for (final s in _videoSubscriptions) {
      s.cancel();
    }
    _videoSubscriptions.clear();
    _videoPlayer = null;
  }

  /// Built-in video player (background-capable): media notification play/pause/stop.
  void attachBuiltInVideoPlayer(mk.Player player, String title) {
    _cancelVideoSubscriptions();

    if (MusicPlayerService().isPlaying.value) {
      MusicPlayerService().pause();
    }
    final ab = AudiobookPlayerService();
    if (ab.isPlaying.value) {
      unawaited(ab.mediaPlayer.pause());
    }

    _currentType = AudioPlayerType.video;
    _videoPlayer = player;
    _activePlayer = player;

    mediaItem.add(MediaItem(
      id: 'playtorrio-builtin-video',
      title: title,
      album: 'PlayTorrio',
      displaySubtitle: 'Video',
    ));

    void tick(_) => _updateVideoState();
    _videoSubscriptions.add(player.stream.position.listen(tick));
    _videoSubscriptions.add(player.stream.duration.listen(tick));
    _videoSubscriptions.add(player.stream.playing.listen(tick));
    _videoSubscriptions.add(player.stream.buffering.listen(tick));
    _videoSubscriptions.add(player.stream.completed.listen(tick));

    _updateVideoState();
  }

  void detachBuiltInVideoPlayer() {
    _cancelVideoSubscriptions();

    final ab = AudiobookPlayerService();
    if (ab.currentBook.value != null) {
      _currentType = AudioPlayerType.audiobook;
      _activePlayer = ab.mediaPlayer;
      ab.refreshPlaybackStateOnHandler();
    } else {
      _currentType = AudioPlayerType.music;
      _activePlayer = _musicPlayer;
      _updateState();
    }
  }

  void setPlayerType(AudioPlayerType type, dynamic player) {
    if (_currentType == AudioPlayerType.video && type != AudioPlayerType.video) {
      _cancelVideoSubscriptions();
    }
    _currentType = type;
    _activePlayer = player;
    _updateState();
  }

  void _updateVideoState() {
    if (_currentType != AudioPlayerType.video || _videoPlayer == null) return;
    final st = _videoPlayer!.state;
    playbackState.add(PlaybackState(
      controls: [
        st.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.playPause,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1],
      processingState:
          st.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: st.playing,
      updatePosition: st.position,
      bufferedPosition: st.buffer,
      speed: st.rate,
    ));
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
      processingState: _musicPlayer.state.buffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      playing: _musicPlayer.state.playing,
      updatePosition: _musicPlayer.state.position,
      bufferedPosition: _musicPlayer.state.buffer,
      speed: _musicPlayer.state.rate,
    ));
  }

  @override
  Future<void> play() async {
    if (_currentType == AudioPlayerType.music) {
      MusicPlayerService().play();
    } else {
      await _activePlayer.play();
    }
  }

  @override
  Future<void> pause() async {
    if (_currentType == AudioPlayerType.music) {
      MusicPlayerService().pause();
    } else {
      await _activePlayer.pause();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (_currentType == AudioPlayerType.music) {
      await _musicPlayer.seek(position);
    } else {
      await _activePlayer.seek(position);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_currentType == AudioPlayerType.music) {
      MusicPlayerService().next();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentType == AudioPlayerType.music) {
      MusicPlayerService().previous();
    }
  }

  void updateState(PlaybackState state) {
    if (_currentType != AudioPlayerType.audiobook) return;
    playbackState.add(state);
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
  }

  @override
  Future<void> stop() async {
    if (_currentType == AudioPlayerType.video) {
      await _videoPlayer?.pause();
      detachBuiltInVideoPlayer();
      return super.stop();
    }
    if (_currentType == AudioPlayerType.music) {
      await _musicPlayer.stop();
    } else {
      await _activePlayer.stop();
    }
    return super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    await super.onTaskRemoved();
  }
}
