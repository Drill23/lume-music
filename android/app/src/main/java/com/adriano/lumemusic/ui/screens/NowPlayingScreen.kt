package com.adriano.lumemusic.ui.screens

import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.audio.PlaybackClock
import com.adriano.lumemusic.data.DownloadManager
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.PlayerSurfaceTab
import com.adriano.lumemusic.data.RepeatMode
import com.adriano.lumemusic.data.SleepTimerOption
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlin.math.abs

private val tabs = listOf(PlayerSurfaceTab.ARTWORK, PlayerSurfaceTab.VINYL, PlayerSurfaceTab.CASSETTE, PlayerSurfaceTab.WAVES, PlayerSurfaceTab.LYRICS)

@Composable
fun NowPlayingScreen() {
    val track = AudioPlayer.currentTrack ?: run { AppModel.showPlayer = false; return }
    val pal = AudioPlayer.palette
    val art = AudioPlayer.currentArtwork.ifEmpty { track.artworkURL }
    var dragY by remember { mutableFloatStateOf(0f) }
    val q = pal.quadrants
    val c0 by animateColorAsState(q[0], tween(800), label = "q0")
    val c1 by animateColorAsState(q[1], tween(800), label = "q1")
    val c2 by animateColorAsState(q[2], tween(800), label = "q2")
    val c3 by animateColorAsState(q[3], tween(800), label = "q3")
    val ctx = LocalContext.current

    Box(
        Modifier.fillMaxSize().background(Color(0xFF09090B))
            .graphicsLayer { translationY = maxOf(0f, dragY); alpha = 1f - (maxOf(0f, dragY) / 1800f) }
            .pointerInput(Unit) {
                detectDragGestures(onDragEnd = { if (dragY > 260f) AppModel.showPlayer = false; dragY = 0f }, onDragCancel = { dragY = 0f }) { change, d ->
                    if (abs(d.y) > abs(d.x) || dragY > 0f) { dragY += d.y; change.consume() }
                }
            },
    ) {
        // Fundo ambiente: capa borrada + malha de cores da capa + véu de legibilidade
        if (art.isNotEmpty()) AsyncImage(art, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = 1.8f; scaleY = 1.8f; alpha = 0.55f }.blur(70.dp))
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(c0.copy(0.75f), Color.Transparent), center = androidx.compose.ui.geometry.Offset(0f, 0f), radius = 1400f)))
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(c1.copy(0.65f), Color.Transparent), center = androidx.compose.ui.geometry.Offset(1200f, 100f), radius = 1300f)))
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(c2.copy(0.6f), Color.Transparent), center = androidx.compose.ui.geometry.Offset(0f, 2200f), radius = 1500f)))
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(c3.copy(0.6f), Color.Transparent), center = androidx.compose.ui.geometry.Offset(1200f, 2300f), radius = 1500f)))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(0.10f), Color.Black.copy(0.30f), Color.Black.copy(0.66f)))))

        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 4.dp)) {
            // Barra superior
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                PlayerIcon("chevron.down", "Fechar") { AppModel.showPlayer = false }
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("TOCANDO AGORA", style = Theme.font(11f, FontWeight.SemiBold, Color.White.copy(0.6f), letterSpacing = androidx.compose.ui.unit.TextUnit(1.2f, androidx.compose.ui.unit.TextUnitType.Sp)))
                    Text(AudioPlayer.contextTitle.ifEmpty { track.album.ifEmpty { track.sourceService } }, style = Theme.font(13.5f, FontWeight.SemiBold, Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                PlayerIcon("ellipsis", "Mais opções") { AppModel.showTrackMenu(track, AudioPlayer.queue) }
            }

            // Seletor de palco
            Row(Modifier.padding(horizontal = 12.dp).fillMaxWidth().height(46.dp).glass(RoundedCornerShape(50)).padding(3.dp)) {
                for (t in tabs) {
                    val sel = AppModel.playerTab == t
                    Row(Modifier.weight(1f).fillMaxSize().clip(RoundedCornerShape(50)).background(if (sel) Color.White.copy(0.20f) else Color.Transparent).pressable(0.95f) { Haptics.selection(); AppModel.playerTab = t },
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                        Icon(sf(t.icon), null, tint = Color.White.copy(if (sel) 1f else 0.65f), modifier = Modifier.size(15.dp))
                        Text(t.raw, style = Theme.font(11.5f, FontWeight.SemiBold, Color.White.copy(if (sel) 1f else 0.7f)), modifier = Modifier.padding(start = 3.dp), maxLines = 1)
                    }
                }
            }

            // Palco
            Box(Modifier.weight(1f).fillMaxWidth().padding(vertical = 8.dp)) {
                Crossfade(AppModel.playerTab, animationSpec = tween(260), label = "stage") { tab ->
                    PlayerStages.forTab(tab).Content(track, art, Modifier)
                }
            }

            // Título + curtir
            val fav = track.id in LibraryStore.favoriteIds
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(track.title, style = Theme.font(22f, FontWeight.Bold, Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(track.artist, style = Theme.font(16f, FontWeight.Medium, Color.White.copy(0.72f)), maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.pressable(0.97f) { AppModel.navigateFromPlayer(LumeRoute.Artist(LibraryStore.mainArtist(track.artist), null)) })
                    Text(AudioPlayer.currentBitrateLabel, style = Theme.font(11.5f, color = Color.White.copy(0.45f)))
                }
                PlayerIcon(if (fav) "heart.fill" else "heart", if (fav) "Remover das curtidas" else "Curtir", tint = if (fav) Theme.rose else Color.White) { LibraryStore.toggleFavorite(track) }
            }

            SeekBar(Modifier.padding(horizontal = 24.dp, vertical = 8.dp), pal.vibrant)

            // Controles principais
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                PlayerIcon("shuffle", "Aleatório", tint = if (AudioPlayer.shuffleEnabled) Theme.rose else Color.White.copy(0.8f)) { AudioPlayer.shuffleEnabled = !AudioPlayer.shuffleEnabled }
                PlayerIcon("backward.fill", "Anterior", size = 56.dp, iconSize = 32.dp) { AudioPlayer.previousTrack() }
                Box(Modifier.size(76.dp).pressable(0.92f) { AudioPlayer.togglePlayPause() }.shadow(16.dp, CircleShape, spotColor = pal.vibrant).clip(CircleShape).background(Color.White), contentAlignment = Alignment.Center) {
                    if (AudioPlayer.isLoading) CircularProgressIndicator(Modifier.size(30.dp), color = Color.Black, strokeWidth = 3.dp)
                    else Icon(sf(if (AudioPlayer.isPlaying) "pause.fill" else "play.fill"), if (AudioPlayer.isPlaying) "Pausar" else "Tocar", tint = Color.Black, modifier = Modifier.size(40.dp))
                }
                PlayerIcon("forward.fill", "Próxima", size = 56.dp, iconSize = 32.dp) { AudioPlayer.nextTrack() }
                PlayerIcon(if (AudioPlayer.repeatMode == RepeatMode.ONE) "repeat.1" else "repeat", "Repetir", tint = if (AudioPlayer.repeatMode != RepeatMode.OFF) Theme.rose else Color.White.copy(0.8f)) { AudioPlayer.repeatMode = AudioPlayer.repeatMode.next }
            }

            // Ações secundárias
            Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                PlayerIcon("quote.bubble", "Letra", tint = if (AppModel.playerTab == PlayerSurfaceTab.LYRICS) Theme.rose else Color.White.copy(0.85f)) {
                    AppModel.playerTab = if (AppModel.playerTab == PlayerSurfaceTab.LYRICS) AppModel.playerStyle else PlayerSurfaceTab.LYRICS
                }
                if (AppModel.playerTab == PlayerSurfaceTab.LYRICS && AudioPlayer.lyrics != null)
                    PlayerIcon("translate", "Traduzir", tint = if (AudioPlayer.showTranslation) Theme.rose else Color.White.copy(0.85f)) { AudioPlayer.toggleTranslation() }
                PlayerIcon("paintpalette", "Estilos") { AppModel.tabletSheet = "styles" }
                PlayerIcon("moon.zzz", "Timer de dormir", tint = if (AudioPlayer.sleepTimerOption != SleepTimerOption.OFF) Theme.rose else Color.White.copy(0.85f)) { AppModel.tabletSheet = "sleep" }
                SpeedButton()
                PlayerIcon("slider.vertical.3", "Equalizador") { AppModel.navigateFromPlayer(LumeRoute.Equalizer) }
                val dl = track.id in LibraryStore.downloadedIds
                PlayerIcon(if (dl) "checkmark.circle.fill" else "arrow.down.circle", "Baixar", tint = if (dl) Theme.ok else Color.White.copy(0.85f)) {
                    if (dl) AppModel.showToast("Já está baixada") else { DownloadManager.download(track); AppModel.showToast("Baixando ${track.title}") }
                }
                PlayerIcon("list.bullet", "Fila") { AppModel.showQueue = true }
            }
        }
    }
}

@Composable
private fun SpeedButton() {
    val speeds = listOf(0.75f, 1f, 1.25f, 1.5f, 2f)
    val r = AudioPlayer.playbackRate
    Box(Modifier.size(44.dp).pressable(0.9f) {
        Haptics.selection()
        val i = speeds.indexOfFirst { abs(it - r) < 0.01f }
        AudioPlayer.setRate(speeds[(if (i < 0) 1 else i + 1) % speeds.size])
    }, contentAlignment = Alignment.Center) {
        Text(if (abs(r - 1f) < 0.01f) "1×" else "${"%.2f".format(r).trimEnd('0').trimEnd('.')}×", style = Theme.font(14f, FontWeight.Bold, if (abs(r - 1f) > 0.01f) Theme.rose else Color.White.copy(0.85f)))
    }
}

@Composable
private fun PlayerIcon(name: String, desc: String, tint: Color = Color.White, size: androidx.compose.ui.unit.Dp = 44.dp, iconSize: androidx.compose.ui.unit.Dp = 24.dp, onClick: () -> Unit) {
    Box(Modifier.size(maxOf(size, 44.dp)).pressable(0.88f) { Haptics.light(); onClick() }, contentAlignment = Alignment.Center) {
        Icon(sf(name), desc, tint = tint, modifier = Modifier.size(iconSize))
    }
}

/** Barra de progresso com arrasto (e toque) — só ela recompõe a cada tick do relógio. */
@Composable
private fun SeekBar(modifier: Modifier, accent: Color) {
    var dragging by remember { mutableStateOf(false) }
    var dragFrac by remember { mutableFloatStateOf(0f) }
    var width by remember { mutableFloatStateOf(1f) }
    val dur = PlaybackClock.duration
    val frac = if (dragging) dragFrac else if (dur > 0) (PlaybackClock.currentTime / dur).toFloat().coerceIn(0f, 1f) else 0f
    Column(modifier) {
        Box(
            Modifier.fillMaxWidth().height(32.dp).onSizeChanged { width = it.width.toFloat().coerceAtLeast(1f) }
                .pointerInput(dur) {
                    detectTapGestures { o -> if (dur > 0) AudioPlayer.seek(dur * (o.x / width).coerceIn(0f, 1f)) }
                }
                .pointerInput(dur) {
                    detectDragGestures(
                        onDragStart = { o -> dragging = true; dragFrac = (o.x / width).coerceIn(0f, 1f) },
                        onDragEnd = { if (dur > 0) AudioPlayer.seek(dur * dragFrac); dragging = false },
                        onDragCancel = { dragging = false },
                    ) { change, _ -> dragFrac = (change.position.x / width).coerceIn(0f, 1f); change.consume() }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            val h = if (dragging) 8.dp else 5.dp
            Box(Modifier.fillMaxWidth().height(h).clip(CircleShape).background(Color.White.copy(0.22f)))
            Box(Modifier.fillMaxWidth(frac).height(h).clip(CircleShape).background(Brush.horizontalGradient(listOf(Theme.peach, Theme.rose, accent))))
        }
        Row(Modifier.fillMaxWidth()) {
            Text(Theme.formatTime(if (dragging) dur * dragFrac else PlaybackClock.currentTime), style = Theme.font(12f, FontWeight.Medium, Color.White.copy(0.65f)))
            Spacer(Modifier.weight(1f))
            Text("-" + Theme.formatTime(maxOf(0.0, dur - (if (dragging) dur * dragFrac else PlaybackClock.currentTime))), style = Theme.font(12f, FontWeight.Medium, Color.White.copy(0.65f)))
        }
    }
}

