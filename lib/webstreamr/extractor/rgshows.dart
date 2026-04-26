/// Port of webstreamr/src/extractor/RgShows.ts
library;

import '../errors.dart';
import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/height.dart';
import 'extractor.dart';

class RgShows extends Extractor {
  RgShows(super.fetcher);

  @override
  String get id => 'rgshows';
  @override
  String get label => 'RgShows';
  @override
  Duration get ttl => const Duration(hours: 3);

  @override
  bool supports(Context ctx, Uri url) => url.host.contains('rgshows');

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {
      'Referer': 'https://www.rgshows.ru/',
      'Origin': 'https://www.rgshows.ru',
      'User-Agent': 'Mozilla',
    };
    final data = await fetcher.json(
        ctx, url, FetcherRequestConfig(headers: headers)) as Map<String, dynamic>;
    final streamUrl = Uri.parse(
        (data['stream'] as Map<String, dynamic>)['url'] as String);
    if (streamUrl.host.contains('vidzee')) {
      throw BlockedError(url, BlockedReason.unknown, const {});
    }
    final isMp4 = streamUrl.toString().contains('mp4');
    final isHls = streamUrl.toString().contains('m3u8') ||
        streamUrl.toString().contains('txt');
    final out = meta.clone();
    if (isHls) {
      out.height ??= await guessHeightFromPlaylist(
          ctx, fetcher, streamUrl, FetcherRequestConfig(headers: headers));
    }
    return [
      InternalUrlResult(
        url: streamUrl,
        format: isMp4 ? Format.mp4 : (isHls ? Format.hls : Format.unknown),
        meta: out,
        requestHeaders: headers,
      ),
    ];
  }
}
