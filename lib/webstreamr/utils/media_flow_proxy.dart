/// Port of webstreamr/src/utils/media-flow-proxy.ts
library;

import '../types.dart';
import 'fetcher.dart';

bool supportsMediaFlowProxy(Context ctx) =>
    (ctx.config['mediaFlowProxyUrl'] ?? '').isNotEmpty;

Uri _buildMfpExtractorUrl(
    Context ctx, String host, Uri url, Map<String, String> headers) {
  final base = ctx.config['mediaFlowProxyUrl']!
      .replaceFirst(RegExp(r'^https?:\/\/'), '');
  final mfpUrl = Uri.parse('https://$base/extractor/video');
  final qp = <String, String>{
    'host': host,
    'api_password': ctx.config['mediaFlowProxyPassword'] ?? '',
    'd': url.toString(),
  };
  for (final e in headers.entries) {
    qp['h_${e.key.toLowerCase()}'] = e.value;
  }
  return mfpUrl.replace(queryParameters: qp);
}

Uri buildMediaFlowProxyExtractorRedirectUrl(
    Context ctx, String host, Uri url,
    [Map<String, String> headers = const {}]) {
  final u = _buildMfpExtractorUrl(ctx, host, url, headers);
  final qp = Map<String, String>.from(u.queryParameters);
  qp['redirect_stream'] = 'true';
  return u.replace(queryParameters: qp);
}

Future<Uri> buildMediaFlowProxyExtractorStreamUrl(Context ctx, Fetcher fetcher,
    String host, Uri url, Map<String, String> headers) async {
  final mfpUrl = _buildMfpExtractorUrl(ctx, host, url, headers);
  final result =
      await fetcher.json(ctx, mfpUrl, FetcherRequestConfig(
    queueLimit: 4,
    queueTimeout: const Duration(seconds: 10),
    timeout: const Duration(seconds: 20),
  )) as Map<String, dynamic>;
  final streamUrl = Uri.parse(result['mediaflow_proxy_url'] as String);
  final qp = Map<String, String>.from(streamUrl.queryParameters);
  final qParams = (result['query_params'] as Map?)?.cast<String, dynamic>();
  qParams?.forEach((k, v) => qp[k] = v.toString());
  final reqHeaders = (result['request_headers'] as Map?)?.cast<String, dynamic>();
  reqHeaders?.forEach((k, v) => qp['h_$k'] = v.toString());
  qp['d'] = result['destination_url'] as String;
  return streamUrl.replace(queryParameters: qp);
}
