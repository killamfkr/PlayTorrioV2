/// VegaMovies — Hindi-English dual audio movies & series.
///
/// Workflow:
///   1. Search by IMDb id (or fallback to title) via /search.php (Typesense
///      proxy). Hits provide a `permalink` to the post page.
///   2. Fetch the post page. Each download button links to nexdrive.pro.
///   3. Fetch each nexdrive page. It exposes 3 mirrors per quality:
///        - fastdl.zip   (G-Direct)
///        - vcloud.zip   (V-Cloud, identical engine to HubCloud)
///        - filebee.xyz  (Filepress)
///      We surface the vcloud.zip URL and let the HubCloud extractor finish
///      it (vcloud uses the same `gamerxyt.com/hubcloud.php` endpoint).
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/fetcher.dart';
import '../utils/id.dart';
import '../utils/resolution.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class VegaMoviesSource extends Source {
  VegaMoviesSource(super.fetcher);

  @override
  String get id => 'vegamovies';
  @override
  String get label => 'VegaMovies';
  @override
  List<String> get contentTypes => const ['movie'];
  @override
  List<CountryCode> get countryCodes => const [
        CountryCode.multi,
        CountryCode.hi,
        CountryCode.en,
      ];
  @override
  String get baseUrl => 'https://vegamovies.market';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final imdbId = await getImdbId(ctx, fetcher, id);
    // Movies only — skip if this is an episode lookup.
    if (imdbId.episode != null) return const [];
    final pageUrls = await _searchByImdb(ctx, imdbId);
    if (pageUrls.isEmpty) return const [];

    final lists = await Future.wait(
        pageUrls.map((u) => _handlePage(ctx, u, imdbId)));
    return lists.expand((e) => e).toList();
  }

  Future<List<Uri>> _searchByImdb(Context ctx, ImdbId imdbId) async {
    final searchUrl = Uri.parse(
        '$baseUrl/search.php?q=${Uri.encodeComponent(imdbId.id)}&page=1');
    final resp = await fetcher.json(ctx, searchUrl,
        FetcherRequestConfig(headers: {'Referer': baseUrl})) as Map<String, dynamic>;

    final hits = (resp['hits'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final out = <Uri>[];
    for (final hit in hits) {
      final doc = hit['document'] as Map<String, dynamic>;
      if (doc['imdb_id'] != imdbId.id) continue;
      final postTitle = doc['post_title'] as String? ?? '';
      // Skip trailer / news posts.
      final lower = postTitle.toLowerCase();
      if (lower.contains('trailer') || lower.contains('coming soon')) continue;

      if (imdbId.season != null) {
        final s = imdbId.season.toString();
        final sPad = s.padLeft(2, '0');
        if (!postTitle.contains('Season $s') &&
            !postTitle.contains('S$s') &&
            !postTitle.contains('S$sPad')) {
          continue;
        }
      } else {
        // For movies, drop posts that look like series.
        if (postTitle.contains('Season ') || RegExp(r'\bS\d{1,2}\b').hasMatch(postTitle)) {
          continue;
        }
      }
      final permalink = doc['permalink'] as String;
      out.add(Uri.parse(permalink).hasScheme
          ? Uri.parse(permalink)
          : Uri.parse(baseUrl).resolve(permalink));
    }
    return out;
  }

  Future<List<SourceResult>> _handlePage(
      Context ctx, Uri pageUrl, ImdbId imdbId) async {
    final html = await fetcher.text(ctx, pageUrl,
        FetcherRequestConfig(headers: {'Referer': baseUrl}));
    final doc = html_parser.parse(html);

    // VegaMovies posts are dual-audio Hindi-English. Tag accordingly.
    final meta = Meta(
      countryCodes: <CountryCode>{
        CountryCode.multi,
        CountryCode.hi,
        CountryCode.en,
      }.toList(),
      referer: pageUrl.toString(),
    );

    // Collect (nexdrive_url, quality_label) pairs to resolve.
    final targets = <_NexTarget>[];

    if (imdbId.episode == null) {
      // Movie OR season pack: take every nexdrive link with its preceding header.
      _collectNexdriveTargets(doc.body, targets);
    } else {
      final epStr = '${imdbId.episode}';
      final epPad = epStr.padLeft(2, '0');
      // Try episode-specific sections first (look for headers containing
      // "Episode N" / "EPISODE N" and gather following anchors until <hr> or
      // next header).
      _collectEpisodeTargets(doc.body, epStr, epPad, targets);
      // If nothing found, fall back to season-pack links.
      if (targets.isEmpty) {
        _collectNexdriveTargets(doc.body, targets);
      }
    }

    final lists = await Future.wait(targets.map(
        (t) => _resolveNexdrive(ctx, t.url, t.label, pageUrl, meta)));
    return lists.expand((e) => e).toList();
  }

  void _collectNexdriveTargets(
      dynamic root, List<_NexTarget> out) {
    if (root == null) return;
    for (final a in root.querySelectorAll('a[href*="nexdrive."]')) {
      final href = a.attributes['href'];
      if (href == null) continue;
      // Try to find the nearest preceding header for a quality label.
      String label = '';
      var p = a.parent;
      while (p != null) {
        var sib = p.previousElementSibling;
        while (sib != null) {
          final tag = sib.localName ?? '';
          if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
            label = sib.text.trim();
            break;
          }
          sib = sib.previousElementSibling;
        }
        if (label.isNotEmpty) break;
        p = p.parent;
      }
      out.add(_NexTarget(Uri.parse(href), label));
    }
  }

  void _collectEpisodeTargets(
      dynamic root, String epStr, String epPad, List<_NexTarget> out) {
    if (root == null) return;
    final seen = <String>{};
    final headers = root.querySelectorAll('h1, h2, h3, h4, h5, h6');
    for (final h in headers) {
      final t = h.text;
      final hasEp = t.contains('Episode $epStr') ||
          t.contains('Episode $epPad') ||
          t.contains('EPISODE $epStr') ||
          t.contains('EPISODE $epPad') ||
          t.contains('EPiSODE $epStr') ||
          t.contains('EPiSODE $epPad');
      if (!hasEp) continue;
      final label = h.text.trim();
      var n = h.nextElementSibling;
      while (n != null) {
        final tag = n.localName ?? '';
        if (RegExp(r'^h[1-6]$').hasMatch(tag) || tag == 'hr') break;
        for (final a in n.querySelectorAll('a[href*="nexdrive."]')) {
          final href = a.attributes['href'];
          if (href == null || !seen.add(href)) continue;
          out.add(_NexTarget(Uri.parse(href), label));
        }
        n = n.nextElementSibling;
      }
    }
  }

  Future<List<SourceResult>> _resolveNexdrive(
      Context ctx, Uri nexUrl, String label, Uri refererUrl, Meta meta) async {
    try {
      final html = await fetcher.text(ctx, nexUrl,
          FetcherRequestConfig(headers: {'Referer': refererUrl.toString()}));
      // Pull all vcloud.zip mirrors. Prefer those — they map to the HubCloud
      // engine. fastdl/filebee are skipped (no standalone extractors yet).
      final out = <SourceResult>[];
      final seen = <String>{};
      for (final m
          in RegExp(r'href="(https?://[^"]*vcloud[^"]+)"').allMatches(html)) {
        final href = m.group(1)!;
        if (!seen.add(href)) continue;
        final m2 = meta.clone();
        m2.referer = nexUrl.toString();
        // Tag with quality from header text if available.
        final h = findHeight(label);
        if (h != null) m2.height = h;
        if (label.isNotEmpty) m2.title = label;
        out.add(SourceResult(url: Uri.parse(href), meta: m2));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

class _NexTarget {
  final Uri url;
  final String label;
  _NexTarget(this.url, this.label);
}
