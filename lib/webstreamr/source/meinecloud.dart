/// Port of webstreamr/src/source/MeineCloud.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../types.dart';
import '../utils/id.dart';
import '../utils/tmdb.dart';
import 'source.dart';

class MeineCloudSource extends Source {
  MeineCloudSource(super.fetcher);

  @override
  String get id => 'meinecloud';
  @override
  String get label => 'MeineCloud';
  @override
  List<String> get contentTypes => const ['movie'];
  @override
  List<CountryCode> get countryCodes => const [CountryCode.de];
  @override
  String get baseUrl => 'https://meinecloud.click';

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
      if (u.host.contains('meinecloud')) continue;
      out.add(SourceResult(
        url: u,
        meta: Meta(countryCodes: const [CountryCode.de], referer: baseUrl),
      ));
    }
    return out;
  }
}
