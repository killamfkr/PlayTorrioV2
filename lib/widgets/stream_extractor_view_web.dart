import 'package:flutter/material.dart';
import '../api/stream_extractor.dart';

/// In-app WebView extraction is not available on web.
class StreamExtractorView extends StatelessWidget {
  final String url;
  final Function(ExtractedMedia) onMediaExtracted;

  const StreamExtractorView({
    super.key,
    required this.url,
    required this.onMediaExtracted,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream extraction'),
        backgroundColor: const Color(0xFF0F0418),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Manual stream extraction requires the mobile or desktop app '
            '(embedded WebView). On web, open the stream URL in a new tab or '
            'paste a direct stream link if you have one.\n\n$url',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ),
      ),
    );
  }
}
