import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/settings_service.dart';
import '../api/stremio_service.dart';
import '../services/external_player_service.dart';
import '../api/debrid_api.dart';
import '../api/trakt_service.dart';
import '../services/jackett_service.dart';
import '../services/prowlarr_service.dart';
import '../services/app_updater_service.dart';
import '../widgets/update_dialog.dart';
import '../utils/app_theme.dart';
import '../network/play_torrio_network.dart';
import '../platform/android_tv_platform.dart';
import '../services/settings_lan_sync_service.dart';
import '../utils/platform_flags.dart';
import '../platform/android_battery_background.dart';

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
  bool _builtinBackgroundPlay = false;
  bool _builtinPictureInPicture = false;
  bool _builtinEmbeddedSubtitles = true;
  String _sortPreference = 'Seeders (High to Low)';
  List<Map<String, dynamic>> _installedAddons = [];
  List<Map<String, dynamic>> _streamCapabilityAddons = [];
  String _preferredStremioStreamAddon = '';
  bool _stremioAutoPickFirst = false;
  bool _detailsDefaultStremioFirst = true;
  bool _iptvCaptionsEnabled = true;
  bool _iptvLivePlaylistCompact = false;
  bool _socks5Enabled = false;
  bool _isInstalling = false;
  
  bool _useDebrid = false;
  String _debridService = 'None';
  final TextEditingController _addonController = TextEditingController();
  final TextEditingController _torboxController = TextEditingController();
  final TextEditingController _socksHostController = TextEditingController();
  final TextEditingController _socksPortController = TextEditingController(text: '1080');
  final TextEditingController _socksUserController = TextEditingController();
  final TextEditingController _socksPassController = TextEditingController();
  bool _socksPassObscure = true;

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
  bool _isTraktLoggedIn = false;
  String? _traktUserCode;
  String? _traktVerifyUrl;
  Timer? _traktPollTimer;
  bool _isTraktSyncing = false;
  String? _traktUsername;

  bool _isCheckingUpdate = false;
  final AppUpdaterService _updater = AppUpdaterService();

  // Torrent cache
  String _torrentCacheType = 'ram';
  int _torrentRamCacheMb = 200;

  // Navbar config
  List<String> _navbarVisible = [];
  List<String> _navbarOrder = [];

  // LAN settings sync (phone hosts → TV pulls)
  bool _lanHosting = false;
  String _lanHintIp = '';
  int _lanShownPort = 0;
  String _lanShownToken = '';
  bool _lanBusy = false;
  final TextEditingController _lanTvHostController = TextEditingController();
  final TextEditingController _lanTvPortController =
      TextEditingController(text: '${SettingsLanSyncService.defaultPort}');
  final TextEditingController _lanTvTokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (!kIsWeb && SettingsLanSyncService.instance.isHosting) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLanHostingUi());
    }
  }

  Future<void> _syncLanHostingUi() async {
    final svc = SettingsLanSyncService.instance;
    if (!svc.isHosting || !mounted) return;
    final ip = await SettingsLanSyncService.guessLanIPv4() ?? '';
    setState(() {
      _lanHosting = true;
      _lanHintIp = ip;
      _lanShownPort = svc.port;
      _lanShownToken = svc.token ?? '';
    });
  }

  Future<void> _loadSettings() async {
    final streaming = await _settings.isStreamingModeEnabled();
    final externalPlayer = await _settings.getExternalPlayer();
    final sort = await _settings.getSortPreference();
    final useDebrid = await _settings.useDebridForStreams();
    final service = await _settings.getDebridService();
    final addons = await _settings.getStremioAddons();
    final streamCaps = await _stremio.getAddonsForResource('stream');
    var prefStremioAddon = await _settings.getStremioPreferredStreamAddonBaseUrl();
    if (prefStremioAddon.isNotEmpty &&
        !streamCaps.any((a) => a['baseUrl'] == prefStremioAddon)) {
      prefStremioAddon = '';
      await _settings.setStremioPreferredStreamAddonBaseUrl('');
    }
    final stremioAutoPick = await _settings.getStremioAutoPickFirstStream();
    final detailsStremioDefault = await _settings.getDetailsDefaultStremioFirst();
    final iptvCaps = await _settings.getIptvCaptionsEnabled();
    final iptvCompact = await _settings.getIptvLivePlaylistCompact();
    final socks5On = await _settings.getSocks5Enabled();
    final socksHost = await _settings.getSocks5Host();
    final socksPort = await _settings.getSocks5Port();
    final socksUser = await _settings.getSocks5Username();
    final torboxKey = await _debrid.getTorBoxKey();
    final rdToken = await _debrid.getRDAccessToken();
    
    // Load Trakt status
    final traktLoggedIn = await _trakt.isLoggedIn();
    String? traktUser;
    if (traktLoggedIn) {
      final profile = await _trakt.getUserProfile();
      traktUser = profile?['user']?['username']?.toString() ?? profile?['username']?.toString();
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
    final builtinBg = await _settings.getBuiltinPlayerBackgroundPlay();
    final builtinPip = await _settings.getBuiltinPlayerPictureInPicture();
    final builtinEmbSubs =
        await _settings.getBuiltinPlayerEmbeddedSubtitlesDefault();

    // Load navbar config
    final navVisible = await _settings.getNavbarConfig();
    // Full order: visible items first, then hidden items
    final allIds = SettingsService.allNavIds;
    final hidden = allIds.where((id) => !navVisible.contains(id)).toList();
    final navOrder = [...navVisible, ...hidden];

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
        _streamCapabilityAddons = streamCaps;
        _preferredStremioStreamAddon = prefStremioAddon;
        _stremioAutoPickFirst = stremioAutoPick;
        _detailsDefaultStremioFirst = detailsStremioDefault;
        _iptvCaptionsEnabled = iptvCaps;
        _iptvLivePlaylistCompact = iptvCompact;
        _socks5Enabled = socks5On;
        _socksHostController.text = socksHost;
        _socksPortController.text = socksPort.toString();
        _socksUserController.text = socksUser;
        _socksPassController.clear();
        _useDebrid = useDebrid;
        _debridService = service;
        _torboxController.text = torboxKey ?? '';
        _isRDLoggedIn = rdToken != null;
        _isTraktLoggedIn = traktLoggedIn;
        _traktUsername = traktUser;
        
        _jackettUrlController.text = jackettUrl ?? '';
        _jackettApiKeyController.text = jackettKey ?? '';
        
        _prowlarrUrlController.text = prowlarrUrl ?? '';
        _prowlarrApiKeyController.text = prowlarrKey ?? '';
        _torrentCacheType = cacheType;
        _torrentRamCacheMb = ramCacheMb;
        _navbarVisible = navVisible;
        _navbarOrder = navOrder;
        _builtinBackgroundPlay = builtinBg;
        _builtinPictureInPicture = builtinPip;
        _builtinEmbeddedSubtitles = builtinEmbSubs;
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
    if (_preferredStremioStreamAddon == baseUrl) {
      await _settings.setStremioPreferredStreamAddonBaseUrl('');
    }
    await _settings.removeStremioAddon(baseUrl);
    await _loadSettings();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Addon removed')));
  }

  @override
  void dispose() {
    _addonController.dispose();
    _torboxController.dispose();
    _socksHostController.dispose();
    _socksPortController.dispose();
    _socksUserController.dispose();
    _socksPassController.dispose();
    _lanTvHostController.dispose();
    _lanTvPortController.dispose();
    _lanTvTokenController.dispose();
    unawaited(SettingsLanSyncService.instance.stopHosting());
    _jackettUrlController.dispose();
    _jackettApiKeyController.dispose();
    _prowlarrUrlController.dispose();
    _prowlarrApiKeyController.dispose();
    _rdPollTimer?.cancel();
    _traktPollTimer?.cancel();
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
                      _buildFocusableToggle(
                        'Continue playback in background',
                        'Do not pause video when leaving the app (audio may keep playing).',
                        _builtinBackgroundPlay,
                        (val) async {
                          await _settings.setBuiltinPlayerBackgroundPlay(val);
                          setState(() => _builtinBackgroundPlay = val);
                        },
                      ),
                      _buildFocusableToggle(
                        'Picture-in-picture',
                        'Show a PiP button in the built-in player on Android. iOS is not supported yet.',
                        _builtinPictureInPicture,
                        (val) async {
                          await _settings.setBuiltinPlayerPictureInPicture(val);
                          setState(() => _builtinPictureInPicture = val);
                        },
                      ),
                      _buildFocusableToggle(
                        'Load embedded subtitles by default',
                        'Movies, shows, and other built-in playback (not IPTV). Turn off to start with no subtitles; use the subtitle button in the player anytime.',
                        _builtinEmbeddedSubtitles,
                        (val) async {
                          await _settings.setBuiltinPlayerEmbeddedSubtitlesDefault(val);
                          setState(() => _builtinEmbeddedSubtitles = val);
                        },
                      ),
                    ],
                    if (!kIsWeb && showAndroidAutoSettingsDisclaimer) ...[
                      const SizedBox(height: 24),
                      _buildSectionHeader('Android Auto'),
                      _buildAndroidAutoDisclaimer(),
                      const SizedBox(height: 20),
                      _buildSectionHeader('Background on this device'),
                      _buildAndroidBatteryBackgroundTile(),
                    ],
                    const SizedBox(height: 32),
                    _buildSectionHeader('IPTV'),
                    _buildFocusableToggle(
                      'Show captions for IPTV',
                      'Built-in player loads embedded subtitles for live TV and VOD. Turn off to start with subtitles disabled; you can still turn them on from the player.',
                      _iptvCaptionsEnabled,
                      (val) async {
                        await _settings.setIptvCaptionsEnabled(val);
                        setState(() => _iptvCaptionsEnabled = val);
                      },
                    ),
                    _buildFocusableToggle(
                      'Compact Live TV playlist',
                      'Use a horizontal channel strip on Live TV instead of the full list. You can also toggle this from the Live TV screen.',
                      _iptvLivePlaylistCompact,
                      (val) async {
                        await _settings.setIptvLivePlaylistCompact(val);
                        setState(() => _iptvLivePlaylistCompact = val);
                      },
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('SOCKS5 proxy'),
                    _buildSocks5Section(),
                    if (!kIsWeb) ...[
                      const SizedBox(height: 32),
                      if (AndroidTvPlatform.isTv) ...[
                        _buildSectionHeader('Sync from phone (same Wi-Fi)'),
                        _buildLanSyncTvSection(),
                      ] else ...[
                        _buildSectionHeader('Share settings (local network)'),
                        _buildLanSyncHostSection(),
                      ],
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
                    _buildStremioStreamPreferences(),
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
                    _buildSectionHeader('App Updates'),
                    _buildUpdateChecker(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('Navigation Bar'),
                    _buildNavbarConfig(),
                    const SizedBox(height: 64),
                    const Center(
                      child: Text(
                        'PlayTorrio Native v1.0.7',
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

  Widget _buildAndroidBatteryBackgroundTile() {
    return FocusableControl(
      onTap: () async {
        final ok = await AndroidBatteryBackground.openBatteryOptimizationRequest();
        if (!mounted) return;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open battery settings.')),
          );
        }
      },
      scaleOnFocus: 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.battery_charging_full_rounded,
                color: AppTheme.accentColor, size: 22),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Allow background without battery limits',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Opens Android so PlayTorrio is not put to sleep during background playback or torrents. Use this any time streams stop when the screen is off.',
                    style: TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.25)),
          ],
        ),
      ),
    );
  }

  Widget _buildAndroidAutoDisclaimer() {
    final style = TextStyle(
      fontSize: 13,
      color: Colors.white.withValues(alpha: 0.55),
      height: 1.45,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.directions_car_filled_outlined,
                color: AppTheme.primaryColor.withValues(alpha: 0.85),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'PlayTorrio is registered for Android Auto media. When you play music or audiobooks, '
                  'you can control them from the car display. Video does not appear on the Android Auto screen. '
                  'If you watch video on your phone in a vehicle, only when parked safely and legally. Never watch video while driving.',
                  style: style,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Colors.white.withValues(alpha: 0.45),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Apps installed outside the Play Store are often hidden from Android Auto until you allow them: '
                  'open the Android Auto app, find About, then tap Version repeatedly (about 10 times) until developer mode is enabled. '
                  'Open the menu, choose Developer settings, and turn on the option to show apps from unknown or non-Play sources (wording varies). '
                  'Reconnect to the car. Open PlayTorrio once and start Music or an audiobook so the media service runs.',
                  style: style,
                ),
              ),
            ],
          ),
        ],
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
    'live_matches': {'icon': Icons.sports_soccer_rounded,      'label': 'Live Matches'},
    'iptv':         {'icon': Icons.live_tv,                    'label': 'IPTV'},
    'audiobooks':   {'icon': Icons.menu_book,                  'label': 'Audiobooks'},
    'books':        {'icon': Icons.import_contacts_rounded,    'label': 'Books'},
    'music':        {'icon': Icons.music_note,                 'label': 'Music'},
    'comics':       {'icon': Icons.auto_stories,               'label': 'Comics'},
    'manga':        {'icon': Icons.book,                       'label': 'Manga'},
    'jellyfin':     {'icon': Icons.dns_rounded,                'label': 'Jellyfin'},
    'anime':        {'icon': Icons.play_circle_filled,         'label': 'Anime'},
    'arabic':       {'icon': Icons.movie_filter,               'label': 'Arabic'},
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
                onPressed: _isInstalling ? null : _installAddon,
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

  Widget _buildStremioStreamPreferences() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STREAM LINKS (DETAILS PAGE)',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _buildFocusableToggle(
            'Default to Stremio on title details',
            'When opening a title in torrent/details mode, show Stremio addon streams first instead of torrent sources. Turn off to default to PlayTorrio torrents.',
            _detailsDefaultStremioFirst,
            (val) async {
              await _settings.setDetailsDefaultStremioFirst(val);
              setState(() => _detailsDefaultStremioFirst = val);
            },
          ),
          if (_streamCapabilityAddons.isNotEmpty)
            FocusableControl(
              onTap: () {},
              scaleOnFocus: 1.0,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Preferred addon (list first)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'When you use “All” Stremio addons on a title, streams from this addon appear at the top.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.54),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _preferredStremioStreamAddon.isEmpty
                              ? ''
                              : _streamCapabilityAddons.any(
                                      (a) => a['baseUrl'] == _preferredStremioStreamAddon)
                                  ? _preferredStremioStreamAddon
                                  : '',
                          dropdownColor: const Color(0xFF1A0B2E),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppTheme.primaryColor,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text(
                                'Default order',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            ..._streamCapabilityAddons.map(
                              (a) => DropdownMenuItem<String>(
                                value: a['baseUrl'] as String,
                                child: Text(
                                  a['name']?.toString() ?? a['baseUrl'].toString(),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            await _settings.setStremioPreferredStreamAddonBaseUrl(v);
                            setState(() => _preferredStremioStreamAddon = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _buildFocusableToggle(
            'Auto-pick first stream',
            'When Stremio streams finish loading, start the first playable link (resume match is preferred if you have progress).',
            _stremioAutoPickFirst,
            (val) async {
              await _settings.setStremioAutoPickFirstStream(val);
              setState(() => _stremioAutoPickFirst = val);
            },
          ),
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
                  onPressed: _isTestingJackett ? null : _testJackettConnection,
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
                  onPressed: _saveJackettSettings,
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
                  onPressed: _isTestingProwlarr ? null : _testProwlarrConnection,
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
                  onPressed: _saveProwlarrSettings,
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

  void _startTraktLogin() async {
    final data = await _trakt.startDeviceAuth();
    if (data == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start Trakt login')),
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
      final exportedCount = await _trakt.exportMyListToWatchlist();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Trakt sync done! Imported $watchlistCount to My List, '
              '$playbackCount to Continue Watching, '
              'exported $exportedCount to Trakt',
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
          const SizedBox(height: 16),

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

            // Sync button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isTraktSyncing ? null : _syncTrakt,
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

  Widget _buildUpdateChecker() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Check for new versions of PlayTorrio',
            style: TextStyle(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCheckingUpdate ? null : _checkForUpdates,
              icon: _isCheckingUpdate
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.system_update_rounded),
              label: Text(
                _isCheckingUpdate ? 'Checking...' : 'Check for Updates',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _checkForUpdates() async {
    setState(() => _isCheckingUpdate = true);
    
    try {
      final updateInfo = await _updater.checkForUpdates();
      
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
        
        if (updateInfo != null) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => UpdateDialog(updateInfo: updateInfo),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Text('You\'re running the latest version!'),
                ],
              ),
              backgroundColor: Colors.green.withValues(alpha: 0.2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to check for updates: $e'),
            backgroundColor: Colors.red.withValues(alpha: 0.2),
          ),
        );
      }
    }
  }

  InputDecoration _socksFieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  Widget _buildSocks5Section() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
            child: Text(
              'Routes HTTP/HTTPS requests made through Dart\'s http client over SOCKS5 (e.g. APIs, IPTV playlists, scrapers). '
              'Torrent streams and some native players may still bypass this. Fully restart the app after saving.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.35,
              ),
            ),
          ),
          _buildFocusableToggle(
            'Use SOCKS5 proxy',
            'Requires a reachable SOCKS5 server (no auth, or username + password).',
            _socks5Enabled,
            (val) async {
              await _settings.setSocks5Enabled(val);
              setState(() => _socks5Enabled = val);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _socksHostController,
              style: const TextStyle(color: Colors.white),
              decoration: _socksFieldDecoration('Proxy host', hint: '127.0.0.1 or hostname'),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _socksPortController,
              style: const TextStyle(color: Colors.white),
              decoration: _socksFieldDecoration('Port', hint: '1080'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _socksUserController,
              style: const TextStyle(color: Colors.white),
              decoration: _socksFieldDecoration('Username (optional)'),
              textInputAction: TextInputAction.next,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _socksPassController,
              obscureText: _socksPassObscure,
              style: const TextStyle(color: Colors.white),
              decoration: _socksFieldDecoration('Password (optional)', hint: 'Leave blank to keep saved password')
                  .copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _socksPassObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Colors.white38,
                  ),
                  onPressed: () => setState(() => _socksPassObscure = !_socksPassObscure),
                ),
              ),
              textInputAction: TextInputAction.done,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saveSocks5Settings,
                icon: const Icon(Icons.save_outlined, size: 20),
                label: const Text('Save SOCKS5 settings'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSocks5Settings() async {
    final host = _socksHostController.text.trim();
    final port = int.tryParse(_socksPortController.text.trim());
    if (_socks5Enabled && host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a proxy host or turn SOCKS5 off.')),
        );
      }
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid port (1–65535).')),
        );
      }
      return;
    }

    final user = _socksUserController.text.trim();
    final pass = _socksPassController.text;

    await _settings.setSocks5Enabled(_socks5Enabled);
    await _settings.setSocks5Host(host);
    await _settings.setSocks5Port(port);
    await _settings.setSocks5Username(user);

    if (pass.isNotEmpty) {
      await PlayTorrioNetwork.savePassword(pass);
    } else if (user.isEmpty) {
      await PlayTorrioNetwork.clearPassword();
    }

    await PlayTorrioNetwork.refreshFromStorage();
    if (mounted) {
      _socksPassController.clear();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOCKS5 saved. Restart the app so all connections use the new proxy.'),
        ),
      );
    }
  }

  Widget _buildLanSyncHostSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
            child: Text(
              'On your phone or tablet, open PlayTorrio Settings and tap Start hosting. Keep Settings open. '
              'On the TV, enter the IP, port, and token from the phone. Data stays on your local network.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.35,
              ),
            ),
          ),
          if (_lanHosting) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SelectableText(
                'http://${_lanHintIp.isEmpty ? "your-phone-ip" : _lanHintIp}:$_lanShownPort\nToken: $_lanShownToken',
                style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.45),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Stops after 15 minutes or when you leave Settings.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _lanBusy ? null : _stopLanHosting,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop hosting'),
                ),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _lanBusy ? null : _startLanHosting,
                  icon: const Icon(Icons.wifi_tethering, size: 20),
                  label: const Text('Start hosting for TV sync'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _startLanHosting() async {
    setState(() => _lanBusy = true);
    try {
      await SettingsLanSyncService.instance.startHosting();
      final ip = await SettingsLanSyncService.guessLanIPv4() ?? '';
      if (!mounted) return;
      setState(() {
        _lanHosting = true;
        _lanHintIp = ip;
        _lanShownPort = SettingsLanSyncService.instance.port;
        _lanShownToken = SettingsLanSyncService.instance.token ?? '';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start hosting: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _lanBusy = false);
    }
  }

  Future<void> _stopLanHosting() async {
    setState(() => _lanBusy = true);
    await SettingsLanSyncService.instance.stopHosting();
    if (!mounted) return;
    setState(() {
      _lanHosting = false;
      _lanBusy = false;
    });
  }

  Widget _buildLanSyncTvSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
            child: Text(
              'On your phone, open Settings, tap Start hosting for TV sync, then type the address and token shown there.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _lanTvHostController,
              style: const TextStyle(color: Colors.white),
              decoration: _socksFieldDecoration('Phone IP address', hint: '192.168.1.20'),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _lanTvPortController,
              style: const TextStyle(color: Colors.white),
              decoration: _socksFieldDecoration('Port', hint: '${SettingsLanSyncService.defaultPort}'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _lanTvTokenController,
              style: const TextStyle(color: Colors.white),
              decoration: _socksFieldDecoration('Token', hint: '6-digit code from phone'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _lanBusy ? null : _importSettingsFromPhone,
                icon: _lanBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_done_outlined, size: 20),
                label: Text(_lanBusy ? 'Importing...' : 'Import settings from phone'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importSettingsFromPhone() async {
    final host = _lanTvHostController.text.trim();
    final port = int.tryParse(_lanTvPortController.text.trim());
    final token = _lanTvTokenController.text.trim();
    if (host.isEmpty || port == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter your phone IP, port, and token.')),
        );
      }
      return;
    }
    if (port < 1 || port > 65535) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid port (1–65535).')),
        );
      }
      return;
    }
    setState(() => _lanBusy = true);
    try {
      await SettingsLanSyncService.importFromHost(host: host, port: port, token: token);
      await _loadSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Settings imported. Fully restart the app so players and network clients reload configuration.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _lanBusy = false);
    }
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
