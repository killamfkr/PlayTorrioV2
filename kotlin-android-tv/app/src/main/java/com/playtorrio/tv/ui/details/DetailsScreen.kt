package com.playtorrio.tv.ui.details

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.playtorrio.tv.data.AppContainer
import com.playtorrio.tv.data.model.MediaItem
import com.playtorrio.tv.data.model.StremioStream
import com.playtorrio.tv.data.model.TvEpisode
import com.playtorrio.tv.data.model.WatchEntry
import com.playtorrio.tv.ui.components.ErrorText
import com.playtorrio.tv.ui.components.LoadingBox
import com.playtorrio.tv.ui.player.PlayerActivity
import com.playtorrio.tv.ui.theme.PtAccent
import com.playtorrio.tv.ui.theme.PtMuted
import com.playtorrio.tv.ui.theme.PtSurface
import com.playtorrio.tv.ui.theme.PtText
import kotlinx.coroutines.launch

@Composable
fun DetailsScreen(
    container: AppContainer,
    mediaType: String,
    tmdbId: Int,
    isTelevision: Boolean,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var item by remember { mutableStateOf<MediaItem?>(null) }
    var season by remember { mutableIntStateOf(1) }
    var episodes by remember { mutableStateOf<List<TvEpisode>>(emptyList()) }
    var episode by remember { mutableIntStateOf(1) }
    var streams by remember { mutableStateOf<List<StremioStream>>(emptyList()) }
    var streamsLoading by remember { mutableStateOf(false) }
    var seasonMenu by remember { mutableStateOf(false) }

    LaunchedEffect(tmdbId, mediaType) {
        loading = true
        error = null
        runCatching { container.tmdb.details(tmdbId, mediaType) }
            .onSuccess {
                item = it
                if (mediaType == "tv") {
                    val seasons = (it.numberOfSeasons ?: 1).coerceAtLeast(1)
                    season = 1
                    runCatching { container.tmdb.season(tmdbId, 1) }
                        .onSuccess { s ->
                            episodes = s.episodes
                            episode = s.episodes.firstOrNull()?.episodeNumber ?: 1
                        }
                    // keep seasons count on item
                    item = it.copy(numberOfSeasons = seasons)
                }
            }
            .onFailure { error = it.message }
        loading = false
    }

    LaunchedEffect(season, mediaType, tmdbId) {
        if (mediaType != "tv") return@LaunchedEffect
        runCatching { container.tmdb.season(tmdbId, season) }
            .onSuccess {
                episodes = it.episodes
                episode = it.episodes.firstOrNull()?.episodeNumber ?: 1
            }
    }

    fun loadStreams() {
        val media = item ?: return
        val imdb = media.imdbId
        if (imdb.isNullOrBlank()) {
            error = "No IMDb id — cannot query Stremio streams"
            return
        }
        streamsLoading = true
        scope.launch {
            val type = if (mediaType == "tv") "series" else "movie"
            val id = if (mediaType == "tv") "$imdb:$season:$episode" else imdb
            runCatching { container.stremio.getStreams(type, id) }
                .onSuccess { streams = it.filter { s -> !s.url.isNullOrBlank() } }
                .onFailure { error = it.message }
            streamsLoading = false
        }
    }

    fun play(stream: StremioStream) {
        val media = item ?: return
        val url = stream.url ?: return
        scope.launch {
            container.watchHistory.upsert(
                WatchEntry(
                    tmdbId = media.id,
                    imdbId = media.imdbId,
                    title = media.title,
                    posterPath = media.posterPath,
                    mediaType = mediaType,
                    streamUrl = url,
                    streamHeaders = stream.requestHeaders,
                    season = season.takeIf { mediaType == "tv" },
                    episode = episode.takeIf { mediaType == "tv" },
                ),
            )
        }
        context.startActivity(
            Intent(context, PlayerActivity::class.java).apply {
                putExtra(PlayerActivity.EXTRA_URL, url)
                putExtra(PlayerActivity.EXTRA_TITLE, media.title)
                putStringArrayListExtra(
                    PlayerActivity.EXTRA_HEADER_KEYS,
                    ArrayList(stream.requestHeaders.keys),
                )
                putStringArrayListExtra(
                    PlayerActivity.EXTRA_HEADER_VALUES,
                    ArrayList(stream.requestHeaders.values),
                )
            },
        )
    }

    when {
        loading -> LoadingBox()
        error != null && item == null -> Column {
            TextButton(onClick = onBack) { Text("Back", color = PtAccent) }
            ErrorText(error!!)
        }
        else -> {
            val media = item!!
            LazyColumn(Modifier.fillMaxSize()) {
                item {
                    Box {
                        AsyncImage(
                            model = media.backdropUrl ?: media.posterUrl,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(if (isTelevision) 300.dp else 220.dp),
                        )
                        TextButton(onClick = onBack, modifier = Modifier.padding(8.dp)) {
                            Text("← Back", color = PtText)
                        }
                    }
                    Text(
                        media.title,
                        color = PtText,
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    )
                    Text(
                        buildString {
                            append(media.releaseDate?.take(4) ?: "")
                            media.voteAverage.takeIf { it > 0 }?.let {
                                if (isNotEmpty()) append(" · ")
                                append("%.1f".format(it))
                            }
                            media.imdbId?.let {
                                if (isNotEmpty()) append(" · ")
                                append(it)
                            }
                        },
                        color = PtMuted,
                        modifier = Modifier.padding(horizontal = 20.dp),
                    )
                    Text(
                        media.overview,
                        color = PtMuted,
                        modifier = Modifier.padding(20.dp),
                    )
                    if (mediaType == "tv") {
                        Row(
                            Modifier.padding(horizontal = 20.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Box {
                                TextButton(onClick = { seasonMenu = true }) {
                                    Text("Season $season", color = PtAccent)
                                }
                                DropdownMenu(expanded = seasonMenu, onDismissRequest = { seasonMenu = false }) {
                                    val max = media.numberOfSeasons ?: 1
                                    (1..max).forEach { n ->
                                        DropdownMenuItem(
                                            text = { Text("Season $n") },
                                            onClick = {
                                                season = n
                                                seasonMenu = false
                                            },
                                        )
                                    }
                                }
                            }
                        }
                        Column(Modifier.padding(horizontal = 12.dp)) {
                            episodes.forEach { ep ->
                                val selected = ep.episodeNumber == episode
                                Text(
                                    "E${ep.episodeNumber}  ${ep.name}",
                                    color = if (selected) PtAccent else PtText,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { episode = ep.episodeNumber }
                                        .background(if (selected) PtSurface else androidx.compose.ui.graphics.Color.Transparent)
                                        .padding(12.dp),
                                )
                            }
                        }
                    }
                    Button(
                        onClick = { loadStreams() },
                        colors = ButtonDefaults.buttonColors(containerColor = PtAccent),
                        modifier = Modifier.padding(20.dp),
                    ) {
                        Text(if (streamsLoading) "Loading streams…" else "Find streams")
                    }
                    error?.let { ErrorText(it) }
                }
                items(streams) { stream ->
                    Column(
                        Modifier
                            .padding(horizontal = 16.dp, vertical = 6.dp)
                            .fillMaxWidth()
                            .background(PtSurface, RoundedCornerShape(10.dp))
                            .clickable { play(stream) }
                            .padding(14.dp),
                    ) {
                        Text(stream.displayLabel, color = PtText, fontWeight = FontWeight.Medium)
                        stream.addonName?.let {
                            Text(it, color = PtMuted, fontSize = 12.sp)
                        }
                    }
                }
                item { Spacer(Modifier.height(40.dp)) }
            }
        }
    }
}
