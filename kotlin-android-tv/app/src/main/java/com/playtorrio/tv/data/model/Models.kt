package com.playtorrio.tv.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class MediaItem(
    val id: Int,
    val title: String,
    val overview: String = "",
    val posterPath: String? = null,
    val backdropPath: String? = null,
    val voteAverage: Double = 0.0,
    val releaseDate: String? = null,
    /** "movie" or "tv" */
    val mediaType: String = "movie",
    val imdbId: String? = null,
    val runtimeMinutes: Int? = null,
    val numberOfSeasons: Int? = null,
) {
    val posterUrl: String?
        get() = posterPath?.let { "https://image.tmdb.org/t/p/w500$it" }
    val backdropUrl: String?
        get() = backdropPath?.let { "https://image.tmdb.org/t/p/w1280$it" }
}

@Serializable
data class TvSeason(
    val seasonNumber: Int,
    val name: String,
    val episodes: List<TvEpisode> = emptyList(),
)

@Serializable
data class TvEpisode(
    val episodeNumber: Int,
    val name: String,
    val overview: String = "",
    val stillPath: String? = null,
) {
    val stillUrl: String?
        get() = stillPath?.let { "https://image.tmdb.org/t/p/w300$it" }
}

@Serializable
data class StremioAddon(
    val baseUrl: String,
    val name: String,
    val version: String? = null,
    val logo: String? = null,
)

@Serializable
data class StremioStream(
    val name: String? = null,
    val title: String? = null,
    val description: String? = null,
    val url: String? = null,
    val infoHash: String? = null,
    val behaviorHints: BehaviorHints? = null,
    val addonName: String? = null,
    val addonBaseUrl: String? = null,
) {
    val displayLabel: String
        get() = listOfNotNull(name, title, description).firstOrNull { it.isNotBlank() }
            ?: url?.take(64)
            ?: infoHash?.take(16)
            ?: "Stream"

    val requestHeaders: Map<String, String>
        get() = behaviorHints?.proxyHeaders?.request.orEmpty()
}

@Serializable
data class BehaviorHints(
    val proxyHeaders: ProxyHeaders? = null,
)

@Serializable
data class ProxyHeaders(
    val request: Map<String, String>? = null,
    val requests: Map<String, String>? = null,
)

@Serializable
data class WatchEntry(
    val tmdbId: Int,
    val imdbId: String? = null,
    val title: String,
    val posterPath: String? = null,
    val mediaType: String = "movie",
    val method: String = "stremio_direct",
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val season: Int? = null,
    val episode: Int? = null,
    val streamUrl: String? = null,
    val streamHeaders: Map<String, String> = emptyMap(),
    val updatedAt: Long = System.currentTimeMillis(),
) {
    val uniqueId: String
        get() = if (season != null && episode != null) {
            "${tmdbId}_S${season}_E$episode"
        } else {
            "$tmdbId"
        }

    val posterUrl: String?
        get() = posterPath?.let { "https://image.tmdb.org/t/p/w500$it" }
}

@Serializable
data class IptvCredentials(
    /** "xtream" or "m3u" */
    val type: String = "xtream",
    val serverUrl: String = "",
    val username: String = "",
    val password: String = "",
    /** For M3U playlist login */
    val m3uUrl: String = "",
) {
    val isXtream: Boolean get() = type != "m3u"
    val isM3u: Boolean get() = type == "m3u"
}

@Serializable
data class IptvCategory(
    val categoryId: String,
    val categoryName: String,
)

@Serializable
data class IptvChannel(
    val streamId: String,
    val name: String,
    val streamIcon: String? = null,
    val categoryId: String? = null,
    val playUrl: String,
    val containerExtension: String? = null,
    /** live | movie | series_episode */
    val kind: String = "live",
)

@Serializable
data class IptvSeries(
    val seriesId: String,
    val name: String,
    val cover: String? = null,
    val categoryId: String? = null,
    val plot: String? = null,
)

@Serializable
data class IptvEpisode(
    val episodeId: String,
    val title: String,
    val season: Int,
    val episodeNum: Int,
    val containerExtension: String = "mp4",
    val playUrl: String,
)

@Serializable
data class IptvEpgEntry(
    val title: String,
    val description: String = "",
    val start: String? = null,
    val end: String? = null,
)


@Serializable
data class IptvPortal(
    val url: String,
    val username: String,
    val password: String,
    val source: String = "",
) {
    val key: String get() = "$url|$username|$password".lowercase()
    val credKey: String get() = "$username|$password".lowercase()
}

@Serializable
data class VerifiedPortal(
    val portal: IptvPortal,
    val name: String = "",
    val expiry: String = "",
    val maxConnections: String = "1",
    val activeConnections: String = "0",
) {
    val key: String get() = portal.key
}

@Serializable
data class ScrapePage(
    val portals: List<IptvPortal> = emptyList(),
    val nextAfter: String? = null,
    val error: String? = null,
) {
    val hasMore: Boolean get() = !nextAfter.isNullOrBlank()
}

@Serializable
data class TvGuideSlot(
    val portal: VerifiedPortal,
    val channel: IptvChannel,
    val programs: List<IptvEpgProgram> = emptyList(),
) {
    val host: String
        get() = runCatching {
            java.net.URI(portal.portal.url).host.orEmpty()
        }.getOrDefault(portal.portal.url)
}

@Serializable
data class IptvEpgProgram(
    val title: String,
    val description: String = "",
    val startMs: Long = 0,
    val stopMs: Long = 0,
) {
    val isNow: Boolean
        get() {
            val now = System.currentTimeMillis()
            return now in startMs until stopMs
        }
}

@Serializable
data class TmdbPagedResponse(
    val results: List<TmdbResult> = emptyList(),
)

@Serializable
data class TmdbResult(
    val id: Int,
    val title: String? = null,
    val name: String? = null,
    val overview: String? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("vote_average") val voteAverage: Double = 0.0,
    @SerialName("release_date") val releaseDate: String? = null,
    @SerialName("first_air_date") val firstAirDate: String? = null,
    @SerialName("media_type") val mediaType: String? = null,
)

@Serializable
data class TmdbExternalIds(
    @SerialName("imdb_id") val imdbId: String? = null,
)

@Serializable
data class TmdbMovieDetails(
    val id: Int,
    val title: String? = null,
    val overview: String? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("vote_average") val voteAverage: Double = 0.0,
    @SerialName("release_date") val releaseDate: String? = null,
    val runtime: Int? = null,
    @SerialName("imdb_id") val imdbId: String? = null,
    @SerialName("external_ids") val externalIds: TmdbExternalIds? = null,
)

@Serializable
data class TmdbTvDetails(
    val id: Int,
    val name: String? = null,
    val overview: String? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("vote_average") val voteAverage: Double = 0.0,
    @SerialName("first_air_date") val firstAirDate: String? = null,
    @SerialName("number_of_seasons") val numberOfSeasons: Int? = null,
    @SerialName("external_ids") val externalIds: TmdbExternalIds? = null,
)

@Serializable
data class TmdbSeasonResponse(
    @SerialName("season_number") val seasonNumber: Int = 1,
    val name: String = "",
    val episodes: List<TmdbEpisodeDto> = emptyList(),
)

@Serializable
data class TmdbEpisodeDto(
    @SerialName("episode_number") val episodeNumber: Int,
    val name: String? = null,
    val overview: String? = null,
    @SerialName("still_path") val stillPath: String? = null,
)
