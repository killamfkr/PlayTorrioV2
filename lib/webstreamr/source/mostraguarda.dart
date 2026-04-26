/// Port of webstreamr/src/source/MostraGuarda.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class MostraGuardaSource extends Source {
  MostraGuardaSource(super.fetcher);

  @override
  String get id => 'mostraguarda';
  @override
  String get label => 'MostraGuarda';
  @override
  List<String> get contentTypes => const ['movie'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.it];
  @override
  String get baseUrl => 'https://mostraguarda.stream';

  @override
  Future<List<SourceResult>> handleInternal(
      Context ctx, String type, Id id) async {
    final imdbId = await getImdbId(ctx, fetcher, id);
    final pageUrl = Uri.parse('$baseUrl/movie/${imdbId.id}');
    final html = await fetcher.text(ctx, pageUrl);
    final doc = html_parser.parse(html);

    final out = <SourceResult>[];
    for (final el in doc.querySelectorAll('[data-link]')) {
      final raw = el.attributes['data-link'];
      if (raw == null || raw.isEmpty) continue;
      final fixed = raw.replaceFirst(RegExp(r'^(https:)?//'), 'https://');
      final u = Uri.parse(fixed);
      if (u.host.contains('mostraguarda')) continue;
      out.add(SourceResult(
        url: u,
        meta: Meta(countryCodes: const [CountryCode.it], referer: baseUrl),
      ));
    }
    return out;
  }
}
