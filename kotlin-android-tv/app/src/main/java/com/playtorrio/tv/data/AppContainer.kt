package com.playtorrio.tv.data

import android.content.Context
import com.playtorrio.tv.data.iptv.IptvRepository
import com.playtorrio.tv.data.prefs.PrefsRepository
import com.playtorrio.tv.data.stremio.StremioRepository
import com.playtorrio.tv.data.tmdb.TmdbRepository
import com.playtorrio.tv.data.watch.WatchHistoryRepository
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

class AppContainer(context: Context) {
    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    val prefs = PrefsRepository(context)
    val tmdb = TmdbRepository(http)
    val stremio = StremioRepository(http, prefs)
    val iptv = IptvRepository(http, prefs)
    val watchHistory = WatchHistoryRepository(prefs)
}
