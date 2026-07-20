package com.playtorrio.tv.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.playtorrio.tv.data.model.MediaItem
import com.playtorrio.tv.ui.theme.PtAccent
import com.playtorrio.tv.ui.theme.PtMuted
import com.playtorrio.tv.ui.theme.PtSurface
import com.playtorrio.tv.ui.theme.PtText

@Composable
fun SectionTitle(text: String) {
    Text(
        text = text,
        color = PtText,
        fontSize = 20.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
    )
}

@Composable
fun MediaRow(
    title: String,
    items: List<MediaItem>,
    onOpen: (MediaItem) -> Unit,
) {
    if (items.isEmpty()) return
    Column {
        SectionTitle(title)
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(items, key = { "${it.mediaType}-${it.id}" }) { item ->
                PosterCard(item = item, onClick = { onOpen(item) })
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
fun PosterCard(
    item: MediaItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var focused by remember { mutableStateOf(false) }
    Column(
        modifier = modifier
            .width(120.dp)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable(onClick = onClick)
            .then(
                if (focused) Modifier.border(2.dp, PtAccent, RoundedCornerShape(10.dp))
                else Modifier,
            )
            .padding(2.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(8.dp))
                .background(PtSurface),
        ) {
            AsyncImage(
                model = item.posterUrl,
                contentDescription = item.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
            )
        }
        Text(
            text = item.title,
            color = PtText,
            fontSize = 12.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 6.dp),
        )
    }
}

@Composable
fun LoadingBox() {
    Box(
        Modifier
            .fillMaxWidth()
            .height(180.dp),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator(color = PtAccent)
    }
}

@Composable
fun ErrorText(message: String) {
    Text(
        text = message,
        color = Color(0xFFFF8A80),
        modifier = Modifier.padding(20.dp),
    )
}

@Composable
fun TvSideNav(
    selected: String,
    onSelect: (String) -> Unit,
) {
    val items = listOf(
        "home" to "Home",
        "search" to "Search",
        "iptv" to "IPTV",
        "settings" to "Settings",
    )
    Column(
        Modifier
            .width(180.dp)
            .background(PtSurface)
            .padding(vertical = 24.dp, horizontal = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            "PlayTorrio",
            color = PtAccent,
            fontWeight = FontWeight.Bold,
            fontSize = 18.sp,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 12.dp),
        )
        items.forEach { (id, label) ->
            var focused by remember { mutableStateOf(false) }
            val selectedBg = if (selected == id) PtAccent.copy(alpha = 0.25f) else Color.Transparent
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .background(selectedBg)
                    .onFocusChanged { focused = it.isFocused }
                    .focusable()
                    .border(
                        width = if (focused) 2.dp else 0.dp,
                        color = if (focused) PtAccent else Color.Transparent,
                        shape = RoundedCornerShape(8.dp),
                    )
                    .clickable { onSelect(id) }
                    .padding(horizontal = 12.dp, vertical = 14.dp),
            ) {
                Text(label, color = if (selected == id) PtText else PtMuted)
            }
        }
    }
}
