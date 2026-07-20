package com.playtorrio.tv.data.iptv

import com.playtorrio.tv.data.model.IptvPortal
import com.playtorrio.tv.data.model.ScrapePage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.concurrent.TimeUnit

enum class CatalogSource { BEST, WORKS }

/**
 * Port of Flutter [IptvScraper] — Reddit OAuth catalog + GitHub XML2 dumps.
 */
class IptvScraper(private val http: OkHttpClient) {
    private val json = Json { ignoreUnknownKeys = true }

    @Volatile private var oauthToken: String? = null
    @Volatile private var oauthExpiryMs: Long = 0
    @Volatile private var oauthClientIdx: Int = 0
    @Volatile private var xml2Files: List<String>? = null

    suspend fun scrapePage(
        source: CatalogSource,
        after: String? = null,
    ): ScrapePage = withContext(Dispatchers.IO) {
        when (source) {
            CatalogSource.WORKS -> scrapeXml2(after)
            CatalogSource.BEST -> scrapeReddit(after)
        }
    }

    private fun scrapeXml2(after: String?): ScrapePage {
        val files = xml2Files ?: loadXml2Files().also { xml2Files = it }
        val idx = when {
            after.isNullOrBlank() -> 0
            after.startsWith("xml2:") -> after.removePrefix("xml2:").toIntOrNull() ?: 0
            else -> 0
        }
        if (idx >= files.size) return ScrapePage(portals = emptyList(), nextAfter = null)
        val encoded = files[idx]
        val pretty = java.net.URLDecoder.decode(encoded, "UTF-8")
        val body = httpGet("$XML2_BASE$encoded", UA_BROWSER) ?: ""
        val portals = extractPortals(body, "XML2/$pretty")
        val next = if (idx + 1 < files.size) "xml2:${idx + 1}" else null
        return ScrapePage(portals = portals, nextAfter = next)
    }

    private fun loadXml2Files(): List<String> {
        val api = httpGet(XML2_LIST_API, UA_BROWSER)
        if (api != null) {
            runCatching {
                val arr = json.parseToJsonElement(api).jsonArray
                val names = arr.mapNotNull { el ->
                    val o = el.jsonObject
                    val name = o["name"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                    if (!name.endsWith(".txt", ignoreCase = true)) return@mapNotNull null
                    val size = o["size"]?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: Long.MAX_VALUE
                    size to java.net.URLEncoder.encode(name, "UTF-8").replace("+", "%20")
                }.sortedBy { it.first }.map { it.second }
                if (names.isNotEmpty()) return names
            }
        }
        return XML2_FALLBACK
    }

    private fun scrapeReddit(after: String?): ScrapePage {
        var subIdx = 0
        var redditAfter: String? = null
        if (!after.isNullOrBlank() && after.startsWith("reddit:")) {
            val parts = after.removePrefix("reddit:").split(":", limit = 2)
            subIdx = parts.getOrNull(0)?.toIntOrNull() ?: 0
            redditAfter = parts.getOrNull(1)?.takeIf { it.isNotBlank() }
        }
        if (subIdx >= CATALOG_SUBS.size) {
            return ScrapePage(portals = emptyList(), nextAfter = null)
        }
        val sub = CATALOG_SUBS[subIdx]
        val oauthJson = fetchCatalogOAuth(sub, redditAfter)
        val acc = linkedMapOf<String, IptvPortal>()
        if (oauthJson != null) {
            runCatching {
                val data = json.parseToJsonElement(oauthJson).jsonObject["data"]?.jsonObject
                val children = data?.get("children")?.jsonArray.orEmpty()
                val nextToken = data?.get("after")?.jsonPrimitive?.contentOrNull
                children.forEachIndexed { i, el ->
                    val post = el.jsonObject["data"]?.jsonObject ?: return@forEachIndexed
                    val body = buildString {
                        append(post["title"]?.jsonPrimitive?.contentOrNull.orEmpty())
                        append('\n')
                        append(post["selftext"]?.jsonPrimitive?.contentOrNull.orEmpty())
                        append('\n')
                        append(post["url"]?.jsonPrimitive?.contentOrNull.orEmpty())
                    }
                    processPostBody(body, "Catalog", acc, deep = true)
                }
                val nextAfter = when {
                    !nextToken.isNullOrBlank() -> "reddit:$subIdx:$nextToken"
                    subIdx + 1 < CATALOG_SUBS.size -> "reddit:${subIdx + 1}:"
                    else -> null
                }
                return ScrapePage(portals = acc.values.toList(), nextAfter = nextAfter)
            }
        }
        // RSS fallback
        val rss = httpGet(
            buildString {
                append("https://www.reddit.com/r/$sub/new/.rss?limit=25")
                if (!redditAfter.isNullOrBlank()) append("&after=$redditAfter")
            },
            OAUTH_UA,
        )
        if (rss != null) {
            processPostBody(rss, "Catalog/RSS", acc, deep = false)
        }
        val nextAfter = if (subIdx + 1 < CATALOG_SUBS.size) "reddit:${subIdx + 1}:" else null
        return ScrapePage(portals = acc.values.toList(), nextAfter = nextAfter)
    }

    private fun processPostBody(
        body: String,
        source: String,
        acc: MutableMap<String, IptvPortal>,
        deep: Boolean,
    ) {
        extractPortals(body, source).forEach { acc.putIfAbsent(it.key, it) }
        // base64 http blobs
        B64.findAll(body).take(6).forEach { m ->
            val decoded = runCatching {
                String(Base64.getDecoder().decode(m.value), StandardCharsets.UTF_8)
            }.getOrNull() ?: return@forEach
            extractPortals(decoded, "$source (b64)").forEach { acc.putIfAbsent(it.key, it) }
        }
        if (deep) {
            RAW_PASTE.findAll(body).take(4).forEach { m ->
                val text = fetchPaste(m.value) ?: return@forEach
                extractPortals(text, "$source (paste)").forEach { acc.putIfAbsent(it.key, it) }
            }
        }
    }

    private fun fetchPaste(url: String): String? {
        // Skip paste.sh AES fragments for now
        if (url.contains("paste.sh/") && url.contains("#")) return null
        val fetchUrl = when {
            url.contains("pastebin.com/") && !url.contains("/raw/") ->
                "https://pastebin.com/raw/${url.substringAfterLast('/')}"
            url.contains("pastes.dev/") ->
                "https://api.pastes.dev/${url.substringAfterLast('/')}"
            url.contains("rentry.co/") && !url.contains("/raw") ->
                "https://rentry.co/${url.substringAfterLast('/')}/raw"
            else -> url
        }
        return httpGet(fetchUrl, UA_BROWSER)
    }

    private fun fetchCatalogOAuth(sub: String, after: String?): String? {
        val token = getOAuthToken() ?: return null
        val base = "https://oauth.reddit.com/r/$sub/new?limit=100&sort=new&raw_json=1"
        val url = if (after.isNullOrBlank()) base else "$base&after=$after"
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", OAUTH_UA)
            .header("Authorization", "Bearer $token")
            .get()
            .build()
        return runCatching {
            http.newCall(req).execute().use { resp ->
                if (resp.code == 401 || resp.code == 403) {
                    oauthToken = null
                    oauthExpiryMs = 0
                }
                if (!resp.isSuccessful) return@use null
                resp.body?.string()
            }
        }.getOrNull()
    }

    private fun getOAuthToken(): String? {
        val now = System.currentTimeMillis()
        val cached = oauthToken
        if (cached != null && now < oauthExpiryMs) return cached
        for (i in OAUTH_CLIENT_IDS.indices) {
            val idx = (oauthClientIdx + i) % OAUTH_CLIENT_IDS.size
            val clientId = OAUTH_CLIENT_IDS[idx]
            val basic = Base64.getEncoder()
                .encodeToString("$clientId:".toByteArray(StandardCharsets.UTF_8))
            val body = FormBody.Builder()
                .add("grant_type", "https://oauth.reddit.com/grants/installed_client")
                .add("device_id", "DO_NOT_TRACK_THIS_DEVICE")
                .build()
            val req = Request.Builder()
                .url("https://www.reddit.com/api/v1/access_token")
                .header("User-Agent", OAUTH_UA)
                .header("Authorization", "Basic $basic")
                .post(body)
                .build()
            val token = runCatching {
                http.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) return@use null
                    val root = json.parseToJsonElement(resp.body?.string().orEmpty()).jsonObject
                    val access = root["access_token"]?.jsonPrimitive?.contentOrNull
                    val expires = root["expires_in"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 3600
                    if (!access.isNullOrBlank()) {
                        oauthToken = access
                        oauthExpiryMs = now + (expires - 60) * 1000L
                        oauthClientIdx = idx
                        access
                    } else null
                }
            }.getOrNull()
            if (token != null) return token
        }
        oauthClientIdx = (oauthClientIdx + 1) % OAUTH_CLIENT_IDS.size
        oauthToken = null
        oauthExpiryMs = 0
        return null
    }

    fun extractPortals(rawText: String, source: String): List<IptvPortal> {
        if (rawText.length < 15 || isJunkCode(rawText)) return emptyList()
        val cleaned = rawText
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace(Regex("""<(?:p|br|div|li|h\d)[^>]*>""", RegexOption.IGNORE_CASE), "\n")
            .replace(Regex("<[^>]+>"), "")
        val acc = linkedMapOf<String, IptvPortal>()
        URL_PARAM.findAll(cleaned).forEach { m ->
            finalize(acc, m.groupValues[1], m.groupValues[2], m.groupValues[3], source)
        }
        LABEL.findAll(cleaned).forEach { m ->
            finalize(acc, m.groupValues[1], m.groupValues[2], m.groupValues[3], source)
        }
        return acc.values.toList()
    }

    private fun finalize(
        acc: MutableMap<String, IptvPortal>,
        rawUrl: String,
        rawUser: String,
        rawPass: String,
        source: String,
    ) {
        val url = cleanPortalUrl(rawUrl)
        val user = cleanCred(rawUser)
        val pass = cleanCred(rawPass)
        if (url.isEmpty() || user.length < 3 || pass.length < 3) return
        if (user.contains("http") || pass.contains("http")) return
        val lu = user.lowercase()
        val lp = pass.lowercase()
        if (JUNK_TOKENS.any { lu.contains(it) || lp.contains(it) }) return
        val p = IptvPortal(url, user, pass, source)
        acc.putIfAbsent(p.key, p)
    }

    private fun cleanPortalUrl(raw: String): String {
        var clean = raw.replace(Regex("\\s+"), "")
        val q = clean.indexOf('?')
        if (q >= 0) clean = clean.substring(0, q)
        clean = clean.trim()
        if (clean.contains('@')) {
            clean = "http://" + clean.substringAfterLast('@')
        }
        clean = clean.replace(
            Regex(
                """/(?:get|live|portal|c|index|playlist|player_api|xmltv|index\.php|portal\.php)\.php$""",
                RegexOption.IGNORE_CASE,
            ),
            "",
        )
        while (clean.endsWith('/')) clean = clean.dropLast(1)
        if (!clean.startsWith("http")) clean = "http://$clean"
        return clean
    }

    private fun cleanCred(raw: String): String {
        var s = raw
        while (s.startsWith('=')) s = s.drop(1)
        return s.split(Regex("""[ \n&?]""")).firstOrNull()?.trim().orEmpty()
    }

    private fun isJunkCode(text: String): Boolean {
        val markers = listOf(
            "Array.isArray", "prototype.", "function(", "var ", "const ",
            "let ", "return!", "void ", ".message}", "window.", "document.",
        )
        return markers.count { text.contains(it) } >= 2
    }

    private fun httpGet(url: String, ua: String): String? {
        val client = http.newBuilder()
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .build()
        val req = Request.Builder().url(url).header("User-Agent", ua).get().build()
        return runCatching {
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) null else resp.body?.string()
            }
        }.getOrNull()
    }

    companion object {
        private const val OAUTH_UA = "PlayTorrio/1.3.6 (by /u/PlayTorrioApp)"
        private const val UA_BROWSER =
            "Mozilla/5.0 (Linux; Android 11; PlayTorrio) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36"
        private val CATALOG_SUBS = listOf("IPTV_ZONENEW", "FreeIPTV", "iptvguru", "IPTVfree")
        private val OAUTH_CLIENT_IDS = listOf("ohXpoqrZYub1kg", "NOe2iKrPPzwscA", "JrPdG8Z6dkWNxA")
        private const val XML2_BASE =
            "https://raw.githubusercontent.com/akeotaseo/world_repo/main/Updater_Matrix/XML2/"
        private const val XML2_LIST_API =
            "https://api.github.com/repos/akeotaseo/world_repo/contents/Updater_Matrix/XML2?ref=main"
        private val XML2_FALLBACK = listOf(
            "25.txt", "71.txt", "ABN.txt", "DOV.txt",
            "%5BK_B_W_%20Client%5D.txt", "br.txt",
            "channels_fulltime%20(OR).txt", "channels_fulltime.txt",
            "kgen%20(4).txt", "kgen.txt", "rg.txt", "x.txt", "%7BAllTelegram%7D2.txt",
        )
        private val JUNK_TOKENS = listOf(
            "type=m3u", "output=ts", "password=", "username=", "password", "username",
        )
        private val URL_PARAM = Regex(
            """(https?://[^?\s"'<]+)\?(?:[^\s"'<]*?&)?(?:username|user)=([^&\s"'<]+)\s*&(?:password|pass)=([^&\s"'<]+)""",
            RegexOption.IGNORE_CASE,
        )
        private val LABEL = Regex(
            """(?:Portal|Host(?:\s*URL)?|H[ᴏo]s[ᴛt]|Panel|Real|URL|🔗|🌍|🌐)\W*?(https?://[^<\s"']+)[\s\S]{1,500}?(?:Username|Usu[áa]rio|Usuario|User|Us[ᴇe]r|Us[ᴜu][ᴀa]r[ɪi][ᴏo]|👤)\W*?([^\s|<"'\n]+)[\s\S]{1,200}?(?:Password|Senha|Contrase[ñn]a|Pass|P[ᴀa]ss|S[ᴇe]nh[ᴀa]|🔑)\W*?([^\s|<"'\n]+)""",
            RegexOption.IGNORE_CASE,
        )
        private val B64 = Regex("""aHR0c[a-zA-Z0-9+/=]{10,}""")
        private val RAW_PASTE = Regex(
            """https?://(?:paste\.sh|pastebin\.com|justpaste\.it|controlc\.com|pastes\.dev|text\.is|rentry\.co)/[a-zA-Z0-9#_=-]+""",
            RegexOption.IGNORE_CASE,
        )
    }
}
