/// Config helpers — 1:1 from webstreamr/src/utils/config.ts
library;

import '../types.dart';

Config getDefaultConfig() => {'multi': 'on', 'en': 'on'};

bool showErrors(Config c) => c.containsKey('showErrors');
bool showExternalUrls(Config c) => c.containsKey('includeExternalUrls');
bool hasMultiEnabled(Config c) => c.containsKey('multi');

String disableExtractorConfigKey(String extractorId) =>
    'disableExtractor_$extractorId';
bool isExtractorDisabled(Config c, String extractorId) =>
    c.containsKey(disableExtractorConfigKey(extractorId));

String excludeResolutionConfigKey(String resolution) =>
    'excludeResolution_$resolution';
bool isResolutionExcluded(Config c, String resolution) =>
    c.containsKey(excludeResolutionConfigKey(resolution));
