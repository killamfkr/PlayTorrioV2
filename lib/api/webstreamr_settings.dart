import 'package:shared_preferences/shared_preferences.dart';

/// Persistent settings for the local WebStreamr port.
/// All getters return defaults when no value is set so the service is usable
/// out-of-the-box without showing the settings UI first.
class WebStreamrSettings {
  // Country codes (matches webstreamr CountryCode enum) — comma list in prefs.
  static const _kCountryCodes = 'webstreamr_country_codes';
  // MediaFlow proxy
  static const _kMfpUrl = 'webstreamr_mfp_url';
  static const _kMfpPassword = 'webstreamr_mfp_password';
  // FlareSolverr
  static const _kFlareUrl = 'webstreamr_flare_url';
  // Per-extractor disable (comma list of extractor ids)
  static const _kDisabledExtractors = 'webstreamr_disabled_extractors';
  // Excluded resolutions (comma list, e.g. "360p,4k")
  static const _kExcludedResolutions = 'webstreamr_excluded_resolutions';
  // TMDB v4 access token (Bearer …)
  static const _kTmdbToken = 'webstreamr_tmdb_token';

  /// Default country set when nothing is saved yet. Enables EVERY supported
  /// CC so foreign-language sources (DE/FR/IT/ES/AL/RU/...) light up
  /// out-of-the-box. Users can still narrow the list in Settings.
  static List<String> get defaultCountryCodes =>
      <String>['multi', ...allCountryCodes];

  /// All supported country codes (the WebStreamr CountryCode enum minus
  /// `multi` which is always on).
  static const allCountryCodes = <String>[
    'al', 'ar', 'bg', 'bl', 'cs', 'de', 'el', 'en', 'es', 'et', 'fa', 'fr',
    'gu', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'kn', 'ko', 'lt', 'lv',
    'ml', 'mr', 'mx', 'nl', 'no', 'pa', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl',
    'sr', 'ta', 'te', 'th', 'tr', 'uk', 'vi', 'zh',
  ];

  /// All extractor ids in the local pipeline (excluding `external` which is
  /// the catch-all and shouldn't be disabled).
  static const allExtractorIds = <String>[
    'doodstream', 'dropload', 'fastream', 'filelions', 'filemoon', 'fsst',
    'hubcloud', 'hubdrive', 'kinoger', 'lulustream', 'mixdrop', 'rgshows',
    'savefiles', 'streamembed', 'streamtape', 'supervideo', 'uqload',
    'vidora', 'vidsrc', 'vixsrc', 'voe', 'youtube',
  ];

  static const allResolutions = <String>['360p', '480p', '720p', '1080p', '4k'];

  static Future<List<String>> getEnabledCountryCodes() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kCountryCodes);
    if (raw == null) return List.of(defaultCountryCodes);
    return raw;
  }

  static Future<void> setEnabledCountryCodes(List<String> codes) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kCountryCodes, codes);
  }

  static Future<String?> getMediaFlowProxyUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kMfpUrl);
  }

  static Future<void> setMediaFlowProxyUrl(String? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null || v.isEmpty) {
      await p.remove(_kMfpUrl);
    } else {
      await p.setString(_kMfpUrl, v);
    }
  }

  static Future<String?> getMediaFlowProxyPassword() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kMfpPassword);
  }

  static Future<void> setMediaFlowProxyPassword(String? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null || v.isEmpty) {
      await p.remove(_kMfpPassword);
    } else {
      await p.setString(_kMfpPassword, v);
    }
  }

  static Future<String?> getFlareSolverrUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kFlareUrl);
  }

  static Future<void> setFlareSolverrUrl(String? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null || v.isEmpty) {
      await p.remove(_kFlareUrl);
    } else {
      await p.setString(_kFlareUrl, v);
    }
  }

  static Future<List<String>> getDisabledExtractors() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kDisabledExtractors) ?? const [];
  }

  static Future<void> setDisabledExtractors(List<String> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kDisabledExtractors, ids);
  }

  static Future<List<String>> getExcludedResolutions() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kExcludedResolutions) ?? const [];
  }

  static Future<void> setExcludedResolutions(List<String> res) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kExcludedResolutions, res);
  }

  static Future<String?> getTmdbAccessToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kTmdbToken);
  }

  static Future<void> setTmdbAccessToken(String? v) async {
    final p = await SharedPreferences.getInstance();
    if (v == null || v.isEmpty) {
      await p.remove(_kTmdbToken);
    } else {
      await p.setString(_kTmdbToken, v);
    }
  }
}
