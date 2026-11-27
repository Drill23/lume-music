package com.adriano.lumemusic.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.ChartCountry
import com.adriano.lumemusic.data.MoodCategory
import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.CatalogExplorerService
import com.adriano.lumemusic.engine.CountryChartBundle
import com.adriano.lumemusic.engine.GenreHubBundle
import com.adriano.lumemusic.engine.MusicEngine
import com.adriano.lumemusic.ui.AlbumTile
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtistBubble
import com.adriano.lumemusic.ui.DetailTopBar
import com.adriano.lumemusic.ui.GradientCard
import com.adriano.lumemusic.ui.HRow
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.PrismChip
import com.adriano.lumemusic.ui.SectionHeader
import com.adriano.lumemusic.ui.Skeleton
import com.adriano.lumemusic.ui.TallTrackCard
import com.adriano.lumemusic.ui.TrackRow
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme

/** Botões Tocar / Aleatório de listas de faixas. */
@Composable
fun PlayShuffleRow(tracks: List<Track>, context: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        com.adriano.lumemusic.ui.PrismButton("Tocar", "play.fill", modifier = Modifier.weight(1f)) {
            if (tracks.isNotEmpty()) { AudioPlayer.shuffleEnabled = false; AudioPlayer.play(tracks.first(), tracks, context) }
        }
        com.adriano.lumemusic.ui.GlassButton("Aleatório", "shuffle", modifier = Modifier.weight(1f)) {
            if (tracks.isNotEmpty()) { AudioPlayer.shuffleEnabled = true; val t = tracks.random(); AudioPlayer.play(t, tracks, context) }
        }
    }
}

@Composable
fun ExploreScreen(bottomInset: Dp) {
    var country by remember { mutableStateOf(ChartCountry.all.first()) }
    val chart by produceState<CountryChartBundle?>(null, country) { value = null; value = CatalogExplorerService.countryChart(country) }
    val feed = AppModel.feed
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = bottomInset + 16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item { Text("Explorar", style = Theme.font(32f, FontWeight.Bold, Theme.text), modifier = Modifier.statusBarsPadding().padding(horizontal = 20.dp, vertical = 8.dp)) }

        item {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionHeader("Paradas por País", "Veja o Top 50 ao vivo em qualquer região")
                HRow(spacing = 8.dp) { items(ChartCountry.all, key = { it.code }) { c -> PrismChip("${c.flag} ${c.name}", c.code == country.code) { country = c } } }
            }
        }
        item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader("Top 50 · ${country.name}", null, "Ver Top 50", onAction = { AppModel.push(LumeRoute.Country(country)) })
                val c = chart
                if (c == null) Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { repeat(4) { Skeleton(Modifier.fillMaxWidth().height(56.dp)) } }
                else c.topSongs.take(6).forEachIndexed { i, t -> TrackRow(t, rank = i + 1, queue = c.topSongs) }
            }
        }
        if (AppModel.artistReleases.isNotEmpty()) item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader("Dos seus artistas", "Lançamentos de quem você ouve", onAction = { AppModel.push(LumeRoute.Releases) })
                HRow { items(AppModel.artistReleases.take(15), key = { it.id }) { a -> AlbumTile(a, subtitle = a.artist) { AppModel.push(LumeRoute.Album(a)) } } }
            }
        }
        feed?.let { f ->
            if (f.topGlobal.isNotEmpty()) item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader("Mais tocadas", "Parada global", onAction = { AppModel.push(LumeRoute.Tracks("Parada global", f.topGlobal)) })
                    HRow { rankedRow(f.topGlobal.take(15), f.topGlobal) }
                }
            }
            val gta = f.globalTopArtists
            if (!gta.isNullOrEmpty()) item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader("Cantores mais ouvidos", "Mundo", onAction = { AppModel.push(LumeRoute.Artists("Cantores mais ouvidos · Mundo", gta)) })
                    HRow { items(gta, key = { it.id }) { a -> ArtistBubble(a) { AppModel.openArtist(a.name, a.deezerId) } } }
                }
            }
            val alb = f.topAlbumsGlobal
            if (!alb.isNullOrEmpty()) item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader("Álbuns em alta", null, onAction = { AppModel.push(LumeRoute.Albums("Álbuns em alta", alb)) })
                    HRow { items(alb.take(15), key = { it.id }) { a -> AlbumTile(a, subtitle = a.artist) { AppModel.push(LumeRoute.Album(a)) } } }
                }
            }
        }
        item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader("Gêneros, Climas & Décadas")
                var group by remember { mutableStateOf("Gêneros BR") }
                HRow(spacing = 8.dp) { items(listOf("Gêneros BR", "Internacional", "Climas", "Décadas")) { g -> PrismChip(g, group == g) { group = g } } }
                val cards: List<Triple<String, Pair<Long, Long>, () -> Unit>> = when (group) {
                    "Gêneros BR" -> MusicGenre.all.filter { it.group == MusicGenre.Group.BRASIL }.map { g -> Triple(g.title, g.hexA to g.hexB) { AppModel.push(LumeRoute.Genre(g)) } }
                    "Internacional" -> MusicGenre.all.filter { it.group == MusicGenre.Group.INTERNACIONAL }.map { g -> Triple(g.title, g.hexA to g.hexB) { AppModel.push(LumeRoute.Genre(g)) } }
                    "Climas" -> (MoodCategory.presets + MoodCategory.activities).map { m -> Triple(m.title, m.hexA to m.hexB) { AppModel.push(LumeRoute.Mood(m)) } }
                    else -> MoodCategory.decades.map { m -> Triple(m.title, m.hexA to m.hexB) { AppModel.push(LumeRoute.Mood(m)) } }
                }
                Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    cards.chunked(2).forEach { pair ->
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            pair.forEach { (title, cols, click) -> GradientCard(title, null, null, cols.first, cols.second, Modifier.weight(1f).height(84.dp), onClick = click) }
                            if (pair.size == 1) Column(Modifier.weight(1f)) {}
                        }
                    }
                }
            }
        }
    }
}

private fun LazyListScope.rankedRow(list: List<Track>, queue: List<Track>) {
    itemsIndexed(list, key = { i, t -> "$i${t.id}" }) { i, t -> TallTrackCard(t, rank = i + 1, queue = queue) }
}

@Composable
fun CountryChartScreen(country: ChartCountry, bottomInset: Dp) {
    val chart by produceState<CountryChartBundle?>(null, country) { value = CatalogExplorerService.countryChart(country) }
    Column(Modifier.fillMaxSize()) {
        DetailTopBar("${country.flag} Top 50 · ${country.name}")
        val c = chart
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = bottomInset + 16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            if (c == null) item { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { repeat(8) { Skeleton(Modifier.fillMaxWidth().height(56.dp)) } } }
            else {
                item { PlayShuffleRow(c.topSongs, "Top 50 · ${country.name}") }
                item { Column { c.topSongs.forEachIndexed { i, t -> TrackRow(t, rank = i + 1, queue = c.topSongs) } } }
                if (c.topAlbums.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Álbuns mais ouvidos")
                        HRow { items(c.topAlbums, key = { it.id }) { a -> AlbumTile(a, subtitle = a.artist) { AppModel.push(LumeRoute.Album(a)) } } }
                    }
                }
                if (c.topArtists.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Artistas em alta")
                        HRow { items(c.topArtists, key = { it.id }) { a -> ArtistBubble(a) { AppModel.openArtist(a.name, a.deezerId) } } }
                    }
                }
                if (c.trending.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SectionHeader("Em alta no YouTube Music", "Vídeos e músicas em ascensão")
                        c.trending.take(20).forEach { TrackRow(it, queue = c.trending) }
                    }
                }
            }
        }
    }
}

@Composable
fun GenreHubScreen(genre: MusicGenre, bottomInset: Dp) {
    val hub by produceState<GenreHubBundle?>(null, genre) { value = CatalogExplorerService.genreHub(genre) }
    Column(Modifier.fillMaxSize()) {
        DetailTopBar(genre.title)
        val h = hub
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = bottomInset + 16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            item {
                GradientCard(genre.title, genre.subtitle, genre.icon, genre.hexA, genre.hexB, Modifier.padding(horizontal = 20.dp).fillMaxWidth().height(120.dp)) {}
            }
            if (h == null) item { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { repeat(8) { Skeleton(Modifier.fillMaxWidth().height(56.dp)) } } }
            else {
                item { PlayShuffleRow(h.topSongs, genre.title) }
                item { Column { h.topSongs.forEachIndexed { i, t -> TrackRow(t, rank = i + 1, queue = h.topSongs) } } }
                if (h.topAlbums.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Álbuns em alta")
                        HRow { items(h.topAlbums, key = { it.id }) { a -> AlbumTile(a, subtitle = a.artist) { AppModel.push(LumeRoute.Album(a)) } } }
                    }
                }
                if (h.topArtists.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Artistas")
                        HRow { items(h.topArtists, key = { it.id }) { a -> ArtistBubble(a) { AppModel.openArtist(a.name, a.deezerId) } } }
                    }
                }
                if (h.playlists.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Playlists")
                        HRow { items(h.playlists, key = { it.id }) { p ->
                            Column(Modifier.size(width = 150.dp, height = 210.dp).pressable(0.96f) { AppModel.push(LumeRoute.RemotePlaylistRoute(p)) }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                com.adriano.lumemusic.ui.ArtworkImage(p.artworkURL, Modifier.size(150.dp), 16.dp, icon = "music.note.list")
                                Text(p.title, style = Theme.font(14.5f, FontWeight.SemiBold, Theme.text), maxLines = 1)
                                Text(p.subtitle, style = Theme.font(12.5f, color = Theme.secondary), maxLines = 1)
                            }
                        } }
                    }
                }
            }
        }
    }
}

@Composable
fun MoodScreen(mood: MoodCategory, bottomInset: Dp) {
    val tracks by produceState<List<Track>?>(null, mood) { value = MusicEngine.searchSongs(mood.query, 30) }
    Column(Modifier.fillMaxSize()) {
        DetailTopBar(mood.title)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = bottomInset + 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item { GradientCard(mood.title, null, mood.icon, mood.hexA, mood.hexB, Modifier.padding(horizontal = 20.dp).fillMaxWidth().height(110.dp)) {} }
            val t = tracks
            if (t == null) item { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { repeat(8) { Skeleton(Modifier.fillMaxWidth().height(56.dp)) } } }
            else {
                item { PlayShuffleRow(t, mood.title) }
                items(t, key = { it.id }) { TrackRow(it, queue = t) }
            }
        }
    }
}

