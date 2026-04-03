import 'package:flutter/foundation.dart';

/// Bumped when the app should reload TV Guide / XMLTV-backed channel listings
/// (e.g. app resumed from background or main shell opened after splash).
class TvGuideRefresh {
  TvGuideRefresh._();

  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  static void bump() {
    notifier.value++;
  }
}
