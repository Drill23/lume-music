package com.adriano.lumemusic.ui.screens

import com.adriano.lumemusic.ui.Chrome
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.verticalScroll
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.audio.PlaybackClock
import com.adriano.lumemusic.data.DownloadManager
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.PlayerSurfaceTab
import com.adriano.lumemusic.data.RepeatMode
import com.adriano.lumemusic.data.SleepTimerOption
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.GlassIconButton
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.TrackArtwork
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.stage.StageSwitcher
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlin.math.abs

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
    val mode = AppModel.playerTab
    val lyrics = mode == PlayerSurfaceTab.LYRICS

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
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(c0.copy(0.75f), Color.Transparent), center = Offset(0f, 0f), radius = 1400f)))
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(c1.copy(0.65f), Color.Transparent), center = Offset(1200f, 100f), radius = 1300f)))
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(c2.copy(0.6f), Color.Transparent), center = Offset(0f, 2200f), radius = 1500f)))
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(c3.copy(0.6f), Color.Transparent), center = Offset(1200f, 2300f), radius = 1500f)))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(0.10f), Color.Black.copy(0.30f), Color.Black.copy(0.66f)))))

        // Telas baixas (360×640, fonte grande): a tela inteira rola e o palco ganha altura fixa, para nenhum controle ficar escondido.
        androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
        val compact = maxHeight < 700.dp
        Column(Modifier.fillMaxSize().then(if (compact) Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState()) else Modifier)) {
            // Barra superior (alça + fechar / "TOCANDO AGORA" / opções)
            Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(40.dp, 5.dp).clip(CircleShape).background(Color.White.copy(0.28f)))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    GlassIconButton("chevron.down", 40.dp, foreground = Color.White, desc = "Fechar") { AppModel.showPlayer = false }
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Text("TOCANDO AGORA", style = Theme.font(10.5f, FontWeight.SemiBold, Color.White.copy(0.62f), letterSpacing = TextUnit(1.2f, TextUnitType.Sp)))
                        Text(AudioPlayer.contextTitle.ifEmpty { "Lume Music" }, style = Theme.font(13f, FontWeight.SemiBold, Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    GlassIconButton("ellipsis", 40.dp, foreground = Color.White, desc = "Mais opções") { AppModel.showTrackMenu(track, AudioPlayer.queue) }
                }
            }

            // Seletor de palco (pílula de vidro com indicador deslizante)
            StageSwitcher(mode, { t -> if (t != PlayerSurfaceTab.LYRICS) AppModel.playerStyle = t; AppModel.playerTab = t }, Modifier.padding(top = 6.dp, bottom = 4.dp))

            // Palco
            Box((if (compact) Modifier.height(if (lyrics) 330.dp else 290.dp) else Modifier.weight(1f)).fillMaxWidth()) {
                Crossfade(AppModel.playerTab, animationSpec = tween(260), label = "stage") { tab ->
                    PlayerStages.forTab(tab).Content(track, art, Modifier)
                }
            }

            // Controles
            Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(if (lyrics) 14.dp else 20.dp)) {
                Metadata(track, lyrics)
                SeekBar(Modifier.fillMaxWidth())
                Transport(lyrics)
                if (!lyrics) VolumeRow()
                BottomRow()
            }
        }
        }
    }
}

@Composable
private fun Metadata(track: Track, lyrics: Boolean) {
    val fav = track.id in LibraryStore.favoriteIds
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (lyrics) TrackArtwork(track, Modifier.size(48.dp), 8.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(track.title, style = Theme.font(if (lyrics) 17f else 22f, FontWeight.Bold, Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(track.artist, style = Theme.font(if (lyrics) 14f else 17f, color = Color.White.copy(0.62f)), maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.pressable(0.97f) { AppModel.navigateFromPlayer(LumeRoute.Artist(LibraryStore.mainArtist(track.artist), null)) })
        }
        // baixar
        val downloaded = track.id in LibraryStore.downloadedIds
        val p = DownloadManager.progressById[track.id]
        Box(Modifier.size(Chrome.minTouch).pressable(0.88f) {
            if (downloaded) { Haptics.selection(); AppModel.showToast("Esta música já está salva no celular") }
            else if (DownloadManager.isDownloading(track.id)) DownloadManager.cancel(track.id)
            else { Haptics.light(); DownloadManager.download(track) }
        }, contentAlignment = Alignment.Center) {
            Box(Modifier.size(40.dp).glass(CircleShape), contentAlignment = Alignment.Center) {
                if (p != null) {
                    Canvas(Modifier.size(20.dp)) {
                        val sw = 2.4.dp.toPx()
                        drawCircle(Color.White.copy(0.15f), size.minDimension / 2 - sw / 2, style = Stroke(sw))
                        drawArc(Color.White, -90f, 360f * p.toFloat(), false, topLeft = Offset(sw / 2, sw / 2), size = Size(size.width - sw, size.height - sw), style = Stroke(sw, cap = StrokeCap.Round))
                    }
                } else Icon(sf(if (downloaded) "arrow.down.circle.fill" else "arrow.down"), "Baixar", tint = Color.White, modifier = Modifier.size(20.dp))
            }
        }
        // curtir
        Box(Modifier.size(Chrome.minTouch).pressable(0.88f) { LibraryStore.toggleFavorite(track) }, contentAlignment = Alignment.Center) {
            Box(Modifier.size(40.dp).glass(CircleShape), contentAlignment = Alignment.Center) {
                Icon(sf(if (fav) "heart.fill" else "heart"), if (fav) "Remover das curtidas" else "Curtir", tint = if (fav) Theme.rose else Color.White, modifier = Modifier.size(20.dp))
            }
        }
    }
}

@Composable
private fun Transport(lyrics: Boolean) {
    val playSize = if (lyrics) 70.dp else 84.dp
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        TransportIcon("shuffle", "Aleatório", 48.dp, 20.dp, if (AudioPlayer.shuffleEnabled) Theme.rose else Color.White.copy(0.62f)) { Haptics.selection(); AudioPlayer.shuffleEnabled = !AudioPlayer.shuffleEnabled }
        TransportIcon("backward.fill", "Anterior", 60.dp, 34.dp, Color.White, 0.82f) { AudioPlayer.previousTrack() }
        Box(Modifier.size(playSize).pressable(0.9f) { AudioPlayer.togglePlayPause() }.glass(CircleShape), contentAlignment = Alignment.Center) {
            if (AudioPlayer.isLoading) CircularProgressIndicator(Modifier.size(32.dp), color = Color.White, strokeWidth = 3.dp)
            else Icon(sf(if (AudioPlayer.isPlaying) "pause.fill" else "play.fill"), if (AudioPlayer.isPlaying) "Pausar" else "Tocar", tint = Color.White, modifier = Modifier.size(40.dp))
        }
        TransportIcon("forward.fill", "Próxima", 60.dp, 34.dp, Color.White, 0.82f) { AudioPlayer.nextTrack() }
        TransportIcon(if (AudioPlayer.repeatMode == RepeatMode.ONE) "repeat.1" else "repeat", "Repetir", 48.dp, 20.dp, if (AudioPlayer.repeatMode != RepeatMode.OFF) Theme.rose else Color.White.copy(0.62f)) { Haptics.selection(); AudioPlayer.repeatMode = AudioPlayer.repeatMode.next }
    }
}

@Composable
private fun TransportIcon(name: String, desc: String, box: Dp, icon: Dp, tint: Color, press: Float = 0.94f, onClick: () -> Unit) {
    Box(Modifier.size(box).pressable(press) { onClick() }, contentAlignment = Alignment.Center) { Icon(sf(name), desc, tint = tint, modifier = Modifier.size(icon)) }
}

/** Fileira de baixo: Letra, timer, velocidade, equalizador e fila (o AirPlay do iOS não existe no Android). */
@Composable
private fun BottomRow() {
    val lyricsOn = AppModel.playerTab == PlayerSurfaceTab.LYRICS
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        BottomIcon("quote.bubble", "Letra", if (lyricsOn) Theme.rose else Color.White.copy(0.62f)) {
            Haptics.selection(); AppModel.playerTab = if (lyricsOn) AppModel.playerStyle else PlayerSurfaceTab.LYRICS
        }
        if (lyricsOn && AudioPlayer.lyrics != null) BottomIcon("translate", "Traduzir", if (AudioPlayer.showTranslation) Theme.rose else Color.White.copy(0.62f)) { AudioPlayer.toggleTranslation() }
        Row(Modifier.height(Chrome.minTouch).widthIn(min = 48.dp).pressable(0.9f) { Haptics.light(); AppModel.tabletSheet = "sleep" }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            val on = AudioPlayer.sleepTimerOption != SleepTimerOption.OFF
            Icon(sf("moon.zzz"), "Timer de dormir", tint = if (on) Theme.rose else Color.White.copy(0.62f), modifier = Modifier.size(22.dp))
            if (AudioPlayer.sleepRemainingSeconds > 0) Text(Theme.formatTime(AudioPlayer.sleepRemainingSeconds.toDouble()), style = Theme.font(12.5f, FontWeight.SemiBold, Color.White.copy(0.62f)))
        }
        SpeedButton()
        BottomIcon("slider.vertical.3", "Equalizador", Color.White.copy(0.62f)) { AppModel.navigateFromPlayer(LumeRoute.Equalizer) }
        BottomIcon("list.bullet", "Fila", Color.White.copy(0.62f)) { Haptics.light(); AppModel.showQueue = true }
    }
}

@Composable
private fun BottomIcon(name: String, desc: String, tint: Color, onClick: () -> Unit) {
    Box(Modifier.size(48.dp, 48.dp).pressable(0.9f) { onClick() }, contentAlignment = Alignment.Center) { Icon(sf(name), desc, tint = tint, modifier = Modifier.size(22.dp)) }
}

@Composable
private fun SpeedButton() {
    val speeds = listOf(0.75f, 1f, 1.25f, 1.5f, 2f)
    val r = AudioPlayer.playbackRate
    Box(Modifier.size(48.dp, 48.dp).pressable(0.9f) {
        Haptics.selection()
        val i = speeds.indexOfFirst { abs(it - r) < 0.01f }
        AudioPlayer.setRate(speeds[(if (i < 0) 1 else i + 1) % speeds.size])
    }, contentAlignment = Alignment.Center) {
        Text(if (abs(r - 1f) < 0.01f) "1×" else "${"%.2f".format(r).trimEnd('0').trimEnd('.')}×", style = Theme.font(14f, FontWeight.Bold, if (abs(r - 1f) > 0.01f) Theme.rose else Color.White.copy(0.62f)))
    }
}

/** Barra de progresso (estilo Apple Music): 6 dp, vira 12 dp ao arrastar; só ela recompõe a cada tick do relógio. */
@Composable
private fun SeekBar(modifier: Modifier) {
    var dragging by remember { mutableStateOf(false) }
    var dragFrac by remember { mutableFloatStateOf(0f) }
    var width by remember { mutableFloatStateOf(1f) }
    val dur = PlaybackClock.duration
    val frac = if (dragging) dragFrac else if (dur > 0) (PlaybackClock.currentTime / dur).toFloat().coerceIn(0f, 1f) else 0f
    val h by animateDpAsState(if (dragging) 12.dp else 6.dp, spring(0.8f, 600f), label = "seekH")
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(
            Modifier.fillMaxWidth().height(22.dp).onSizeChanged { width = it.width.toFloat().coerceAtLeast(1f) }
                .pointerInput(dur) { detectTapGestures { o -> if (dur > 0) AudioPlayer.seek(dur * (o.x / width).coerceIn(0f, 1f)) } }
                .pointerInput(dur) {
                    detectDragGestures(
                        onDragStart = { o -> Haptics.light(); dragging = true; dragFrac = (o.x / width).coerceIn(0f, 1f) },
                        onDragEnd = { if (dur > 0) AudioPlayer.seek(dur * dragFrac); dragging = false },
                        onDragCancel = { dragging = false },
                    ) { change, _ -> dragFrac = (change.position.x / width).coerceIn(0f, 1f); change.consume() }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            Box(Modifier.fillMaxWidth().height(h).clip(CircleShape).background(Color.White.copy(0.18f)))
            Box(Modifier.fillMaxWidth(frac).height(h).clip(CircleShape).background(Color.White.copy(if (dragging) 1f else 0.82f)))
        }
        val cur = if (dragging) dur * dragFrac else PlaybackClock.currentTime
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(Theme.formatTime(cur), style = Theme.font(12f, FontWeight.Medium, Color.White.copy(0.62f)))
            Spacer(Modifier.weight(1f))
            Text(AudioPlayer.currentBitrateLabel, style = Theme.font(10.5f, FontWeight.Bold, Color.White.copy(0.62f)),
                modifier = Modifier.border(0.8.dp, Color.White.copy(0.4f), CircleShape).padding(horizontal = 7.dp, vertical = 2.dp))
            Spacer(Modifier.weight(1f))
            Text("-" + Theme.formatTime(maxOf(0.0, dur - cur)), style = Theme.font(12f, FontWeight.Medium, Color.White.copy(0.62f)))
        }
    }
}

/** Volume do sistema (STREAM_MUSIC), com a mesma linha de 6 dp do iOS. */
@Composable
private fun VolumeRow() {
    val ctx = LocalContext.current
    val am = remember { ctx.getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager }
    val maxV = remember { am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC).coerceAtLeast(1) }
    var level by remember { mutableFloatStateOf(am.getStreamVolume(android.media.AudioManager.STREAM_MUSIC) / maxV.toFloat()) }
    var dragging by remember { mutableStateOf(false) }
    var width by remember { mutableFloatStateOf(1f) }
    LaunchedEffect(Unit) {
        while (true) {
            if (!dragging) level = am.getStreamVolume(android.media.AudioManager.STREAM_MUSIC) / maxV.toFloat()
            kotlinx.coroutines.delay(600)
        }
    }
    fun set(x: Float) {
        val v = (x / width).coerceIn(0f, 1f); level = v
        am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, (v * maxV).toInt(), 0)
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(sf("speaker.fill"), null, tint = Color.White.copy(0.62f), modifier = Modifier.size(14.dp))
        Box(
            Modifier.weight(1f).height(22.dp).onSizeChanged { width = it.width.toFloat().coerceAtLeast(1f) }
                .pointerInput(Unit) { detectTapGestures { set(it.x) } }
                .pointerInput(Unit) { detectDragGestures(onDragStart = { dragging = true; set(it.x) }, onDragEnd = { dragging = false }, onDragCancel = { dragging = false }) { c, _ -> set(c.position.x); c.consume() } },
            contentAlignment = Alignment.CenterStart,
        ) {
            Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(Color.White.copy(0.18f)))
            Box(Modifier.fillMaxWidth(level).height(6.dp).clip(CircleShape).background(Color.White.copy(0.75f)))
        }
        Icon(sf("speaker.wave.3.fill"), null, tint = Color.White.copy(0.62f), modifier = Modifier.size(15.dp))
    }
}
