package com.adriano.lumemusic.ui.screens

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.AppTab
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.PersonalizedMix
import com.adriano.lumemusic.engine.CatalogExplorerService
import com.adriano.lumemusic.engine.DiscText
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.GlassIconButton
import com.adriano.lumemusic.ui.HRow
import com.adriano.lumemusic.ui.HomeStore
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.LumeWordmark
import com.adriano.lumemusic.ui.OnboardingGenres
import com.adriano.lumemusic.ui.SectionHeader
import com.adriano.lumemusic.ui.Skeleton
import com.adriano.lumemusic.ui.TallTrackCard
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

/**
 * Início — poucas coisas por vez, bem espaçadas: saudação, busca, continuar ouvindo, uma vitrine, atalhos,
 * "Para você", Top 10 com seletor de países e lançamentos. Tudo aparece na hora a partir do cache (igual ao iOS).
 */
@Composable
fun HomeScreen(bottomInset: Dp) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { HomeStore.start() }
    PullToRefreshBox(
        refreshing,
        onRefresh = { scope.launch { refreshing = true; HomeStore.refresh(); AppModel.refreshArtistReleases(); refreshing = false } },
        modifier = Modifier.fillMaxSize(),
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 6.dp, bottom = bottomInset + 8.dp), verticalArrangement = Arrangement.spacedBy(32.dp)) {
            item { Header() }
            item { SearchPill() }
            item { ContinueSection() }
            item { Showcase() }
            item { Shortcuts() }
            item { ForYou() }
            item { TopTen() }
            item { Releases() }
            item { Text(Theme.credit, style = Theme.font(11.5f, color = Theme.tertiary), modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) }
        }
    }
}

// ---------------- Cabeçalho ----------------

@Composable
private fun Header() {
    Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            LumeWordmark(24f)
            if (LibraryStore.offlineMode) {
                Row(Modifier.height(24.dp).clip(RoundedCornerShape(50)).background(Theme.fillStrong).padding(horizontal = 9.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(sf("airplane"), null, tint = Theme.accent, modifier = Modifier.size(12.dp))
                    Text("Offline", style = Theme.font(11f, FontWeight.SemiBold, Theme.accent))
                }
            }
            Spacer(Modifier.weight(1f))
            GlassIconButton("sparkles", size = 44.dp, desc = "Lume Replay") { AppModel.push(LumeRoute.Replay) }
            GlassIconButton("bell", size = 44.dp, badge = AppModel.hasUnseenReleases, desc = "Novidades dos seus artistas") { AppModel.push(LumeRoute.Releases) }
            GlassIconButton("gearshape", size = 44.dp, desc = "Ajustes") { AppModel.push(LumeRoute.Settings) }
        }
        Text(greeting(), style = Theme.font(34f, FontWeight.Bold, Theme.text))
    }
}

@Composable
private fun SearchPill() {
    val shape = RoundedCornerShape(50)
    Row(
        Modifier.padding(horizontal = 20.dp).fillMaxWidth().height(50.dp).glass(shape).padding(start = 18.dp, end = 7.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.weight(1f).fillMaxSize().pressable(0.99f) { AppModel.select(AppTab.SEARCH) }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(sf("magnifyingglass"), null, tint = Theme.secondary, modifier = Modifier.size(20.dp))
            Text("Músicas, artistas, álbuns e trechos", style = Theme.font(15.5f, color = Theme.secondary), maxLines = 1)
        }
        Row(
            Modifier.height(36.dp).pressable(0.94f) { Haptics.light(); AppModel.openLyricsSearch() }.clip(shape).background(Theme.fillStrong).padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(sf("quote.bubble.fill"), null, tint = Theme.accent, modifier = Modifier.size(14.dp))
            Text("Letra", style = Theme.font(12f, FontWeight.SemiBold, Theme.accent))
        }
    }
}

// ---------------- Continuar ouvindo ----------------

@Composable
private fun ContinueSection() {
    val recent = LibraryStore.recentTracks.take(10)
    if (recent.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader("Continuar ouvindo", actionLabel = "Histórico", onAction = { AppModel.push(LumeRoute.Tracks("Histórico", LibraryStore.recentTracks)) })
        HRow(spacing = 12.dp) { items(recent, key = { it.id }) { TallTrackCard(it, queue = recent, width = 128.dp) } }
    }
}

// ---------------- Vitrine principal ----------------

@Composable
private fun Showcase() {
    val place = HomeStore.homePlace
    val feed = AppModel.feed
    val chartAlbums = (HomeStore.homeList?.albums ?: emptyList()).take(6)
    val fallback = ((feed?.newReleases?.takeIf { it.isNotEmpty() } ?: feed?.brazilReleases) ?: emptyList()).take(6)
    val albums = chartAlbums.ifEmpty { fallback }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(
            if (chartAlbums.isEmpty()) "Em destaque" else "Álbuns em alta · ${place.name}",
            if (chartAlbums.isEmpty()) "Lançamentos que estão chamando atenção" else "Os mais ouvidos ${if (place.isGlobal) "no mundo" else "no país"} agora",
            if (albums.isEmpty()) null else "Ver tudo",
            onAction = if (albums.isEmpty()) null else {
                { AppModel.push(LumeRoute.Albums("Álbuns em alta · ${place.name}", if (chartAlbums.isEmpty()) fallback else (HomeStore.homeList?.albums ?: emptyList()))) }
            },
        )
        if (albums.isEmpty()) Skeleton(Modifier.padding(horizontal = 20.dp).fillMaxWidth().height(332.dp), RoundedCornerShape(30.dp))
        else androidx.compose.runtime.key(if (chartAlbums.isEmpty()) "fallback" else "chart_${place.id}") {
            ReleaseHeroCarousel(albums, if (chartAlbums.isEmpty()) null else { idx, _ -> "#${idx + 1} · ${place.name.uppercase()}" })
        }
    }
}

// ---------------- Atalhos (onde fica cada coisa) ----------------

private fun releaseItems(): List<AlbumShowcase> {
    val feed = AppModel.feed ?: return AppModel.artistReleases
    val regional = if (HomeStore.homePlace.id == "br") feed.brazilReleases + feed.newReleases else feed.newReleases + feed.brazilReleases
    val seen = HashSet<String>()
    val out = mutableListOf<AlbumShowcase>()
    for (a in AppModel.artistReleases + regional) {
        val key = DiscText.normalize(a.title) + "|" + DiscText.normalize(a.artist)
        if (seen.add(key)) out.add(a)
    }
    return out
}

@Composable
private fun Shortcuts() {
    val items: List<Triple<String, String, () -> Unit>> = listOf(
        Triple("Paradas", "chart.bar.fill") { AppModel.push(LumeRoute.Country(HomeStore.place.chartCountry)) },
        Triple("Gêneros", "square.grid.2x2.fill") { AppModel.push(LumeRoute.GenresHub) },
        Triple("Lançamentos", "sparkles.rectangle.stack.fill") {
            val list = releaseItems()
            if (list.isEmpty()) AppModel.push(LumeRoute.Releases) else AppModel.push(LumeRoute.Albums("Lançamentos", list))
        },
        Triple("Cover Flow", "square.stack.3d.down.right.fill") { Haptics.medium(); AppModel.showCoverFlow = true },
        Triple("Minhas playlists", "music.note.list") { AppModel.select(AppTab.LIBRARY) },
        Triple("Lume Flow", "infinity") { Haptics.medium(); AppModel.startFlow() },
    )
    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { (title, icon, click) ->
                    Column(
                        Modifier.weight(1f).height(80.dp).pressable(0.96f) { Haptics.light(); click() }.glass(RoundedCornerShape(22.dp)),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(sf(icon), null, tint = Theme.rose, modifier = Modifier.size(24.dp))
                        Text(title, style = Theme.font(12.5f, FontWeight.SemiBold, Theme.text), modifier = Modifier.padding(top = 8.dp), maxLines = 1)
                    }
                }
            }
        }
    }
}

// ---------------- Para você ----------------

@Composable
private fun ForYou() {
    val store = LibraryStore
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val mixes: List<PersonalizedMix> = run {
        val fromHistory = CatalogExplorerService.buildPersonalizedMixes(
            store.mostPlayedTracks, store.favoriteTracks, store.recentTracks, store.topListenedArtists, null,
        ).filter { it.id in setOf("mix_norepeat", "mix_daily1", "mix_daily2", "mix_favorites") }
        (HomeStore.genreMixes + fromHistory).take(6)
    }
    if (mixes.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader("Para você", if (OnboardingGenres.selected(ctx).isEmpty()) "Com base no que você ouve" else "Seus gêneros e o que você ouve")
        HRow(spacing = 14.dp) { items(mixes, key = { it.id }) { m -> PersonalizedMixCard(m) } }
    }
}

// ---------------- Top 10 com seletor de país ----------------

@Composable
private fun TopTen() {
    val place = HomeStore.place
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SectionHeader(
            place.title,
            HomeStore.current?.caption ?: if (place.isGlobal) "Parada mundial · Deezer" else "Carregando a parada…",
            "Top 50", onAction = { AppModel.push(LumeRoute.Country(place.chartCountry)) },
        )
        PlaceChipsBar(place.id) { p -> HomeStore.select(p) }
        androidx.compose.runtime.key(place.id) {
            ChartTrackList(HomeStore.current, HomeStore.isLoadingCurrent || !HomeStore.settled, 10) {
                scope.launch { HomeStore.revalidate(place, force = true) }
            }
        }
    }
}

// ---------------- Lançamentos ----------------

@Composable
private fun Releases() {
    val items = releaseItems()
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(
            "Lançamentos",
            if (AppModel.artistReleases.isEmpty()) "Álbuns e singles recentes" else "Novidades dos seus artistas e do que está em alta",
            if (items.isEmpty()) null else "Ver tudo",
            onAction = if (items.isEmpty()) null else { { AppModel.push(LumeRoute.Albums("Lançamentos", items)) } },
        )
        if (items.isEmpty()) {
            Row(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                repeat(3) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Skeleton(Modifier.size(150.dp), RoundedCornerShape(12.dp))
                        Skeleton(Modifier.size(width = 110.dp, height = 13.dp), RoundedCornerShape(6.dp))
                    }
                }
            }
        } else HRow { items(items.take(16), key = { it.id }) { a -> DatedAlbumTile(a, 150.dp) } }
    }
}
