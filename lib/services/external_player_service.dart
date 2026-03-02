import 'dart:io';
import 'package:flutter/material.dart';
import '../api/settings_service.dart';
import 'android_player_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  EXTERNAL PLAYER SERVICE
//
//  Handles launching video URLs in external players on all platforms.
//  On Android: uses ACTION_VIEW intents with package targeting.
//  On Desktop: uses Process.start with known install paths / PATH lookup.
// ─────────────────────────────────────────────────────────────────────────────

class ExternalPlayerService {
  static final ExternalPlayerService _instance =
      ExternalPlayerService._internal();
  factory ExternalPlayerService() => _instance;
  ExternalPlayerService._internal();

  // ═════════════════════════════════════════════════════════════════════════
  //  PLAYER DEFINITIONS
  // ═════════════════════════════════════════════════════════════════════════

  /// All known external players per platform, in display order.
  static List<ExternalPlayer> get availablePlayers {
    if (Platform.isAndroid || Platform.isIOS) {
      return _mobilePlayers;
    } else if (Platform.isWindows) {
      return _windowsPlayers;
    } else if (Platform.isLinux) {
      return _linuxPlayers;
    } else if (Platform.isMacOS) {
      return _macPlayers;
    }
    return [];
  }

  /// The full list including "Built-in Player" as first option.
  static List<String> get playerNames =>
      ['Built-in Player', ...availablePlayers.map((p) => p.displayName)];

  // ── Mobile (Android / iOS) ─────────────────────────────────────────────

  static final List<ExternalPlayer> _mobilePlayers = [
    ExternalPlayer(
      displayName: 'VLC',
      androidPackage: 'org.videolan.vlc',
      androidExtras: {'title': true},
    ),
    ExternalPlayer(
      displayName: 'MX Player',
      androidPackage: 'com.mxtech.videoplayer.ad',
      androidAltPackages: ['com.mxtech.videoplayer.pro'],
      androidExtras: {'title': true, 'return_result': true},
    ),
    ExternalPlayer(
      displayName: 'mpv-android',
      androidPackage: 'is.xyz.mpv',
    ),
    ExternalPlayer(
      displayName: 'mpv-kt',
      androidPackage: 'live.mehiz.mpvkt',
    ),
    ExternalPlayer(
      displayName: 'Just Player',
      androidPackage: 'com.brouken.player',
    ),
    ExternalPlayer(
      displayName: 'Nova Player',
      androidPackage: 'org.courville.nova',
    ),
    ExternalPlayer(
      displayName: 'KMPlayer',
      androidPackage: 'com.kmplayer',
    ),
    ExternalPlayer(
      displayName: 'nPlayer',
      androidPackage: 'com.newin.nplayer.pro',
    ),
    ExternalPlayer(
      displayName: 'Kodi',
      androidPackage: 'org.xbmc.kodi',
    ),
    ExternalPlayer(
      displayName: 'System Default',
      androidPackage: null, // Shows system chooser
    ),
  ];

  // ── Windows ────────────────────────────────────────────────────────────

  static final List<ExternalPlayer> _windowsPlayers = [
    ExternalPlayer(
      displayName: 'mpv',
      windowsBinary: 'mpv.exe',
      windowsPaths: [
        r'C:\Program Files\mpv\mpv.exe',
        r'C:\Program Files (x86)\mpv\mpv.exe',
        r'C:\ProgramData\chocolatey\bin\mpv.exe',
      ],
      desktopArgs: (url, title, headers) => [
        if (title != null) '--force-media-title=$title',
        if (headers != null)
          '--http-header-fields=${headers.entries.map((e) => '${e.key}: ${e.value}').join(',')}',
        url,
      ],
    ),
    ExternalPlayer(
      displayName: 'VLC',
      windowsBinary: 'vlc.exe',
      windowsPaths: [
        r'C:\Program Files\VideoLAN\VLC\vlc.exe',
        r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
      ],
      windowsRegistryKey: r'HKLM\SOFTWARE\VideoLAN\VLC',
      windowsRegistryValue: 'InstallDir',
      windowsRegistryBinary: 'vlc.exe',
      desktopArgs: (url, title, headers) => [
        if (title != null) '--meta-title=$title',
        if (headers != null && headers.containsKey('Referer'))
          '--http-referrer=${headers['Referer']}',
        if (headers != null && headers.containsKey('User-Agent'))
          '--http-user-agent=${headers['User-Agent']}',
        url,
      ],
    ),
    ExternalPlayer(
      displayName: 'PotPlayer',
      windowsBinary: 'PotPlayerMini64.exe',
      windowsPaths: [
        r'C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe',
        r'C:\Program Files (x86)\DAUM\PotPlayer\PotPlayerMini.exe',
        r'C:\Program Files\PotPlayer\PotPlayerMini64.exe',
      ],
      desktopArgs: (url, title, headers) => [url],
    ),
    ExternalPlayer(
      displayName: 'MPC-HC',
      windowsBinary: 'mpc-hc64.exe',
      windowsPaths: [
        r'C:\Program Files\MPC-HC\mpc-hc64.exe',
        r'C:\Program Files (x86)\MPC-HC\mpc-hc.exe',
        r'C:\Program Files\MPC-HC x64\mpc-hc64.exe',
      ],
      desktopArgs: (url, title, headers) => [url],
    ),
    ExternalPlayer(
      displayName: 'MPC-BE',
      windowsBinary: 'mpc-be64.exe',
      windowsPaths: [
        r'C:\Program Files\MPC-BE x64\mpc-be64.exe',
        r'C:\Program Files (x86)\MPC-BE\mpc-be.exe',
      ],
      desktopArgs: (url, title, headers) => [url],
    ),
    ExternalPlayer(
      displayName: 'SMPlayer',
      windowsBinary: 'smplayer.exe',
      windowsPaths: [
        r'C:\Program Files\SMPlayer\smplayer.exe',
        r'C:\Program Files (x86)\SMPlayer\smplayer.exe',
      ],
      desktopArgs: (url, title, headers) => [url],
    ),
  ];

  // ── Linux ──────────────────────────────────────────────────────────────

  static final List<ExternalPlayer> _linuxPlayers = [
    ExternalPlayer(
      displayName: 'mpv',
      linuxBinary: 'mpv',
      desktopArgs: (url, title, headers) => [
        if (title != null) '--force-media-title=$title',
        if (headers != null)
          '--http-header-fields=${headers.entries.map((e) => '${e.key}: ${e.value}').join(',')}',
        url,
      ],
    ),
    ExternalPlayer(
      displayName: 'VLC',
      linuxBinary: 'vlc',
      desktopArgs: (url, title, headers) => [
        if (title != null) '--meta-title=$title',
        if (headers != null && headers.containsKey('Referer'))
          '--http-referrer=${headers['Referer']}',
        url,
      ],
    ),
    ExternalPlayer(
      displayName: 'Celluloid',
      linuxBinary: 'celluloid',
      desktopArgs: (url, title, headers) => [url],
    ),
    ExternalPlayer(
      displayName: 'Haruna',
      linuxBinary: 'haruna',
      desktopArgs: (url, title, headers) => [url],
    ),
    ExternalPlayer(
      displayName: 'SMPlayer',
      linuxBinary: 'smplayer',
      desktopArgs: (url, title, headers) => [url],
    ),
  ];

  // ── macOS ──────────────────────────────────────────────────────────────

  static final List<ExternalPlayer> _macPlayers = [
    ExternalPlayer(
      displayName: 'IINA',
      macAppPath: '/Applications/IINA.app',
      macBinary: 'iina',
      desktopArgs: (url, title, headers) => [
        if (title != null) '--mpv-force-media-title=$title',
        url,
      ],
    ),
    ExternalPlayer(
      displayName: 'VLC',
      macAppPath: '/Applications/VLC.app',
      macBinary: 'vlc',
      desktopArgs: (url, title, headers) => [
        if (title != null) '--meta-title=$title',
        url,
      ],
    ),
    ExternalPlayer(
      displayName: 'mpv',
      macBinary: 'mpv',
      desktopArgs: (url, title, headers) => [
        if (title != null) '--force-media-title=$title',
        url,
      ],
    ),
  ];

  // ═════════════════════════════════════════════════════════════════════════
  //  CHECK IF SELECTED PLAYER IS EXTERNAL
  // ═════════════════════════════════════════════════════════════════════════

  static Future<bool> isExternalPlayerSelected() async {
    final player = await SettingsService().getExternalPlayer();
    return player != 'Built-in Player';
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  LAUNCH EXTERNAL PLAYER
  // ═════════════════════════════════════════════════════════════════════════

  /// Launch the selected external player with the given URL.
  /// Returns true if launch was successful, false if player not found.
  static Future<bool> launch({
    required String url,
    required String title,
    Map<String, String>? headers,
    BuildContext? context,
  }) async {
    final selectedName = await SettingsService().getExternalPlayer();
    if (selectedName == 'Built-in Player') return false;

    final players = availablePlayers;
    if (players.isEmpty) return false;

    final player = players.firstWhere(
      (p) => p.displayName == selectedName,
      orElse: () => players.first,
    );

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        return await _launchAndroid(player, url, title, headers);
      } else {
        return await _launchDesktop(player, url, title, headers);
      }
    } catch (e) {
      debugPrint('[ExternalPlayer] Error launching ${player.displayName}: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${player.displayName} could not be launched. Is it installed?',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red.shade900,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  // ── Android Launch ─────────────────────────────────────────────────────

  static Future<bool> _launchAndroid(
    ExternalPlayer player,
    String url,
    String title,
    Map<String, String>? headers,
  ) async {
    final Map<String, dynamic> extras = {};
    if (player.androidExtras?.containsKey('title') == true) {
      extras['title'] = title;
    }
    if (player.androidExtras?.containsKey('return_result') == true) {
      extras['return_result'] = true;
    }
    // MX Player supports headers as alternating key/value array
    if (headers != null &&
        headers.isNotEmpty &&
        (player.androidPackage == 'com.mxtech.videoplayer.ad' ||
            player.androidPackage == 'com.mxtech.videoplayer.pro')) {
      final headerList = <String>[];
      headers.forEach((k, v) {
        headerList.add(k);
        headerList.add(v);
      });
      extras['headers'] = headerList;
    }

    // Try main package first, then alternate packages
    final packagesToTry = [
      player.androidPackage,
      ...(player.androidAltPackages ?? []),
    ];

    for (final pkg in packagesToTry) {
      try {
        final success = await AndroidPlayerLauncher.launch(
          url: url,
          packageName: pkg,
          title: title,
          extras: extras.isNotEmpty ? extras : null,
        );
        if (success) return true;
      } catch (e) {
        debugPrint('[ExternalPlayer] Failed with package $pkg: $e');
      }
    }
    return false;
  }

  // ── Desktop Launch ─────────────────────────────────────────────────────

  static Future<bool> _launchDesktop(
    ExternalPlayer player,
    String url,
    String title,
    Map<String, String>? headers,
  ) async {
    final executable = await _findDesktopExecutable(player);
    if (executable == null) {
      debugPrint(
          '[ExternalPlayer] ${player.displayName} not found on this system');
      return false;
    }

    var args = player.desktopArgs?.call(url, title, headers) ?? [url];

    // macOS: when using 'open', prepend -a <AppPath> before user args
    if (Platform.isMacOS && executable == 'open' && player.macAppPath != null) {
      args = ['-a', player.macAppPath!, ...args];
    }

    debugPrint('[ExternalPlayer] Launching: $executable ${args.join(' ')}');
    await Process.start(executable, args, mode: ProcessStartMode.detached);
    return true;
  }

  /// Tries to find the executable for a desktop player.
  static Future<String?> _findDesktopExecutable(ExternalPlayer player) async {
    // 1. Check known install paths
    if (Platform.isWindows && player.windowsPaths != null) {
      for (final path in player.windowsPaths!) {
        if (await File(path).exists()) return path;
      }
      // Also check scoop user directory
      final home = Platform.environment['USERPROFILE'];
      if (home != null && player.windowsBinary != null) {
        final scoopPath =
            '$home\\scoop\\apps\\${player.displayName.toLowerCase()}\\current\\${player.windowsBinary}';
        if (await File(scoopPath).exists()) return scoopPath;
      }
    }

    if (Platform.isLinux && player.linuxBinary != null) {
      // Use 'which' to check PATH
      try {
        final result = await Process.run('which', [player.linuxBinary!]);
        if (result.exitCode == 0) {
          return result.stdout.toString().trim();
        }
      } catch (_) {}
    }

    if (Platform.isMacOS) {
      // Check app bundle — handled specially in _launchDesktop
      if (player.macAppPath != null &&
          await Directory(player.macAppPath!).exists()) {
        return 'open'; // Caller must prepend [-a, appPath] to args
      }
      // Check PATH binary
      if (player.macBinary != null) {
        try {
          final result = await Process.run('which', [player.macBinary!]);
          if (result.exitCode == 0) {
            return result.stdout.toString().trim();
          }
        } catch (_) {}
      }
    }

    // 2. Check Windows registry
    if (Platform.isWindows && player.windowsRegistryKey != null) {
      try {
        final result = await Process.run('reg', [
          'query',
          player.windowsRegistryKey!,
          '/v',
          player.windowsRegistryValue ?? '',
        ]);
        if (result.exitCode == 0) {
          final match = RegExp(r'REG_SZ\s+(.+)')
              .firstMatch(result.stdout.toString());
          if (match != null) {
            final dir = match.group(1)!.trim();
            final fullPath = '$dir\\${player.windowsRegistryBinary ?? player.windowsBinary}';
            if (await File(fullPath).exists()) return fullPath;
          }
        }
      } catch (_) {}
    }

    // 3. Check if binary is in PATH (Windows: where, others: which)
    if (Platform.isWindows && player.windowsBinary != null) {
      try {
        final result = await Process.run('where', [player.windowsBinary!]);
        if (result.exitCode == 0) {
          return result.stdout.toString().trim().split('\n').first.trim();
        }
      } catch (_) {}
    }

    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  EXTERNAL PLAYER MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class ExternalPlayer {
  final String displayName;

  // Android
  final String? androidPackage;
  final List<String>? androidAltPackages;
  final Map<String, dynamic>? androidExtras;

  // Windows
  final String? windowsBinary;
  final List<String>? windowsPaths;
  final String? windowsRegistryKey;
  final String? windowsRegistryValue;
  final String? windowsRegistryBinary;

  // Linux
  final String? linuxBinary;

  // macOS
  final String? macAppPath;
  final String? macBinary;

  // Desktop args builder
  final List<String> Function(
      String url, String? title, Map<String, String>? headers)? desktopArgs;

  const ExternalPlayer({
    required this.displayName,
    this.androidPackage,
    this.androidAltPackages,
    this.androidExtras,
    this.windowsBinary,
    this.windowsPaths,
    this.windowsRegistryKey,
    this.windowsRegistryValue,
    this.windowsRegistryBinary,
    this.linuxBinary,
    this.macAppPath,
    this.macBinary,
    this.desktopArgs,
  });
}
