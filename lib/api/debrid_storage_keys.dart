/// SharedPreferences keys for debrid provider API tokens (used by [DebridApi] and cloud sync).
abstract final class DebridStorageKeys {
  static const String rdToken = 'rd_access_token';
  static const String torbox = 'torbox_api_key';
  static const String allDebrid = 'alldebrid_api_key';
  static const String premiumize = 'premiumize_api_key';
  static const String debridLink = 'debridlink_api_key';
}
