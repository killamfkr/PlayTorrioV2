/// Web: no LAN settings server.
class TvSettingsRemoteService {
  static final TvSettingsRemoteService _instance =
      TvSettingsRemoteService._internal();
  factory TvSettingsRemoteService() => _instance;
  TvSettingsRemoteService._internal();

  int get port => 0;
  String? get remoteUrl => null;
  bool get isRunning => false;

  Future<void> ensureStarted() async {}
  Future<void> refreshLanIp() async {}
  Future<void> stop() async {}
}
