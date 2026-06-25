/// No-op stand-in: cloud sync is optional in the full PlayTorrio app.
class PlaytorrioCloudSyncService {
  PlaytorrioCloudSyncService._();
  static final instance = PlaytorrioCloudSyncService._();

  void scheduleSettingsPush() {}
  void scheduleDebouncedSettingsPush() {}
  Future<void> pullUserSettings() async {}
}
