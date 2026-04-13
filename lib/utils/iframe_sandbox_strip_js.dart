/// Injected into WebViews so nested players (e.g. YouTube) are not blocked by
/// parent `<iframe sandbox>` — Android WebView shows "Remove sandbox attributes
/// on the iframe tag" otherwise.
library;

import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Runs at document start in main frame **and** subframes (`forMainFrameOnly: false`).
String iframeSandboxStripAtDocumentStartJs() => '''
(function() {
  if (window.__pt_strip_iframe_sandbox) return;
  window.__pt_strip_iframe_sandbox = true;
  var relax = function() {
    document.querySelectorAll('iframe[sandbox]').forEach(function(el) {
      try { el.removeAttribute('sandbox'); } catch (e) {}
    });
  };
  relax();
  try {
    new MutationObserver(relax).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}
})();
''';

List<UserScript> iframeSandboxStripUserScripts() => UnmodifiableListView([
      UserScript(
        source: iframeSandboxStripAtDocumentStartJs(),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
    ]);
