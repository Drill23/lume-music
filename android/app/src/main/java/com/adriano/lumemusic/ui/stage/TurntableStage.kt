package com.adriano.lumemusic.ui.stage

import android.graphics.Bitmap
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.drag
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.audio.PlaybackClock
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.PlayerSurfaceTab
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.data.TurntableFinish
import com.adriano.lumemusic.data.VinylEdition
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.screens.PlayerStage
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.reduceMotion
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Palco "Vinil" (TurntableView.swift): deck estático pré-renderizado + prato/disco que só giram + braço que só roda. */
object VinylStage : PlayerStage {
    override val tab = PlayerSurfaceTab.VINYL

    @Composable
    override fun Content(track: Track, artwork: String, modifier: Modifier) = TurntableStage(track, artwork, modifier)
}

internal fun spF(v: Float) = TextUnit(v, TextUnitType.Sp)

@Composable
private fun TurntableStage(track: Track, artwork: String, modifier: Modifier) {
    val store = LibraryStore
    var rpm45 by remember { mutableStateOf(false) }
    var pitch by remember { mutableFloatStateOf(0f) }
    val playing = AudioPlayer.isPlaying
    val progressQ by remember { derivedStateOf { val d = PlaybackClock.duration; if (d > 0) ((PlaybackClock.currentTime / d).coerceIn(0.0, 1.0) * 400).roundToInt() else 0 } }

    BoxWithConstraints(modifier.fillMaxSize()) {
        val gw = maxWidth.value
        val gh = maxHeight.value
        val thick = if (store.turntable3D) 0.035f else 0f
        val availH = max(170f, gh - 44f - 36f)
        val w = min(min(gw - 24f, availH / (1 + thick) * DeckGeo.aspect), 520f)
        val h = w / DeckGeo.aspect

        Column(Modifier.fillMaxSize().padding(bottom = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            TurntableDeck(
                h = h, artwork = artwork, playing = playing, progressQ = progressQ, finish = store.turntableFinish, edition = store.vinylEdition,
                is3D = store.turntable3D, rpm45 = rpm45, pitch = pitch, modifier = Modifier.size(w.dp, (h * (1 + thick)).dp),
            )
            Spacer(Modifier.height(14.dp))
            Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 66.dp).height(44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SpeedPicker(rpm45) { rpm45 = it }
                PlayDockButton(playing)
                PitchSlider(pitch, Modifier.weight(1f).defaultMinSize(minWidth = 80.dp)) { v ->
                    pitch = v
                    AudioPlayer.setVarispeed(1f + v * 0.08f)
                }
            }
        }

        StageStyleOrb(icon = "slider.horizontal.3", desc = "Personalizar toca-discos") { TurntablePanel() }
    }
}

// ============================================================ doca

@Composable
private fun SpeedPicker(rpm45: Boolean, onChange: (Boolean) -> Unit) {
    val shape = RoundedCornerShape(50)
    val x by animateDpAsState(if (rpm45) 50.dp else 0.dp, spring(0.8f, 330f), label = "speed")
    Box(Modifier.height(50.dp).glass(shape).padding(3.dp)) {
        Box(Modifier.offset(x = x).size(48.dp, 44.dp).clip(shape).background(Theme.prismDiagonal))
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            for ((label, is45) in listOf("33⅓" to false, "45" to true)) {
                val active = rpm45 == is45
                Box(Modifier.size(48.dp, 44.dp).clip(shape).pressable(0.94f) { if (!active) { Haptics.medium(); onChange(is45) } }, contentAlignment = Alignment.Center) {
                    Text(label, style = Theme.font(14f, FontWeight.Bold, if (active) Theme.onPrism else StageText))
                }
            }
        }
    }
}

@Composable
private fun PlayDockButton(playing: Boolean) {
    val shape = RoundedCornerShape(50)
    Row(
        Modifier.defaultMinSize(minWidth = 84.dp, minHeight = 44.dp).glass(shape, if (playing) Theme.mint.copy(0.35f) else null)
            .pressable(0.94f) { Haptics.medium(); AudioPlayer.togglePlayPause() }.padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        Icon(sf(if (playing) "pause.fill" else "play.fill"), if (playing) "Parar o disco" else "Iniciar o disco", tint = StageText, modifier = Modifier.size(18.dp))
        Text(if (playing) "Parar" else "Iniciar", style = Theme.font(13.5f, FontWeight.SemiBold, StageText), modifier = Modifier.padding(start = 6.dp), maxLines = 1)
    }
}

@Composable
private fun PitchSlider(value: Float, modifier: Modifier, onChange: (Float) -> Unit) {
    val shape = RoundedCornerShape(50)
    val cur by rememberUpdatedState(value)
    BoxWithConstraints(
        modifier.height(44.dp).glass(shape)
            .pointerInput(Unit) { detectTapGestures(onDoubleTap = { Haptics.medium(); onChange(0f) }) }
            .pointerInput(Unit) {
                val pad = 18.dp.toPx()
                fun nv(x: Float): Float {
                    val trackW = max(1f, size.width - pad * 2)
                    var v = ((x - pad) / trackW * 2 - 1).coerceIn(-1f, 1f)
                    if (abs(v) < 0.07f) v = 0f
                    return v
                }
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    fun apply(x: Float) { val v = nv(x); if ((v == 0f) != (cur == 0f)) Haptics.medium(); onChange(v) }
                    apply(down.position.x)
                    drag(down.id) { apply(it.position.x); it.consume() }
                }
            },
    ) {
        val pad = 18.dp
        val trackW = maxWidth - pad * 2
        val x = pad + trackW * ((value + 1f) / 2f)
        val mid = pad + trackW / 2
        // trilho
        Box(Modifier.padding(horizontal = pad).align(Alignment.BottomStart).padding(bottom = 10.dp).fillMaxWidth().height(4.dp).clip(CircleShape).background(Color.White.copy(0.18f)))
        // preenchimento a partir do centro
        Box(Modifier.align(Alignment.BottomStart).padding(bottom = 10.dp).offset(x = if (x < mid) x else mid).width(if (x > mid) x - mid else mid - x).height(4.dp).clip(CircleShape).background(Theme.prismDiagonal))
        // marca central
        Box(Modifier.align(Alignment.BottomStart).padding(bottom = 6.dp).offset(x = mid - 0.75.dp).size(1.5.dp, 12.dp).background(Color.White.copy(0.55f)))
        // polegar
        Box(Modifier.align(Alignment.BottomStart).padding(bottom = 1.dp).offset(x = x - 11.dp).size(22.dp).shadow(3.dp, CircleShape).background(Color.White, CircleShape))
        Text(
            "PITCH %+.1f%%".format(value * 8), textAlign = TextAlign.Center,
            style = Theme.font(10.5f, FontWeight.ExtraBold, if (abs(value) < 0.02f) StageSecondary else Theme.rose, letterSpacing = spF(0.4f)),
            modifier = Modifier.align(Alignment.TopCenter).padding(top = 5.dp),
        )
    }
}

// ============================================================ painel de estilos

@Composable
private fun TurntablePanel() {
    val s = LibraryStore
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(bottom = 4.dp)) {
        StageSegmented(listOf(true to "3D Estúdio", false to "Vista Topo"), s.turntable3D) { s.turntable3D = it }
        StageSectionHeader("MESA", s.turntableFinish.raw)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            for (f in TurntableFinish.entries) {
                val bmp by produceState<Bitmap?>(null, f) { value = withContext(Dispatchers.Default) { StageTextures.surfaceFor(f) } }
                StageSwatch(s.turntableFinish == f, f.raw, { s.turntableFinish = f }) {
                    bmp?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Crop) }
                }
            }
        }
        StageSectionHeader("VINIL", s.vinylEdition.raw)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            for (e in VinylEdition.entries) {
                StageSwatch(s.vinylEdition == e, e.raw, { s.vinylEdition = e }) { VinylSwatch(e) }
            }
        }
    }
}

@Composable
private fun VinylSwatch(e: VinylEdition) {
    val brush = when (e) {
        VinylEdition.CLASSIC_BLACK -> Brush.radialGradient(listOf(G(0.30f), G(0.06f)), Offset.Zero, 40f * 2.2f)
        VinylEdition.PRISM_CRYSTAL -> Brush.sweepGradient(listOf(Color(0xFFFF2D55), Color(0xFFFF9500), Color(0xFFFFCC00), Color(0xFF00C7BE), Color(0xFF32ADE6), Color(0xFFAF52DE), Color(0xFFFF2D55)))
        VinylEdition.LIMITED_GOLD -> Brush.radialGradient(listOf(Color(0.98f, 0.82f, 0.40f), Color(0.58f, 0.38f, 0.10f)), Offset.Zero, 40f * 2.2f)
        VinylEdition.WHITE_MARBLE -> Brush.radialGradient(listOf(Color.White, G(0.78f)), Offset.Zero, 40f * 2.2f)
    }
    Box(Modifier.fillMaxSize().background(brush))
}

// ============================================================ deck

/** Física do prato: aceleração e desaceleração lineares com inércia (SpinModel). */
private class SpinModel {
    var velocity = 0f
    fun step(angle: Float, dt: Float, target: Float): Float {
        if (velocity < target) velocity = min(target, velocity + 320f * dt)
        else if (velocity > target) velocity = max(target, velocity - 130f * dt)
        var a = angle + velocity * dt
        if (a > 360_000f || a < -360_000f) a %= 360f
        return a
    }
}

@Composable
private fun TurntableDeck(
    h: Float, artwork: String, playing: Boolean, progressQ: Int, finish: TurntableFinish, edition: VinylEdition,
    is3D: Boolean, rpm45: Boolean, pitch: Float, modifier: Modifier,
) {
    val density = LocalDensity.current
    val reduce = reduceMotion()
    val w = h * DeckGeo.aspect
    val dens = density.density
    val platterPx = ((h * DeckGeo.platterD * dens / 2f).roundToInt()) * 2
    val basePx = (w * dens).roundToInt()
    val progress = progressQ / 400.0

    var baseBmp by remember { mutableStateOf<Bitmap?>(null) }
    var recBmp by remember { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(finish, edition, is3D, platterPx, basePx) {
        StageTextures.cachedDeck(finish, is3D, basePx)?.let { baseBmp = it }
        StageTextures.cachedRecord(edition, platterPx)?.let { recBmp = it }
        val (r, b) = withContext(Dispatchers.Default) { StageTextures.record(edition, platterPx) to StageTextures.deckBase(finish, is3D, basePx) }
        recBmp = r; baseBmp = b
    }
    val arm by produceState<ArmImages?>(null) { value = withContext(Dispatchers.Default) { StageTextures.arm() } }
    val sheen by produceState<Bitmap?>(null, edition) { value = withContext(Dispatchers.Default) { StageTextures.sheen(edition == VinylEdition.PRISM_CRYSTAL, 360) } }

    // ---- braço
    val armAngle = remember { Animatable(if (playing) DeckGeo.angle(progress).toFloat() else DeckGeo.restAngle.toFloat()) }
    val armLift = remember { Animatable(if (playing) 0f else 1f) }
    var scratching by remember { mutableStateOf(false) }
    var armFirst by remember { mutableStateOf(true) }
    val progressNow by rememberUpdatedState(progress)
    LaunchedEffect(playing) {
        if (armFirst) { armFirst = false; return@LaunchedEffect }
        if (playing) {
            launch { armAngle.animateTo(DeckGeo.angle(progressNow).toFloat(), tween(if (reduce) 200 else 1150, easing = FastOutSlowInEasing)) }
            delay(if (reduce) 150L else 980L)
            armLift.animateTo(0f, tween(500, easing = EaseOut))
        } else {
            launch { armLift.animateTo(1f, tween(280, easing = EaseOut)) }
            delay(240)
            armAngle.animateTo(DeckGeo.restAngle.toFloat(), tween(if (reduce) 200 else 1050, easing = FastOutSlowInEasing))
        }
    }
    LaunchedEffect(progressQ) {
        if (playing && armLift.value == 0f && !scratching) armAngle.animateTo(DeckGeo.angle(progress).toFloat(), tween(500, easing = LinearEasing))
    }

    // ---- prato (inércia; o relógio só roda enquanto o prato está em movimento)
    val spinAngle = remember { mutableFloatStateOf(0f) }
    val model = remember { SpinModel() }
    var spinActive by remember { mutableStateOf(playing && !reduce) }
    var scratchDelta by remember { mutableFloatStateOf(0f) }
    var scratchLast by remember { mutableStateOf<Float?>(null) }
    val degPerSec = (if (rpm45) 45f else 33.3333f) * 6f * (1 + pitch * 0.08f)
    val degPerSecNow by rememberUpdatedState(degPerSec)
    val spinTarget by rememberUpdatedState(if (playing && !scratching && !reduce) degPerSec else 0f)
    LaunchedEffect(playing) {
        if (playing) spinActive = !reduce else { delay(2800); if (!scratching) spinActive = false }
    }
    LaunchedEffect(spinActive, scratching) {
        if (!spinActive && !scratching) return@LaunchedEffect
        var last = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            val dt = min(0.1f, max(0f, (now - last) / 1e9f))
            last = now
            spinAngle.floatValue = model.step(spinAngle.floatValue, dt, spinTarget)
        }
    }

    Box(modifier) {
        val mx = DeckGeo.marginX * h; val mt = DeckGeo.marginTop * h; val mb = DeckGeo.marginBottom * h
        // base estática
        baseBmp?.let { Image(it.asImageBitmap(), null, Modifier.offset(x = (-mx).dp, y = (-mt).dp).size((w + 2 * mx).dp, (h + mt + mb).dp)) }

        // lâmpada do estroboscópio
        val lampA by animateFloatAsState(if (playing) 1f else 0f, tween(500), label = "lamp")
        Box(Modifier.offset(x = (1.17f * h - h * 0.09f).dp, y = (0.80f * h - h * 0.09f).dp).size((h * 0.18f).dp).graphicsLayer { alpha = lampA }) {
            Canvas(Modifier.fillMaxSize()) {
                drawCircle(Brush.radialGradient(listOf(Theme.peach.copy(0.85f), Theme.peach.copy(0f)), center, size.minDimension / 2), size.minDimension / 2)
                drawCircle(Color(1f, 0.85f, 0.7f), h * 0.010f * dens, center)
            }
        }

        // disco: arrastar = scratch, toque = tocar/pausar
        val dD = DeckGeo.platterD * h
        val labelD = DeckGeo.labelD * h
        Box(
            Modifier.offset(x = (DeckGeo.platterCx * h - dD / 2).dp, y = (DeckGeo.platterCy * h - dD / 2).dp).size(dD.dp)
                .pointerInput(Unit) { detectTapGestures { Haptics.medium(); AudioPlayer.togglePlayPause() } }
                .pointerInput(dens) {
                    detectDragGestures(
                        onDragStart = { scratchLast = null },
                        onDragEnd = {
                            val secs = scratchDelta / degPerSecNow
                            if (abs(secs) > 0.2f) AudioPlayer.seek(max(0.0, PlaybackClock.currentTime + secs))
                            scratchDelta = 0f; scratchLast = null; scratching = false
                        },
                        onDragCancel = { scratchDelta = 0f; scratchLast = null; scratching = false },
                    ) { change, _ ->
                        val c = size.width / 2f
                        val ang = Math.toDegrees(atan2((change.position.y - c).toDouble(), (change.position.x - c).toDouble())).toFloat()
                        val last = scratchLast
                        if (last != null) {
                            var d = ang - last
                            if (d > 180) d -= 360
                            if (d < -180) d += 360
                            val before = (scratchDelta / 20f).toInt()
                            scratchDelta += d
                            spinAngle.floatValue += d
                            if ((scratchDelta / 20f).toInt() != before) Haptics.light()
                        } else { spinActive = true; scratching = true }
                        scratchLast = ang
                        change.consume()
                    }
                },
        ) {
            Box(Modifier.fillMaxSize().graphicsLayer { rotationZ = spinAngle.floatValue }, contentAlignment = Alignment.Center) {
                recBmp?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize()) }
                VinylLabel(labelD, artwork, if (rpm45) "LADO A · 45 RPM" else "LADO A · 33⅓ RPM")
            }
        }

        // reflexo parado (gravata borboleta)
        sheen?.let {
            val rs = DeckGeo.recordD * h
            Image(it.asImageBitmap(), null, Modifier.offset(x = (DeckGeo.platterCx * h - rs / 2).dp, y = (DeckGeo.platterCy * h - rs / 2).dp).size(rs.dp))
        }

        // pino central
        val sd = h * 0.030f
        Canvas(Modifier.offset(x = (DeckGeo.platterCx * h - sd / 2 - 2).dp, y = (DeckGeo.platterCy * h - sd / 2 - 2).dp).size((sd + 4).dp)) {
            val c = center; val r = sd * dens / 2
            drawCircle(Color.Black.copy(0.35f), r + 1.2f * dens, c + Offset(0f, 1f * dens))
            drawCircle(Brush.radialGradient(listOf(G(1f), G(0.62f), G(0.22f)), c + Offset(-r * 0.3f, -r * 0.4f), r * 1.4f), r, c)
            drawCircle(Color.Black.copy(0.5f), r, c, style = Stroke(0.6f * dens))
        }

        // braço (imagem estática que só gira em torno do pivô) + sombra
        arm?.let { imgs ->
            val aw = armCanvasWu * h; val ah = armCanvasHu * h
            val cx = DeckGeo.pivotX * h
            val cy = DeckGeo.pivotY * h + (ah / 2 - StageTextures.armPivotY * h)
            val origin = TransformOrigin(StageTextures.armPivotX / StageTextures.armCanvasW, StageTextures.armPivotY / StageTextures.armCanvasH)
            val ox = (cx - aw / 2).dp; val oy = (cy - ah / 2).dp
            Image(
                imgs.shadow.asImageBitmap(), null,
                Modifier.offset(x = ox, y = oy).size(aw.dp, ah.dp).graphicsLayer {
                    val lift = armLift.value
                    alpha = 0.55f - 0.22f * lift
                    transformOrigin = origin
                    rotationZ = armAngle.value
                    translationX = h * (0.010f + 0.034f * lift) * dens
                    translationY = h * (0.014f + 0.046f * lift) * dens
                },
            )
            Image(
                imgs.arm.asImageBitmap(), null,
                Modifier.offset(x = ox, y = oy).size(aw.dp, ah.dp).graphicsLayer {
                    val s = 1f + 0.045f * armLift.value
                    transformOrigin = origin
                    scaleX = s; scaleY = s
                    rotationZ = armAngle.value
                },
            )
        }

        // alavanca do pitch (o canal é impresso na base)
        val knobY by animateFloatAsState((0.57f + 0.144f * pitch) * h, spring(0.8f, 330f), label = "knob")
        val kw = h * 0.062f; val kh = h * 0.032f
        Box(
            Modifier.offset(x = (1.395f * h - kw / 2).dp, y = (knobY - kh / 2).dp).size(kw.dp, kh.dp)
                .shadow(1.5.dp, RoundedCornerShape((h * 0.008f).dp))
                .clip(RoundedCornerShape((h * 0.008f).dp)).background(Brush.verticalGradient(listOf(G(0.40f), G(0.08f))))
                .border(0.6.dp, Color.White.copy(0.35f), RoundedCornerShape((h * 0.008f).dp)),
            contentAlignment = Alignment.Center,
        ) { Box(Modifier.fillMaxWidth().height(1.3.dp).background(Theme.rose)) }

        if (scratching) {
            val secs = scratchDelta / degPerSec
            val label = (if (secs >= 0) "+" else "−") + "%.1fs".format(abs(secs)) + "  ·  " + Theme.formatTime(max(0.0, PlaybackClock.currentTime + secs))
            Box(Modifier.offset(x = (DeckGeo.platterCx * h - 70).dp, y = (h * 0.06f - 17).dp).width(140.dp).height(34.dp).glass(RoundedCornerShape(50)), contentAlignment = Alignment.Center) {
                Text(label, style = Theme.font(13f, FontWeight.SemiBold, StageText), maxLines = 1)
            }
        }
    }
}

private val armCanvasWu get() = StageTextures.armCanvasW
private val armCanvasHu get() = StageTextures.armCanvasH

// ============================================================ selo do disco (papel com a capa)

@Composable
fun VinylLabel(diameter: Float, artworkURL: String, rpmText: String) {
    val d = diameter
    Box(Modifier.size(d.dp), contentAlignment = Alignment.Center) {
        ArtworkImage(artworkURL, Modifier.size(d.dp), shape = CircleShape)
        // véu de papel + aros impressos
        Canvas(Modifier.size(d.dp)) {
            val r = size.minDimension / 2
            drawCircle(Brush.radialGradient(0f to Color.Transparent, 0.5f to Color.Transparent, 1f to Color.Black.copy(0.30f), center = center, radius = r), r)
            drawCircle(Brush.linearGradient(listOf(Color.White.copy(0.10f), Color.Transparent, Color.Black.copy(0.10f)), Offset.Zero, Offset(size.width, size.height)), r)
            drawCircle(Color.Black.copy(0.28f), r * 0.62f, center, style = Stroke(max(0.6f, d * 0.006f) * density))
            drawCircle(Color.White.copy(0.22f), r * 0.92f, center, style = Stroke(max(0.5f, d * 0.004f) * density))
            drawCircle(Color.Black.copy(0.7f), r - max(1f, d * 0.012f) * density / 2, center, style = Stroke(max(1f, d * 0.012f) * density))
            drawCircle(G(0.08f), d * 0.075f * density / 2, center)
        }
        Text(
            rpmText, style = Theme.rounded(max(5f, d * 0.062f), FontWeight.ExtraBold, Color.White.copy(0.92f)).copy(letterSpacing = spF(0.6f), shadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(0.8f), Offset.Zero, 3f)),
            modifier = Modifier.offset(y = (d * 0.33f).dp), maxLines = 1, softWrap = false,
        )
        Text(
            "STEREO", style = Theme.rounded(max(4.5f, d * 0.050f), FontWeight.ExtraBold, Color.White.copy(0.8f)).copy(letterSpacing = spF(1.2f), shadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(0.8f), Offset.Zero, 3f)),
            modifier = Modifier.offset(y = (-d * 0.33f).dp), maxLines = 1, softWrap = false,
        )
    }
}
