package com.adriano.lumemusic.ui.screens

import androidx.compose.foundation.layout.heightIn
import com.adriano.lumemusic.ui.Chrome
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import com.adriano.lumemusic.ui.KeyboardOkButton
import com.adriano.lumemusic.ui.keyboardDismissing
import com.adriano.lumemusic.ui.rememberKeyboardCloser
import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.border
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.style.TextAlign
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.DownloadManager
import com.adriano.lumemusic.data.DownloadState
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.MusicPlaylist
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.ImportException
import com.adriano.lumemusic.engine.ImportService
import com.adriano.lumemusic.ui.AlbumTile
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtistAvatar
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.DetailHeader
import com.adriano.lumemusic.ui.EmptyState
import com.adriano.lumemusic.ui.GlassButton
import com.adriano.lumemusic.ui.GlassIconButton
import com.adriano.lumemusic.ui.HRow
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.PrismButton
import com.adriano.lumemusic.ui.PrismChip
import com.adriano.lumemusic.ui.SectionHeader
import com.adriano.lumemusic.ui.TrackRow
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.launch

private val filters = listOf("Tudo", "Playlists", "Álbuns", "Artistas", "Baixadas")

@Composable
fun LibraryScreen(bottomInset: Dp) {
    var filter by remember { mutableStateOf("Tudo") }
    var showNew by remember { mutableStateOf(false) }
    val store = LibraryStore
    val failed = DownloadManager.failedItems
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(22.dp)) {
        item {
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 20.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Biblioteca", style = Theme.font(34f, FontWeight.Bold, Theme.text), modifier = Modifier.weight(1f))
                GlassIconButton("plus", size = 42.dp, desc = "Nova playlist") { showNew = true }
            }
        }
        item { HRow(spacing = 8.dp) { items(filters) { f -> PrismChip(f, filter == f) { filter = f } } } }
        if (DownloadManager.pendingCount > 0) item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).pressable(0.98f) { AppModel.push(LumeRoute.Downloads) }.glass(RoundedCornerShape(18.dp), tint = Theme.sky).padding(14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(sf("arrow.down.circle.fill"), null, tint = Theme.sky, modifier = Modifier.size(22.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        if (DownloadManager.paused) "Downloads pausados (${DownloadManager.pendingCount})"
                        else "Baixando ${DownloadManager.pendingCount} ${if (DownloadManager.pendingCount == 1) "música" else "músicas"}…",
                        style = Theme.font(15f, FontWeight.SemiBold, Theme.text),
                    )
                    LinearProgressIndicator(progress = { DownloadManager.overallProgress.toFloat() }, modifier = Modifier.fillMaxWidth().clip(CircleShape), color = Theme.sky, trackColor = Theme.fill)
                }
                Icon(sf("chevron.right"), null, tint = Theme.tertiary, modifier = Modifier.size(16.dp))
            }
        }
        if (failed.isNotEmpty()) item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).pressable(0.98f) { DownloadManager.retryAllFailed() }.glass(RoundedCornerShape(18.dp), tint = Theme.danger).padding(14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(sf("exclamationmark.triangle.fill"), null, tint = Theme.danger, modifier = Modifier.size(22.dp))
                Column { Text("${failed.size} downloads falharam", style = Theme.font(15f, FontWeight.SemiBold, Theme.text)); Text("Toque para tentar novamente", style = Theme.font(12.5f, color = Theme.secondary)) }
            }
        }
        if (filter == "Tudo") item {
            val quick = listOf(
                Triple("Curtidas", "heart.fill", Pair(store.favoriteTracks, Theme.rose)),
                Triple("Histórico", "clock.fill", Pair(store.recentTracks, Theme.peach)),
                Triple("Mais ouvidas", "chart.line.uptrend.xyaxis", Pair(store.mostPlayedTracks, Theme.lavender)),
                Triple("Baixadas", "arrow.down.circle.fill", Pair(store.downloadedTracks, Theme.sky)),
            )
            Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                quick.chunked(2).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        pair.forEach { (t, icon, data) ->
                            val (list, tint) = data
                            Row(
                                Modifier.weight(1f).heightIn(min = 66.dp).pressable(0.96f) {
                                    if (t == "Baixadas") AppModel.push(LumeRoute.Downloads)
                                    else AppModel.push(LumeRoute.Tracks(t, list))
                                }
                                    .glass(RoundedCornerShape(20.dp)).padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Box(Modifier.size(36.dp).clip(CircleShape).background(tint.copy(0.18f)), contentAlignment = Alignment.Center) {
                                    Icon(sf(icon), null, tint = tint, modifier = Modifier.size(18.dp))
                                }
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                                    Text(t, style = Theme.font(14.5f, FontWeight.SemiBold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text("${list.size}", style = Theme.font(12.5f, color = Theme.secondary))
                                }
                            }
                        }
                    }
                }
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 62.dp).pressable(0.97f) { AppModel.push(LumeRoute.Replay) }
                        .glass(RoundedCornerShape(20.dp)).padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(Modifier.size(36.dp).clip(CircleShape).background(Theme.lavender.copy(0.18f)), contentAlignment = Alignment.Center) {
                        Icon(sf("sparkles"), null, tint = Theme.lavender, modifier = Modifier.size(18.dp))
                    }
                    Text("Lume Replay · Seu Resumo", style = Theme.font(15f, FontWeight.SemiBold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Icon(sf("chevron.right"), null, tint = Theme.tertiary, modifier = Modifier.size(17.dp))
                }
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 62.dp).pressable(0.97f) { AppModel.push(LumeRoute.ImportHub) }
                        .glass(RoundedCornerShape(20.dp)).padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(Modifier.size(36.dp).clip(CircleShape).background(Theme.sky.copy(0.18f)), contentAlignment = Alignment.Center) {
                        Icon(sf("square.and.arrow.down"), null, tint = Theme.sky, modifier = Modifier.size(18.dp))
                    }
                    Text("Importar músicas", style = Theme.font(15f, FontWeight.SemiBold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Icon(sf("chevron.right"), null, tint = Theme.tertiary, modifier = Modifier.size(17.dp))
                }
            }
        }
        if (filter in listOf("Tudo", "Playlists")) item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader("Suas playlists")
                if (store.playlists.isEmpty()) EmptyState("music.note.list", "Nenhuma playlist", "Crie uma playlist ou importe do Spotify, YouTube Music e Apple Music.")
                else store.playlists.forEach { PlaylistRow(it) }
            }
        }
        if (filter in listOf("Tudo", "Álbuns")) item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader("Álbuns salvos")
                if (store.savedAlbums.isEmpty()) EmptyState("square.stack.fill", "Nenhum álbum salvo", "Salve álbuns para tê-los sempre à mão.")
                else HRow { items(store.savedAlbums, key = { it.id }) { a -> AlbumTile(a) { AppModel.push(LumeRoute.Album(a)) } } }
            }
        }
        if (filter in listOf("Tudo", "Artistas")) item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader("Artistas")
                if (store.followedArtists.isEmpty()) EmptyState("person.fill", "Nenhum artista encontrado", "Siga artistas pela página deles.")
                else store.followedArtists.forEach { a ->
                    Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).pressable(0.98f) { AppModel.openArtist(a) }.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        ArtistAvatar(a, 48.dp); Text(a, style = Theme.font(16f, color = Theme.text), maxLines = 1, modifier = Modifier.weight(1f)); Icon(sf("chevron.right"), null, tint = Theme.tertiary)
                    }
                }
            }
        }
        if (filter in listOf("Tudo", "Baixadas")) {
            val dl = store.downloadedTracks
            item { SectionHeader("Baixadas (${dl.size})", actionLabel = "Central", onAction = { AppModel.push(LumeRoute.Downloads) }) }
            if (dl.isEmpty()) item { EmptyState("arrow.down.circle", "Nenhuma música baixada", "Baixe músicas para ouvir sem internet.") }
            else items(dl.take(if (filter == "Tudo") 6 else 500), key = { "dl${it.id}" }) { TrackRow(it, queue = dl) }
        }
        if (filter == "Tudo" && store.recentTracks.isNotEmpty()) {
            item { SectionHeader("Tocadas recentemente", actionLabel = "Ver tudo", onAction = { AppModel.push(LumeRoute.Tracks("Histórico", store.recentTracks)) }) }
            items(store.recentTracks.take(5), key = { "rc${it.id}" }) { TrackRow(it, queue = store.recentTracks) }
        }
    }
    if (showNew) NewPlaylistDialog { showNew = false }
}

@Composable
fun NewPlaylistDialog(onDismiss: () -> Unit) {
    var name by remember { mutableStateOf("") }
    val closeKeyboard = rememberKeyboardCloser()
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = Theme.canvasRaised,
        title = { Text("Nova playlist", color = Theme.text) },
        text = {
            Column(Modifier.keyboardDismissing(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Dê um nome para a sua nova playlist.", style = Theme.font(14f, color = Theme.secondary))
                Box(Modifier.fillMaxWidth().height(48.dp).glass(RoundedCornerShape(24.dp)).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
                    if (name.isEmpty()) Text("Nome", style = Theme.font(16f, color = Theme.tertiary))
                    BasicTextField(name, { name = it }, singleLine = true, textStyle = Theme.font(16f, color = Theme.text), cursorBrush = SolidColor(Theme.rose),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { closeKeyboard() }),
                        modifier = Modifier.fillMaxWidth())
                }
            }
        },
        confirmButton = { TextButton({ if (name.isNotBlank()) { LibraryStore.createPlaylist(name.trim()); onDismiss() } }) { Text("Criar", color = Theme.accent) } },
        dismissButton = { TextButton(onDismiss) { Text("Cancelar", color = Theme.secondary) } },
    )
}

@Composable
private fun PlaylistRow(pl: MusicPlaylist) {
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).pressable(0.98f) { AppModel.push(LumeRoute.Playlist(pl.id)) }.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        ArtworkImage(pl.artworkURL, Modifier.size(54.dp), 12.dp, icon = "music.note.list")
        Column(Modifier.weight(1f)) {
            Text(pl.name, style = Theme.font(16f, FontWeight.Medium, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${pl.trackIds.size} músicas" + if (pl.sourceBadge != "Lume") " · ${pl.sourceBadge}" else "", style = Theme.font(13f, color = Theme.secondary), maxLines = 1)
        }
        Icon(sf("chevron.right"), null, tint = Theme.tertiary, modifier = Modifier.size(18.dp))
    }
}

@Composable
fun PlaylistScreen(id: String, bottomInset: Dp) {
    val pl = LibraryStore.playlists.firstOrNull { it.id == id }
    var confirm by remember { mutableStateOf(false) }
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        DetailHeader(pl?.name ?: "Playlist", listState, 230.dp) {
            GlassIconButton("trash", size = 42.dp, desc = "Excluir") { confirm = true }
        }
        if (pl == null) { EmptyState("music.note.list", "Playlist não encontrada", ""); return@Column }
        val tracks = LibraryStore.tracks(pl)
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                Column(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val coverShape = RoundedCornerShape(24.dp)
                    ArtworkImage(pl.artworkURL, Modifier.size(200.dp).shadow(18.dp, coverShape, ambientColor = Theme.shadow, spotColor = Theme.shadow).border(0.6.dp, Theme.hairline, coverShape), 24.dp, icon = "music.note.list")
                    Text(pl.name, style = Theme.font(24f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 24.dp))
                    Text("${tracks.size} músicas · ${pl.sourceBadge}", style = Theme.font(13.5f, color = Theme.secondary))
                }
            }
            item {
                Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.weight(1f)) { PlayShuffleRow(tracks, pl.name, horizontalPadding = 0.dp) }
                    GlassIconButton("arrow.down.circle", size = 48.dp, desc = "Baixar tudo") {
                        val pending = tracks.filter { !LibraryStore.isDownloaded(it.id) }
                        if (pending.isEmpty()) AppModel.showToast("Todas as músicas já estão baixadas")
                        else { DownloadManager.downloadBatch(pending); AppModel.showToast("Baixando ${pending.size} músicas") }
                    }
                }
            }
            if (tracks.isEmpty()) item { EmptyState("music.note", "Playlist vazia", "Adicione músicas pelo menu ••• de qualquer faixa.") }
            items(tracks, key = { "pl${it.id}" }) { t ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { TrackRow(t, queue = tracks) }
                    Box(Modifier.padding(end = 6.dp).size(width = 38.dp, height = Chrome.minTouch).pressable(0.85f) { LibraryStore.removeTrack(t.id, pl.id) }, contentAlignment = Alignment.Center) {
                        Icon(sf("minus.circle.fill"), "Remover da playlist", tint = Theme.tertiary, modifier = Modifier.size(20.dp))
                    }
                }
            }
        }
    }
    if (confirm && pl != null) AlertDialog(
        onDismissRequest = { confirm = false }, containerColor = Theme.canvasRaised, title = { Text("Excluir playlist?", color = Theme.text) },
        text = { Text("“${pl.name}” será removida. As músicas continuam na biblioteca.", color = Theme.secondary) },
        confirmButton = { TextButton({ LibraryStore.deletePlaylist(pl.id); confirm = false; AppModel.pop() }) { Text("Excluir", color = Theme.danger) } },
        dismissButton = { TextButton({ confirm = false }) { Text("Cancelar", color = Theme.secondary) } },
    )
}

@Composable
fun DownloadsScreen(bottomInset: Dp) {
    val dl = LibraryStore.downloadedTracks
    val states = DownloadManager.statesById
    val active = states.filter { it.value.isActive }
    var confirmClearAll by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        DetailHeader("Central de Downloads")
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).glass(RoundedCornerShape(22.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Armazenamento offline", style = Theme.font(13f, color = Theme.secondary))
                    Text(LibraryStore.offlineStorageFormatted, style = Theme.font(28f, FontWeight.Bold, Theme.text))
                    Text("${dl.size} músicas baixadas · ${DownloadManager.pendingCount} na fila", style = Theme.font(13.5f, color = Theme.secondary))
                    if (DownloadManager.pendingCount > 0) {
                        LinearProgressIndicator(progress = { DownloadManager.overallProgress.toFloat() }, modifier = Modifier.fillMaxWidth().clip(CircleShape), color = Theme.rose, trackColor = Theme.fill)
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            GlassButton(if (DownloadManager.paused) "Retomar" else "Pausar", if (DownloadManager.paused) "play.fill" else "pause.fill", height = 46.dp, fontSize = 14.5f, modifier = Modifier.weight(1f)) { DownloadManager.togglePauseAll() }
                            GlassButton("Cancelar tudo", "xmark.circle", height = 46.dp, fontSize = 14.5f, modifier = Modifier.weight(1f)) { DownloadManager.cancelAll() }
                        }
                    }
                }
            }
            if (active.isNotEmpty()) {
                item { SectionHeader("Em andamento") }
                items(active.keys.toList(), key = { "act$it" }) { id ->
                    val t = LibraryStore.tracksById[id] ?: return@items
                    val st = states[id]
                    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        com.adriano.lumemusic.ui.TrackArtwork(t, Modifier.size(46.dp), 8.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(t.title, style = Theme.font(15f, color = Theme.text), maxLines = 1)
                            LinearProgressIndicator(progress = { (st?.fraction ?: 0.0).toFloat() }, modifier = Modifier.fillMaxWidth().clip(CircleShape), color = Theme.rose, trackColor = Theme.fill)
                            Text(
                                when (st) {
                                    is DownloadState.Queued -> "Na fila"
                                    is DownloadState.Resolving -> "Preparando…"
                                    is DownloadState.Downloading -> "Baixando ${(st.progress * 100).toInt()}%"
                                    else -> "Baixando…"
                                },
                                style = Theme.font(12f, color = Theme.secondary),
                            )
                        }
                        Box(Modifier.size(Chrome.minTouch).pressable(0.85f) { DownloadManager.cancel(id) }, contentAlignment = Alignment.Center) { Icon(sf("xmark.circle.fill"), "Cancelar", tint = Theme.tertiary) }
                    }
                }
            }
            val failed = DownloadManager.failedItems
            if (failed.isNotEmpty()) {
                item { SectionHeader("Falharam", actionLabel = "Tentar todas", onAction = { DownloadManager.retryAllFailed() }) }
                items(failed, key = { "f${it.first.id}" }) { (t, reason) ->
                    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp).height(56.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Column(Modifier.weight(1f)) { Text(t.title, style = Theme.font(15f, color = Theme.text), maxLines = 1); Text(reason, style = Theme.font(12.5f, color = Theme.danger)) }
                        Box(Modifier.size(Chrome.minTouch).pressable(0.85f) { DownloadManager.retry(t.id) }, contentAlignment = Alignment.Center) { Icon(sf("arrow.clockwise"), "Tentar de novo", tint = Theme.accent) }
                    }
                }
            }
            item { SectionHeader("Baixadas (${dl.size})") }
            if (dl.isEmpty()) item { EmptyState("arrow.down.circle", "Nenhuma música baixada", "Use ••• › Baixar em qualquer música.") }
            items(dl, key = { "d${it.id}" }) { t ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { TrackRow(t, queue = dl) }
                    Text(LibraryStore.fileSizeFormatted(t.id), style = Theme.font(12f, color = Theme.tertiary), modifier = Modifier.padding(end = 20.dp))
                }
            }
            if (dl.isNotEmpty()) item { Box(Modifier.padding(horizontal = 20.dp)) { GlassButton("Apagar todos os downloads", "trash") { confirmClearAll = true } } }
        }
    }
    if (confirmClearAll) AlertDialog(
        onDismissRequest = { confirmClearAll = false },
        containerColor = Theme.canvasRaised,
        title = { Text("Apagar todos os downloads?", color = Theme.text) },
        text = { Text("Todas as ${dl.size} músicas salvas offline serão removidas deste aparelho. Suas playlists e curtidas continuam intactas.", color = Theme.secondary) },
        confirmButton = {
            TextButton({
                LibraryStore.removeAllDownloads()
                confirmClearAll = false
                AppModel.showToast("Downloads apagados")
            }) { Text("Apagar", color = Theme.danger) }
        },
        dismissButton = { TextButton({ confirmClearAll = false }) { Text("Cancelar", color = Theme.secondary) } },
    )
}

@Composable
fun ReplayScreen(bottomInset: Dp) {
    val s = LibraryStore.replaySummary
    Column(Modifier.fillMaxSize()) {
        DetailHeader("Lume Replay")
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            item {
                Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).clip(RoundedCornerShape(28.dp)).background(Theme.prismDiagonal).padding(22.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Seu resumo", style = Theme.font(14f, FontWeight.SemiBold, Theme.onPrism.copy(0.7f)))
                    Text("${s.totalMinutes} min", style = Theme.rounded(48f, FontWeight.Bold, Theme.onPrism))
                    Text("ouvidos em ${s.totalPlays} reproduções", style = Theme.font(15f, color = Theme.onPrism.copy(0.8f)))
                    Row(horizontalArrangement = Arrangement.spacedBy(22.dp), modifier = Modifier.padding(top = 8.dp)) {
                        Column { Text("${s.uniqueTracks}", style = Theme.rounded(24f, FontWeight.Bold, Theme.onPrism)); Text("músicas", style = Theme.font(12f, color = Theme.onPrism.copy(0.7f))) }
                        Column { Text("${s.uniqueArtists}", style = Theme.rounded(24f, FontWeight.Bold, Theme.onPrism)); Text("artistas", style = Theme.font(12f, color = Theme.onPrism.copy(0.7f))) }
                    }
                }
            }
            if (s.topTracks.isEmpty()) item { EmptyState("sparkles", "Ainda sem histórico", "Ouça algumas músicas e volte aqui para ver o seu resumo.") }
            else {
                item { SectionHeader("Suas músicas favoritas") }
                items(s.topTracks.size) { i -> val (t, n) = s.topTracks[i]
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f)) { TrackRow(t, rank = i + 1, queue = s.topTracks.map { it.first }) }
                        Text("$n×", style = Theme.font(13f, FontWeight.SemiBold, Theme.secondary), modifier = Modifier.padding(end = 20.dp))
                    }
                }
                item { SectionHeader("Seus artistas") }
                items(s.topArtists.size) { i -> val (name, n) = s.topArtists[i]
                    Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).pressable(0.98f) { AppModel.openArtist(name) }.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        Text("${i + 1}", style = Theme.font(14.5f, FontWeight.Bold, Theme.secondary), modifier = Modifier.width(26.dp))
                        ArtistAvatar(name, 46.dp); Text(name, style = Theme.font(16f, color = Theme.text), maxLines = 1, modifier = Modifier.weight(1f)); Text("$n×", style = Theme.font(13f, color = Theme.secondary))
                    }
                }
            }
        }
    }
}

@Composable
fun ImportScreen(bottomInset: Dp) {
    val coordinator = remember { ImportCoordinator() }
    val scope = rememberCoroutineScope()
    val closeKeyboard = rememberKeyboardCloser()
    var showList by remember { mutableStateOf(false) }
    var rawListName by remember { mutableStateOf("") }
    var rawListText by remember { mutableStateOf("") }
    var textFocused by remember { mutableStateOf(false) }

    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    Column(Modifier.fillMaxSize()) {
        DetailHeader("Importar músicas", listState, 48.dp)
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(top = 6.dp, bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            item {
                Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Importar músicas", style = Theme.font(32f, FontWeight.Bold, Theme.text))
                    Text("Traga suas playlists e músicas de outros serviços para a Lume.", style = Theme.font(15f, color = Theme.secondary))
                }
            }
            item {
                Box(Modifier.padding(horizontal = 20.dp)) {
                    ImportHubPanel(coordinator)
                }
            }
            if (coordinator.phase is ImportPhase.Idle) {
                item {
                    Column(
                        Modifier.fillMaxWidth().padding(horizontal = 20.dp).glass(RoundedCornerShape(24.dp)).padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 44.dp).pressable(0.98f) { com.adriano.lumemusic.platform.Haptics.light(); showList = !showList },
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            Box(
                                Modifier.size(44.dp).clip(CircleShape).background(Theme.prismDiagonal),
                                contentAlignment = Alignment.Center,
                            ) { Icon(sf("text.badge.plus"), null, tint = Theme.onPrism, modifier = Modifier.size(20.dp)) }
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text("Lista de texto", style = Theme.font(17f, FontWeight.SemiBold, Theme.text))
                                Text("Uma música por linha, no formato Artista - Música.", style = Theme.font(13.5f, color = Theme.secondary))
                            }
                            Icon(sf(if (showList) "chevron.up" else "chevron.down"), null, tint = Theme.tertiary, modifier = Modifier.size(18.dp))
                        }
                        if (showList) {
                            Box(Modifier.fillMaxWidth().height(48.dp).glass(RoundedCornerShape(24.dp)).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
                                if (rawListName.isEmpty()) Text("Nome da playlist", style = Theme.font(15f, color = Theme.tertiary))
                                BasicTextField(
                                    rawListName, { rawListName = it }, singleLine = true,
                                    textStyle = Theme.font(15f, color = Theme.text), cursorBrush = SolidColor(Theme.rose),
                                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Next),
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                            Box(Modifier.fillMaxWidth().height(140.dp).glass(RoundedCornerShape(18.dp)).padding(12.dp)) {
                                if (rawListText.isEmpty()) Text("Uma música por linha:\nArtista - Música\nOutro Artista - Outra Música", style = Theme.font(13.5f, color = Theme.tertiary))
                                BasicTextField(
                                    rawListText, { rawListText = it },
                                    textStyle = Theme.font(14.5f, color = Theme.text), cursorBrush = SolidColor(Theme.rose),
                                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default),
                                    modifier = Modifier.fillMaxSize().onFocusChanged { textFocused = it.isFocused },
                                )
                                if (textFocused) KeyboardOkButton(Modifier.align(Alignment.BottomEnd))
                            }
                            GlassButton("Criar playlist da lista", "music.note.list", height = 48.dp) {
                                closeKeyboard()
                                val t = rawListText.trim()
                                val n = rawListName.trim()
                                if (t.isNotEmpty()) {
                                    scope.launch {
                                        coordinator.run("Lista") {
                                            val res = ImportService.importFromText(t, n)
                                            if (res.tracks.isEmpty()) throw ImportException("Cole pelo menos uma música na lista.")
                                            listOf(res)
                                        }
                                        rawListText = ""; rawListName = ""; showList = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
