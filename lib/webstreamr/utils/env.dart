/// App-level "env" — Dart equivalent of `process.env` lookups in
/// webstreamr/src/utils/env.ts. Backed by an in-memory map that the host
/// app can populate from settings / shared_preferences.
library;

class WsEnv {
  WsEnv._();
  static final Map<String, String> _env = {};

  /// Replace the entire env map (e.g. when settings change).
  static void load(Map<String, String> values) {
    _env
      ..clear()
      ..addAll(values);
  }

  static void set(String key, String? value) {
    if (value == null || value.isEmpty) {
      _env.remove(key);
    } else {
      _env[key] = value;
    }
  }

  static String? get(String key) => _env[key];

  static String getRequired(String key) {
    final v = _env[key];
    if (v == null || v.isEmpty) {
      throw StateError('Environment variable "$key" is not configured.');
    }
    return v;
  }

  static String appId() => _env['MANIFEST_ID'] ?? 'webstreamr';
  static String appName() => _env['MANIFEST_NAME'] ?? 'WebStreamr';
  static bool isProd() => _env['NODE_ENV'] == 'production';
  static bool isTest() => _env['NODE_ENV'] == 'test';
}
