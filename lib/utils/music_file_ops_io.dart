import 'dart:io';

/// Deletes a file at [path] if it exists. No-op on failure.
Future<void> deleteFileIfExists(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// Parent directory of [path] when it denotes a file path.
String? parentDirectoryPath(String path) {
  try {
    return File(path).parent.path;
  } catch (_) {
    return null;
  }
}
