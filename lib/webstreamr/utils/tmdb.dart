/// Port of webstreamr/src/utils/tmdb.ts. Prefers a TMDB v4 access token in
/// `WsEnv.set('TMDB_ACCESS_TOKEN', ...)`; falls back to a bundled v3 api_key.
library;

import '../errors.dart';
import '../types.dart';
import 'env.dart';
import 'fetcher.dart';
import 'id.dart';
import 'semaphore.dart';

/// Bundled v3 fallback (same key used elsewhere in the app for metadata).
const _kFallbackV3ApiKey = 'c3515fdc674ea2bd7b514f4bc3616a4a';

final _mutexes = <String, Mutex>{};

Future<dynamic> _tmdbFetch(
    Context ctx, Fetcher fetcher, String path,
    [Map<String, String?>? searchParams]) async {
  final v4 = WsEnv.get('TMDB_ACCESS_TOKEN');
  final headers = <String, String>{'Content-Type': 'application/json'};
  final qp = <String, String>{};
  if (v4 != null && v4.isNotEmpty) {
    headers['Authorization'] = 'Bearer $v4';
  } else {
    qp['api_key'] = _kFallbackV3ApiKey;
  }
  final cfg = FetcherRequestConfig(headers: headers, queueLimit: 50);
  searchParams?.forEach((k, v) {
    if (v != null && v.isNotEmpty) qp[k] = v;
  });
  final url =
      Uri.parse('https://api.themoviedb.org/3$path').replace(queryParameters: qp);
  final mutex = _mutexes.putIfAbsent(url.toString(), () => Mutex());
  final out = await mutex.runExclusive(() => fetcher.json(ctx, url, cfg));
  return out;
}

final _imdbToTmdb = <String, int>{};
Future<TmdbId> getTmdbIdFromImdbId(
    Context ctx, Fetcher fetcher, ImdbId imdbId) async {
  // Manual mismatch fixes (copied verbatim from upstream).
  if (imdbId.id == 'tt13207736' && imdbId.season == 2) {
    return TmdbId(225634, imdbId.season! - 1, imdbId.episode);
  }
  if (imdbId.id == 'tt13207736' && imdbId.season == 3) {
    return TmdbId(286801, imdbId.season! - 2, imdbId.episode);
  }

  if (_imdbToTmdb.containsKey(imdbId.id)) {
    return TmdbId(_imdbToTmdb[imdbId.id]!, imdbId.season, imdbId.episode);
  }
  final resp = await _tmdbFetch(
      ctx, fetcher, '/find/${imdbId.id}', {'external_source': 'imdb_id'});
  final data = resp as Map<String, dynamic>;
  final list = imdbId.season != null
      ? (data['tv_results'] as List)
      : (data['movie_results'] as List);
  if (list.isEmpty) {
    throw NotFoundError('Could not get TMDB ID of IMDb ID "${imdbId.id}"');
  }
  final id = (list.first as Map)['id'] as int;
  _imdbToTmdb[imdbId.id] = id;
  return TmdbId(id, imdbId.season, imdbId.episode);
}

final _tmdbToImdb = <int, String>{};
Future<ImdbId> getImdbIdFromTmdbId(
    Context ctx, Fetcher fetcher, TmdbId tmdbId) async {
  if (_tmdbToImdb.containsKey(tmdbId.id)) {
    return ImdbId(_tmdbToImdb[tmdbId.id]!, tmdbId.season, tmdbId.episode);
  }
  final type = tmdbId.season != null ? 'tv' : 'movie';
  final resp = await _tmdbFetch(
      ctx, fetcher, '/$type/${tmdbId.id}/external_ids') as Map<String, dynamic>;
  final id = resp['imdb_id'] as String;
  _tmdbToImdb[tmdbId.id] = id;
  return ImdbId(id, tmdbId.season, tmdbId.episode);
}

Future<ImdbId> getImdbId(Context ctx, Fetcher fetcher, Id id) async {
  if (id is TmdbId) return getImdbIdFromTmdbId(ctx, fetcher, id);
  return id as ImdbId;
}

Future<TmdbId> getTmdbId(Context ctx, Fetcher fetcher, Id id) async {
  if (id is ImdbId) return getTmdbIdFromImdbId(ctx, fetcher, id);
  return id as TmdbId;
}

/// Returns `[name, year, originalName]`.
Future<List<dynamic>> getTmdbNameAndYear(
    Context ctx, Fetcher fetcher, TmdbId tmdbId,
    [String? language]) async {
  if (tmdbId.season != null) {
    final d = await _tmdbFetch(
        ctx, fetcher, '/tv/${tmdbId.id}', {'language': language}) as Map<String, dynamic>;
    final name = d['name'] as String;
    final year = DateTime.tryParse(d['first_air_date'] as String? ?? '')?.year ?? 0;
    final orig = d['original_name'] as String? ?? name;
    return [name, year, orig];
  }
  final d = await _tmdbFetch(
      ctx, fetcher, '/movie/${tmdbId.id}', {'language': language}) as Map<String, dynamic>;
  final title = d['title'] as String;
  final year = DateTime.tryParse(d['release_date'] as String? ?? '')?.year ?? 0;
  final orig = d['original_title'] as String? ?? title;
  return [title, year, orig];
}
