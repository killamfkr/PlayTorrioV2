/// Core types — 1:1 port of webstreamr/src/types.ts
library;

/// User configuration. Each enabled country/feature is present as a key with
/// any non-null value (the upstream uses 'on'). Special keys:
///   * `showErrors`, `includeExternalUrls`
///   * `mediaFlowProxyUrl`, `mediaFlowProxyPassword`
///   * `disableExtractor_<id>`
///   * `excludeResolution_<res>`
typedef Config = Map<String, String>;

/// Per-request execution context.
class Context {
  final Uri hostUrl;
  final String id;
  final String? ip;
  final Config config;

  Context({
    required this.hostUrl,
    required this.id,
    this.ip,
    required this.config,
  });
}

enum CountryCode {
  multi,
  al,
  ar,
  bg,
  bl,
  cs,
  de,
  el,
  en,
  es,
  et,
  fa,
  fr,
  gu,
  he,
  hi,
  hr,
  hu,
  id,
  it,
  ja,
  kn,
  ko,
  lt,
  lv,
  ml,
  mr,
  mx,
  nl,
  no,
  pa,
  pl,
  pt,
  ro,
  ru,
  sk,
  sl,
  sr,
  ta,
  te,
  th,
  tr,
  uk,
  vi,
  zh,
}

CountryCode? countryCodeFromString(String s) {
  for (final c in CountryCode.values) {
    if (c.name == s) return c;
  }
  return null;
}

// ignore_for_file: constant_identifier_names
enum BlockedReason {
  cloudflare_challenge,
  flaresolverr_failed,
  cloudflare_censor,
  media_flow_proxy_auth,
  unknown,
}

enum Format { hls, mp4, unknown }

class Meta {
  int? bytes;
  List<CountryCode>? countryCodes;
  String? extractorId;
  int? height;
  int? priority;
  String? referer;
  String? sourceId;
  String? sourceLabel;
  String? title;

  Meta({
    this.bytes,
    this.countryCodes,
    this.extractorId,
    this.height,
    this.priority,
    this.referer,
    this.sourceId,
    this.sourceLabel,
    this.title,
  });

  Meta clone() => Meta(
        bytes: bytes,
        countryCodes: countryCodes == null ? null : List.of(countryCodes!),
        extractorId: extractorId,
        height: height,
        priority: priority,
        referer: referer,
        sourceId: sourceId,
        sourceLabel: sourceLabel,
        title: title,
      );

  Meta merge(Meta? other) {
    if (other == null) return clone();
    final out = clone();
    if (other.bytes != null) out.bytes = other.bytes;
    if (other.countryCodes != null) out.countryCodes = List.of(other.countryCodes!);
    if (other.extractorId != null) out.extractorId = other.extractorId;
    if (other.height != null) out.height = other.height;
    if (other.priority != null) out.priority = other.priority;
    if (other.referer != null) out.referer = other.referer;
    if (other.sourceId != null) out.sourceId = other.sourceId;
    if (other.sourceLabel != null) out.sourceLabel = other.sourceLabel;
    if (other.title != null) out.title = other.title;
    return out;
  }

  Map<String, dynamic> toJson() => {
        if (bytes != null) 'bytes': bytes,
        if (countryCodes != null)
          'countryCodes': countryCodes!.map((c) => c.name).toList(),
        if (extractorId != null) 'extractorId': extractorId,
        if (height != null) 'height': height,
        if (priority != null) 'priority': priority,
        if (referer != null) 'referer': referer,
        if (sourceId != null) 'sourceId': sourceId,
        if (sourceLabel != null) 'sourceLabel': sourceLabel,
        if (title != null) 'title': title,
      };

  static Meta fromJson(Map<String, dynamic> j) => Meta(
        bytes: (j['bytes'] as num?)?.toInt(),
        countryCodes: (j['countryCodes'] as List?)
            ?.map((s) => countryCodeFromString(s as String))
            .whereType<CountryCode>()
            .toList(),
        extractorId: j['extractorId'] as String?,
        height: (j['height'] as num?)?.toInt(),
        priority: (j['priority'] as num?)?.toInt(),
        referer: j['referer'] as String?,
        sourceId: j['sourceId'] as String?,
        sourceLabel: j['sourceLabel'] as String?,
        title: j['title'] as String?,
      );
}

/// Result returned by an [Extractor.extractInternal].
class InternalUrlResult {
  Uri url;
  Format format;
  bool isExternal;
  String? ytId;
  Object? error;
  String? label;
  Meta? meta;
  Map<String, String>? requestHeaders;

  InternalUrlResult({
    required this.url,
    required this.format,
    this.isExternal = false,
    this.ytId,
    this.error,
    this.label,
    this.meta,
    this.requestHeaders,
  });
}

/// Result with all extractor-level metadata applied (label + ttl).
class UrlResult {
  Uri url;
  Format format;
  bool isExternal;
  String? ytId;
  Object? error;
  String label;
  int ttl;
  Meta? meta;
  bool? notWebReady;
  Map<String, String>? requestHeaders;

  UrlResult({
    required this.url,
    required this.format,
    this.isExternal = false,
    this.ytId,
    this.error,
    required this.label,
    required this.ttl,
    this.meta,
    this.notWebReady,
    this.requestHeaders,
  });
}

/// Result returned by a [Source.handleInternal] — an embed URL + meta.
class SourceResult {
  Uri url;
  Meta meta;
  SourceResult({required this.url, required this.meta});
}
