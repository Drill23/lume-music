package com.adriano.lumemusic.ui

import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.DownloadManager
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.SleepTimerOption
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf

@Composable
fun SheetsHost() {
    AppModel.menuTrack?.let { t -> TrackMenuSheet(t, AppModel.menuQueue) { AppModel.menuTrack = null } }
    AppModel.playlistPickerTrack?.let { t -> AddToPlaylistSheet(t) { AppModel.playlistPickerTrack = null } }
    if (AppModel.showQueue) QueueSheet { AppModel.showQueue = false }
    if (AppModel.tabletSheet == "sleep") SleepTimerSheet { AppModel.tabletSheet = null }
    if (AppModel.tabletSheet == "styles") StylesSheet { AppModel.tabletSheet = null }
}

@Composable
private fun LumeSheet(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    ModalBottomSheet(
        onDismissRequest = onDismiss, sheetState = state,
        containerColor = Theme.canvasRaised, shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        contentColor = Theme.text,
    ) { Column(Modifier.navigationBarsPadding().imePadding().keyboardDismissing()) { content() } }
}

@Composable
private fun MenuRow(icon: String, label: String, danger: Boolean = false, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).pressable(0.99f) { Haptics.light(); onClick() }.padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(sf(icon), null, tint = if (danger) Theme.danger else Theme.text, modifier = Modifier.size(22.dp))
        Text(label, style = Theme.font(16f, color = if (danger) Theme.danger else Theme.text))
    }
}

@Composable
fun TrackMenuSheet(track: Track, queue: List<Track>?, onDismiss: () -> Unit) {
    val fav = track.id in LibraryStore.favoriteIds
    val downloaded = track.id in LibraryStore.downloadedIds
    LumeSheet(onDismiss) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TrackArtwork(track, Modifier.size(52.dp), 10.dp)
            Column(Modifier.weight(1f)) {
                Text(track.title, style = Theme.font(16f, FontWeight.SemiBold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(track.artist, style = Theme.font(13.5f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        HorizontalDivider(color = Theme.hairline)
        MenuRow("play.fill", "Tocar agora") { AudioPlayer.play(track, queue); onDismiss() }
        MenuRow("text.line.first.and.arrowtriangle.forward", "Tocar a seguir") { AudioPlayer.playNextInQueue(track); AppModel.showToast("Toca a seguir: ${track.title}"); onDismiss() }
        MenuRow("text.line.last.and.arrowtriangle.forward", "Adicionar à fila") { AudioPlayer.addToQueue(track); AppModel.showToast("Adicionada à fila"); onDismiss() }
        MenuRow("dot.radiowaves.left.and.right", "Iniciar rádio") { AudioPlayer.startRadio(track); onDismiss() }
        HorizontalDivider(color = Theme.hairline)
        MenuRow(if (fav) "heart.slash" else "heart", if (fav) "Remover das curtidas" else "Curtir") { LibraryStore.toggleFavorite(track); onDismiss() }
        MenuRow("text.badge.plus", "Adicionar a uma playlist") { onDismiss(); AppModel.playlistPickerTrack = track }
        when {
            downloaded -> MenuRow("trash", "Remover download", danger = true) { LibraryStore.removeDownload(track.id); onDismiss() }
            DownloadManager.isDownloading(track.id) -> MenuRow("xmark.circle", "Cancelar download") { DownloadManager.cancel(track.id); onDismiss() }
            else -> MenuRow("arrow.down.circle", "Baixar") { DownloadManager.download(track); onDismiss() }
        }
        HorizontalDivider(color = Theme.hairline)
        MenuRow("music.mic", "Ver artista") { onDismiss(); AppModel.showPlayer = false; AppModel.openArtist(track.artist) }
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
fun AddToPlaylistSheet(track: Track, onDismiss: () -> Unit) {
    var creating by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    LumeSheet(onDismiss) {
        val closeKeyboard = rememberKeyboardCloser()
        Text("Adicionar a uma playlist", style = Theme.font(19f, FontWeight.Bold, Theme.text), modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
        if (creating) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f).height(48.dp).glass(RoundedCornerShape(24.dp)).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
                    if (name.isEmpty()) Text("Nome da playlist", style = Theme.font(16f, color = Theme.tertiary))
                    BasicTextField(name, { name = it }, singleLine = true, textStyle = Theme.font(16f, color = Theme.text), cursorBrush = SolidColor(Theme.rose),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { closeKeyboard() }),
                        modifier = Modifier.fillMaxWidth())
                }
                PrismButton("Criar", modifier = Modifier.width(96.dp), height = 48.dp) {
                    if (name.isNotBlank()) {
                        val pl = LibraryStore.createPlaylist(name.trim(), tracks = listOf(track))
                        AppModel.showToast("Adicionada a “${pl.name}”"); onDismiss()
                    }
                }
            }
        } else MenuRow("plus", "Nova playlist") { creating = true }
        LazyColumn(Modifier.heightIn(max = 320.dp)) {
            itemsIndexed(LibraryStore.playlists, key = { _, p -> p.id }) { _, pl ->
                Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).pressable(0.99f) { LibraryStore.addTrack(track, pl.id); AppModel.showToast("Adicionada a “${pl.name}”"); onDismiss() }.padding(horizontal = 24.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ArtworkImage(pl.artworkURL, Modifier.size(44.dp), 10.dp, icon = "music.note.list")
                    Column(Modifier.weight(1f)) {
                        Text(pl.name, style = Theme.font(16f, color = Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("${pl.trackIds.size} músicas", style = Theme.font(13f, color = Theme.secondary))
                    }
                    if (track.id in pl.trackIds) Icon(sf("checkmark.circle.fill"), null, tint = Theme.ok, modifier = Modifier.size(22.dp))
                }
            }
        }
    }
}

@Composable
fun QueueSheet(onDismiss: () -> Unit) {
    val q = AudioPlayer.queue
    val cur = AudioPlayer.currentIndex
    LumeSheet(onDismiss) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Fila", style = Theme.font(21f, FontWeight.Bold, Theme.text))
                Text(if (AudioPlayer.contextTitle.isNotEmpty()) AudioPlayer.contextTitle else "${q.size} músicas", style = Theme.font(13f, color = Theme.secondary), maxLines = 1)
            }
            Box(Modifier.height(Chrome.minTouch).pressable(0.95f) { AudioPlayer.clearUpcoming() }.padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                Text("Limpar a seguir", style = Theme.font(14f, FontWeight.Medium, Theme.accent))
            }
        }
        Row(Modifier.padding(horizontal = 24.dp).padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PrismChip("Aleatório", AudioPlayer.shuffleEnabled, "shuffle") { AudioPlayer.shuffleEnabled = !AudioPlayer.shuffleEnabled }
            PrismChip(when (AudioPlayer.repeatMode.raw) { "one" -> "Repetir 1" else -> "Repetir" }, AudioPlayer.repeatMode.raw != "off", AudioPlayer.repeatMode.let { if (it.raw == "one") "repeat.1" else "repeat" }) { AudioPlayer.repeatMode = AudioPlayer.repeatMode.next }
            PrismChip("Rádio", AudioPlayer.autoplayRadio, "infinity") { AudioPlayer.autoplayRadio = !AudioPlayer.autoplayRadio }
        }
        LazyColumn(Modifier.heightIn(max = 420.dp)) {
            itemsIndexed(q, key = { i, t -> "${t.id}#$i" }) { i, t ->
                val active = i == cur
                Row(Modifier.fillMaxWidth().heightIn(min = 60.dp).pressable(0.99f) { AudioPlayer.jumpToQueueIndex(i) }
                    .background(if (active) Theme.fill else Color.Transparent).padding(start = 24.dp, end = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TrackArtwork(t, Modifier.size(44.dp), 8.dp)
                    Column(Modifier.weight(1f)) {
                        Text(t.title, style = Theme.font(15.5f, color = if (active) Theme.accent else Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(t.artist, style = Theme.font(13f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (!active) {
                        Box(Modifier.size(Chrome.minTouch).pressable(0.85f) { AudioPlayer.moveQueue(i, i - 1) }, contentAlignment = Alignment.Center) { Icon(sf("chevron.up"), "Subir", tint = Theme.secondary, modifier = Modifier.size(22.dp)) }
                        Box(Modifier.size(Chrome.minTouch).pressable(0.85f) { AudioPlayer.moveQueue(i, i + 1) }, contentAlignment = Alignment.Center) { Icon(sf("chevron.down"), "Descer", tint = Theme.secondary, modifier = Modifier.size(22.dp)) }
                        Box(Modifier.size(Chrome.minTouch).pressable(0.85f) { AudioPlayer.removeFromQueue(i) }, contentAlignment = Alignment.Center) { Icon(sf("xmark"), "Remover", tint = Theme.secondary, modifier = Modifier.size(20.dp)) }
                    } else Icon(sf("waveform"), null, tint = Theme.accent, modifier = Modifier.padding(end = 12.dp).size(20.dp))
                }
            }
        }
    }
}

@Composable
fun SleepTimerSheet(onDismiss: () -> Unit) {
    LumeSheet(onDismiss) {
        Text("Timer de dormir", style = Theme.font(19f, FontWeight.Bold, Theme.text), modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
        for (o in SleepTimerOption.entries) {
            val sel = AudioPlayer.sleepTimerOption == o
            Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).pressable(0.99f) { AudioPlayer.setSleepTimer(o); onDismiss() }.padding(horizontal = 24.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(o.label, style = Theme.font(16f, color = if (sel) Theme.accent else Theme.text), modifier = Modifier.weight(1f))
                if (sel) Icon(sf("checkmark"), null, tint = Theme.accent, modifier = Modifier.size(20.dp))
            }
        }
        Spacer(Modifier.height(12.dp))
    }
}


/** Painel de Estilos do Tocando agora: palco, ondas, toca-discos, disco, K7. */
@Composable
fun StylesSheet(onDismiss: () -> Unit) {
    val s = LibraryStore
    @Composable fun <T> StyleRow(title: String, items: List<Pair<String, T>>, selected: T, onSelect: (T) -> Unit) {
        Text(title, style = Theme.font(14f, FontWeight.SemiBold, Theme.secondary), modifier = Modifier.padding(start = 24.dp, top = 10.dp, bottom = 2.dp))
        androidx.compose.foundation.lazy.LazyRow(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            itemsIndexed(items) { _, (label, v) -> PrismChip(label, v == selected) { onSelect(v) } }
        }
    }
    LumeSheet(onDismiss) {
        Text("Estilos", style = Theme.font(21f, FontWeight.Bold, Theme.text), modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
        StyleRow("Palco", listOf(com.adriano.lumemusic.data.PlayerSurfaceTab.ARTWORK, com.adriano.lumemusic.data.PlayerSurfaceTab.VINYL, com.adriano.lumemusic.data.PlayerSurfaceTab.CASSETTE, com.adriano.lumemusic.data.PlayerSurfaceTab.WAVES).map { it.raw to it }, AppModel.playerStyle) { AppModel.playerStyle = it; AppModel.playerTab = it }
        StyleRow("Estilo das ondas", com.adriano.lumemusic.data.VisualizerStyle.entries.map { it.title to it }, s.visualizerStyle) { s.visualizerStyle = it }
        StyleRow("Acabamento do toca-discos", com.adriano.lumemusic.data.TurntableFinish.entries.map { it.raw to it }, s.turntableFinish) { s.turntableFinish = it }
        StyleRow("Edição do disco", com.adriano.lumemusic.data.VinylEdition.entries.map { it.raw to it }, s.vinylEdition) { s.vinylEdition = it }
        StyleRow("Estilo da fita K7", com.adriano.lumemusic.data.CassetteStyle.entries.map { it.raw to it }, s.cassetteStyle) { s.cassetteStyle = it }
        Spacer(Modifier.height(16.dp))
    }
}
