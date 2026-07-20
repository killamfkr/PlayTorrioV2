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
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.playtorrio.tv.data.AppContainer
import com.playtorrio.tv.data.iptv.CatalogSource
import com.playtorrio.tv.data.model.IptvCategory
import com.playtorrio.tv.data.model.IptvChannel
import com.playtorrio.tv.data.model.IptvCredentials
import com.playtorrio.tv.data.model.IptvEpisode
import com.playtorrio.tv.data.model.IptvEpgEntry
import com.playtorrio.tv.data.model.IptvSeries
import com.playtorrio.tv.data.model.TvGuideSlot
import com.playtorrio.tv.data.model.VerifiedPortal
import com.playtorrio.tv.ui.components.ErrorText
import com.playtorrio.tv.ui.components.LoadingBox
import com.playtorrio.tv.ui.components.TvSideNav
import com.playtorrio.tv.ui.player.PlayerActivity
import com.playtorrio.tv.ui.theme.PtAccent
import com.playtorrio.tv.ui.theme.PtMuted
import com.playtorrio.tv.ui.theme.PtSurface
import com.playtorrio.tv.ui.theme.PtText
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

private enum class MainTab { Browse, Discover, Guide }
private enum class BrowseSection { Live, Movies, Series, Favorites }
private enum class LoginMode { Xtream, M3u }

@Composable
fun IptvScreen(
    container: AppContainer,
    isTelevision: Boolean,
    onOpenTab: (String) -> Unit = {},
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var mainTab by remember { mutableStateOf(MainTab.Browse) }
    var creds by remember { mutableStateOf<IptvCredentials?>(null) }
    var loading by remember { mutableStateOf(true) }
    var listLoading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    var loginMode by remember { mutableStateOf(LoginMode.Xtream) }
    var server by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var m3uUrl by remember { mutableStateOf("") }

    var section by remember { mutableStateOf(BrowseSection.Live) }
    var categories by remember { mutableStateOf<List<IptvCategory>>(emptyList()) }
    var selectedCat by remember { mutableStateOf<String?>(null) }
    var channels by remember { mutableStateOf<List<IptvChannel>>(emptyList()) }
    var series by remember { mutableStateOf<List<IptvSeries>>(emptyList()) }
    var openSeries by remember { mutableStateOf<IptvSeries?>(null) }
    var episodes by remember { mutableStateOf<List<IptvEpisode>>(emptyList()) }
    var favorites by remember { mutableStateOf<Set<String>>(emptySet()) }
    var guideFavIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var query by remember { mutableStateOf("") }
    var epg by remember { mutableStateOf<IptvEpgEntry?>(null) }

    // Discover
    var catalogSource by remember { mutableStateOf(CatalogSource.BEST) }
    var scrapeBusy by remember { mutableStateOf(false) }
    var scrapeStatus by remember { mutableStateOf("") }
    var verifiedPortals by remember { mutableStateOf<List<VerifiedPortal>>(emptyList()) }

    // Guide
    var guideSlots by remember { mutableStateOf<List<TvGuideSlot>>(emptyList()) }
    var guideLoading by remember { mutableStateOf(false) }
    var guideStatus by remember { mutableStateOf("") }

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

    fun portalKeyForCreds(c: IptvCredentials): String =
        "${c.serverUrl}|${c.username}|${c.password}".lowercase()

    suspend fun refreshGuideFavs(c: IptvCredentials) {
        if (!c.isXtream) {
            guideFavIds = emptySet()
            return
        }
        guideFavIds = container.iptv.guideFavoriteIds(portalKeyForCreds(c))
    }

    suspend fun loadBrowse(c: IptvCredentials, sec: BrowseSection) {
        listLoading = true
        error = null
        openSeries = null
        episodes = emptyList()
        epg = null
        try {
            when (sec) {
                BrowseSection.Live -> {
                    categories = container.iptv.liveCategories(c)
                    selectedCat = categories.firstOrNull()?.categoryId
                    channels = container.iptv.liveStreams(c, selectedCat)
                    series = emptyList()
                    refreshGuideFavs(c)
                }
                BrowseSection.Movies -> {
                    categories = container.iptv.vodCategories(c)
                    selectedCat = categories.firstOrNull()?.categoryId
                    channels = container.iptv.vodStreams(c, selectedCat)
                    series = emptyList()
                }
                BrowseSection.Series -> {
                    categories = container.iptv.seriesCategories(c)
                    selectedCat = categories.firstOrNull()?.categoryId
                    series = container.iptv.seriesList(c, selectedCat)
                    channels = emptyList()
                }
                BrowseSection.Favorites -> {
                    categories = emptyList()
                    selectedCat = null
                    val favs = container.iptv.favoriteIds()
                    favorites = favs
                    val live = container.iptv.liveStreams(c, null)
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

    suspend fun reloadGuide() {
        guideLoading = true
        guideStatus = "Loading TV Guide…"
        guideSlots = runCatching { container.iptv.buildTvGuideSlots() }
            .onFailure { guideStatus = it.message ?: "Guide failed" }
            .getOrDefault(emptyList())
        guideLoading = false
        guideStatus = if (guideSlots.isEmpty()) {
            "Star live channels in Browse (TV★) to build your guide."
        } else {
            "${guideSlots.size} channel(s)"
        }
    }

    LaunchedEffect(Unit) {
        loading = true
        favorites = container.iptv.favoriteIds()
        verifiedPortals = container.iptv.verifiedPortals()
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
                }
                loadBrowse(saved, section)
            }.onFailure { error = it.message }
        }
        loading = false
    }

    LaunchedEffect(selectedCat, section, creds, mainTab) {
        val c = creds ?: return@LaunchedEffect
        if (mainTab != MainTab.Browse) return@LaunchedEffect
        if (section == BrowseSection.Favorites || openSeries != null) return@LaunchedEffect
        listLoading = true
        runCatching {
            when (section) {
                BrowseSection.Live -> {
                    channels = container.iptv.liveStreams(c, selectedCat)
                    refreshGuideFavs(c)
                }
                BrowseSection.Movies -> channels = container.iptv.vodStreams(c, selectedCat)
                BrowseSection.Series -> series = container.iptv.seriesList(c, selectedCat)
                BrowseSection.Favorites -> Unit
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
        Column(Modifier.fillMaxSize()) {
            Text(
                "IPTV",
                color = PtText,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp),
            )
            Text(
                "Scrape portals, browse live/VOD, play from TV Guide.",
                color = PtMuted,
                fontSize = 13.sp,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )

            ScrollableTabRow(
                selectedTabIndex = MainTab.entries.indexOf(mainTab),
                containerColor = PtSurface,
                contentColor = PtAccent,
                edgePadding = 8.dp,
            ) {
                MainTab.entries.forEach { tab ->
                    Tab(
                        selected = mainTab == tab,
                        onClick = {
                            mainTab = tab
                            if (tab == MainTab.Guide) {
                                scope.launch { reloadGuide() }
                            }
                            if (tab == MainTab.Discover) {
                                scope.launch {
                                    verifiedPortals = container.iptv.verifiedPortals()
                                }
                            }
                        },
                        text = { Text(tab.name) },
                    )
                }
            }

            when (mainTab) {
                MainTab.Discover -> DiscoverPane(
                    catalogSource = catalogSource,
                    onSource = { catalogSource = it },
                    scrapeBusy = scrapeBusy,
                    scrapeStatus = scrapeStatus,
                    verifiedPortals = verifiedPortals,
                    chipColors = chipColors,
                    onScrape = {
                        scope.launch {
                            scrapeBusy = true
                            scrapeStatus = "Scraping catalog…"
                            runCatching {
                                val portals = container.iptv.scrapeCatalog(catalogSource) {
                                    scrapeStatus = it
                                }
                                scrapeStatus = "Verifying ${portals.size} candidate(s)…"
                                val alive = container.iptv.verifyBatch(portals, target = 5) { checked, aliveCount ->
                                    scrapeStatus = "Verified $checked — $aliveCount working"
                                }
                                verifiedPortals = container.iptv.verifiedPortals()
                                scrapeStatus = "Saved ${alive.size} working portal(s). ${verifiedPortals.size} total."
                                if (alive.isNotEmpty() && creds == null) {
                                    val c = container.iptv.openVerifiedAsSession(alive.first())
                                    creds = c
                                    server = c.serverUrl
                                    user = c.username
                                    pass = c.password
                                    loginMode = LoginMode.Xtream
                                }
                            }.onFailure { scrapeStatus = it.message ?: "Scrape failed" }
                            scrapeBusy = false
                        }
                    },
                    onSelectPortal = { portal ->
                        scope.launch {
                            loading = true
                            runCatching {
                                val c = container.iptv.openVerifiedAsSession(portal)
                                creds = c
                                server = c.serverUrl
                                user = c.username
                                pass = c.password
                                loginMode = LoginMode.Xtream
                                section = BrowseSection.Live
                                mainTab = MainTab.Browse
                                loadBrowse(c, BrowseSection.Live)
                            }.onFailure { error = it.message }
                            loading = false
                        }
                    },
                    onClear = {
                        scope.launch {
                            container.iptv.clearVerifiedPortals()
                            verifiedPortals = emptyList()
                            scrapeStatus = "Cleared verified portals."
                        }
                    },
                )

                MainTab.Guide -> GuidePane(
                    slots = guideSlots,
                    loading = guideLoading,
                    status = guideStatus,
                    onRefresh = { scope.launch { reloadGuide() } },
                    onPlay = { slot -> play(slot.channel.playUrl, slot.channel.name) },
                    onRemove = { slot ->
                        scope.launch {
                            container.iptv.toggleGuideFavorite(slot.portal.key, slot.channel.streamId)
                            reloadGuide()
                            creds?.let { refreshGuideFavs(it) }
                        }
                    },
                )

                MainTab.Browse -> when {
                    loading -> LoadingBox()
                    creds == null -> Column(Modifier.fillMaxSize().padding(20.dp)) {
                        Text(
                            "Xtream, M3U, or use Discover to scrape portals.",
                            color = PtMuted,
                            modifier = Modifier.padding(bottom = 12.dp),
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
                                        verifiedPortals = container.iptv.verifiedPortals()
                                        section = BrowseSection.Live
                                        loadBrowse(c, BrowseSection.Live)
                                    }.onFailure { error = it.message }
                                    loading = false
                                }
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = PtAccent),
                            modifier = Modifier.padding(top = 16.dp),
                        ) { Text("Connect") }
                        if (verifiedPortals.isNotEmpty()) {
                            Spacer(Modifier.height(16.dp))
                            Text("Or open a verified portal", color = PtMuted, fontSize = 13.sp)
                            verifiedPortals.take(8).forEach { portal ->
                                TextButton(onClick = {
                                    scope.launch {
                                        loading = true
                                        runCatching {
                                            val c = container.iptv.openVerifiedAsSession(portal)
                                            creds = c
                                            server = c.serverUrl
                                            user = c.username
                                            pass = c.password
                                            loadBrowse(c, BrowseSection.Live)
                                        }.onFailure { error = it.message }
                                        loading = false
                                    }
                                }) {
                                    Text(
                                        portalDisplay(portal),
                                        color = PtAccent,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        }
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
                        if (verifiedPortals.isNotEmpty() && creds!!.isXtream) {
                            Row(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 8.dp, vertical = 4.dp),
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                verifiedPortals.take(6).forEach { portal ->
                                    FilterChip(
                                        selected = portalKeyForCreds(creds!!) == portal.key,
                                        onClick = {
                                            scope.launch {
                                                listLoading = true
                                                runCatching {
                                                    val c = container.iptv.openVerifiedAsSession(portal)
                                                    creds = c
                                                    server = c.serverUrl
                                                    user = c.username
                                                    pass = c.password
                                                    loadBrowse(c, section)
                                                }.onFailure { error = it.message }
                                                listLoading = false
                                            }
                                        },
                                        label = {
                                            Text(
                                                portalHost(portal),
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                        },
                                        colors = chipColors,
                                    )
                                }
                            }
                        }

                        val tabs = buildList {
                            add(BrowseSection.Live)
                            if (creds!!.isXtream) {
                                add(BrowseSection.Movies)
                                add(BrowseSection.Series)
                            }
                            add(BrowseSection.Favorites)
                        }
                        val tabIndex = tabs.indexOf(section).coerceAtLeast(0)
                        ScrollableTabRow(
                            selectedTabIndex = tabIndex,
                            containerColor = PtSurface,
                            contentColor = PtAccent,
                            edgePadding = 8.dp,
                        ) {
                            tabs.forEach { sec ->
                                Tab(
                                    selected = section == sec,
                                    onClick = {
                                        section = sec
                                        scope.launch { loadBrowse(creds!!, sec) }
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
                                    if (section == BrowseSection.Series) {
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
                                            val inGuide = ch.streamId in guideFavIds
                                            Row(
                                                Modifier
                                                    .fillMaxWidth()
                                                    .padding(vertical = 4.dp)
                                                    .background(PtSurface, RoundedCornerShape(8.dp))
                                                    .padding(horizontal = 4.dp, vertical = 2.dp),
                                            ) {
                                                Text(
                                                    ch.name,
                                                    color = PtText,
                                                    modifier = Modifier
                                                        .weight(1f)
                                                        .clickable {
                                                            if (section == BrowseSection.Live && creds!!.isXtream) {
                                                                scope.launch {
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
                                                        if (section == BrowseSection.Favorites) {
                                                            loadBrowse(creds!!, BrowseSection.Favorites)
                                                        }
                                                    }
                                                }) {
                                                    Text(if (isFav) "♥" else "♡", color = PtAccent)
                                                }
                                                if (section == BrowseSection.Live && creds!!.isXtream) {
                                                    TextButton(onClick = {
                                                        scope.launch {
                                                            val key = portalKeyForCreds(creds!!)
                                                            guideFavIds = container.iptv.toggleGuideFavorite(
                                                                key,
                                                                ch.streamId,
                                                            )
                                                        }
                                                    }) {
                                                        Text(if (inGuide) "TV★" else "TV☆", color = PtAccent, fontSize = 12.sp)
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

@Composable
private fun DiscoverPane(
    catalogSource: CatalogSource,
    onSource: (CatalogSource) -> Unit,
    scrapeBusy: Boolean,
    scrapeStatus: String,
    verifiedPortals: List<VerifiedPortal>,
    chipColors: androidx.compose.material3.SelectableChipColors,
    onScrape: () -> Unit,
    onSelectPortal: (VerifiedPortal) -> Unit,
    onClear: () -> Unit,
) {
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text("Catalog scraper", color = PtText, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        Text(
            "Pull portal lists from the remote catalog, verify logins, then open in Browse or star channels for TV Guide.",
            color = PtMuted,
            fontSize = 13.sp,
            modifier = Modifier.padding(top = 4.dp, bottom = 12.dp),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = catalogSource == CatalogSource.BEST,
                onClick = { onSource(CatalogSource.BEST) },
                label = { Text("best") },
                enabled = !scrapeBusy,
                colors = chipColors,
            )
            FilterChip(
                selected = catalogSource == CatalogSource.WORKS,
                onClick = { onSource(CatalogSource.WORKS) },
                label = { Text("works") },
                enabled = !scrapeBusy,
                colors = chipColors,
            )
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = onScrape,
                enabled = !scrapeBusy,
                colors = ButtonDefaults.buttonColors(containerColor = PtAccent),
            ) {
                Text(if (scrapeBusy) "Working…" else "Scrape & verify")
            }
            if (verifiedPortals.isNotEmpty()) {
                OutlinedButton(onClick = onClear, enabled = !scrapeBusy) {
                    Text("Clear saved", color = PtAccent)
                }
            }
        }
        if (scrapeBusy) {
            Spacer(Modifier.height(12.dp))
            LoadingBox()
        }
        if (scrapeStatus.isNotBlank()) {
            Text(scrapeStatus, color = PtMuted, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
        }
        Spacer(Modifier.height(16.dp))
        Text("Verified portals", color = PtText, fontWeight = FontWeight.Medium)
        Spacer(Modifier.height(8.dp))
        if (verifiedPortals.isEmpty()) {
            Text("None yet — run Scrape & verify.", color = PtMuted)
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(verifiedPortals, key = { it.key }) { portal ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .background(PtSurface, RoundedCornerShape(10.dp))
                            .clickable { onSelectPortal(portal) }
                            .padding(14.dp),
                    ) {
                        Text(portalDisplay(portal), color = PtText, fontWeight = FontWeight.Medium)
                        Text(
                            "${portal.portal.username} · open in Browse",
                            color = PtMuted,
                            fontSize = 12.sp,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun GuidePane(
    slots: List<TvGuideSlot>,
    loading: Boolean,
    status: String,
    onRefresh: () -> Unit,
    onPlay: (TvGuideSlot) -> Unit,
    onRemove: (TvGuideSlot) -> Unit,
) {
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Column(Modifier.weight(1f)) {
                Text("TV Guide", color = PtText, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
                Text(status, color = PtMuted, fontSize = 13.sp)
            }
            TextButton(onClick = onRefresh) { Text("Refresh", color = PtAccent) }
        }
        Text(
            "Star channels in Browse with TV★ to pin them here with EPG. Tap a row to play.",
            color = PtMuted,
            fontSize = 12.sp,
            modifier = Modifier.padding(vertical = 8.dp),
        )
        when {
            loading -> LoadingBox()
            slots.isEmpty() -> Text("No guide channels yet.", color = PtMuted)
            else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(slots, key = { "${it.portal.key}:${it.channel.streamId}" }) { slot ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .background(PtSurface, RoundedCornerShape(10.dp))
                            .clickable { onPlay(slot) }
                            .padding(14.dp),
                    ) {
                        Row(Modifier.fillMaxWidth()) {
                            Column(Modifier.weight(1f)) {
                                Text(slot.channel.name, color = PtText, fontWeight = FontWeight.Medium)
                                Text(slot.host, color = PtMuted, fontSize = 12.sp)
                            }
                            TextButton(onClick = { onPlay(slot) }) { Text("Play", color = PtAccent) }
                            TextButton(onClick = { onRemove(slot) }) { Text("TV★", color = PtAccent) }
                        }
                        val now = slot.programs.firstOrNull { it.isNow } ?: slot.programs.firstOrNull()
                        if (now != null) {
                            Text(now.title, color = PtText, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            Text(
                                formatEpgWindow(now.startMs, now.stopMs),
                                color = PtMuted,
                                fontSize = 12.sp,
                            )
                            val next = slot.programs.firstOrNull { it.startMs > now.stopMs }
                                ?: slot.programs.getOrNull(1)
                            if (next != null) {
                                Text(
                                    "Next: ${next.title}",
                                    color = PtMuted,
                                    fontSize = 12.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        } else {
                            Text("No EPG for this channel", color = PtMuted, fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }
}

private fun portalHost(portal: VerifiedPortal): String =
    runCatching { java.net.URI(portal.portal.url).host.orEmpty() }
        .getOrDefault(portal.portal.url)
        .ifBlank { portal.portal.url }
        .take(28)

private fun portalDisplay(portal: VerifiedPortal): String {
    val host = portalHost(portal)
    val name = portal.name.ifBlank { portal.portal.username }
    return "$host · $name"
}

private fun formatEpgWindow(startMs: Long, endMs: Long): String {
    if (startMs <= 0L && endMs <= 0L) return ""
    val fmt = SimpleDateFormat("HH:mm", Locale.getDefault()).apply {
        timeZone = TimeZone.getDefault()
    }
    val a = if (startMs > 0) fmt.format(Date(startMs)) else "?"
    val b = if (endMs > 0) fmt.format(Date(endMs)) else "?"
    return "$a – $b"
}
