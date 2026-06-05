import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> saveLyricsJson(String trackId, String jsonBody) async {
  final dir = await getApplicationDocumentsDirectory();
  final lyricsDir = Directory('${dir.path}/lyrics');
  if (!await lyricsDir.exists()) await lyricsDir.create(recursive: true);
  final file = File('${lyricsDir.path}/$trackId.json');
  await file.writeAsString(jsonBody);
}

Future<String?> loadLyricsJson(String trackId) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/lyrics/$trackId.json');
  if (await file.exists()) {
    return file.readAsString();
  }
  return null;
}
