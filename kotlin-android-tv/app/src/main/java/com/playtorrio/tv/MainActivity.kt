package com.playtorrio.tv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.playtorrio.tv.ui.navigation.PlayTorrioNav
import com.playtorrio.tv.ui.theme.PlayTorrioTheme
import com.playtorrio.tv.ui.theme.PtBg
import com.playtorrio.tv.util.isTelevision

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as PlayTorrioApp
        setContent {
            val tv = remember { isTelevision() }
            PlayTorrioTheme(isTelevision = tv) {
                androidx.compose.foundation.layout.Box(
                    Modifier
                        .fillMaxSize()
                        .background(PtBg),
                ) {
                    PlayTorrioNav(container = app.container, isTelevision = tv)
                }
            }
        }
    }
}
