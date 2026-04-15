import 'package:flutter/material.dart';

import '../api/settings_service.dart';

class ExternalPlayerService {
  static final ExternalPlayerService _instance =
      ExternalPlayerService._internal();
  factory ExternalPlayerService() => _instance;
  ExternalPlayerService._internal();

  static List<String> get playerNames => const ['Built-in Player'];

  static Future<bool> isExternalPlayerSelected() async => false;

  static Future<bool> launch({
    required String url,
    required String title,
    Map<String, String>? headers,
    BuildContext? context,
  }) async =>
      false;
}
