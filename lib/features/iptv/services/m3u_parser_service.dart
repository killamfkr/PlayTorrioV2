import 'package:http/http.dart' as http;
import '../models/iptv_channel.dart';
import '../models/iptv_category.dart';

class M3uParserService {
  Future<M3uParseResult> parseFromUrl(String url) async {
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw Exception('Failed to fetch playlist: ${response.statusCode}');
    final body = response.body;
    if (!body.trimLeft().startsWith('#EXTM3U')) {
      throw Exception('Invalid M3U playlist format');
    }
    return _parse(body);
  }

  M3uParseResult _parse(String content) {
    // Normalize line endings
    final lines = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final channels = <IptvChannel>[];
    final categoriesSet = <String>{};
    int autoId = 1;

    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXTINF:')) {
        // Find the next non-empty, non-comment line for URL
        String? streamUrl;
        for (int j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (next.isEmpty || next.startsWith('#')) continue;
          streamUrl = next;
          break;
        }
        if (streamUrl == null || streamUrl.isEmpty) continue;

        final name = _extractAfterComma(line);
        final tvgLogo = _extractAttribute(line, 'tvg-logo');
        final groupTitle = _extractAttribute(line, 'group-title') ?? 'Uncategorized';
        final tvgId = _extractAttribute(line, 'tvg-id');

        categoriesSet.add(groupTitle);

        channels.add(IptvChannel(
          num: autoId,
          name: name.isNotEmpty ? name : 'Channel $autoId',
          streamId: autoId,
          streamIcon: tvgLogo,
          categoryId: groupTitle,
          categoryName: groupTitle,
          epgChannelId: tvgId,
          streamUrl: streamUrl,
        ));
        autoId++;
      }
    }

    // Build category list from group titles
    final categories = categoriesSet.map((name) => IptvCategory(
      categoryId: name,
      categoryName: name,
    )).toList()
      ..sort((a, b) => a.categoryName.compareTo(b.categoryName));

    return M3uParseResult(channels: channels, categories: categories);
  }

  String _extractAfterComma(String line) {
    final idx = line.lastIndexOf(',');
    return idx >= 0 ? line.substring(idx + 1).trim() : '';
  }

  String? _extractAttribute(String line, String attr) {
    final regex = RegExp('$attr="([^"]*)"');
    return regex.firstMatch(line)?.group(1);
  }
}

class M3uParseResult {
  final List<IptvChannel> channels;
  final List<IptvCategory> categories;

  const M3uParseResult({required this.channels, required this.categories});
}
