package com.playtorrio.tv.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val PtBg = Color(0xFF0E0C14)
val PtSurface = Color(0xFF1A1625)
val PtAccent = Color(0xFFE85D4C)
val PtText = Color(0xFFF5F2FA)
val PtMuted = Color(0xFF9B93A8)

private val DarkColors = darkColorScheme(
    primary = PtAccent,
    onPrimary = Color.White,
    background = PtBg,
    onBackground = PtText,
    surface = PtSurface,
    onSurface = PtText,
    secondary = PtMuted,
    onSecondary = PtText,
)

@Composable
fun PlayTorrioTheme(
    isTelevision: Boolean = false,
    content: @Composable () -> Unit,
) {
    // Shared Material3 theme for phone + TV (D-pad focus handled in components).
    MaterialTheme(
        colorScheme = DarkColors,
        content = content,
    )
}
