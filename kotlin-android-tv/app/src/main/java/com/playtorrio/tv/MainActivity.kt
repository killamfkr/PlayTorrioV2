package com.playtorrio.tv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.playtorrio.tv.ui.PlayTorrioTvApp
import com.playtorrio.tv.ui.theme.PlayTorrioTvTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            PlayTorrioTvTheme {
                PlayTorrioTvApp()
            }
        }
    }
}
