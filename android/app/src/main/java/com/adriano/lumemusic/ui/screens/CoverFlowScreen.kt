package com.adriano.lumemusic.ui.screens

import com.adriano.lumemusic.ui.blockTouchesBehind
import com.adriano.lumemusic.ui.Chrome
import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.ArtworkStore
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.DiscoveryService
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.EmptyState
import com.adriano.lumemusic.ui.GlassIconButton
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.LocalDark
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.tanh

// ============================================================ modelo

class CoverFlowItem(
    val id: String, val title: String, val subtitle: String, val artworkURL: String,
    val album: AlbumShowcase? = null, val track: Track? = null, val localTracks: List<Track> = emptyList(),
)

private enum class FlowSource(val title: String) { RELEASES("Lançamentos"), TRENDING("Em alta"), LIBRARY("Sua biblioteca") }

/** Faixas por capa, carregadas sob demanda e guardadas em cache. */
private class CoverFlowTrackStore {
    val cache = mutableStateMapOf<String, List<Track>>()
    private val inflight = HashSet<String>()
    suspend fun load(item: CoverFlowItem) {
        if (cache[item.id] != null) return
        if (item.localTracks.isNotEmpty()) { cache[item.id] = item.localTracks; return }
        item.track?.let { cache[item.id] = listOf(it); return }
        val album = item.album ?: return
        if (!inflight.add(item.id)) return
        cache[item.id] = try { DiscoveryService.albumTracks(album) } catch (_: Exception) { emptyList() }
        inflight.remove(item.id)
    }
}

/** Métricas do Cover Flow (CoverFlowMetrics do Swift), em dp. */
private class Metrics(
    val width: Float, val height: Float, val cover: Float, val coverTop: Float, val backAspect: Float,
    val flipScale: Float, val flipCenterY: Float, val interactTop: Float, val interactBottom: Float,
) {
    val sideGap get() = cover * 0.88f
    val step get() = cover * 0.38f
    val dragSpacing get() = cover * 0.52f
    val flipShift get() = flipCenterY - (coverTop + cover / 2)

    companion object {
        const val barHeight = 44f
        const val portraitCoverTop = 4f + barHeight + 8f + barHeight + 18f
        fun landscape(w: Float, h: Float): Metrics {
            val barBottom = 8f + barHeight
            val cover = min(h * 0.54f, w * 0.27f)
            val coverTop = barBottom + 8f
            val flipCenterY = (barBottom + h) / 2
            val scale = min(1.6f, (h - barBottom - 8f) / cover)
            return Metrics(w, h, cover, coverTop, 1.55f, scale, flipCenterY, barBottom, h)
        }
        fun portrait(w: Float, h: Float): Metrics {
            val coverTop = portraitCoverTop
            val cover = min(w * 0.64f, (h - coverTop) * 0.36f)
            val scale = min(1.5f, (w * 0.92f) / cover)
            return Metrics(w, h, cover, coverTop, 1f, scale, coverTop + cover * scale / 2, coverTop - 8f, coverTop + cover * 1.28f)
        }
    }
}

private fun springFor(response: Float, damping: Float) = spring<Float>(damping, (2f * Math.PI.toFloat() / response).let { it * it })

// ============================================================ tela

/** Cover Flow estilo iPod: aviso "Vire o celular", acelerômetro, paisagem com reflexo e flip 3D com as faixas. */
@Composable
fun CoverFlowScreen() {
    val ctx = LocalContext.current
    var source by remember { mutableStateOf(FlowSource.RELEASES) }
    var choosePortrait by remember { mutableStateOf(false) }
    var forcedLandscape by remember { mutableStateOf(false) }
    val tracks = remember { CoverFlowTrackStore() }
    val pos = remember { Animatable(0f) }
    var selIndex by remember { mutableIntStateOf(0) }
    var flippedId by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val feed = AppModel.feed

    val items = remember(source, feed, LibraryStore.favoriteIds.size, LibraryStore.recentIds.size, LibraryStore.playlists) { buildItems(source) }
    LaunchedEffect(items.size) {
        val maxIndex = max(0, items.size - 1)
        if (selIndex > maxIndex) { selIndex = maxIndex; pos.snapTo(maxIndex.toFloat()) }
    }
    LaunchedEffect(source) { flippedId = null; selIndex = 0; pos.snapTo(0f) }

    DisposableEffect(Unit) {
        val sm = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val acc = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val activity = ctx as? Activity
        val l = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val x = abs(e.values[0]); val y = abs(e.values[1])
                if (x > 6.5f && y < 5f && !forcedLandscape) {
                    forcedLandscape = true
                    activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                } else if (y > 7f && x < 4f && forcedLandscape) {
                    // voltou a segurar em pé: devolve a interface a retrato e mostra a versão vertical preenchida
                    forcedLandscape = false; choosePortrait = true
                    activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
            }
            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }
        if (acc != null) sm.registerListener(l, acc, SensorManager.SENSOR_DELAY_UI)
        onDispose { sm.unregisterListener(l); activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
    }

    fun close() {
        flippedId = null
        AppModel.showCoverFlow = false
    }

    fun playCurrent() {
        val item = items.getOrNull(selIndex) ?: return
        scope.launch {
            item.track?.let { Haptics.medium(); AudioPlayer.play(it, items.mapNotNull { i -> i.track }); return@launch }
            tracks.load(item)
            val list = tracks.cache[item.id]
            if (!list.isNullOrEmpty()) { Haptics.medium(); AudioPlayer.play(list.first(), list) }
        }
    }

    CompositionLocalProvider(LocalDark provides true) {
        Box(Modifier.fillMaxSize().blockTouchesBehind()) {
            CoverFlowBackdrop()
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val landscape = maxWidth > maxHeight
                val w = maxWidth.value; val h = maxHeight.value
                if (landscape) LandscapeLayout(w, h, items, source, { source = it }, pos, selIndex, { selIndex = it }, flippedId, { flippedId = it }, tracks, ::close, ::playCurrent)
                else if (choosePortrait) PortraitLayout(w, h, items, source, { source = it }, pos, selIndex, { selIndex = it }, flippedId, { flippedId = it }, tracks, ::close, ::playCurrent)
                else RotatePrompt(onContinue = { Haptics.light(); choosePortrait = true }, onClose = ::close)
            }
        }
    }
}

private fun buildItems(source: FlowSource): List<CoverFlowItem> {
    val feed = AppModel.feed
    return when (source) {
        FlowSource.RELEASES -> {
            val seen = HashSet<String>()
            ((feed?.newReleases ?: emptyList()) + (feed?.brazilReleases ?: emptyList())).mapNotNull { a ->
                if (!seen.add(a.id)) null else CoverFlowItem(a.id, a.title, a.artist, a.artworkURL, album = a)
            }
        }
        FlowSource.TRENDING -> (feed?.topBrazil ?: emptyList()).map { t -> CoverFlowItem(t.id, t.title, t.artist, ArtworkStore.url(t), track = t) }
        FlowSource.LIBRARY -> {
            val groups = LinkedHashMap<String, MutableList<Track>>()
            for (t in LibraryStore.favoriteTracks + LibraryStore.recentTracks + LibraryStore.playlists.flatMap { LibraryStore.tracks(it) }) {
                val key = (t.album.ifEmpty { t.title }).lowercase() + "|" + LibraryStore.mainArtist(t.artist).lowercase()
                val list = groups.getOrPut(key) { mutableListOf() }
                if (list.none { it.id == t.id }) list.add(t)
            }
            groups.mapNotNull { (k, list) ->
                val f = list.firstOrNull() ?: return@mapNotNull null
                CoverFlowItem(k, f.album.ifEmpty { f.title }, LibraryStore.mainArtist(f.artist), ArtworkStore.url(f), localTracks = list)
            }
        }
    }
}

// ============================================================ fundo (preto profundo com vinheta)

@Composable
private fun CoverFlowBackdrop() {
    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(white = 0.11f), Color(white = 0.02f), Color.Black)))) {
        Box(Modifier.fillMaxSize().drawWithContent {
            drawRect(Brush.radialGradient(listOf(Theme.lavender.copy(0.16f), Color.Transparent), Offset(size.width * 0.5f, size.height * 0.42f), 380f * density))
            drawRect(Brush.radialGradient(0.45f to Color.Transparent, 1f to Color.Black.copy(0.85f), center = center, radius = kotlin.math.hypot(size.width, size.height) / 2f))
        })
    }
}

private fun Color(white: Float) = Color(white, white, white)

// ============================================================ layouts

@Composable
private fun LandscapeLayout(
    w: Float, h: Float, items: List<CoverFlowItem>, source: FlowSource, onSource: (FlowSource) -> Unit, pos: Animatable<Float, *>,
    sel: Int, setSel: (Int) -> Unit, flippedId: String?, setFlipped: (String?) -> Unit, tracks: CoverFlowTrackStore, onClose: () -> Unit, onPlay: () -> Unit,
) {
    val m = Metrics.landscape(w, h)
    val captionH = 56f
    val flipA by animateFloatAsState(if (flippedId == null) 1f else 0f, tween(200), label = "chrome")
    // Modo imersivo em paisagem (sem barra de status/navegação); restaura ao sair.
    val view = LocalView.current
    DisposableEffect(view) {
        val window = (view.context as? Activity)?.window
        val ctrl = window?.let { WindowInsetsControllerCompat(it, view) }
        ctrl?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        ctrl?.hide(WindowInsetsCompat.Type.systemBars())
        onDispose { ctrl?.show(WindowInsetsCompat.Type.systemBars()) }
    }
    val navBottom = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp().value }
    Box(Modifier.fillMaxSize()) {
        if (items.isEmpty()) CoverFlowEmpty(source)
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp).graphicsLayer { alpha = flipA }.zIndex(2f),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            GlassIconButton("xmark", 44.dp, 17.dp, foreground = Color.White, desc = "Fechar") { if (flippedId == null) onClose() }
            Spacer(Modifier.weight(1f))
            CoverFlowSourcePicker(source, onSource)
            Spacer(Modifier.weight(1f))
            GlassIconButton("play.fill", 44.dp, 17.dp, foreground = Color.White, desc = "Tocar") { if (flippedId == null) onPlay() }
        }
        if (items.isNotEmpty()) {
            Box(Modifier.fillMaxWidth().padding(top = (h - captionH - 4 - navBottom).dp).height(captionH.dp).graphicsLayer { alpha = flipA }.zIndex(2f), contentAlignment = Alignment.TopCenter) {
                CoverFlowCaption(items, sel, Modifier.fillMaxSize())
            }
        }
        // Quando uma capa está virada, o palco sobe acima das barras para nenhum botão invisível roubar toque da lista de faixas.
        Box(Modifier.fillMaxSize().zIndex(if (flippedId != null) 10f else 1f)) {
            CoverFlowStage(items, m, pos, sel, setSel, flippedId, setFlipped, tracks)
        }
    }
}

@Composable
private fun PortraitLayout(
    w: Float, h: Float, items: List<CoverFlowItem>, source: FlowSource, onSource: (FlowSource) -> Unit, pos: Animatable<Float, *>,
    sel: Int, setSel: (Int) -> Unit, flippedId: String?, setFlipped: (String?) -> Unit, tracks: CoverFlowTrackStore, onClose: () -> Unit, onPlay: () -> Unit,
) {
    val m = Metrics.portrait(w, h)
    val captionY = m.coverTop + m.cover * 1.30f
    val captionH = 60f
    val sliderY = captionY + captionH + 4f
    val panelY = sliderY + 40f
    val navBottomDp = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp().value }
    val panelH = max(120f, h - panelY - 8f - navBottomDp)
    val flipA by animateFloatAsState(if (flippedId == null) 1f else 0f, tween(200), label = "chrome")
    val scope = rememberCoroutineScope()
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxWidth().statusBarsPadding().padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                GlassIconButton("xmark", 44.dp, 17.dp, foreground = Color.White, desc = "Fechar") { onClose() }
                Spacer(Modifier.weight(1f))
                Text("Cover Flow", style = Theme.rounded(17f, FontWeight.SemiBold, Color.White))
                Spacer(Modifier.weight(1f))
                GlassIconButton("play.fill", 44.dp, 17.dp, foreground = Color.White, desc = "Tocar") { onPlay() }
            }
            CoverFlowSourcePicker(source, onSource)
        }
        if (items.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(top = m.coverTop.dp)) { CoverFlowEmpty(source) }
        } else {
            Box(Modifier.fillMaxWidth().padding(top = captionY.dp).height(captionH.dp).graphicsLayer { alpha = flipA }, contentAlignment = Alignment.TopCenter) {
                CoverFlowCaption(items, sel, Modifier.fillMaxSize())
            }
            // scrubber
            Slider(
                value = pos.value.coerceIn(0f, max(1f, (items.size - 1).toFloat())),
                onValueChange = { v ->
                    setFlipped(null)
                    scope.launch { pos.snapTo(v) }
                    val idx = v.roundToInt().coerceIn(0, max(0, items.size - 1))
                    if (idx != sel) { setSel(idx); Haptics.selection() }
                },
                valueRange = 0f..max(1f, (items.size - 1).toFloat()),
                onValueChangeFinished = { scope.launch { pos.animateTo(pos.value.roundToInt().toFloat(), springFor(0.38f, 1f)) } },
                colors = SliderDefaults.colors(thumbColor = Color.White.copy(0.95f), activeTrackColor = Color.White.copy(0.85f), inactiveTrackColor = Color.White.copy(0.22f)),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 28.dp).padding(top = sliderY.dp).height(36.dp),
            )
            Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = panelY.dp).height(panelH.dp)) {
                CoverFlowTrackPanel(items, sel, tracks)
            }
        }
        // Estágio acima de tudo só enquanto uma capa está virada; fora disso ele não pode engolir toques dos botões, do scrubber e da lista.
        Box(Modifier.fillMaxSize().zIndex(if (flippedId != null) 10f else -1f)) { CoverFlowStage(items, m, pos, sel, setSel, flippedId, setFlipped, tracks) }
    }
}

// ============================================================ seletor de fonte (vidro)

@Composable
private fun CoverFlowSourcePicker(source: FlowSource, onSource: (FlowSource) -> Unit) {
    Row(Modifier.height(Chrome.minTouch).glass(RoundedCornerShape(50)).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for (s in FlowSource.entries) {
            val active = source == s
            Box(
                Modifier.height(Chrome.minTouch).pressable(0.97f) { if (!active) { Haptics.selection(); onSource(s) } },
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.height(36.dp).clip(RoundedCornerShape(50)).then(if (active) Modifier.background(Theme.prismDiagonal) else Modifier).padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
                    Text(s.title, style = Theme.font(13f, FontWeight.SemiBold, if (active) Theme.onPrism else Color.White.copy(0.85f)), maxLines = 1)
                }
            }
        }
    }
}

// ============================================================ legenda

@Composable
private fun CoverFlowCaption(items: List<CoverFlowItem>, sel: Int, modifier: Modifier) {
    val i = sel.coerceIn(0, max(0, items.size - 1))
    val cur = items[i]
    Box(modifier.padding(horizontal = 24.dp), contentAlignment = Alignment.Center) {
        Column(
            Modifier.widthIn440().fillMaxHeight().glass(RoundedCornerShape(22.dp)).padding(horizontal = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
        ) {
            Text(cur.title, style = Theme.rounded(17f, FontWeight.Bold, Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${cur.subtitle}  ·  ${i + 1} de ${items.size}", style = Theme.font(13f, FontWeight.Medium, Color.White.copy(0.62f)), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

private fun Modifier.widthIn440(): Modifier = this.widthIn(max = 440.dp)

// ============================================================ palco 3D

@Composable
private fun CoverFlowStage(
    items: List<CoverFlowItem>, m: Metrics, pos: Animatable<Float, *>, sel: Int, setSel: (Int) -> Unit,
    flippedId: String?, setFlipped: (String?) -> Unit, tracks: CoverFlowTrackStore,
) {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val dragEnabled = flippedId == null
    val liveCenter by remember(items.size) {
        derivedStateOf { if (items.isEmpty()) 0 else pos.value.roundToInt().coerceIn(0, items.size - 1) }
    }
    val visibleRange by remember(items.size) {
        derivedStateOf {
            if (items.isEmpty()) IntRange.EMPTY
            else max(0, floor(pos.value).toInt() - 5)..min(items.size - 1, ceil(pos.value).toInt() + 5)
        }
    }
    var lastHapticMs by remember { mutableStateOf(0L) }

    fun unflip() { if (flippedId != null) setFlipped(null) }

    // Mantém seleção e legenda sincronizadas com o centro real ao vivo (nunca pula antes da animação).
    LaunchedEffect(liveCenter) {
        if (items.isNotEmpty() && liveCenter != sel) {
            setSel(liveCenter)
            val now = android.os.SystemClock.uptimeMillis()
            if (now - lastHapticMs > 65L) { lastHapticMs = now; Haptics.selection() }
        }
    }

    LaunchedEffect(liveCenter, items.size) {
        // Pré-carrega as faixas da capa central para o giro ser instantâneo.
        if (items.isEmpty()) return@LaunchedEffect
        delay(200)
        tracks.load(items[liveCenter])
    }

    Box(
        Modifier.fillMaxSize().then(
            if (dragEnabled) Modifier.pointerInput(items.size, m.dragSpacing) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val vt = VelocityTracker()
                    vt.addPosition(down.uptimeMillis, down.position)
                    var started = false
                    var startPos = 0f
                    var totalDx = 0f
                    val slop = 6.dp.toPx()
                    drag(down.id) { ch ->
                        vt.addPosition(ch.uptimeMillis, ch.position)
                        totalDx = ch.position.x - down.position.x
                        if (!started && abs(totalDx) > slop) {
                            started = true
                            scope.launch { pos.stop() }
                            startPos = pos.value
                            unflip()
                        }
                        if (started) {
                            ch.consume()
                            val raw = startPos - totalDx / density.density / m.dragSpacing
                            val maxV = max(0, items.size - 1).toFloat()
                            val rb = if (raw < 0) raw * 0.28f else if (raw > maxV) maxV + (raw - maxV) * 0.28f else raw
                            scope.launch { pos.snapTo(rb) }
                        }
                    }
                    if (started) {
                        val vx = vt.calculateVelocity().x
                        val velItems = (-vx / density.density / m.dragSpacing).coerceIn(-12f, 12f)
                        val from = pos.value
                        val projected = from + velItems * 0.26f
                        val clampedJump = min(from + 6f, max(from - 6f, projected))
                        val target = clampedJump.roundToInt().coerceIn(0, max(0, items.size - 1)).toFloat()
                        val distance = abs(target - from)
                        val response = 0.36f + min(0.28f, distance * 0.045f)
                        scope.launch { pos.animateTo(target, springFor(response, 1f), initialVelocity = velItems) }
                    }
                }
            } else Modifier,
        ),
    ) {
        // Área de toque em todo o palco: um toque no fundo desvira a capa.
        val scrimA by animateFloatAsState(if (flippedId != null) 0.58f else 0f, tween(220), label = "scrim")
        Box(
            Modifier.fillMaxSize()
                .then(if (flippedId != null) Modifier.background(Color.Black.copy(scrimA)).zIndex(50f) else Modifier)
                .clickable(MutableInteractionSource(), null) { unflip() },
        )

        val floorA by animateFloatAsState(if (flippedId == null) 1f else 0f, tween(250), label = "floor")
        CoverFlowFloor(m.width, m.cover, Modifier.padding(top = (m.coverTop + m.cover).dp).graphicsLayer { alpha = floorA })

        if (items.isNotEmpty()) {
            for (idx in visibleRange) {
                val item = items[idx]
                val isFlipped = flippedId == item.id
                androidx.compose.runtime.key(item.id) {
                    CoverFlowCardSlot(item, idx, m, pos, isFlipped, tracks, onClose = { unflip() }, onPlayAll = {
                        val list = tracks.cache[items.getOrNull(sel)?.id ?: ""]
                        if (!list.isNullOrEmpty()) { Haptics.medium(); AudioPlayer.play(list.first(), list) }
                    }) {
                        // toque
                        if (idx != liveCenter) {
                            if (flippedId != null) setFlipped(null)
                            Haptics.light()
                            val distance = abs(idx - pos.value)
                            val response = 0.40f + min(0.24f, distance * 0.045f)
                            scope.launch { pos.animateTo(idx.toFloat(), springFor(response, 1f)) }
                        } else if (!isFlipped) {
                            val t = item.track
                            if (t != null) { Haptics.medium(); AudioPlayer.play(t, items.mapNotNull { it.track }) }
                            else { Haptics.medium(); setFlipped(item.id) }
                        }
                    }
                }
            }
        }
    }
}

private val cfTanhNorm = tanh(1.6).toFloat()

/** Posiciona uma capa no palco: curva C∞ sem quinas, zIndex ao vivo e expansão em resolução nativa (sem esticar texto). */
@Composable
private fun CoverFlowCardSlot(
    item: CoverFlowItem, idx: Int, m: Metrics, pos: Animatable<Float, *>, flipped: Boolean, tracks: CoverFlowTrackStore,
    onClose: () -> Unit, onPlayAll: () -> Unit, onTap: () -> Unit,
) {
    val density = LocalDensity.current.density
    val wide = m.backAspect > 1.2f
    // Dimensões nativas da capa virada (sem scaleX=1.6 esticando texto/botões).
    val targetW = if (flipped) {
        if (wide) min(m.width - 40f, max(m.cover * 2.35f, 460f)) else min(m.width - 32f, 350f)
    } else m.cover
    val targetH = if (flipped) {
        if (wide) min(m.height - 28f, 300f) else min(m.height - m.coverTop - 36f, 370f)
    } else m.cover
    val targetTop = if (flipped) {
        if (wide) max(14f, (m.height - targetH) / 2f) else max(m.coverTop - 10f, (m.height - targetH) / 2f)
    } else m.coverTop

    val cardW by animateDpAsState(targetW.dp, spring(0.84f, 220f), label = "cw")
    val cardH by animateDpAsState(targetH.dp, spring(0.84f, 220f), label = "ch")
    val topPad by animateDpAsState(targetTop.dp, spring(0.84f, 220f), label = "ct")
    val liveZ by remember(idx, flipped) {
        derivedStateOf { if (flipped) 100f else -abs(idx - pos.value) }
    }
    Box(
        Modifier.fillMaxWidth().padding(top = topPad).zIndex(liveZ),
        contentAlignment = Alignment.TopCenter,
    ) {
        Box(
            Modifier.size(cardW, if (flipped) cardH else cardH * 1.5f).graphicsLayer {
                if (flipped) {
                    rotationY = 0f
                    scaleX = 1f; scaleY = 1f
                    translationX = 0f
                    alpha = 1f
                } else {
                    val delta = idx - pos.value
                    val a = abs(delta)
                    val s = if (delta >= 0) 1f else -1f
                    val curve = tanh(1.6 * a.toDouble()).toFloat() / cfTanhNorm
                    val tilt = tanh(1.7 * a.toDouble()).toFloat()
                    val beyond = max(0f, a - 1f)
                    val x = s * (m.step * a + (m.sideGap - m.step) * curve)
                    val angle = -s * 56f * tilt
                    val scale = (1f - 0.16f * tilt - 0.025f * beyond).coerceAtLeast(0.68f)
                    val fade = if (a > 3.6f) max(0f, 1f - (a - 3.6f) / 1.1f) else 1f
                    transformOrigin = TransformOrigin(0.5f, 1f / 3f)
                    cameraDistance = 12f * density
                    rotationY = angle
                    scaleX = scale; scaleY = scale
                    translationX = x * density
                    alpha = fade
                }
                compositingStrategy = CompositingStrategy.Offscreen
            }.drawWithContent {
                drawContent()
                if (!flipped) {
                    val a = abs(idx - pos.value)
                    val tilt = tanh(1.7 * a.toDouble()).toFloat()
                    val shade = (1f - 0.42f * tilt - 0.06f * max(0f, a - 1f)).coerceAtLeast(0.32f)
                    if (shade < 0.999f) drawRect(Color.Black.copy(1f - shade), blendMode = BlendMode.SrcAtop)
                }
            }.then(if (!flipped) Modifier.clickable(MutableInteractionSource(), null) { onTap() } else Modifier),
        ) {
            CoverFlowCard(item, cardW.value, cardH.value, wide, flipped, tracks, onClose, onPlayAll)
        }
    }
}

/** Brilho do "chão" sob as capas. */
@Composable
private fun CoverFlowFloor(width: Float, cover: Float, modifier: Modifier) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.width((width * 0.96f).dp).graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.drawWithContent {
                drawContent()
                drawRect(Brush.horizontalGradient(0f to Color.Transparent, 0.18f to Color.White, 0.82f to Color.White, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
            },
        ) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(Brush.horizontalGradient(listOf(Color.Transparent, Color.White.copy(0.30f), Color.Transparent))))
            Box(Modifier.fillMaxWidth().height((cover * 0.62f).dp).background(Brush.verticalGradient(listOf(Color.White.copy(0.075f), Color.Transparent))))
        }
    }
}

// ============================================================ capa (frente + reflexo + verso)

@Composable
private fun CoverFlowCard(
    item: CoverFlowItem, widthDp: Float, heightDp: Float, wide: Boolean, flipped: Boolean,
    store: CoverFlowTrackStore, onClose: () -> Unit, onPlayAll: () -> Unit,
) {
    val density = LocalDensity.current.density
    val angle by animateFloatAsState(if (flipped) 180f else 0f, springFor(0.62f, 0.88f), label = "flip")
    val reflA by animateFloatAsState(if (flipped) 0f else 1f, tween(200), label = "refl")
    Box(Modifier.fillMaxSize()) {
        if (!flipped || reflA > 0.01f) {
            // reflexo barato: a mesma imagem espelhada, com máscara de gradiente
            Box(
                Modifier.offset(y = (heightDp + 2f).dp).size(widthDp.dp, (heightDp * 0.5f).dp)
                    .graphicsLayer { alpha = reflA; compositingStrategy = CompositingStrategy.Offscreen }
                    .clip(RoundedCornerShape(4.dp)).drawWithContent {
                        drawContent()
                        drawRect(Brush.verticalGradient(0f to Color.White.copy(0.42f), 0.5f to Color.White.copy(0.10f), 1f to Color.Transparent), blendMode = BlendMode.DstIn)
                    },
            ) {
                ArtworkImage(item.artworkURL, Modifier.size(widthDp.dp, heightDp.dp).graphicsLayer { scaleY = -1f }, cornerRadius = 4.dp)
            }
        }
        Box(
            Modifier.size(widthDp.dp, heightDp.dp).graphicsLayer {
                rotationY = angle
                cameraDistance = 14f * density
            },
            contentAlignment = Alignment.Center,
        ) {
            if (angle < 90f) {
                Box(Modifier.fillMaxSize()) {
                    ArtworkImage(item.artworkURL, Modifier.fillMaxSize(), cornerRadius = 4.dp)
                    Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(Color.White.copy(0.16f), Color.Transparent, Color.Transparent))))
                    Box(Modifier.fillMaxSize().border(0.6.dp, Color.White.copy(0.14f), RoundedCornerShape(4.dp)))
                }
            } else {
                Box(Modifier.fillMaxSize().graphicsLayer { rotationY = 180f }) {
                    CoverFlowBack(item, wide, store, onClose, onPlayAll)
                }
            }
        }
    }
}

// ============================================================ verso: faixas em vidro (resolução nativa)

@Composable
private fun CoverFlowBack(item: CoverFlowItem, wide: Boolean, store: CoverFlowTrackStore, onClose: () -> Unit, onPlayAll: () -> Unit) {
    val tracks = store.cache[item.id]
    val shape = RoundedCornerShape(22.dp)
    Box(
        Modifier.fillMaxSize()
            .shadow(22.dp, shape, ambientColor = Color.Black.copy(0.65f), spotColor = Color.Black.copy(0.65f))
            .clip(shape)
            .background(Color(0xFF101018))
            .border(1.dp, Brush.linearGradient(Theme.glassStrokeColors), shape),
    ) {
        // Fundo ambiente suave: capa borrada + véu escuro legível (nunca atrapalha a leitura das faixas).
        ArtworkImage(item.artworkURL, Modifier.fillMaxSize().scale(1.25f).blur(28.dp), cornerRadius = 0.dp)
        Box(Modifier.fillMaxSize().background(Color(0xFF0A0A12).copy(0.76f)))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to Color.White.copy(0.10f), 0.35f to Color.Transparent, 1f to Color.Black.copy(0.25f))))

        Box(Modifier.fillMaxSize().padding(14.dp)) {
            if (wide) {
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Column(Modifier.width(148.dp).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        ArtworkImage(
                            item.artworkURL,
                            Modifier.size(72.dp).border(0.6.dp, Color.White.copy(0.22f), RoundedCornerShape(10.dp))
                                .clickable(MutableInteractionSource(), null) { onClose() },
                            cornerRadius = 10.dp,
                        )
                        Text(item.title, style = Theme.rounded(15.5f, FontWeight.Bold, Color.White), maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Text(item.subtitle, style = Theme.font(12.5f, color = Color.White.copy(0.68f)), maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.weight(1f))
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            BackPlayButton(onPlayAll)
                            BackCloseButton(onClose)
                        }
                    }
                    Box(
                        Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(16.dp))
                            .background(Color.White.copy(0.06f)).border(0.7.dp, Color.White.copy(0.14f), RoundedCornerShape(16.dp)),
                    ) { TrackList(tracks) }
                }
            } else {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        ArtworkImage(item.artworkURL, Modifier.size(48.dp).border(0.6.dp, Color.White.copy(0.2f), RoundedCornerShape(8.dp)), cornerRadius = 8.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(item.title, style = Theme.rounded(15.5f, FontWeight.Bold, Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(item.subtitle, style = Theme.font(12.5f, color = Color.White.copy(0.68f)), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        BackPlayButton(onPlayAll)
                        BackCloseButton(onClose)
                    }
                    Box(
                        Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(16.dp))
                            .background(Color.White.copy(0.06f)).border(0.7.dp, Color.White.copy(0.14f), RoundedCornerShape(16.dp)),
                    ) { TrackList(tracks) }
                }
            }
        }
    }
}

@Composable
private fun BackPlayButton(onClick: () -> Unit) {
    Box(
        Modifier.size(44.dp).pressable(0.92f) { onClick() }
            .clip(CircleShape).background(Theme.prismDiagonal).border(0.8.dp, Color.White.copy(0.5f), CircleShape),
        contentAlignment = Alignment.Center,
    ) { Icon(sf("play.fill"), "Tocar", tint = Theme.onPrism, modifier = Modifier.size(18.dp)) }
}

@Composable
private fun BackCloseButton(onClick: () -> Unit) {
    Box(
        Modifier.size(44.dp).pressable(0.92f) { onClick() }
            .clip(CircleShape).background(Color.White.copy(0.14f)).border(0.8.dp, Color.White.copy(0.24f), CircleShape),
        contentAlignment = Alignment.Center,
    ) { Icon(sf("xmark"), "Fechar", tint = Color.White, modifier = Modifier.size(16.dp)) }
}

@Composable
private fun TrackList(tracks: List<Track>?) {
    when {
        tracks == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = Color.White, modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
        }
        tracks.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("Sem faixas disponíveis", style = Theme.font(13.5f, color = Color.White.copy(0.65f)))
        }
        else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 4.dp)) {
            itemsIndexed(tracks, key = { i, t -> "${i}_${t.id}" }) { i, t ->
                BackRow(i, t, tracks)
                if (i < tracks.lastIndex) HorizontalDivider(color = Color.White.copy(0.08f), modifier = Modifier.padding(start = 38.dp, end = 12.dp))
            }
            if (tracks.size <= 4) {
                item {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(sf(if (tracks.size == 1) "music.note" else "square.stack"), null, tint = Theme.rose, modifier = Modifier.size(15.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "${if (tracks.size == 1) "Single" else "EP · ${tracks.size} faixas"} · ${totalDuration(tracks)}",
                            style = Theme.font(12f, FontWeight.Medium, Color.White.copy(0.58f)),
                        )
                    }
                }
            }
        }
    }
}

private fun totalDuration(tracks: List<Track>): String {
    val secs = tracks.sumOf { it.duration }.toInt()
    return if (secs >= 3600) "${secs / 3600} h ${(secs % 3600) / 60} min" else "${max(1, secs / 60)} min"
}

@Composable
private fun BackRow(i: Int, t: Track, tracks: List<Track>) {
    val playing = AudioPlayer.currentTrack?.id == t.id
    Row(
        Modifier.fillMaxWidth().height(44.dp).pressable(0.99f) { Haptics.light(); AudioPlayer.play(t, tracks) }.padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.width(20.dp), contentAlignment = Alignment.CenterEnd) {
            if (playing) Icon(sf("waveform"), null, tint = Theme.rose, modifier = Modifier.size(14.dp))
            else Text("${i + 1}", style = Theme.font(12f, FontWeight.Medium, Color.White.copy(0.5f)))
        }
        Text(
            t.title,
            style = Theme.font(14f, if (playing) FontWeight.SemiBold else FontWeight.Medium, if (playing) Theme.rose else Color.White),
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
        )
        if (t.formattedDuration.isNotEmpty()) {
            Text(t.formattedDuration, style = Theme.font(12f, color = Color.White.copy(0.5f)))
        }
    }
}

// ============================================================ retrato: lista de faixas da capa atual

@Composable
private fun CoverFlowTrackPanel(items: List<CoverFlowItem>, sel: Int, store: CoverFlowTrackStore) {
    val i = sel.coerceIn(0, max(0, items.size - 1))
    val item = items[i]
    val isChart = item.track != null
    Column(Modifier.fillMaxSize().glass(RoundedCornerShape(26.dp))) {
        Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(if (isChart) "Em alta agora" else "Faixas", style = Theme.rounded(16f, FontWeight.Bold, Color.White))
                Text(if (isChart) "${items.size} músicas" else item.title, style = Theme.font(12.5f, color = Color.White.copy(0.6f)), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        HorizontalDivider(color = Color.White.copy(0.12f))
        if (isChart) {
            val all = remember(items) { items.mapNotNull { it.track } }
            val state = rememberLazyListState()
            LaunchedEffect(i) { runCatching { state.animateScrollToItem(max(0, i - 2)) } }
            LazyColumn(Modifier.fillMaxSize(), state = state) {
                itemsIndexed(items, key = { _, it -> it.id }) { n, it ->
                    val t = it.track ?: return@itemsIndexed
                    PanelRow(n + 1, t.title, t.artist, t.formattedDuration, n == i || AudioPlayer.currentTrack?.id == t.id) { AudioPlayer.play(t, all) }
                }
            }
        } else {
            val tracks = store.cache[item.id]
            LaunchedEffect(item.id) { store.load(item) }
            when {
                tracks == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Color.White, modifier = Modifier.size(24.dp), strokeWidth = 2.dp) }
                tracks.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("Sem faixas disponíveis", style = Theme.font(14f, color = Color.White.copy(0.6f))) }
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    itemsIndexed(tracks, key = { n, t -> "${n}_${t.id}" }) { n, t -> PanelRow(n + 1, t.title, null, t.formattedDuration, AudioPlayer.currentTrack?.id == t.id) { AudioPlayer.play(t, tracks) } }
                }
            }
        }
    }
}

@Composable
private fun PanelRow(number: Int, title: String, subtitle: String?, duration: String, active: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(if (subtitle == null) Chrome.minTouch else 52.dp).pressable(0.99f) { Haptics.light(); onClick() }.padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.width(24.dp), contentAlignment = Alignment.CenterEnd) { Text("$number", style = Theme.font(13f, FontWeight.Medium, Color.White.copy(0.45f))) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = Theme.font(15f, if (active) FontWeight.SemiBold else FontWeight.Normal, if (active) Theme.rose else Color.White), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, style = Theme.font(12.5f, color = Color.White.copy(0.55f)), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(duration, style = Theme.font(12.5f, color = Color.White.copy(0.45f)))
    }
}

// ============================================================ "Vire o celular"

@Composable
private fun RotatePrompt(onContinue: () -> Unit, onClose: () -> Unit) {
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().statusBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(30.dp)) {
            Spacer(Modifier.weight(1f))
            PhoneIllustration()
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Vire o celular", style = Theme.rounded(30f, FontWeight.Bold, Color.White))
                Text("O Cover Flow fica ainda mais bonito\ncom o celular na horizontal.", style = Theme.font(16f, color = Color.White.copy(0.62f)).copy(lineHeight = androidx.compose.ui.unit.TextUnit(21f, androidx.compose.ui.unit.TextUnitType.Sp)), textAlign = TextAlign.Center)
            }
            Spacer(Modifier.weight(1f))
            Box(Modifier.padding(bottom = 12.dp).height(52.dp).glass(RoundedCornerShape(50)).pressable(0.95f) { onContinue() }.padding(horizontal = 26.dp), contentAlignment = Alignment.Center) {
                Text("Continuar na vertical", style = Theme.font(16f, FontWeight.SemiBold, Color.White))
            }
        }
        Box(Modifier.statusBarsPadding().padding(start = 16.dp, top = 4.dp)) { GlassIconButton("xmark", 44.dp, 17.dp, foreground = Color.White, desc = "Fechar") { onClose() } }
    }
}

/** Celular que gira de pé para deitado em loop. */
@Composable
private fun PhoneIllustration() {
    var turned by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(900); turned = true
            delay(1700); turned = false
            delay(900)
        }
    }
    val rot by animateFloatAsState(if (turned) -90f else 0f, if (turned) springFor(0.95f, 0.78f) else springFor(0.8f, 0.85f), label = "phone")
    val arrowA by animateFloatAsState(if (turned) 0.25f else 1f, tween(300), label = "arrow")
    Box(Modifier.size(240.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size(240.dp).background(Brush.radialGradient(listOf(Theme.lavender.copy(0.32f), Theme.rose.copy(0.10f), Color.Transparent)), CircleShape))
        Box(Modifier.graphicsLayer { rotationZ = rot }) { Phone() }
        Box(Modifier.offset(x = 84.dp, y = 70.dp).size(52.dp).glass(CircleShape).graphicsLayer { alpha = arrowA }, contentAlignment = Alignment.Center) {
            Icon(sf("arrow.counterclockwise"), null, tint = Color.White.copy(0.9f), modifier = Modifier.size(28.dp))
        }
    }
}

@Composable
private fun Phone() {
    val shape = RoundedCornerShape(22.dp)
    Box(Modifier.size(66.dp, 128.dp).shadow(18.dp, shape, ambientColor = Theme.lavender.copy(0.35f), spotColor = Theme.lavender.copy(0.35f)), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxSize().clip(shape).background(Brush.verticalGradient(listOf(Color(0.16f, 0.16f, 0.16f), Color(0.05f, 0.05f, 0.05f)))).border(2.5.dp, Brush.linearGradient(listOf(Color.White.copy(0.75f), Color.White.copy(0.18f))), shape))
        Row(Modifier.offset(y = 4.dp), horizontalArrangement = Arrangement.spacedBy((-10).dp), verticalAlignment = Alignment.CenterVertically) {
            for (i in 0 until 3) {
                Box(
                    Modifier.size(if (i == 1) 26.dp else 16.dp, if (i == 1) 26.dp else 22.dp).zIndex(if (i == 1) 1f else 0f)
                        .graphicsLayer { rotationY = if (i == 0) 55f else if (i == 2) -55f else 0f; cameraDistance = 8f; alpha = 1f }
                        .clip(RoundedCornerShape(3.dp)).background(Theme.prismDiagonal, RoundedCornerShape(3.dp)).graphicsLayer { alpha = if (i == 1) 1f else 0.55f },
                )
            }
        }
        Box(Modifier.offset(y = (-50).dp).size(22.dp, 6.dp).background(Color.Black, CircleShape))
    }
}

// ============================================================ vazio / carregando

@Composable
private fun CoverFlowEmpty(source: FlowSource) {
    if (source != FlowSource.LIBRARY && AppModel.feed == null) {
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)) {
            CircularProgressIndicator(color = Color.White, modifier = Modifier.size(28.dp), strokeWidth = 2.5.dp)
            Text("Carregando capas…", style = Theme.font(14f, color = Color.White.copy(0.6f)))
        }
    } else {
        EmptyState("square.stack.3d.forward.dottedline", "Nada por aqui ainda", "Curta músicas ou abra os lançamentos para preencher o Cover Flow.", Modifier.fillMaxSize())
    }
}
