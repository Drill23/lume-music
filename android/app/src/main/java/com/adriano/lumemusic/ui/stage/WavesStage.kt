package com.adriano.lumemusic.ui.stage

import android.content.Context
import android.os.PowerManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Waves
import androidx.compose.material3.Icon
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.currentStateAsState
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.audio.AudioSpectrum
import com.adriano.lumemusic.audio.PlaybackClock
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.PlayerSurfaceTab
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.data.VisualizerStyle
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.screens.PlayerStage
import com.adriano.lumemusic.ui.theme.LocalDark
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** Palco "Ondas" (VisualizerViews.swift): visualizadores reativos ao FFT real do player. */
object WavesStage : PlayerStage {
    override val tab = PlayerSurfaceTab.WAVES

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) = WavesStageContent(track, artwork, modifier)
}

/** Estilos do menu (5.0): "Anel Solar" saiu (vira Orbe) e "Desligado" vira as Ondas Líquidas. */
private val waveStyles = listOf(VisualizerStyle.ARES, VisualizerStyle.AURORA, VisualizerStyle.ORB, VisualizerStyle.OSCILLOSCOPE, VisualizerStyle.NEBULA)
private fun resolved(s: VisualizerStyle) = when (s) { VisualizerStyle.SOLAR_RING -> VisualizerStyle.ORB; VisualizerStyle.OFF -> VisualizerStyle.ARES; else -> s }
private fun titleFor(s: VisualizerStyle) = when (s) {
    VisualizerStyle.ARES -> "Ondas Líquidas"; VisualizerStyle.AURORA -> "Espectro"; VisualizerStyle.ORB -> "Orbe"
    VisualizerStyle.SOLAR_RING -> "Anel Solar"; VisualizerStyle.OSCILLOSCOPE -> "Osciloscópio"; VisualizerStyle.NEBULA -> "Nebulosa"; VisualizerStyle.OFF -> "Desligado"
}
private fun iconFor(s: VisualizerStyle): ImageVector = if (s == VisualizerStyle.ARES) Icons.Rounded.Waves else sf(s.icon)

@Composable
private fun WavesStageContent(track: Track, artwork: String, modifier: Modifier) {
    val store = LibraryStore
    val style = resolved(store.visualizerStyle)
    Box(modifier.fillMaxSize()) {
        SpectrumVisualizer(
            style, AudioPlayer.palette.vibrant, AudioPlayer.palette.vibrant2, artwork, AudioPlayer.isPlaying, track.id,
            Modifier.fillMaxSize().padding(horizontal = 8.dp).pointerInput(style) {
                detectTapGestures {
                    Haptics.selection()
                    val i = waveStyles.indexOf(style).coerceAtLeast(0)
                    store.visualizerStyle = waveStyles[(i + 1) % waveStyles.size]
                }
            },
        )
        StageStyleOrb(icon = "waveform", desc = "Estilo das ondas", top = true) { dismiss ->
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("VISUALIZADOR", style = Theme.font(10f, FontWeight.ExtraBold, StageSecondary, letterSpacing = spF(0.8f)), modifier = Modifier.padding(start = 6.dp, end = 6.dp, bottom = 2.dp))
                for (st in waveStyles) {
                    val active = style == st
                    val shape = RoundedCornerShape(10.dp)
                    Row(
                        Modifier.fillMaxWidth().height(44.dp).clip(shape).background(if (active) Theme.prismDiagonal else androidx.compose.ui.graphics.SolidColor(Color.White.copy(0.06f)), shape)
                            .pointerInput(st) { detectTapGestures { Haptics.selection(); store.visualizerStyle = st; dismiss() } }.padding(horizontal = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        val c = if (active) Theme.onPrism else StageText
                        Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { Icon(iconFor(st), null, tint = c, modifier = Modifier.size(13.dp)) }
                        Text(titleFor(st), style = Theme.font(12f, if (active) FontWeight.Bold else FontWeight.SemiBold, c), modifier = Modifier.weight(1f), maxLines = 1)
                        if (active) Icon(sf("checkmark"), null, tint = c, modifier = Modifier.size(12.dp))
                    }
                }
            }
        }
    }
}

// ============================================================ quadro do analisador (kick / graves / nível / batida)

class SpectrumFrame(val bands: FloatArray, val level: Float, val kick: Float, val bass: Float, val beat: Int)

/**
 * Monta o quadro a partir do FFT real do Android (24 bandas + nível): graves suavizados como no iOS
 * ((b0+b1+b2+b3)/4, ataque 0,6 / queda 0,18), batida detectada por salto de graves sobre a média lenta
 * (decaimento do kick ~170 ms) e, sem espectro real, a mesma simulação guiada pelo tempo da faixa.
 */
class SpectrumFrameBuilder {
    private var bassSm = 0f
    private var bassAvg = 0f
    private var kickStrength = 0f
    private var kickTimeNs = 0L
    private var beatCounter = 0
    private var simAnchorSong = 0.0
    private var simAnchorWall = 0.0
    private var simLastClock = -1.0
    private var frameOut = SpectrumFrame(FloatArray(AudioSpectrum.BAND_COUNT), 0f, 0f, 0f, 0)

    val frame: SpectrumFrame get() = frameOut

    fun update(nowNanos: Long, playing: Boolean, trackId: String): SpectrumFrame {
        frameOut = if (AudioSpectrum.isLive) live(nowNanos) else simulated(nowNanos / 1e9, playing, trackId)
        return frameOut
    }

    private fun live(now: Long): SpectrumFrame {
        val b = AudioSpectrum.bands
        val bassNow = if (b.size >= 4) (b[0] + b[1] + b[2] + b[3]) * 0.25f else 0f
        bassSm += (bassNow - bassSm) * (if (bassNow > bassSm) 0.6f else 0.18f)
        val since0 = if (kickTimeNs == 0L) 10.0 else (now - kickTimeNs) / 1e9
        if (bassNow > bassAvg * 1.35f + 0.05f && since0 > 0.20) {
            kickStrength = min(1f, 0.45f + (bassNow - bassAvg) * 2.2f + bassNow * 0.3f)
            kickTimeNs = now
            beatCounter++
        }
        bassAvg += (bassNow - bassAvg) * 0.04f
        val since = if (kickTimeNs == 0L) 10.0 else (now - kickTimeNs) / 1e9
        val k = kickStrength * exp(-max(0.0, since) / 0.17).toFloat()
        return SpectrumFrame(b, AudioSpectrum.level, k, bassSm, beatCounter)
    }

    private fun simulated(wall: Double, playing: Boolean, trackId: String): SpectrumFrame {
        val n = AudioSpectrum.BAND_COUNT
        val clockNow = PlaybackClock.currentTime
        if (clockNow != simLastClock) { simLastClock = clockNow; simAnchorSong = clockNow; simAnchorWall = wall }
        val song = if (playing) simAnchorSong + min(0.5, wall - simAnchorWall) else simAnchorSong
        var h = 2166136261L
        for (c in trackId.ifEmpty { "lume" }.toByteArray(Charsets.UTF_8)) { h = ((h xor (c.toLong() and 0xFF)) * 16777619L) and 0xFFFFFFFFL }
        val bpm = 92.0 + (h % 36)
        val spb = 60.0 / bpm
        val beatPos = max(0.0, song) / spb
        val beatIdx = beatPos.toInt()
        val phase = beatPos - beatIdx
        val since = phase * spb
        val accent = if (beatIdx % 4 == 0) 1.0 else if (beatIdx % 2 == 0) 0.8 else 0.68
        val amp = if (playing) 1.0 else 0.0
        val kick = amp * accent * exp(-since / 0.17)
        val hatPhase = ((phase + 0.5) % 1.0) * spb
        val hat = amp * exp(-hatPhase / 0.06)
        val phr = 0.75 + 0.25 * sin(beatPos * PI / 8)
        val bands = FloatArray(n)
        for (i in 0 until n) {
            val f = i.toDouble() / (n - 1)
            val tilt = 0.55 * (1 - f) + 0.12
            val low = if (f < 0.25) kick * (1 - f * 3) * 0.5 else 0.0
            val mid = 0.16 * (0.5 + 0.5 * sin(song * 1.7 + i * 0.9)) * (if (f > 0.2 && f < 0.75) 1.0 else 0.4)
            val high = if (f > 0.6) hat * 0.28 * f else 0.0
            bands[i] = min(1.0, max(0.02, amp * (tilt * phr + low + mid + high))).toFloat()
        }
        return SpectrumFrame(bands, (amp * (0.45 + 0.25 * kick + 0.1 * phr)).toFloat(), kick.toFloat(), (amp * (0.35 + 0.55 * kick)).toFloat(), beatIdx)
    }
}

private class PeakHold {
    var peaks = DoubleArray(40)
    var lastT = 0.0
    fun update(vals: DoubleArray, t: Double): DoubleArray {
        val dt = if (lastT == 0.0) 0.016 else (t - lastT).coerceIn(0.004, 0.08)
        lastT = t
        if (peaks.size != vals.size) peaks = DoubleArray(vals.size)
        for (i in vals.indices) peaks[i] = if (vals[i] >= peaks[i]) vals[i] else max(0.0, peaks[i] - dt * 0.45)
        return peaks
    }
}

/** Ondulações disparadas por cada batida (anéis que se expandem e somem em ~1,1 s). */
private class BeatRipples {
    class Ripple(val t0: Double, val strength: Double)
    val ripples = ArrayList<Ripple>()
    private var lastBeat = Int.MIN_VALUE
    fun update(beat: Int, kick: Double, t: Double) {
        if (beat != lastBeat) {
            if (lastBeat != Int.MIN_VALUE && kick > 0.25) {
                ripples.add(Ripple(t, min(1.0, kick)))
                while (ripples.size > 4) ripples.removeAt(0)
            }
            lastBeat = beat
        }
        ripples.removeAll { t - it.t0 > 1.1 }
    }
}

// ============================================================ visualizador

@Composable
private fun SpectrumVisualizer(style: VisualizerStyle, vibrant: Color, vibrant2: Color, artworkURL: String, playing: Boolean, trackId: String, modifier: Modifier) {
    DisposableEffect(Unit) { AudioSpectrum.acquire(); onDispose { AudioSpectrum.release() } }
    val dark = LocalDark.current
    val ctx = LocalContext.current
    val saver = remember { (ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isPowerSaveMode == true }
    val rich = !saver
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val lstate by lifecycle.currentStateAsState()
    val active = lstate.isAtLeast(Lifecycle.State.STARTED)
    val live = AudioSpectrum.isLive
    val paused = !active || (!playing && !live)

    val builder = remember { SpectrumFrameBuilder() }
    val peaks = remember { PeakHold() }
    val ripples = remember { BeatRipples() }
    var tick by remember { mutableFloatStateOf(0f) }
    var kickState by remember { mutableFloatStateOf(0f) }
    val textColor = Theme.text
    val interval = if (saver) 33_000_000L else 15_000_000L

    LaunchedEffect(paused, playing, trackId) {
        if (paused) { builder.update(System.nanoTime(), playing, trackId); kickState = 0f; tick += 1f; return@LaunchedEffect }
        var last = 0L
        while (true) {
            val now = withFrameNanos { it }
            if (now - last < interval) continue
            last = now
            val f = builder.update(System.nanoTime(), playing, trackId)
            ripples.update(f.beat, f.kick.toDouble(), now / 1e9)
            kickState = f.kick
            tick += 1f
        }
    }

    Box(modifier) {
        if (style == VisualizerStyle.ORB) {
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val d = min(maxWidth.value, maxHeight.value) * 0.5f
                Box(Modifier.align(Alignment.Center).size((d * 1.5f).dp), contentAlignment = Alignment.Center) {
                    Canvas(Modifier.fillMaxSize().graphicsLayer { scaleX = 1 + kickState * 0.06f; scaleY = 1 + kickState * 0.06f }) {
                        val r = size.minDimension / 2
                        drawCircle(Brush.radialGradient(listOf(vibrant.copy(0.55f), Color.Transparent), center, r), r)   // brilho barato
                    }
                    ArtworkImage(artworkURL, Modifier.size(d.dp).graphicsLayer { scaleX = 1 + kickState * 0.06f; scaleY = 1 + kickState * 0.06f }, shape = CircleShape)
                }
            }
        }
        Canvas(Modifier.fillMaxSize()) {
            tick.let { }
            val f = builder.frame
            val t = System.nanoTime() / 1e9
            val g = DrawCtx(this, vibrant, vibrant2, dark, rich, textColor, ripples.ripples)
            when (style) {
                VisualizerStyle.AURORA -> g.drawBars(size.width, size.height, f, t, peaks)
                VisualizerStyle.ORB, VisualizerStyle.SOLAR_RING -> g.drawOrb(size.width, size.height, f, t)
                VisualizerStyle.OSCILLOSCOPE -> g.drawOscilloscope(size.width, size.height, f, t)
                VisualizerStyle.NEBULA -> g.drawNebula(size.width, size.height, f, t)
                else -> g.drawLiquid(size.width, size.height, f, t)
            }
        }
    }
}

private class DrawCtx(
    val s: DrawScope, val vibrant: Color, val vibrant2: Color, val dark: Boolean, val rich: Boolean, val text: Color,
    val ripples: List<BeatRipples.Ripple>,
) {
    val d = s.density

    /** Interpola as 24 bandas em [count] amostras suaves. */
    fun resample(b: FloatArray, count: Int, mirror: Boolean = false): DoubleArray {
        if (b.size <= 1) return DoubleArray(count)
        return DoubleArray(count) { i ->
            var u = i.toDouble() / (count - 1)
            if (mirror) u = abs(u - 0.5) * 2
            val x = u * (b.size - 1)
            val i0 = x.toInt(); val i1 = min(b.size - 1, i0 + 1)
            val fr = x - i0
            val sm = fr * fr * (3 - 2 * fr)
            b[i0] * (1 - sm) + b[i1] * sm
        }
    }

    private fun hsv(h: Float, sat: Float, v: Float) = Color.hsv(h * 360f, sat, v)

    // ---- Ondas Líquidas (vidro iridescente)
    fun drawLiquid(w: Float, h: Float, f: SpectrumFrame, t: Double) {
        val kick = f.kick.toDouble(); val level = f.level.toDouble(); val bass = f.bass.toDouble()
        val mid = h * 0.5f
        val samples = if (rich) 84 else 48
        val vals = resample(f.bands, samples, true)
        val maxAmp = h * 0.36f

        if (kick > 0.02) {
            val r = w * (0.42f + 0.22f * kick.toFloat())
            val k = kick.toFloat()
            s.drawOval(
                Brush.radialGradient(listOf(vibrant.copy((if (dark) 0.26f else 0.18f) * k), vibrant2.copy(0.08f * k), Color.Transparent), Offset(w / 2, mid), r),
                Offset(w / 2 - r, mid - r * 0.55f), Size(2 * r, r * 1.1f),
            )
        }
        for (rp in ripples) {
            val age = (t - rp.t0) / 1.1
            if (age < 0 || age >= 1) continue
            val rr = w * (0.10f + 0.55f * age.toFloat())
            s.drawOval(
                (if (dark) Color.White else vibrant).copy((0.30 * rp.strength * (1 - age)).toFloat()),
                Offset(w / 2 - rr, mid - rr * 0.34f), Size(2 * rr, rr * 0.68f), style = Stroke(((1.2 + 1.8 * (1 - age)) * d).toFloat()),
            )
        }

        val ribbonColors = listOf(vibrant, hsv(0.92f, 0.72f, 1f), hsv(0.74f, 0.66f, 1f), hsv(0.55f, 0.70f, 1f), hsv(0.07f, 0.66f, 1f))
        val layers = if (rich) 5 else 3
        val blend = if (dark) BlendMode.Screen else BlendMode.SrcOver
        for (layer in 0 until layers) {
            val li = layer.toDouble()
            val speed = 0.30 + 0.14 * li
            val k1 = 1.0 + 0.30 * li; val k2 = 2.1 + 0.45 * li
            val phase = li * 1.9
            val amp = maxAmp * (0.30 + 0.30 * level + 0.40 * kick) * (1.0 - 0.12 * li)
            val topX = FloatArray(samples); val topY = FloatArray(samples); val botY = FloatArray(samples)
            for (i in 0 until samples) {
                val u = i.toDouble() / (samples - 1)
                topX[i] = (w * u).toFloat()
                val env = sin(u * PI).pow(2.2)
                val carrier = 0.6 * sin(2 * PI * (u * k1 + t * speed * 0.5) + phase) + 0.4 * sin(2 * PI * (u * k2 - t * speed * 0.35) + phase * 0.7)
                val energy = min(1.25, 0.25 + 0.9 * vals[i] + 0.3 * bass)
                val a = amp * env * energy
                val center = a * 0.35 * carrier
                topY[i] = (mid + center - a).toFloat()
                botY[i] = (mid + center + a * 0.55).toFloat()
            }
            val ribbon = Path()
            ribbon.moveTo(topX[0], topY[0])
            for (i in 1 until samples) ribbon.lineTo(topX[i], topY[i])
            for (i in samples - 1 downTo 0) ribbon.lineTo(topX[i], botY[i])
            ribbon.close()
            val edge = Path()
            edge.moveTo(topX[0], topY[0])
            for (i in 1 until samples) edge.lineTo(topX[i], topY[i])

            val col = ribbonColors[layer % ribbonColors.size]
            val col2 = ribbonColors[(layer + 2) % ribbonColors.size]
            val fillA = (if (dark) 0.26 + 0.14 * kick else 0.30 + 0.14 * kick).toFloat()
            s.drawPath(ribbon, Brush.linearGradient(listOf(col.copy(0f), col, col2, col.copy(0f)), Offset(0f, mid), Offset(w, mid)), alpha = fillA, blendMode = blend)
            val edgeA = (if (dark) 0.55 + 0.35 * kick else 0.45 + 0.30 * kick).toFloat()
            s.drawPath(
                edge, Brush.linearGradient(listOf(Color.Transparent, (if (dark) Color.White else col2).copy(0.9f), Color.Transparent), Offset(0f, mid), Offset(w, mid)),
                alpha = edgeA, style = Stroke((if (layer == 0) 1.6f else 1.0f) * d, cap = StrokeCap.Round, join = StrokeJoin.Round), blendMode = blend,
            )
        }
    }

    // ---- Espectro (barras com peak-hold)
    fun drawBars(w: Float, h: Float, f: SpectrumFrame, t: Double, hold: PeakHold) {
        val count = 36
        val kick = f.kick.toDouble()
        val vals = resample(f.bands, count, true)
        val peaks = hold.update(vals, t)
        val gap = 4f * d
        val bw = max(2f, (w - gap * (count - 1)) / count)
        val mid = h * 0.60f
        val maxH = h * 0.44f * (1 + 0.08f * kick.toFloat())
        val cols = listOf(Color.White, vibrant, vibrant2)
        for (i in 0 until count) {
            val hh = max(3f * d, vals[i].toFloat() * maxH)
            val x = i * (bw + gap)
            val shade = Brush.linearGradient(cols, Offset(x, mid - maxH), Offset(x, mid))
            if (rich) {
                s.drawRoundRect(shade, Offset(x - 3 * d, mid - hh - 3 * d), Size(bw + 6 * d, hh + 6 * d), CornerRadius(bw / 2 + 3 * d), alpha = (0.16 + 0.3 * kick).toFloat())
            }
            s.drawRoundRect(shade, Offset(x, mid - hh), Size(bw, hh), CornerRadius(bw / 2))
            val ph = max(3f * d, peaks[i].toFloat() * maxH)
            s.drawRoundRect(Color.White.copy(0.9f), Offset(x, mid - ph - 5 * d), Size(bw, 2.5f * d), CornerRadius(1.25f * d))
            s.drawRoundRect(shade, Offset(x, mid + 6 * d), Size(bw, hh * 0.42f), CornerRadius(bw / 2), alpha = 0.22f)
        }
    }

    // ---- Orbe
    fun drawOrb(w: Float, h: Float, f: SpectrumFrame, t: Double) {
        val c = Offset(w / 2, h / 2)
        val kick = f.kick.toDouble()
        val base = min(w, h) * 0.27f * (1 + 0.05f * kick.toFloat())
        val count = if (rich) 96 else 64
        val vals = resample(f.bands, count / 2)
        val shade = Brush.sweepGradient(listOf(vibrant, Color.White, vibrant2, vibrant), c)
        for (rp in ripples) {
            val age = (t - rp.t0) / 1.1
            if (age < 0 || age >= 1) continue
            val rr = base * (1.1f + 0.9f * age.toFloat())
            s.drawCircle(Color.White.copy((0.4 * rp.strength * (1 - age)).toFloat()), rr, c, style = Stroke(((1.5 + 2.5 * (1 - age)) * d).toFloat()))
        }
        val rays = Path()
        for (i in 0 until count) {
            val k = if (i < count / 2) i else count - 1 - i
            val v = vals[k]
            val a = i.toDouble() / count * 2 * PI - PI / 2 + t * 0.12
            val r0 = base * 1.06
            val r1 = r0 + base * (0.08 + 0.75 * v)
            rays.moveTo((c.x + r0 * cos(a)).toFloat(), (c.y + r0 * sin(a)).toFloat())
            rays.lineTo((c.x + r1 * cos(a)).toFloat(), (c.y + r1 * sin(a)).toFloat())
        }
        if (rich) s.drawPath(rays, shade, alpha = (0.22 + 0.3 * kick).toFloat(), style = Stroke(6f * d, cap = StrokeCap.Round))
        s.drawPath(rays, shade, style = Stroke(2.6f * d, cap = StrokeCap.Round))

        val ring = Path()
        for (i in 0..72) {
            val u = i / 72.0
            val a = u * 2 * PI - t * 0.22
            val v = vals[i % vals.size]
            val rr = base * (1.28 + 0.12 * v + 0.10 * kick + 0.04 * sin(a * 6 + t * 2))
            val x = (c.x + rr * cos(a)).toFloat(); val y = (c.y + rr * sin(a)).toFloat()
            if (i == 0) ring.moveTo(x, y) else ring.lineTo(x, y)
        }
        ring.close()
        s.drawPath(ring, Color.White.copy((0.35 + 0.4 * kick).toFloat()), style = Stroke(1.4f * d))
        // anel da capa (o Orbe mostra a capa por baixo): contorno fino que acompanha o kick
        val ad = min(w, h) * 0.5f
        s.drawCircle(Color.White.copy((0.3 + 0.4 * kick).toFloat()), ad / 2, c, style = Stroke(1f * d))
    }

    // ---- Osciloscópio
    fun drawOscilloscope(w: Float, h: Float, f: SpectrumFrame, t: Double) {
        val mid = h * 0.5f
        val kick = f.kick.toDouble()
        val grid = Path()
        for (gx in 1 until 6) {
            val x = w * gx / 6f
            grid.moveTo(x, h * 0.14f); grid.lineTo(x, h * 0.86f)
        }
        s.drawPath(grid, text.copy(0.06f), style = Stroke(0.8f * d))
        s.drawLine(text.copy(0.10f), Offset(0f, mid), Offset(w, mid), 1f * d)

        val vals = resample(f.bands, if (rich) 96 else 64, true)
        val grad = listOf(Theme.sky, Theme.lavender, Color.White, Theme.rose, Theme.peach)
        for (layer in 0 until 2) {
            val wave = Path()
            val phase = if (layer == 0) t * 4.5 else -t * 3.2 + 1.4
            val ampScale = (if (layer == 0) 0.36 else 0.22) * (1 + 0.5 * kick)
            for (i in vals.indices) {
                val u = i.toDouble() / (vals.size - 1)
                val x = (w * u).toFloat()
                val env = sin(u * PI)
                val carrier = sin(u * PI * (if (layer == 0) 8.0 else 12.0) + phase)
                val y = (mid + carrier * vals[i] * env * h * ampScale).toFloat()
                if (i == 0) wave.moveTo(x, y) else wave.lineTo(x, y)
            }
            val shade = Brush.horizontalGradient(grad, 0f, w)
            if (layer == 0 && rich) s.drawPath(wave, shade, alpha = (0.22 + 0.3 * kick).toFloat(), style = Stroke(8f * d, cap = StrokeCap.Round))
            s.drawPath(wave, shade, style = Stroke((if (layer == 0) 2.4f else 1.4f) * d, cap = StrokeCap.Round))
        }
    }

    // ---- Nebulosa
    fun drawNebula(w: Float, h: Float, f: SpectrumFrame, t: Double) {
        val vals = resample(f.bands, if (rich) 64 else 40)
        val bass = f.bass.toDouble(); val kick = f.kick.toDouble()
        val colors = listOf(vibrant, vibrant2, Theme.sky, Theme.rose)
        val blend = if (dark) BlendMode.Plus else BlendMode.SrcOver
        for (ribbon in 0 until 4) {
            val path = Path()
            val baseY = h * (0.28 + 0.14 * ribbon)
            for (i in vals.indices) {
                val u = i.toDouble() / (vals.size - 1)
                val x = (w * u).toFloat()
                val lift = vals[i] * h * 0.22 * sin(u * PI) * (1 + 0.4 * kick)
                val wave = sin(u * 6.0 + t * (1.2 + ribbon * 0.35) + ribbon) * (14 + 28 * bass) * d
                val y = (baseY - lift + wave).toFloat()
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            val col = colors[ribbon % colors.size]
            if (rich) s.drawPath(path, col, alpha = (0.10 + 0.12 * kick).toFloat(), style = Stroke(26f * d, cap = StrokeCap.Round), blendMode = blend)
            s.drawPath(path, col, alpha = (0.30 + 0.25 * kick).toFloat(), style = Stroke(9f * d, cap = StrokeCap.Round), blendMode = blend)
            s.drawPath(path, Color.White, alpha = 0.65f, style = Stroke(1.5f * d, cap = StrokeCap.Round), blendMode = blend)
        }
        // Estrelas que acendem na batida
        for (st in 0 until 28) {
            val sx = w * ((st * 37) % 100) / 100f
            val sy = h * ((st * 73 + 19) % 100) / 100f
            val twinkle = 0.5 + 0.5 * sin(t * 1.3 + st * 2.4)
            val pulse = ((1.5 + 2.0 * twinkle + 4.0 * kick * ((st % 3) + 1) / 3) * d).toFloat()
            s.drawOval(Color.White.copy((0.35 + 0.25 * twinkle + 0.4 * kick).toFloat().coerceIn(0f, 1f)), Offset(sx - pulse / 2, sy - pulse / 2), Size(pulse, pulse))
        }
    }
}
