/// Robust season/episode → filename matcher.
///
/// Handles the common scene/release naming schemes:
///   * `Show.S03E07.1080p.mkv`        — SxxExx (zero-padded or not)
///   * `Show.s3e7.WEB-DL.mkv`         — lowercase
///   * `Show.S03.E07.mkv`             — separator between S and E
///   * `Show.S03 E07.mkv`             — space separator
///   * `Show.3x07.HDTV.mkv`           — old-school NxNN
///   * `Show.Season 3 Episode 7.mkv`  — verbose
///
/// Also offers helpers to pick the best video file from a torrent payload:
/// `pickEpisode` for TV (matches season/episode, falls back to largest video,
/// excludes samples/extras), and `pickLargestVideo` for movies.
library;

class EpisodeMatcher {
  static const _videoExts = {
    '.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v',
    '.ts', '.mpg', '.mpeg', '.m2ts', '.divx', '.vob', '.ogv',
  };

  /// Strong (season+episode) patterns. Used first.
  static final List<RegExp> _seasonEpisodePatterns = [
    // S03E07 / s3e7 / S03.E07 / S03 E07 / S03_E07 / S03-E07
    RegExp(r's0*(\d{1,3})[\s._\-]*e0*(\d{1,4})'),
    // 3x07 / 03x07 / 3X7
    RegExp(r'(?<![a-z0-9])0*(\d{1,3})x0*(\d{1,4})(?![a-z0-9])'),
    // "season 3 episode 7"
    RegExp(r'season\s*0*(\d{1,3})\s*(?:episode|ep)\s*0*(\d{1,4})'),
  ];

  /// Episode-only patterns. Used as a fallback when the file (or whole pack)
  /// has no explicit season marker — e.g. season-folder packs named like
  /// `Ep 03 - Title.mkv`, `E03.mkv`, `Episode 03 - Title.mkv`, or just
  /// `03 - Title.mkv`.
  static final List<RegExp> _episodeOnlyPatterns = [
    // E07 / Ep07 / Ep 07 / Ep.07 / Episode 07 / Episode-07
    RegExp(r'(?<![a-z0-9])e(?:p|pisode)?[\s._\-]*0*(\d{1,4})(?![a-z0-9])'),
    // Leading "03 - Title", "03. Title", "03_Title" at the start of basename
    RegExp(r'^\s*0*(\d{1,4})\s*[-._]\s*'),
  ];

  /// True if [filename] (or full path) looks like the file for the given
  /// [season]/[episode]. Casing and zero-padding don't matter.
  static bool matches(String filename, int season, int episode) {
    final base = _basename(filename);
    if (base.isEmpty) return false;

    for (final p in _seasonEpisodePatterns) {
      for (final m in p.allMatches(base)) {
        final s = int.tryParse(m.group(1)!);
        final e = int.tryParse(m.group(2)!);
        if (s == season && e == episode) return true;
      }
    }
    return false;
  }

  /// True if [filename] contains an episode-only marker matching [episode]
  /// (no season information required). Used as a fallback only.
  static bool matchesEpisodeOnly(String filename, int episode) {
    final base = _basename(filename);
    if (base.isEmpty) return false;
    for (final p in _episodeOnlyPatterns) {
      for (final m in p.allMatches(base)) {
        final e = int.tryParse(m.group(1)!);
        if (e == episode) return true;
      }
    }
    return false;
  }

  static String _basename(String filename) {
    if (filename.isEmpty) return '';
    return filename.toLowerCase().split(RegExp(r'[\\/]')).last;
  }

  /// Picks the best video file for [season]/[episode]. Returns `null` if the
  /// list contains no video files at all.
  ///
  /// Strategy:
  ///   1. Filter to playable video files, dropping obvious extras
  ///      (`sample`, `featurette`, `behind*the*scenes`, `extras`).
  ///   2. Try to find a file whose basename has a strong S+E match
  ///      (`S03E07`, `3x07`, `Season 3 Episode 7`).
  ///   3. If no strong match exists in the entire pack, try episode-only
  ///      naming (`Ep 03`, `E03`, `Episode 03`, `03 - Title.mkv`) — common
  ///      in season-folder packs that omit the season marker.
  ///   4. Otherwise fall back to the largest remaining video file.
  ///
  /// On ties, the largest file wins (handles dual-quality packs).
  static T? pickEpisode<T>(
    List<T> files,
    int season,
    int episode, {
    required String Function(T) name,
    required int Function(T) size,
  }) {
    final videos = _onlyVideos(files, name);
    if (videos.isEmpty) return null;

    // 1. Strong S+E match.
    final strong =
        videos.where((f) => matches(name(f), season, episode)).toList();
    if (strong.isNotEmpty) {
      strong.sort((a, b) => size(b).compareTo(size(a)));
      return strong.first;
    }

    // 2. Episode-only fallback — but ONLY if no file in the pack uses
    //    SxxExx-style naming for any other season/episode. If something does,
    //    the absence of our season+episode is real, not a naming gap, and
    //    falling through to the largest video is safer than guessing.
    final hasAnyStrongMarker = videos.any((f) {
      final base = _basename(name(f));
      return _seasonEpisodePatterns.any((p) => p.hasMatch(base));
    });
    if (!hasAnyStrongMarker) {
      final epOnly =
          videos.where((f) => matchesEpisodeOnly(name(f), episode)).toList();
      if (epOnly.isNotEmpty) {
        epOnly.sort((a, b) => size(b).compareTo(size(a)));
        return epOnly.first;
      }
    }

    // 3. Last resort: largest video.
    videos.sort((a, b) => size(b).compareTo(size(a)));
    return videos.first;
  }

  /// Picks the largest video file (samples/extras filtered out). Returns
  /// `null` if no video files are present.
  static T? pickLargestVideo<T>(
    List<T> files, {
    required String Function(T) name,
    required int Function(T) size,
  }) {
    final videos = _onlyVideos(files, name);
    if (videos.isEmpty) return null;
    videos.sort((a, b) => size(b).compareTo(size(a)));
    return videos.first;
  }

  static List<T> _onlyVideos<T>(List<T> files, String Function(T) name) {
    return files.where((f) {
      final n = name(f).toLowerCase();
      if (!_videoExts.any(n.endsWith)) return false;
      // Drop common junk that ships alongside the real file.
      if (n.contains('sample')) return false;
      if (n.contains('featurette')) return false;
      if (n.contains('behind.the.scenes') || n.contains('behind-the-scenes')) {
        return false;
      }
      if (n.contains('/extras/') || n.contains(r'\extras\')) return false;
      return true;
    }).toList();
  }
}
