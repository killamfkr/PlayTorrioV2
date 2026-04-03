import '../services/xmltv_epg_service.dart';

/// A single TV guide time block (Stremio meta, XMLTV, or placeholder).
class TvScheduleSlot {
  final DateTime start;
  final DateTime end;
  final String title;
  final String? subtitle;

  const TvScheduleSlot({
    required this.start,
    required this.end,
    required this.title,
    this.subtitle,
  });
}

/// Builds programme lists from Stremio channel meta and optional XMLTV EPG.
class StremioTvSchedule {
  StremioTvSchedule._();

  static DateTime? parseReleased(dynamic released) {
    if (released == null) return null;
    if (released is int) {
      final n = released;
      if (n > 2000000000000) return DateTime.fromMillisecondsSinceEpoch(n);
      if (n > 2000000000) return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      return DateTime.fromMillisecondsSinceEpoch(n * 1000);
    }
    if (released is double) {
      return parseReleased(released.round());
    }
    if (released is String) {
      final t = DateTime.tryParse(released);
      if (t != null) return t;
      final asInt = int.tryParse(released);
      if (asInt != null) return parseReleased(asInt);
      // Compact ISO without separators: YYYYMMDDTHHmmss or YYYYMMDD
      final digits = released.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 8) {
        final y = int.tryParse(digits.substring(0, 4));
        final mo = digits.length >= 6 ? int.tryParse(digits.substring(4, 6)) : null;
        final d = digits.length >= 8 ? int.tryParse(digits.substring(6, 8)) : null;
        if (y != null && mo != null && d != null) {
          if (digits.length >= 14) {
            final h = int.tryParse(digits.substring(8, 10)) ?? 0;
            final mi = int.tryParse(digits.substring(10, 12)) ?? 0;
            final sec = int.tryParse(digits.substring(12, 14)) ?? 0;
            return DateTime(y, mo, d, h, mi, sec);
          }
          return DateTime(y, mo, d);
        }
      }
    }
    return null;
  }

  /// Slot that contains [now] (start <= now < end), or null.
  static TvScheduleSlot? currentSlot(Iterable<TvScheduleSlot> slots, [DateTime? now]) {
    final n = now ?? DateTime.now();
    for (final s in slots) {
      if (!n.isBefore(s.start) && n.isBefore(s.end)) return s;
    }
    return null;
  }

  /// 0..1 progress through [slot] at [now].
  static double progressOf(TvScheduleSlot slot, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final total = slot.end.difference(slot.start).inMicroseconds;
    if (total <= 0) return 0;
    final elapsed = n.difference(slot.start).inMicroseconds.clamp(0, total);
    return elapsed / total;
  }

  /// [fromAddon] is true when `videos` or `behaviorHints.epg` produced the list.
  static ({List<TvScheduleSlot> slots, bool fromAddon}) slotsFromMeta(
    Map<String, dynamic> meta,
    String channelName,
  ) {
    final videos = meta['videos'];
    if (videos is List && videos.isNotEmpty) {
      final List<TvScheduleSlot> slots = [];
      for (final raw in videos) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw as Map);
        final title = (m['name'] ?? m['title'] ?? 'Program').toString();
        final start = parseReleased(
          m['released'] ??
              m['firstAired'] ??
              m['airDate'] ??
              m['time'] ??
              m['start'] ??
              m['from'] ??
              m['date'],
        );
        if (start == null) continue;
        final durMin = (m['duration'] as num?)?.toInt() ??
            (m['runtime'] as num?)?.toInt() ??
            30;
        final end = start.add(Duration(minutes: durMin.clamp(15, 240)));
        slots.add(TvScheduleSlot(
          start: start,
          end: end,
          title: title,
          subtitle: m['description']?.toString(),
        ));
      }
      slots.sort((a, b) => a.start.compareTo(b.start));
      if (slots.isNotEmpty) return (slots: slots, fromAddon: true);
    }

    final hints = meta['behaviorHints'];
    if (hints is Map && hints['epg'] is List) {
      final List<TvScheduleSlot> slots = [];
      for (final e in hints['epg'] as List) {
        if (e is! Map) continue;
        final start = parseReleased(e['start'] ?? e['from']);
        final end = parseReleased(e['end'] ?? e['to']);
        if (start == null) continue;
        slots.add(TvScheduleSlot(
          start: start,
          end: end ?? start.add(const Duration(hours: 1)),
          title: (e['title'] ?? e['name'] ?? 'Program').toString(),
          subtitle: e['description']?.toString(),
        ));
      }
      slots.sort((a, b) => a.start.compareTo(b.start));
      if (slots.isNotEmpty) return (slots: slots, fromAddon: true);
    }

    final now = DateTime.now();
    final hourStart = DateTime(now.year, now.month, now.day, now.hour);
    return (
      slots: [
        TvScheduleSlot(
          start: hourStart,
          end: hourStart.add(const Duration(hours: 1)),
          title: 'Live',
          subtitle: channelName,
        ),
      ],
      fromAddon: false,
    );
  }

  static List<TvScheduleSlot> slotsFromXmltv(
    XmltvEpgService epg, {
    required String? tvgId,
    required String channelName,
    required String stremioId,
    String? epgChannelOverride,
  }) {
    final from = DateTime.now().subtract(const Duration(hours: 6));
    final to = DateTime.now().add(const Duration(days: 2));
    final progs = epg.programmesFor(
      tvgId: tvgId,
      channelName: channelName,
      stremioId: stremioId,
      epgChannelOverride: epgChannelOverride,
      from: from,
      to: to,
      maxItems: 24,
    );
    return progs
        .map(
          (p) => TvScheduleSlot(
            start: p.start,
            end: p.end,
            title: p.title,
            subtitle: p.subtitle,
          ),
        )
        .toList();
  }

  /// Resolves schedule from Stremio meta and optional XMLTV.
  ///
  /// XMLTV is preferred when it yields a programme airing **now**, so channel cards
  /// show real titles instead of the hourly "Live" placeholder when EPG matches.
  static List<TvScheduleSlot> resolveSlots({
    required Map<String, dynamic> meta,
    required String channelName,
    required String stremioId,
    required XmltvEpgService epg,
    required bool epgLoaded,
    String? epgChannelOverride,
    String? catalogItemTvgId,
  }) {
    final built = slotsFromMeta(meta, channelName);
    final now = DateTime.now();

    if (!epgLoaded) {
      return built.slots;
    }

    final tvgId =
        meta['tvgId']?.toString() ?? meta['tvg_id']?.toString() ?? catalogItemTvgId;
    final xmlSlots = slotsFromXmltv(
      epg,
      tvgId: tvgId,
      channelName: channelName,
      stremioId: stremioId,
      epgChannelOverride: epgChannelOverride,
    );
    if (xmlSlots.isEmpty) {
      return built.slots;
    }

    final xmlNow = currentSlot(xmlSlots, now);
    if (xmlNow != null) {
      return xmlSlots;
    }
    if (!built.fromAddon) {
      return xmlSlots;
    }
    return built.slots;
  }
}
