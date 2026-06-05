/// Port of webstreamr/src/source/VerHdLink.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class VerHdLinkSource extends Source {
  VerHdLinkSource(super.fetcher);

  @override
  String get id => 'verhdlink';
  @override
  String get label => 'VerHdLink';
  @override
  List<String> get contentTypes => const ['movie'];
  @override
  List<CountryCode> get countryCodes =>
      const [CountryCode.es, CountryCode.mx];
  @override
  String get baseUrl => 'https://verhdlink.cam';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final imdbId = await getImdbId(ctx, fetcher, id);
    final pageUrl = Uri.parse('$baseUrl/movie/${imdbId.id}');
    final html = await fetcher.text(ctx, pageUrl);
    final doc = html_parser.parse(html);

    final out = <SourceResult>[];
    for (final el in doc.querySelectorAll('._player-mirrors')) {
      final classes = el.classes;
      List<CountryCode> ccs;
      if (classes.contains('latino')) {
        ccs = const [CountryCode.mx];
      } else if (classes.contains('castellano')) {
        ccs = const [CountryCode.es];
      } else {
        continue;
      }
      for (final dl in el.querySelectorAll('[data-link]')) {
        final raw = dl.attributes['data-link'];
        if (raw == null || raw.isEmpty) continue;
        final fixed = raw.replaceFirst(RegExp(r'^(https:)?//'), 'https://');
        final u = Uri.parse(fixed);
        if (u.host.contains('verhdlink')) continue;
        out.add(SourceResult(
          url: u,
          meta: Meta(countryCodes: ccs, referer: baseUrl),
        ));
      }
    }
    return out;
  }
}
