import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class WebViewCleanup {
  /// Deletes the WebView cache folder to save disk space (cross-platform)
  static Future<void> cleanupWebView2Cache() async {
    if (kIsWeb) return;
    try {
      // Wait for WebView to fully release file locks
      await Future.delayed(const Duration(seconds: 2));
      
      if (Platform.isWindows) {
        // Windows: Delete .WebView2 folder next to executable
        final exePath = Platform.resolvedExecutable;
        final exeDir = path.dirname(exePath);
        final exeName = path.basenameWithoutExtension(exePath);
        final webView2Dir = Directory(path.join(exeDir, '$exeName.WebView2'));
        
        if (await webView2Dir.exists()) {
          debugPrint('[WebViewCleanup] Found WebView2 cache: ${webView2Dir.path}');
          
          // Try multiple times with increasing delays
          bool deleted = false;
          for (int attempt = 1; attempt <= 5; attempt++) {
            try {
              debugPrint('[WebViewCleanup] Deletion attempt $attempt/5...');
              await webView2Dir.delete(recursive: true);
              debugPrint('[WebViewCleanup] ✓ Cache deleted successfully');
              deleted = true;
              break;
            } catch (e) {
              debugPrint('[WebViewCleanup] Attempt $attempt failed: $e');
              if (attempt < 5) {
                await Future.delayed(Duration(seconds: attempt)); // Exponential backoff
              }
            }
          }
          
          // If normal delete failed, try force delete with cmd
          if (!deleted) {
            debugPrint('[WebViewCleanup] Trying force delete with rmdir...');
            try {
              final result = await Process.run(
                'cmd',
                ['/c', 'rmdir', '/s', '/q', '"${webView2Dir.path}"'],
                runInShell: true,
              );
              if (result.exitCode == 0) {
                debugPrint('[WebViewCleanup] ✓ Force deleted with rmdir');
              } else {
                debugPrint('[WebViewCleanup] rmdir failed: ${result.stderr}');
              }
            } catch (e) {
              debugPrint('[WebViewCleanup] Force delete failed: $e');
            }
          }
        } else {
          debugPrint('[WebViewCleanup] No WebView2 cache found');
        }
      } else if (Platform.isLinux) {
        // Linux: WebKitGTK cache in ~/.cache/webkitgtk or app-specific cache
        final home = Platform.environment['HOME'];
        if (home != null) {
          final cacheDirs = [
            Directory(path.join(home, '.cache', 'webkitgtk')),
            Directory(path.join(home, '.cache', 'play_torrio_native')),
          ];
          
          for (final cacheDir in cacheDirs) {
            if (await cacheDir.exists()) {
              debugPrint('[WebViewCleanup] Deleting Linux cache: ${cacheDir.path}');
              await cacheDir.delete(recursive: true);
            }
          }
        }
      } else if (Platform.isMacOS) {
        // macOS: WKWebView cache in ~/Library/Caches
        final home = Platform.environment['HOME'];
        if (home != null) {
          final cacheDirs = [
            Directory(path.join(home, 'Library', 'Caches', 'play_torrio_native')),
            Directory(path.join(home, 'Library', 'WebKit')),
          ];
          
          for (final cacheDir in cacheDirs) {
            if (await cacheDir.exists()) {
              debugPrint('[WebViewCleanup] Deleting macOS cache: ${cacheDir.path}');
              await cacheDir.delete(recursive: true);
            }
          }
        }
      }
      
      debugPrint('[WebViewCleanup] Cleanup complete');
    } catch (e) {
      debugPrint('[WebViewCleanup] Error cleaning cache: $e');
      // Silently fail - not critical
    }
  }
}
