package com.playtorrio.tv.ui.iptv

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.playtorrio.tv.data.AppContainer
import com.playtorrio.tv.data.model.IptvCategory
import com.playtorrio.tv.data.model.IptvChannel
import com.playtorrio.tv.data.model.IptvCredentials
import com.playtorrio.tv.data.model.IptvEpisode
import com.playtorrio.tv.data.model.IptvEpgEntry
import com.playtorrio.tv.data.model.IptvSeries
import com.playtorrio.tv.ui.components.ErrorText
import com.playtorrio.tv.ui.components.LoadingBox
import com.playtorrio.tv.ui.components.TvSideNav
import com.playtorrio.tv.ui.player.PlayerActivity
import com.playtorrio.tv.ui.theme.PtAccent
import com.playtorrio.tv.ui.theme.PtMuted
import com.playtorrio.tv.ui.theme.PtSurface
import com.playtorrio.tv.ui.theme.PtText
import kotlinx.coroutines.launch

private enum class IptvSection { Live, Movies, Series, Favorites }
private enum class LoginMode { Xtream, M3u }

@Composable
fun IptvScreen(
    container: AppContainer,
    isTelevision: Boolean,
    onOpenTab: (String) -> Unit = {},
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var creds by remember { mutableStateOf<IptvCredentials?>(null) }
    var loading by remember { mutableStateOf(true) }
    var listLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    var loginMode by remember { mutableStateOf(LoginMode.Xtream) }
    var server by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var m3uUrl by remember { mutableStateOf("") }

    var section by remember { mutableStateOf(IptvSection.Live) }
    var categories by remember { mutableStateOf<List<IptvCategory>>(emptyList()) }
    var selectedCat by remember { mutableStateOf<String?>(null) }
    var channels by remember { mutableStateOf<List<IptvChannel>>(emptyList()) }
    var series by remember { mutableStateOf<List<IptvSeries>>(emptyList()) }
    var openSeries by remember { mutableStateOf<IptvSeries?>(null) }
    var episodes by remember { mutableStateOf<List<IptvEpisode>>(emptyList()) }
    var favorites by remember { mutableStateOf<Set<String>>(emptySet()) }
    var query by remember { mutableStateOf("") }
    var epg by remember { mutableStateOf<IptvEpgEntry?>(null) }
    var epgStreamId by remember { mutableStateOf<String?>(null) }

    fun play(url: String, title: String) {
        context.startActivity(
            Intent(context, PlayerActivity::class.java).apply {
                putExtra(PlayerActivity.EXTRA_URL, url)
                putExtra(PlayerActivity.EXTRA_TITLE, title)
                putStringArrayListExtra(PlayerActivity.EXTRA_HEADER_KEYS, arrayListOf("User-Agent"))
                putStringArrayListExtra(
                    PlayerActivity.EXTRA_HEADER_VALUES,
                    arrayListOf("VLC/3.0.20 LibVLC/3.0.20"),
                )
            },
        )
    }

    suspend fun loadSection(c: IptvCredentials, sec: IptvSection) {
        listLoading = true
        error = null
        openSeries = null
        episodes = emptyList()
        epg = null
        try {
            when (sec) {
                IptvSection.Live -> {
                    categories = container.iptv.liveCategories(c)
                    selectedCat = categories.firstOrNull()?.categoryId
                    channels = container.iptv.liveStreams(c, selectedCat)
                    series = emptyList()
                }
                IptvSection.Movies -> {
                    categories = container.iptv.vodCategories(c)
                    selectedCat = categories.firstOrNull()?.categoryId
                    channels = container.iptv.vodStreams(c, selectedCat)
                    series = emptyList()
                }
                IptvSection.Series -> {
                    categories = container.iptv.seriesCategories(c)
                    selectedCat = categories.firstOrNull()?.categoryId
                    series = container.iptv.seriesList(c, selectedCat)
                    channels = emptyList()
                }
                IptvSection.Favorites -> {
                    categories = emptyList()
                    selectedCat = null
                    val favs = container.iptv.favoriteIds()
                    favorites = favs
                    val live = if (c.isXtream) {
                        container.iptv.liveStreams(c, null)
                    } else {
                        container.iptv.liveStreams(c, null)
                    }
                    val vod = if (c.isXtream) container.iptv.vodStreams(c, null) else emptyList()
                    channels = (live + vod).filter { it.streamId in favs }
                    series = emptyList()
                }
            }
        } catch (t: Throwable) {
            error = t.message
        }
        listLoading = false
    }

    LaunchedEffect(Unit) {
        loading = true
        favorites = container.iptv.favoriteIds()
        val saved = container.iptv.savedCredentials()
        if (saved != null) {
            runCatching {
                container.iptv.restoreSession(saved)
                creds = saved
                if (saved.isXtream) {
                    server = saved.serverUrl
                    user = saved.username
                    pass = saved.password
                    loginMode = LoginMode.Xtream
                } else {
                    m3uUrl = saved.m3uUrl
                    loginMode = LoginMode.M3u
                    section = IptvSection.Live
                }
                loadSection(saved, section)
            }.onFailure { error = it.message }
        }
        loading = false
    }

    LaunchedEffect(selectedCat, section, creds) {
        val c = creds ?: return@LaunchedEffect
        if (section == IptvSection.Favorites || openSeries != null) return@LaunchedEffect
        listLoading = true
        runCatching {
            when (section) {
                IptvSection.Live -> channels = container.iptv.liveStreams(c, selectedCat)
                IptvSection.Movies -> channels = container.iptv.vodStreams(c, selectedCat)
                IptvSection.Series -> series = container.iptv.seriesList(c, selectedCat)
                IptvSection.Favorites -> Unit
            }
        }.onFailure { error = it.message }
        listLoading = false
    }

    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedBorderColor = PtAccent,
        unfocusedBorderColor = PtMuted,
        focusedLabelColor = PtAccent,
        unfocusedLabelColor = PtMuted,
        focusedTextColor = PtText,
        unfocusedTextColor = PtText,
        cursorColor = PtAccent,
    )

    val chipColors = FilterChipDefaults.filterChipColors(
        selectedContainerColor = PtAccent.copy(alpha = 0.3f),
        selectedLabelColor = PtText,
        labelColor = PtMuted,
        containerColor = PtSurface,
    )

    val body: @Composable () -> Unit = {
        when {
            loading -> LoadingBox()
            creds == null -> Column(Modifier.fillMaxSize().padding(20.dp)) {
                Text("IPTV", color = PtText, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                Text(
                    "Xtream Codes or M3U playlist — same flows as PlayTorrio’s IPTV tab.",
                    color = PtMuted,
                    modifier = Modifier.padding(top = 4.dp, bottom = 12.dp),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = loginMode == LoginMode.Xtream,
                        onClick = { loginMode = LoginMode.Xtream },
                        label = { Text("Xtream") },
                        colors = chipColors,
                    )
                    FilterChip(
                        selected = loginMode == LoginMode.M3u,
                        onClick = { loginMode = LoginMode.M3u },
                        label = { Text("M3U") },
                        colors = chipColors,
                    )
                }
                Spacer(Modifier.height(12.dp))
                if (loginMode == LoginMode.Xtream) {
                    OutlinedTextField(
                        value = server,
                        onValueChange = { server = it },
                        label = { Text("Server URL") },
                        modifier = Modifier.fillMaxWidth(),
                        colors = fieldColors,
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = user,
                        onValueChange = { user = it },
                        label = { Text("Username") },
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                        colors = fieldColors,
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = pass,
                        onValueChange = { pass = it },
                        label = { Text("Password") },
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                        colors = fieldColors,
                        singleLine = true,
                    )
                } else {
                    OutlinedTextField(
                        value = m3uUrl,
                        onValueChange = { m3uUrl = it },
                        label = { Text("M3U / M3U8 playlist URL") },
                        modifier = Modifier.fillMaxWidth(),
                        colors = fieldColors,
                        singleLine = true,
                    )
                }
                error?.let { ErrorText(it) }
                Button(
                    onClick = {
                        scope.launch {
                            loading = true
                            error = null
                            runCatching {
                                val c = if (loginMode == LoginMode.Xtream) {
                                    container.iptv.loginXtream(server, user, pass)
                                } else {
                                    container.iptv.loginM3u(m3uUrl)
                                }
                                creds = c
                                section = IptvSection.Live
                                loadSection(c, IptvSection.Live)
                            }.onFailure { error = it.message }
                            loading = false
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = PtAccent),
                    modifier = Modifier.padding(top = 16.dp),
                ) { Text("Connect") }
            }

            openSeries != null -> Column(Modifier.fillMaxSize()) {
                TextButton(onClick = {
                    openSeries = null
                    episodes = emptyList()
                }) { Text("← ${openSeries!!.name}", color = PtAccent) }
                if (listLoading) LoadingBox()
                LazyColumn(Modifier.fillMaxSize().padding(horizontal = 12.dp)) {
                    items(episodes, key = { it.episodeId }) { ep ->
                        Text(
                            "S${ep.season}E${ep.episodeNum}  ${ep.title}",
                            color = PtText,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                                .background(PtSurface, RoundedCornerShape(8.dp))
                                .clickable { play(ep.playUrl, ep.title) }
                                .padding(14.dp),
                        )
                    }
                }
            }

            else -> Column(Modifier.fillMaxSize()) {
                val tabs = buildList {
                    add(IptvSection.Live)
                    if (creds!!.isXtream) {
                        add(IptvSection.Movies)
                        add(IptvSection.Series)
                    }
                    add(IptvSection.Favorites)
                }
                val tabIndex = tabs.indexOf(section).coerceAtLeast(0)
                ScrollableTabRow(
                    selectedTabIndex = tabIndex,
                    containerColor = PtSurface,
                    contentColor = PtAccent,
                    edgePadding = 8.dp,
                ) {
                    tabs.forEachIndexed { idx, sec ->
                        Tab(
                            selected = section == sec,
                            onClick = {
                                section = sec
                                scope.launch { loadSection(creds!!, sec) }
                            },
                            text = { Text(sec.name) },
                        )
                    }
                }
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                        label = { Text("Filter") },
                        colors = fieldColors,
                    )
                    TextButton(onClick = {
                        scope.launch {
                            container.iptv.logout()
                            creds = null
                            channels = emptyList()
                            series = emptyList()
                            categories = emptyList()
                        }
                    }) { Text("Log out", color = PtAccent) }
                }
                error?.let { ErrorText(it) }
                epg?.let {
                    Text(
                        "EPG: ${it.title}",
                        color = PtAccent,
                        modifier = Modifier.padding(horizontal = 16.dp),
                        fontSize = 13.sp,
                    )
                    if (it.description.isNotBlank()) {
                        Text(
                            it.description,
                            color = PtMuted,
                            maxLines = 2,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
                            fontSize = 12.sp,
                        )
                    }
                }
                Row(Modifier.fillMaxSize()) {
                    if (categories.isNotEmpty()) {
                        LazyColumn(
                            Modifier
                                .width(if (isTelevision) 220.dp else 150.dp)
                                .fillMaxSize()
                                .background(PtSurface)
                                .padding(6.dp),
                        ) {
                            items(categories, key = { it.categoryId }) { cat ->
                                Text(
                                    cat.categoryName,
                                    color = if (cat.categoryId == selectedCat) PtAccent else PtText,
                                    fontSize = 13.sp,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { selectedCat = cat.categoryId }
                                        .padding(10.dp),
                                )
                            }
                        }
                    }
                    if (listLoading) {
                        LoadingBox()
                    } else {
                        LazyColumn(Modifier.weight(1f).padding(8.dp)) {
                            if (section == IptvSection.Series) {
                                val filtered = series.filter {
                                    query.isBlank() || it.name.contains(query, ignoreCase = true)
                                }
                                items(filtered, key = { it.seriesId }) { s ->
                                    Text(
                                        s.name,
                                        color = PtText,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(vertical = 4.dp)
                                            .background(PtSurface, RoundedCornerShape(8.dp))
                                            .clickable {
                                                scope.launch {
                                                    listLoading = true
                                                    openSeries = s
                                                    runCatching {
                                                        episodes = container.iptv.seriesEpisodes(
                                                            creds!!,
                                                            s.seriesId,
                                                        )
                                                    }.onFailure { error = it.message }
                                                    listLoading = false
                                                }
                                            }
                                            .padding(14.dp),
                                    )
                                }
                            } else {
                                val filtered = channels.filter {
                                    query.isBlank() || it.name.contains(query, ignoreCase = true)
                                }
                                items(filtered, key = { it.streamId }) { ch ->
                                    val isFav = ch.streamId in favorites
                                    Row(
                                        Modifier
                                            .fillMaxWidth()
                                            .padding(vertical = 4.dp)
                                            .background(PtSurface, RoundedCornerShape(8.dp))
                                            .padding(horizontal = 8.dp, vertical = 4.dp),
                                    ) {
                                        Text(
                                            ch.name,
                                            color = PtText,
                                            modifier = Modifier
                                                .weight(1f)
                                                .clickable {
                                                    if (section == IptvSection.Live && creds!!.isXtream) {
                                                        scope.launch {
                                                            epgStreamId = ch.streamId
                                                            epg = container.iptv.shortEpg(
                                                                creds!!,
                                                                ch.streamId,
                                                            )
                                                        }
                                                    }
                                                    play(ch.playUrl, ch.name)
                                                }
                                                .padding(10.dp),
                                        )
                                        TextButton(onClick = {
                                            scope.launch {
                                                favorites = container.iptv.toggleFavorite(ch.streamId)
                                                if (section == IptvSection.Favorites) {
                                                    loadSection(creds!!, IptvSection.Favorites)
                                                }
                                            }
                                        }) {
                                            Text(if (isFav) "★" else "☆", color = PtAccent)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (isTelevision) {
        Row(Modifier.fillMaxSize()) {
            TvSideNav(selected = "iptv") { id ->
                when (id) {
                    "home" -> onOpenTab("home")
                    "search" -> onOpenTab("search")
                    "iptv" -> Unit
                    "settings" -> onOpenTab("settings")
                }
            }
            body()
        }
    } else {
        body()
    }
}
