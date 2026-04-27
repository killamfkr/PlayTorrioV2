import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import '../utils/app_theme.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class _Match {
  final String id;
  final String title;
  final String category;
  final int date;
  final String? poster;
  final bool popular;
  final String? homeTeam;
  final String? homeBadge;
  final String? awayTeam;
  final String? awayBadge;
  final List<_Source> sources;

  const _Match({
    required this.id,
    required this.title,
    required this.category,
    required this.date,
    this.poster,
    this.popular = false,
    this.homeTeam,
    this.homeBadge,
    this.awayTeam,
    this.awayBadge,
    required this.sources,
  });

  factory _Match.fromJson(Map<String, dynamic> j) {
    final teams = j['teams'] as Map<String, dynamic>?;
    final home  = teams?['home']  as Map<String, dynamic>?;
    final away  = teams?['away']  as Map<String, dynamic>?;
    final srcs  = (j['sources'] as List? ?? [])
        .map((s) => _Source.fromJson(s as Map<String, dynamic>))
        .toList();
    return _Match(
      id:       (j['id'] ?? '').toString(),
      title:    (j['title'] ?? 'Unknown').toString(),
      category: (j['category'] ?? '').toString(),
      date:     (j['date'] as num?)?.toInt() ?? 0,
      poster:   j['poster'] as String?,
      popular:  (j['popular'] as bool?) ?? false,
      homeTeam: home?['name'] as String?,
      homeBadge: home?['badge'] as String?,
      awayTeam: away?['name'] as String?,
      awayBadge: away?['badge'] as String?,
      sources:  srcs,
    );
  }

  String get badgeUrl => homeBadge != null && awayBadge != null
      ? 'https://streamed.pk/api/images/poster/$homeBadge/$awayBadge.webp'
      : (poster != null ? 'https://streamed.pk/api/images/proxy/$poster.webp' : '');
}

class _Source {
  final String source;
  final String id;
  const _Source({required this.source, required this.id});
  factory _Source.fromJson(Map<String, dynamic> j) =>
      _Source(source: (j['source'] ?? '').toString(), id: (j['id'] ?? '').toString());
}

class _Stream {
  final String id;
  final int streamNo;
  final String language;
  final bool hd;
  final String embedUrl;
  final String source;

  const _Stream({
    required this.id,
    required this.streamNo,
    required this.language,
    required this.hd,
    required this.embedUrl,
    required this.source,
  });

  factory _Stream.fromJson(Map<String, dynamic> j) => _Stream(
        id:        (j['id'] ?? '').toString(),
        streamNo:  (j['streamNo'] as num?)?.toInt() ?? 1,
        language:  (j['language'] ?? 'Unknown').toString(),
        hd:        (j['hd'] as bool?) ?? false,
        embedUrl:  (j['embedUrl'] ?? '').toString(),
        source:    (j['source'] ?? '').toString(),
      );
}

class _Sport {
  final String id;
  final String name;
  const _Sport({required this.id, required this.name});
  factory _Sport.fromJson(Map<String, dynamic> j) =>
      _Sport(id: (j['id'] ?? '').toString(), name: (j['name'] ?? '').toString());
}

class _PpvStream {
  final int id;
  final String name;
  final String tag;
  final String? poster;
  final String uriName;
  final int startsAt;
  final int endsAt;
  final bool alwaysLive;
  final String category;
  final String? iframe;
  final bool allowPastStreams;

  const _PpvStream({
    required this.id,
    required this.name,
    required this.tag,
    this.poster,
    required this.uriName,
    required this.startsAt,
    required this.endsAt,
    required this.alwaysLive,
    required this.category,
    this.iframe,
    required this.allowPastStreams,
  });

  factory _PpvStream.fromJson(Map<String, dynamic> j) => _PpvStream(
        id:              (j['id'] as num?)?.toInt() ?? 0,
        name:            (j['name'] ?? '').toString(),
        tag:             (j['tag'] ?? '').toString(),
        poster:          j['poster'] as String?,
        uriName:         (j['uri_name'] ?? '').toString(),
        startsAt:        (j['starts_at'] as num?)?.toInt() ?? 0,
        endsAt:          (j['ends_at'] as num?)?.toInt() ?? 0,
        alwaysLive:      (j['always_live'] as num?)?.toInt() == 1,
        category:        (j['category_name'] ?? '').toString(),
        iframe:          j['iframe'] as String?,
        allowPastStreams: (j['allowpaststreams'] as num?)?.toInt() == 1,
      );

  String get timeLabel {
    if (alwaysLive) return '🔴 Always Live';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now >= startsAt && now <= endsAt) return '🔴 Live Now';
    if (startsAt > now) {
      final dt = DateTime.fromMillisecondsSinceEpoch(startsAt * 1000);
      return '⏰ ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    }
    return '';
  }
}

class _CdnChannel {
  final String name;
  final String code;
  final String url;
  final String image;
  final String status;
  final int viewers;

  const _CdnChannel({
    required this.name,
    required this.code,
    required this.url,
    required this.image,
    required this.status,
    required this.viewers,
  });

  factory _CdnChannel.fromJson(Map<String, dynamic> j) => _CdnChannel(
        name:    (j['name'] ?? '').toString(),
        code:    (j['code'] ?? '').toString(),
        url:     (j['url'] ?? '').toString(),
        image:   (j['image'] ?? '').toString(),
        status:  (j['status'] ?? 'offline').toString(),
        viewers: (j['viewers'] as num?)?.toInt() ?? 0,
      );
}

class _CdnSportEvent {
  final String gameID;
  final String homeTeam;
  final String awayTeam;
  final String homeTeamIMG;
  final String awayTeamIMG;
  final String time;
  final String tournament;
  final String country;
  final String countryIMG;
  final String status;
  final String start;
  final String end;
  final List<_CdnChannel> channels;

  const _CdnSportEvent({
    required this.gameID,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeTeamIMG,
    required this.awayTeamIMG,
    required this.time,
    required this.tournament,
    required this.country,
    required this.countryIMG,
    required this.status,
    required this.start,
    required this.end,
    required this.channels,
  });

  factory _CdnSportEvent.fromJson(Map<String, dynamic> j) => _CdnSportEvent(
        gameID:      (j['gameID'] ?? '').toString(),
        homeTeam:    (j['homeTeam'] ?? '').toString(),
        awayTeam:    (j['awayTeam'] ?? '').toString(),
        homeTeamIMG: (j['homeTeamIMG'] ?? '').toString(),
        awayTeamIMG: (j['awayTeamIMG'] ?? '').toString(),
        time:        (j['time'] ?? '').toString(),
        tournament:  (j['tournament'] ?? '').toString(),
        country:     (j['country'] ?? '').toString(),
        countryIMG:  (j['countryIMG'] ?? '').toString(),
        status:      (j['status'] ?? '').toString(),
        start:       (j['start'] ?? '').toString(),
        end:         (j['end'] ?? '').toString(),
        channels:    (j['channels'] as List? ?? [])
            .map((c) => _CdnChannel.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

// ─── API helpers ──────────────────────────────────────────────────────────────

const _base = 'https://streamed.pk';
const _ua = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'};

Future<List<_Match>> _fetchMatches(String endpoint) async {
  final resp = await http.get(Uri.parse('$_base$endpoint'), headers: _ua)
      .timeout(const Duration(seconds: 12));
  if (resp.statusCode != 200) return [];
  return (jsonDecode(resp.body) as List)
      .map((e) => _Match.fromJson(e as Map<String, dynamic>))
      .toList();
}

Future<List<_Sport>> _fetchSports() async {
  try {
    final resp = await http.get(Uri.parse('$_base/api/sports'), headers: _ua)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];
    return (jsonDecode(resp.body) as List)
        .map((e) => _Sport.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<List<_Stream>> _fetchStreams(String source, String id) async {
  final resp = await http.get(Uri.parse('$_base/api/stream/$source/$id'), headers: _ua)
      .timeout(const Duration(seconds: 12));
  if (resp.statusCode != 200) return [];
  final body = jsonDecode(resp.body);
  if (body is! List) return [];
  return body.map((e) => _Stream.fromJson(e as Map<String, dynamic>)).toList();
}

String _badgeUrl(String badge) => '$_base/api/images/badge/$badge.webp';

Future<List<_PpvStream>> _fetchPpvStreams() async {
  final resp = await http.get(Uri.parse('https://old.ppv.to/api/streams'), headers: _ua)
      .timeout(const Duration(seconds: 12));
  if (resp.statusCode != 200) return [];
  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  final categories = (body['streams'] as List? ?? []);
  final result = <_PpvStream>[];
  for (final cat in categories) {
    final streams = (cat['streams'] as List? ?? []);
    for (final s in streams) {
      try { result.add(_PpvStream.fromJson(s as Map<String, dynamic>)); } catch (_) {}
    }
  }
  return result;
}

Future<List<_CdnChannel>> _fetchCdnChannels() async {
  final resp = await http.get(Uri.parse('https://api.cdn-live.tv/api/v1/channels/?user=cdnlivetv&plan=free'), headers: _ua)
      .timeout(const Duration(seconds: 12));
  if (resp.statusCode != 200) return [];
  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  return ((body['channels'] as List?) ?? [])
      .map((c) => _CdnChannel.fromJson(c as Map<String, dynamic>))
      .toList();
}

Future<List<_CdnSportEvent>> _fetchCdnSports() async {
  final resp = await http.get(Uri.parse('https://api.cdn-live.tv/api/v1/events/sports/?user=cdnlivetv&plan=free'), headers: _ua)
      .timeout(const Duration(seconds: 12));
  if (resp.statusCode != 200) return [];
  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  final cdnData = body['cdn-live-tv'] as Map<String, dynamic>?;
  if (cdnData == null) return [];
  
  final result = <_CdnSportEvent>[];
  for (final key in ['Soccer', 'NFL', 'NBA', 'NHL']) {
    final events = (cdnData[key] as List?) ?? [];
    for (final e in events) {
      try { result.add(_CdnSportEvent.fromJson(e as Map<String, dynamic>)); } catch (_) {}
    }
  }
  return result;
}

// ═════════════════════════════════════════════════════════════════════════════
//  MAIN SCREEN
// ═════════════════════════════════════════════════════════════════════════════

class LiveMatchesScreen extends StatefulWidget {
  const LiveMatchesScreen({super.key});

  @override
  State<LiveMatchesScreen> createState() => _LiveMatchesScreenState();
}

class _LiveMatchesScreenState extends State<LiveMatchesScreen>
    with TickerProviderStateMixin {
  // tabs: All + each sport
  List<_Sport> _sports = [];
  List<_Match> _matches = [];
  bool _loading = true;
  String? _error;

  // 'live' | 'all-today' | 'all'
  _ViewMode _viewMode = _ViewMode.live;

  // selected sport filter ('all' = no filter)
  String _sportFilter = 'all';

  TabController? _tabController;
  _DataProvider _provider = _DataProvider.streamed;
  List<_PpvStream> _ppvStreams = [];
  List<_CdnChannel> _cdnChannels = [];
  List<_CdnSportEvent> _cdnSports = [];
  bool _cdnShowChannels = true; // true = channels, false = sports

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _sportFilter = 'all'; });
    if (_provider == _DataProvider.ppv) {
      await _loadPpv();
      return;
    }
    if (_provider == _DataProvider.cdnLive) {
      await _loadCdn();
      return;
    }
    try {
      final results = await Future.wait([
        _fetchMatches(_endpoint()),
        _fetchSports(),
      ]);
      final matches = results[0] as List<_Match>;
      final sports  = results[1] as List<_Sport>;

      final presentIds = matches.map((m) => m.category).toSet();
      final filteredSports = sports.where((s) => presentIds.contains(s.id)).toList();

      if (mounted) {
        final oldCtrl = _tabController;
        setState(() {
          _tabController = null;
          _matches = matches;
          _sports  = filteredSports;
          _loading = false;
        });
        oldCtrl?.dispose();

        final newCtrl = TabController(length: filteredSports.length + 1, vsync: this);
        newCtrl.addListener(() {
          if (!newCtrl.indexIsChanging) {
            final idx = newCtrl.index;
            setState(() => _sportFilter = idx == 0 ? 'all' : filteredSports[idx - 1].id);
          }
        });
        if (mounted) setState(() => _tabController = newCtrl);
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _loadPpv() async {
    try {
      final streams = await _fetchPpvStreams();
      // Build category tabs from unique categories in streams
      final seenCats = <String>{};
      final cats = <_Sport>[];
      for (final s in streams) {
        if (s.category.isNotEmpty && seenCats.add(s.category)) {
          cats.add(_Sport(id: s.category, name: s.category));
        }
      }
      if (mounted) {
        final oldCtrl = _tabController;
        setState(() {
          _tabController = null;
          _ppvStreams = streams;
          _sports = cats;
          _loading = false;
        });
        oldCtrl?.dispose();
        final newCtrl = TabController(length: cats.length + 1, vsync: this);
        newCtrl.addListener(() {
          if (!newCtrl.indexIsChanging) {
            final idx = newCtrl.index;
            setState(() => _sportFilter = idx == 0 ? 'all' : cats[idx - 1].id);
          }
        });
        if (mounted) setState(() => _tabController = newCtrl);
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _loadCdn() async {
    try {
      final results = await Future.wait([
        _fetchCdnChannels(),
        _fetchCdnSports(),
      ]);
      final channels = results[0] as List<_CdnChannel>;
      final sports = results[1] as List<_CdnSportEvent>;
      
      // Build categories from sports
      final seenCats = <String>{};
      final cats = <_Sport>[];
      for (final s in sports) {
        if (s.tournament.isNotEmpty && seenCats.add(s.tournament)) {
          cats.add(_Sport(id: s.tournament, name: s.tournament));
        }
      }
      
      if (mounted) {
        final oldCtrl = _tabController;
        setState(() {
          _tabController = null;
          _cdnChannels = channels;
          _cdnSports = sports;
          _sports = cats;
          _loading = false;
        });
        oldCtrl?.dispose();
        final newCtrl = TabController(length: cats.length + 1, vsync: this);
        newCtrl.addListener(() {
          if (!newCtrl.indexIsChanging) {
            final idx = newCtrl.index;
            setState(() => _sportFilter = idx == 0 ? 'all' : cats[idx - 1].id);
          }
        });
        if (mounted) setState(() => _tabController = newCtrl);
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  List<_PpvStream> get _filteredPpv => _sportFilter == 'all'
      ? _ppvStreams
      : _ppvStreams.where((s) => s.category == _sportFilter).toList();

  String _endpoint() {
    switch (_viewMode) {
      case _ViewMode.live:    return '/api/matches/live';
      case _ViewMode.today:   return '/api/matches/all-today';
      case _ViewMode.all:     return '/api/matches/all';
    }
  }

  void _switchMode(_ViewMode mode) {
    _sportFilter = 'all';
    _viewMode = mode;
    _load();
  }

  List<_Match> get _filtered => _sportFilter == 'all'
      ? _matches
      : _matches.where((m) => m.category == _sportFilter).toList();

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildProviderBar(),
            if (_provider == _DataProvider.streamed) _buildModeBar(),
            if (_tabController != null && _sports.isNotEmpty) _buildSportTabs(),
            const SizedBox(height: 4),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 12),
      child: Row(
        children: [
          const Icon(Icons.sports_soccer_rounded, color: AppTheme.primaryColor, size: 28),
          const SizedBox(width: 10),
          const Text(
            'Live Matches',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  Widget _buildProviderBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          _ModeChip(
            label: '📡 Streamed.pk',
            active: _provider == _DataProvider.streamed,
            onTap: () {
              if (_provider == _DataProvider.streamed) return;
              setState(() { _provider = _DataProvider.streamed; });
              _load();
            },
          ),
          const SizedBox(width: 8),
          _ModeChip(
            label: '🎬 PPV.to',
            active: _provider == _DataProvider.ppv,
            onTap: () {
              if (_provider == _DataProvider.ppv) return;
              setState(() { _provider = _DataProvider.ppv; });
              _load();
            },
          ),
          const SizedBox(width: 8),
          _ModeChip(
            label: '📺 CDN Live',
            active: _provider == _DataProvider.cdnLive,
            onTap: () {
              if (_provider == _DataProvider.cdnLive) return;
              setState(() { _provider = _DataProvider.cdnLive; });
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          _ModeChip(label: '🔴 Live',   active: _viewMode == _ViewMode.live,  onTap: () => _switchMode(_ViewMode.live)),
          const SizedBox(width: 8),
          _ModeChip(label: '📅 Today',  active: _viewMode == _ViewMode.today, onTap: () => _switchMode(_ViewMode.today)),
          const SizedBox(width: 8),
          _ModeChip(label: '📋 All',    active: _viewMode == _ViewMode.all,   onTap: () => _switchMode(_ViewMode.all)),
        ],
      ),
    );
  }

  Widget _buildSportTabs() {
    final tabs = [
      const Tab(text: 'All'),
      ..._sports.map((s) => Tab(text: s.name)),
    ];
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      indicatorColor: AppTheme.primaryColor,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white38,
      tabAlignment: TabAlignment.start,
      dividerColor: Colors.white12,
      tabs: tabs,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            ),
          ],
        ),
      );
    }
    if (_provider == _DataProvider.ppv) return _buildPpvBody();
    if (_provider == _DataProvider.cdnLive) return _buildCdnBody();

    final matches = _filtered;
    if (matches.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_rounded, color: Colors.white24, size: 64),
            SizedBox(height: 16),
            Text('No matches right now', style: TextStyle(color: Colors.white38, fontSize: 16)),
          ],
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final crossCount = (constraints.maxWidth / 300).floor().clamp(1, 6);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          mainAxisExtent: 190,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: matches.length,
        itemBuilder: (context, i) => _MatchCard(
          match: matches[i],
          onTap: () => _openSourceSheet(matches[i]),
        ),
      );
    });
  }

  Widget _buildPpvBody() {
    final streams = _filteredPpv;
    if (streams.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_rounded, color: Colors.white24, size: 64),
            SizedBox(height: 16),
            Text('No streams available', style: TextStyle(color: Colors.white38, fontSize: 16)),
          ],
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final crossCount = (constraints.maxWidth / 300).floor().clamp(1, 6);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossCount,
          mainAxisExtent: 200,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: streams.length,
        itemBuilder: (context, i) => _PpvMatchCard(
          stream: streams[i],
          onTap: () => _openPpvStream(streams[i]),
        ),
      );
    });
  }

  Widget _buildCdnBody() {
    if (_cdnShowChannels) {
      final channels = _cdnChannels.where((c) => c.status == 'online').toList();
      if (channels.isEmpty) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tv_rounded, color: Colors.white24, size: 64),
              SizedBox(height: 16),
              Text('No channels available', style: TextStyle(color: Colors.white38, fontSize: 16)),
            ],
          ),
        );
      }
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                _ModeChip(label: '📺 Channels', active: _cdnShowChannels, onTap: () => setState(() => _cdnShowChannels = true)),
                const SizedBox(width: 8),
                _ModeChip(label: '⚽ Sports', active: !_cdnShowChannels, onTap: () => setState(() => _cdnShowChannels = false)),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final crossCount = (constraints.maxWidth / 280).floor().clamp(1, 6);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  mainAxisExtent: 160,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: channels.length,
                itemBuilder: (context, i) => _CdnChannelCard(
                  channel: channels[i],
                  onTap: () => _openCdnChannel(channels[i]),
                ),
              );
            }),
          ),
        ],
      );
    } else {
      final sports = _sportFilter == 'all'
          ? _cdnSports
          : _cdnSports.where((s) => s.tournament == _sportFilter).toList();
      if (sports.isEmpty) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sports_rounded, color: Colors.white24, size: 64),
              SizedBox(height: 16),
              Text('No sports events available', style: TextStyle(color: Colors.white38, fontSize: 16)),
            ],
          ),
        );
      }
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                _ModeChip(label: '📺 Channels', active: _cdnShowChannels, onTap: () => setState(() => _cdnShowChannels = true)),
                const SizedBox(width: 8),
                _ModeChip(label: '⚽ Sports', active: !_cdnShowChannels, onTap: () => setState(() => _cdnShowChannels = false)),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final crossCount = (constraints.maxWidth / 300).floor().clamp(1, 6);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  mainAxisExtent: 200,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: sports.length,
                itemBuilder: (context, i) => _CdnSportCard(
                  event: sports[i],
                  onTap: () => _openCdnSportEvent(sports[i]),
                ),
              );
            }),
          ),
        ],
      );
    }
  }

  void _openCdnChannel(_CdnChannel channel) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _CdnPlayerScreen(url: channel.url, title: channel.name),
    ));
  }

  void _openCdnSportEvent(_CdnSportEvent event) {
    if (event.channels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No channels available for this event')),
      );
      return;
    }
    if (event.channels.length == 1) {
      _openCdnChannel(event.channels.first);
      return;
    }
    // Show channel selection
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CdnChannelSheet(
        event: event,
        onChannelSelected: (ch) {
          Navigator.pop(context);
          _openCdnChannel(ch);
        },
      ),
    );
  }

  void _openPpvStream(_PpvStream s) {
    if (s.iframe == null || s.iframe!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stream not yet available for this event')),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _PpvPlayerScreen(stream: s),
    ));
  }

  // ── select source → streams ───────────────────────────────────────────────

  Future<void> _openSourceSheet(_Match match) async {
    if (match.sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sources available for this match')),
      );
      return;
    }

    // If only one source, skip straight to streams
    if (match.sources.length == 1) {
      _loadStreamsForSource(match, match.sources.first);
      return;
    }

    // Multiple sources → pick one
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SourceSheet(
        match: match,
        onSourceSelected: (src) {
          Navigator.pop(context);
          _loadStreamsForSource(match, src);
        },
      ),
    );
  }

  Future<void> _loadStreamsForSource(_Match match, _Source source) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
    );
    try {
      final streams = await _fetchStreams(source.source, source.id);
      if (!mounted) return;
      Navigator.pop(context); // close loader
      if (streams.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No streams found for this source')),
        );
        return;
      }
      _openStreamSheet(match, streams);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _openStreamSheet(_Match match, List<_Stream> streams) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StreamSheet(
        match: match,
        streams: streams,
        onStreamSelected: (stream) {
          Navigator.pop(context);
          _openPlayer(match, stream);
        },
      ),
    );
  }

  void _openPlayer(_Match match, _Stream stream) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LivePlayerScreen(match: match, stream: stream),
      ),
    );
  }
}

enum _ViewMode { live, today, all }
enum _DataProvider { streamed, ppv, cdnLive }

// ─── Chips ────────────────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModeChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.primaryColor : Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? AppTheme.primaryColor : Colors.white24, width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? Colors.white : Colors.white60,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                fontSize: 13)),
      ),
    );
  }
}

// ─── Match Card ───────────────────────────────────────────────────────────────

class _MatchCard extends StatefulWidget {
  final _Match match;
  final VoidCallback onTap;
  const _MatchCard({required this.match, required this.onTap});

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final hasTeams = m.homeTeam != null && m.awayTeam != null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _hovered ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: _hovered ? AppTheme.primaryColor.withValues(alpha: 0.6) : Colors.white12,
              width: 1.5,
            ),
            boxShadow: _hovered
                ? [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 2)]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                // background poster if available
                if (m.badgeUrl.isNotEmpty)
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: m.badgeUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                // dark overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.black.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                  ),
                ),
                // content
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // team badges row
                      if (hasTeams) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _TeamBadge(badge: m.homeBadge, name: m.homeTeam!),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('VS',
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 2)),
                            ),
                            _TeamBadge(badge: m.awayBadge, name: m.awayTeam!),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      // title
                      Text(
                        m.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                // LIVE badge top-right
                Positioned(
                  top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('● LIVE',
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
                // sport category badge top-left
                Positioned(
                  top: 10, left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(m.category.toUpperCase(),
                        style: const TextStyle(color: Colors.white60, fontSize: 9, letterSpacing: 0.8)),
                  ),
                ),
                // play overlay on hover
                if (_hovered)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.85),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamBadge extends StatelessWidget {
  final String? badge;
  final String name;
  const _TeamBadge({required this.badge, required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.white12,
          child: badge != null && badge!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: _badgeUrl(badge!),
                  width: 38, height: 38, fit: BoxFit.contain,
                  errorWidget: (_, _, _) => Text(
                    name.isNotEmpty ? name[0] : '?',
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                  ),
                )
              : Text(name.isNotEmpty ? name[0] : '?',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 9.5)),
        ),
      ],
    );
  }
}

// ─── PPV Match Card ───────────────────────────────────────────────────────────

class _PpvMatchCard extends StatefulWidget {
  final _PpvStream stream;
  final VoidCallback onTap;
  const _PpvMatchCard({required this.stream, required this.onTap});

  @override
  State<_PpvMatchCard> createState() => _PpvMatchCardState();
}

class _PpvMatchCardState extends State<_PpvMatchCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stream;
    final hasIframe = s.iframe != null && s.iframe!.isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _hovered ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: _hovered ? AppTheme.primaryColor.withValues(alpha: 0.6) : Colors.white12,
              width: 1.5,
            ),
            boxShadow: _hovered
                ? [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 2)]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                // poster background
                if (s.poster != null && s.poster!.isNotEmpty)
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: s.poster!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                // dark gradient overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.black.withValues(alpha: 0.90),
                        ],
                      ),
                    ),
                  ),
                ),
                // content
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        s.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (s.tag.isNotEmpty) ...[  
                        const SizedBox(height: 6),
                        Text(s.tag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                      ],
                    ],
                  ),
                ),
                // time label top-right
                if (s.timeLabel.isNotEmpty)
                  Positioned(
                    top: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: s.timeLabel.contains('Live') ? Colors.red.shade700 : Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(s.timeLabel,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
                // category top-left
                Positioned(
                  top: 10, left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(s.category.toUpperCase(),
                        style: const TextStyle(color: Colors.white60, fontSize: 9, letterSpacing: 0.8)),
                  ),
                ),
                // no iframe warning bottom
                if (!hasIframe)
                  Positioned(
                    bottom: 8, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Not yet available',
                            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                // play overlay on hover
                if (_hovered && hasIframe)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.85),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── PPV WebView Player ───────────────────────────────────────────────────────

class _PpvPlayerScreen extends StatefulWidget {
  final _PpvStream stream;
  const _PpvPlayerScreen({required this.stream});

  @override
  State<_PpvPlayerScreen> createState() => _PpvPlayerScreenState();
}

class _PpvPlayerScreenState extends State<_PpvPlayerScreen> {
  bool _loading = true;
  bool _isFullscreen = false;

  void _enterFullscreen() async {
    setState(() => _isFullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
  }

  void _exitFullscreen() async {
    setState(() => _isFullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final embedUrl = widget.stream.iframe!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullscreen ? null : AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.stream.name,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.teal)),
                child: const Text('PPV.to', style: TextStyle(color: Colors.teal, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              disableDefaultErrorPage: true,
              supportMultipleWindows: false,
            ),
            onLoadStart: (_, _) => setState(() => _loading = true),
            onLoadStop:  (_, _) => setState(() => _loading = false),
            onEnterFullscreen: (_) => _enterFullscreen(),
            onExitFullscreen:  (_) => _exitFullscreen(),
            shouldOverrideUrlLoading: (ctrl, action) async {
              final url = action.request.url?.toString() ?? '';
              final embedHost = Uri.tryParse(embedUrl)?.host ?? '';
              if (embedHost.isNotEmpty && !url.contains(embedHost)) {
                http.get(Uri.parse(url), headers: {
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                      'AppleWebKit/537.36 (KHTML, like Gecko) '
                      'Chrome/122.0.0.0 Safari/537.36',
                  'Referer': embedUrl,
                }).catchError((_) => http.Response('', 200));
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
        ],
      ),
    );
  }
}

// ─── Source sheet ─────────────────────────────────────────────────────────────

class _SourceSheet extends StatelessWidget {
  final _Match match;
  final void Function(_Source) onSourceSelected;
  const _SourceSheet({required this.match, required this.onSourceSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Text(match.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Choose a stream source:', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          ...match.sources.map((src) => ListTile(
            onTap: () => onSourceSelected(src),
            leading: const Icon(Icons.stream_rounded, color: AppTheme.primaryColor),
            title: Text(src.source.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('ID: ${src.id}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          )),
        ],
      ),
    );
  }
}

// ─── Stream sheet ─────────────────────────────────────────────────────────────

class _StreamSheet extends StatelessWidget {
  final _Match match;
  final List<_Stream> streams;
  final void Function(_Stream) onStreamSelected;
  const _StreamSheet({required this.match, required this.streams, required this.onStreamSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Text(match.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Select a stream:', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          ...streams.map((s) => ListTile(
            onTap: () => onStreamSelected(s),
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: AppTheme.primaryColor, size: 20),
            ),
            title: Text('Stream ${s.streamNo} · ${s.language}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            trailing: s.hd
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber, width: 1)),
                    child: const Text('HD', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)))
                : const Text('SD', style: TextStyle(color: Colors.white38, fontSize: 11)),
          )),
        ],
      ),
    );
  }
}

// ─── WebView player ───────────────────────────────────────────────────────────

class _LivePlayerScreen extends StatefulWidget {
  final _Match match;
  final _Stream stream;
  const _LivePlayerScreen({required this.match, required this.stream});

  @override
  State<_LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<_LivePlayerScreen> {
  bool _loading = true;
  bool _isFullscreen = false;

  void _enterFullscreen() async {
    setState(() => _isFullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
  }

  void _exitFullscreen() async {
    setState(() => _isFullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullscreen ? null : AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.match.title,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!widget.stream.hd)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: Text('SD', style: TextStyle(color: Colors.white38, fontSize: 12))),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber)),
                  child: const Text('HD',
                      style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.stream.embedUrl)),
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              disableDefaultErrorPage: true,
              supportMultipleWindows: false,
            ),
            onLoadStart: (_, _) => setState(() => _loading = true),
            onLoadStop:  (_, _) => setState(() => _loading = false),
            onEnterFullscreen: (_) => _enterFullscreen(),
            onExitFullscreen:  (_) => _exitFullscreen(),
            // Intercept navigations that leave the embed domain.
            // Instead of silently cancelling (which the site detects and blacks out the video),
            // we fire a background HTTP request to the redirect URL so the ad tracker
            // registers a "visit", then cancel the actual WebView navigation.
            shouldOverrideUrlLoading: (ctrl, action) async {
              final url = action.request.url?.toString() ?? '';
              final embedHost = Uri.tryParse(widget.stream.embedUrl)?.host ?? '';
              if (embedHost.isNotEmpty && !url.contains(embedHost)) {
                // Silently ping the ad URL so the tracker thinks it was opened
                http.get(Uri.parse(url), headers: {
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                      'AppleWebKit/537.36 (KHTML, like Gecko) '
                      'Chrome/122.0.0.0 Safari/537.36',
                  'Referer': widget.stream.embedUrl,
                }).catchError((_) => http.Response('', 200)); // ignore any error — it's a best-effort ping
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
        ],
      ),
    );
  }
}

// ─── CDN Channel Card ─────────────────────────────────────────────────────────

class _CdnChannelCard extends StatefulWidget {
  final _CdnChannel channel;
  final VoidCallback onTap;
  const _CdnChannelCard({required this.channel, required this.onTap});

  @override
  State<_CdnChannelCard> createState() => _CdnChannelCardState();
}

class _CdnChannelCardState extends State<_CdnChannelCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.channel;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _hovered ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: _hovered ? AppTheme.primaryColor.withValues(alpha: 0.6) : Colors.white12,
              width: 1.5,
            ),
            boxShadow: _hovered
                ? [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 2)]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (c.image.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: c.image,
                          height: 60,
                          fit: BoxFit.contain,
                          errorWidget: (_, _, _) => const Icon(Icons.tv_rounded, color: Colors.white38, size: 48),
                        )
                      else
                        const Icon(Icons.tv_rounded, color: Colors.white38, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        c.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (c.viewers > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${c.viewers} viewers',
                          style: const TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('● LIVE',
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (_hovered)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.85),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── CDN Sport Event Card ─────────────────────────────────────────────────────

class _CdnSportCard extends StatefulWidget {
  final _CdnSportEvent event;
  final VoidCallback onTap;
  const _CdnSportCard({required this.event, required this.onTap});

  @override
  State<_CdnSportCard> createState() => _CdnSportCardState();
}

class _CdnSportCardState extends State<_CdnSportCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _hovered ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: _hovered ? AppTheme.primaryColor.withValues(alpha: 0.6) : Colors.white12,
              width: 1.5,
            ),
            boxShadow: _hovered
                ? [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 2)]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              if (e.homeTeamIMG.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: e.homeTeamIMG,
                                  width: 40, height: 40,
                                  errorWidget: (_, _, _) => const Icon(Icons.sports_rounded, color: Colors.white38, size: 32),
                                )
                              else
                                const Icon(Icons.sports_rounded, color: Colors.white38, size: 32),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 60,
                                child: Text(e.homeTeam, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white70, fontSize: 10)),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('VS',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ),
                          Column(
                            children: [
                              if (e.awayTeamIMG.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: e.awayTeamIMG,
                                  width: 40, height: 40,
                                  errorWidget: (_, _, _) => const Icon(Icons.sports_rounded, color: Colors.white38, size: 32),
                                )
                              else
                                const Icon(Icons.sports_rounded, color: Colors.white38, size: 32),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 60,
                                child: Text(e.awayTeam, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white70, fontSize: 10)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        e.tournament,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: e.status == 'live' ? Colors.red.shade700 : Colors.orange.shade700,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(e.status == 'live' ? '● LIVE' : e.status.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (_hovered)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.85),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── CDN Channel Sheet ────────────────────────────────────────────────────────

class _CdnChannelSheet extends StatelessWidget {
  final _CdnSportEvent event;
  final void Function(_CdnChannel) onChannelSelected;
  const _CdnChannelSheet({required this.event, required this.onChannelSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Text('${event.homeTeam} vs ${event.awayTeam}',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Choose a channel:', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          ...event.channels.map((ch) => ListTile(
            onTap: () => onChannelSelected(ch),
            leading: ch.image.isNotEmpty
                ? CachedNetworkImage(imageUrl: ch.image, width: 32, height: 32, fit: BoxFit.contain,
                    errorWidget: (_, _, _) => const Icon(Icons.tv_rounded, color: AppTheme.primaryColor))
                : const Icon(Icons.tv_rounded, color: AppTheme.primaryColor),
            title: Text(ch.name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: ch.viewers > 0
                ? Text('${ch.viewers} viewers', style: const TextStyle(color: Colors.white38, fontSize: 11))
                : null,
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          )),
        ],
      ),
    );
  }
}

// ─── CDN Player Screen ────────────────────────────────────────────────────────

class _CdnPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  const _CdnPlayerScreen({required this.url, required this.title});

  @override
  State<_CdnPlayerScreen> createState() => _CdnPlayerScreenState();
}

class _CdnPlayerScreenState extends State<_CdnPlayerScreen> {
  bool _loading = true;
  bool _isFullscreen = false;

  void _enterFullscreen() async {
    setState(() => _isFullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
  }

  void _exitFullscreen() async {
    setState(() => _isFullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullscreen ? null : AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue)),
                child: const Text('CDN Live', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              disableDefaultErrorPage: true,
              supportMultipleWindows: false,
            ),
            onLoadStart: (_, _) => setState(() => _loading = true),
            onLoadStop:  (_, _) => setState(() => _loading = false),
            onEnterFullscreen: (_) => _enterFullscreen(),
            onExitFullscreen:  (_) => _exitFullscreen(),
            shouldOverrideUrlLoading: (ctrl, action) async {
              final url = action.request.url?.toString() ?? '';
              final embedHost = Uri.tryParse(widget.url)?.host ?? '';
              if (embedHost.isNotEmpty && !url.contains(embedHost)) {
                http.get(Uri.parse(url), headers: {
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                      'AppleWebKit/537.36 (KHTML, like Gecko) '
                      'Chrome/122.0.0.0 Safari/537.36',
                  'Referer': widget.url,
                }).catchError((_) => http.Response('', 200));
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
        ],
      ),
    );
  }
}
