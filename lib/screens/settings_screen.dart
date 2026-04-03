import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/settings_service.dart';
import '../api/stremio_service.dart';
import '../services/external_player_service.dart';
import '../api/debrid_api.dart';
import '../api/trakt_service.dart';
import '../api/simkl_service.dart';
import '../api/mdblist_service.dart';
import '../services/jackett_service.dart';
import '../services/prowlarr_service.dart';
import '../utils/app_theme.dart';
import '../utils/settings_backup_download.dart';
import '../utils/read_file_path.dart';
import '../platform_flags.dart';
import 'lists_screen.dart';
import 'epg_channel_mapping_screen.dart';
import 'settings_export.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  final StremioService _stremio = StremioService();
  final DebridApi _debrid = DebridApi();
  final JackettService _jackett = JackettService();
  final ProwlarrService _prowlarr = ProwlarrService();
  
  bool _isStreamingMode = false;
  String _externalPlayer = 'Built-in Player';
  String _sortPreference = 'Seeders (High to Low)';
  List<Map<String, dynamic>> _installedAddons = [];
  bool _isInstalling = false;
  
  bool _useDebrid = false;
  String _debridService = 'None';
  final TextEditingController _addonController = TextEditingController();
  final TextEditingController _xmltvEpgUrlController = TextEditingController();
  final TextEditingController _torboxController = TextEditingController();
  
  // Jackett
  final TextEditingController _jackettUrlController = TextEditingController();
  final TextEditingController _jackettApiKeyController = TextEditingController();
  bool _isTestingJackett = false;
  String? _jackettTestResult;
  
  // Prowlarr
  final TextEditingController _prowlarrUrlController = TextEditingController();
  final TextEditingController _prowlarrApiKeyController = TextEditingController();
  bool _isTestingProwlarr = false;
  String? _prowlarrTestResult;
  
  bool _isRDLoggedIn = false;
  String? _rdUserCode;
  Timer? _rdPollTimer;
  
  // Trakt
  final TraktService _trakt = TraktService();
  final TextEditingController _traktClientIdController = TextEditingController();
  final TextEditingController _traktClientSecretController = TextEditingController();
  bool _isTraktLoggedIn = false;
  String? _traktUserCode;
  String? _traktVerifyUrl;
  Timer? _traktPollTimer;
  bool _isTraktSyncing = false;
  String? _traktUsername;
  Map<String, dynamic>? _traktStats;

  // Simkl
  final SimklService _simkl = SimklService();
  bool _isSimklLoggedIn = false;
  String? _simklUserCode;
  String? _simklVerifyUrl;
  Timer? _simklPollTimer;
  bool _isSimklSyncing = false;
  String? _simklUsername;

  // MDBlist
  final MdblistService _mdblist = MdblistService();
  bool _isMdblistConfigured = false;
  final TextEditingController _mdblistApiKeyController = TextEditingController();
  String? _mdblistUsername;

  // Torrent cache
  String _torrentCacheType = 'ram';
  int _torrentRamCacheMb = 200;

  // Light mode
  bool _isLightMode = false;

  // Navbar config
  List<String> _navbarVisible = [];
  List<String> _navbarOrder = [];

  /// `__playtorrio__` or a Stremio addon [baseUrl].
  String _defaultStremioStreamKey = '__auto__';
  bool _continuePlaybackInBackground = true;
  bool _showAndroidPipButton = true;
  bool _autoEnterPipAndroid = false;
  bool _builtinPlayerSubtitlesEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final streaming = await _settings.isStreamingModeEnabled();
    final externalPlayer = await _settings.getExternalPlayer();
    final sort = await _settings.getSortPreference();
    final useDebrid = await _settings.useDebridForStreams();
    final service = await _settings.getDebridService();
    final addons = await _settings.getStremioAddons();
    final torboxKey = await _debrid.getTorBoxKey();
    final rdToken = await _debrid.getRDAccessToken();
    
    // Trakt API app credentials (local / sideload builds)
    final traktPrefs = await SharedPreferences.getInstance();
    _traktClientIdController.text =
        traktPrefs.getString(TraktService.prefsClientIdKey) ?? '';
    _traktClientSecretController.text =
        traktPrefs.getString(TraktService.prefsClientSecretKey) ?? '';

    // Load Trakt status
    final traktLoggedIn = await _trakt.isLoggedIn();
    String? traktUser;
    Map<String, dynamic>? traktStats;
    if (traktLoggedIn) {
      final profile = await _trakt.getUserProfile();
      traktUser = profile?['user']?['username']?.toString() ?? profile?['username']?.toString();
      traktStats = await _trakt.getUserStats();
    }

    // Load Simkl status
    final simklLoggedIn = await _simkl.isLoggedIn();
    String? simklUser;
    if (simklLoggedIn) {
      final profile = await _simkl.getUserProfile();
      simklUser = profile?['name']?.toString();
    }

    // Load MDBlist status
    final mdblistConfigured = await _mdblist.isConfigured();
    String? mdblistUser;
    final mdblistKey = await _mdblist.getApiKey();
    if (mdblistConfigured) {
      final info = await _mdblist.getUserInfo();
      mdblistUser = info?['name']?.toString();
    }

    // Load Jackett settings
    final jackettUrl = await _settings.getJackettBaseUrl();
    final jackettKey = await _settings.getJackettApiKey();
    
    // Load Prowlarr settings
    final prowlarrUrl = await _settings.getProwlarrBaseUrl();
    final prowlarrKey = await _settings.getProwlarrApiKey();

    // Load torrent cache settings
    final cacheType = await _settings.getTorrentCacheType();
    final ramCacheMb = await _settings.getTorrentRamCacheMb();

    // Load light mode
    final lightMode = await _settings.isLightModeEnabled();

    final xmltvEpg = await _settings.getXmltvEpgUrl();
    final defaultAddonUrl = await _settings.getDefaultStremioAddonBaseUrl();
    final bgPlay = await _settings.continuePlaybackInBackground();
    final pipBtn = await _settings.showAndroidPipButton();
    final autoPip = await _settings.autoEnterPipAndroid();
    final builtinSubs = await _settings.getBuiltinPlayerSubtitlesEnabled();

    // Load navbar config
    final navVisible = await _settings.getNavbarConfig();
    // Full order: visible items first, then hidden items
    final allIds = SettingsService.allNavIds;
    final hidden = allIds.where((id) => !navVisible.contains(id)).toList();
    final navOrder = [...navVisible, ...hidden];

    String streamKey;
    if (defaultAddonUrl == null || defaultAddonUrl.isEmpty) {
      streamKey = '__auto__';
    } else if (defaultAddonUrl == SettingsService.streamSourceForcePlayTorrio) {
      streamKey = '__playtorrio__';
    } else {
      streamKey = defaultAddonUrl;
    }
    if (streamKey != '__auto__' &&
        streamKey != '__playtorrio__' &&
        !addons.any((a) => a['baseUrl'] == streamKey)) {
      streamKey = '__auto__';
      await _settings.setDefaultStremioAddonBaseUrl(null);
    }

    if (mounted) {
      setState(() {
        _isStreamingMode = streaming;
        // Ensure saved value is in the current platform's player list
        final validNames = ExternalPlayerService.playerNames;
        _externalPlayer = validNames.contains(externalPlayer)
            ? externalPlayer
            : 'Built-in Player';
        _sortPreference = sort;
        _installedAddons = addons;
        _useDebrid = useDebrid;
        _debridService = service;
        _torboxController.text = torboxKey ?? '';
        _isRDLoggedIn = rdToken != null;
        _isTraktLoggedIn = traktLoggedIn;
        _traktUsername = traktUser;
        _traktStats = traktStats;
        _isSimklLoggedIn = simklLoggedIn;
        _simklUsername = simklUser;
        _isMdblistConfigured = mdblistConfigured;
        _mdblistUsername = mdblistUser;
        _mdblistApiKeyController.text = mdblistKey ?? '';
        
        _jackettUrlController.text = jackettUrl ?? '';
        _jackettApiKeyController.text = jackettKey ?? '';
        
        _prowlarrUrlController.text = prowlarrUrl ?? '';
        _prowlarrApiKeyController.text = prowlarrKey ?? '';
        _torrentCacheType = cacheType;
        _torrentRamCacheMb = ramCacheMb;
        _isLightMode = lightMode;
        _navbarVisible = navVisible;
        _navbarOrder = navOrder;
        _xmltvEpgUrlController.text = xmltvEpg ?? '';
        _defaultStremioStreamKey = streamKey;
        _continuePlaybackInBackground = bgPlay;
        _showAndroidPipButton = pipBtn;
        _autoEnterPipAndroid = autoPip;
        _builtinPlayerSubtitlesEnabled = builtinSubs;
      });
    }
  }

  Future<void> _installAddon() async {
    final url = _addonController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isInstalling = true);

    try {
      final addonData = await _stremio.fetchManifest(url);
      if (addonData != null) {
        await _settings.saveStremioAddon(addonData);
        _addonController.clear();
        await _loadSettings();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Addon installed successfully!')));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to install addon. Check URL.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isInstalling = false);
    }
  }

  void _removeAddon(String baseUrl) async {
    await _settings.removeStremioAddon(baseUrl);
    await _loadSettings();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Addon removed')));
  }

  @override
  void dispose() {
    _addonController.dispose();
    _xmltvEpgUrlController.dispose();
    _torboxController.dispose();
    _jackettUrlController.dispose();
    _jackettApiKeyController.dispose();
    _prowlarrUrlController.dispose();
    _prowlarrApiKeyController.dispose();
    _mdblistApiKeyController.dispose();
    _traktClientIdController.dispose();
    _traktClientSecretController.dispose();
    _rdPollTimer?.cancel();
    _traktPollTimer?.cancel();
    _simklPollTimer?.cancel();
    _jackett.dispose();
    _prowlarr.dispose();
    super.dispose();
  }

  void _startRDLogin() async {
    final data = await _debrid.startRDLogin();
    if (data != null) {
      final userCode = data['user_code'];
      setState(() {
        _rdUserCode = userCode;
      });

      await Clipboard.setData(ClipboardData(text: userCode));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Code $userCode copied to clipboard!')),
        );
      }

      _rdPollTimer?.cancel();
      _rdPollTimer = Timer.periodic(Duration(seconds: data['interval']), (timer) async {
        final success = await _debrid.pollRDCredentials(data['device_code']);
        if (success) {
          timer.cancel();
          setState(() {
            _rdUserCode = null;
            _isRDLoggedIn = true;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Real-Debrid Login Successful!')));
          }
        }
      });

      Future.delayed(Duration(seconds: data['expires_in']), () {
        if (_rdPollTimer?.isActive ?? false) {
          _rdPollTimer?.cancel();
          setState(() => _rdUserCode = null);
        }
      });
    }
  }

  void _logoutRD() async {
    await _debrid.logoutRD();
    setState(() {
      _isRDLoggedIn = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged out of Real-Debrid')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              const SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                floating: true,
                title: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 32, fontFamily: 'Poppins')),
                centerTitle: false,
              ),
              SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildSectionHeader('Backup & Restore'),
                    _buildBackupRestore(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Performance'),
                    _buildFocusableToggle(
                      'Light Mode',
                      'Disables blur effects, glows, shadows, and animations for better FPS on low-end devices.',
                      _isLightMode,
                      (val) async {
                        await _settings.setLightMode(val);
                        setState(() => _isLightMode = val);
                      },
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Playback'),
                    _buildFocusableToggle(
                      'Direct Streaming Mode',
                      'Use direct stream links instead of torrents by default.',
                      _isStreamingMode,
                      (val) async {
                        await _settings.setStreamingMode(val);
                        setState(() => _isStreamingMode = val);
                      },
                    ),
                    _buildFocusableDropdown(
                      'Video Player',
                      'Choose which player opens videos. External players must be installed.',
                      _externalPlayer,
                      ExternalPlayerService.playerNames,
                      (val) async {
                        if (val != null) {
                          await _settings.setExternalPlayer(val);
                          setState(() => _externalPlayer = val);
                        }
                      },
                    ),
                    if (_externalPlayer == 'Built-in Player') ...[
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            Icon(Icons.smart_display_rounded,
                                size: 18, color: AppTheme.primaryColor.withValues(alpha: 0.9)),
                            const SizedBox(width: 8),
                            const Text(
                              'Built-in player',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Background audio/video, PiP (Android), and related options apply only when using the built-in player.',
                          style: TextStyle(fontSize: 12, color: Colors.white38, height: 1.35),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildFocusableToggle(
                        'Continue playback in background',
                        'Off: pause when you leave the app or the window loses focus.',
                        _continuePlaybackInBackground,
                        (val) async {
                          await _settings.setContinuePlaybackInBackground(val);
                          setState(() => _continuePlaybackInBackground = val);
                        },
                      ),
                      _buildFocusableToggle(
                        'Show subtitles',
                        'Off: hides on-screen subtitles and clears the active subtitle track in the built-in player.',
                        _builtinPlayerSubtitlesEnabled,
                        (val) async {
                          await _settings.setBuiltinPlayerSubtitlesEnabled(val);
                          setState(() => _builtinPlayerSubtitlesEnabled = val);
                        },
                      ),
                      if (platformIsAndroid) ...[
                        _buildFocusableToggle(
                          'Picture-in-picture button',
                          'Shows a PiP icon in the player toolbar (Android 8+).',
                          _showAndroidPipButton,
                          (val) async {
                            await _settings.setShowAndroidPipButton(val);
                            setState(() => _showAndroidPipButton = val);
                          },
                        ),
                        _buildFocusableToggle(
                          'Auto-enter PiP when leaving app',
                          'Android 12+: enter PiP when you press Home while playing. Enable PiP for this app in system settings if needed.',
                          _autoEnterPipAndroid,
                          (val) async {
                            await _settings.setAutoEnterPipAndroid(val);
                            setState(() => _autoEnterPipAndroid = val);
                          },
                        ),
                      ],
                    ] else ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
                        child: Text(
                          'Tip: choose “Built-in Player” above to set background playback and Picture-in-picture (Android).',
                          style: TextStyle(fontSize: 12, color: Colors.white38, height: 1.35),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    _buildSectionHeader('Search & Sorting'),
                    _buildFocusableDropdown(
                      'Default Sort Order',
                      'Choose how torrent results are sorted automatically.',
                      _sortPreference,
                      [
                        'Seeders (High to Low)', 'Seeders (Low to High)',
                        'Quality (High to Low)', 'Quality (Low to High)',
                        'Size (High to Low)', 'Size (Low to High)',
                      ],
                      (val) {
                        if (val != null) {
                          _settings.setSortPreference(val);
                          setState(() => _sortPreference = val);
                        }
                      },
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Stremio Addons'),
                    _buildAddonInput(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Default Stremio source'),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(
                        'Auto uses your first installed Stremio addon (recommended) instead of built-in scrapers. Pick PlayTorrio only if you prefer torrent-style sources.',
                        style: TextStyle(fontSize: 13, color: Colors.white54, height: 1.35),
                      ),
                    ),
                    _buildDefaultStremioStreamSource(),
                    const SizedBox(height: 24),
                    _buildXmltvEpgSection(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Jackett'),
                    _buildJackettConfig(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Prowlarr'),
                    _buildProwlarrConfig(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Torrent Engine'),
                    _buildFocusableDropdown(
                      'Cache Type',
                      'Choose where torrent data is cached during streaming.',
                      _torrentCacheType == 'ram' ? 'RAM' : 'Disk',
                      ['RAM', 'Disk'],
                      (val) async {
                        if (val != null) {
                          final type = val == 'RAM' ? 'ram' : 'disk';
                          await _settings.setTorrentCacheType(type);
                          setState(() => _torrentCacheType = type);
                        }
                      },
                    ),
                    if (_torrentCacheType == 'ram')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
                            child: Text(
                              'RAM Cache Size: $_torrentRamCacheMb MB',
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                          Slider(
                            value: _torrentRamCacheMb.toDouble(),
                            min: 50,
                            max: 2048,
                            divisions: 39,
                            activeColor: Colors.deepPurpleAccent,
                            inactiveColor: Colors.white12,
                            label: '$_torrentRamCacheMb MB',
                            onChanged: (val) {
                              setState(() => _torrentRamCacheMb = val.round());
                            },
                            onChangeEnd: (val) async {
                              await _settings.setTorrentRamCacheMb(val.round());
                            },
                          ),
                        ],
                      ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Debrid Support'),
                    _buildFocusableToggle(
                      'Use Debrid for Streams',
                      'Resolve torrents using your debrid account for faster playback.',
                      _useDebrid,
                      (val) async {
                        await _settings.setUseDebridForStreams(val);
                        setState(() => _useDebrid = val);
                      },
                    ),
                    _buildFocusableDropdown(
                      'Debrid Service',
                      'Select your preferred provider.',
                      _debridService,
                      ['None', 'Real-Debrid', 'TorBox'],
                      (val) async {
                        if (val != null) {
                          await _settings.setDebridService(val);
                          setState(() => _debridService = val);
                        }
                      },
                    ),
                    if (_debridService == 'Real-Debrid') _buildRDLogin(),
                    if (_debridService == 'TorBox') _buildTorBoxConfig(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Trakt'),
                    _buildTraktSection(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Simkl'),
                    _buildSimklSection(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('MDBlist'),
                    _buildMdblistSection(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Lists'),
                    _buildListsSection(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Navigation Bar'),
                    _buildNavbarConfig(),
                    const SizedBox(height: 64),
                    const Center(
                      child: Text(
                        'PlayTorrio Native v1.1.2',
                        style: TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Backup & Restore
  // ═══════════════════════════════════════════════════════════════════════════

  bool _isExporting = false;
  bool _isImporting = false;

  Future<void> _exportSettings() async {
    setState(() => _isExporting = true);
    try {
      final data = await _settings.exportAllSettings();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final fileName = 'playtorrio_settings_$timestamp.json';

      if (kIsWeb) {
        triggerJsonDownload(fileName, jsonStr);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Settings download started.')),
          );
        }
      } else {
        final ok = await runNativeSettingsExport(jsonStr, fileName);
        if (ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Settings exported successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importSettings() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Settings',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final String jsonStr;
    if (file.bytes != null) {
      jsonStr = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      jsonStr = await readFilePathAsString(file.path!);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file.')),
        );
      }
      return;
    }

    if (!mounted) return;

    // Confirm before overwriting
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text('Import Settings', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will overwrite all your current settings, including addons, API keys, and preferences. Continue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isImporting = true);
    try {
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      await _settings.importAllSettings(data);
      await _loadSettings(); // Refresh all UI state
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings imported successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Widget _buildBackupRestore() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export or import all your settings, addons, API keys, music liked songs and playlists, and preferences as a JSON file.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isExporting ? null : () => _exportSettings(),
                  icon: _isExporting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_rounded, size: 20),
                  label: const Text('Export'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isImporting ? null : () => _importSettings(),
                  icon: _isImporting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_rounded, size: 20),
                  label: const Text('Import'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 2,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Navbar Configuration
  // ═══════════════════════════════════════════════════════════════════════════

  static const Map<String, Map<String, dynamic>> _navMeta = {
    'home':         {'icon': Icons.home,                       'label': 'Home'},
    'discover':     {'icon': Icons.explore,                    'label': 'Discover'},
    'search':       {'icon': Icons.search,                     'label': 'Search'},
    'mylist':       {'icon': Icons.bookmark,                   'label': 'My List'},
    'magnet':       {'icon': Icons.link_rounded,               'label': 'Magnet'},
    'live_matches': {'icon': Icons.live_tv_rounded,           'label': 'TV Channels'},
    'iptv':         {'icon': Icons.live_tv,                    'label': 'IPTV'},
    'audiobooks':   {'icon': Icons.menu_book,                  'label': 'Audiobooks'},
    'books':        {'icon': Icons.import_contacts_rounded,    'label': 'Books'},
    'music':        {'icon': Icons.music_note,                 'label': 'Music'},
    'comics':       {'icon': Icons.auto_stories,               'label': 'Comics'},
    'manga':        {'icon': Icons.book,                       'label': 'Manga'},
    'jellyfin':     {'icon': Icons.dns_rounded,                'label': 'Jellyfin'},
    'anime':        {'icon': Icons.play_circle_filled,         'label': 'Anime'},
  };

  void _saveNavbarConfig() {
    final visible = _navbarOrder.where((id) => _navbarVisible.contains(id)).toList();
    _settings.setNavbarConfig(visible);
  }

  Widget _buildNavbarConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Show, hide, and reorder navigation tabs. Drag to reorder. Settings is always visible.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
          ),
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _navbarOrder.length,
          proxyDecorator: (child, index, animation) {
            return Material(
              color: Colors.transparent,
              child: child,
            );
          },
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = _navbarOrder.removeAt(oldIndex);
              _navbarOrder.insert(newIndex, item);
            });
            _saveNavbarConfig();
          },
          itemBuilder: (context, index) {
            final id = _navbarOrder[index];
            final meta = _navMeta[id]!;
            final isVisible = _navbarVisible.contains(id);

            return Container(
              key: ValueKey(id),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: isVisible
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: Icon(
                  meta['icon'] as IconData,
                  color: isVisible ? Colors.white : Colors.white24,
                  size: 22,
                ),
                title: Text(
                  meta['label'] as String,
                  style: TextStyle(
                    color: isVisible ? Colors.white : Colors.white38,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: isVisible,
                      activeTrackColor: AppTheme.primaryColor,
                      onChanged: (val) {
                        setState(() {
                          if (val) {
                            _navbarVisible.add(id);
                          } else {
                            _navbarVisible.remove(id);
                          }
                        });
                        _saveNavbarConfig();
                      },
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.drag_handle, color: Colors.white24, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Settings row — always visible, not reorderable
        Container(
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
          ),
          child: ListTile(
            leading: const Icon(Icons.settings, color: AppTheme.primaryColor, size: 22),
            title: const Text(
              'Settings',
              style: TextStyle(color: AppTheme.primaryColor, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, color: Colors.white.withValues(alpha: 0.2), size: 16),
                const SizedBox(width: 8),
                Text('Always visible', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultStremioStreamSource() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: (_defaultStremioStreamKey == '__auto__' ||
                    _defaultStremioStreamKey == '__playtorrio__' ||
                    _installedAddons.any((a) => a['baseUrl'] == _defaultStremioStreamKey))
                ? _defaultStremioStreamKey
                : '__auto__',
            isExpanded: true,
            hint: const Text('Choose default…', style: TextStyle(color: Colors.white38)),
            dropdownColor: const Color(0xFF1A0B2E),
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            items: [
              const DropdownMenuItem(
                value: '__auto__',
                child: Text('Auto — Stremio addon first'),
              ),
              const DropdownMenuItem(
                value: '__playtorrio__',
                child: Text('PlayTorrio (built-in / torrents)'),
              ),
              ..._installedAddons.map(
                (a) => DropdownMenuItem(
                  value: a['baseUrl'] as String,
                  child: Text(
                    a['name']?.toString() ?? 'Addon',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await _settings.setDefaultStremioAddonBaseUrl(
                v == '__auto__' ? null : v,
              );
              if (mounted) setState(() => _defaultStremioStreamKey = v);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildXmltvEpgSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TV Guide EPG (XMLTV)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Optional. When Stremio channels have no built-in schedule, the TV Guide loads programmes from this URL (XML or gzipped XML). Channel ids in the file should match each channel\'s tvgId when possible.',
            style: TextStyle(fontSize: 13, color: Colors.white54, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _xmltvEpgUrlController,
            decoration: InputDecoration(
              hintText: 'https://example.com/epg.xml',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onSubmitted: (_) => _saveXmltvEpgUrl(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _saveXmltvEpgUrl(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save EPG URL'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await _settings.setXmltvEpgUrl(null);
                    if (mounted) {
                      setState(() => _xmltvEpgUrlController.clear());
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('EPG URL cleared')),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EpgChannelMappingScreen()),
                );
              },
              icon: const Icon(Icons.link_rounded, size: 20),
              label: const Text('Match EPG channels to Live TV'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveXmltvEpgUrl() async {
    final url = _xmltvEpgUrlController.text.trim();
    await _settings.setXmltvEpgUrl(url.isEmpty ? null : url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(url.isEmpty ? 'EPG URL cleared' : 'TV Guide EPG URL saved')),
      );
    }
  }

  Widget _buildAddonInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Install Stremio Addon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addonController,
                  decoration: InputDecoration(
                    hintText: 'stremio://... or https://...',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isInstalling ? null : () => _installAddon(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isInstalling 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Install', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (_installedAddons.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('INSTALLED ADDONS', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 12),
            ..._installedAddons.map((addon) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: ListTile(
                leading: addon['icon'].toString().isNotEmpty 
                  ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(addon['icon'], width: 32, height: 32, errorBuilder: (c,e,s) => const Icon(Icons.extension)))
                  : const Icon(Icons.extension, color: AppTheme.primaryColor),
                title: Text(addon['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(addon['baseUrl'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white38)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => _removeAddon(addon['baseUrl']),
                ),
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildRDLogin() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isRDLoggedIn)
            ElevatedButton.icon(
              onPressed: _logoutRD,
              icon: const Icon(Icons.logout),
              label: const Text('Logout from Real-Debrid'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                foregroundColor: Colors.redAccent,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          else if (_rdUserCode != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  const Text('Enter this code at real-debrid.com/device:'),
                  const SizedBox(height: 8),
                  Text(_rdUserCode!, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.primaryColor, letterSpacing: 4)),
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(color: AppTheme.primaryColor, backgroundColor: Colors.white10),
                ],
              ),
            ),
          ] else
            ElevatedButton.icon(
              onPressed: _startRDLogin,
              icon: const Icon(Icons.login),
              label: const Text('Login with Real-Debrid'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTorBoxConfig() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('API Key', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _torboxController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Enter TorBox API Key',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () async {
                  await _debrid.saveTorBoxKey(_torboxController.text);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TorBox API Key Saved!')));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJackettConfig() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Base URL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _jackettUrlController,
            decoration: InputDecoration(
              hintText: 'http://localhost:9117',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (_) => setState(() => _jackettTestResult = null),
          ),
          const SizedBox(height: 16),
          const Text('API Key', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _jackettApiKeyController,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Enter Jackett API Key',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (_) => setState(() => _jackettTestResult = null),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isTestingJackett ? null : () => _testJackettConnection(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isTestingJackett
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Test Connection', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _saveJackettSettings(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          if (_jackettTestResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _jackettTestResult!.startsWith('✅')
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _jackettTestResult!.startsWith('✅')
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                _jackettTestResult!,
                style: TextStyle(
                  color: _jackettTestResult!.startsWith('✅') ? Colors.green : Colors.red,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProwlarrConfig() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Base URL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _prowlarrUrlController,
            decoration: InputDecoration(
              hintText: 'http://localhost:9696',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (_) => setState(() => _prowlarrTestResult = null),
          ),
          const SizedBox(height: 16),
          const Text('API Key', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _prowlarrApiKeyController,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Enter Prowlarr API Key',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (_) => setState(() => _prowlarrTestResult = null),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isTestingProwlarr ? null : () => _testProwlarrConnection(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isTestingProwlarr
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Test Connection', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _saveProwlarrSettings(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          if (_prowlarrTestResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _prowlarrTestResult!.startsWith('✅')
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _prowlarrTestResult!.startsWith('✅')
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                _prowlarrTestResult!,
                style: TextStyle(
                  color: _prowlarrTestResult!.startsWith('✅') ? Colors.green : Colors.red,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _testJackettConnection() async {
    final url = _jackettUrlController.text.trim();
    final apiKey = _jackettApiKeyController.text.trim();

    if (url.isEmpty || apiKey.isEmpty) {
      setState(() => _jackettTestResult = '❌ Please enter both Base URL and API Key');
      return;
    }

    setState(() {
      _isTestingJackett = true;
      _jackettTestResult = null;
    });

    try {
      final result = await _jackett.testConnection(url, apiKey);
      if (mounted) {
        setState(() {
          _jackettTestResult = result.message;
          _isTestingJackett = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _jackettTestResult = '❌ Error: $e';
          _isTestingJackett = false;
        });
      }
    }
  }

  Future<void> _saveJackettSettings() async {
    final url = _jackettUrlController.text.trim();
    final apiKey = _jackettApiKeyController.text.trim();

    await _settings.setJackettBaseUrl(url);
    await _settings.setJackettApiKey(apiKey);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jackett settings saved!')),
      );
    }
  }

  Future<void> _testProwlarrConnection() async {
    final url = _prowlarrUrlController.text.trim();
    final apiKey = _prowlarrApiKeyController.text.trim();

    if (url.isEmpty || apiKey.isEmpty) {
      setState(() => _prowlarrTestResult = '❌ Please enter both Base URL and API Key');
      return;
    }

    setState(() {
      _isTestingProwlarr = true;
      _prowlarrTestResult = null;
    });

    try {
      final result = await _prowlarr.testConnection(url, apiKey);
      if (mounted) {
        setState(() {
          _prowlarrTestResult = result.message;
          _isTestingProwlarr = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _prowlarrTestResult = '❌ Error: $e';
          _isTestingProwlarr = false;
        });
      }
    }
  }

  Future<void> _saveProwlarrSettings() async {
    final url = _prowlarrUrlController.text.trim();
    final apiKey = _prowlarrApiKeyController.text.trim();

    await _settings.setProwlarrBaseUrl(url);
    await _settings.setProwlarrApiKey(apiKey);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prowlarr settings saved!')),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Trakt
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _saveTraktApiCredentials() async {
    final id = _traktClientIdController.text.trim();
    final secret = _traktClientSecretController.text.trim();
    if (id.isEmpty || secret.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter both Trakt Client ID and Client Secret'),
          ),
        );
      }
      return;
    }
    await _trakt.setApiCredentials(clientId: id, clientSecret: secret);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trakt API credentials saved')),
      );
    }
  }

  void _startTraktLogin() async {
    if (!await _trakt.hasApiCredentials()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Add your Trakt Client ID and Secret above (from trakt.tv/oauth/apps), then tap Login again.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    final data = await _trakt.startDeviceAuth();
    if (data == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Trakt did not return a device code. Check your Client ID and network, or try again.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final userCode = data['user_code'] as String;
    final verifyUrl = data['verification_url'] as String;
    final interval = (data['interval'] as int?) ?? 5;
    final expiresIn = (data['expires_in'] as int?) ?? 600;
    final deviceCode = data['device_code'] as String;

    setState(() {
      _traktUserCode = userCode;
      _traktVerifyUrl = verifyUrl;
    });

    await Clipboard.setData(ClipboardData(text: userCode));

    // Auto-open the verification URL in the default browser
    final uri = Uri.parse(verifyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Code $userCode copied! Opening $verifyUrl...')),
      );
    }

    _traktPollTimer?.cancel();
    _traktPollTimer = Timer.periodic(Duration(seconds: interval), (timer) async {
      final result = await _trakt.pollForToken(deviceCode);
      if (result == 'success') {
        timer.cancel();
        // Fetch username
        final profile = await _trakt.getUserProfile();
        final username = profile?['user']?['username']?.toString() ?? profile?['username']?.toString();
        if (mounted) {
          setState(() {
            _traktUserCode = null;
            _traktVerifyUrl = null;
            _isTraktLoggedIn = true;
            _traktUsername = username;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Logged in to Trakt${username != null ? " as $username" : ""}!')),
          );
        }
        // Auto-sync after login
        _syncTrakt();
      } else if (result == 'expired' || result == 'denied') {
        timer.cancel();
        if (mounted) {
          setState(() {
            _traktUserCode = null;
            _traktVerifyUrl = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result == 'denied' ? 'Trakt login denied' : 'Code expired, try again')),
          );
        }
      }
      // 'pending' → keep polling
    });

    // Expire timer
    Future.delayed(Duration(seconds: expiresIn), () {
      if (_traktPollTimer?.isActive ?? false) {
        _traktPollTimer?.cancel();
        if (mounted) {
          setState(() {
            _traktUserCode = null;
            _traktVerifyUrl = null;
          });
        }
      }
    });
  }

  void _logoutTrakt() async {
    await _trakt.logout();
    if (mounted) {
      setState(() {
        _isTraktLoggedIn = false;
        _traktUsername = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged out of Trakt')),
      );
    }
  }

  Future<void> _syncTrakt() async {
    if (_isTraktSyncing) return;
    setState(() => _isTraktSyncing = true);

    try {
      final watchlistCount = await _trakt.importWatchlistToMyList();
      final playbackCount = await _trakt.importPlaybackToWatchHistory();
      final episodesImported = await _trakt.importWatchedEpisodes();
      final exportedCount = await _trakt.exportMyListToWatchlist();
      final episodesExported = await _trakt.exportWatchedEpisodes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Trakt sync done! Imported $watchlistCount watchlist, '
              '$playbackCount playback, $episodesImported episodes. '
              'Exported $exportedCount watchlist, $episodesExported episodes.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Trakt sync error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTraktSyncing = false);
    }
  }

  Widget _buildTraktStatsWidget() {
    final stats = _traktStats!;
    final movies = stats['movies'] as Map<String, dynamic>? ?? {};
    final episodes = stats['episodes'] as Map<String, dynamic>? ?? {};
    final moviesWatched = movies['watched'] as int? ?? 0;
    final moviesMinutes = movies['minutes'] as int? ?? 0;
    final epsWatched = episodes['watched'] as int? ?? 0;
    final epsMinutes = episodes['minutes'] as int? ?? 0;
    final totalHours = ((moviesMinutes + epsMinutes) / 60).round();

    Widget stat(IconData icon, String label, String value) {
      return Column(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 20),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          stat(Icons.movie_rounded, 'Movies', '$moviesWatched'),
          stat(Icons.tv_rounded, 'Episodes', '$epsWatched'),
          stat(Icons.schedule_rounded, 'Hours', '$totalHours'),
        ],
      ),
    );
  }

  Widget _buildTraktSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sync your watchlist and watch history with Trakt.tv',
            style: TextStyle(fontSize: 13, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          Text(
            'Create an app at trakt.tv/oauth/apps (Redirect: urn:ietf:wg:oauth:2.0:oob), then paste Client ID and Secret below. Official builds may already include these.',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.35), height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _traktClientIdController,
            decoration: InputDecoration(
              labelText: 'Trakt Client ID',
              hintText: 'From your Trakt API app',
              labelStyle: const TextStyle(color: Colors.white54),
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _traktClientSecretController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Trakt Client Secret',
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _saveTraktApiCredentials,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save Trakt API credentials'),
            ),
          ),
          const SizedBox(height: 20),

          if (_isTraktLoggedIn) ...[
            // ── Logged in ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connected${_traktUsername != null ? " as $_traktUsername" : ""}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const Text('Trakt.tv', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.sync, color: AppTheme.primaryColor, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Stats
            if (_traktStats != null) ...[
              _buildTraktStatsWidget(),
              const SizedBox(height: 12),
            ],

            // Sync button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isTraktSyncing ? null : () => _syncTrakt(),
                icon: _isTraktSyncing
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync),
                label: Text(_isTraktSyncing ? 'Syncing...' : 'Sync Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Logout button
            ElevatedButton.icon(
              onPressed: _logoutTrakt,
              icon: const Icon(Icons.logout),
              label: const Text('Logout from Trakt'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                foregroundColor: Colors.redAccent,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ] else if (_traktUserCode != null) ...[
            // ── Polling — show code ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Go to the URL below and enter this code:',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _traktUserCode!,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _traktVerifyUrl ?? 'https://trakt.tv/activate',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(
                    color: AppTheme.primaryColor,
                    backgroundColor: Colors.white10,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Waiting for authorization...',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ] else ...[
            // ── Not logged in ──
            ElevatedButton.icon(
              onPressed: _startTraktLogin,
              icon: const Icon(Icons.login),
              label: const Text('Login with Trakt'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Simkl
  // ═══════════════════════════════════════════════════════════════════════

  void _startSimklLogin() async {
    final data = await _simkl.requestPin();
    if (data == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start Simkl login')),
        );
      }
      return;
    }

    final userCode = data['user_code'] as String;
    final verifyUrl = data['verification_url']?.toString() ?? 'https://simkl.com/pin/$userCode';
    final interval = (data['interval'] as int?) ?? 5;
    final expiresIn = (data['expires_in'] as int?) ?? 900;

    setState(() {
      _simklUserCode = userCode;
      _simklVerifyUrl = verifyUrl;
    });

    await Clipboard.setData(ClipboardData(text: userCode));

    final uri = Uri.parse(verifyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Code $userCode copied! Opening $verifyUrl...')),
      );
    }

    _simklPollTimer?.cancel();
    _simklPollTimer = Timer.periodic(Duration(seconds: interval), (timer) async {
      final token = await _simkl.pollForToken(userCode);
      if (token != null) {
        timer.cancel();
        final profile = await _simkl.getUserProfile();
        final username = profile?['name']?.toString();
        if (mounted) {
          setState(() {
            _simklUserCode = null;
            _simklVerifyUrl = null;
            _isSimklLoggedIn = true;
            _simklUsername = username;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Logged in to Simkl${username != null ? " as $username" : ""}!')),
          );
        }
        _syncSimkl();
      }
    });

    Future.delayed(Duration(seconds: expiresIn), () {
      if (_simklPollTimer?.isActive ?? false) {
        _simklPollTimer?.cancel();
        if (mounted) {
          setState(() {
            _simklUserCode = null;
            _simklVerifyUrl = null;
          });
        }
      }
    });
  }

  void _logoutSimkl() async {
    await _simkl.logout();
    if (mounted) {
      setState(() {
        _isSimklLoggedIn = false;
        _simklUsername = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged out of Simkl')),
      );
    }
  }

  Future<void> _syncSimkl() async {
    if (_isSimklSyncing) return;
    setState(() => _isSimklSyncing = true);

    try {
      final watchlistCount = await _simkl.importWatchlistToMyList();
      final episodesImported = await _simkl.importWatchedEpisodes();
      final exportedCount = await _simkl.exportMyListToWatchlist();
      final episodesExported = await _simkl.exportWatchedEpisodes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Simkl sync done! Imported $watchlistCount watchlist, '
              '$episodesImported episodes. '
              'Exported $exportedCount watchlist, $episodesExported episodes.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Simkl sync error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSimklSyncing = false);
    }
  }

  Widget _buildSimklSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sync your watchlist and watch history with Simkl',
            style: TextStyle(fontSize: 13, color: Colors.white54),
          ),
          const SizedBox(height: 16),

          if (_isSimklLoggedIn) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connected${_simklUsername != null ? " as $_simklUsername" : ""}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const Text('Simkl', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.sync, color: AppTheme.primaryColor, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSimklSyncing ? null : () => _syncSimkl(),
                icon: _isSimklSyncing
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync),
                label: Text(_isSimklSyncing ? 'Syncing...' : 'Sync Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _logoutSimkl,
              icon: const Icon(Icons.logout),
              label: const Text('Logout from Simkl'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                foregroundColor: Colors.redAccent,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ] else if (_simklUserCode != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Go to the URL below and enter this code:',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _simklUserCode!,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _simklVerifyUrl ?? 'https://simkl.com/pin',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(
                    color: AppTheme.primaryColor,
                    backgroundColor: Colors.white10,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Waiting for authorization...',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ] else ...[
            ElevatedButton.icon(
              onPressed: _startSimklLogin,
              icon: const Icon(Icons.login),
              label: const Text('Login with Simkl'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MDBlist
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _saveMdblistApiKey() async {
    final key = _mdblistApiKeyController.text.trim();
    if (key.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter an API key')),
        );
      }
      return;
    }

    await _mdblist.setApiKey(key);

    // Validate by fetching user info
    final info = await _mdblist.getUserInfo();
    if (info != null) {
      if (mounted) {
        setState(() {
          _isMdblistConfigured = true;
          _mdblistUsername = info['name']?.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('MDBlist connected${_mdblistUsername != null ? " as $_mdblistUsername" : ""}!')),
        );
      }
    } else {
      await _mdblist.logout();
      if (mounted) {
        setState(() {
          _isMdblistConfigured = false;
          _mdblistUsername = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid MDBlist API key')),
        );
      }
    }
  }

  void _logoutMdblist() async {
    await _mdblist.logout();
    if (mounted) {
      setState(() {
        _isMdblistConfigured = false;
        _mdblistUsername = null;
        _mdblistApiKeyController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MDBlist API key removed')),
      );
    }
  }

  Widget _buildMdblistSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aggregated ratings from IMDb, TMDB, Trakt, Letterboxd, RT, and more',
            style: TextStyle(fontSize: 13, color: Colors.white54),
          ),
          const SizedBox(height: 16),

          if (_isMdblistConfigured) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connected${_mdblistUsername != null ? " as $_mdblistUsername" : ""}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const Text('MDBlist', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _logoutMdblist,
              icon: const Icon(Icons.logout),
              label: const Text('Remove API Key'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                foregroundColor: Colors.redAccent,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ] else ...[
            TextField(
              controller: _mdblistApiKeyController,
              decoration: InputDecoration(
                labelText: 'MDBlist API Key',
                hintText: 'Paste your API key from mdblist.com',
                labelStyle: const TextStyle(color: Colors.white54),
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Colors.white),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _saveMdblistApiKey(),
              icon: const Icon(Icons.save),
              label: const Text('Save API Key'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildListsSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Browse and manage your Trakt and MDBlist custom lists',
            style: TextStyle(fontSize: 13, color: Colors.white54),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const ListsScreen(),
              )),
              icon: const Icon(Icons.list_alt_rounded),
              label: const Text('Manage Lists'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusableToggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return FocusableControl(
      onTap: () => onChanged(!value),
      scaleOnFocus: 1.0, // Disable scaling
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.white54)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusableDropdown(String title, String subtitle, String value, List<String> options, ValueChanged<String?> onChanged) {
    return FocusableControl(
      onTap: () {},
      scaleOnFocus: 1.0, // Disable scaling
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.white54)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButton<String>(
                value: value,
                dropdownColor: const Color(0xFF1A0B2E),
                underline: const SizedBox.shrink(),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryColor),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                selectedItemBuilder: (BuildContext context) {
                  return options.map<Widget>((String item) {
                    return Container(
                      alignment: Alignment.centerLeft,
                      child: Text(item, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    );
                  }).toList();
                },
                items: options.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(color: Colors.white)))).toList(),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
