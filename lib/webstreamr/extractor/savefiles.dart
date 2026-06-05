/// Port of webstreamr/src/extractor/SaveFiles.ts
library;

import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../types.dart';
import '../utils/fetcher.dart';
import 'extractor.dart';

class SaveFiles extends Extractor {
  SaveFiles(super.fetcher);

  @override
  String get id => 'savefiles';
  @override
  String get label => 'SaveFiles';
  @override
  Duration get ttl => const Duration(hours: 6);

  @override
  bool supports(Context ctx, Uri url) =>
      RegExp(r'savefiles|streamhls').hasMatch(url.host);

  @override
  Uri normalize(Uri url) => Uri.parse(url
      .toString()
      .replaceFirst('/e/', '/')
      .replaceFirst('/d/', '/'));

  @override
  Future<List<InternalUrlResult>> extractInternal(
      Context ctx, Uri url, Meta meta) async {
    final headers = {'Referer': meta.referer ?? url.toString()};
    final html =
        await fetcher.text(ctx, url, FetcherRequestConfig(headers: headers));
    if (RegExp(r'file was locked|file was deleted', caseSensitive: false)
        .hasMatch(html)) {
      throw NotFoundError();
    }
    final fM = RegExp(r'file:"(.*?)"').firstMatch(html);
    final sM = RegExp(r'\[\d{3,}x(\d{3,})').firstMatch(html);
    if (fM == null) throw StateError('SaveFiles: file: missing');
    final doc = html_parser.parse(html);
    final title = doc.querySelector('.download-title')?.text.trim();

    final out = meta.clone();
    if (title != null && title.isNotEmpty) out.title = title;
    if (sM != null) out.height = int.tryParse(sM.group(1)!);

    return [
      InternalUrlResult(
        url: Uri.parse(fM.group(1)!),
        format: Format.hls,
        meta: out,
      ),
    ];
  }
}
