package com.playtorrio.tv.data.watch

import com.playtorrio.tv.data.model.WatchEntry
import com.playtorrio.tv.data.prefs.PrefsRepository

class WatchHistoryRepository(private val prefs: PrefsRepository) {
    suspend fun list(): List<WatchEntry> = prefs.getWatchHistory()

    suspend fun upsert(entry: WatchEntry) {
        val current = prefs.getWatchHistory().toMutableList()
        current.removeAll { it.uniqueId == entry.uniqueId }
        current.add(0, entry)
        prefs.saveWatchHistory(current)
    }

    suspend fun remove(uniqueId: String) {
        prefs.saveWatchHistory(prefs.getWatchHistory().filterNot { it.uniqueId == uniqueId })
    }
}
