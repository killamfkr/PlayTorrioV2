package com.playtorrio.tv.ui.theme

import androidx.compose.runtime.Composable
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.TvMaterialTheme

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun PlayTorrioTvTheme(content: @Composable () -> Unit) {
    TvMaterialTheme {
        content()
    }
}
