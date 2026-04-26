/// Identifier classes — port of webstreamr/src/utils/id/*.ts
library;

abstract class Id {
  int? get season;
  int? get episode;
  @override
  String toString();
}

class ImdbId extends Id {
  final String id;
  @override
  final int? season;
  @override
  final int? episode;

  ImdbId(this.id, this.season, this.episode);

  static ImdbId fromString(String raw) {
    final parts = raw.split(':');
    final base = parts[0];
    if (!RegExp(r'^tt\d+$').hasMatch(base)) {
      throw ArgumentError('IMDb ID "$raw" is invalid');
    }
    return ImdbId(
      base,
      parts.length > 1 ? int.tryParse(parts[1]) : null,
      parts.length > 2 ? int.tryParse(parts[2]) : null,
    );
  }

  @override
  String toString() => season == null ? id : '$id:$season:$episode';
}

class TmdbId extends Id {
  final int id;
  @override
  final int? season;
  @override
  final int? episode;

  TmdbId(this.id, this.season, this.episode);

  static TmdbId fromString(String raw) {
    final parts = raw.split(':');
    final base = int.tryParse(parts[0]);
    if (base == null) {
      throw ArgumentError('TMDB ID "$raw" is invalid');
    }
    return TmdbId(
      base,
      parts.length > 1 ? int.tryParse(parts[1]) : null,
      parts.length > 2 ? int.tryParse(parts[2]) : null,
    );
  }

  @override
  String toString() => season == null ? '$id' : '$id:$season:$episode';

  String formatSeasonAndEpisode() =>
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
}
