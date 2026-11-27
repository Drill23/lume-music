package com.adriano.lumemusic.ui.screens

import com.adriano.lumemusic.ui.Chrome
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
import androidx.compose.ui.draw.drawWithContent
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
import com.adriano.lumemusic.ui.stage.CassetteStage
import com.adriano.lumemusic.ui.stage.VinylStage
import com.adriano.lumemusic.ui.stage.WavesStage
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
    val all: List<PlayerStage> = listOf(ArtworkStage, VinylStage, CassetteStage, WavesStage, LyricsStage)
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
                    Box(Modifier.padding(top = 6.dp).height(Chrome.minTouch).clip(RoundedCornerShape(50)).glass(RoundedCornerShape(50)).clickable { AudioPlayer.reloadLyrics() }.padding(horizontal = 22.dp), contentAlignment = Alignment.Center) {
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
    LazyColumn(
        state = state,
        // Máscara de esmaecimento do iOS (LyricsStage): topo 0→8%, base 82%→100%; as linhas somem antes de tocar a pílula de palcos.
        modifier = Modifier.fillMaxSize().graphicsLayer { compositingStrategy = androidx.compose.ui.graphics.CompositingStrategy.Offscreen }.drawWithContent {
            drawContent()
            drawRect(
                Brush.verticalGradient(0f to Color.Transparent, 0.08f to Color.Black, 0.82f to Color.Black, 1f to Color.Transparent),
                blendMode = androidx.compose.ui.graphics.BlendMode.DstIn,
            )
        },
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 28.dp, vertical = 80.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
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
