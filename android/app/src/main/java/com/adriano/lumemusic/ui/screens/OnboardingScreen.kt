package com.adriano.lumemusic.ui.screens

import com.adriano.lumemusic.ui.Chrome
import com.adriano.lumemusic.ui.rememberKeyboardCloser
import com.adriano.lumemusic.ui.keyboardDismissing
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.layout.imePadding
import android.content.Context
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ExperimentalAnimationApi
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.currentStateAsState
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import com.adriano.lumemusic.R
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.access.AccessState
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.engine.CatalogExplorerService
import com.adriano.lumemusic.engine.DiscoveryService
import com.adriano.lumemusic.engine.GenreSources
import com.adriano.lumemusic.engine.SearchService
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.LocalDark
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.hex
import com.adriano.lumemusic.ui.theme.reduceMotion
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Preferências do onboarding (para a Home e Ajustes). */
object Onboarding {
    private fun prefs(c: Context) = c.getSharedPreferences("lume_prefs", Context.MODE_PRIVATE)
    fun isDone(c: Context) = prefs(c).getBoolean("onboarded", false)
    fun setDone(c: Context) = prefs(c).edit().putBoolean("onboarded", true).apply()
    /** Grava os ids (ex. "sertanejo", "rock") na chave única `lume.onboarding.genres` — a mesma que a Home lê. */
    fun saveGenres(c: Context, ids: Set<String>) = prefs(c).edit().putStringSet(com.adriano.lumemusic.ui.OnboardingGenres.KEY, ids).apply()
    fun genres(c: Context): Set<String> = (prefs(c).getStringSet(com.adriano.lumemusic.ui.OnboardingGenres.KEY, null) ?: emptySet()).toSet()
    fun saveArtists(c: Context, names: Set<String>) = prefs(c).edit().putStringSet("artists", names).apply()
    fun artists(c: Context): Set<String> = prefs(c).getStringSet("artists", emptySet()) ?: emptySet()
}

private enum class Step(val palette: Float) { WELCOME(0f), ACCESS(1f), GENRES(2f), ARTISTS(3f), IMPORT(4f), DONE(5f) }

// ============================================================ marca

/** O emblema novo do Lume: a mesma arte do ícone (disco de vidro claro com anel prisma). */
@Composable
fun PrismMark(size: Float) {
    Image(
        painterResource(R.drawable.lume_mark), null,
        Modifier.size(size.dp).shadow((size * 0.12f).dp, CircleShape, ambientColor = Theme.lavender.copy(0.30f), spotColor = Theme.lavender.copy(0.30f)),
    )
}

// ============================================================ fundo animado

private val palettes = listOf(
    longArrayOf(0xFFB27A, 0xFF7BA9, 0xAD8CFF), longArrayOf(0xAD8CFF, 0x7CC8FF, 0xFF7BA9), longArrayOf(0xFF7BA9, 0xFFB27A, 0xAD8CFF),
    longArrayOf(0x7CC8FF, 0xAD8CFF, 0x6FE3C1), longArrayOf(0x6FE3C1, 0x7CC8FF, 0xFFB27A), longArrayOf(0xFFB27A, 0xFF7BA9, 0xAD8CFF),
    longArrayOf(0xAD8CFF, 0x7CC8FF, 0xFF7BA9),
)

/** Manchas de cor suaves que se movem devagar e mudam de paleta a cada passo. <= 30 fps e pausa fora de cena. */
@Composable
private fun OnboardingBackdrop(phase: Float, running: Boolean, modifier: Modifier = Modifier) {
    val dark = LocalDark.current
    val reduce = reduceMotion()
    var tick by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(running, reduce) {
        if (!running || reduce) return@LaunchedEffect
        var last = 0L
        while (true) { val n = withFrameNanos { it }; if (n - last >= 33_000_000L) { last = n; tick = n / 1e9f } }
    }
    Canvas(modifier) {
        val t = tick.toDouble()
        val alpha = if (dark) 0.50f else 0.42f
        val r = max(size.width, size.height) * 0.62f
        val p = phase.coerceIn(0f, (palettes.size - 1).toFloat())
        val lo = p.toInt(); val hi = min(palettes.size - 1, lo + 1); val f = p - lo
        for (i in 0 until 3) {
            val x = size.width * (0.5 + 0.34 * sin(t * 0.17 + i * 2.1)).toFloat()
            val y = size.height * (0.5 + 0.36 * cos(t * 0.13 + i * 1.7)).toFloat()
            val a = hex(palettes[lo][i]); val b = hex(palettes[hi][i])
            val c = Color(a.red + (b.red - a.red) * f, a.green + (b.green - a.green) * f, a.blue + (b.blue - a.blue) * f)
            drawCircle(Brush.radialGradient(listOf(c.copy(alpha), c.copy(0f)), Offset(x, y), r), r, Offset(x, y))
        }
    }
}

@Composable
private fun appearProgress(delayMs: Int, response: Float = 0.7f, damping: Float = 0.8f): Float {
    var on by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(delayMs.toLong()); on = true }
    val k = (2f * PI.toFloat() / response).let { it * it }
    val v by animateFloatAsState(if (on) 1f else 0f, spring(damping, k), label = "appear")
    return v
}

private fun genreShort(g: MusicGenre): String = when (g.id) {
    "funk_br" -> "Funk"; "pagode" -> "Pagode"; "mpb" -> "MPB"; "forro" -> "Forró / Piseiro"; "gospel" -> "Gospel"; "hiphop" -> "Hip-Hop / Rap"
    "eletronica" -> "Eletrônica"; "rnb" -> "R&B"; "latina" -> "Latina"; "indie" -> "Indie"; "classica" -> "Clássica"; "soundtrack" -> "Trilhas & Games"
    else -> g.title
}

@Composable
private fun PrismCta(title: String, icon: String?, height: Int, enabled: Boolean = true, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    val a by animateFloatAsState(if (enabled) 1f else 0.4f, tween(250), label = "cta")
    Row(
        modifier.fillMaxWidth().height(height.dp).alpha(a).then(if (enabled) Modifier.pressable { Haptics.medium(); onClick() } else Modifier)
            .shadow(12.dp, shape, spotColor = Theme.rose.copy(0.45f)).clip(shape).background(Theme.prismDiagonal).border(0.8.dp, Color.White.copy(0.5f), shape),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        // iOS (PrismButton): ícone ANTES do texto, 8 pt de espaço.
        if (icon != null) { Icon(sf(icon), null, tint = Theme.onPrism, modifier = Modifier.size(17.dp)); Spacer(Modifier.width(8.dp)) }
        Text(title, style = Theme.font(16f, FontWeight.SemiBold, Theme.onPrism))
    }
}

@Composable
private fun GlassCta(title: String, height: Int, onClick: () -> Unit) {
    Box(Modifier.fillMaxWidth().height(height.dp).glass(RoundedCornerShape(50)).pressable { Haptics.light(); onClick() }, contentAlignment = Alignment.Center) {
        Text(title, style = Theme.font(16f, FontWeight.SemiBold, Theme.text))
    }
}

private val roundedTitle = TextStyle(fontWeight = FontWeight.Bold, fontFamily = androidx.compose.ui.text.font.FontFamily.SansSerif)

// ============================================================ tela

@OptIn(ExperimentalAnimationApi::class)
@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    val ctx = LocalContext.current
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val accessState by Access.service.state.collectAsState()
    // v2.3: o teste grátis automático substitui o passo do código; ele volta só se o painel desligou o teste.
    LaunchedEffect(Unit) { com.adriano.lumemusic.ui.UpgradeModel.runTrial() }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val lstate by lifecycle.currentStateAsState()
    val running = lstate.isAtLeast(Lifecycle.State.RESUMED)

    var steps by remember { mutableStateOf(listOf(Step.WELCOME, Step.GENRES, Step.ARTISTS, Step.IMPORT, Step.DONE)) }
    var index by remember { mutableIntStateOf(0) }
    var forward by remember { mutableStateOf(true) }
    val selectedGenres = remember { mutableStateListOf<String>() }
    val selectedArtists = remember { mutableStateListOf<String>() }
    var ripple by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(false) }
    var openImport by remember { mutableStateOf(false) }
    var accessInfo by remember { mutableStateOf<com.adriano.lumemusic.access.AccessInfo?>(null) }
    val reveal = remember { Animatable(0f) }
    var revealing by remember { mutableStateOf(false) }
    val step = steps[min(index, steps.size - 1)]
    val chosenGenres = selectedGenres.mapNotNull { id -> MusicGenre.all.firstOrNull { it.id == id } }
    val phase by animateFloatAsState(if (loading) 6f else step.palette, tween(900, easing = FastOutSlowInEasing), label = "phase")

    DisposableEffect(Unit) { SoundFX.begin(); SoundFX.holdOpen = true; onDispose { SoundFX.end() } }

    fun go(delta: Int) {
        val target = (index + delta).coerceIn(0, steps.size - 1)
        if (target == index) return
        forward = delta > 0
        SoundFX.play(SoundFX.Effect.WHOOSH); SoundFX.resetScale(); Haptics.light()
        ripple++
        index = target
    }
    val canGoBack = index > 0 && step != Step.ACCESS && step != Step.DONE && steps[index - 1] != Step.ACCESS && steps[index - 1] != Step.WELCOME
    val canSkip = step == Step.GENRES || step == Step.ARTISTS || step == Step.IMPORT
    fun skip() { if (step == Step.GENRES && selectedGenres.isEmpty()) go(steps.size - 1 - index) else go(1) }

    fun enterApp() {
        Onboarding.setDone(ctx)
        Onboarding.saveGenres(ctx, LinkedHashSet(selectedGenres))
        Onboarding.saveArtists(ctx, LinkedHashSet(selectedArtists))
        com.adriano.lumemusic.ui.HomeStore.onboardingGenresChanged()
        for (n in selectedArtists) if (!LibraryStore.isFollowing(n)) LibraryStore.toggleFollow(n)
        SoundFX.play(SoundFX.Effect.CHORD); Haptics.success()
        loading = true
    }

    fun finishNow() { SoundFX.end(); onFinished(); if (openImport) AppModel.push(LumeRoute.ImportHub) }
    fun doReveal() {
        SoundFX.play(SoundFX.Effect.WHOOSH)
        revealing = true
        scope.launch { reveal.animateTo(1400f, tween(750, easing = FastOutSlowInEasing)); finishNow() }
    }

    BoxWithConstraints(
        Modifier.fillMaxSize().keyboardDismissing().graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.drawWithContent {
            drawContent()
            if (revealing) drawCircle(Color.Black, reveal.value * density.density, center, blendMode = BlendMode.Clear)
        }.background(Theme.canvas),
    ) {
        val w = maxWidth.value
        val h = maxHeight.value
        val markCY = h * 0.30f
        OnboardingBackdrop(phase, running, Modifier.fillMaxSize())
        if (loading) {
            LoadingMusicView(if (chosenGenres.isEmpty()) Onboarding.genres(ctx).mapNotNull { id -> MusicGenre.all.firstOrNull { it.id == id } } else chosenGenres, running) { doReveal() }
        } else {
            Box(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding()) {
                // Marca única que viaja entre as telas (centro <-> cabeçalho).
                val big = step == Step.WELCOME || step == Step.DONE
                val sc by animateFloatAsState(if (big) 1f else 0.2f, spring(0.82f, 80f), label = "markS")
                val my by animateFloatAsState(if (big) markCY else 30f, spring(0.82f, 80f), label = "markY")
                Box(Modifier.offset(x = (w / 2 - 75).dp, y = (my - 75).dp).size(150.dp).graphicsLayer { scaleX = sc; scaleY = sc }) { PrismMark(150f) }

                Column(Modifier.fillMaxSize()) {
                    // cabeçalho
                    val headerH by animateFloatAsState(if (step == Step.WELCOME || step == Step.DONE) 60f else 96f, spring(0.85f, 150f), label = "hdr")
                    Box(Modifier.fillMaxWidth().height(headerH.dp).padding(horizontal = 20.dp).padding(top = 8.dp)) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                            AnimatedVisibility(canGoBack, enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
                                Box(Modifier.size(Chrome.minTouch).glass(CircleShape).pressable(0.92f) { go(-1) }, contentAlignment = Alignment.Center) {
                                    Icon(sf("chevron.left"), "Voltar", tint = Theme.text, modifier = Modifier.size(20.dp))
                                }
                            }
                            Spacer(Modifier.weight(1f))
                            AnimatedVisibility(canSkip, enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
                                Box(Modifier.defaultMinSize(44.dp, 44.dp).glass(RoundedCornerShape(50)).pressable(0.94f) { skip() }.padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
                                    Text("Pular", style = Theme.font(15f, FontWeight.SemiBold, Theme.secondary))
                                }
                            }
                        }
                        if (step != Step.WELCOME && step != Step.DONE) {
                            Row(Modifier.fillMaxWidth().padding(top = 52.dp), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
                                for ((i, s) in steps.withIndex()) {
                                    if (s == Step.WELCOME || s == Step.DONE) continue
                                    val cw by animateFloatAsState(if (i == index) 24f else 7f, spring(0.8f, 200f), label = "dot")
                                    Box(Modifier.size(cw.dp, 7.dp).clip(CircleShape).background(if (i == index) Theme.prismHorizontal else SolidColor(Theme.fillStrong)))
                                }
                            }
                        }
                    }
                    AnimatedContent(
                        step, Modifier.weight(1f).fillMaxWidth(), label = "obStep",
                        transitionSpec = {
                            val dir = if (forward) 1 else -1
                            (slideInHorizontally(tween(420, easing = FastOutSlowInEasing)) { it * dir } + fadeIn(tween(420)) + androidx.compose.animation.scaleIn(tween(420), 0.96f)) togetherWith
                                (slideOutHorizontally(tween(420, easing = FastOutSlowInEasing)) { -it * dir } + fadeOut(tween(300)) + androidx.compose.animation.scaleOut(tween(420), 0.96f))
                        },
                    ) { s ->
                        when (s) {
                            Step.WELCOME -> WelcomeStep(markCY, {
                                SoundFX.play(SoundFX.Effect.TAP)
                                scope.launch {
                                    com.adriano.lumemusic.ui.UpgradeModel.awaitTrial()
                                    if (com.adriano.lumemusic.ui.UpgradeModel.trialNeedsCodeStep() && !steps.contains(Step.ACCESS)) steps = steps.toMutableList().also { it.add(1, Step.ACCESS) }
                                    go(1)
                                }
                            })
                            Step.ACCESS -> Column(Modifier.fillMaxSize().padding(horizontal = 24.dp).padding(top = 60.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                                val info = accessInfo ?: (accessState as? AccessState.Active)?.info
                                if (info != null) com.adriano.lumemusic.ui.screens.AccessSuccessView(info, "Continuar") { com.adriano.lumemusic.ui.UpgradeModel.onActivated(info); go(1) }
                                else com.adriano.lumemusic.ui.screens.AccessCodeEntry("Digite seu código de acesso", com.adriano.lumemusic.ui.UpgradeModel.trialMessage ?: "Quem te enviou o código também te mostra o prazo.", "Ativar", extra = { com.adriano.lumemusic.ui.screens.AccessGateExtras(null) }) { accessInfo = it }
                            }
                            Step.GENRES -> GenresStep(selectedGenres) { go(1) }
                            Step.ARTISTS -> ArtistsStep(chosenGenres, selectedArtists) { go(1) }
                            Step.IMPORT -> ImportStep(onImport = { openImport = true; go(1) }, onNext = { go(1) })
                            Step.DONE -> DoneStep(markCY, chosenGenres, selectedArtists.size) { enterApp() }
                        }
                    }
                }
                RippleBurst(ripple, Modifier.offset(x = (w / 2 - 60).dp, y = (h - 70 - 60).dp))
            }
        }
    }
}

/** Anel de vidro que se expande e some (transição entre passos). */
@Composable
private fun RippleBurst(trigger: Int, modifier: Modifier) {
    val p = remember { Animatable(1f) }
    LaunchedEffect(trigger) { if (trigger > 0) { p.snapTo(0f); p.animateTo(1f, tween(850, easing = EaseOut)) } }
    Box(
        modifier.size(120.dp).graphicsLayer {
            val s = 0.2f + 8.8f * p.value
            scaleX = s; scaleY = s
            alpha = if (trigger == 0) 0f else 0.55f * (1f - p.value)
        }.border(3.dp, Theme.prismSweep, CircleShape),
    )
}

// ============================================================ 1. boas-vindas

@Composable
private fun WelcomeStep(centerY: Float, onStart: () -> Unit) {
    val com_UpgradeModel = com.adriano.lumemusic.ui.UpgradeModel
    val appear = appearProgress(0, 0.6f, 0.8f)
    val reduce = reduceMotion()
    val inf = rememberInfiniteTransition(label = "welcome")
    val spin by inf.animateFloat(0f, 360f, infiniteRepeatable(tween(16000, easing = LinearEasing)), label = "spin")
    Box(Modifier.fillMaxSize()) {
        // Disco de vidro girando + ondas suaves (centrado onde a marca está)
        Box(Modifier.fillMaxWidth().offset(y = (centerY - 60 - 120).dp).height(240.dp).graphicsLayer { alpha = appear; val s = 0.5f + 0.5f * appear; scaleX = s; scaleY = s }, contentAlignment = Alignment.Center) {
            for (i in 0 until 3) {
                val k by inf.animateFloat(0f, 1f, infiniteRepeatable(tween(3600, easing = EaseOut), RepeatMode.Restart, StartOffset(i * 1200)), label = "ring$i")
                Box(Modifier.size(170.dp).graphicsLayer { val s = 0.9f + 1.4f * k; scaleX = s; scaleY = s; alpha = if (reduce) 0f else 0.7f * (1f - k) }.border(1.6.dp, Theme.prismSweep, CircleShape))
            }
            Box(Modifier.size(214.dp).background(Color.White.copy(0.07f), CircleShape))
            Box(Modifier.size(214.dp).graphicsLayer { rotationZ = if (reduce) 0f else spin; alpha = 0.8f }.border(3.dp, Theme.prismSweep, CircleShape))
        }
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            Column(verticalArrangement = Arrangement.spacedBy(6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                WordLine(listOf("Sua", "música,"), 0, false)
                WordLine(listOf("em", "outra", "luz."), 2, true)
            }
            val sub = appearProgress(900, 0.6f, 1f)
            Text("Vamos deixar a Lume com a sua cara em menos de um minuto.", style = Theme.font(15.5f, color = Theme.secondary), textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 36.dp).padding(top = 14.dp).graphicsLayer { alpha = sub })
            val btn = appearProgress(1100, 0.6f, 0.8f)
            PrismCta("Começar", "arrow.right", 54, modifier = Modifier.padding(horizontal = 28.dp).padding(top = 28.dp).graphicsLayer { val s = 0.9f + 0.1f * btn; scaleX = s; scaleY = s; alpha = btn }) { onStart() }
            // Links discretos para quem recebeu um código ou já comprou.
            Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.heightIn(min = 48.dp).pressable(0.95f) { com_UpgradeModel.showCodeEntry = true }.padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
                    Text("Tenho um código", style = Theme.font(13.5f, FontWeight.Medium, Theme.secondary))
                }
                Text("·", style = Theme.font(13.5f, color = Theme.tertiary))
                Box(Modifier.heightIn(min = 48.dp).pressable(0.95f) { com_UpgradeModel.showRecover = true }.padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
                    Text("Já sou vitalício", style = Theme.font(13.5f, FontWeight.Medium, Theme.secondary))
                }
            }
            Text(Theme.credit, style = Theme.font(11.5f, color = Theme.tertiary), modifier = Modifier.padding(top = 4.dp, bottom = 22.dp))
        }
    }
}

@Composable
private fun WordLine(words: List<String>, offset: Int, prism: Boolean) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for ((i, wd) in words.withIndex()) {
            val p = appearProgress(350 + (offset + i) * 140, 0.7f, 0.8f)
            Text(
                wd, modifier = Modifier.graphicsLayer { alpha = p; translationY = (1f - p) * 16f * density },
                style = if (prism) roundedTitle.copy(fontSize = 38.sp, brush = Theme.prismHorizontal) else roundedTitle.copy(fontSize = 38.sp, color = Theme.text),
            )
        }
    }
}

// ============================================================ 3. estilos

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun GenresStep(selected: MutableList<String>, onNext: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 28.dp).padding(top = 4.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Qual estilo você mais curte?", style = roundedTitle.copy(fontSize = 28.sp, color = Theme.text), textAlign = TextAlign.Center)
            Text("Toque nos que combinam com você. Pode escolher vários.", style = Theme.font(14.5f, color = Theme.secondary), textAlign = TextAlign.Center)
        }
        Box(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())) {
            FlowRow(
                Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                MusicGenre.all.forEachIndexed { i, g -> GenreBubble(g, g.id in selected, i) {
                    if (g.id in selected) { selected.remove(g.id); SoundFX.play(SoundFX.Effect.DESELECT); Haptics.light() }
                    else { selected.add(g.id); SoundFX.play(SoundFX.Effect.SELECT); Haptics.medium() }
                } }
            }
        }
        Column(Modifier.padding(horizontal = 28.dp).padding(top = 10.dp, bottom = 26.dp), verticalArrangement = Arrangement.spacedBy(10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(if (selected.isEmpty()) "Escolha pelo menos um" else "${selected.size} escolhido${if (selected.size == 1) "" else "s"}", style = Theme.font(13.5f, FontWeight.Medium, Theme.secondary))
            PrismCta("Continuar", "arrow.right", 54, enabled = selected.isNotEmpty()) { onNext() }
        }
    }
}

@Composable
private fun GenreBubble(g: MusicGenre, selected: Boolean, index: Int, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    val appear = appearProgress(index * 30, 0.5f, 0.72f)
    val pulse = remember { Animatable(1f) }
    val ring = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val a = hex(g.hexA); val b = hex(g.hexB)
    Box(
        Modifier.graphicsLayer { val s = (0.5f + 0.5f * appear) * pulse.value; scaleX = s; scaleY = s; alpha = appear }
            .defaultMinSize(minHeight = 48.dp)
            .then(if (selected) Modifier.shadow(10.dp, shape, ambientColor = a.copy(0.5f), spotColor = a.copy(0.5f)).clip(shape).background(Brush.linearGradient(listOf(a, b)), shape).border(1.dp, Color.White.copy(0.5f), shape) else Modifier.glass(shape))
            .clickable(MutableInteractionSource(), null) {
                scope.launch { pulse.animateTo(0.88f, tween(90)); pulse.animateTo(1.1f, spring(0.5f, 500f)); pulse.animateTo(1f, spring(0.8f, 300f)) }
                scope.launch { ring.snapTo(0f); ring.animateTo(1f, tween(500, easing = EaseOut)) }
                onClick()
            }
            .drawWithContent {
                drawContent()
                val r = ring.value
                if (r > 0f && r < 1f) drawRoundRect(a.copy(0.7f * (1 - r)), Offset(-size.width * 0.25f * r, -size.height * 0.25f * r), Size(size.width * (1 + 0.5f * r), size.height * (1 + 0.5f * r)), androidx.compose.ui.geometry.CornerRadius(size.height), style = Stroke(2.dp.toPx()))
            }
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(sf(g.icon), null, tint = if (selected) Color.White else Theme.text, modifier = Modifier.size(17.dp))
            Text(genreShort(g), style = Theme.font(15.5f, FontWeight.SemiBold, if (selected) Color.White else Theme.text), maxLines = 1)
        }
    }
}

// ============================================================ 4. artistas

private val artistSuggestions: Map<String, List<String>> = mapOf(
    "sertanejo" to listOf("Gusttavo Lima", "Jorge & Mateus", "Henrique & Juliano", "Marília Mendonça", "Ana Castela", "Luan Santana"),
    "funk_br" to listOf("MC Ryan SP", "MC Cabelinho", "Anitta", "MC Hariel", "Kevinho", "MC Livinho"),
    "pagode" to listOf("Thiaguinho", "Menos É Mais", "Ferrugem", "Grupo Revelação", "Péricles", "Dilsinho"),
    "mpb" to listOf("Caetano Veloso", "Gilberto Gil", "Djavan", "Milton Nascimento", "Marisa Monte", "Jorge Ben Jor"),
    "forro" to listOf("Zé Vaqueiro", "Natanzinho Lima", "Mari Fernandez", "Xand Avião", "Wesley Safadão", "Luiz Gonzaga"),
    "gospel" to listOf("Aline Barros", "Fernandinho", "Gabriela Rocha", "Isadora Pompeo", "Thalles Roberto", "Hillsong United"),
    "pop" to listOf("Taylor Swift", "Dua Lipa", "Ariana Grande", "Billie Eilish", "The Weeknd", "Sabrina Carpenter"),
    "rock" to listOf("Queen", "Foo Fighters", "Legião Urbana", "Nirvana", "Imagine Dragons", "Capital Inicial"),
    "hiphop" to listOf("Kendrick Lamar", "Drake", "Travis Scott", "Emicida", "Djonga", "Eminem"),
    "eletronica" to listOf("Alok", "Calvin Harris", "David Guetta", "Martin Garrix", "Vintage Culture", "Avicii"),
    "rnb" to listOf("SZA", "Beyoncé", "Bruno Mars", "Frank Ocean", "Rihanna", "Usher"),
    "latina" to listOf("Bad Bunny", "Shakira", "J Balvin", "Karol G", "Rosalía", "Daddy Yankee"),
    "kpop" to listOf("BTS", "BLACKPINK", "NewJeans", "Stray Kids", "TWICE", "LE SSERAFIM"),
    "metal" to listOf("Metallica", "Iron Maiden", "Sepultura", "Black Sabbath", "Slipknot", "Angra"),
    "indie" to listOf("Arctic Monkeys", "Tame Impala", "Lana Del Rey", "Mac DeMarco", "Radiohead", "Terno Rei"),
    "jazz" to listOf("Miles Davis", "Norah Jones", "Louis Armstrong", "John Coltrane", "Ella Fitzgerald", "Diana Krall"),
    "classica" to listOf("Mozart", "Beethoven", "Chopin", "Ludovico Einaudi", "Vivaldi", "Johann Sebastian Bach"),
    "reggae" to listOf("Bob Marley", "Natiruts", "Jimmy Cliff", "Ponto de Equilíbrio", "Peter Tosh", "Gregory Isaacs"),
    "country" to listOf("Luke Combs", "Morgan Wallen", "Johnny Cash", "Dolly Parton", "Zach Bryan", "Chris Stapleton"),
    "soundtrack" to listOf("Hans Zimmer", "John Williams", "Ramin Djawadi", "Ennio Morricone", "Joe Hisaishi", "Howard Shore"),
)

/** Intercala os estilos escolhidos para variar (até 15 nomes). */
private fun suggestionsFor(genres: List<MusicGenre>): List<String> {
    val ids = if (genres.isEmpty()) listOf("pop", "sertanejo", "funk_br") else genres.map { it.id }
    val out = ArrayList<String>()
    var round = 0
    while (out.size < 15 && round < 6) {
        for (id in ids) { val arr = artistSuggestions[id]; if (arr != null && round < arr.size && arr[round] !in out && out.size < 15) out.add(arr[round]) }
        round++
    }
    return out
}

@Composable
private fun ArtistsStep(genres: List<MusicGenre>, selected: MutableList<String>, onNext: () -> Unit) {
    val suggestions = remember(genres) { suggestionsFor(genres) }
    val pics = remember { mutableStateMapOf<String, String>() }
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<ArtistInfo>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    val closeKeyboard = rememberKeyboardCloser()
    val names = results.map { it.name }.filter { it !in suggestions } + suggestions

    LaunchedEffect(suggestions) {
        coroutineScope {
            suggestions.map { name -> async { runCatching {
                val hits = SearchService.artists(name)
                val best = hits.firstOrNull { it.name.equals(name, ignoreCase = true) } ?: hits.firstOrNull()
                if (best != null && best.pictureURL.isNotEmpty()) pics[name] = best.pictureURL
            } } }.awaitAll()
        }
    }
    LaunchedEffect(query) {
        val q = query.trim()
        if (q.length < 2) { results = emptyList(); searching = false; return@LaunchedEffect }
        searching = true
        delay(350)
        val r = runCatching { SearchService.artists(q) }.getOrDefault(emptyList()).take(9)
        results = r
        for (a in r) if (a.pictureURL.isNotEmpty()) pics[a.name] = a.pictureURL
        searching = false
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 28.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Artistas que você ama", style = roundedTitle.copy(fontSize = 28.sp, color = Theme.text), textAlign = TextAlign.Center)
            Text("Opcional. Eles aparecem primeiro nos seus lançamentos.", style = Theme.font(14.5f, color = Theme.secondary), textAlign = TextAlign.Center)
        }
        Row(
            Modifier.padding(horizontal = 24.dp).padding(top = 16.dp).fillMaxWidth().height(48.dp).glass(RoundedCornerShape(50)).padding(start = 16.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(sf("magnifyingglass"), null, tint = Theme.secondary, modifier = Modifier.size(17.dp))
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) Text("Buscar outro artista", style = Theme.font(15.5f, color = Theme.tertiary))
                BasicTextField(query, { query = it }, singleLine = true, textStyle = Theme.font(15.5f, color = Theme.text), cursorBrush = SolidColor(Theme.rose),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { closeKeyboard() }),
                    modifier = Modifier.fillMaxWidth())
            }
            if (searching) CircularProgressIndicator(Modifier.size(18.dp), color = Theme.secondary, strokeWidth = 2.dp)
            else if (query.isNotEmpty()) Box(Modifier.size(Chrome.minTouch).pressable(0.9f) { query = "" }, contentAlignment = Alignment.Center) { Icon(sf("xmark.circle.fill"), "Limpar", tint = Theme.tertiary, modifier = Modifier.size(20.dp)) }
            else Spacer(Modifier.width(12.dp))
        }
        LazyVerticalGrid(
            GridCells.Fixed(3), Modifier.weight(1f).fillMaxWidth(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 18.dp, vertical = 18.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            itemsIndexed(names, key = { _, n -> n }) { i, name ->
                val appear = appearProgress(min(i, 12) * 40, 0.5f, 0.75f)
                Box(Modifier.graphicsLayer { val s = 0.6f + 0.4f * appear; scaleX = s; scaleY = s; alpha = appear }, contentAlignment = Alignment.TopCenter) {
                    ArtistBubble(name, pics[name], name in selected) {
                        if (name in selected) { selected.remove(name); SoundFX.play(SoundFX.Effect.DESELECT); Haptics.light() }
                        else { selected.add(name); SoundFX.play(SoundFX.Effect.SELECT); Haptics.medium() }
                    }
                }
            }
        }
        Column(Modifier.padding(horizontal = 28.dp).padding(top = 8.dp, bottom = 26.dp)) {
            PrismCta(if (selected.isEmpty()) "Continuar sem escolher" else "Continuar · ${selected.size}", "arrow.right", 54) { onNext() }
        }
    }
}

@Composable
private fun ArtistBubble(name: String, picture: String?, selected: Boolean, onClick: () -> Unit) {
    val s by animateFloatAsState(if (selected) 1.06f else 1f, spring(0.7f, 250f), label = "bub")
    Column(Modifier.defaultMinSize(minHeight = 44.dp).pressable(0.94f) { onClick() }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(contentAlignment = Alignment.BottomEnd) {
            Box(
                Modifier.size(92.dp).graphicsLayer { scaleX = s; scaleY = s }
                    .then(if (selected) Modifier.shadow(10.dp, CircleShape, ambientColor = Theme.rose.copy(0.45f), spotColor = Theme.rose.copy(0.45f)) else Modifier)
                    .clip(CircleShape).background(Theme.fillStrong, CircleShape)
                    .border(if (selected) 4.dp else 1.dp, if (selected) Theme.prismSweep else SolidColor(Theme.hairline), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                if (!picture.isNullOrEmpty()) ArtworkImage(picture, Modifier.fillMaxSize(), shape = CircleShape, icon = "person.fill")
                else Icon(sf("person.fill"), null, tint = Theme.tertiary, modifier = Modifier.size(30.dp))
            }
            CheckBadge(selected)
        }
        Text(name, style = Theme.font(12.5f, if (selected) FontWeight.SemiBold else FontWeight.Medium, if (selected) Theme.text else Theme.secondary), textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.height(32.dp))
    }
}

// ============================================================ 5. importar

@Composable
private fun ImportStep(onImport: () -> Unit, onNext: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 28.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Traga sua música", style = roundedTitle.copy(fontSize = 28.sp, color = Theme.text), textAlign = TextAlign.Center)
            Text("Já tem playlists em outro serviço? Traga tudo para cá com um toque.", style = Theme.font(14.5f, color = Theme.secondary), textAlign = TextAlign.Center)
        }
        Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 22.dp, vertical = 20.dp)) {
            Column(
                Modifier.fillMaxWidth().glass(RoundedCornerShape(24.dp)).pressable(0.97f) { onImport() }.padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(Modifier.size(84.dp).glass(CircleShape), contentAlignment = Alignment.Center) { Icon(sf("square.and.arrow.down"), null, tint = Theme.sky, modifier = Modifier.size(40.dp)) }
                Text("Importar playlists", style = Theme.font(17f, FontWeight.Bold, Theme.text))
                Text("Spotify, YouTube Music, Deezer e mais", style = Theme.font(13.5f, color = Theme.secondary), textAlign = TextAlign.Center)
            }
        }
        Column(Modifier.padding(horizontal = 28.dp).padding(top = 8.dp, bottom = 26.dp), verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            GlassCta("Agora não, importo depois", 54) { onNext() }
            Text("Você pode importar a qualquer hora em Biblioteca.", style = Theme.font(12f, color = Theme.tertiary))
        }
    }
}

// ============================================================ 6. tudo pronto

@Composable
private fun DoneStep(centerY: Float, genres: List<MusicGenre>, artists: Int, onEnter: () -> Unit) {
    val burst = remember { Animatable(0f) }
    val grow = remember { Animatable(0.4f) }
    LaunchedEffect(Unit) {
        SoundFX.play(SoundFX.Effect.SUCCESS); Haptics.success()
        launch { grow.animateTo(1f, spring(0.7f, 80f)) }
        delay(250); burst.animateTo(1f, tween(1100, easing = EaseOut))
    }
    val show = appearProgress(200, 0.7f, 0.82f)
    val density = LocalDensity.current.density
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().offset(y = (centerY - 40 - 150).dp).height(300.dp), contentAlignment = Alignment.Center) {
            for (i in 0 until 12) {
                val a = i / 12.0 * 2 * PI
                val b = burst.value
                Box(Modifier.offset { IntOffset((cos(a) * 128 * b * density).toInt(), (sin(a) * 128 * b * density).toInt()) }.graphicsLayer { alpha = 1f - b; val s = 0.2f + 0.8f * b; scaleX = s; scaleY = s }) {
                    if (i % 3 == 0) Icon(sf("sparkles"), null, tint = Theme.prismColors[i % 4], modifier = Modifier.size(16.dp))
                    else Box(Modifier.size(6.dp).background(Theme.prismColors[i % 4], CircleShape))
                }
            }
            Box(Modifier.size(200.dp).graphicsLayer { scaleX = grow.value; scaleY = grow.value }.background(Color.White.copy(0.07f), CircleShape))
        }
        Column(Modifier.fillMaxSize().graphicsLayer { alpha = show; translationY = (1f - show) * 20f * density }, horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            Text("Tudo pronto!", style = roundedTitle.copy(fontSize = 36.sp, color = Theme.text))
            Text(summary(genres, artists), style = Theme.font(15.5f, color = Theme.secondary), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 36.dp).padding(top = 10.dp))
            PrismCta("Entrar na Lume", "sparkles", 56, modifier = Modifier.padding(horizontal = 28.dp).padding(top = 28.dp, bottom = 40.dp)) { onEnter() }
        }
    }
}

private fun summary(genres: List<MusicGenre>, artists: Int): String {
    val parts = ArrayList<String>()
    if (genres.isNotEmpty()) {
        val names = genres.take(3).joinToString(", ") { genreShort(it) }
        parts.add("Montamos a sua Lume com $names" + (if (genres.size > 3) " e mais ${genres.size - 3}" else "") + ".")
    } else parts.add("A sua Lume está pronta. Você pode afinar os estilos depois.")
    if (artists > 0) parts.add("$artists artista${if (artists == 1) "" else "s"} para acompanhar.")
    return parts.joinToString(" ")
}

// ============================================================ carregando suas músicas

/** Pré-carrega de verdade o que a Home usa (feed + vitrines dos gêneros + capas) enquanto a animação roda. */
private class LoadingMusicModel {
    var covers by mutableStateOf<List<String>>(emptyList())
    var doneTasks by mutableIntStateOf(0)
    var totalTasks = 1
    val taskFraction: Float get() = if (totalTasks > 0) doneTasks.toFloat() / totalTasks else 1f

    suspend fun start(ctx: Context, genres: List<MusicGenre>) = coroutineScope {
        val hub = genres.take(3)
        totalTasks = 2 + hub.size
        val lists = MutableList(hub.size) { emptyList<String>() }
        // Capas do cache aparecem na hora (nada de esperar a rede para trocar os quadrados coloridos).
        withContext(Dispatchers.IO) { runCatching { DiscoveryService.cachedFeed() } }.getOrNull()?.let { AppModel.setFeedIfEmpty(it); fillFromFeedNow() }
        launch { runCatching { AppModel.loadFeed() }; doneTasks++ }
        launch {
            // Uma vitrine leve por gênero (álbuns do Apple Music): cada uma publica as capas assim que chega,
            // sem esperar o pacote completo do gênero (músicas, artistas, playlists), que só aquece o cache da Home.
            hub.mapIndexed { i, g ->
                async {
                    runCatching { GenreSources.albums(g, 16).map { it.artworkURL }.filter { it.isNotEmpty() } }.getOrDefault(emptyList())
                        .also { synchronized(lists) { lists[i] = it; merge(lists) }; doneTasks++ }
                    launch(Dispatchers.IO) { runCatching { CatalogExplorerService.genreHub(g) } }
                }
            }.awaitAll()
            fillFromFeed()
            decode(ctx)
            doneTasks++
        }
        // O feed chega em paralelo: completa a estante assim que existir.
        launch { fillFromFeed() }
    }

    private fun merge(lists: List<List<String>>) {
        val out = ArrayList<String>()
        var round = 0
        while (out.size < 12 && round < 12) {
            for (l in lists) if (round < l.size && l[round] !in out && out.size < 12) out.add(l[round])
            round++
        }
        if (out.isNotEmpty()) covers = out
        fillFromFeedNow()
    }

    private suspend fun fillFromFeed() {
        if (covers.size >= 12) return
        for (n in 0 until 25) { if (AppModel.feed != null) break; delay(200) }
        fillFromFeedNow()
    }

    /** Completa a estante (até 12) com lançamentos/top do feed. */
    private fun fillFromFeedNow() {
        if (covers.size >= 12) return
        val feed = AppModel.feed ?: return
        val pool = (feed.newReleases + feed.brazilReleases + (feed.topAlbumsBrazil ?: emptyList()) + (feed.topAlbumsGlobal ?: emptyList())).shuffled()
        val out = covers.toMutableList()
        for (a in pool) if (a.artworkURL.isNotEmpty() && a.artworkURL !in out && out.size < 12) out.add(a.artworkURL)
        if (out.size > covers.size) covers = out
    }

    private suspend fun decode(ctx: Context) {
        val loader = SingletonImageLoader.get(ctx)
        coroutineScope { covers.map { u -> async { runCatching { loader.execute(ImageRequest.Builder(ctx).data(u).build()) } } }.awaitAll() }
    }
}

private val phrases = listOf("Afinando seus gêneros…", "Buscando lançamentos…", "Montando sua biblioteca…", "Quase lá…")

/** "Carregando suas músicas": disco de vidro girando, capas voando para a estante, anel de progresso prisma e frases. 3,5 s a 6 s. */
@Composable
private fun LoadingMusicView(genres: List<MusicGenre>, running: Boolean, onFinish: () -> Unit) {
    val ctx = LocalContext.current
    val model = remember { LoadingMusicModel() }
    val tints = if (genres.isEmpty()) listOf(MusicGenre.all[0], MusicGenre.all[6], MusicGenre.all[1]) else genres
    val start = remember { System.nanoTime() }
    val landed = remember { mutableStateListOf<Boolean>().also { l -> repeat(12) { l.add(false) } } }
    var progress by remember { mutableFloatStateOf(0f) }
    var finished by remember { mutableStateOf(false) }
    var elapsed by remember { mutableFloatStateOf(0f) }
    val reduce = reduceMotion()
    val spin by rememberInfiniteTransition(label = "spin").animateFloat(0f, 360f, infiniteRepeatable(tween(3200, easing = LinearEasing)), label = "markSpin")

    LaunchedEffect(Unit) {
        launch { model.start(ctx, genres) }
        for (i in 0 until 12) launch {
            delay(250L + i * 170L); landed[i] = true
            if (i % 3 == 0) SoundFX.play(SoundFX.Effect.TAP)
        }
    }
    LaunchedEffect(running) {
        if (!running) return@LaunchedEffect
        var last = 0L
        while (!finished) {
            val n = withFrameNanos { it }
            if (n - last < 33_000_000L) continue
            last = n
            val e = (System.nanoTime() - start) / 1e9f
            elapsed = e
            val timeFrac = min(1f, e / 3.5f)
            val cap = if (model.taskFraction >= 1f) 1f else 0.92f
            progress = if (e >= 6f) 1f else min(timeFrac, cap)
            if (progress >= 1f || e >= 6f) { finished = true; onFinish() }
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
        val mw = maxWidth.value
        val tile = min(86f, (mw - 48f - 10f * 3) / 4f)
        val fillStrong = Theme.fillStrong
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            // disco + anel de progresso
            Box(Modifier.size(148.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    val sw = 6.dp.toPx()
                    drawCircle(fillStrong, size.minDimension / 2 - sw / 2, style = Stroke(sw))
                    drawArc(Theme.prismSweep, -90f, 360f * progress, false, topLeft = Offset(sw / 2, sw / 2), size = Size(size.width - sw, size.height - sw), style = Stroke(sw, cap = StrokeCap.Round))
                }
                Box(Modifier.size(128.dp).glass(CircleShape, Theme.lavender.copy(0.15f)))
                Box(Modifier.graphicsLayer { rotationZ = if (reduce) 0f else spin }) { PrismMark(104f) }
            }
            Text("Carregando suas músicas", style = roundedTitle.copy(fontSize = 24.sp, color = Theme.text), modifier = Modifier.padding(top = 22.dp))
            val pi = min(phrases.size - 1, (elapsed / 1.25f).toInt())
            Box(Modifier.padding(top = 6.dp).height(28.dp).clip(androidx.compose.ui.graphics.RectangleShape), contentAlignment = Alignment.Center) {
                AnimatedContent(pi, label = "phrase", transitionSpec = {
                    (slideInVertically(spring(0.85f, 200f)) { it } + fadeIn()) togetherWith (slideOutVertically(spring(0.85f, 200f)) { -it } + fadeOut())
                }) { i -> Text(phrases[max(0, i)], style = Theme.font(15f, FontWeight.Medium, Theme.secondary)) }
            }
            Spacer(Modifier.weight(0.8f))
            // estante: capas voam e se encaixam
            Column(Modifier.padding(horizontal = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                for (row in 0 until 3) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            for (col in 0 until 4) {
                                val i = row * 4 + col
                                CoverTile(model.covers.getOrNull(i), tints[i % tints.size], tile, landed[i], i, mw)
                            }
                        }
                        Box(Modifier.width((mw - 40f).dp).height(5.dp).alpha(0.8f).glass(RoundedCornerShape(50)))
                    }
                }
            }
            Spacer(Modifier.height(36.dp))
        }
    }
}

@Composable
private fun CoverTile(url: String?, genre: MusicGenre, size: Float, landed: Boolean, index: Int, width: Float) {
    val k = (2f * PI.toFloat() / 0.6f).let { it * it }
    val p by animateFloatAsState(if (landed) 1f else 0f, spring(0.72f, k), label = "fly")
    val a = index * 2.399
    val sx = (cos(a) * width * 0.9).toFloat(); val sy = (sin(a) * 420 - 120).toFloat()
    val tilt = (((index * 37) % 9) - 4).toFloat()
    val ca = hex(genre.hexA, 0.85f); val cb = hex(genre.hexB, 0.85f)
    val shape = RoundedCornerShape(14.dp)
    Box(
        Modifier.size(size.dp).graphicsLayer {
            translationX = (1f - p) * sx * density; translationY = (1f - p) * sy * density
            rotationZ = (1f - p) * tilt * 14f
            val s = 0.3f + 0.7f * p; scaleX = s; scaleY = s
            alpha = p.coerceIn(0f, 1f)
        }.shadow(6.dp, shape, ambientColor = Color.Black.copy(0.18f), spotColor = Color.Black.copy(0.18f)).clip(shape)
            .background(Brush.linearGradient(listOf(ca, cb))).border(0.8.dp, Color.White.copy(0.35f), shape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(sf(genre.icon), null, tint = Color.White.copy(0.7f), modifier = Modifier.size((size * 0.32f).dp))
        if (url != null) ArtworkImage(url, Modifier.fillMaxSize(), cornerRadius = 14.dp)
    }
}

@Composable
private fun CheckBadge(selected: Boolean) {
    AnimatedVisibility(selected, enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
        Box(Modifier.size(26.dp).background(Theme.prismDiagonal, CircleShape).border(1.dp, Color.White.copy(0.6f), CircleShape), contentAlignment = Alignment.Center) {
            Icon(sf("checkmark"), null, tint = Theme.onPrism, modifier = Modifier.size(13.dp))
        }
    }
}
