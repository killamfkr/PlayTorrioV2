import 'audiobook_service.dart';
import 'torrent_stream_service.dart';

/// Resolves torrent file indices to HTTP stream URLs for magnet audiobooks.
class AudiobookMagnetResolver {
  static Future<List<AudiobookChapter>> resolvePlaybackChapters(
    String magnetLink,
    List<AudiobookChapter> raw,
  ) async {
    final torrent = TorrentStreamService();
    final started = await torrent.start();
    if (!started) {
      throw Exception('Torrent engine did not start');
    }
    final out = <AudiobookChapter>[];
    for (final ch in raw) {
      final idx = ch.torrentFileIndex;
      if (idx == null) {
        throw Exception('Missing torrent file index for "${ch.title}"');
      }
      final url = await torrent.streamAudiobookFile(magnetLink, idx);
      if (url == null || url.isEmpty) {
        throw Exception('Could not stream torrent file: ${ch.title}');
      }
      out.add(AudiobookChapter(
        title: ch.title,
        url: url,
        headers: ch.headers,
      ));
    }
    return out;
  }
}
