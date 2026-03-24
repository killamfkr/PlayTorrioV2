import 'dart:convert';

/// Single row from Xtream `get_short_epg` (title/description often base64).
class IptvEpgListing {
  final String title;
  final String description;
  final DateTime? start;
  final DateTime? end;

  const IptvEpgListing({
    required this.title,
    this.description = '',
    this.start,
    this.end,
  });

  static String decodeEpgText(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final t = raw.trim();
    if (t.length < 8) return t;
    final looksB64 = RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(t.replaceAll('\n', ''));
    if (!looksB64) return t;
    try {
      final normalized = t.replaceAll('\n', '');
      final decoded = utf8.decode(base64Decode(normalized));
      if (decoded.isEmpty) return t;
      return decoded;
    } catch (_) {
      return t;
    }
  }

  static DateTime? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n != null) {
      if (n > 2000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true).toLocal();
    }
    final normalized = s.contains(' ') && !s.contains('T')
        ? s.replaceFirst(' ', 'T')
        : s;
    return DateTime.tryParse(normalized);
  }

  factory IptvEpgListing.fromXtreamJson(Map<String, dynamic> json) {
    return IptvEpgListing(
      title: decodeEpgText(json['title']?.toString()),
      description: decodeEpgText(json['description']?.toString()),
      start: _parseTime(
        json['start_timestamp']?.toString() ??
            json['start']?.toString(),
      ),
      end: _parseTime(
        json['stop_timestamp']?.toString() ??
            json['end']?.toString(),
      ),
    );
  }
}
