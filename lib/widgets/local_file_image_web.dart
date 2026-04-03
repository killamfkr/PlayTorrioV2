import 'package:flutter/material.dart';

Widget localFileImageOrFallback({
  required String path,
  required double width,
  required double height,
  BoxFit fit = BoxFit.cover,
}) {
  return Container(
    width: width,
    height: height,
    color: Colors.white.withValues(alpha: 0.05),
    child: const Icon(Icons.folder_off_rounded, color: Colors.white24),
  );
}
