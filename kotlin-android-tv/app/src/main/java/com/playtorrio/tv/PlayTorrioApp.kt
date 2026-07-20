package com.playtorrio.tv

import android.app.Application
import com.playtorrio.tv.data.AppContainer

class PlayTorrioApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
