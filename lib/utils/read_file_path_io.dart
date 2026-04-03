import 'dart:io';

Future<String> readFilePathAsString(String path) => File(path).readAsString();
