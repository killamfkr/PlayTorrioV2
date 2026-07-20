package com.playtorrio.tv.data.prefs

import android.content.Context
import com.playtorrio.tv.BuildConfig
import com.playtorrio.tv.data.model.IptvCredentials
import com.playtorrio.tv.data.model.StremioAddon
import com.playtorrio.tv.data.model.VerifiedPortal
import com.playtorrio.tv.data.model.WatchEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class PrefsRepository(context: Context) {
    private val prefs = context.getSharedPreferences("playtorrio_native", Context.MODE_PRIVATE)
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    suspend fun getAddons(): List<StremioAddon> = withContext(Dispatchers.IO) {
        val raw = prefs.getString(KEY_ADDONS, null) ?: return@withContext emptyList()
        runCatching { json.decodeFromString<List<StremioAddon>>(raw) }.getOrDefault(emptyList())
    }

    suspend fun saveAddons(addons: List<StremioAddon>) = withContext(Dispatchers.IO) {
        prefs.edit().putString(KEY_ADDONS, json.encodeToString(addons)).apply()
    }

    fun defaultAddonManifestUrl(): String = BuildConfig.DEFAULT_STREMIO_ADDON

    suspend fun getIptvCredentials(): IptvCredentials? = withContext(Dispatchers.IO) {
        val raw = prefs.getString(KEY_IPTV, null) ?: return@withContext null
        runCatching { json.decodeFromString<IptvCredentials>(raw) }.getOrNull()
    }

    suspend fun saveIptvCredentials(creds: IptvCredentials) = withContext(Dispatchers.IO) {
        prefs.edit().putString(KEY_IPTV, json.encodeToString(creds)).apply()
    }

    suspend fun clearIptvCredentials() = withContext(Dispatchers.IO) {
        prefs.edit().remove(KEY_IPTV).apply()
    }

    suspend fun getIptvFavoriteIds(): Set<String> = withContext(Dispatchers.IO) {
        prefs.getStringSet(KEY_IPTV_FAVS, emptySet())?.toSet().orEmpty()
    }

    suspend fun saveIptvFavoriteIds(ids: Set<String>) = withContext(Dispatchers.IO) {
        prefs.edit().putStringSet(KEY_IPTV_FAVS, ids).apply()
    }

    suspend fun getVerifiedPortals(): List<VerifiedPortal> = withContext(Dispatchers.IO) {
        val raw = prefs.getString(KEY_VERIFIED, null) ?: return@withContext emptyList()
        runCatching { json.decodeFromString<List<VerifiedPortal>>(raw) }.getOrDefault(emptyList())
    }

    suspend fun saveVerifiedPortals(list: List<VerifiedPortal>) = withContext(Dispatchers.IO) {
        prefs.edit().putString(KEY_VERIFIED, json.encodeToString(list)).apply()
    }

    suspend fun clearVerifiedPortals() = withContext(Dispatchers.IO) {
        prefs.edit().remove(KEY_VERIFIED).apply()
    }

    /** Per-portal starred live stream IDs for TV Guide. */
    suspend fun getGuideFavoriteIds(portalKey: String): Set<String> = withContext(Dispatchers.IO) {
        prefs.getStringSet(KEY_GUIDE_FAV + portalKey.lowercase(), emptySet())?.toSet().orEmpty()
    }

    suspend fun saveGuideFavoriteIds(portalKey: String, ids: Set<String>) =
        withContext(Dispatchers.IO) {
            prefs.edit().putStringSet(KEY_GUIDE_FAV + portalKey.lowercase(), ids).apply()
        }

    suspend fun getWatchHistory(): List<WatchEntry> = withContext(Dispatchers.IO) {
        val raw = prefs.getString(KEY_HISTORY, null) ?: return@withContext emptyList()
        runCatching { json.decodeFromString<List<WatchEntry>>(raw) }.getOrDefault(emptyList())
    }

    suspend fun saveWatchHistory(entries: List<WatchEntry>) = withContext(Dispatchers.IO) {
        prefs.edit().putString(KEY_HISTORY, json.encodeToString(entries.take(50))).apply()
    }

    companion object {
        private const val KEY_ADDONS = "stremio_addons"
        private const val KEY_IPTV = "iptv_credential"
        private const val KEY_IPTV_FAVS = "iptv_favorites"
        private const val KEY_VERIFIED = "pt_iptv_verified_portals"
        private const val KEY_GUIDE_FAV = "pt_iptv_browser_fav_"
        private const val KEY_HISTORY = "watch_history"
    }
}
