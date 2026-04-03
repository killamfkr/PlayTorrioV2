import 'dart:io';

Future<bool> localMusicFileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (_) {
    return false;
  }
}
