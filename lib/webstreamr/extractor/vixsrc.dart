/// Port of webstreamr/src/extractor/VixSrc.ts
library;

import '../types.dart';
import '../utils/config.dart';
import '../utils/fetcher.dart';
import '../utils/height.dart';
import '../utils/language.dart';
import 'extractor.dart';

class VixSrc extends Extractor {
  VixSrc(super.fetcher);

  @override
  String get id => 'vixsrc';
  @override
  String get label => 'VixSrc';
  @override
  Duration get ttl => const Duration(hours: 6);

  @override
  bool supports(Context ctx, Uri url) => url.host.contains('vixsrc');

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': url.toString()};
    final html = await fetcher.text(ctx, url);

    final tokenMatch =
        RegExp(r'''['"]token['"]\s*[:=]\s*['"]([^'"]+)['"]''').firstMatch(html);
    final expiresMatch =
        RegExp(r'''['"]expires['"]\s*[:=]\s*['"]([^'"]+)['"]''')
            .firstMatch(html);
    final urlMatch =
        RegExp(r'''url\s*[:=]\s*['"](https?://[^'"]+)['"]''').firstMatch(html) ??
            RegExp(r'''['"]url['"]\s*[:=]\s*['"](https?://[^'"]+)['"]''')
                .firstMatch(html) ??
            RegExp(r'''(https?://[^'"\s]+\.mp4[^'"\s]*)''').firstMatch(html) ??
            RegExp(r'''(https?://[^'"\s]+\.m3u8[^'"\s]*)''').firstMatch(html);
    if (tokenMatch == null || expiresMatch == null || urlMatch == null) {
      // Dump a small slice of the HTML for debugging the next time this
      // breaks (vixsrc obfuscation changes regularly).
      final snippet = html.length > 300 ? html.substring(0, 300) : html;
      throw StateError(
          'VixSrc: token/expires/url not found. token=${tokenMatch != null} expires=${expiresMatch != null} url=${urlMatch != null}. head=$snippet');
    }
    final base = Uri.parse(urlMatch.group(1)!);
    final qp = Map<String, String>.from(base.queryParameters);
    qp['token'] = tokenMatch.group(1)!;
    qp['expires'] = expiresMatch.group(1)!;
    qp['h'] = '1';
    final playlistUrl = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '${base.path}.m3u8',
      queryParameters: qp,
    );

    final ccs = meta.countryCodes ??
        [
          CountryCode.multi,
          ...await _detectCountries(ctx, playlistUrl, headers),
        ];
    if (!hasMultiEnabled(ctx.config) &&
        !ccs.any((c) => ctx.config.containsKey(c.name))) {
      return const [];
    }

    final out = meta.clone();
    out.countryCodes = ccs;
    out.height ??= await guessHeightFromPlaylist(
        ctx, fetcher, playlistUrl, FetcherRequestConfig(headers: headers));

    return [
      InternalUrlResult(url: playlistUrl, format: Format.hls, meta: out),
    ];
  }

  Future<List<CountryCode>> _detectCountries(
      Context ctx, Uri playlistUrl, Map<String, String> headers) async {
    final pl = await fetcher.text(
        ctx, playlistUrl, FetcherRequestConfig(headers: headers));
    final out = <CountryCode>[];
    for (final cc in CountryCode.values) {
      final iso = iso639FromCountryCode(cc);
      if (iso == null) continue;
      if (RegExp('#EXT-X-MEDIA:TYPE=AUDIO.*LANGUAGE="$iso"').hasMatch(pl)) {
        if (!out.contains(cc)) out.add(cc);
      }
    }
    return out;
  }
}
