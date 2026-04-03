import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/settings_service.dart';
import '../api/stremio_service.dart';
import '../models/movie.dart';
import '../services/xmltv_epg_service.dart';
import '../utils/app_theme.dart';
import '../utils/stremio_tv_schedule.dart';
import '../utils/tv_guide_refresh.dart';
import 'details_screen.dart';
import 'epg_channel_mapping_screen.dart';

/// Time-blocked listing for Stremio live-TV channels.
///
/// If the addon exposes a `videos` schedule (or `behaviorHints` EPG hints), those
/// rows are shown. Otherwise each channel gets a simple "Live now" placeholder
/// for the current window — Stremio does not guarantee EPG in the protocol.
class StremioTvGuideScreen extends StatefulWidget {
  const StremioTvGuideScreen({super.key});

  @override
  State<StremioTvGuideScreen> createState() => _StremioTvGuideScreenState();
}

class _ChannelRow {
  final Map<String, dynamic> catalogItem;
  final String addonBaseUrl;
  final String metaType;
  final List<TvScheduleSlot> slots;
  /// True when slots came from addon meta (videos / behaviorHints), not XMLTV or placeholder.
  final bool fromStremioSchedule;
  final String? tvgId;

  _ChannelRow({
    required this.catalogItem,
    required this.addonBaseUrl,
    required this.metaType,
    required this.slots,
    this.fromStremioSchedule = false,
    this.tvgId,
  });

  String get id => catalogItem['id']?.toString() ?? '';
  String get name => catalogItem['name']?.toString() ?? 'Channel';
  String? get poster => catalogItem['poster']?.toString();
}

class _StremioTvGuideScreenState extends State<StremioTvGuideScreen> {
  final StremioService _stremio = StremioService();

  bool _loading = true;
  String? _error;
  List<_ChannelRow> _rows = [];
  final int _maxChannels = 48;
  final int _concurrency = 6;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    TvGuideRefresh.notifier.addListener(_onTvGuideRefreshSignal);
    _load();
  }

  @override
  void dispose() {
    TvGuideRefresh.notifier.removeListener(_onTvGuideRefreshSignal);
    super.dispose();
  }

  void _onTvGuideRefreshSignal() {
    if (mounted) unawaited(_load());
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final settings = SettingsService();
      final epgUrl = await settings.getXmltvEpgUrl();
      if (!mounted || gen != _loadGen) return;
      final epgMap = await settings.getXmltvChannelMap();
      if (!mounted || gen != _loadGen) return;
      final epg = XmltvEpgService.instance;
      if (epgUrl != null && epgUrl.isNotEmpty) {
        await epg.loadFromUrl(epgUrl);
      } else {
        epg.clear();
      }

      if (!mounted || gen != _loadGen) return;
      var catalogs = await _stremio.getAllCatalogs();
      catalogs = catalogs.where((c) => StremioService.isLiveTvCatalogType(c['catalogType'])).toList();

      final List<Map<String, dynamic>> items = [];
      for (final cat in catalogs) {
        if (items.length >= _maxChannels) break;
        final batch = await _stremio.getCatalog(
          baseUrl: cat['addonBaseUrl'],
          type: cat['catalogType'],
          id: cat['catalogId'],
        );
        for (final m in batch) {
          if (items.length >= _maxChannels) break;
          final copy = Map<String, dynamic>.from(m);
          copy['_addonBaseUrl'] = cat['addonBaseUrl'];
          copy['_catalogType'] = cat['catalogType'];
          items.add(copy);
        }
      }

      if (!mounted || gen != _loadGen) return;

      if (items.isEmpty) {
        if (mounted && gen == _loadGen) {
          setState(() {
            _loading = false;
            _rows = [];
            _error = null;
          });
        }
        return;
      }

      final List<_ChannelRow> rows = [];
      for (var i = 0; i < items.length; i += _concurrency) {
        if (!mounted || gen != _loadGen) return;
        final chunk = items.skip(i).take(_concurrency);
        final futures = chunk.map((item) async {
          final base = item['_addonBaseUrl']?.toString() ?? '';
          final type = item['type']?.toString() ?? item['_catalogType']?.toString() ?? 'tv';
          final id = item['id']?.toString() ?? '';
          if (base.isEmpty || id.isEmpty) return null;
          final meta = await _stremio.getMeta(baseUrl: base, type: type, id: id);
          if (meta == null) return null;
          final name = item['name']?.toString() ?? meta['name']?.toString() ?? 'Channel';
          final tvgId = meta['tvgId']?.toString() ?? item['tvgId']?.toString();
          final mapKey = SettingsService.xmltvChannelMapKeyFor(
            addonBaseUrl: base,
            stremioChannelId: id,
          );
          final built = StremioTvSchedule.slotsFromMeta(meta, name);
          var slots = built.slots;
          var fromStremio = built.fromAddon;
          if (!fromStremio && epg.isLoaded) {
            final xmlSlots = StremioTvSchedule.slotsFromXmltv(
              epg,
              tvgId: tvgId,
              channelName: name,
              stremioId: id,
              epgChannelOverride: epgMap[mapKey],
            );
            if (xmlSlots.isNotEmpty) {
              slots = xmlSlots;
            }
          }
          return _ChannelRow(
            catalogItem: item,
            addonBaseUrl: base,
            metaType: type,
            slots: slots,
            fromStremioSchedule: fromStremio,
            tvgId: tvgId,
          );
        });
        final part = await Future.wait(futures);
        if (!mounted || gen != _loadGen) return;
        rows.addAll(part.whereType<_ChannelRow>());
      }

      if (mounted && gen == _loadGen) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && gen == _loadGen) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _openChannel(_ChannelRow row) {
    final item = Map<String, dynamic>.from(row.catalogItem);
    item['_addonBaseUrl'] = row.addonBaseUrl;
    item['type'] = row.metaType;

    final movie = Movie(
      id: row.id.hashCode,
      imdbId: row.id.startsWith('tt') ? row.id : null,
      title: row.name,
      posterPath: row.poster ?? '',
      backdropPath: item['background']?.toString() ?? row.poster ?? '',
      voteAverage: 0,
      releaseDate: '',
      overview: item['description']?.toString() ?? '',
      genres: (item['genres'] as List?)?.cast<String>() ?? [],
      mediaType: 'tv',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsScreen(movie: movie, stremioItem: item),
      ),
    );
  }

  String _fmtTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  List<TvScheduleSlot> _upcomingSlots(_ChannelRow row, {int max = 4}) {
    final now = DateTime.now();
    final filtered = row.slots.where((s) => s.end.isAfter(now.subtract(const Duration(minutes: 5)))).toList();
    if (filtered.isEmpty) return row.slots.take(max).toList();
    return filtered.take(max).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('TV Guide'),
        actions: [
          IconButton(
            tooltip: 'Match EPG to channels',
            icon: const Icon(Icons.link_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EpgChannelMappingScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _load(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
                  ),
                )
              : _rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.grid_view_rounded, size: 64, color: Colors.white.withValues(alpha: 0.12)),
                            const SizedBox(height: 16),
                            const Text(
                              'No channels for the guide',
                              style: TextStyle(color: Colors.white38, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Install a live TV Stremio addon and open TV Guide again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: AppTheme.primaryColor,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        itemCount: _rows.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16, top: 4),
                              child: Text(
                                'Schedules use the addon when it provides them. If not, add an XMLTV URL in Settings → Stremio (TV Guide EPG) to fill the grid; channel ids should match tvg-id or the channel name when possible.',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12, height: 1.35),
                              ),
                            );
                          }
                          final row = _rows[index - 1];
                          final upcoming = _upcomingSlots(row);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _openChannel(row),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: row.poster != null && row.poster!.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: row.poster!,
                                                width: 52,
                                                height: 52,
                                                fit: BoxFit.cover,
                                                errorWidget: (_, __, ___) => _channelPlaceholder(),
                                              )
                                            : _channelPlaceholder(),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              row.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ...upcoming.map((s) {
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 6),
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '${_fmtTime(s.start)}',
                                                      style: TextStyle(
                                                        color: AppTheme.primaryColor.withValues(alpha: 0.9),
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        fontFeatures: const [FontFeature.tabularFigures()],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            s.title,
                                                            maxLines: 2,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                                                          ),
                                                          if (s.subtitle != null &&
                                                              s.subtitle!.isNotEmpty &&
                                                              s.title != 'Live')
                                                            Text(
                                                              s.subtitle!,
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: TextStyle(
                                                                color: Colors.white.withValues(alpha: 0.35),
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.2)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _channelPlaceholder() {
    return Container(
      width: 52,
      height: 52,
      color: Colors.white.withValues(alpha: 0.06),
      child: Icon(Icons.live_tv_rounded, color: Colors.white.withValues(alpha: 0.2), size: 26),
    );
  }
}
