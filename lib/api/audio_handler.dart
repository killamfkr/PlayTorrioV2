import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:rxdart/rxdart.dart';

import 'audiobook_player_service.dart';
import 'music_player_service.dart';
import 'music_service.dart';

enum AudioPlayerType { music, audiobook, video }

class PlayTorrioAudioHandler extends BaseAudioHandler with SeekHandler {
  static const String _browseQueueId = 'playtorrio/queue';
  static const String _browseQueueEmptyId = 'playtorrio/queue_empty';

  final mk.Player _musicPlayer;
  AudioPlayerType _currentType = AudioPlayerType.music;
  dynamic _activePlayer;

  mk.Player? _videoPlayer;
  final List<StreamSubscription<dynamic>> _videoSubscriptions = [];

  final PublishSubject<void> _browseRefresh = PublishSubject<void>();

  PlayTorrioAudioHandler(this._musicPlayer) {
    _activePlayer = _musicPlayer;
    // Bind music player events
    _musicPlayer.stream.position.listen((p) => _updateState());
    _musicPlayer.stream.duration.listen((d) => _updateState());
    _musicPlayer.stream.playing.listen((pl) => _updateState());
    _musicPlayer.stream.buffering.listen((b) => _updateState());
    _musicPlayer.stream.completed.listen((c) => _updateState());

    final msvc = MusicPlayerService();
    msvc.playlist.addListener(_emitBrowseRefresh);
    msvc.currentTrack.addListener(_emitBrowseRefresh);
    syncMusicQueueFromPlaylist();
  }

  void _emitBrowseRefresh() {
    syncMusicQueueFromPlaylist();
    _browseRefresh.add(null);
  }

  MediaItem _mediaItemFromTrack(MusicTrack t) {
    return MediaItem(
      id: t.id,
      album: t.album,
      title: t.title,
      artist: t.artist,
      displayTitle: t.title,
      displaySubtitle: t.artist,
      duration: Duration(seconds: t.duration),
      artUri: t.cover.startsWith('http')
          ? Uri.tryParse(t.cover)
          : Uri.file(t.cover),
    );
  }

  /// Keeps [queue] in sync for Android Auto / MediaSession queue UI.
  void syncMusicQueueFromPlaylist() {
    if (_currentType != AudioPlayerType.music) return;
    final tracks = MusicPlayerService().playlist.value;
    queue.add(tracks.map(_mediaItemFromTrack).toList());
    _updateState();
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
    _browseRefresh.add(null);

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
    syncMusicQueueFromPlaylist();
    _browseRefresh.add(null);
  }

  void setPlayerType(AudioPlayerType type, dynamic player) {
    if (_currentType == AudioPlayerType.video && type != AudioPlayerType.video) {
      _cancelVideoSubscriptions();
    }
    _currentType = type;
    _activePlayer = player;
    _updateState();
    if (type == AudioPlayerType.music) {
      syncMusicQueueFromPlaylist();
    }
    _browseRefresh.add(null);
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

    final svc = MusicPlayerService();
    final hasMedia = svc.currentTrack.value != null;
    final st = _musicPlayer.state;
    // mpv often reports buffering while idle — Android Auto treats that as endless loading.
    final processingState = !hasMedia && !st.playing
        ? AudioProcessingState.idle
        : (st.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready);

    final tracks = svc.playlist.value;
    final cur = svc.currentTrack.value;
    int? qIdx;
    if (cur != null && tracks.isNotEmpty) {
      final i = tracks.indexWhere((t) => t.id == cur.id);
      qIdx = i >= 0 ? i : null;
    }

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
      processingState: processingState,
      playing: st.playing,
      updatePosition: st.position,
      bufferedPosition: st.buffer,
      speed: st.rate,
      queueIndex: qIdx,
    ));
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    switch (parentMediaId) {
      case 'root':
      case '':
        return [
          MediaItem(
            id: _browseQueueId,
            title: 'Music queue',
            playable: false,
            displaySubtitle: 'Current playlist — tap to see songs',
          ),
        ];
      case AudioService.recentRootId:
        final cur = mediaItem.value;
        if (cur != null) return [cur];
        return [];
      case _browseQueueId:
        final tracks = MusicPlayerService().playlist.value;
        if (tracks.isEmpty) {
          return [
            MediaItem(
              id: _browseQueueEmptyId,
              title: 'Queue is empty',
              playable: false,
              displaySubtitle: 'Pick music in PlayTorrio on your phone first',
            ),
          ];
        }
        return tracks.map(_mediaItemFromTrack).toList();
      default:
        return super.getChildren(parentMediaId, options);
    }
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    switch (parentMediaId) {
      case 'root':
      case '':
      case AudioService.recentRootId:
      case _browseQueueId:
        return Rx.merge<Object?>([
          Stream<Object?>.value(null),
          _browseRefresh.map<Object?>((_) => null),
          mediaItem.map<Object?>((MediaItem? _) => null),
        ]).map((_) => <String, dynamic>{}).shareValueSeeded(<String, dynamic>{});
      default:
        return super.subscribeToChildren(parentMediaId);
    }
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (mediaId == _browseQueueId) {
      return MediaItem(
        id: _browseQueueId,
        title: 'Music queue',
        playable: false,
      );
    }
    if (mediaId == _browseQueueEmptyId) {
      return MediaItem(
        id: _browseQueueEmptyId,
        title: 'Queue is empty',
        playable: false,
      );
    }
    final tracks = MusicPlayerService().playlist.value;
    for (final t in tracks) {
      if (t.id == mediaId) return _mediaItemFromTrack(t);
    }
    return null;
  }

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    if (_currentType == AudioPlayerType.video) return;
    if (mediaId == _browseQueueId ||
        mediaId == _browseQueueEmptyId ||
        mediaId.isEmpty) {
      return;
    }
    final tracks = MusicPlayerService().playlist.value;
    final idx = tracks.indexWhere((t) => t.id == mediaId);
    if (idx < 0) return;

    if (AudiobookPlayerService().isPlaying.value) {
      unawaited(AudiobookPlayerService().mediaPlayer.pause());
    }

    setPlayerType(AudioPlayerType.music, _musicPlayer);
    await MusicPlayerService().playTrack(tracks[idx]);
    MusicPlayerService().play();
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
    _browseRefresh.add(null);
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
