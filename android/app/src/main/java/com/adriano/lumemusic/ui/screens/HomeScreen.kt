package com.adriano.lumemusic.ui.screens

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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.ChartCountry
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.MoodCategory
import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.CatalogExplorerService
import com.adriano.lumemusic.ui.AlbumTile
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtistBubble
import com.adriano.lumemusic.ui.GlassIconButton
import com.adriano.lumemusic.ui.GradientCard
import com.adriano.lumemusic.ui.HRow
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.LumeWordmark
import com.adriano.lumemusic.ui.PrismButton
import com.adriano.lumemusic.ui.SectionHeader
import com.adriano.lumemusic.ui.Skeleton
import com.adriano.lumemusic.ui.TallTrackCard
import com.adriano.lumemusic.ui.TrackRow
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.launch
import java.util.Calendar

fun greeting(): String {
    val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
    return when { h < 5 -> "Boa madrugada"; h < 12 -> "Bom dia"; h < 18 -> "Boa tarde"; else -> "Boa noite" }
}

@Composable
fun HomeScreen(bottomInset: Dp) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    val feed = AppModel.feed
    val store = LibraryStore
    PullToRefreshBox(refreshing, onRefresh = { scope.launch { refreshing = true; AppModel.loadFeed(force = true); AppModel.refreshArtistReleases(); refreshing = false } }, modifier = Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = bottomInset + 16.dp), verticalArrangement = Arrangement.spacedBy(26.dp)) {
            item {
                Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 20.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        LumeWordmark(24f)
                        Text(greeting(), style = Theme.font(14f, color = Theme.secondary), modifier = Modifier.padding(top = 2.dp))
                    }
                    GlassIconButton("bell", badge = AppModel.hasUnseenReleases, desc = "Lançamentos") { AppModel.push(LumeRoute.Releases) }
                    Spacer(Modifier.size(8.dp))
                    GlassIconButton("gearshape", desc = "Ajustes") { AppModel.push(LumeRoute.Settings) }
                }
            }
            item { FlowCard() }
            item { QuickShelf() }

            if (store.recentTracks.isNotEmpty()) item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader("Tocadas recentemente", actionLabel = "Ver tudo", onAction = { AppModel.push(LumeRoute.Tracks("Tocadas recentemente", store.recentTracks)) })
                    val list = store.recentTracks.take(15)
                    HRow { items(list, key = { it.id }) { TallTrackCard(it, queue = list) } }
                }
            }

            val mixes = CatalogExplorerService.buildPersonalizedMixes(store.mostPlayedTracks, store.favoriteTracks, store.recentTracks, store.topListenedArtists, feed)
            if (mixes.isNotEmpty()) item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader("Feito para você", "Mixes atualizados com o seu gosto")
                    HRow { items(mixes, key = { it.id }) { m ->
                        GradientCard(m.title, m.subtitle, m.icon, m.hexA, m.hexB, Modifier.size(width = 170.dp, height = 150.dp)) { AppModel.push(LumeRoute.Mix(m)) }
                    } }
                }
            }

            if (feed == null) item { Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { repeat(3) { Skeleton(Modifier.fillMaxWidth().height(64.dp)) } } }

            feed?.let { f ->
                if (f.topBrazil.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Em alta no Brasil", "Top 50 Brasil", onAction = { AppModel.push(LumeRoute.Tracks("Top 50 Brasil", f.topBrazil)) })
                        val list = f.topBrazil.take(20)
                        HRow { rankedCards(list, f.topBrazil) }
                    }
                }
                val releases = (AppModel.artistReleases.ifEmpty { f.newReleases }).take(20)
                if (releases.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Lançamentos da semana", if (AppModel.artistReleases.isNotEmpty()) "Lançamentos recentes de quem você acompanha" else "Lançamentos no mundo",
                            onAction = { AppModel.push(LumeRoute.Releases) })
                        HRow { items(releases, key = { it.id }) { a -> AlbumTile(a, subtitle = a.artist) { AppModel.push(LumeRoute.Album(a)) } } }
                    }
                }
                if (f.topArtists.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Cantores mais ouvidos", "Brasil", onAction = { AppModel.push(LumeRoute.Artists("Cantores mais ouvidos", f.topArtists)) })
                        HRow { items(f.topArtists.take(20), key = { it.id }) { a -> ArtistBubble(a) { AppModel.openArtist(a.name, a.deezerId) } } }
                    }
                }
                if (f.topGlobal.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Top 50 Mundo", "As mais tocadas no planeta agora", onAction = { AppModel.push(LumeRoute.Tracks("Top 50 Mundo", f.topGlobal)) })
                        HRow { rankedCards(f.topGlobal.take(20), f.topGlobal) }
                    }
                }
                if (f.trending.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        SectionHeader("Em alta", "Subindo rápido nas paradas")
                        Spacer(Modifier.height(8.dp))
                        f.trending.take(8).forEach { TrackRow(it, queue = f.trending) }
                    }
                }
            }

            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader("Paradas pelo Mundo", "Toque em um país para abrir o Top 50")
                    HRow { items(ChartCountry.all, key = { it.code }) { c ->
                        GradientCard(c.name, c.region, null, c.hexA, c.hexB, Modifier.size(width = 150.dp, height = 96.dp), emoji = c.flag) { AppModel.push(LumeRoute.Country(c)) }
                    } }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader("Estilos do Brasil", "Paradas e playlists separadas por estilo")
                    HRow { items(MusicGenre.all.filter { it.group == MusicGenre.Group.BRASIL }, key = { it.id }) { g ->
                        GradientCard(g.title, null, g.icon, g.hexA, g.hexB, Modifier.size(width = 150.dp, height = 96.dp)) { AppModel.push(LumeRoute.Genre(g)) }
                    } }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader("Gêneros Internacionais")
                    HRow { items(MusicGenre.all.filter { it.group == MusicGenre.Group.INTERNACIONAL }, key = { it.id }) { g ->
                        GradientCard(g.title, null, g.icon, g.hexA, g.hexB, Modifier.size(width = 150.dp, height = 96.dp)) { AppModel.push(LumeRoute.Genre(g)) }
                    } }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader("Gêneros & Estilos")
                    HRow { items(MoodCategory.presets, key = { it.id }) { m ->
                        GradientCard(m.title, null, m.icon, m.hexA, m.hexB, Modifier.size(width = 150.dp, height = 96.dp)) { AppModel.push(LumeRoute.Mood(m)) }
                    } }
                }
            }
            item { Text(Theme.credit, style = Theme.font(12f, color = Theme.tertiary), modifier = Modifier.fillMaxWidth().padding(top = 8.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.rankedCards(list: List<Track>, queue: List<Track>) {
    itemsIndexed(list, key = { i, t -> "$i${t.id}" }) { i, t -> TallTrackCard(t, rank = i + 1, queue = queue) }
}

@Composable
private fun FlowCard() {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp).clip(RoundedCornerShape(26.dp)).glass(RoundedCornerShape(26.dp), elevation = 6.dp).padding(18.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Lume Flow", style = Theme.font(20f, FontWeight.Bold, Theme.text))
            Text("Rádio infinita com o seu gosto", style = Theme.font(13.5f, color = Theme.secondary))
        }
        PrismButton("Tocar", "play.fill", modifier = Modifier.size(width = 112.dp, height = 48.dp), height = 48.dp) { AppModel.startFlow() }
    }
}

@Composable
private fun QuickShelf() {
    val store = LibraryStore
    val cards = listOf(
        Triple("Curtidas", "heart.fill", store.favoriteTracks),
        Triple("Baixadas", "arrow.down.circle.fill", store.downloadedTracks),
        Triple("Histórico", "clock.fill", store.recentTracks),
    )
    HRow(spacing = 12.dp) {
        items(cards, key = { it.first }) { (title, icon, tracks) ->
            Row(
                Modifier.size(width = 168.dp, height = 56.dp).pressable(0.96f) { AppModel.push(LumeRoute.Tracks(title, tracks)) }.glass(RoundedCornerShape(18.dp)).padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(sf(icon), null, tint = Theme.rose, modifier = Modifier.size(20.dp))
                Column {
                    Text(title, style = Theme.font(15f, FontWeight.SemiBold, Theme.text))
                    Text("${tracks.size} músicas", style = Theme.font(12f, color = Theme.secondary))
                }
            }
        }
        item {
            Row(
                Modifier.size(width = 168.dp, height = 56.dp).pressable(0.96f) { AppModel.push(LumeRoute.Replay) }.glass(RoundedCornerShape(18.dp)).padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(sf("sparkles"), null, tint = Theme.lavender, modifier = Modifier.size(20.dp))
                Text("Lume Replay", style = Theme.font(15f, FontWeight.SemiBold, Theme.text))
            }
        }
    }
}

