/// Error hierarchy mirroring webstreamr/src/error/*.ts
library;

import 'types.dart';

abstract class WebStreamrError implements Exception {
  final String message;
  WebStreamrError([this.message = '']);
  @override
  String toString() => '$runtimeType: $message';
}

class NotFoundError extends WebStreamrError {
  NotFoundError([super.message]);
}

class HttpError extends WebStreamrError {
  final Uri url;
  final int status;
  final String statusText;
  final Map<String, String> headers;
  HttpError(this.url, this.status, this.statusText, this.headers)
      : super('HTTP $status ($statusText) for $url');
}

class TimeoutError extends WebStreamrError {
  final Uri url;
  TimeoutError(this.url) : super('Timeout for $url');
}

class TooManyTimeoutsError extends WebStreamrError {
  final Uri url;
  TooManyTimeoutsError(this.url) : super('Too many timeouts for $url');
}

class TooManyRequestsError extends WebStreamrError {
  final Uri url;
  final num retryAfter;
  TooManyRequestsError(this.url, this.retryAfter)
      : super('Rate limited for ${url.host} (retry-after $retryAfter)');
}

class QueueIsFullError extends WebStreamrError {
  final Uri url;
  QueueIsFullError(this.url) : super('Queue full for ${url.host}');
}

class BlockedError extends WebStreamrError {
  final Uri url;
  final BlockedReason reason;
  final Map<String, String> headers;
  BlockedError(this.url, this.reason, this.headers)
      : super('Blocked: ${reason.name} on ${url.host}');
}
