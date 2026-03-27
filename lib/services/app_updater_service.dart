import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// GitHub repo for [releases](https://docs.github.com/en/rest/releases/releases).
/// Override at build time: `--dart-define=GITHUB_UPDATE_REPO=owner/name`
class AppUpdaterService {
  static const String githubRepo = String.fromEnvironment(
    'GITHUB_UPDATE_REPO',
    defaultValue: 'killamfkr/PlayTorrioV2',
  );

  static String get _releasesApi =>
      'https://api.github.com/repos/$githubRepo/releases';

  static const _githubApiHeaders = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'PlayTorrio-Updater',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<UpdateInfo?> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final release = await _fetchLatestUsableRelease();
      if (release == null) return null;

      final tagName = (release['tag_name'] as String?) ?? '';
      var latestVersion = tagName.replaceFirst(RegExp(r'^v'), '').trim();
      // Ignore CI tags like ci-123 for semver compare (still allow download if needed)
      if (!_looksLikeSemver(latestVersion)) {
        latestVersion = _versionFromReleaseBodyOrTag(release, tagName);
      }
      if (!_looksLikeSemver(latestVersion)) return null;

      final releaseNotes =
          (release['body'] as String?) ?? 'No release notes available';
      final publishedAt = DateTime.tryParse(
            (release['published_at'] as String?) ?? '',
          ) ??
          DateTime.now();

      if (!_isNewerVersion(currentVersion, latestVersion)) {
        return null;
      }

      String? downloadUrl;
      final assets = release['assets'] as List? ?? [];

      if (Platform.isWindows) {
        final asset = _pickAsset(assets, (name) {
          final n = name.toLowerCase();
          return n.contains('windows') && n.endsWith('.exe');
        });
        downloadUrl = asset?['browser_download_url'] as String?;
      } else if (Platform.isLinux) {
        final asset = _pickAsset(assets, (name) {
          final n = name.toLowerCase();
          return n.contains('linux') &&
              (n.endsWith('.appimage') || n.endsWith('.deb'));
        });
        downloadUrl = asset?['browser_download_url'] as String?;
      } else if (Platform.isMacOS) {
        downloadUrl = release['html_url'] as String?;
      } else if (Platform.isAndroid) {
        final asset = _pickAndroidApk(assets);
        downloadUrl = asset?['browser_download_url'] as String?;
      } else if (Platform.isIOS) {
        downloadUrl = release['html_url'] as String?;
      }

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl ?? (release['html_url'] as String? ?? ''),
        releaseNotes: releaseNotes,
        publishedAt: publishedAt,
        isMacOS: Platform.isMacOS,
        isIOS: Platform.isIOS,
      );
    } catch (e, st) {
      debugPrint('Error checking for updates: $e\n$st');
      return null;
    }
  }

  /// Prefer /releases/latest, then newest release with a semver-looking tag.
  Future<Map<String, dynamic>?> _fetchLatestUsableRelease() async {
    var response = await http.get(
      Uri.parse('$_releasesApi/latest'),
      headers: _githubApiHeaders,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }

    // No "latest" (e.g. only drafts or prereleases-only) — walk recent releases.
    response = await http.get(
      Uri.parse('$_releasesApi?per_page=15'),
      headers: _githubApiHeaders,
    );
    if (response.statusCode != 200) {
      debugPrint(
        'GitHub releases list failed: ${response.statusCode} ${response.body}',
      );
      return null;
    }

    final list = json.decode(response.body) as List<dynamic>;
    for (final raw in list) {
      final r = raw as Map<String, dynamic>;
      if (r['draft'] == true) continue;
      final tag = (r['tag_name'] as String?) ?? '';
      final ver = tag.replaceFirst(RegExp(r'^v'), '');
      if (_looksLikeSemver(ver)) return r;
    }
    return null;
  }

  String _versionFromReleaseBodyOrTag(
    Map<String, dynamic> release,
    String tagName,
  ) {
    final body = release['body'] as String? ?? '';
    final m = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(body);
    if (m != null) return m.group(1)!;
    final t = tagName.replaceFirst(RegExp(r'^v'), '');
    return t;
  }

  bool _looksLikeSemver(String v) {
    return RegExp(r'^\d+(\.\d+){1,3}$').hasMatch(v.trim());
  }

  Map<String, dynamic>? _pickAsset(
    List<dynamic> assets,
    bool Function(String name) match,
  ) {
    for (final a in assets) {
      final name = (a['name'] as String?) ?? '';
      if (match(name)) return a as Map<String, dynamic>;
    }
    return null;
  }

  /// Prefer PlayTorrio / Android / release APK names over random .apk assets.
  Map<String, dynamic>? _pickAndroidApk(List<dynamic> assets) {
    Map<String, dynamic>? firstApk;
    for (final a in assets) {
      final map = a as Map<String, dynamic>;
      final name = (map['name'] as String?) ?? '';
      if (!name.toLowerCase().endsWith('.apk')) continue;
      firstApk ??= map;
      final n = name.toLowerCase();
      if (n.contains('playtorrio') ||
          n.contains('android') ||
          n.contains('release')) {
        return map;
      }
    }
    return firstApk;
  }

  bool _isNewerVersion(String current, String latest) {
    try {
      final c = _semverParts(current);
      final l = _semverParts(latest);
      for (var i = 0; i < 3; i++) {
        if (l[i] > c[i]) return true;
        if (l[i] < c[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  List<int> _semverParts(String v) {
    final parts = v.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts.take(3).toList();
  }

  Future<void> openDownloadPage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final DateTime publishedAt;
  final bool isMacOS;
  final bool isIOS;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.isMacOS,
    this.isIOS = false,
  });
}
