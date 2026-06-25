import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'audiobook_player_service.dart';
import 'music_player_service.dart';

enum AudioPlayerType { music, audiobook }

class PlayTorrioAudioHandler extends BaseAudioHandler with SeekHandler {
  final mk.Player _musicPlayer;
  AudioPlayerType _currentType = AudioPlayerType.music;
  dynamic _activePlayer;
  final List<StreamSubscription<dynamic>> _audiobookSubs = [];

  PlayTorrioAudioHandler(this._musicPlayer) {
    _activePlayer = _musicPlayer;
    _musicPlayer.stream.position.listen((_) => _updateMusicState());
    _musicPlayer.stream.playing.listen((_) => _updateMusicState());
    _musicPlayer.stream.buffering.listen((_) => _updateMusicState());
  }

  void setPlayerType(AudioPlayerType type, dynamic player) {
    for (final s in _audiobookSubs) {
      s.cancel();
    }
    _audiobookSubs.clear();

    _currentType = type;
    _activePlayer = player;

    if (type == AudioPlayerType.audiobook && player is mk.Player) {
      void pushAudiobookState() {
        if (_currentType != AudioPlayerType.audiobook) return;
        final st = player.state;
        playbackState.add(PlaybackState(
          controls: [
            MediaControl.skipToPrevious,
            st.playing ? MediaControl.pause : MediaControl.play,
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
          processingState: st.buffering
              ? AudioProcessingState.buffering
              : AudioProcessingState.ready,
          playing: st.playing,
          updatePosition: st.position,
          bufferedPosition: st.buffer,
          speed: st.rate,
        ));
      }

      _audiobookSubs.addAll([
        player.stream.position.listen((_) => pushAudiobookState()),
        player.stream.duration.listen((d) {
          final cur = mediaItem.value;
          if (cur != null && d > Duration.zero && cur.duration != d) {
            mediaItem.add(cur.copyWith(duration: d));
          }
          pushAudiobookState();
        }),
        player.stream.playing.listen((_) => pushAudiobookState()),
        player.stream.buffering.listen((_) => pushAudiobookState()),
        player.stream.buffer.listen((_) => pushAudiobookState()),
      ]);
      pushAudiobookState();
      return;
    }

    if (type == AudioPlayerType.music) {
      _updateMusicState();
    }
  }

  void _updateMusicState() {
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

  @override
  Future<void> skipToNext() async {
    if (_currentType == AudioPlayerType.music) {
      MusicPlayerService().next();
    } else {
      AudiobookPlayerService().skipToNextChapter();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentType == AudioPlayerType.music) {
      MusicPlayerService().previous();
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
    if (_currentType == AudioPlayerType.audiobook) {
      final p = _activePlayer as mk.Player?;
      if (p != null) {
        playbackState.add(PlaybackState(
          controls: [
            MediaControl.skipToPrevious,
            p.state.playing ? MediaControl.pause : MediaControl.play,
            MediaControl.stop,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.playPause,
            MediaAction.stop,
            MediaAction.skipToNext,
            MediaAction.skipToPrevious,
          },
          androidCompactActionIndices: const [0, 1, 3],
          processingState: p.state.buffering
              ? AudioProcessingState.buffering
              : AudioProcessingState.ready,
          playing: p.state.playing,
          updatePosition: p.state.position,
          bufferedPosition: p.state.buffer,
          speed: p.state.rate,
        ));
      }
    }
  }

  @override
  Future<void> stop() async {
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
