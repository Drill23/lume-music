package com.adriano.lumemusic.ui.screens

import androidx.compose.foundation.layout.heightIn
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.ChartCountry
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.LyricSearchHit
import com.adriano.lumemusic.data.MoodCategory
import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.data.RemotePlaylist
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.MusicEngine
import com.adriano.lumemusic.engine.SearchService
import com.adriano.lumemusic.ui.AlbumTile
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.Chrome
import com.adriano.lumemusic.ui.rememberKeyboardCloser
import com.adriano.lumemusic.ui.ArtistBubble
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.EmptyState
import com.adriano.lumemusic.ui.GradientCard
import com.adriano.lumemusic.ui.HRow
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.PrismChip
import com.adriano.lumemusic.ui.SectionHeader
import com.adriano.lumemusic.ui.TrackArtwork
import com.adriano.lumemusic.ui.TrackRow
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay

private val scopes = listOf("Tudo", "Músicas", "Artistas", "Álbuns", "Playlists", "Letras")

private data class Results(
    val songs: List<Track> = emptyList(), val artists: List<ArtistInfo> = emptyList(), val albums: List<AlbumShowcase> = emptyList(),
    val playlists: List<RemotePlaylist> = emptyList(), val lyrics: List<LyricSearchHit> = emptyList(),
)

@Composable
fun SearchScreen(bottomInset: Dp) {
    var query by remember { mutableStateOf("") }
    var submitted by remember { mutableStateOf("") }
    var scope by remember { mutableStateOf("Tudo") }
    var suggestions by remember { mutableStateOf<List<String>>(emptyList()) }
    var results by remember { mutableStateOf<Results?>(null) }
    var loading by remember { mutableStateOf(false) }
    var browse by remember { mutableStateOf("Gêneros") }
    val focus = remember { FocusRequester() }
    val fm = LocalFocusManager.current

    LaunchedEffect(AppModel.searchFocusToken) { if (AppModel.searchFocusToken > 0) runCatching { focus.requestFocus() } }
    LaunchedEffect(AppModel.searchLyricsToken) { if (AppModel.searchLyricsToken > 0) scope = "Letras" }
    LaunchedEffect(query) {
        if (query.trim().length < 2) { suggestions = emptyList(); if (query.isBlank()) { submitted = ""; results = null }; return@LaunchedEffect }
        delay(220)
        suggestions = SearchService.suggestions(query)
    }
    LaunchedEffect(submitted, scope) {
        val q = submitted
        if (q.isBlank()) return@LaunchedEffect
        loading = true
        results = coroutineScope {
            val songs = async { if (scope in listOf("Tudo", "Músicas")) MusicEngine.searchSongs(q, 25) else emptyList() }
            val artists = async { if (scope in listOf("Tudo", "Artistas")) SearchService.artists(q) else emptyList() }
            val albums = async { if (scope in listOf("Tudo", "Álbuns")) SearchService.albums(q) else emptyList() }
            val pls = async { if (scope in listOf("Tudo", "Playlists")) SearchService.playlists(q) else emptyList() }
            val lyr = async { if (scope in listOf("Tudo", "Letras")) SearchService.searchByLyrics(q) else emptyList() }
            Results(songs.await(), artists.await(), albums.await(), pls.await(), lyr.await())
        }
        loading = false
    }
    val closeKeyboard = rememberKeyboardCloser()
    fun submit(q: String) { query = q; submitted = q.trim(); suggestions = emptyList(); LibraryStore.addSearchTerm(q); closeKeyboard() }
    LaunchedEffect(AppModel.searchPrefillToken) { if (AppModel.searchPrefillToken > 0 && AppModel.searchPrefill.isNotBlank()) submit(AppModel.searchPrefill) }

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Text("Buscar", style = Theme.font(32f, FontWeight.Bold, Theme.text), modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).height(52.dp).glass(RoundedCornerShape(26.dp)).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(sf("magnifyingglass"), null, tint = Theme.secondary, modifier = Modifier.size(20.dp))
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) Text("Músicas, artistas, álbuns e trechos", style = Theme.font(16f, color = Theme.tertiary))
                BasicTextField(query, { query = it }, singleLine = true, textStyle = Theme.font(16f, color = Theme.text), cursorBrush = SolidColor(Theme.rose),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { if (query.isBlank()) closeKeyboard() else submit(query) }),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus))
            }
            if (query.isNotEmpty()) Box(Modifier.size(Chrome.minTouch).pressable(0.85f) { query = ""; submitted = ""; results = null }, contentAlignment = Alignment.Center) {
                Icon(sf("xmark.circle.fill"), "Limpar", tint = Theme.tertiary, modifier = Modifier.size(20.dp))
            }
        }
        HRow(spacing = 8.dp, contentPadding = PaddingValues(horizontal = 20.dp, vertical = 6.dp)) { items(scopes) { s -> PrismChip(s, scope == s) { scope = s } } }

        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 6.dp, bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            if (suggestions.isNotEmpty() && submitted != query.trim()) {
                items(suggestions, key = { it }) { s ->
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).pressable(0.99f) { submit(s) }.padding(horizontal = 24.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Icon(sf("magnifyingglass"), null, tint = Theme.tertiary, modifier = Modifier.size(18.dp))
                        Text(s, style = Theme.font(16f, color = Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Icon(sf("arrow.up.left"), null, tint = Theme.tertiary, modifier = Modifier.size(18.dp))
                    }
                }
            } else if (submitted.isBlank()) {
                if (LibraryStore.searchHistory.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        SectionHeader("Buscas recentes", actionLabel = "Limpar", onAction = { LibraryStore.clearSearchHistory() })
                        LibraryStore.searchHistory.take(6).forEach { h ->
                            Row(Modifier.fillMaxWidth().height(Chrome.minTouch).pressable(0.99f) { submit(h) }.padding(horizontal = 24.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                                Icon(sf("clock"), null, tint = Theme.tertiary, modifier = Modifier.size(18.dp))
                                Text(h, style = Theme.font(16f, color = Theme.text), maxLines = 1)
                            }
                        }
                    }
                }
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader("Navegar por categorias")
                        HRow(spacing = 8.dp) { items(listOf("Gêneros", "Climas", "Décadas", "Países")) { b -> PrismChip(b, browse == b) { browse = b } } }
                        val cards: List<Triple<String, Pair<Long, Long>, () -> Unit>> = when (browse) {
                            "Gêneros" -> MusicGenre.all.map { g -> Triple(g.title, g.hexA to g.hexB) { AppModel.push(LumeRoute.Genre(g)) } }
                            "Climas" -> (MoodCategory.presets + MoodCategory.activities).map { m -> Triple(m.title, m.hexA to m.hexB) { AppModel.push(LumeRoute.Mood(m)) } }
                            "Décadas" -> MoodCategory.decades.map { m -> Triple(m.title, m.hexA to m.hexB) { AppModel.push(LumeRoute.Mood(m)) } }
                            else -> ChartCountry.all.map { c -> Triple("${c.flag} ${c.name}", c.hexA to c.hexB) { AppModel.push(LumeRoute.Country(c)) } }
                        }
                        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            cards.chunked(2).forEach { pair ->
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    pair.forEach { (t, c, click) -> GradientCard(t, null, null, c.first, c.second, Modifier.weight(1f).height(84.dp), onClick = click) }
                                    if (pair.size == 1) Column(Modifier.weight(1f)) {}
                                }
                            }
                        }
                    }
                }
            } else {
                val r = results
                if (loading && r == null) item { Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Theme.rose) } }
                if (r != null) {
                    val empty = r.songs.isEmpty() && r.artists.isEmpty() && r.albums.isEmpty() && r.playlists.isEmpty() && r.lyrics.isEmpty()
                    if (empty && !loading) item { EmptyState("magnifyingglass", "Nada encontrado", "Tente outro termo ou verifique a ortografia.") }
                    if (scope == "Tudo" && r.songs.isNotEmpty()) item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            SectionHeader("Melhor resultado")
                            val t = r.songs.first()
                            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).pressable(0.98f) { AudioPlayer.play(t, r.songs) }.glass(RoundedCornerShape(22.dp)).padding(14.dp),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                                TrackArtwork(t, Modifier.size(76.dp), 14.dp)
                                Column {
                                    Text(t.title, style = Theme.font(18f, FontWeight.Bold, Theme.text), maxLines = 2)
                                    Text("Música · ${t.artist}", style = Theme.font(13.5f, color = Theme.secondary), maxLines = 1)
                                }
                            }
                        }
                    }
                    if (r.songs.isNotEmpty()) item {
                        Column {
                            SectionHeader("Músicas")
                            r.songs.take(if (scope == "Tudo") 6 else 30).forEach { TrackRow(it, queue = r.songs) }
                        }
                    }
                    if (r.artists.isNotEmpty()) item {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SectionHeader("Artistas")
                            HRow { items(r.artists, key = { it.id }) { a -> ArtistBubble(a) { AppModel.openArtist(a.name, a.deezerId) } } }
                        }
                    }
                    if (r.albums.isNotEmpty()) item {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SectionHeader("Álbuns")
                            HRow { items(r.albums, key = { it.id }) { a -> AlbumTile(a) { AppModel.push(LumeRoute.Album(a)) } } }
                        }
                    }
                    if (r.playlists.isNotEmpty()) item {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SectionHeader("Playlists")
                            HRow { items(r.playlists, key = { it.id }) { p ->
                                Column(Modifier.size(width = 150.dp, height = 210.dp).pressable(0.96f) { AppModel.push(LumeRoute.RemotePlaylistRoute(p)) }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    ArtworkImage(p.artworkURL, Modifier.size(150.dp), 16.dp, icon = "music.note.list")
                                    Text(p.title, style = Theme.font(14.5f, FontWeight.SemiBold, Theme.text), maxLines = 1)
                                    Text(p.subtitle, style = Theme.font(12.5f, color = Theme.secondary), maxLines = 1)
                                }
                            } }
                        }
                    }
                    if (r.lyrics.isNotEmpty()) item {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            SectionHeader("Trechos de letras")
                            r.lyrics.forEach { h ->
                                Column(Modifier.fillMaxWidth().pressable(0.99f) { AudioPlayer.play(h.track, r.lyrics.map { it.track }) }.padding(horizontal = 20.dp, vertical = 8.dp)) {
                                    Text(h.track.title, style = Theme.font(16f, FontWeight.SemiBold, Theme.text), maxLines = 1)
                                    Text(h.track.artist, style = Theme.font(13f, color = Theme.secondary), maxLines = 1)
                                    Text("“${h.snippet}”", style = Theme.font(13.5f, color = Theme.accent), maxLines = 2, modifier = Modifier.padding(top = 2.dp))
                                }
                            }
                        }
                    }
                    if (scope == "Letras" && r.lyrics.isEmpty() && !loading) item { EmptyState("quote.bubble", "Nenhuma letra encontrada", "Digite um trecho da música para achar a faixa.") }
                }
            }
        }
    }
}
