package com.adriano.lumemusic.ui.screens

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.height
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.audio.AudioSpectrum
import com.adriano.lumemusic.audio.PlaybackClock
import com.adriano.lumemusic.data.PlayerSurfaceTab
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlin.math.max

/**
 * Arquitetura de "palcos" do Tocando agora. Cada palco desenha a área central; a fase 2 troca os
 * placeholders de Vinil, K7 e Ondas pelos palcos finais (iguais aos do iOS) sem mexer no resto da tela.
 */
interface PlayerStage {
    val tab: PlayerSurfaceTab
    @Composable fun Content(track: Track, artwork: String, modifier: Modifier)
}

object PlayerStages {
    val all: List<PlayerStage> = listOf(ArtworkStage, VinylStagePlaceholder, CassetteStagePlaceholder, WavesStagePlaceholder, LyricsStage)
    fun forTab(t: PlayerSurfaceTab): PlayerStage = all.first { it.tab == t }
}

// ---------------------------------------------------------------- Capa

object ArtworkStage : PlayerStage {
    override val tab = PlayerSurfaceTab.ARTWORK

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) {
        val scale by animateFloatAsState(if (AudioPlayer.isPlaying) 1f else 0.86f, spring(0.72f, Spring.StiffnessLow), label = "cover")
        Box(modifier.fillMaxSize().padding(horizontal = 28.dp), contentAlignment = Alignment.Center) {
            ArtworkImage(
                artwork.ifEmpty { track.artworkURL },
                Modifier.fillMaxWidth().graphicsLayer { scaleX = scale; scaleY = scale }
                    .shadow(28.dp * scale, RoundedCornerShape(26.dp), ambientColor = AudioPlayer.palette.vibrant, spotColor = AudioPlayer.palette.vibrant)
                    .aspectRatio(1f),
                26.dp,
            )
        }
    }
}

// ---------------------------------------------------------------- Vinil (placeholder)

object VinylStagePlaceholder : PlayerStage {
    override val tab = PlayerSurfaceTab.VINYL

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) {
        val spin by rememberSpin(AudioPlayer.isPlaying, 5200)
        Box(modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
            BoxWithConstraints(Modifier.fillMaxWidth().aspectRatio(1f), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize().rotate(spin)) {
                    val r = size.minDimension / 2
                    drawCircle(Brush.radialGradient(listOf(Color(0xFF2B2B30), Color(0xFF0B0B0D), Color(0xFF050506)), radius = r))
                    for (i in 0 until 18) drawCircle(Color.White.copy(alpha = 0.045f), radius = r * (0.40f + i * 0.032f), style = Stroke(1f))
                    drawArc(Color.White.copy(alpha = 0.10f), 200f, 40f, false, Offset(r * 0.12f, r * 0.12f), Size(r * 1.76f, r * 1.76f), style = Stroke(r * 0.06f, cap = StrokeCap.Round))
                }
                ArtworkImage(artwork.ifEmpty { track.artworkURL }, Modifier.fillMaxWidth(0.38f).aspectRatio(1f).rotate(spin), shape = CircleShape)
                Box(Modifier.size(10.dp).background(Color(0xFF0B0B0D), CircleShape))
            }
        }
    }
}

// ---------------------------------------------------------------- K7 (placeholder)

object CassetteStagePlaceholder : PlayerStage {
    override val tab = PlayerSurfaceTab.CASSETTE

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) {
        val spin by rememberSpin(AudioPlayer.isPlaying, 2600)
        Box(modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.fillMaxWidth().aspectRatio(1.6f).clip(RoundedCornerShape(20.dp)).background(Brush.verticalGradient(listOf(Color(0xFF3A3A40), Color(0xFF1C1C20)))).padding(14.dp)) {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(10.dp)).background(Color(0xFFEDE6D8)).padding(8.dp)) {
                        Column {
                            Text(track.title, style = Theme.font(15f, FontWeight.Bold, Color(0xFF2A2420)), maxLines = 1)
                            Text(track.artist, style = Theme.font(12f, color = Color(0xFF5A4E45)), maxLines = 1)
                        }
                    }
                    Box(Modifier.fillMaxWidth().weight(1.3f).clip(RoundedCornerShape(30.dp)).background(Color(0xFF0E0E10)), contentAlignment = Alignment.Center) {
                        Row(horizontalArrangement = Arrangement.spacedBy(56.dp)) {
                            repeat(2) {
                                Canvas(Modifier.size(54.dp).rotate(spin)) {
                                    val r = size.minDimension / 2
                                    drawCircle(Color(0xFFE9E9EC), radius = r)
                                    drawCircle(Color(0xFF111114), radius = r * 0.5f)
                                    for (k in 0 until 6) { val a = Math.toRadians(k * 60.0); drawLine(Color(0xFFE9E9EC), Offset(r, r), Offset(r + (r * 0.5f * Math.cos(a)).toFloat(), r + (r * 0.5f * Math.sin(a)).toFloat()), 4f) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- Ondas (espectro real)

object WavesStagePlaceholder : PlayerStage {
    override val tab = PlayerSurfaceTab.WAVES

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) {
        DisposableEffect(Unit) { AudioSpectrum.acquire(); onDispose { AudioSpectrum.release() } }
        val bands = AudioSpectrum.bands
        val p = AudioPlayer.palette
        Box(modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxWidth().height(240.dp)) {
                val n = bands.size
                val gap = 5.dp.toPx()
                val bw = (size.width - gap * (n - 1)) / n
                for (i in 0 until n) {
                    val h = max(6.dp.toPx(), bands[i] * size.height)
                    drawRoundRect(Brush.verticalGradient(listOf(p.vibrant, p.vibrant2), startY = size.height - h, endY = size.height),
                        Offset(i * (bw + gap), size.height - h), Size(bw, h), androidx.compose.ui.geometry.CornerRadius(bw / 2))
                }
            }
        }
    }
}

// ---------------------------------------------------------------- Letra (karaokê sincronizado)

object LyricsStage : PlayerStage {
    override val tab = PlayerSurfaceTab.LYRICS

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) {
        val bundle = AudioPlayer.lyrics
        Box(modifier.fillMaxSize()) {
            when {
                bundle == null && AudioPlayer.isLoadingLyrics -> CircularProgressIndicator(Modifier.align(Alignment.Center), color = Theme.rose)
                bundle == null -> Column(Modifier.align(Alignment.Center).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(sf("quote.bubble"), null, tint = Color.White.copy(0.6f), modifier = Modifier.size(40.dp))
                    Text("Letra não encontrada", style = Theme.font(17f, FontWeight.SemiBold, Color.White))
                    Text("Não achamos a letra desta faixa.", style = Theme.font(14f, color = Color.White.copy(0.7f)), textAlign = TextAlign.Center)
                    Box(Modifier.padding(top = 6.dp).height(44.dp).clip(RoundedCornerShape(50)).glass(RoundedCornerShape(50)).clickable { AudioPlayer.reloadLyrics() }.padding(horizontal = 22.dp), contentAlignment = Alignment.Center) {
                        Text("Tentar de novo", style = Theme.font(15f, FontWeight.SemiBold, Color.White))
                    }
                }
                else -> LyricsList(bundle)
            }
        }
    }
}

@Composable
private fun LyricsList(bundle: com.adriano.lumemusic.data.LyricsBundle) {
    val state = rememberLazyListState()
    val lines = bundle.lines
    val active by remember(bundle) {
        derivedStateOf {
            if (!bundle.synced) -1 else {
                val t = PlaybackClock.currentTime + 0.25
                var idx = -1
                for (i in lines.indices) { if (lines[i].time <= t) idx = i else break }
                idx
            }
        }
    }
    val density = LocalDensity.current
    LaunchedEffect(active) {
        if (active >= 0) state.animateScrollToItem(active, scrollOffset = -with(density) { 120.dp.roundToPx() })
    }
    LazyColumn(state = state, modifier = Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 28.dp, vertical = 80.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        items(lines.size, key = { lines[it].id }) { i ->
            val l = lines[i]
            val isActive = i == active
            val a by animateFloatAsState(if (!bundle.synced) 0.92f else if (isActive) 1f else if (active >= 0 && i < active) 0.38f else 0.5f, tween(300), label = "la")
            val s by animateFloatAsState(if (isActive) 1.04f else 1f, spring(0.8f, Spring.StiffnessMedium), label = "ls")
            Column(Modifier.fillMaxWidth().clickable(remember { MutableInteractionSource() }, null) { if (bundle.synced) AudioPlayer.seek(l.time) }.graphicsLayer { alpha = a; scaleX = s; scaleY = s; transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 0.5f) }) {
                Text(l.text, style = Theme.font(if (isActive) 26f else 24f, FontWeight.Bold, if (isActive) Color.White else Color.White.copy(0.9f)).copy(lineHeight = 31.sp))
                if (AudioPlayer.showTranslation && l.translated != null) Text(l.translated, style = Theme.font(15.5f, FontWeight.Medium, Theme.peach), modifier = Modifier.padding(top = 3.dp))
            }
        }
        item { Text(bundle.source, style = Theme.font(12f, color = Color.White.copy(0.45f)), modifier = Modifier.padding(top = 24.dp)) }
    }
}

// ---------------------------------------------------------------- utilitários

@Composable
private fun rememberSpin(playing: Boolean, periodMs: Int): androidx.compose.runtime.State<Float> {
    val angle = remember { androidx.compose.runtime.mutableFloatStateOf(0f) }
    LaunchedEffect(playing) {
        if (!playing) return@LaunchedEffect
        var last = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            angle.floatValue = (angle.floatValue + (now - last) / 1e6f * 360f / periodMs) % 360f
            last = now
        }
    }
    return angle
}
