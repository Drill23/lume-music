package com.adriano.lumemusic.ui.screens

import com.adriano.lumemusic.ui.Chrome
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.PersonalizedMix
import com.adriano.lumemusic.engine.ChartList
import com.adriano.lumemusic.engine.ChartPlace
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.AlbumTile
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.PrismChip
import com.adriano.lumemusic.ui.Skeleton
import com.adriano.lumemusic.ui.TrackRow
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.hex
import com.adriano.lumemusic.ui.theme.sf

/** Peças reutilizadas pela Home, Explorar e Paradas (porta de ChartsKit.swift / HomeView.swift). */

// ---------------- Seletor de país / Global (chips com bandeira) ----------------

@Composable
fun PlaceChipsBar(selected: String, places: List<ChartPlace> = ChartPlace.all, onSelect: (ChartPlace) -> Unit) {
    val state = rememberLazyListState()
    LaunchedEffect(selected) {
        val i = places.indexOfFirst { it.id == selected }
        if (i >= 0) state.animateScrollToItem(maxOf(0, i - 1))
    }
    LazyRow(state = state, contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(places, key = { it.id }) { p -> PrismChip("${p.flag} ${p.short}", p.id == selected) { onSelect(p) } }
    }
}

// ---------------- Lista Top N (carregando / vazio / pronta) ----------------

@Composable
fun ChartTrackList(list: ChartList?, loading: Boolean, limit: Int = 10, retry: () -> Unit) {
    if (list != null && list.songs.isNotEmpty()) {
        Column { list.songs.take(limit).forEachIndexed { i, t -> TrackRow(t, rank = i + 1, queue = list.songs) } }
    } else if (loading) {
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            repeat(minOf(limit, 10)) { Skeleton(Modifier.fillMaxWidth().height(50.dp)) }
        }
    } else {
        Column(Modifier.fillMaxWidth().padding(vertical = 28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(sf("wifi.exclamationmark"), null, tint = Theme.tertiary, modifier = Modifier.size(26.dp))
            Text("Parada indisponível agora", style = Theme.font(15f, FontWeight.SemiBold, Theme.text))
            Text("Tentar de novo", style = Theme.font(14f, FontWeight.SemiBold, Theme.text),
                modifier = Modifier.height(Chrome.minTouch).pressable(0.95f) { Haptics.light(); retry() }
                    .clip(RoundedCornerShape(50)).background(Theme.fillStrong).padding(horizontal = 18.dp, vertical = 12.dp))
        }
    }
}

// ---------------- Cartão de mix ----------------

@Composable
fun PersonalizedMixCard(mix: PersonalizedMix) {
    val shape = RoundedCornerShape(24.dp)
    Box(
        Modifier.size(width = 178.dp, height = 192.dp).pressable(0.97f) { Haptics.light(); AppModel.push(LumeRoute.Mix(mix)) }
            .clip(shape).background(Brush.linearGradient(listOf(hex(mix.hexA), hex(mix.hexB)))).border(0.8.dp, Color.White.copy(0.22f), shape),
    ) {
        mix.tracks.firstOrNull { it.artworkURL.isNotEmpty() }?.artworkURL?.let { art ->
            ArtworkImage(art, Modifier.fillMaxSize().alpha(0.32f), cornerRadius = 0.dp)
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(0.55f)))))
        Column(Modifier.fillMaxSize().padding(14.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(mix.tag, style = Theme.font(10.5f, FontWeight.Bold, Color.White, letterSpacing = androidx.compose.ui.unit.TextUnit(0.8f, androidx.compose.ui.unit.TextUnitType.Sp)),
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(0.2f)).padding(horizontal = 9.dp, vertical = 3.dp))
                Spacer(Modifier.weight(1f))
                Icon(sf(mix.icon), null, tint = Color.White.copy(0.9f), modifier = Modifier.size(16.dp))
            }
            Spacer(Modifier.weight(1f))
            Text(mix.title, style = Theme.rounded(20f, FontWeight.ExtraBold, Color.White), maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(mix.subtitle, style = Theme.font(12f, FontWeight.Medium, Color.White.copy(0.84f)), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

// ---------------- Vitrine principal (carrossel de álbuns) ----------------

@Composable
fun ReleaseHeroCarousel(albums: List<AlbumShowcase>, kicker: ((Int, AlbumShowcase) -> String)? = null) {
    val shown = albums.take(8)
    if (shown.isEmpty()) return
    val pager = rememberPagerState { shown.size }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HorizontalPager(pager, contentPadding = PaddingValues(horizontal = 20.dp), pageSpacing = 12.dp, modifier = Modifier.fillMaxWidth()) { idx ->
            val strip = buildList {
                var i = idx
                while (size < 4) { add(shown[i % shown.size]); i++; if (i - idx > shown.size) break }
            }
            ReleaseHeroCard(shown[idx], strip, kicker?.invoke(idx, shown[idx]))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
            for (i in shown.indices) {
                val on = i == pager.currentPage
                Box(Modifier.size(width = if (on) 18.dp else 6.dp, height = 6.dp).clip(CircleShape)
                    .background(if (on) Theme.rose else Theme.tertiary))
            }
        }
    }
}

@Composable
private fun ReleaseHeroCard(album: AlbumShowcase, strip: List<AlbumShowcase>, kickerOverride: String?) {
    val shape = RoundedCornerShape(30.dp)
    val kicker = kickerOverride ?: buildList {
        add((album.kind ?: "Lançamento").uppercase())
        Theme.shortDate(album.releaseDate).takeIf { it.isNotEmpty() }?.let { add(it.uppercase()) }
    }.joinToString(" · ")
    Box(
        Modifier.fillMaxWidth().height(332.dp).clip(shape).border(0.8.dp, Color.White.copy(0.22f), shape)
            .pressable(0.98f) { Haptics.medium(); AppModel.push(LumeRoute.Album(album)) },
    ) {
        // fundo: a capa ampliada e desfocada + véus
        ArtworkImage(album.artworkURL, Modifier.fillMaxSize().scale(1.5f).blur(34.dp), cornerRadius = 0.dp)
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(0.05f), Color.Black.copy(0.35f)))))
        Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Theme.lavender.copy(0.18f), Theme.rose.copy(0.12f)))))
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.padding(horizontal = 22.dp).padding(top = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(kicker, style = Theme.font(11.5f, FontWeight.SemiBold, Color.White, letterSpacing = androidx.compose.ui.unit.TextUnit(0.6f, androidx.compose.ui.unit.TextUnitType.Sp)),
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(0.2f)).padding(horizontal = 12.dp, vertical = 5.dp))
                Text(album.title, style = Theme.font(28f, FontWeight.Bold, Color.White), textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(album.artist, style = Theme.font(15f, FontWeight.Medium, Color.White.copy(0.82f)), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.weight(1f))
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp).padding(bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                strip.forEachIndexed { i, a ->
                    val s = RoundedCornerShape(16.dp)
                    ArtworkImage(a.artworkURL, Modifier.weight(1f).height(124.dp)
                        .border(if (i == 0) 1.6.dp else 0.7.dp, Color.White.copy(if (i == 0) 0.9f else 0.35f), s)
                        .pressable(0.96f) { Haptics.light(); AppModel.push(LumeRoute.Album(a)) }, 16.dp, icon = "square.stack.fill")
                }
            }
        }
    }
}

/** Álbum no carrossel horizontal: artista · data de lançamento quando houver. */
@Composable
fun DatedAlbumTile(a: AlbumShowcase, width: androidx.compose.ui.unit.Dp = 150.dp, showDate: Boolean = a.releaseDate != null) {
    val date = if (showDate) Theme.shortDate(a.releaseDate) else ""
    val sub = listOf(a.artist, date).filter { it.isNotEmpty() }.joinToString(" · ")
    AlbumTile(a, width, subtitle = sub) { AppModel.push(LumeRoute.Album(a)) }
}
