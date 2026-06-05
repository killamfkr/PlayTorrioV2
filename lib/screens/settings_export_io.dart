import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../platform_flags.dart';

/// Returns true if the user completed save (or web download handled elsewhere).
Future<bool> runNativeSettingsExport(String jsonStr, String fileName) async {
  final tempDir = await getTemporaryDirectory();
  final tempFile = File('${tempDir.path}/$fileName');
  await tempFile.writeAsString(jsonStr);

  final result = await FilePicker.platform.saveFile(
    dialogTitle: 'Export Settings',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['json'],
    bytes: Uint8List.fromList(utf8.encode(jsonStr)),
  );

  if (result != null && platformIsDesktop) {
    await File(result).writeAsString(jsonStr);
  }

  await tempFile.delete();
  return result != null;
}
