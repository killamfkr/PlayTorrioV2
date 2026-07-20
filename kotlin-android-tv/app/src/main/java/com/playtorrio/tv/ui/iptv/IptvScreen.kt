package com.playtorrio.tv.ui.iptv

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.playtorrio.tv.data.AppContainer
import com.playtorrio.tv.data.model.IptvCategory
import com.playtorrio.tv.data.model.IptvChannel
import com.playtorrio.tv.data.model.IptvCredentials
import com.playtorrio.tv.ui.components.ErrorText
import com.playtorrio.tv.ui.components.LoadingBox
import com.playtorrio.tv.ui.components.TvSideNav
import com.playtorrio.tv.ui.player.PlayerActivity
import com.playtorrio.tv.ui.theme.PtAccent
import com.playtorrio.tv.ui.theme.PtMuted
import com.playtorrio.tv.ui.theme.PtSurface
import com.playtorrio.tv.ui.theme.PtText
import kotlinx.coroutines.launch

@Composable
fun IptvScreen(
    container: AppContainer,
    isTelevision: Boolean,
    onOpenTab: (String) -> Unit = {},
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var creds by remember { mutableStateOf<IptvCredentials?>(null) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var server by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var categories by remember { mutableStateOf<List<IptvCategory>>(emptyList()) }
    var selectedCat by remember { mutableStateOf<String?>(null) }
    var channels by remember { mutableStateOf<List<IptvChannel>>(emptyList()) }

    LaunchedEffect(Unit) {
        loading = true
        creds = container.iptv.savedCredentials()
        creds?.let { c ->
            server = c.serverUrl
            user = c.username
            pass = c.password
            runCatching {
                categories = container.iptv.liveCategories(c)
                selectedCat = categories.firstOrNull()?.categoryId
                channels = container.iptv.liveStreams(c, selectedCat)
            }.onFailure { error = it.message }
        }
        loading = false
    }

    LaunchedEffect(selectedCat, creds) {
        val c = creds ?: return@LaunchedEffect
        val cat = selectedCat ?: return@LaunchedEffect
        runCatching { channels = container.iptv.liveStreams(c, cat) }
            .onFailure { error = it.message }
    }

    fun play(ch: IptvChannel) {
        context.startActivity(
            Intent(context, PlayerActivity::class.java).apply {
                putExtra(PlayerActivity.EXTRA_URL, ch.playUrl)
                putExtra(PlayerActivity.EXTRA_TITLE, ch.name)
                putStringArrayListExtra(
                    PlayerActivity.EXTRA_HEADER_KEYS,
                    arrayListOf("User-Agent"),
                )
                putStringArrayListExtra(
                    PlayerActivity.EXTRA_HEADER_VALUES,
                    arrayListOf("VLC/3.0.20 LibVLC/3.0.20"),
                )
            },
        )
    }

    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedBorderColor = PtAccent,
        unfocusedBorderColor = PtMuted,
        focusedLabelColor = PtAccent,
        unfocusedLabelColor = PtMuted,
        focusedTextColor = PtText,
        unfocusedTextColor = PtText,
        cursorColor = PtAccent,
    )

    val body: @Composable () -> Unit = {
        if (loading) {
            LoadingBox()
        } else if (creds == null) {
            Column(Modifier.fillMaxSize().padding(20.dp)) {
                Text("Xtream Codes login", color = PtText)
                OutlinedTextField(
                    value = server,
                    onValueChange = { server = it },
                    label = { Text("Server URL") },
                    modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                    colors = fieldColors,
                    singleLine = true,
                )
                OutlinedTextField(
                    value = user,
                    onValueChange = { user = it },
                    label = { Text("Username") },
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    colors = fieldColors,
                    singleLine = true,
                )
                OutlinedTextField(
                    value = pass,
                    onValueChange = { pass = it },
                    label = { Text("Password") },
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    colors = fieldColors,
                    singleLine = true,
                )
                error?.let { ErrorText(it) }
                Button(
                    onClick = {
                        scope.launch {
                            loading = true
                            error = null
                            runCatching { container.iptv.login(server, user, pass) }
                                .onSuccess {
                                    creds = it
                                    categories = container.iptv.liveCategories(it)
                                    selectedCat = categories.firstOrNull()?.categoryId
                                }
                                .onFailure { error = it.message }
                            loading = false
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = PtAccent),
                    modifier = Modifier.padding(top = 16.dp),
                ) { Text("Connect") }
            }
        } else {
            Row(Modifier.fillMaxSize()) {
                LazyColumn(
                    Modifier
                        .weight(0.35f)
                        .fillMaxSize()
                        .background(PtSurface)
                        .padding(8.dp),
                ) {
                    item {
                        TextButton(onClick = {
                            scope.launch {
                                container.iptv.logout()
                                creds = null
                                categories = emptyList()
                                channels = emptyList()
                            }
                        }) { Text("Log out", color = PtAccent) }
                    }
                    items(categories, key = { it.categoryId }) { cat ->
                        Text(
                            cat.categoryName,
                            color = if (cat.categoryId == selectedCat) PtAccent else PtText,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { selectedCat = cat.categoryId }
                                .padding(12.dp),
                        )
                    }
                }
                LazyColumn(Modifier.weight(0.65f).padding(8.dp)) {
                    items(channels, key = { it.streamId }) { ch ->
                        Text(
                            ch.name,
                            color = PtText,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                                .background(PtSurface, RoundedCornerShape(8.dp))
                                .clickable { play(ch) }
                                .padding(14.dp),
                        )
                    }
                }
            }
        }
    }

    if (isTelevision) {
        Row(Modifier.fillMaxSize()) {
            TvSideNav(selected = "iptv") { id ->
                when (id) {
                    "home" -> onOpenTab("home")
                    "search" -> onOpenTab("search")
                    "iptv" -> Unit
                    "settings" -> onOpenTab("settings")
                }
            }
            body()
        }
    } else {
        body()
    }
}
