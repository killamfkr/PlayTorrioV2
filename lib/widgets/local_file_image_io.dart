import 'dart:io';

import 'package:flutter/material.dart';

Widget localFileImageOrFallback({
  required String path,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  return Image.file(
    File(path),
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (c, e, s) => Container(
      width: width,
      height: height,
      color: Colors.white.withValues(alpha: 0.05),
      child: const Icon(Icons.broken_image_rounded, color: Colors.white24),
    ),
  );
}
