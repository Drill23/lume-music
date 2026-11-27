package com.adriano.lumemusic.ui

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
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
private fun LumeSheet(onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    ModalBottomSheet(
        onDismissRequest = onDismiss, sheetState = state,
        containerColor = Theme.canvas, shape = RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp),
        contentColor = Theme.text,
    ) {
        Column(Modifier.navigationBarsPadding().imePadding().keyboardDismissing()) { content() }
    }
}

@Composable
private fun SheetHeader(title: String, subtitle: String? = null, trailingLabel: String = "OK", onTrailing: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = Theme.font(20f, FontWeight.Bold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, style = Theme.font(13f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(
            Modifier.height(38.dp).pressable(0.92f) { Haptics.light(); onTrailing() }
                .glass(RoundedCornerShape(50)).padding(horizontal = 16.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(trailingLabel, style = Theme.font(14f, FontWeight.Bold, Theme.text))
        }
    }
}

@Composable
private fun SheetCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().padding(horizontal = 16.dp)
            .clip(RoundedCornerShape(22.dp)).background(Theme.canvasRaised)
            .border(0.6.dp, Theme.hairline, RoundedCornerShape(22.dp)),
        content = content,
    )
}

@Composable
private fun SheetDivider() {
    HorizontalDivider(Modifier.padding(start = 52.dp, end = 16.dp), thickness = 0.5.dp, color = Theme.hairline)
}

@Composable
private fun MenuRow(icon: String, label: String, danger: Boolean = false, onClick: () -> Unit) {
    val tint = if (danger) Theme.danger else Theme.accent
    val fg = if (danger) Theme.danger else Theme.text
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).pressable(0.985f) { Haptics.light(); onClick() }.padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(sf(icon), null, tint = tint, modifier = Modifier.size(21.dp))
        Text(label, style = Theme.font(15.5f, FontWeight.Medium, fg), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
    }
}

@Composable
fun TrackMenuSheet(track: Track, queue: List<Track>?, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    val fav = track.id in LibraryStore.favoriteIds
    val downloaded = track.id in LibraryStore.downloadedIds
    LumeSheet(onDismiss) {
        SheetHeader("Opções", onTrailing = onDismiss)
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Cartão principal com a faixa + ações principais (idêntico ao iOS)
            SheetCard {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    TrackArtwork(track, Modifier.size(50.dp).border(0.5.dp, Theme.hairline, RoundedCornerShape(10.dp)), 10.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(track.title, style = Theme.font(16f, FontWeight.SemiBold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(track.artist, style = Theme.font(13.5f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = Theme.hairline)
                MenuRow("text.badge.plus", "Adicionar a uma playlist") { onDismiss(); AppModel.playlistPickerTrack = track }
                SheetDivider()
                MenuRow("music.mic", "Ver artista") { onDismiss(); AppModel.showPlayer = false; AppModel.openArtist(track.artist) }
                SheetDivider()
                MenuRow("dot.radiowaves.left.and.right", "Iniciar rádio desta música") { AudioPlayer.startRadio(track); onDismiss() }
                SheetDivider()
                MenuRow(if (fav) "heart.slash" else "heart", if (fav) "Remover das curtidas" else "Curtir") { LibraryStore.toggleFavorite(track); onDismiss() }
                SheetDivider()
                MenuRow("square.and.arrow.up", "Compartilhar música") {
                    val share = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, "Ouvindo ${track.title} — ${track.artist} no Lume Music\nhttps://lume-music-enq.pages.dev/")
                    }
                    runCatching { ctx.startActivity(Intent.createChooser(share, "Compartilhar música")) }
                    onDismiss()
                }
            }

            // Fila e download
            SheetCard {
                MenuRow("play.fill", "Tocar agora") { AudioPlayer.play(track, queue); onDismiss() }
                SheetDivider()
                MenuRow("text.line.first.and.arrowtriangle.forward", "Tocar a seguir") { AudioPlayer.playNextInQueue(track); AppModel.showToast("Toca a seguir: ${track.title}"); onDismiss() }
                SheetDivider()
                MenuRow("text.line.last.and.arrowtriangle.forward", "Adicionar à fila") { AudioPlayer.addToQueue(track); AppModel.showToast("Adicionada à fila"); onDismiss() }
                SheetDivider()
                when {
                    downloaded -> MenuRow("trash", "Remover download", danger = true) { LibraryStore.removeDownload(track.id); onDismiss() }
                    DownloadManager.isDownloading(track.id) -> MenuRow("xmark.circle", "Cancelar download") { DownloadManager.cancel(track.id); onDismiss() }
                    else -> MenuRow("arrow.down.circle", "Baixar para ouvir offline") { DownloadManager.download(track); onDismiss() }
                }
            }

            // Atalho de estilo do Tocando agora (igual ao iOS)
            SheetCard {
                MenuRow("paintpalette.fill", "Estilo do Tocando agora") { onDismiss(); AppModel.tabletSheet = "styles" }
            }
        }
    }
}

@Composable
fun AddToPlaylistSheet(track: Track, onDismiss: () -> Unit) {
    var creating by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    LumeSheet(onDismiss) {
        val closeKeyboard = rememberKeyboardCloser()
        SheetHeader("Adicionar à playlist", "${track.title} · ${track.artist}", onTrailing = onDismiss)
        SheetCard(Modifier.padding(bottom = 12.dp)) {
            if (creating) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.weight(1f).height(46.dp).glass(RoundedCornerShape(23.dp)).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
                        if (name.isEmpty()) Text("Nome da playlist", style = Theme.font(15f, color = Theme.tertiary))
                        BasicTextField(name, { name = it }, singleLine = true, textStyle = Theme.font(15.5f, color = Theme.text), cursorBrush = SolidColor(Theme.rose),
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { closeKeyboard() }),
                            modifier = Modifier.fillMaxWidth())
                    }
                    PrismButton("Criar", modifier = Modifier.width(92.dp), height = 46.dp, fontSize = 14.5f) {
                        if (name.isNotBlank()) {
                            val pl = LibraryStore.createPlaylist(name.trim(), tracks = listOf(track))
                            AppModel.showToast("Adicionada a “${pl.name}”"); onDismiss()
                        }
                    }
                }
            } else {
                MenuRow("plus", "Nova playlist") { creating = true }
            }
        }
        if (LibraryStore.playlists.isEmpty()) {
            EmptyState("music.note.list", "Nenhuma playlist ainda", "Toque em Nova playlist acima para criar a primeira.")
        } else {
            SheetCard(Modifier.padding(bottom = 16.dp)) {
                LazyColumn(Modifier.heightIn(max = 320.dp)) {
                    itemsIndexed(LibraryStore.playlists, key = { _, p -> p.id }) { idx, pl ->
                        if (idx > 0) SheetDivider()
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 62.dp).pressable(0.985f) {
                                LibraryStore.addTrack(track, pl.id)
                                AppModel.showToast("Adicionada a “${pl.name}”")
                                onDismiss()
                            }.padding(horizontal = 16.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            ArtworkImage(pl.artworkURL, Modifier.size(44.dp).border(0.5.dp, Theme.hairline, RoundedCornerShape(10.dp)), 10.dp, icon = "music.note.list")
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                                Text(pl.name, style = Theme.font(15.5f, FontWeight.Medium, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text("${pl.trackIds.size} músicas", style = Theme.font(12.5f, color = Theme.secondary))
                            }
                            if (track.id in pl.trackIds) Icon(sf("checkmark.circle.fill"), null, tint = Theme.ok, modifier = Modifier.size(21.dp))
                        }
                    }
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
        SheetHeader(
            "Fila",
            if (AudioPlayer.contextTitle.isNotEmpty()) AudioPlayer.contextTitle else "${q.size} músicas",
            trailingLabel = if (q.size > cur + 1) "Limpar" else "OK",
            onTrailing = {
                if (q.size > cur + 1) AudioPlayer.clearUpcoming() else onDismiss()
            },
        )
        HRow(contentPadding = PaddingValues(horizontal = 16.dp), spacing = 8.dp) {
            item { PrismChip("Aleatório", AudioPlayer.shuffleEnabled, "shuffle") { AudioPlayer.shuffleEnabled = !AudioPlayer.shuffleEnabled } }
            item {
                PrismChip(
                    when (AudioPlayer.repeatMode.raw) { "one" -> "Repetir 1" else -> "Repetir" },
                    AudioPlayer.repeatMode.raw != "off",
                    AudioPlayer.repeatMode.let { if (it.raw == "one") "repeat.1" else "repeat" },
                ) { AudioPlayer.repeatMode = AudioPlayer.repeatMode.next }
            }
            item { PrismChip("Rádio", AudioPlayer.autoplayRadio, "infinity") { AudioPlayer.autoplayRadio = !AudioPlayer.autoplayRadio } }
        }
        Spacer(Modifier.height(8.dp))
        SheetCard(Modifier.padding(bottom = 16.dp)) {
            if (q.isEmpty()) {
                EmptyState("list.bullet", "Fila vazia", "Escolha uma música para começar.")
            } else {
                LazyColumn(Modifier.heightIn(max = 420.dp)) {
                    itemsIndexed(q, key = { i, t -> "${t.id}#$i" }) { i, t ->
                        if (i > 0) SheetDivider()
                        val active = i == cur
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 60.dp).pressable(0.99f) { AudioPlayer.jumpToQueueIndex(i) }
                                .background(if (active) Theme.fill else Color.Transparent).padding(start = 14.dp, end = 6.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            TrackArtwork(t, Modifier.size(44.dp).border(0.5.dp, Theme.hairline, RoundedCornerShape(8.dp)), 8.dp)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                                Text(t.title, style = Theme.font(15f, if (active) FontWeight.SemiBold else FontWeight.Medium, if (active) Theme.accent else Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(t.artist, style = Theme.font(12.5f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            if (!active) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(Modifier.size(width = 34.dp, height = 44.dp).alpha(if (i > 0) 1f else 0.3f).pressable(0.85f, enabled = i > 0) { AudioPlayer.moveQueue(i, i - 1) }, contentAlignment = Alignment.Center) {
                                        Icon(sf("chevron.up"), "Subir", tint = Theme.secondary, modifier = Modifier.size(19.dp))
                                    }
                                    Box(Modifier.size(width = 34.dp, height = 44.dp).alpha(if (i < q.lastIndex) 1f else 0.3f).pressable(0.85f, enabled = i < q.lastIndex) { AudioPlayer.moveQueue(i, i + 1) }, contentAlignment = Alignment.Center) {
                                        Icon(sf("chevron.down"), "Descer", tint = Theme.secondary, modifier = Modifier.size(19.dp))
                                    }
                                    Box(Modifier.size(width = 34.dp, height = 44.dp).pressable(0.85f) { AudioPlayer.removeFromQueue(i) }, contentAlignment = Alignment.Center) {
                                        Icon(sf("xmark"), "Remover", tint = Theme.secondary, modifier = Modifier.size(17.dp))
                                    }
                                }
                            } else {
                                Icon(sf("waveform"), null, tint = Theme.accent, modifier = Modifier.padding(end = 10.dp).size(20.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SleepTimerSheet(onDismiss: () -> Unit) {
    LumeSheet(onDismiss) {
        SheetHeader("Timer de dormir", "Pausa a música automaticamente", onTrailing = onDismiss)
        SheetCard(Modifier.padding(bottom = 16.dp)) {
            SleepTimerOption.entries.forEachIndexed { idx, o ->
                if (idx > 0) HorizontalDivider(Modifier.padding(horizontal = 16.dp), thickness = 0.5.dp, color = Theme.hairline)
                val sel = AudioPlayer.sleepTimerOption == o
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).pressable(0.985f) { Haptics.selection(); AudioPlayer.setSleepTimer(o); onDismiss() }.padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(o.label, style = Theme.font(15.5f, if (sel) FontWeight.SemiBold else FontWeight.Medium, if (sel) Theme.accent else Theme.text), modifier = Modifier.weight(1f))
                    if (sel) Icon(sf("checkmark"), null, tint = Theme.accent, modifier = Modifier.size(20.dp))
                }
            }
        }
    }
}

/** Painel de Estilos do Tocando agora: palco, ondas, toca-discos, disco, K7. */
@Composable
fun StylesSheet(onDismiss: () -> Unit) {
    val s = LibraryStore
    @Composable fun <T> StyleRow(title: String, items: List<Pair<String, T>>, selected: T, onSelect: (T) -> Unit) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title.uppercase(), style = Theme.font(11.5f, FontWeight.SemiBold, Theme.secondary), modifier = Modifier.padding(start = 20.dp, top = 6.dp))
            androidx.compose.foundation.lazy.LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                itemsIndexed(items) { _, (label, v) -> PrismChip(label, v == selected) { onSelect(v) } }
            }
        }
    }
    LumeSheet(onDismiss) {
        SheetHeader("Estilos do Tocando agora", "Personalize capa, vinil, K7 e ondas", onTrailing = onDismiss)
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 18.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            StyleRow("Palco", listOf(com.adriano.lumemusic.data.PlayerSurfaceTab.ARTWORK, com.adriano.lumemusic.data.PlayerSurfaceTab.VINYL, com.adriano.lumemusic.data.PlayerSurfaceTab.CASSETTE, com.adriano.lumemusic.data.PlayerSurfaceTab.WAVES).map { it.raw to it }, AppModel.playerStyle) { AppModel.playerStyle = it; AppModel.playerTab = it }
            StyleRow("Estilo das ondas", com.adriano.lumemusic.data.VisualizerStyle.entries.map { it.title to it }, s.visualizerStyle) { s.visualizerStyle = it }
            StyleRow("Acabamento do toca-discos", com.adriano.lumemusic.data.TurntableFinish.entries.map { it.raw to it }, s.turntableFinish) { s.turntableFinish = it }
            StyleRow("Edição do disco", com.adriano.lumemusic.data.VinylEdition.entries.map { it.raw to it }, s.vinylEdition) { s.vinylEdition = it }
            StyleRow("Estilo da fita K7", com.adriano.lumemusic.data.CassetteStyle.entries.map { it.raw to it }, s.cassetteStyle) { s.cassetteStyle = it }
        }
    }
}
