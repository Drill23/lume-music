package com.adriano.lumemusic.ui.stage

import android.graphics.Bitmap
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Autorenew
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.R
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.audio.AudioSpectrum
import com.adriano.lumemusic.audio.PlaybackClock
import com.adriano.lumemusic.data.ArtworkStore
import com.adriano.lumemusic.data.CassetteStyle
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.PlayerSurfaceTab
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.screens.PlayerStage
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.reduceMotion
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/** Palco "K7" (CassetteView.swift): fita em primeiro plano com camadas pré-renderizadas, carretéis animados, flip A/B e VU. */
object CassetteStage : PlayerStage {
    override val tab = PlayerSurfaceTab.CASSETTE

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) = CassetteStageContent(track, artwork, modifier)
}

internal val HandFont = FontFamily(Font(R.font.kalam_bold, FontWeight.Bold))

/** Posição "ao vivo" da fita: extrapola o relógio entre as atualizações do player. */
private class LiveAnchor { @Volatile var time = 0.0; @Volatile var nanos = System.nanoTime() }

@Composable
private fun CassetteStageContent(track: Track, artwork: String, modifier: Modifier) {
    val store = LibraryStore
    var sideB by remember(track.id) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    DisposableEffect(Unit) { AudioSpectrum.acquire(); onDispose { AudioSpectrum.release() } }
    val style = store.cassetteStyle
    // aquece o outro lado para o flip não piscar
    LaunchedEffect(style) {
        val px = (380 * density.density).toInt()
        withContext(Dispatchers.Default) { StageTextures.cassetteLayers(style, true, px) }
    }

    BoxWithConstraints(modifier.fillMaxSize()) {
        val gw = maxWidth.value; val gh = maxHeight.value
        val availH = max(150f, gh - 44f - 40f)
        val w = min(min(gw - 28f, availH * TapeGeo.aspect), 420f)
        val flip by animateFloatAsState(if (sideB) 180f else 0f, spring(0.82f, 80f), label = "k7flip")
        val artBack = ArtworkStore.photo(track.artist) ?: artwork

        Column(Modifier.fillMaxSize().padding(bottom = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            Box(
                Modifier.size(w.dp, (w / TapeGeo.aspect).dp)
                    .graphicsLayer { rotationY = flip; cameraDistance = 2.2f * w / 160f }
                    .pointerInput(Unit) { detectTapGestures { Haptics.medium(); AudioPlayer.togglePlayPause() } },
            ) {
                if (flip < 90f) CassetteTape(w, track.title, track.artist, artwork, false, style, Modifier.fillMaxSize())
                else Box(Modifier.fillMaxSize().graphicsLayer { rotationY = 180f }) { CassetteTape(w, track.title, track.artist, artBack, true, style, Modifier.fillMaxSize()) }
            }
            Spacer(Modifier.height(18.dp))
            Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 66.dp).height(44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val shape = RoundedCornerShape(50)
                Row(
                    Modifier.defaultMinSize(minWidth = 108.dp, minHeight = 44.dp).glass(shape).pressable(0.94f) {
                        Haptics.medium()
                        scope.launch { ArtworkStore.ensurePhoto(track.artist) }
                        sideB = !sideB
                    }.padding(horizontal = 14.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(Icons.Rounded.Autorenew, if (sideB) "Virar para o lado A" else "Virar para o lado B", tint = StageText, modifier = Modifier.size(17.dp))
                    Text(if (sideB) "Lado A" else "Lado B", style = Theme.font(13.5f, FontWeight.SemiBold, StageText), modifier = Modifier.padding(start = 6.dp), maxLines = 1)
                }
                VUDock(Modifier.weight(1f).defaultMinSize(minWidth = 100.dp))
            }
        }

        StageStyleOrb(icon = "recordingtape", desc = "Estilo da fita K7") {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(bottom = 4.dp)) {
                StageSectionHeader("FITA", store.cassetteStyle.raw)
                for (st in CassetteStyle.entries) {
                    StageOptionRow(st.raw, subtitleFor(st), store.cassetteStyle == st, { store.cassetteStyle = st }) {
                        Box(Modifier.fillMaxSize().clip(CircleShape).background(swatchFor(st)).border(0.8.dp, Color.White.copy(0.45f), CircleShape))
                    }
                }
            }
        }
    }
}

private fun subtitleFor(s: CassetteStyle) = when (s) {
    CassetteStyle.SMOKED_STUDIO -> "Plástico fumê, engrenagens à vista"
    CassetteStyle.CRYSTAL_CLEAR -> "Transparente, mecanismo visível"
    CassetteStyle.METALLIC_CHROME -> "Cromo Tipo II, acabamento espelhado"
    CassetteStyle.VINTAGE_CREAM -> "Creme dos anos 80"
}

private fun swatchFor(s: CassetteStyle): Brush = when (s) {
    CassetteStyle.SMOKED_STUDIO -> Brush.verticalGradient(listOf(G(0.34f), G(0.08f)))
    CassetteStyle.CRYSTAL_CLEAR -> Brush.verticalGradient(listOf(Color(0.85f, 0.93f, 0.97f), Color(0.55f, 0.68f, 0.78f)))
    CassetteStyle.METALLIC_CHROME -> Brush.verticalGradient(listOf(G(0.95f), G(0.45f)))
    CassetteStyle.VINTAGE_CREAM -> Brush.verticalGradient(listOf(Color(0.96f, 0.92f, 0.80f), Color(0.80f, 0.72f, 0.56f)))
}

// ============================================================ VU analógico (dois mostradores)

/** Balística física de agulha (ataque rápido, decaimento suave sem jitter). */
private class VUBallistics {
    var l = 0.0; var r = 0.0
    private var last = 0L
    fun step(nowNanos: Long, tl: Double, tr: Double) {
        val dt = if (last == 0L) 0.016 else ((nowNanos - last) / 1e9).coerceIn(0.004, 0.08)
        last = nowNanos
        val tauL = if (tl > l) 0.045 else 0.24
        val tauR = if (tr > r) 0.045 else 0.24
        l += (tl - l) * (1 - exp(-dt / tauL))
        r += (tr - r) * (1 - exp(-dt / tauR))
    }
}

@Composable
private fun VUDock(modifier: Modifier) {
    val density = LocalDensity.current
    val playing = AudioPlayer.isPlaying
    val phys = remember { VUBallistics() }
    var tick by remember { mutableFloatStateOf(0f) }
    var level by remember { mutableStateOf(0.0 to 0.0) }
    val playingNow by rememberUpdatedState(playing)
    LaunchedEffect(playing) {
        if (!playing) { phys.l = 0.0; phys.r = 0.0; tick += 1f; return@LaunchedEffect }
        var lastFrame = 0L
        while (true) {
            val now = withFrameNanos { it }
            if (now - lastFrame < 32_000_000L) continue
            lastFrame = now
            val raw = vuLevels(now / 1e9, playingNow)
            phys.step(now, raw.first, raw.second)
            level = phys.l to phys.r
            tick += 1f
        }
    }
    BoxWithConstraints(modifier.height(44.dp).glass(RoundedCornerShape(50)), contentAlignment = Alignment.Center) {
        val w = min(64f, (maxWidth.value - 30f) / 2f)
        val h = w * 0.62f
        val face by androidx.compose.runtime.produceState<Bitmap?>(null, (w * density.density).roundToInt()) {
            value = withContext(Dispatchers.Default) { StageTextures.vuFace((w * density.density).roundToInt().coerceAtLeast(8)) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Dial(face, w, h, level.first)
            Dial(face, w, h, level.second)
        }
    }
}

private fun vuLevels(t: Double, playing: Boolean): Pair<Double, Double> {
    if (AudioSpectrum.isLive) {
        val b = AudioSpectrum.bands
        val half = max(1, b.size / 2)
        val low = b.take(half).sum() / half
        val high = b.takeLast(half).sum() / half
        val l = 0.06 + AudioSpectrum.level * 0.58 + low * 0.22
        val r = 0.06 + AudioSpectrum.level * 0.58 + high * 0.26
        return min(1.0, l) to min(1.0, r)
    }
    if (!playing) return 0.0 to 0.0
    val base = 0.55 + 0.20 * sin(t * 2.3) * cos(t * 0.7)
    val l = base + 0.16 * sin(t * 9.1) + 0.08 * sin(t * 17.3)
    val r = base + 0.16 * sin(t * 8.3 + 1) + 0.08 * cos(t * 15.1)
    return min(1.0, max(0.0, l)) to min(1.0, max(0.0, r))
}

@Composable
private fun Dial(face: Bitmap?, w: Float, h: Float, level: Double) {
    val img = remember(face) { face?.asImageBitmap() }
    Canvas(Modifier.size(w.dp, h.dp).clip(RoundedCornerShape((h * 0.16f).dp))) {
        val pw = size.width; val ph = size.height
        if (img != null) drawImage(img, dstSize = androidx.compose.ui.unit.IntSize(pw.roundToInt(), ph.roundToInt()), filterQuality = FilterQuality.Medium)
        val lv = level.coerceIn(0.0, 1.0).toFloat()
        val needleW = 1.3f * density
        rotate(-48f + 96f * lv, Offset(pw / 2, ph)) {
            drawRoundRect(Color.Black.copy(0.85f), Offset(pw / 2 - needleW / 2, ph - ph * 0.80f), Size(needleW, ph * 0.80f), CornerRadius(needleW / 2))
        }
        drawCircle(Color.Black.copy(0.85f), ph * 0.10f / 2, Offset(pw / 2, ph * 0.99f))
        drawCircle(if (lv > 0.84f) Color.Red else Color.Red.copy(0.2f), ph * 0.09f / 2, Offset(pw * 0.88f, ph * 0.84f))
    }
}

// ============================================================ fita K7

@Composable
fun CassetteTape(
    w: Float, title: String, artist: String, artworkURL: String, sideB: Boolean, style: CassetteStyle, modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val h = w / TapeGeo.aspect
    val px = (w * density.density).roundToInt()
    var layers by remember(style, sideB, px) { mutableStateOf(StageTextures.cachedCassette(style, sideB, px)) }
    LaunchedEffect(style, sideB, px) {
        if (layers == null) layers = withContext(Dispatchers.Default) { StageTextures.cassetteLayers(style, sideB, px) }
    }
    val parts by androidx.compose.runtime.produceState<Pair<Bitmap, Bitmap>?>(null) {
        value = withContext(Dispatchers.Default) { StageTextures.hub() to StageTextures.pack() }
    }
    val L = layers
    Box(modifier.size(w.dp, h.dp)) {
        if (L != null) {
            val sw = w * (1 + 2 * TapeGeo.shadowMarginX)
            val sh = h + w * (TapeGeo.shadowMarginTop + TapeGeo.shadowMarginBottom)
            Image(
                L.shadow.asImageBitmap(), null,
                Modifier.offset(x = (-(w * TapeGeo.shadowMarginX)).dp, y = (-(w * TapeGeo.shadowMarginTop)).dp).wrapContentSize(Alignment.TopStart, unbounded = true).requiredSize(sw.dp, sh.dp),
                contentScale = androidx.compose.ui.layout.ContentScale.FillBounds,
            )
            Image(L.back.asImageBitmap(), null, Modifier.size(w.dp, h.dp))
            parts?.let { (hub, pack) -> Reels(w, h, hub, pack) }
            Image(L.front.asImageBitmap(), null, Modifier.size(w.dp, h.dp))
            LabelText(w, title, artist, artworkURL, sideB)
        } else {
            Box(Modifier.size(w.dp, h.dp).clip(RoundedCornerShape((w * 0.034f).dp)).background(Color.White.copy(0.08f)))
        }
    }
}

/** Carretéis: a única parte que anima (raio pelo progresso, ω = k/raio, fita entre rolos e roletes). */
@Composable
private fun Reels(w: Float, h: Float, hub: Bitmap, pack: Bitmap) {
    val playing = AudioPlayer.isPlaying
    val reduce = reduceMotion()
    val hubImg = remember(hub) { hub.asImageBitmap() }
    val packImg = remember(pack) { pack.asImageBitmap() }
    val anchor = remember { LiveAnchor() }
    var aL by remember { mutableFloatStateOf(0f) }
    var aR by remember { mutableFloatStateOf(0f) }
    var live by remember { mutableFloatStateOf(0f) }
    var tick by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) {
        snapshotFlow { PlaybackClock.currentTime }.collect { anchor.time = it; anchor.nanos = System.nanoTime() }
    }
    LaunchedEffect(playing, reduce) {
        anchor.time = PlaybackClock.currentTime; anchor.nanos = System.nanoTime()
        if (!playing) return@LaunchedEffect
        var last = 0L
        var lastFrame = 0L
        val frameGap = if (reduce) 1_000_000_000L else 32_000_000L
        while (true) {
            val now = withFrameNanos { it }
            if (now - lastFrame < frameGap) continue
            lastFrame = now
            val dur = max(1.0, PlaybackClock.duration)
            val t = anchor.time + (System.nanoTime() - anchor.nanos) / 1e9
            val p = (t / dur).coerceIn(0.0, 1.0).toFloat()
            live = p
            val dt = if (last == 0L) 0f else min(0.1f, (now - last) / 1e9f)
            last = now
            if (!reduce) {
                val (rl, rr) = reelRadii(p)
                aL -= 14f / max(0.03f, rl) * dt
                aR -= 14f / max(0.03f, rr) * dt
            }
            tick += 1f
        }
    }
    Canvas(Modifier.size(w.dp, h.dp)) {
        tick.let { }
        val dur = max(1.0, PlaybackClock.duration)
        val p = if (playing) live else (PlaybackClock.currentTime / dur).coerceIn(0.0, 1.0).toFloat()
        val (rL, rR) = reelRadii(p)
        val cL = Offset(TapeGeo.reelLx * w * density, TapeGeo.reelLy * w * density)
        val cR = Offset(TapeGeo.reelRx * w * density, TapeGeo.reelRy * w * density)
        val s = w * density
        val tape = Color(0.30f, 0.18f, 0.10f)
        drawTape(w, rL, rR, tape)
        for ((c, r) in listOf(cL to rL, cR to rR)) {
            val d = (r * 2 * s).roundToInt()
            drawImage(packImg, dstOffset = androidx.compose.ui.unit.IntOffset((c.x - d / 2f).roundToInt(), (c.y - d / 2f).roundToInt()), dstSize = androidx.compose.ui.unit.IntSize(d, d), filterQuality = FilterQuality.Medium)
        }
        val hd = (TapeGeo.hubR * 2 * s).roundToInt()
        rotate(aL, cL) { drawImage(hubImg, dstOffset = androidx.compose.ui.unit.IntOffset((cL.x - hd / 2f).roundToInt(), (cL.y - hd / 2f).roundToInt()), dstSize = androidx.compose.ui.unit.IntSize(hd, hd), filterQuality = FilterQuality.Medium) }
        rotate(aR, cR) { drawImage(hubImg, dstOffset = androidx.compose.ui.unit.IntOffset((cR.x - hd / 2f).roundToInt(), (cR.y - hd / 2f).roundToInt()), dstSize = androidx.compose.ui.unit.IntSize(hd, hd), filterQuality = FilterQuality.Medium) }
    }
}

/** Raio do rolo esquerdo (esvazia) e direito (enche) pelo progresso: área da fita se conserva. */
private fun reelRadii(p: Float): Pair<Float, Float> {
    val a = TapeGeo.rFull * TapeGeo.rFull - TapeGeo.rEmpty * TapeGeo.rEmpty
    val q = p.coerceIn(0f, 1f)
    return sqrt(TapeGeo.rFull * TapeGeo.rFull - q * a) to sqrt(TapeGeo.rEmpty * TapeGeo.rEmpty + q * a)
}

/** Fita saindo de cada rolo (tangente) até os roletes guia. */
private fun DrawScope.drawTape(w: Float, rL: Float, rR: Float, color: Color) {
    fun tangent(px: Float, py: Float, cx: Float, cy: Float, r: Float, sign: Float): Offset {
        val dx = px - cx; val dy = py - cy
        val d = max(r + 0.001f, hypot(dx, dy))
        val beta = atan2(dy, dx)
        val alpha = acos(min(1f, r / d))
        val t = beta + sign * alpha
        return Offset(cx + r * cos(t), cy + r * sin(t))
    }
    val s = w * density
    val tL = tangent(TapeGeo.rollerLx - 0.016f, TapeGeo.rollerLy, TapeGeo.reelLx, TapeGeo.reelLy, rL, 1f)
    val tR = tangent(TapeGeo.rollerRx + 0.016f, TapeGeo.rollerRy, TapeGeo.reelRx, TapeGeo.reelRy, rR, -1f)
    val sw = max(1f, w * 0.0055f) * density
    drawLine(color, Offset(tL.x * s, tL.y * s), Offset((TapeGeo.rollerLx - 0.016f) * s, TapeGeo.rollerLy * s), sw, StrokeCap.Round)
    drawLine(color, Offset(tR.x * s, tR.y * s), Offset((TapeGeo.rollerRx + 0.016f) * s, TapeGeo.rollerRy * s), sw, StrokeCap.Round)
}

// ============================================================ escrita à mão na etiqueta

@Composable
private fun LabelText(w: Float, title: String, artist: String, artworkURL: String, sideB: Boolean) {
    val main = if (sideB) artist else title
    val sub = if (sideB) title else artist
    val measurer = rememberTextMeasurer()
    val h = w / TapeGeo.aspect
    Box(Modifier.size(w.dp, h.dp)) {
        HandLine(measurer, main, w * 0.054f, Color(0.10f, 0.14f, 0.46f), w * 0.69f, -0.7f, w * 0.430f, w * 0.133f)
        HandLine(measurer, sub, w * 0.040f, Color(0.16f, 0.18f, 0.40f, 0.85f), w * 0.69f, -0.5f, w * 0.430f, w * 0.172f)
        ArtworkImage(
            artworkURL, Modifier.offset(x = (w * 0.873f - w * 0.039f).dp, y = (w * 0.147f - w * 0.039f).dp).size((w * 0.078f).dp),
            cornerRadius = (w * 0.004f).dp, icon = if (sideB) "person.fill" else "music.note",
        )
    }
}

/** Uma linha manuscrita centrada em (cx, cy) na largura [maxW], alinhada à esquerda e reduzida até 50% para caber. */
@Composable
private fun HandLine(measurer: TextMeasurer, text: String, size: Float, color: Color, maxW: Float, rot: Float, cx: Float, cy: Float) {
    val density = LocalDensity.current
    val fit = remember(text, size, maxW) {
        val base = measurer.measure(text, TextStyle(fontFamily = HandFont, fontWeight = FontWeight.Bold, fontSize = (size).sp), maxLines = 1, softWrap = false)
        val tw = base.size.width / density.density
        if (tw <= maxW) 1f else max(0.5f, maxW / tw)
    }
    Box(Modifier.offset(x = (cx - maxW / 2).dp, y = (cy - size).dp).width(maxW.dp).height((size * 2).dp).graphicsLayer { rotationZ = rot }, contentAlignment = Alignment.CenterStart) {
        Text(text, style = TextStyle(fontFamily = HandFont, fontWeight = FontWeight.Bold, fontSize = (size * fit).sp, color = color), maxLines = 1, softWrap = false)
    }
}
