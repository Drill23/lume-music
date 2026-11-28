package com.adriano.lumemusic.ui.screens

import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.ui.PrismButton
import com.adriano.lumemusic.ui.PrismChip
import com.adriano.lumemusic.ui.theme.sf
import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.ArtistDetail
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.ArtworkStore
import com.adriano.lumemusic.data.DownloadManager
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.PersonalizedMix
import com.adriano.lumemusic.data.RemotePlaylist
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.CatalogExplorerService
import com.adriano.lumemusic.engine.DiscoveryService
import com.adriano.lumemusic.ui.AlbumTile
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtistBubble
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.DetailHeader
import com.adriano.lumemusic.ui.EmptyState
import com.adriano.lumemusic.ui.GlassButton
import com.adriano.lumemusic.ui.GlassIconButton
import com.adriano.lumemusic.ui.GradientCard
import com.adriano.lumemusic.ui.HRow
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.SectionHeader
import com.adriano.lumemusic.ui.Skeleton
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.TrackRow
import com.adriano.lumemusic.ui.theme.Theme

@Composable
fun AlbumScreen(album: AlbumShowcase, bottomInset: Dp) {
    val tracks by produceState(album.tracks, album.id) {
        if (album.tracks.isEmpty()) value = DiscoveryService.albumTracks(album).ifEmpty { com.adriano.lumemusic.engine.MusicEngine.fetchAlbumTracks(album.title, album.artist, album.artworkURL) }
    }
    val saved = LibraryStore.isAlbumSaved(album.id)
    val listState = rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        DetailHeader(album.title, listState, 240.dp) {
            GlassIconButton(if (saved) "heart.fill" else "heart", size = 42.dp, foreground = if (saved) Theme.rose else Theme.text, desc = "Salvar álbum") { LibraryStore.toggleSaveAlbum(album, tracks) }
        }
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                Column(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    val coverShape = RoundedCornerShape(26.dp)
                    ArtworkImage(album.artworkURL, Modifier.size(220.dp).shadow(20.dp, coverShape, ambientColor = Theme.shadow, spotColor = Theme.shadow).border(0.6.dp, Theme.hairline, coverShape), 26.dp, icon = "square.stack.fill")
                    Text(album.title, style = Theme.font(24f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 24.dp))
                    Text(album.artist, style = Theme.font(16f, FontWeight.SemiBold, Theme.accent), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.pressable(0.95f) { AppModel.openArtist(album.artist) })
                    Text(listOfNotNull(album.kind, album.year.ifEmpty { null }, album.genre.ifEmpty { null }).joinToString(" · "), style = Theme.font(13f, color = Theme.secondary))
                }
            }
            item {
                Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.weight(1f)) { PlayShuffleRow(tracks, album.title, horizontalPadding = 0.dp) }
                    GlassIconButton("arrow.down.circle", size = 48.dp, desc = "Baixar álbum") {
                        val pending = tracks.filter { !LibraryStore.isDownloaded(it.id) }
                        if (pending.isEmpty()) AppModel.showToast("Todas as músicas deste álbum já estão baixadas")
                        else { DownloadManager.downloadBatch(pending); AppModel.showToast("Baixando ${pending.size} músicas") }
                    }
                }
            }
            if (tracks.isEmpty()) item { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { repeat(6) { Skeleton(Modifier.fillMaxWidth().height(56.dp)) } } }
            items(tracks.size) { i -> TrackRow(tracks[i], rank = i + 1, queue = tracks) }
        }
    }
}

@Composable
fun ArtistScreen(name: String, deezerId: Long?, bottomInset: Dp) {
    val detail by produceState<ArtistDetail?>(null, name, deezerId) { value = DiscoveryService.artistDetail(name, deezerId) }
    val following = LibraryStore.isFollowing(name)
    var expandTop by remember(name) { mutableStateOf(false) }
    var discogFilter by remember(name) { mutableStateOf("Todos") }
    val listState = rememberLazyListState()
    Box(Modifier.fillMaxSize()) {
        val d = detail
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            // Cabeçalho de artista full-bleed até o topo (por trás da barra de status e botão voltar de vidro, idêntico ao iPhone)
            item {
                Box(Modifier.fillMaxWidth().height(360.dp)) {
                    val pic = d?.artist?.pictureURL ?: ""
                    if (pic.isNotEmpty()) ArtworkImage(pic, Modifier.fillMaxSize(), cornerRadius = 0.dp, icon = "person.fill")
                    else Box(Modifier.fillMaxSize().background(Theme.prismDiagonal), contentAlignment = Alignment.Center) {
                        Icon(sf("person.fill"), null, tint = Color.White.copy(0.8f), modifier = Modifier.size(84.dp))
                    }
                    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to Color.Black.copy(0.24f), 0.28f to Color.Transparent, 0.62f to Color.Transparent, 0.86f to Theme.canvas.copy(0.82f), 1f to Theme.canvas)))
                    Column(Modifier.align(Alignment.BottomStart).padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(d?.artist?.name ?: name, style = Theme.font(32f, FontWeight.ExtraBold, Theme.text), maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                            Icon(sf("checkmark.seal.fill"), null, tint = Theme.accent, modifier = Modifier.size(20.dp))
                        }
                        d?.artist?.fans?.takeIf { it > 0 }?.let {
                            Text("${"%,d".format(it).replace(',', '.')} fãs", style = Theme.font(14f, FontWeight.Medium, Theme.secondary))
                        }
                    }
                }
            }
            if (d == null) item { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { repeat(6) { Skeleton(Modifier.fillMaxWidth().height(56.dp)) } } }
            else {
                // Ações: Tocar (prisma) · Rádio · Seguir (compacto sem quebrar linha em telas de 360dp)
                item {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        PrismButton("Tocar", "play.fill", height = 46.dp, fontSize = 14f, iconSize = 16.dp, modifier = Modifier.weight(1f)) {
                            d.topTracks.firstOrNull()?.let { first ->
                                AudioPlayer.shuffleEnabled = false
                                AudioPlayer.play(first, d.topTracks, d.artist.name)
                            }
                        }
                        GlassButton("Rádio", "dot.radiowaves.left.and.right", height = 46.dp, fontSize = 14f, iconSize = 16.dp, modifier = Modifier.weight(1f)) {
                            d.topTracks.firstOrNull()?.let { AudioPlayer.startRadio(it) } ?: AppModel.showToast("Sem músicas para iniciar a rádio")
                        }
                        GlassButton(
                            if (following) "Seguindo" else "Seguir",
                            if (following) "checkmark" else "plus",
                            height = 46.dp, fontSize = 14f, iconSize = 15.dp,
                            tint = if (following) Theme.rose else null,
                            foreground = if (following) Theme.accent else Theme.text,
                            modifier = Modifier.weight(1f),
                        ) {
                            LibraryStore.toggleFollow(d.artist.name)
                        }
                    }
                }
                if (d.topTracks.isNotEmpty()) {
                    val limit = if (expandTop) 20 else 5
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            SectionHeader(
                                "Mais tocadas",
                                actionLabel = if (d.topTracks.size > 5) (if (expandTop) "Ver menos" else "Ver tudo") else null,
                                onAction = if (d.topTracks.size > 5) { { expandTop = !expandTop } } else null,
                            )
                            d.topTracks.take(limit).forEachIndexed { i, t -> TrackRow(t, rank = i + 1, queue = d.topTracks) }
                        }
                    }
                }
                if (d.albums.isNotEmpty()) {
                    val filtered = d.albums.filter { alb ->
                        when (discogFilter) {
                            "Álbuns" -> (alb.kind ?: "Álbum") == "Álbum"
                            "Singles e EPs" -> alb.kind == "Single" || alb.kind == "EP"
                            else -> true
                        }
                    }.ifEmpty { d.albums }
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SectionHeader("Discografia", actionLabel = "Ver tudo", onAction = { AppModel.push(LumeRoute.Albums("Discografia · ${d.artist.name}", filtered)) })
                            HRow(spacing = 8.dp) {
                                items(listOf("Todos", "Álbuns", "Singles e EPs")) { f -> PrismChip(f, discogFilter == f) { discogFilter = f } }
                            }
                            HRow { items(filtered.take(20), key = { it.id }) { a -> AlbumTile(a, subtitle = listOfNotNull(a.kind, a.year.ifEmpty { null }).joinToString(" · ")) { AppModel.push(LumeRoute.Album(a)) } } }
                        }
                    }
                }
                if (d.related.isNotEmpty()) item {
                    Column(Modifier.padding(bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Artistas parecidos")
                        HRow(spacing = 16.dp) { items(d.related, key = { it.id }) { a -> ArtistBubble(a) { AppModel.openArtist(a.name, a.deezerId) } } }
                    }
                }
            }
        }
        DetailHeader(detail?.artist?.name ?: name, listState, 260.dp, overlay = true)
    }
}

@Composable
fun RemotePlaylistScreen(pl: RemotePlaylist, bottomInset: Dp) {
    val tracks by produceState<List<Track>?>(null, pl.deezerId) { value = CatalogExplorerService.playlistTracks(pl.deezerId) }
    val listState = rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        DetailHeader(pl.title, listState, 235.dp)
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    ArtworkImage(pl.artworkURL, Modifier.size(200.dp), 24.dp, icon = "music.note.list")
                    Text(pl.title, style = Theme.font(23f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 24.dp))
                    Text(pl.subtitle, style = Theme.font(13.5f, color = Theme.secondary))
                }
            }
            val t = tracks
            if (t == null) item { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { repeat(8) { Skeleton(Modifier.fillMaxWidth().height(56.dp)) } } }
            else {
                item { PlayShuffleRow(t, pl.title) }
                item {
                    Row(Modifier.padding(horizontal = 20.dp)) {
                        GlassButton("Salvar na biblioteca", "plus", modifier = Modifier.weight(1f)) {
                            if (LibraryStore.playlists.any { it.name == pl.title }) {
                                AppModel.showToast("Esta playlist já está na sua biblioteca")
                            } else {
                                LibraryStore.createPlaylist(pl.title, "Deezer", "Deezer", pl.artworkURL, t)
                                AppModel.showToast("Playlist salva na biblioteca")
                            }
                        }
                    }
                }
                items(t.size) { TrackRow(t[it], queue = t) }
            }
        }
    }
}

@Composable
fun MixScreen(mix: PersonalizedMix, bottomInset: Dp) {
    val listState = rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        DetailHeader(mix.title, listState, 100.dp)
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item { GradientCard(mix.title, mix.subtitle, mix.icon, mix.hexA, mix.hexB, Modifier.padding(horizontal = 20.dp).fillMaxWidth().height(130.dp)) {} }
            item { PlayShuffleRow(mix.tracks, mix.title) }
            items(mix.tracks.size) { TrackRow(mix.tracks[it], queue = mix.tracks) }
        }
    }
}

@Composable
fun ReleasesScreen(bottomInset: Dp) {
    LaunchedEffect(Unit) { AppModel.markReleasesSeen() }
    val mine = AppModel.artistReleases
    val world = AppModel.feed?.newReleases ?: emptyList()
    val br = AppModel.feed?.brazilReleases ?: emptyList()
    Column(Modifier.fillMaxSize()) {
        DetailHeader("Lançamentos")
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            if (mine.isNotEmpty()) item { ReleaseSection("De quem você ouve", mine) }
            if (br.isNotEmpty()) item { ReleaseSection("Novidades do Brasil", br) }
            if (world.isNotEmpty()) item { ReleaseSection("Lançamentos no mundo", world) }
            if (mine.isEmpty() && br.isEmpty() && world.isEmpty()) item { EmptyState("bell", "Sem lançamentos por enquanto", "Puxe a Início para atualizar.") }
        }
    }
}

@Composable
private fun ReleaseSection(title: String, albums: List<AlbumShowcase>) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        SectionHeader(title)
        albums.take(30).forEach { a ->
            Row(Modifier.fillMaxWidth().heightIn(min = 68.dp).pressable(0.98f) { AppModel.push(LumeRoute.Album(a)) }.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                ArtworkImage(a.artworkURL, Modifier.size(56.dp), 12.dp, icon = "square.stack.fill")
                Column(Modifier.weight(1f)) {
                    Text(a.title, style = Theme.font(15.5f, FontWeight.Medium, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(a.artist, style = Theme.font(13f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text(Theme.shortDate(a.releaseDate), style = Theme.font(12.5f, color = Theme.tertiary))
            }
        }
    }
}

@Composable
fun TrackListScreen(title: String, tracks: List<Track>, bottomInset: Dp) {
    Column(Modifier.fillMaxSize()) {
        DetailHeader(title)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (tracks.isEmpty()) item { EmptyState("music.note", "Nada por aqui ainda", "As músicas aparecem aqui assim que você ouvir ou curtir.") }
            else {
                item { PlayShuffleRow(tracks, title) }
                items(tracks.size, key = { "$it${tracks[it].id}" }) { TrackRow(tracks[it], queue = tracks) }
            }
        }
    }
}

@Composable
fun AlbumGridScreen(title: String, albums: List<AlbumShowcase>, bottomInset: Dp) {
    Column(Modifier.fillMaxSize()) {
        DetailHeader(title)
        LazyVerticalGrid(GridCells.Fixed(2), Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = bottomInset, top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            items(albums, key = { it.id }) { a ->
                BoxWithConstraints {
                    AlbumTile(a, width = maxWidth) { AppModel.push(LumeRoute.Album(a)) }
                }
            }
        }
    }
}

@Composable
fun ArtistGridScreen(title: String, artists: List<ArtistInfo>, bottomInset: Dp) {
    LaunchedEffect(artists) { ArtworkStore.register(artists) }
    Column(Modifier.fillMaxSize()) {
        DetailHeader(title)
        LazyVerticalGrid(GridCells.Fixed(3), Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = bottomInset, top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            items(artists, key = { it.id }) { a ->
                BoxWithConstraints(contentAlignment = Alignment.Center) {
                    ArtistBubble(a, size = (maxWidth - 8.dp).coerceIn(76.dp, 106.dp)) { AppModel.openArtist(a.name, a.deezerId) }
                }
            }
        }
    }
}
