/// Port of webstreamr/src/utils/height.ts
library;

import 'dart:math' as math;

import '../types.dart';
import 'fetcher.dart';

Future<int?> guessHeightFromPlaylist(
    Context ctx, Fetcher fetcher, Uri playlistUrl,
    [FetcherRequestConfig? cfg]) async {
  final m3u8 = await fetcher.text(ctx, playlistUrl, cfg);
  final heights = RegExp(r'\d+x(\d+)|(\d+)p')
      .allMatches(m3u8)
      .map((m) => m.group(1) ?? m.group(2))
      .whereType<String>()
      .map(int.parse)
      .toList();
  if (heights.isEmpty) return null;
  return heights.reduce(math.max);
}
