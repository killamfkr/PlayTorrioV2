/// Port of webstreamr/src/error/index.ts `logErrorAndReturnNiceString`.
library;

import '../errors.dart';
import '../types.dart';

typedef WsLogger = void Function(String level, String msg);

String logErrorAndReturnNiceString(
    Context ctx, WsLogger logger, String source, Object error) {
  if (error is BlockedError) {
    if (error.reason == BlockedReason.media_flow_proxy_auth) {
      return '⚠️ MediaFlow Proxy authentication failed. Please set the correct password.';
    }
    logger('warn',
        '$source: Request to ${error.url} was blocked, reason: ${error.reason.name}, headers: ${error.headers}.');
    return '⚠️ Request to ${error.url.host} was blocked. Reason: ${error.reason.name}';
  }
  if (error is TooManyRequestsError) {
    logger('warn',
        '$source: Request to ${error.url} was rate limited for ${error.retryAfter} seconds.');
    return '🚦 Request to ${error.url.host} was rate-limited. Please try again later or consider self-hosting.';
  }
  if (error is TooManyTimeoutsError) {
    logger('warn', '$source: Too many timeouts when requesting ${error.url}.');
    return '🚦 Too many recent timeouts when requesting ${error.url.host}. Please try again later.';
  }
  if (error is TimeoutError) {
    logger('warn', '$source: Request to ${error.url} timed out.');
    return '🐢 Request to ${error.url.host} timed out.';
  }
  if (error is QueueIsFullError) {
    logger('warn', '$source: Request queue for ${error.url.host} is full.');
    return '⏳ Request queue for ${error.url.host} is full. Please try again later or consider self-hosting.';
  }
  if (error is HttpError) {
    logger('error',
        '$source: Error when requesting url ${error.url}, HTTP status ${error.status} (${error.statusText}), headers: ${error.headers}.');
    if (error.status >= 500) {
      return '❌ Remote server ${error.url.host} has issues. We can\'t fix this, please try later again.';
    }
    return '❌ Request to ${error.url.host} failed with status ${error.status} (${error.statusText}). Request-id: ${ctx.id}.';
  }
  logger('error', '$source error: $error');
  return '❌ Request failed. Request-id: ${ctx.id}.';
}
