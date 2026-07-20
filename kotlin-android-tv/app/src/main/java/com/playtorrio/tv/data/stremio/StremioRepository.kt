package com.playtorrio.tv.data.stremio

import com.playtorrio.tv.data.model.StremioAddon
import com.playtorrio.tv.data.model.StremioStream
import com.playtorrio.tv.data.prefs.PrefsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request

class StremioRepository(
    private val http: OkHttpClient,
    private val prefs: PrefsRepository,
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun listAddons(): List<StremioAddon> = prefs.getAddons()

    suspend fun installDefaultIfNeeded() {
        if (prefs.getAddons().isNotEmpty()) return
        runCatching { installAddon(prefs.defaultAddonManifestUrl()) }
    }

    suspend fun installAddon(manifestUrlRaw: String): StremioAddon = withContext(Dispatchers.IO) {
        val manifestUrl = normalizeManifestUrl(manifestUrlRaw)
        val body = get(manifestUrl)
        val root = json.parseToJsonElement(body).jsonObject
        val name = root["name"]?.jsonPrimitive?.contentOrNull
            ?: root["id"]?.jsonPrimitive?.contentOrNull
            ?: "Addon"
        val version = root["version"]?.jsonPrimitive?.contentOrNull
        val logo = root["logo"]?.jsonPrimitive?.contentOrNull
        val baseUrl = manifestUrl.removeSuffix("/manifest.json").trimEnd('/')
        val addon = StremioAddon(baseUrl = baseUrl, name = name, version = version, logo = logo)
        val next = prefs.getAddons().filterNot { it.baseUrl == baseUrl } + addon
        prefs.saveAddons(next)
        addon
    }

    suspend fun removeAddon(baseUrl: String) {
        prefs.saveAddons(prefs.getAddons().filterNot { it.baseUrl == baseUrl })
    }

    /**
     * Movie: [imdbId] like `tt123`.
     * Series: [imdbId]:[season]:[episode] like `tt123:1:5`.
     */
    suspend fun getStreams(
        type: String,
        stremioId: String,
    ): List<StremioStream> = coroutineScope {
        installDefaultIfNeeded()
        val addons = prefs.getAddons()
        if (addons.isEmpty()) return@coroutineScope emptyList()
        addons.map { addon ->
            async(Dispatchers.IO) {
                runCatching { fetchStreams(addon, type, stremioId) }.getOrDefault(emptyList())
            }
        }.awaitAll().flatten()
    }

    private fun fetchStreams(
        addon: StremioAddon,
        type: String,
        stremioId: String,
    ): List<StremioStream> {
        val url = "${addon.baseUrl}/stream/$type/$stremioId.json"
        val body = get(url)
        val root = json.parseToJsonElement(body).jsonObject
        val streams = root["streams"]?.jsonArray.orEmpty()
        return streams.mapNotNull { el ->
            val o = el as? JsonObject ?: return@mapNotNull null
            val hints = o["behaviorHints"]?.jsonObject
            val proxy = hints?.get("proxyHeaders")?.jsonObject
            val request = (proxy?.get("request") ?: proxy?.get("requests"))?.jsonObject
                ?.mapNotNull { (k, v) -> v.jsonPrimitive.contentOrNull?.let { k to it } }
                ?.toMap()
            StremioStream(
                name = o["name"]?.jsonPrimitive?.contentOrNull,
                title = o["title"]?.jsonPrimitive?.contentOrNull,
                description = o["description"]?.jsonPrimitive?.contentOrNull,
                url = o["url"]?.jsonPrimitive?.contentOrNull,
                infoHash = o["infoHash"]?.jsonPrimitive?.contentOrNull,
                behaviorHints = if (request != null) {
                    com.playtorrio.tv.data.model.BehaviorHints(
                        proxyHeaders = com.playtorrio.tv.data.model.ProxyHeaders(request = request),
                    )
                } else {
                    null
                },
                addonName = addon.name,
                addonBaseUrl = addon.baseUrl,
            )
        }.filter { !it.url.isNullOrBlank() || !it.infoHash.isNullOrBlank() }
    }

    private fun normalizeManifestUrl(raw: String): String {
        var u = raw.trim()
        if (u.startsWith("stremio://")) u = "https://" + u.removePrefix("stremio://")
        if (!u.endsWith("/manifest.json")) {
            u = u.trimEnd('/') + "/manifest.json"
        }
        return u
    }

    private fun get(url: String): String {
        val req = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .get()
            .build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("Stremio ${resp.code} for $url")
            return resp.body?.string().orEmpty()
        }
    }
}
