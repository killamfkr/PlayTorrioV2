package com.playtorrio.tv.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.playtorrio.tv.BuildConfig
import com.playtorrio.tv.data.AppContainer
import com.playtorrio.tv.data.model.StremioAddon
import com.playtorrio.tv.ui.components.ErrorText
import com.playtorrio.tv.ui.components.TvSideNav
import com.playtorrio.tv.ui.theme.PtAccent
import com.playtorrio.tv.ui.theme.PtMuted
import com.playtorrio.tv.ui.theme.PtText
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(
    container: AppContainer,
    isTelevision: Boolean,
    onOpenTab: (String) -> Unit = {},
) {
    val scope = rememberCoroutineScope()
    var addons by remember { mutableStateOf<List<StremioAddon>>(emptyList()) }
    var url by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var message by remember { mutableStateOf<String?>(null) }

    fun refresh() {
        scope.launch {
            container.stremio.installDefaultIfNeeded()
            addons = container.stremio.listAddons()
        }
    }

    LaunchedEffect(Unit) { refresh() }

    val body: @Composable () -> Unit = {
        LazyColumn(Modifier.fillMaxSize().padding(20.dp)) {
            item {
                Text("Stremio addons", color = PtText, fontSize = 22.sp)
                Text(
                    "Streams are fetched from installed addon manifests (same protocol as Flutter PlayTorrio).",
                    color = PtMuted,
                    modifier = Modifier.padding(top = 6.dp, bottom = 12.dp),
                )
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("manifest.json URL") },
                    placeholder = { Text(BuildConfig.DEFAULT_STREMIO_ADDON) },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = PtAccent,
                        unfocusedBorderColor = PtMuted,
                        focusedTextColor = PtText,
                        unfocusedTextColor = PtText,
                        cursorColor = PtAccent,
                        focusedLabelColor = PtAccent,
                        unfocusedLabelColor = PtMuted,
                    ),
                )
                Button(
                    onClick = {
                        scope.launch {
                            error = null
                            message = null
                            runCatching {
                                container.stremio.installAddon(
                                    url.ifBlank { BuildConfig.DEFAULT_STREMIO_ADDON },
                                )
                            }.onSuccess {
                                message = "Installed ${it.name}"
                                url = ""
                                refresh()
                            }.onFailure { error = it.message }
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = PtAccent),
                    modifier = Modifier.padding(vertical = 12.dp),
                ) { Text("Add addon") }
                error?.let { ErrorText(it) }
                message?.let { Text(it, color = PtAccent, modifier = Modifier.padding(bottom = 8.dp)) }
            }
            items(addons, key = { it.baseUrl }) { addon ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(addon.name, color = PtText)
                        Text(addon.baseUrl, color = PtMuted, fontSize = 12.sp)
                    }
                    TextButton(onClick = {
                        scope.launch {
                            container.stremio.removeAddon(addon.baseUrl)
                            refresh()
                        }
                    }) { Text("Remove", color = PtAccent) }
                }
            }
            item {
                Text(
                    "PlayTorrio native ${BuildConfig.VERSION_NAME}",
                    color = PtMuted,
                    modifier = Modifier.padding(top = 24.dp),
                )
            }
        }
    }

    if (isTelevision) {
        Row(Modifier.fillMaxSize()) {
            TvSideNav(selected = "settings") { id ->
                when (id) {
                    "home" -> onOpenTab("home")
                    "search" -> onOpenTab("search")
                    "iptv" -> onOpenTab("iptv")
                    "settings" -> Unit
                }
            }
            body()
        }
    } else {
        body()
    }
}
