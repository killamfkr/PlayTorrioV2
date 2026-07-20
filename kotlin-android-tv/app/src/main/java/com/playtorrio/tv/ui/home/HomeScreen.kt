package com.playtorrio.tv.ui.home

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.playtorrio.tv.data.AppContainer
import com.playtorrio.tv.data.model.MediaItem
import com.playtorrio.tv.data.model.WatchEntry
import com.playtorrio.tv.ui.components.ErrorText
import com.playtorrio.tv.ui.components.LoadingBox
import com.playtorrio.tv.ui.components.MediaRow
import com.playtorrio.tv.ui.components.SectionTitle
import com.playtorrio.tv.ui.components.TvSideNav
import com.playtorrio.tv.ui.navigation.Dest
import com.playtorrio.tv.ui.theme.PtMuted
import com.playtorrio.tv.ui.theme.PtText
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

data class HomeState(
    val loading: Boolean = true,
    val error: String? = null,
    val hero: MediaItem? = null,
    val trending: List<MediaItem> = emptyList(),
    val popular: List<MediaItem> = emptyList(),
    val topRated: List<MediaItem> = emptyList(),
    val nowPlaying: List<MediaItem> = emptyList(),
    val continueWatching: List<WatchEntry> = emptyList(),
)

@Composable
fun HomeScreen(
    container: AppContainer,
    isTelevision: Boolean,
    onOpen: (mediaType: String, id: Int) -> Unit,
    onOpenTab: (String) -> Unit,
) {
    var state by remember { mutableStateOf(HomeState()) }

    LaunchedEffect(Unit) {
        state = HomeState(loading = true)
        runCatching {
            coroutineScope {
                val trending = async { container.tmdb.trendingMovies() }
                val popular = async { container.tmdb.popularMovies() }
                val top = async { container.tmdb.topRatedMovies() }
                val now = async { container.tmdb.nowPlaying() }
                val history = async { container.watchHistory.list() }
                container.stremio.installDefaultIfNeeded()
                val t = trending.await()
                HomeState(
                    loading = false,
                    hero = t.firstOrNull(),
                    trending = t,
                    popular = popular.await(),
                    topRated = top.await(),
                    nowPlaying = now.await(),
                    continueWatching = history.await(),
                )
            }
        }.onSuccess { state = it }
            .onFailure { state = HomeState(loading = false, error = it.message) }
    }

    val body: @Composable () -> Unit = {
        when {
            state.loading -> LoadingBox()
            state.error != null -> ErrorText(state.error!!)
            else -> Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
            ) {
                state.hero?.let { hero ->
                    AsyncImage(
                        model = hero.backdropUrl ?: hero.posterUrl,
                        contentDescription = hero.title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(if (isTelevision) 280.dp else 200.dp),
                    )
                    Text(
                        hero.title,
                        color = PtText,
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    )
                    Text(
                        hero.overview,
                        color = PtMuted,
                        maxLines = 3,
                        modifier = Modifier.padding(horizontal = 20.dp),
                    )
                }
                if (state.continueWatching.isNotEmpty()) {
                    MediaRow(
                        title = "Continue watching",
                        items = state.continueWatching.map {
                            MediaItem(
                                id = it.tmdbId,
                                title = it.title,
                                posterPath = it.posterPath,
                                mediaType = it.mediaType,
                                imdbId = it.imdbId,
                            )
                        },
                        onOpen = { onOpen(it.mediaType, it.id) },
                    )
                }
                MediaRow("Trending", state.trending) { onOpen(it.mediaType, it.id) }
                MediaRow("Popular", state.popular) { onOpen(it.mediaType, it.id) }
                MediaRow("Now playing", state.nowPlaying) { onOpen(it.mediaType, it.id) }
                MediaRow("Top rated", state.topRated) { onOpen(it.mediaType, it.id) }
                SectionTitle("Native Android + Android TV")
                Text(
                    "Stremio addons, IPTV Xtream, and Media3 playback.",
                    color = PtMuted,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
                )
            }
        }
    }

    if (isTelevision) {
        Row(Modifier.fillMaxSize()) {
            TvSideNav(selected = "home") { id ->
                when (id) {
                    "home" -> Unit
                    "search" -> onOpenTab(Dest.Search.route)
                    "iptv" -> onOpenTab(Dest.Iptv.route)
                    "settings" -> onOpenTab(Dest.Settings.route)
                }
            }
            body()
        }
    } else {
        body()
    }
}
