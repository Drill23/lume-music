package com.adriano.lumemusic.ui.screens

import android.graphics.Bitmap
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.audio.AudioSpectrum
import com.adriano.lumemusic.audio.PlaybackClock
import com.adriano.lumemusic.data.CassetteStyle
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.PlayerSurfaceTab
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.data.TurntableFinish
import com.adriano.lumemusic.data.VinylEdition
import com.adriano.lumemusic.data.VisualizerStyle
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** Rotação contínua, avançando só enquanto [running] (pausada fora da tela/parada: zero custo). */
@Composable
private fun rememberRotation(running: Boolean, degPerSec: () -> Float): androidx.compose.runtime.State<Float> {
    val a = remember { mutableFloatStateOf(0f) }
    LaunchedEffect(running) {
        if (!running) return@LaunchedEffect
        var last = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            a.floatValue = (a.floatValue + (now - last) / 1e9f * degPerSec()) % 360f
            last = now
        }
    }
    return a
}

// ======================================================================= VINIL (toca-discos)

/** Geometria do toca-discos (mesmas constantes de DeckGeo do iOS; u = altura do deck). */
private object Deck {
    const val ASPECT = 1.45f
    const val PLATTER_CX = 0.505f; const val PLATTER_CY = 0.5f
    const val PLATTER_D = 0.92f; const val RECORD_D = 0.855f; const val LABEL_D = 0.29f
    const val PIVOT_X = 1.30f; const val PIVOT_Y = 0.20f
    const val ARM_L = 0.74f; const val REST = 24.0
    const val R_OUTER = 0.405f; const val R_INNER = 0.195f

    /** Ângulo (graus, horário a partir de "para baixo") em que a agulha cai a [r] do centro do prato. */
    fun armAngle(r: Float): Double {
        var lo = 0.0; var hi = 70.0
        fun dist(deg: Double): Double {
            val a = Math.toRadians(deg)
            val nx = PIVOT_X - ARM_L * sin(a); val ny = PIVOT_Y + ARM_L * cos(a)
            return hypot(nx - PLATTER_CX, ny - PLATTER_CY)
        }
        // distância cresce com o ângulo decrescente; busca por bissecção no intervalo útil
        repeat(40) { val mid = (lo + hi) / 2; if (dist(mid) > r) lo = mid else hi = mid }
        return (lo + hi) / 2
    }
    fun angleForProgress(p: Float): Double = armAngle(R_OUTER - (R_OUTER - R_INNER) * p.coerceIn(0f, 1f))
}

/** Textura do disco (vinil + sulcos) renderizada UMA vez e só girada. */
@Composable
private fun rememberRecordBitmap(edition: VinylEdition): ImageBitmap = remember(edition) {
    val s = 720
    val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
    val c = android.graphics.Canvas(bmp)
    val r = s / 2f
    val (inner, outer) = when (edition) {
        VinylEdition.CLASSIC_BLACK -> 0xFF2A2A2E.toInt() to 0xFF070708.toInt()
        VinylEdition.PRISM_CRYSTAL -> 0xFF8A7BC8.toInt() to 0xFF2C2A52.toInt()
        VinylEdition.LIMITED_GOLD -> 0xFFE3B34A.toInt() to 0xFF6B4A12.toInt()
        VinylEdition.WHITE_MARBLE -> 0xFFF3F1EE.toInt() to 0xFFB9B5B0.toInt()
    }
    val p = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
    p.shader = android.graphics.RadialGradient(r, r, r, intArrayOf(inner, outer, outer), floatArrayOf(0f, 0.8f, 1f), android.graphics.Shader.TileMode.CLAMP)
    c.drawCircle(r, r, r, p)
    val g = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { style = android.graphics.Paint.Style.STROKE; strokeWidth = 1.2f }
    val dark = edition == VinylEdition.CLASSIC_BLACK || edition == VinylEdition.PRISM_CRYSTAL
    var k = 0
    var rr = r * 0.36f
    while (rr < r * 0.97f) { g.color = if (dark) android.graphics.Color.argb(if (k % 7 == 0) 46 else 20, 255, 255, 255) else android.graphics.Color.argb(if (k % 7 == 0) 60 else 28, 0, 0, 0); c.drawCircle(r, r, rr, g); rr += r * 0.0165f; k++ }
    if (edition == VinylEdition.PRISM_CRYSTAL) {
        val sw = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
        sw.shader = android.graphics.SweepGradient(r, r, intArrayOf(0x55FFB27A, 0x55FF7BA9, 0x55AD8CFF, 0x557CC8FF, 0x55FFB27A), null)
        c.drawCircle(r, r, r * 0.97f, sw)
    }
    bmp.asImageBitmap()
}

object VinylStage : PlayerStage {
    override val tab = PlayerSurfaceTab.VINYL

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) {
        val s = LibraryStore
        var rpm45 by remember { mutableStateOf(false) }
        var pitch by remember { mutableFloatStateOf(0f) }
        val playing = AudioPlayer.isPlaying
        val progress = if (PlaybackClock.duration > 0) (PlaybackClock.currentTime / PlaybackClock.duration).toFloat() else 0f
        val restAngle = Deck.REST.toFloat()
        val target = if (playing) Deck.angleForProgress(progress).toFloat() else restAngle
        val arm by animateFloatAsState(target, tween(if (playing) 1150 else 1050, easing = FastOutSlowInEasing), label = "arm")
        val spin by rememberRotation(playing) { (if (rpm45) 45f else 33.3333f) * 6f * (1 + pitch * 0.08f) }
        val record = rememberRecordBitmap(s.vinylEdition)
        val finish = s.turntableFinish
        Column(modifier.fillMaxSize().padding(horizontal = 14.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            BoxWithConstraints(Modifier.fillMaxWidth().aspectRatio(Deck.ASPECT)) {
                val wPx = constraints.maxWidth.toFloat()
                Canvas(Modifier.fillMaxSize()) {
                    val H = size.height
                    val (c1, c2) = when (finish) {
                        TurntableFinish.OBSIDIAN -> Color(0xFF26262B) to Color(0xFF0D0D10)
                        TurntableFinish.SILVER -> Color(0xFFE9E9EE) to Color(0xFFBFC0C8)
                        TurntableFinish.WALNUT -> Color(0xFF6B4630) to Color(0xFF3A2416)
                        TurntableFinish.GOLD -> Color(0xFFEBD9A8) to Color(0xFFB59A55)
                    }
                    drawRoundRect(Color.Black.copy(0.30f), Offset(0.02f * H, 0.04f * H), Size(size.width - 0.04f * H, size.height - 0.04f * H), CornerRadius(0.07f * H))
                    drawRoundRect(Brush.verticalGradient(listOf(c1, c2)), Offset.Zero, Size(size.width, size.height - 0.03f * H), CornerRadius(0.07f * H))
                    drawRoundRect(Color.White.copy(0.18f), Offset.Zero, Size(size.width, size.height - 0.03f * H), CornerRadius(0.07f * H), style = Stroke(1.2f))
                    val cx = Deck.PLATTER_CX * H; val cy = Deck.PLATTER_CY * H
                    val pr = Deck.PLATTER_D * H / 2
                    drawCircle(Brush.radialGradient(listOf(Color(0xFF3A3A40), Color(0xFF111114)), Offset(cx, cy), pr), pr, Offset(cx, cy))
                    // anel estroboscópico (pontos fixos na borda do prato)
                    val dots = if (rpm45) 90 else 100
                    for (i in 0 until dots) {
                        val a = i * 2 * PI / dots
                        val on = i % 2 == 0
                        drawCircle(if (on) Color.White.copy(0.55f) else Color.White.copy(0.14f), 0.0042f * H, Offset(cx + ((pr - 0.012f * H) * cos(a)).toFloat(), cy + ((pr - 0.012f * H) * sin(a)).toFloat()))
                    }
                    // pivô e luz do pitch ficam por conta da doca; braço desenhado depois do disco
                }
                // disco (textura pré-renderizada) girando
                val dRec = with(androidx.compose.ui.platform.LocalDensity.current) { (Deck.RECORD_D * (wPx / Deck.ASPECT)).toDp() }
                val dLab = with(androidx.compose.ui.platform.LocalDensity.current) { (Deck.LABEL_D * (wPx / Deck.ASPECT)).toDp() }
                val xOff = with(androidx.compose.ui.platform.LocalDensity.current) { ((Deck.PLATTER_CX * (wPx / Deck.ASPECT)) - (Deck.RECORD_D * (wPx / Deck.ASPECT)) / 2).toDp() }
                val yOff = with(androidx.compose.ui.platform.LocalDensity.current) { ((Deck.PLATTER_CY * (wPx / Deck.ASPECT)) - (Deck.RECORD_D * (wPx / Deck.ASPECT)) / 2).toDp() }
                Box(Modifier.padding(start = xOff, top = yOff).size(dRec).graphicsLayer { rotationZ = spin }, contentAlignment = Alignment.Center) {
                    androidx.compose.foundation.Image(record, null, Modifier.fillMaxSize())
                    Box(contentAlignment = Alignment.Center) {
                        ArtworkImage(artwork.ifEmpty { track.artworkURL }, Modifier.size(dLab), shape = CircleShape)
                        Text(if (rpm45) "LADO A · 45 RPM" else "LADO A · 33⅓ RPM", style = Theme.font(6.5f, FontWeight.Bold, Color.White.copy(0.85f)), modifier = Modifier.padding(top = dLab * 0.66f))
                        Box(Modifier.size(7.dp).background(Color(0xFF0B0B0D), CircleShape))
                    }
                }
                // reflexo parado (não gira com o disco)
                Canvas(Modifier.fillMaxSize()) {
                    val H = size.height; val cx = Deck.PLATTER_CX * H; val cy = Deck.PLATTER_CY * H; val rr = Deck.RECORD_D * H / 2
                    rotate(-35f, Offset(cx, cy)) {
                        drawRect(Brush.horizontalGradient(listOf(Color.Transparent, Color.White.copy(0.16f), Color.Transparent), cx - rr * 0.25f, cx + rr * 0.25f), Offset(cx - rr * 0.25f, cy - rr), Size(rr * 0.5f, rr * 2))
                    }
                    // braço
                    val px = Deck.PIVOT_X * H; val py = Deck.PIVOT_Y * H
                    rotate(-(arm), Offset(px, py)) {
                        val L = Deck.ARM_L * H
                        drawLine(Brush.horizontalGradient(listOf(Color(0xFFE9E9EE), Color(0xFF9A9AA4))), Offset(px, py - 0.05f * H), Offset(px, py + L), 0.022f * H, StrokeCap.Round)
                        drawRoundRect(Color(0xFFD7D7DE), Offset(px - 0.026f * H, py + L - 0.02f * H), Size(0.052f * H, 0.085f * H), CornerRadius(0.012f * H))
                        drawCircle(Color(0xFF2B2B30), 0.06f * H, Offset(px, py - 0.02f * H))
                        drawCircle(Color(0xFFCFCFD6), 0.03f * H, Offset(px, py - 0.02f * H))
                    }
                }
            }
            // doca: 33/45, iniciar/parar, pitch
            Row(Modifier.fillMaxWidth().padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(Modifier.height(44.dp).glass(RoundedCornerShape(50)).padding(3.dp)) {
                    for ((label, is45) in listOf("33⅓" to false, "45" to true)) {
                        Box(Modifier.size(width = 52.dp, height = 38.dp).clip(RoundedCornerShape(50)).background(if (rpm45 == is45) Color.White.copy(0.22f) else Color.Transparent).pressable(0.94f) { rpm45 = is45 }, contentAlignment = Alignment.Center) {
                            Text(label, style = Theme.font(14f, FontWeight.Bold, Color.White))
                        }
                    }
                }
                Box(Modifier.size(44.dp).glass(CircleShape).pressable(0.9f) { AudioPlayer.togglePlayPause() }, contentAlignment = Alignment.Center) {
                    Icon(sf(if (playing) "pause.fill" else "play.fill"), null, tint = Color.White, modifier = Modifier.size(20.dp))
                }
                Column(Modifier.weight(1f)) {
                    Text("PITCH ${"%+.1f".format(pitch * 8)}%", style = Theme.font(10.5f, FontWeight.SemiBold, Color.White.copy(0.65f)))
                    Slider(pitch, { pitch = it; AudioPlayer.setVarispeed(1f + it * 0.08f) }, valueRange = -1f..1f,
                        colors = SliderDefaults.colors(thumbColor = Theme.rose, activeTrackColor = Theme.rose, inactiveTrackColor = Color.White.copy(0.2f)), modifier = Modifier.height(28.dp))
                }
            }
        }
    }
}

// ======================================================================= FITA K7

object CassetteStage : PlayerStage {
    override val tab = PlayerSurfaceTab.CASSETTE

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) {
        DisposableEffect(Unit) { AudioSpectrum.acquire(); onDispose { AudioSpectrum.release() } }
        val playing = AudioPlayer.isPlaying
        val progress = if (PlaybackClock.duration > 0) (PlaybackClock.currentTime / PlaybackClock.duration).toFloat().coerceIn(0f, 1f) else 0f
        var side by remember { mutableStateOf(0) }
        val flip by animateFloatAsState(side * 180f, tween(600), label = "flip")
        val spin by rememberRotation(playing) { 140f }
        val style = LibraryStore.cassetteStyle
        val (body1, body2, labelBg) = when (style) {
            CassetteStyle.SMOKED_STUDIO -> Triple(Color(0xFF3A3A40), Color(0xFF17171B), Color(0xFFEDE6D8))
            CassetteStyle.CRYSTAL_CLEAR -> Triple(Color(0xFFCFD6E6).copy(0.55f), Color(0xFF9AA6C2).copy(0.45f), Color(0xFFFFFBF2))
            CassetteStyle.METALLIC_CHROME -> Triple(Color(0xFFD9DBE2), Color(0xFF8E919C), Color(0xFFF2EFE6))
            CassetteStyle.VINTAGE_CREAM -> Triple(Color(0xFFE9DDC2), Color(0xFFC9B88F), Color(0xFFFFF7E3))
        }
        val vu = AudioSpectrum.level
        Column(modifier.fillMaxSize().padding(horizontal = 18.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Box(Modifier.fillMaxWidth().aspectRatio(1.62f).graphicsLayer { rotationY = flip; cameraDistance = 14f * density }.clip(RoundedCornerShape(18.dp)).background(Brush.verticalGradient(listOf(body1, body2))).padding(12.dp)) {
                val showBack = flip > 90f
                Column(Modifier.fillMaxSize().graphicsLayer { rotationY = if (showBack) 180f else 0f }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    // etiqueta escrita à mão + capinha
                    Row(Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(8.dp)).background(labelBg).padding(8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ArtworkImage(artwork.ifEmpty { track.artworkURL }, Modifier.fillMaxSize().aspectRatio(1f), 4.dp)
                        Column(Modifier.weight(1f)) {
                            Text(track.title, style = Theme.font(15f, FontWeight.Bold, Color(0xFF2A2420)).copy(fontFamily = FontFamily.Cursive), maxLines = 2)
                            Text(track.artist, style = Theme.font(12.5f, color = Color(0xFF5A4E45)).copy(fontFamily = FontFamily.Cursive), maxLines = 1)
                        }
                        Text(if (showBack) "B" else "A", style = Theme.rounded(22f, FontWeight.Bold, Color(0xFFB0382D)))
                    }
                    // janela com carretéis (tamanho da fita muda com o progresso)
                    Box(Modifier.fillMaxWidth().weight(1.2f).clip(RoundedCornerShape(28.dp)).background(Color(0xFF0E0E10))) {
                        Canvas(Modifier.fillMaxSize()) {
                            val cy = size.height / 2; val gap = size.width * 0.27f
                            val minR = size.height * 0.20f; val maxR = size.height * 0.46f
                            val leftR = maxR - (maxR - minR) * progress
                            val rightR = minR + (maxR - minR) * progress
                            for ((i, cxr) in listOf(size.width / 2 - gap, size.width / 2 + gap).withIndex()) {
                                val tr = if (i == 0) leftR else rightR
                                drawCircle(Color(0xFF3B2A20), tr, Offset(cxr, cy))
                                drawCircle(Color(0xFF5A4332), tr, Offset(cxr, cy), style = Stroke(1.5f))
                                rotate(spin * (if (i == 0) 1f else 1.1f), Offset(cxr, cy)) {
                                    drawCircle(Color(0xFFE9E9EC), minR * 0.78f, Offset(cxr, cy))
                                    drawCircle(Color(0xFF111114), minR * 0.5f, Offset(cxr, cy))
                                    for (k in 0 until 6) { val a = k * PI / 3; drawLine(Color(0xFFE9E9EC), Offset(cxr, cy), Offset(cxr + (minR * 0.62f * cos(a)).toFloat(), cy + (minR * 0.62f * sin(a)).toFloat()), 4f) }
                                }
                            }
                            drawLine(Color(0xFF3B2A20), Offset(size.width / 2 - gap, cy + leftR), Offset(size.width / 2 + gap, cy + rightR), 3f)
                        }
                    }
                    // VU
                    Row(Modifier.fillMaxWidth().height(14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("VU", style = Theme.font(9f, FontWeight.Bold, Color.White.copy(0.7f)))
                        Box(Modifier.weight(1f).height(5.dp).clip(CircleShape).background(Color.White.copy(0.15f))) { Box(Modifier.fillMaxWidth(min(1f, vu * 1.1f)).fillMaxSize().background(Brush.horizontalGradient(listOf(Theme.mint, Theme.peach, Theme.danger)))) }
                        Box(Modifier.weight(1f).height(5.dp).clip(CircleShape).background(Color.White.copy(0.15f))) { Box(Modifier.fillMaxWidth(min(1f, vu * 0.96f)).fillMaxSize().background(Brush.horizontalGradient(listOf(Theme.mint, Theme.peach, Theme.danger)))) }
                    }
                }
            }
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(Modifier.height(44.dp).pressable(0.94f) { side = 1 - side }.glass(RoundedCornerShape(50)).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(sf("arrow.clockwise"), null, tint = Color.White, modifier = Modifier.size(18.dp))
                    Text(if (side == 0) "Virar para o Lado B" else "Virar para o Lado A", style = Theme.font(14f, FontWeight.SemiBold, Color.White))
                }
            }
        }
    }
}

// ======================================================================= ONDAS (vidro líquido + outros estilos)

object WavesStage : PlayerStage {
    override val tab = PlayerSurfaceTab.WAVES

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) {
        DisposableEffect(Unit) { AudioSpectrum.acquire(); onDispose { AudioSpectrum.release() } }
        val style = LibraryStore.visualizerStyle
        val pal = AudioPlayer.palette
        val bands = AudioSpectrum.bands
        val level = AudioSpectrum.level
        var beat by remember { mutableFloatStateOf(0f) }
        var avg by remember { mutableFloatStateOf(0f) }
        val bass = (bands.take(5).average().toFloat())
        avg = avg * 0.94f + bass * 0.06f
        beat = if (bass > avg * 1.35f + 0.05f) 1f else beat * 0.9f
        var phase by remember { mutableFloatStateOf(0f) }
        LaunchedEffect(AudioPlayer.isPlaying) { if (AudioPlayer.isPlaying) { var last = withFrameNanos { it }; while (true) { val n = withFrameNanos { it }; phase += (n - last) / 1e9f; last = n } } }
        Box(modifier.fillMaxSize().padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxWidth().height(340.dp)) {
                when (style) {
                    VisualizerStyle.ARES -> glassRibbons(bands, level, beat, phase, pal.vibrant, pal.vibrant2)
                    VisualizerStyle.AURORA -> mirrorBars(bands, pal.vibrant, pal.vibrant2)
                    VisualizerStyle.ORB -> orb(bands, level, beat, pal.vibrant, pal.vibrant2)
                    VisualizerStyle.SOLAR_RING -> solarRing(bands, level, phase, pal.vibrant, pal.vibrant2)
                    VisualizerStyle.OSCILLOSCOPE -> scope(bands, phase, pal.vibrant)
                    VisualizerStyle.NEBULA -> nebula(bands, level, phase, pal.quadrants)
                    VisualizerStyle.OFF -> {}
                }
            }
            if (style == VisualizerStyle.OFF) ArtworkImage(artwork.ifEmpty { track.artworkURL }, Modifier.fillMaxWidth(0.8f).aspectRatio(1f), 26.dp)
        }
    }
}

/** Fitas de vidro simétricas: cada fita é uma onda cuja amplitude segue uma faixa do FFT; a batida incha o conjunto. */
private fun DrawScope.glassRibbons(bands: FloatArray, level: Float, beat: Float, phase: Float, c1: Color, c2: Color) {
    val cy = size.height / 2; val w = size.width
    val ribbons = 5
    for (r in 0 until ribbons) {
        val b0 = r * 4; val e = (bands.slice(b0 until min(bands.size, b0 + 4)).average().toFloat())
        val amp = (0.08f + e * 0.55f + beat * 0.08f) * size.height * (1f - r * 0.1f)
        val k = 1.6f + r * 0.55f
        val top = Path(); val bot = Path()
        val n = 90
        for (i in 0..n) {
            val t = i / n.toFloat()
            val env = sin(PI * t).toFloat()
            val y = (sin(t * k * 2 * PI + phase * (1.1f + r * 0.35f) + r) * amp * env).toFloat()
            val x = t * w
            if (i == 0) { top.moveTo(x, cy - abs(y) - 3f); bot.moveTo(x, cy + abs(y) + 3f) } else { top.lineTo(x, cy - abs(y) - 3f); bot.lineTo(x, cy + abs(y) + 3f) }
        }
        val col = androidx.compose.ui.graphics.lerp(c1, c2, r / (ribbons - 1f))
        val fill = Path().apply { addPath(top); for (i in 90 downTo 0) { val t = i / 90f; val env = sin(PI * t).toFloat(); val y = (sin(t * k * 2 * PI + phase * (1.1f + r * 0.35f) + r) * amp * env).toFloat(); lineTo(t * w, cy + abs(y) + 3f) }; close() }
        drawPath(fill, Brush.verticalGradient(listOf(col.copy(0.05f), col.copy(0.30f), col.copy(0.05f))))
        drawPath(top, col.copy(0.85f), style = Stroke(2.2f, cap = StrokeCap.Round))
        drawPath(bot, Color.White.copy(0.55f), style = Stroke(1.2f, cap = StrokeCap.Round))
    }
}

private fun DrawScope.mirrorBars(bands: FloatArray, c1: Color, c2: Color) {
    val n = bands.size; val gap = 4.dp.toPx(); val bw = (size.width - gap * (n - 1)) / n; val cy = size.height / 2
    for (i in 0 until n) { val h = max(4.dp.toPx(), bands[i] * size.height / 2); drawRoundRect(Brush.verticalGradient(listOf(c1, c2), cy - h, cy + h), Offset(i * (bw + gap), cy - h), Size(bw, h * 2), CornerRadius(bw / 2)) }
}

private fun DrawScope.orb(bands: FloatArray, level: Float, beat: Float, c1: Color, c2: Color) {
    val c = center; val base = size.minDimension * 0.22f
    drawCircle(Brush.radialGradient(listOf(c1.copy(0.9f), c2.copy(0.35f), Color.Transparent), c, base * (2f + level + beat * 0.3f)), base * (2f + level + beat * 0.3f), c)
    drawCircle(Brush.radialGradient(listOf(Color.White.copy(0.9f), c1, c2), c - Offset(base * 0.2f, base * 0.2f), base * 1.2f), base * (1f + level * 0.35f + beat * 0.1f), c)
    for (i in bands.indices) { val a = i * 2 * PI / bands.size; val r0 = base * 1.3f; val r1 = r0 + bands[i] * base * 1.4f; drawLine(Color.White.copy(0.7f), Offset(c.x + (r0 * cos(a)).toFloat(), c.y + (r0 * sin(a)).toFloat()), Offset(c.x + (r1 * cos(a)).toFloat(), c.y + (r1 * sin(a)).toFloat()), 3f, StrokeCap.Round) }
}

private fun DrawScope.solarRing(bands: FloatArray, level: Float, phase: Float, c1: Color, c2: Color) {
    val c = center; val r0 = size.minDimension * 0.26f
    drawCircle(c1.copy(0.25f), r0 * (1.1f + level * 0.2f), c, style = Stroke(6f))
    rotate(phase * 12f, c) {
        for (i in bands.indices) { val a = i * 2 * PI / bands.size; val l = 6f + bands[i] * size.minDimension * 0.28f
            drawLine(androidx.compose.ui.graphics.lerp(c1, c2, i / bands.size.toFloat()), Offset(c.x + (r0 * cos(a)).toFloat(), c.y + (r0 * sin(a)).toFloat()), Offset(c.x + ((r0 + l) * cos(a)).toFloat(), c.y + ((r0 + l) * sin(a)).toFloat()), 6f, StrokeCap.Round) }
    }
}

private fun DrawScope.scope(bands: FloatArray, phase: Float, c: Color) {
    val cy = size.height / 2; val p = Path(); val n = 120
    for (i in 0..n) { val t = i / n.toFloat(); val bi = (t * (bands.size - 1)).toInt(); val y = (sin(t * 18f + phase * 6f) * bands[bi] * size.height * 0.4f + sin(t * 7f - phase * 3f) * bands[(bi + 3) % bands.size] * size.height * 0.15f).toFloat()
        if (i == 0) p.moveTo(0f, cy + y) else p.lineTo(t * size.width, cy + y) }
    drawPath(p, c.copy(0.25f), style = Stroke(10f, cap = StrokeCap.Round)); drawPath(p, c, style = Stroke(3f, cap = StrokeCap.Round))
    drawLine(Color.White.copy(0.12f), Offset(0f, cy), Offset(size.width, cy), 1f)
}

private fun DrawScope.nebula(bands: FloatArray, level: Float, phase: Float, q: List<Color>) {
    for (i in 0 until 6) { val e = bands[(i * 4) % bands.size]; val a = phase * 0.3f + i * 1.05f
        val c = Offset(center.x + (cos(a) * size.width * 0.28f).toFloat(), center.y + (sin(a * 1.3f) * size.height * 0.25f).toFloat()); val r = size.minDimension * (0.22f + e * 0.35f + level * 0.1f)
        drawCircle(Brush.radialGradient(listOf(q[i % q.size].copy(0.75f), Color.Transparent), c, r), r, c) }
}
