import 'package:flutter/foundation.dart';

/// Web: no LAN HTTP server.
class PtTvHdhomerunServer {
  static final PtTvHdhomerunServer _instance = PtTvHdhomerunServer._internal();
  factory PtTvHdhomerunServer() => _instance;
  PtTvHdhomerunServer._internal();

  bool get isRunning => false;
  int get boundPort => 0;

  Future<void> applyFromSettings() async {
    debugPrint('[PtTvHdhr] Web: LAN HDHomeRun emulation disabled');
  }

  Future<void> stop() async {}

  Future<String?> describeLanBaseUrl() async => null;
}
