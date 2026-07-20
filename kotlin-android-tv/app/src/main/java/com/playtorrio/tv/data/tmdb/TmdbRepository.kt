package com.playtorrio.tv.data.tmdb

import com.playtorrio.tv.BuildConfig
import com.playtorrio.tv.data.model.MediaItem
import com.playtorrio.tv.data.model.TmdbMovieDetails
import com.playtorrio.tv.data.model.TmdbPagedResponse
import com.playtorrio.tv.data.model.TmdbResult
import com.playtorrio.tv.data.model.TmdbSeasonResponse
import com.playtorrio.tv.data.model.TmdbTvDetails
import com.playtorrio.tv.data.model.TvEpisode
import com.playtorrio.tv.data.model.TvSeason
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request

class TmdbRepository(private val http: OkHttpClient) {
    private val json = Json { ignoreUnknownKeys = true }
    private val apiKey = BuildConfig.TMDB_API_KEY
    private val base = "https://api.themoviedb.org/3"

    suspend fun trendingMovies(): List<MediaItem> = getList("/trending/movie/day", "movie")
    suspend fun trendingTv(): List<MediaItem> = getList("/trending/tv/day", "tv")
    suspend fun popularMovies(): List<MediaItem> = getList("/movie/popular", "movie")
    suspend fun popularTv(): List<MediaItem> = getList("/tv/popular", "tv")
    suspend fun topRatedMovies(): List<MediaItem> = getList("/movie/top_rated", "movie")
    suspend fun nowPlaying(): List<MediaItem> = getList("/movie/now_playing", "movie")

    suspend fun search(query: String): List<MediaItem> = withContext(Dispatchers.IO) {
        if (query.isBlank()) return@withContext emptyList()
        val url = "$base/search/multi".toHttpUrl().newBuilder()
            .addQueryParameter("api_key", apiKey)
            .addQueryParameter("query", query)
            .addQueryParameter("include_adult", "true")
            .build()
        val body = get(url.toString())
        val page = json.decodeFromString<TmdbPagedResponse>(body)
        page.results
            .filter { it.mediaType == "movie" || it.mediaType == "tv" }
            .map { it.toMediaItem(it.mediaType ?: "movie") }
    }

    suspend fun details(id: Int, mediaType: String): MediaItem = withContext(Dispatchers.IO) {
        if (mediaType == "tv") {
            val url = "$base/tv/$id".toHttpUrl().newBuilder()
                .addQueryParameter("api_key", apiKey)
                .addQueryParameter("append_to_response", "images,external_ids")
                .build()
            val dto = json.decodeFromString<TmdbTvDetails>(get(url.toString()))
            MediaItem(
                id = dto.id,
                title = dto.name.orEmpty(),
                overview = dto.overview.orEmpty(),
                posterPath = dto.posterPath,
                backdropPath = dto.backdropPath,
                voteAverage = dto.voteAverage,
                releaseDate = dto.firstAirDate,
                mediaType = "tv",
                imdbId = dto.externalIds?.imdbId,
                numberOfSeasons = dto.numberOfSeasons,
            )
        } else {
            val url = "$base/movie/$id".toHttpUrl().newBuilder()
                .addQueryParameter("api_key", apiKey)
                .addQueryParameter("append_to_response", "images,external_ids")
                .build()
            val dto = json.decodeFromString<TmdbMovieDetails>(get(url.toString()))
            MediaItem(
                id = dto.id,
                title = dto.title.orEmpty(),
                overview = dto.overview.orEmpty(),
                posterPath = dto.posterPath,
                backdropPath = dto.backdropPath,
                voteAverage = dto.voteAverage,
                releaseDate = dto.releaseDate,
                mediaType = "movie",
                imdbId = dto.imdbId ?: dto.externalIds?.imdbId,
                runtimeMinutes = dto.runtime,
            )
        }
    }

    suspend fun season(tvId: Int, seasonNumber: Int): TvSeason = withContext(Dispatchers.IO) {
        val url = "$base/tv/$tvId/season/$seasonNumber".toHttpUrl().newBuilder()
            .addQueryParameter("api_key", apiKey)
            .build()
        val dto = json.decodeFromString<TmdbSeasonResponse>(get(url.toString()))
        TvSeason(
            seasonNumber = dto.seasonNumber,
            name = dto.name,
            episodes = dto.episodes.map {
                TvEpisode(
                    episodeNumber = it.episodeNumber,
                    name = it.name.orEmpty(),
                    overview = it.overview.orEmpty(),
                    stillPath = it.stillPath,
                )
            },
        )
    }

    private suspend fun getList(path: String, type: String): List<MediaItem> =
        withContext(Dispatchers.IO) {
            val url = "$base$path".toHttpUrl().newBuilder()
                .addQueryParameter("api_key", apiKey)
                .build()
            val page = json.decodeFromString<TmdbPagedResponse>(get(url.toString()))
            page.results.map { it.toMediaItem(type) }
        }

    private fun get(url: String): String {
        val req = Request.Builder().url(url).get().build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("TMDB ${resp.code}: ${resp.message}")
            return resp.body?.string().orEmpty()
        }
    }

    private fun TmdbResult.toMediaItem(fallbackType: String) = MediaItem(
        id = id,
        title = title ?: name.orEmpty(),
        overview = overview.orEmpty(),
        posterPath = posterPath,
        backdropPath = backdropPath,
        voteAverage = voteAverage,
        releaseDate = releaseDate ?: firstAirDate,
        mediaType = mediaType ?: fallbackType,
    )
}
