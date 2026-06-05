/// Port of webstreamr/src/utils/StreamResolver.ts. Returns Stremio-shaped
/// `Stream` objects as plain `Map<String,dynamic>` (host app converts).
library;

import 'dart:async';

import 'extractor/extractor_registry.dart';
import 'source/source.dart';
import 'types.dart';
import 'utils/config.dart';
import 'utils/env.dart';
import 'utils/error_strings.dart';
import 'utils/id.dart';
import 'utils/language.dart';
import 'utils/resolution.dart';
import 'utils/semaphore.dart';

class ResolveResponse {
  final List<Map<String, dynamic>> streams;
  final int? ttl;
  ResolveResponse({required this.streams, this.ttl});
}

String _formatBytes(int b) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  return '$s ${units[i]}';
}

class StreamResolver {
  final WsLogger logger;
  final ExtractorRegistry registry;
  StreamResolver(this.logger, this.registry);

  Future<ResolveResponse> resolve(
      Context ctx, List<Source> sources, String type, Id id) async {
    if (sources.isEmpty) {
      return ResolveResponse(streams: [
        {
          'name': 'WebStreamr',
          'title': '⚠️ No sources found. Please re-configure the plugin.',
          'externalUrl': ctx.hostUrl.toString(),
        },
      ]);
    }

    final streams = <Map<String, dynamic>>[];
    final urlResults = <UrlResult>[];
    var sourceErrorCount = 0;
    final sourceErrorMutex = Mutex();
    final urlCountByCC = <CountryCode, int>{};
    final urlCountMutex = Mutex();
    final skippedFallbackSources = <Source>[];

    Future<void> handleSource(Source source, bool countByCC) async {
      try {
        final sr = await source.handle(ctx, type, id);
        logger('info',
            'Source ${source.id} returned ${sr.length} embed(s)');
        final futures = sr.map((s) {
          final m = s.meta.clone();
          m.sourceId ??= source.id;
          m.sourceLabel ??= source.label;
          m.priority ??= source.priority;
          return registry.handle(ctx, s.url, m, true);
        });
        final all = (await Future.wait(futures)).expand((x) => x);
        var ok = 0;
        var err = 0;
        for (final r in all) {
          urlResults.add(r);
          if (r.error != null) {
            err++;
            logger('warn',
                'Source ${source.id} → extractor ${r.meta?.extractorId} on ${r.url} errored: ${r.error}');
            continue;
          }
          ok++;
          if (!countByCC) continue;
          await urlCountMutex.runExclusive(() async {
            r.meta?.countryCodes?.forEach((cc) {
              urlCountByCC[cc] = (urlCountByCC[cc] ?? 0) + 1;
            });
          });
        }
        logger('info',
            'Source ${source.id}: $ok ok, $err errored from ${sr.length} embed(s)');
      } catch (error, st) {
        await sourceErrorMutex.runExclusive(() async {
          sourceErrorCount++;
        });
        logger('warn', 'Source ${source.id} threw: $error\n$st');
        if (showErrors(ctx.config)) {
          streams.add({
            'name': WsEnv.appName(),
            'title': '🔗 ${source.label}\n'
                '${logErrorAndReturnNiceString(ctx, logger, source.id, error)}',
            'externalUrl': source.baseUrl,
          });
        }
      }
    }

    final futures = <Future<void>>[];
    for (final s in sources) {
      if (!s.contentTypes.contains(type)) continue;
      if (s.useOnlyWithMaxUrlsFound != null) {
        skippedFallbackSources.add(s);
        continue;
      }
      futures.add(handleSource(s, true));
    }
    await Future.wait(futures);

    final fallbackFutures = <Future<void>>[];
    for (final fb in skippedFallbackSources) {
      final count = urlResults.fold<int>(0, (acc, r) {
        final cc = r.meta?.countryCodes ?? const <CountryCode>[];
        final intersects = fb.countryCodes.any(cc.contains);
        return acc + (intersects ? 1 : 0);
      });
      if (count > fb.useOnlyWithMaxUrlsFound!) continue;
      fallbackFutures.add(handleSource(fb, false));
    }
    await Future.wait(fallbackFutures);

    urlResults.sort((a, b) {
      if (a.error != null || b.error != null) {
        return a.error != null ? -1 : 1;
      }
      if (a.isExternal != b.isExternal) {
        return a.isExternal ? 1 : -1;
      }
      final h = (b.meta?.height ?? 0) - (a.meta?.height ?? 0);
      if (h != 0) return h;
      final by = (b.meta?.bytes ?? 0) - (a.meta?.bytes ?? 0);
      if (by != 0) return by;
      final p = (b.meta?.priority ?? 0) - (a.meta?.priority ?? 0);
      if (p != 0) return p;
      return a.label.compareTo(b.label);
    });

    final errorCount = urlResults.fold<int>(
        sourceErrorCount, (c, r) => r.error != null ? c + 1 : c);
    logger('info',
        'Got ${urlResults.length} url results, including $errorCount errors');

    if (errorCount > 0) {
      for (final r in urlResults) {
        if (r.error == null) continue;
        logger(
            'warn',
            'ERROR src=${r.meta?.sourceId} ext=${r.meta?.extractorId} '
            'url=${r.url} → ${r.error}');
      }
    }

    final seen = <String>{};
    for (final r in urlResults) {
      if (r.error != null && !showErrors(ctx.config)) continue;
      if (isResolutionExcluded(
          ctx.config, getClosestResolution(r.meta?.height))) {
        continue;
      }
      final href = r.url.toString();
      if (!seen.add(href)) continue;
      streams.add({
        ..._buildUrl(r),
        'name': _buildName(ctx, r),
        'title': _buildTitle(ctx, r),
        'behaviorHints': {
          'bingeGroup':
              'webstreamr-${r.meta?.sourceId}-${r.meta?.extractorId}-${r.meta?.countryCodes?.map((c) => c.name).join("_")}',
          if (r.format != Format.mp4) 'notWebReady': true,
          if (r.requestHeaders != null) ...{
            'notWebReady': true,
            'proxyHeaders': {'request': r.requestHeaders},
          },
          if (r.meta?.bytes != null) 'videoSize': r.meta!.bytes,
        },
      });
    }

    int? ttl;
    if (sourceErrorCount == 0) {
      if (urlResults.isEmpty) {
        ttl = const Duration(minutes: 15).inMilliseconds;
      } else {
        ttl = urlResults.map((r) => r.ttl).reduce((a, b) => a < b ? a : b);
      }
    }
    return ResolveResponse(streams: streams, ttl: ttl);
  }

  Map<String, dynamic> _buildUrl(UrlResult r) {
    if (r.ytId != null) return {'ytId': r.ytId};
    if (!r.isExternal) return {'url': r.url.toString()};
    return {'externalUrl': r.url.toString()};
  }

  String _buildName(Context ctx, UrlResult r) {
    var n = WsEnv.appName();
    r.meta?.countryCodes?.forEach((c) {
      n += ' ${flagFromCountryCode(c)}';
    });
    if (r.meta?.height != null) {
      n += ' ${getClosestResolution(r.meta!.height)}';
    }
    if (r.isExternal && showExternalUrls(ctx.config)) {
      n += ' ⚠️ external';
    }
    return n;
  }

  String _buildTitle(Context ctx, UrlResult r) {
    final lines = <String>[];
    if (r.meta?.title != null) lines.add(r.meta!.title!);
    final detail = <String>[];
    if (r.meta?.bytes != null) {
      detail.add('💾 ${_formatBytes(r.meta!.bytes!)}');
    }
    final sl = r.meta?.sourceLabel;
    if (sl != null && sl != r.label) {
      detail.add('🔗 ${r.label} from $sl');
    } else {
      detail.add('🔗 ${r.label}');
    }
    lines.add(detail.join(' '));
    if (r.error != null) {
      lines.add(logErrorAndReturnNiceString(
          ctx, logger, r.meta?.sourceId ?? '', r.error!));
    }
    return lines.join('\n');
  }
}
