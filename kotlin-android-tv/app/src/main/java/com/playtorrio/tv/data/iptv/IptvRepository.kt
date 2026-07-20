package com.playtorrio.tv.data.iptv

import com.playtorrio.tv.data.model.IptvCategory
import com.playtorrio.tv.data.model.IptvChannel
import com.playtorrio.tv.data.model.IptvCredentials
import com.playtorrio.tv.data.model.IptvEpisode
import com.playtorrio.tv.data.model.IptvEpgEntry
import com.playtorrio.tv.data.model.IptvEpgProgram
import com.playtorrio.tv.data.model.IptvPortal
import com.playtorrio.tv.data.model.IptvSeries
import com.playtorrio.tv.data.model.TvGuideSlot
import com.playtorrio.tv.data.model.VerifiedPortal
import com.playtorrio.tv.data.prefs.PrefsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Base64

/**
 * IPTV data layer matching Flutter PlayTorrio IPTV (M3U) tab capabilities:
 * Xtream live / VOD / series + M3U playlists + short EPG + favorites.
 */
class IptvRepository(
    private val http: OkHttpClient,
    private val prefs: PrefsRepository,
    private val scraper: IptvScraper = IptvScraper(http),
) {
    private val json = Json { ignoreUnknownKeys = true }

    /** Cached M3U channels for the current session. */
    @Volatile
    private var m3uChannels: List<IptvChannel> = emptyList()

    @Volatile
    private var m3uCategories: List<IptvCategory> = emptyList()

    suspend fun savedCredentials(): IptvCredentials? = prefs.getIptvCredentials()

    suspend fun logout() {
        prefs.clearIptvCredentials()
        m3uChannels = emptyList()
        m3uCategories = emptyList()
    }

    suspend fun loginXtream(serverUrl: String, username: String, password: String): IptvCredentials =
        withContext(Dispatchers.IO) {
            val base = serverUrl.trim().trimEnd('/')
            val url = "$base/player_api.php".toHttpUrl().newBuilder()
                .addQueryParameter("username", username)
                .addQueryParameter("password", password)
                .build()
            val body = get(url.toString())
            val root = json.parseToJsonElement(body).jsonObject
            val info = root["user_info"]?.jsonObject ?: root
            val auth = info["auth"]?.jsonPrimitive?.contentOrNull
            val status = info["status"]?.jsonPrimitive?.contentOrNull?.lowercase()
            val ok = auth == "1" || status == "active" || root.containsKey("user_info")
            if (!ok) error("IPTV login failed")
            val creds = IptvCredentials(
                type = "xtream",
                serverUrl = base,
                username = username,
                password = password,
            )
            prefs.saveIptvCredentials(creds)
            // Also keep as verified portal for TV Guide starring
            runCatching {
                verifyAndSave(IptvPortal(url = base, username = username, password = password, source = "manual"))
            }
            creds
        }

    suspend fun loginM3u(playlistUrl: String): IptvCredentials = withContext(Dispatchers.IO) {
        val parsed = parseM3uFromUrl(playlistUrl)
        m3uChannels = parsed.first
        m3uCategories = parsed.second
        val creds = IptvCredentials(type = "m3u", m3uUrl = playlistUrl.trim())
        prefs.saveIptvCredentials(creds)
        creds
    }

    suspend fun restoreSession(creds: IptvCredentials) {
        if (creds.isM3u && creds.m3uUrl.isNotBlank()) {
            val parsed = parseM3uFromUrl(creds.m3uUrl)
            m3uChannels = parsed.first
            m3uCategories = parsed.second
        }
    }

    // ── Live ────────────────────────────────────────────────────────────

    suspend fun liveCategories(creds: IptvCredentials): List<IptvCategory> =
        withContext(Dispatchers.IO) {
            if (creds.isM3u) return@withContext m3uCategories
            parseCategories(get(api(creds, "get_live_categories")))
        }

    suspend fun liveStreams(creds: IptvCredentials, categoryId: String? = null): List<IptvChannel> =
        withContext(Dispatchers.IO) {
            if (creds.isM3u) {
                return@withContext m3uChannels.filter {
                    categoryId == null || it.categoryId == categoryId
                }
            }
            val url = if (categoryId != null) {
                api(creds, "get_live_streams", mapOf("category_id" to categoryId))
            } else {
                api(creds, "get_live_streams")
            }
            parseLiveOrVod(get(url), creds, kind = "live")
        }

    // ── VOD / Movies ────────────────────────────────────────────────────

    suspend fun vodCategories(creds: IptvCredentials): List<IptvCategory> =
        withContext(Dispatchers.IO) {
            if (creds.isM3u) return@withContext emptyList()
            parseCategories(get(api(creds, "get_vod_categories")))
        }

    suspend fun vodStreams(creds: IptvCredentials, categoryId: String? = null): List<IptvChannel> =
        withContext(Dispatchers.IO) {
            if (creds.isM3u) return@withContext emptyList()
            val url = if (categoryId != null) {
                api(creds, "get_vod_streams", mapOf("category_id" to categoryId))
            } else {
                api(creds, "get_vod_streams")
            }
            parseLiveOrVod(get(url), creds, kind = "movie")
        }

    // ── Series ──────────────────────────────────────────────────────────

    suspend fun seriesCategories(creds: IptvCredentials): List<IptvCategory> =
        withContext(Dispatchers.IO) {
            if (creds.isM3u) return@withContext emptyList()
            parseCategories(get(api(creds, "get_series_categories")))
        }

    suspend fun seriesList(creds: IptvCredentials, categoryId: String? = null): List<IptvSeries> =
        withContext(Dispatchers.IO) {
            if (creds.isM3u) return@withContext emptyList()
            val url = if (categoryId != null) {
                api(creds, "get_series", mapOf("category_id" to categoryId))
            } else {
                api(creds, "get_series")
            }
            val arr = runCatching { json.parseToJsonElement(get(url)).jsonArray }
                .getOrDefault(JsonArray(emptyList()))
            arr.mapNotNull { el ->
                val o = el as? JsonObject ?: return@mapNotNull null
                val id = o.str("series_id") ?: return@mapNotNull null
                IptvSeries(
                    seriesId = id,
                    name = o.str("name") ?: "Series $id",
                    cover = o.str("cover"),
                    categoryId = o.str("category_id"),
                    plot = o.str("plot"),
                )
            }
        }

    suspend fun seriesEpisodes(creds: IptvCredentials, seriesId: String): List<IptvEpisode> =
        withContext(Dispatchers.IO) {
            if (creds.isM3u) return@withContext emptyList()
            val body = get(api(creds, "get_series_info", mapOf("series_id" to seriesId)))
            val root = json.parseToJsonElement(body).jsonObject
            val episodesObj = root["episodes"]?.jsonObject ?: return@withContext emptyList()
            val out = mutableListOf<IptvEpisode>()
            for ((seasonKey, seasonVal) in episodesObj) {
                val seasonNum = seasonKey.toIntOrNull() ?: continue
                val arr = seasonVal.jsonArray
                for (epEl in arr) {
                    val o = epEl as? JsonObject ?: continue
                    val id = o.str("id") ?: continue
                    val ext = o.str("container_extension") ?: "mp4"
                    val epNum = o["episode_num"]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
                        ?: o.str("episode_num")?.toIntOrNull()
                        ?: 0
                    val title = o.str("title") ?: "S${seasonNum}E$epNum"
                    out += IptvEpisode(
                        episodeId = id,
                        title = title,
                        season = seasonNum,
                        episodeNum = epNum,
                        containerExtension = ext,
                        playUrl = "${creds.serverUrl}/series/${enc(creds.username)}/${enc(creds.password)}/$id.$ext",
                    )
                }
            }
            out.sortedWith(compareBy({ it.season }, { it.episodeNum }))
        }

    // ── EPG ─────────────────────────────────────────────────────────────

    suspend fun shortEpg(creds: IptvCredentials, streamId: String): IptvEpgEntry? =
        withContext(Dispatchers.IO) {
            if (creds.isM3u) return@withContext null
            runCatching {
                val body = get(
                    api(creds, "get_short_epg", mapOf("stream_id" to streamId, "limit" to "2")),
                )
                val listings = json.parseToJsonElement(body).jsonObject["epg_listings"]?.jsonArray
                    ?: return@runCatching null
                val first = listings.firstOrNull()?.jsonObject ?: return@runCatching null
                val titleRaw = first.str("title").orEmpty()
                val descRaw = first.str("description").orEmpty()
                IptvEpgEntry(
                    title = decodeMaybeBase64(titleRaw).ifBlank { "Now" },
                    description = decodeMaybeBase64(descRaw),
                    start = first.str("start"),
                    end = first.str("end"),
                )
            }.getOrNull()
        }

    // ── Favorites ───────────────────────────────────────────────────────

    suspend fun favoriteIds(): Set<String> = prefs.getIptvFavoriteIds()

    suspend fun toggleFavorite(streamId: String): Set<String> {
        val cur = prefs.getIptvFavoriteIds().toMutableSet()
        if (!cur.add(streamId)) cur.remove(streamId)
        prefs.saveIptvFavoriteIds(cur)
        return cur
    }

    // ── M3U ─────────────────────────────────────────────────────────────

    private fun parseM3uFromUrl(url: String): Pair<List<IptvChannel>, List<IptvCategory>> {
        val body = get(url)
        if (!body.trimStart().startsWith("#EXTM3U")) error("Invalid M3U playlist")
        return parseM3u(body)
    }

    private fun parseM3u(content: String): Pair<List<IptvChannel>, List<IptvCategory>> {
        val lines = content.replace("\r\n", "\n").replace('\r', '\n').split('\n')
        val channels = mutableListOf<IptvChannel>()
        val groups = linkedSetOf<String>()
        var autoId = 1
        var i = 0
        while (i < lines.size - 1) {
            val line = lines[i].trim()
            if (line.startsWith("#EXTINF:")) {
                var streamUrl: String? = null
                for (j in (i + 1) until lines.size) {
                    val next = lines[j].trim()
                    if (next.isEmpty() || next.startsWith("#")) continue
                    streamUrl = next
                    break
                }
                if (!streamUrl.isNullOrBlank()) {
                    val name = line.substringAfterLast(',', "Channel $autoId").trim()
                    val logo = attr(line, "tvg-logo")
                    val group = attr(line, "group-title") ?: "Uncategorized"
                    groups += group
                    channels += IptvChannel(
                        streamId = "m3u-$autoId",
                        name = name.ifBlank { "Channel $autoId" },
                        streamIcon = logo,
                        categoryId = group,
                        playUrl = streamUrl,
                        kind = "live",
                    )
                    autoId++
                }
            }
            i++
        }
        val cats = groups.map { IptvCategory(it, it) }.sortedBy { it.categoryName }
        return channels to cats
    }

    private fun attr(line: String, key: String): String? {
        val re = Regex("""$key="([^"]*)"""")
        return re.find(line)?.groupValues?.getOrNull(1)
    }

    // ── Catalog scraper + verified portals + TV Guide ───────────────────

    suspend fun scrapeCatalog(
        source: CatalogSource,
        maxPages: Int = 3,
        onStatus: (String) -> Unit = {},
    ): List<IptvPortal> = withContext(Dispatchers.IO) {
        val all = linkedMapOf<String, IptvPortal>()
        var after: String? = null
        for (page in 0 until maxPages) {
            onStatus("Scraping page ${page + 1}…")
            val result = scraper.scrapePage(source, after)
            if (result.error != null && result.portals.isEmpty()) {
                onStatus(result.error)
                break
            }
            result.portals.forEach { all.putIfAbsent(it.key, it) }
            after = result.nextAfter
            if (after.isNullOrBlank()) break
        }
        onStatus("Found ${all.size} portal candidate(s)")
        all.values.toList()
    }

    suspend fun verifiedPortals(): List<VerifiedPortal> = prefs.getVerifiedPortals()

    suspend fun clearVerifiedPortals() = prefs.clearVerifiedPortals()

    suspend fun verifyAndSave(portal: IptvPortal): VerifiedPortal = withContext(Dispatchers.IO) {
        val url = "${portal.url.trimEnd('/')}/player_api.php".toHttpUrl().newBuilder()
            .addQueryParameter("username", portal.username)
            .addQueryParameter("password", portal.password)
            .build()
        val body = get(url.toString())
        val root = json.parseToJsonElement(body).jsonObject
        val info = root["user_info"]?.jsonObject ?: root
        val auth = info["auth"]?.jsonPrimitive?.contentOrNull
        val status = info["status"]?.jsonPrimitive?.contentOrNull?.lowercase()
        val ok = auth == "1" || status == "active" || root.containsKey("user_info")
        if (!ok) error("Portal login failed")
        val verified = VerifiedPortal(
            portal = portal,
            name = info.str("username") ?: portal.username,
            expiry = info.str("exp_date").orEmpty(),
            maxConnections = info.str("max_connections") ?: "1",
            activeConnections = info.str("active_cons") ?: "0",
        )
        val next = prefs.getVerifiedPortals()
            .filterNot { it.key == verified.key || it.portal.credKey == verified.portal.credKey } +
            verified
        prefs.saveVerifiedPortals(next)
        verified
    }

    /** Verify up to [target] alive portals from [candidates] (parallelism 4). */
    suspend fun verifyBatch(
        candidates: List<IptvPortal>,
        target: Int = 5,
        onProgress: (checked: Int, alive: Int) -> Unit = { _, _ -> },
    ): List<VerifiedPortal> = coroutineScope {
        val alive = mutableListOf<VerifiedPortal>()
        var checked = 0
        val queue = candidates.toMutableList()
        while (queue.isNotEmpty() && alive.size < target) {
            val batch = List(minOf(4, queue.size)) { queue.removeAt(0) }
            val results = batch.map { p ->
                async(Dispatchers.IO) {
                    runCatching { verifyAndSave(p) }.getOrNull()
                }
            }.awaitAll()
            checked += batch.size
            results.filterNotNull().forEach { alive += it }
            onProgress(checked, alive.size)
        }
        alive
    }


    suspend fun openVerifiedAsSession(v: VerifiedPortal): IptvCredentials {
        val creds = IptvCredentials(
            type = "xtream",
            serverUrl = v.portal.url.trimEnd('/'),
            username = v.portal.username,
            password = v.portal.password,
        )
        prefs.saveIptvCredentials(creds)
        return creds
    }

    suspend fun guideFavoriteIds(portalKey: String): Set<String> =
        prefs.getGuideFavoriteIds(portalKey)

    suspend fun toggleGuideFavorite(portalKey: String, streamId: String): Set<String> {
        val cur = prefs.getGuideFavoriteIds(portalKey).toMutableSet()
        if (!cur.add(streamId)) cur.remove(streamId)
        prefs.saveGuideFavoriteIds(portalKey, cur)
        return cur
    }

    /** Build TV Guide slots from starred live channels across verified portals. */
    suspend fun buildTvGuideSlots(): List<TvGuideSlot> = withContext(Dispatchers.IO) {
        val portals = prefs.getVerifiedPortals()
        val slots = mutableListOf<TvGuideSlot>()
        for (v in portals) {
            val favIds = prefs.getGuideFavoriteIds(v.key)
            if (favIds.isEmpty()) continue
            val creds = IptvCredentials(
                type = "xtream",
                serverUrl = v.portal.url.trimEnd('/'),
                username = v.portal.username,
                password = v.portal.password,
            )
            val live = runCatching { liveStreams(creds, null) }.getOrDefault(emptyList())
            val byId = live.associateBy { it.streamId }
            for (id in favIds) {
                val ch = byId[id] ?: IptvChannel(
                    streamId = id,
                    name = "Starred channel",
                    playUrl = "${creds.serverUrl}/live/${enc(creds.username)}/${enc(creds.password)}/$id.ts",
                    kind = "live",
                    containerExtension = "ts",
                )
                val programs = runCatching {
                    shortEpgPrograms(creds, ch.streamId, limit = 6)
                }.getOrDefault(emptyList())
                slots += TvGuideSlot(portal = v, channel = ch, programs = programs)
            }
        }
        slots.sortedWith(
            compareBy({ it.portal.name.ifBlank { it.portal.portal.username } }, { it.channel.name }),
        )
    }

    suspend fun shortEpgPrograms(
        creds: IptvCredentials,
        streamId: String,
        limit: Int = 12,
    ): List<IptvEpgProgram> = withContext(Dispatchers.IO) {
        if (creds.isM3u || streamId.isBlank()) return@withContext emptyList()
        runCatching {
            val body = get(
                api(creds, "get_short_epg", mapOf("stream_id" to streamId, "limit" to "$limit")),
            )
            val root = json.parseToJsonElement(body)
            val arr = when {
                root is JsonObject -> root["epg_listings"]?.jsonArray
                else -> null
            } ?: return@runCatching emptyList()
            arr.mapNotNull { el ->
                val o = el as? JsonObject ?: return@mapNotNull null
                val start = parseEpgTs(o["start_timestamp"]) ?: parseEpgTs(o["start"])
                    ?: return@mapNotNull null
                val stop = parseEpgTs(o["stop_timestamp"]) ?: parseEpgTs(o["end"])
                    ?: return@mapNotNull null
                IptvEpgProgram(
                    title = decodeMaybeBase64(o.str("title").orEmpty()).ifBlank { "Program" },
                    description = decodeMaybeBase64(o.str("description").orEmpty()),
                    startMs = start,
                    stopMs = stop,
                )
            }.sortedBy { it.startMs }
        }.getOrDefault(emptyList())
    }

    private fun parseEpgTs(v: kotlinx.serialization.json.JsonElement?): Long? {
        val s = v?.jsonPrimitive?.contentOrNull ?: return null
        val secs = s.toLongOrNull()
        if (secs != null && secs > 1_000_000_000L) return secs * 1000L
        return runCatching {
            java.time.LocalDateTime.parse(s.replace(' ', 'T'))
                .atZone(java.time.ZoneId.systemDefault())
                .toInstant()
                .toEpochMilli()
        }.getOrNull()
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private fun parseCategories(body: String): List<IptvCategory> {
        val arr = runCatching { json.parseToJsonElement(body).jsonArray }
            .getOrDefault(JsonArray(emptyList()))
        return arr.mapNotNull { el ->
            val o = el as? JsonObject ?: return@mapNotNull null
            val id = o.str("category_id") ?: return@mapNotNull null
            IptvCategory(id, o.str("category_name") ?: id)
        }
    }

    private fun parseLiveOrVod(
        body: String,
        creds: IptvCredentials,
        kind: String,
    ): List<IptvChannel> {
        val arr = runCatching { json.parseToJsonElement(body).jsonArray }
            .getOrDefault(JsonArray(emptyList()))
        return arr.mapNotNull { el ->
            val o = el as? JsonObject ?: return@mapNotNull null
            val id = o.str("stream_id") ?: return@mapNotNull null
            val name = o.str("name") ?: "Stream $id"
            val icon = o.str("stream_icon") ?: o.str("cover")
            val cat = o.str("category_id")
            val ext = o.str("container_extension") ?: if (kind == "live") "m3u8" else "mp4"
            val playUrl = when (kind) {
                "movie" -> "${creds.serverUrl}/movie/${enc(creds.username)}/${enc(creds.password)}/$id.$ext"
                else -> "${creds.serverUrl}/live/${enc(creds.username)}/${enc(creds.password)}/$id.$ext"
            }
            IptvChannel(
                streamId = id,
                name = name,
                streamIcon = icon,
                categoryId = cat,
                playUrl = playUrl,
                containerExtension = ext,
                kind = kind,
            )
        }
    }

    private fun api(
        creds: IptvCredentials,
        action: String,
        extra: Map<String, String> = emptyMap(),
    ): String {
        val b = "${creds.serverUrl}/player_api.php".toHttpUrl().newBuilder()
            .addQueryParameter("username", creds.username)
            .addQueryParameter("password", creds.password)
            .addQueryParameter("action", action)
        extra.forEach { (k, v) -> b.addQueryParameter(k, v) }
        return b.build().toString()
    }

    private fun JsonObject.str(key: String): String? =
        this[key]?.jsonPrimitive?.contentOrNull

    private fun enc(s: String) = URLEncoder.encode(s, StandardCharsets.UTF_8.name())

    private fun decodeMaybeBase64(raw: String): String {
        if (raw.isBlank()) return raw
        return runCatching {
            val decoded = String(Base64.getDecoder().decode(raw), StandardCharsets.UTF_8)
            if (decoded.any { it.code < 9 && it != '\n' && it != '\r' && it != '\t' }) raw else decoded
        }.getOrDefault(raw)
    }

    private fun get(url: String): String {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", "VLC/3.0.20 LibVLC/3.0.20")
            .header("Accept", "*/*")
            .get()
            .build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("IPTV ${resp.code}")
            return resp.body?.string().orEmpty()
        }
    }
}
