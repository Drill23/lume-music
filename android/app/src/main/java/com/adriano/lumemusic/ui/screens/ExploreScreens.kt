package com.adriano.lumemusic.ui.screens

import com.adriano.lumemusic.ui.Chrome
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.ArtworkStore
import com.adriano.lumemusic.data.ChartCountry
import com.adriano.lumemusic.data.DownloadManager
import com.adriano.lumemusic.data.MoodCategory
import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.CatalogExplorerService
import com.adriano.lumemusic.engine.ChartList
import com.adriano.lumemusic.engine.ChartPlace
import com.adriano.lumemusic.engine.ChartsService
import com.adriano.lumemusic.engine.CountryChartBundle
import com.adriano.lumemusic.engine.GenreHubBundle
import com.adriano.lumemusic.engine.MusicEngine
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtistBubble
import com.adriano.lumemusic.ui.DetailHeader
import com.adriano.lumemusic.ui.EmptyState
import com.adriano.lumemusic.ui.GlassIconButton
import com.adriano.lumemusic.ui.GradientCard
import com.adriano.lumemusic.ui.HRow
import com.adriano.lumemusic.ui.HomeStore
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.PrismChip
import com.adriano.lumemusic.ui.SectionHeader
import com.adriano.lumemusic.ui.Skeleton
import com.adriano.lumemusic.ui.TallTrackCard
import com.adriano.lumemusic.ui.TrackRow
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.hex
import kotlinx.coroutines.launch

/** Botões Tocar / Aleatório de listas de faixas. */
@Composable
fun PlayShuffleRow(tracks: List<Track>, context: String, modifier: Modifier = Modifier.fillMaxWidth(), horizontalPadding: Dp = 20.dp) {
    Row(modifier.padding(horizontal = horizontalPadding), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        com.adriano.lumemusic.ui.PrismButton("Tocar", "play.fill", modifier = Modifier.weight(1f)) {
            if (tracks.isNotEmpty()) { AudioPlayer.shuffleEnabled = false; AudioPlayer.play(tracks.first(), tracks, context) }
        }
        com.adriano.lumemusic.ui.GlassButton("Aleatório", "shuffle", modifier = Modifier.weight(1f)) {
            if (tracks.isNotEmpty()) { AudioPlayer.shuffleEnabled = true; val t = tracks.random(); AudioPlayer.play(t, tracks, context) }
        }
    }
}

@Composable
private fun ExploreSkeleton() {
    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { repeat(8) { Skeleton(Modifier.fillMaxWidth().height(56.dp)) } }
}

// ============================================================ Explorar

private enum class ArtistScope(val title: String) { BRAZIL("Brasil"), WORLD("Mundo") }
private val browseGroups = listOf("Gêneros BR", "Internacional", "Climas", "Décadas")

/**
 * Explorar — paradas por país e Global (seletor), cantores mais ouvidos (Brasil/Mundo),
 * gêneros reais, climas, décadas e lançamentos (igual ao ExploreView do iOS).
 */
@Composable
fun ExploreScreen(bottomInset: Dp) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    var place by remember { mutableStateOf(HomeStore.place) }
    var list by remember { mutableStateOf<ChartList?>(null) }
    var loadingChart by remember { mutableStateOf(false) }
    var artistScope by remember { mutableStateOf(ArtistScope.BRAZIL) }
    var group by remember { mutableStateOf(browseGroups[0]) }
    var reloadToken by remember { mutableStateOf(0) }
    val feed = AppModel.feed

    // Mostra o cache na hora e atualiza em seguida.
    LaunchedEffect(place.id, reloadToken) {
        list = ChartsService.cached(place)
        loadingChart = true
        val fresh = ChartsService.load(place, force = reloadToken > 0)
        if (fresh != null) list = fresh
        loadingChart = false
    }

    PullToRefreshBox(
        refreshing,
        onRefresh = { scope.launch { refreshing = true; HomeStore.refresh(); AppModel.refreshArtistReleases(); reloadToken++; refreshing = false } },
        modifier = Modifier.fillMaxSize(),
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 6.dp, bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(30.dp)) {
            // Cabeçalho
            item {
                Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Explorar", style = Theme.font(34f, FontWeight.Bold, Theme.text))
                    Text(list?.caption ?: "Paradas do mundo inteiro", style = Theme.font(14f, color = Theme.secondary))
                }
            }

            // Paradas (país / Global)
            item {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    SectionHeader("Paradas", "Top 10 de cada país e do mundo", "Top 50", onAction = { AppModel.push(LumeRoute.Country(place.chartCountry)) })
                    PlaceChipsBar(place.id) { place = it }
                    androidx.compose.runtime.key(place.id) {
                        ChartTrackList(list, loadingChart, 10) { reloadToken++ }
                    }
                    val albums = list?.albums ?: emptyList()
                    if (albums.isNotEmpty()) Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader(
                            if (place.isGlobal) "Álbuns em alta no mundo" else "Álbuns mais ouvidos · ${place.name}",
                            actionLabel = "Ver tudo", onAction = { AppModel.push(LumeRoute.Albums("Álbuns · ${place.name}", albums)) },
                        )
                        HRow { items(albums.take(16), key = { it.id }) { a -> DatedAlbumTile(a) } }
                    }
                }
            }

            if (feed == null) {
                item {
                    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        Skeleton(Modifier.size(width = 200.dp, height = 22.dp), RoundedCornerShape(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            Skeleton(Modifier.size(width = 206.dp, height = 276.dp), RoundedCornerShape(26.dp))
                            Skeleton(Modifier.size(width = 206.dp, height = 276.dp), RoundedCornerShape(26.dp))
                        }
                    }
                }
            } else {
                // Música brasileira de verdade (playlist "Top Brasil" do Deezer) — a parada da Apple traz muitos hits gringos.
                val hits = feed.brazilianHits ?: emptyList()
                if (hits.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Música brasileira", "Só o que é nacional e está tocando agora", "Tocar",
                            onAction = { AudioPlayer.play(hits.first(), hits, "Música brasileira") })
                        HRow(spacing = 14.dp) { itemsIndexed(hits.take(15), key = { i, t -> "$i${t.id}" }) { i, t -> TallTrackCard(t, rank = i + 1, queue = hits) } }
                    }
                }

                // Cantores mais ouvidos (Brasil | Mundo)
                item {
                    val world = feed.globalTopArtists ?: emptyList()
                    val artists: List<ArtistInfo> = if (artistScope == ArtistScope.WORLD && world.isNotEmpty()) world else feed.topArtists
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("Cantores mais ouvidos", style = Theme.font(21f, FontWeight.Bold, Theme.text))
                                Text(if (artistScope == ArtistScope.BRAZIL) "Os mais tocados na parada brasileira" else "Os mais tocados na parada mundial",
                                    style = Theme.font(13f, color = Theme.secondary))
                            }
                            Row(
                                Modifier.glass(RoundedCornerShape(50)).padding(3.dp),
                                horizontalArrangement = Arrangement.spacedBy(2.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                ArtistScope.entries.forEach { sc ->
                                    val on = artistScope == sc
                                    Box(
                                        Modifier.height(34.dp).clip(RoundedCornerShape(50))
                                            .then(if (on) Modifier.background(Theme.prismDiagonal) else Modifier)
                                            .pressable(0.94f) { com.adriano.lumemusic.platform.Haptics.selection(); artistScope = sc }
                                            .padding(horizontal = 13.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text(sc.title, style = Theme.font(12.5f, FontWeight.SemiBold, if (on) Theme.onPrism else Theme.secondary), maxLines = 1)
                                    }
                                }
                            }
                        }
                        HRow(spacing = 16.dp) { items(artists.take(20), key = { it.id }) { a -> ArtistBubble(a) { AppModel.openArtist(a.name, a.deezerId) } } }
                    }
                }

                // Em alta no YouTube Music Brasil
                if (feed.trending.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Em alta no YouTube Music", "Vídeos de música em alta no Brasil", "Ver tudo",
                            onAction = { AppModel.push(LumeRoute.Tracks("Em alta · YouTube Music Brasil", feed.trending)) })
                        HRow(spacing = 12.dp) { items(feed.trending.take(12), key = { it.id }) { t -> TallTrackCard(t, queue = feed.trending, width = 128.dp) } }
                    }
                }

                // Gêneros, Climas e Décadas
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        SectionHeader("Gêneros, Climas & Décadas")
                        HRow(spacing = 8.dp) { items(browseGroups) { g -> PrismChip(g, group == g) { group = g } } }
                        val cards: List<Triple<String, Pair<Long, Long>, () -> Unit>> = when (group) {
                            "Gêneros BR" -> MusicGenre.all.filter { it.group == MusicGenre.Group.BRASIL }.map { g -> Triple(g.title, g.hexA to g.hexB) { AppModel.push(LumeRoute.Genre(g)) } }
                            "Internacional" -> MusicGenre.all.filter { it.group == MusicGenre.Group.INTERNACIONAL }.map { g -> Triple(g.title, g.hexA to g.hexB) { AppModel.push(LumeRoute.Genre(g)) } }
                            "Climas" -> MoodCategory.activities.map { m -> Triple(m.title, m.hexA to m.hexB) { AppModel.push(LumeRoute.Mood(m)) } }
                            else -> MoodCategory.decades.map { m -> Triple(m.title, m.hexA to m.hexB) { AppModel.push(LumeRoute.Mood(m)) } }
                        }
                        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            cards.chunked(2).forEach { pair ->
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    pair.forEach { (title, cols, click) -> GradientCard(title, null, null, cols.first, cols.second, Modifier.weight(1f).height(100.dp), onClick = click) }
                                    if (pair.size == 1) Column(Modifier.weight(1f)) {}
                                }
                            }
                        }
                    }
                }

                // Lançamentos
                if (AppModel.artistReleases.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Dos seus artistas", "Lançamentos de quem você ouve", "Ver tudo", onAction = { AppModel.push(LumeRoute.Releases) })
                        HRow { items(AppModel.artistReleases.take(12), key = { it.id }) { a -> DatedAlbumTile(a, showDate = true) } }
                    }
                }
                val week = feed.newReleases.ifEmpty { feed.brazilReleases }
                if (week.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        SectionHeader("Lançamentos da semana", actionLabel = "Ver tudo", onAction = { AppModel.push(LumeRoute.Albums("Lançamentos da semana", week)) })
                        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                            week.take(6).chunked(2).forEach { pair ->
                                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                                    pair.forEach { a -> Box(Modifier.weight(1f)) { BoxWithAlbum(a) } }
                                    if (pair.size == 1) Column(Modifier.weight(1f)) {}
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BoxWithAlbum(a: com.adriano.lumemusic.data.AlbumShowcase) {
    androidx.compose.foundation.layout.BoxWithConstraints {
        DatedAlbumTile(a, maxWidth, showDate = true)
    }
}

// ============================================================ Parada de País

private enum class CountryScope(val title: String) { SONGS("Top 50"), ALBUMS("Álbuns"), ARTISTS("Artistas"), TRENDING("Em Alta") }

@Composable
fun CountryChartScreen(country: ChartCountry, bottomInset: Dp) {
    var selected by remember { mutableStateOf(country) }
    var bundle by remember { mutableStateOf<CountryChartBundle?>(null) }
    var loading by remember { mutableStateOf(true) }
    var caption by remember { mutableStateOf("") }
    var scope by remember { mutableStateOf(CountryScope.SONGS) }

    // Stale-while-revalidate: mostra o que já existe NA HORA, atualiza as músicas e só então completa artistas/em alta.
    LaunchedEffect(selected.code) {
        val c = selected
        val cached = CatalogExplorerService.cachedCountryChart(c)
        if (cached != null) { bundle = cached; loading = false } else { bundle = null; loading = true }
        val place = ChartPlace.place(c.code)
        if (place != null) ChartsService.cached(place)?.let { caption = it.caption }
        val fast = CatalogExplorerService.countryChartFast(c)
        if (fast != null && fast.topSongs.isNotEmpty()) { bundle = fast; loading = false }
        val full = CatalogExplorerService.countryChart(c)
        if (full.topSongs.isNotEmpty()) bundle = full
        if (place != null) ChartsService.cached(place)?.let { caption = it.caption }
        ArtworkStore.register(full.topArtists)
        loading = false
    }

    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            // Hero full-bleed até o topo (sem recorte branco sob o botão voltar)
            item {
                Box(Modifier.fillMaxWidth().height(270.dp).background(Brush.linearGradient(listOf(hex(selected.hexA), hex(selected.hexB))))) {
                    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(0.24f), Color.Black.copy(0.15f), Color.Black.copy(0.48f)))))
                    Text(selected.flag, style = Theme.font(130f), modifier = Modifier.align(Alignment.BottomEnd).padding(end = 6.dp).alpha(0.25f))
                    Column(Modifier.align(Alignment.BottomStart).padding(horizontal = 20.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(selected.region.uppercase(), style = Theme.font(11f, FontWeight.Bold, Color.White.copy(0.85f), letterSpacing = androidx.compose.ui.unit.TextUnit(1.1f, androidx.compose.ui.unit.TextUnitType.Sp)))
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(selected.flag, style = Theme.font(36f))
                            Text(if (selected.code == "world") "Top 50 Global" else "Top 50 ${selected.name}", style = Theme.font(30f, FontWeight.ExtraBold, Color.White), maxLines = 2)
                        }
                        Text(if (selected.code == "world") "As músicas mais ouvidas no mundo inteiro" else "As músicas, álbuns e cantores mais ouvidos no país",
                            style = Theme.font(13.5f, FontWeight.Medium, Color.White.copy(0.86f)))
                        if (caption.isNotEmpty()) Text(caption, style = Theme.font(11.5f, FontWeight.SemiBold, Color.White.copy(0.7f)))
                    }
                }
            }
            item { PlaceChipsBar(selected.code) { selected = it.chartCountry } }
            item { HRow(spacing = 8.dp) { items(CountryScope.entries.toList()) { s -> PrismChip(s.title, scope == s) { scope = s } } } }

            val b = bundle
            if (loading && b == null) item { ExploreSkeleton() }
            else if (b == null) item { EmptyState("wifi.exclamationmark", "Parada indisponível", "Não foi possível carregar os rankings deste país agora.") }
            else when (scope) {
                CountryScope.SONGS -> {
                    item {
                        Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Box(Modifier.weight(1f)) { PlayShuffleRow(b.topSongs, "Top 50 ${b.country.name}", horizontalPadding = 0.dp) }
                            GlassIconButton("arrow.down.circle", size = 48.dp, desc = "Baixar Top 10") {
                                DownloadManager.downloadBatch(b.topSongs.take(10))
                                AppModel.showToast("Baixando Top 10 de ${b.country.name}")
                            }
                        }
                    }
                    itemsIndexed(b.topSongs, key = { i, t -> "$i${t.id}" }) { i, t -> TrackRow(t, rank = i + 1, queue = b.topSongs) }
                }
                CountryScope.ALBUMS -> {
                    if (b.topAlbums.isEmpty()) item { EmptyState("square.stack", "Sem álbuns", "Nenhum álbum ranqueado disponível agora.") }
                    else items(b.topAlbums.chunked(2)) { pair ->
                        Row(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            pair.forEach { a -> Box(Modifier.weight(1f)) { BoxWithAlbum(a) } }
                            if (pair.size == 1) Column(Modifier.weight(1f)) {}
                        }
                    }
                }
                CountryScope.ARTISTS -> {
                    if (b.topArtists.isEmpty()) item { EmptyState("music.mic", "Sem artistas", "Nenhum artista ranqueado disponível agora.") }
                    else items(b.topArtists.chunked(3)) { trio ->
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            trio.forEach { a -> Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { ArtistBubble(a, size = 92.dp) { AppModel.openArtist(a.name, a.deezerId) } } }
                            repeat(3 - trio.size) { Box(Modifier.weight(1f)) {} }
                        }
                    }
                }
                CountryScope.TRENDING -> {
                    if (b.trending.isEmpty()) item { EmptyState("play.rectangle", "Sem vídeos em alta", "O YouTube Music não trouxe vídeos em alta para este lugar agora.") }
                    else {
                        item { PlayShuffleRow(b.trending, "Em alta · ${b.country.name}") }
                        itemsIndexed(b.trending, key = { i, t -> "$i${t.id}" }) { i, t -> TrackRow(t, rank = i + 1, queue = b.trending) }
                    }
                }
            }
        }
        DetailHeader("${selected.flag} ${if (selected.code == "world") "Top 50 Global" else "Top 50 · ${selected.name}"}", listState, 180.dp, overlay = true)
    }
}

// ============================================================ Hub de Gênero

@Composable
fun GenreHubScreen(genre: MusicGenre, bottomInset: Dp) {
    var hub by remember { mutableStateOf<GenreHubBundle?>(null) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(genre.id) {
        val cached = CatalogExplorerService.cachedGenreHub(genre)
        if (cached != null) { hub = cached; loading = false } else loading = true
        val fresh = CatalogExplorerService.genreHub(genre)
        if (fresh.topSongs.isNotEmpty()) hub = fresh
        hub?.topArtists?.let { ArtworkStore.register(it) }
        loading = false
    }
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    Box(Modifier.fillMaxSize()) {
        val h = hub
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(26.dp)) {
            item {
                Box(Modifier.fillMaxWidth().height(265.dp).background(Brush.linearGradient(listOf(hex(genre.hexA), hex(genre.hexB))))) {
                    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(0.24f), Color.Black.copy(0.16f), Color.Black.copy(0.45f)))))
                    Column(Modifier.align(Alignment.BottomStart).padding(horizontal = 20.dp, vertical = 20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(genre.group.raw.uppercase(), style = Theme.font(11f, FontWeight.Bold, Color.White.copy(0.84f), letterSpacing = androidx.compose.ui.unit.TextUnit(1.1f, androidx.compose.ui.unit.TextUnitType.Sp)))
                        Text(genre.title, style = Theme.font(34f, FontWeight.ExtraBold, Color.White), maxLines = 2)
                        Text(genre.subtitle, style = Theme.font(14f, FontWeight.Medium, Color.White.copy(0.85f)))
                    }
                }
            }
            if (h == null) {
                if (loading) item { ExploreSkeleton() }
            } else {
                if (h.topSongs.isNotEmpty()) item {
                    Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Box(Modifier.weight(1f)) { PlayShuffleRow(h.topSongs, genre.title, horizontalPadding = 0.dp) }
                        GlassIconButton("dot.radiowaves.left.and.right", size = 48.dp, desc = "Rádio do estilo") { h.topSongs.firstOrNull()?.let { AudioPlayer.startRadio(it) } }
                    }
                }
                if (h.topArtists.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Principais artistas", actionLabel = "Ver todos", onAction = { AppModel.push(LumeRoute.Artists("Artistas · ${genre.title}", h.topArtists)) })
                        HRow(spacing = 16.dp) { items(h.topArtists.take(16), key = { it.id }) { a -> ArtistBubble(a) { AppModel.openArtist(a.name, a.deezerId) } } }
                    }
                }
                if (h.topSongs.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SectionHeader("Mais tocadas em ${genre.title}", actionLabel = if (h.topSongs.size > 10) "Ver tudo" else null,
                            onAction = if (h.topSongs.size > 10) { { AppModel.push(LumeRoute.Tracks("Top ${genre.title}", h.topSongs)) } } else null)
                        h.topSongs.take(12).forEachIndexed { i, t -> TrackRow(t, rank = i + 1, queue = h.topSongs) }
                    }
                }
                if (h.topAlbums.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Álbuns em destaque", actionLabel = "Ver tudo", onAction = { AppModel.push(LumeRoute.Albums("Álbuns · ${genre.title}", h.topAlbums)) })
                        HRow { items(h.topAlbums.take(16), key = { it.id }) { a -> DatedAlbumTile(a, showDate = true) } }
                    }
                }
                if (h.playlists.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Playlists selecionadas")
                        HRow { items(h.playlists, key = { it.id }) { p ->
                            Column(Modifier.size(width = 152.dp, height = 210.dp).pressable(0.97f) { AppModel.push(LumeRoute.RemotePlaylistRoute(p)) }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                com.adriano.lumemusic.ui.ArtworkImage(p.artworkURL, Modifier.size(152.dp), 14.dp, icon = "music.note.list")
                                Text(p.title, style = Theme.font(14f, FontWeight.Medium, Theme.text), maxLines = 1)
                                Text(p.subtitle, style = Theme.font(12f, color = Theme.secondary), maxLines = 1)
                            }
                        } }
                    }
                }
            }
        }
        DetailHeader(genre.title, listState, 180.dp, overlay = true)
    }
}

// ============================================================ Gêneros (hub)

/** Estilos do Brasil, internacionais, climas e décadas (GenresHubView do iOS). */
@Composable
fun GenresHubScreen(bottomInset: Dp) {
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        DetailHeader("Gêneros", listState, 48.dp)
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(top = 6.dp, bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(28.dp)) {
            item {
                Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Gêneros", style = Theme.font(34f, FontWeight.Bold, Theme.text))
                    Text("Toque num estilo para ver as mais tocadas, artistas e álbuns", style = Theme.font(14f, color = Theme.secondary))
                }
            }
            fun group(title: String, cards: List<Triple<String, Pair<Long, Long>, () -> Unit>>, subtitles: List<String?>) {
                item(key = title) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader(title)
                        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            cards.withIndex().toList().chunked(2).forEach { pair ->
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    pair.forEach { (i, c) -> GradientCard(c.first, subtitles[i], null, c.second.first, c.second.second, Modifier.weight(1f).height(98.dp), onClick = c.third) }
                                    if (pair.size == 1) Column(Modifier.weight(1f)) {}
                                }
                            }
                        }
                    }
                }
            }
            val br = MusicGenre.all.filter { it.group == MusicGenre.Group.BRASIL }
            val intl = MusicGenre.all.filter { it.group == MusicGenre.Group.INTERNACIONAL }
            group("Estilos do Brasil", br.map { g -> Triple(g.title, g.hexA to g.hexB) { AppModel.push(LumeRoute.Genre(g)) } }, br.map { it.subtitle })
            group("Internacionais", intl.map { g -> Triple(g.title, g.hexA to g.hexB) { AppModel.push(LumeRoute.Genre(g)) } }, intl.map { it.subtitle })
            group("Climas e momentos", MoodCategory.activities.map { m -> Triple(m.title, m.hexA to m.hexB) { AppModel.push(LumeRoute.Mood(m)) } }, MoodCategory.activities.map { null })
            group("Décadas", MoodCategory.decades.map { m -> Triple(m.title, m.hexA to m.hexB) { AppModel.push(LumeRoute.Mood(m)) } }, MoodCategory.decades.map { null })
        }
    }
}

@Composable
fun MoodScreen(mood: MoodCategory, bottomInset: Dp) {
    val tracks by produceState<List<Track>?>(null, mood) { value = MusicEngine.searchSongs(mood.query, 30) }
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        DetailHeader(mood.title, listState, 90.dp)
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(16.dp)) {
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
