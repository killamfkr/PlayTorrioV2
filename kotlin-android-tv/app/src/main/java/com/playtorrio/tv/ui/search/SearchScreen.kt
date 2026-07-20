package com.playtorrio.tv.ui.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.playtorrio.tv.data.AppContainer
import com.playtorrio.tv.data.model.MediaItem
import com.playtorrio.tv.ui.components.ErrorText
import com.playtorrio.tv.ui.components.LoadingBox
import com.playtorrio.tv.ui.components.PosterCard
import com.playtorrio.tv.ui.components.TvSideNav
import com.playtorrio.tv.ui.theme.PtAccent
import com.playtorrio.tv.ui.theme.PtMuted
import com.playtorrio.tv.ui.theme.PtText
import kotlinx.coroutines.delay

@Composable
fun SearchScreen(
    container: AppContainer,
    isTelevision: Boolean,
    onOpen: (mediaType: String, id: Int) -> Unit,
    onOpenTab: (String) -> Unit = {},
) {
    var query by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var results by remember { mutableStateOf<List<MediaItem>>(emptyList()) }

    LaunchedEffect(query) {
        if (query.isBlank()) {
            results = emptyList()
            return@LaunchedEffect
        }
        delay(350)
        loading = true
        error = null
        runCatching { container.tmdb.search(query) }
            .onSuccess { results = it }
            .onFailure { error = it.message }
        loading = false
    }

    val content = @Composable {
        Column(Modifier.fillMaxSize().padding(16.dp)) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text("Search movies & TV") },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = PtAccent,
                    unfocusedBorderColor = PtMuted,
                    focusedLabelColor = PtAccent,
                    unfocusedLabelColor = PtMuted,
                    focusedTextColor = PtText,
                    unfocusedTextColor = PtText,
                    cursorColor = PtAccent,
                ),
            )
            when {
                loading -> LoadingBox()
                error != null -> ErrorText(error!!)
                else -> LazyVerticalGrid(
                    columns = GridCells.Adaptive(120.dp),
                    contentPadding = PaddingValues(vertical = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(results, key = { "${it.mediaType}-${it.id}" }) { item ->
                        PosterCard(item = item, onClick = { onOpen(item.mediaType, item.id) })
                    }
                }
            }
        }
    }

    if (isTelevision) {
        Row(Modifier.fillMaxSize()) {
            TvSideNav(selected = "search") { id ->
                when (id) {
                    "home" -> onOpenTab("home")
                    "search" -> Unit
                    "iptv" -> onOpenTab("iptv")
                    "settings" -> onOpenTab("settings")
                }
            }
            content()
        }
    } else {
        content()
    }
}
