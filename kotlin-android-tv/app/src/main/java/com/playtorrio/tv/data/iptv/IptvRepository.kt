package com.playtorrio.tv.data.iptv

import com.playtorrio.tv.data.model.IptvCategory
import com.playtorrio.tv.data.model.IptvChannel
import com.playtorrio.tv.data.model.IptvCredentials
import com.playtorrio.tv.data.prefs.PrefsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

class IptvRepository(
    private val http: OkHttpClient,
    private val prefs: PrefsRepository,
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun savedCredentials(): IptvCredentials? = prefs.getIptvCredentials()

    suspend fun logout() = prefs.clearIptvCredentials()

    suspend fun login(serverUrl: String, username: String, password: String): IptvCredentials =
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
            val creds = IptvCredentials(base, username, password)
            prefs.saveIptvCredentials(creds)
            creds
        }

    suspend fun liveCategories(creds: IptvCredentials): List<IptvCategory> =
        withContext(Dispatchers.IO) {
            val url = api(creds, "get_live_categories")
            val arr = json.parseToJsonElement(get(url)).jsonArray
            arr.mapNotNull { el ->
                val o = el.jsonObject
                val id = o["category_id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                val name = o["category_name"]?.jsonPrimitive?.contentOrNull ?: id
                IptvCategory(id, name)
            }
        }

    suspend fun liveStreams(creds: IptvCredentials, categoryId: String? = null): List<IptvChannel> =
        withContext(Dispatchers.IO) {
            val url = api(creds, "get_live_streams")
            val arr = json.parseToJsonElement(get(url)).jsonArray
            arr.mapNotNull { el ->
                val o = el.jsonObject
                val cat = o["category_id"]?.jsonPrimitive?.contentOrNull
                if (categoryId != null && cat != categoryId) return@mapNotNull null
                val id = o["stream_id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                val name = o["name"]?.jsonPrimitive?.contentOrNull ?: "Channel $id"
                val icon = o["stream_icon"]?.jsonPrimitive?.contentOrNull
                IptvChannel(
                    streamId = id,
                    name = name,
                    streamIcon = icon,
                    categoryId = cat,
                    playUrl = "${creds.serverUrl}/live/${enc(creds.username)}/${enc(creds.password)}/$id.m3u8",
                )
            }
        }

    private fun api(creds: IptvCredentials, action: String): String =
        "${creds.serverUrl}/player_api.php".toHttpUrl().newBuilder()
            .addQueryParameter("username", creds.username)
            .addQueryParameter("password", creds.password)
            .addQueryParameter("action", action)
            .build()
            .toString()

    private fun enc(s: String) = URLEncoder.encode(s, StandardCharsets.UTF_8.name())

    private fun get(url: String): String {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", "VLC/3.0.20 LibVLC/3.0.20")
            .get()
            .build()
        http.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) error("IPTV ${resp.code}")
            return resp.body?.string().orEmpty()
        }
    }
}
