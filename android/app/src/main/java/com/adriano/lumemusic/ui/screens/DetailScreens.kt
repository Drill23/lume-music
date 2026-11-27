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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
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
            GlassIconButton(if (saved) "heart.fill" else "heart", foreground = if (saved) Theme.rose else Theme.text, desc = "Salvar álbum") { LibraryStore.toggleSaveAlbum(album, tracks) }
        }
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    ArtworkImage(album.artworkURL, Modifier.size(220.dp), 26.dp, icon = "square.stack.fill")
                    Text(album.title, style = Theme.font(24f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 24.dp))
                    Text(album.artist, style = Theme.font(16f, FontWeight.Medium, Theme.accent), modifier = Modifier.pressable(0.95f) { AppModel.openArtist(album.artist) })
                    Text(listOfNotNull(album.kind, album.year.ifEmpty { null }, album.genre.ifEmpty { null }).joinToString(" · "), style = Theme.font(13f, color = Theme.secondary))
                }
            }
            item { PlayShuffleRow(tracks, album.title) }
            item {
                Row(Modifier.padding(horizontal = 20.dp)) { GlassButton("Baixar álbum", "arrow.down.circle", modifier = Modifier.weight(1f)) { DownloadManager.downloadBatch(tracks); AppModel.showToast("Baixando ${tracks.size} músicas") } }
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
    val listState = rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        DetailHeader(name, listState, 215.dp)
        val d = detail
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            item {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val pic = d?.artist?.pictureURL ?: ""
                    if (pic.isNotEmpty()) ArtworkImage(pic, Modifier.size(170.dp), shape = CircleShape, icon = "person.fill") else com.adriano.lumemusic.ui.ArtistAvatar(name, 170.dp)
                    Text(d?.artist?.name ?: name, style = Theme.font(26f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center)
                    d?.artist?.fans?.let { Text("${"%,d".format(it).replace(',', '.')} fãs", style = Theme.font(13.5f, color = Theme.secondary)) }
                    Row(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        GlassButton(if (following) "Seguindo" else "Seguir", if (following) "checkmark" else "plus", modifier = Modifier.weight(1f)) { LibraryStore.toggleFollow(name) }
                        GlassButton("Rádio", "dot.radiowaves.left.and.right", modifier = Modifier.weight(1f)) { d?.topTracks?.firstOrNull()?.let { com.adriano.lumemusic.audio.AudioPlayer.startRadio(it) } }
                    }
                }
            }
            if (d == null) item { Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { repeat(6) { Skeleton(Modifier.fillMaxWidth().height(56.dp)) } } }
            else {
                if (d.topTracks.isNotEmpty()) {
                    item { PlayShuffleRow(d.topTracks, d.artist.name) }
                    item { Column { SectionHeader("Populares"); d.topTracks.take(10).forEachIndexed { i, t -> TrackRow(t, rank = i + 1, queue = d.topTracks) } } }
                }
                if (d.albums.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Discografia", onAction = { AppModel.push(LumeRoute.Albums("Discografia · ${d.artist.name}", d.albums)) })
                        HRow { items(d.albums.take(20), key = { it.id }) { a -> AlbumTile(a, subtitle = listOfNotNull(a.kind, a.year.ifEmpty { null }).joinToString(" · ")) { AppModel.push(LumeRoute.Album(a)) } } }
                    }
                }
                if (d.related.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Artistas semelhantes")
                        HRow { items(d.related, key = { it.id }) { a -> ArtistBubble(a) { AppModel.openArtist(a.name, a.deezerId) } } }
                    }
                }
            }
        }
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
                            LibraryStore.createPlaylist(pl.title, "Deezer", "Deezer", pl.artworkURL, t); AppModel.showToast("Playlist salva na biblioteca")
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
                    Text(a.title, style = Theme.font(16f, FontWeight.Medium, Theme.text), maxLines = 1)
                    Text(a.artist, style = Theme.font(13f, color = Theme.secondary), maxLines = 1)
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
            horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            items(albums, key = { it.id }) { a -> AlbumTile(a, width = 160.dp) { AppModel.push(LumeRoute.Album(a)) } }
        }
    }
}

@Composable
fun ArtistGridScreen(title: String, artists: List<ArtistInfo>, bottomInset: Dp) {
    LaunchedEffect(artists) { ArtworkStore.register(artists) }
    Column(Modifier.fillMaxSize()) {
        DetailHeader(title)
        LazyVerticalGrid(GridCells.Fixed(3), Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = bottomInset, top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            items(artists, key = { it.id }) { a -> ArtistBubble(a, size = 92.dp) { AppModel.openArtist(a.name, a.deezerId) } }
        }
    }
}
