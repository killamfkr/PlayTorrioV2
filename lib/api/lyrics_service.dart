import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'lyrics_disk.dart';
import 'music_service.dart';

class LyricLine {
  final Duration startTime;
  final String text;

  LyricLine({required this.startTime, required this.text});

  Map<String, dynamic> toJson() => {
    'startTimeMs': startTime.inMilliseconds,
    'text': text,
  };

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
    startTime: Duration(milliseconds: json['startTimeMs']),
    text: json['text'],
  );
}

class LyricsService {
  Future<List<LyricLine>?> getSyncedLyrics({
    required String trackName,
    required String artistName,
    required String albumName,
    required int durationSeconds,
  }) async {
    try {
      final uri = Uri.https('lrclib.net', '/api/get', {
        'track_name': trackName,
        'artist_name': artistName,
        'album_name': albumName,
        'duration': durationSeconds.toString(),
      });

      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String? syncedLyrics = data['syncedLyrics'];
        if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
          debugPrint('LyricsService: Received synced lyrics (${syncedLyrics.length} chars)');
          return _parseLrc(syncedLyrics);
        }
      }
    } catch (e) {
      debugPrint('LyricsService: Error fetching lyrics: $e');
    }
    return null;
  }

  List<LyricLine> _parseLrc(String lrcContent) {
    final List<LyricLine> lines = [];
    final RegExp regExp = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)');

    for (var line in lrcContent.split('\n')) {
      final match = regExp.firstMatch(line.trim());
      if (match != null) {
        try {
          final int minutes = int.parse(match.group(1)!);
          final double seconds = double.parse(match.group(2)!);
          final String text = match.group(3)!.trim();

          if (text.isNotEmpty) {
            final duration = Duration(
              minutes: minutes,
              seconds: seconds.toInt(),
              milliseconds: ((seconds % 1) * 1000).toInt(),
            );
            lines.add(LyricLine(startTime: duration, text: text));
          }
        } catch (e) {
          // Skip malformed lines
        }
      }
    }
    debugPrint('LyricsService: Parsed ${lines.length} lines');
    return lines;
  }

  Future<void> saveLyrics(MusicTrack track, List<LyricLine> lyrics) async {
    try {
      final data = lyrics.map((l) => l.toJson()).toList();
      await saveLyricsJson(track.id, json.encode(data));
    } catch (e) {
      debugPrint('LyricsService: Error saving local lyrics: $e');
    }
  }

  Future<List<LyricLine>?> getLocalLyrics(MusicTrack track) async {
    try {
      final content = await loadLyricsJson(track.id);
      if (content == null) return null;
      final List data = json.decode(content);
      return data.map((item) => LyricLine.fromJson(item)).toList();
    } catch (e) {
      debugPrint('LyricsService: Error reading local lyrics: $e');
    }
    return null;
  }
}
