import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/settings_service.dart';
import '../api/stremio_service.dart';
import '../models/movie.dart';
import '../services/xmltv_epg_service.dart';
import '../utils/app_theme.dart';
import 'details_screen.dart';

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

class _GuideSlot {
  final DateTime start;
  final DateTime end;
  final String title;
  final String? subtitle;

  const _GuideSlot({
    required this.start,
    required this.end,
    required this.title,
    this.subtitle,
  });
}

class _ChannelRow {
  final Map<String, dynamic> catalogItem;
  final String addonBaseUrl;
  final String metaType;
  final List<_GuideSlot> slots;
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? _parseReleased(dynamic released) {
    if (released == null) return null;
    if (released is int) {
      final n = released;
      if (n > 2000000000000) return DateTime.fromMillisecondsSinceEpoch(n);
      if (n > 2000000000) return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      return DateTime.fromMillisecondsSinceEpoch(n * 1000);
    }
    if (released is String) {
      final t = DateTime.tryParse(released);
      if (t != null) return t;
      final asInt = int.tryParse(released);
      if (asInt != null) return _parseReleased(asInt);
    }
    return null;
  }

  /// [fromAddon] is true when videos or embedded EPG hints produced the list.
  ({List<_GuideSlot> slots, bool fromAddon}) _slotsFromMeta(Map<String, dynamic> meta, String channelName) {
    final videos = meta['videos'];
    if (videos is List && videos.isNotEmpty) {
      final List<_GuideSlot> slots = [];
      for (final raw in videos) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw as Map);
        final title = (m['name'] ?? m['title'] ?? 'Program').toString();
        final start = _parseReleased(m['released'] ?? m['firstAired'] ?? m['airDate']);
        if (start == null) continue;
        final durMin = (m['duration'] as num?)?.toInt() ??
            (m['runtime'] as num?)?.toInt() ??
            30;
        final end = start.add(Duration(minutes: durMin.clamp(15, 240)));
        slots.add(_GuideSlot(
          start: start,
          end: end,
          title: title,
          subtitle: m['description']?.toString(),
        ));
      }
      slots.sort((a, b) => a.start.compareTo(b.start));
      if (slots.isNotEmpty) return (slots: slots, fromAddon: true);
    }

    // Optional: addon-specific EPG in behaviorHints (rare)
    final hints = meta['behaviorHints'];
    if (hints is Map && hints['epg'] is List) {
      final List<_GuideSlot> slots = [];
      for (final e in hints['epg'] as List) {
        if (e is! Map) continue;
        final start = _parseReleased(e['start'] ?? e['from']);
        final end = _parseReleased(e['end'] ?? e['to']);
        if (start == null) continue;
        slots.add(_GuideSlot(
          start: start,
          end: end ?? start.add(const Duration(hours: 1)),
          title: (e['title'] ?? e['name'] ?? 'Program').toString(),
          subtitle: e['description']?.toString(),
        ));
      }
      slots.sort((a, b) => a.start.compareTo(b.start));
      if (slots.isNotEmpty) return (slots: slots, fromAddon: true);
    }

    // Fallback: single "Live" block anchored to the current hour
    final now = DateTime.now();
    final hourStart = DateTime(now.year, now.month, now.day, now.hour);
    return (
      slots: [
        _GuideSlot(
          start: hourStart,
          end: hourStart.add(const Duration(hours: 1)),
          title: 'Live',
          subtitle: channelName,
        ),
      ],
      fromAddon: false,
    );
  }

  List<_GuideSlot> _slotsFromXmltv(
    XmltvEpgService epg, {
    required String? tvgId,
    required String channelName,
    required String stremioId,
  }) {
    final from = DateTime.now().subtract(const Duration(hours: 6));
    final to = DateTime.now().add(const Duration(days: 2));
    final progs = epg.programmesFor(
      tvgId: tvgId,
      channelName: channelName,
      stremioId: stremioId,
      from: from,
      to: to,
      maxItems: 24,
    );
    return progs
        .map(
          (p) => _GuideSlot(
            start: p.start,
            end: p.end,
            title: p.title,
            subtitle: p.subtitle,
          ),
        )
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final epgUrl = await SettingsService().getXmltvEpgUrl();
      final epg = XmltvEpgService.instance;
      if (epgUrl != null && epgUrl.isNotEmpty) {
        await epg.loadFromUrl(epgUrl);
      } else {
        epg.clear();
      }

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

      if (items.isEmpty) {
        if (mounted) {
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
          final built = _slotsFromMeta(meta, name);
          var slots = built.slots;
          var fromStremio = built.fromAddon;
          if (!fromStremio && epg.isLoaded) {
            final xmlSlots = _slotsFromXmltv(
              epg,
              tvgId: tvgId,
              channelName: name,
              stremioId: id,
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
        rows.addAll(part.whereType<_ChannelRow>());
      }

      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
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

  List<_GuideSlot> _upcomingSlots(_ChannelRow row, {int max = 4}) {
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
