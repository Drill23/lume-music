package com.adriano.lumemusic.ui.screens

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.access.AccessState
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.GlassButton
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.LumeWordmark
import com.adriano.lumemusic.ui.PrismButton
import com.adriano.lumemusic.ui.PrismChip
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.sin

/** Sons curtos sintetizados (equivalente ao SoundFX do iOS): um "plim" por gênero, escala pentatônica. */
object SoundFX {
    private val scope = CoroutineScope(Dispatchers.Default)
    private val notes = doubleArrayOf(261.6, 293.7, 329.6, 392.0, 440.0, 523.3, 587.3, 659.3, 784.0)
    fun chime(index: Int) = play(notes[index.mod(notes.size)])

    fun play(freq: Double) {
        scope.launch {
            try {
                val sr = 22050
                val n = (sr * 0.28).toInt()
                val pcm = ShortArray(n) { i ->
                    val t = i.toDouble() / sr
                    val env = minOf(1.0, i / (sr * 0.01)) * Math.exp(-t * 9.0)
                    ((sin(2 * PI * freq * t) * 0.6 + sin(2 * PI * freq * 2 * t) * 0.15) * env * 9000).toInt().toShort()
                }
                val track = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(sr).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setBufferSizeInBytes(n * 2).setTransferMode(AudioTrack.MODE_STATIC).build()
                track.write(pcm, 0, n)
                track.play()
                delay(450)
                track.release()
            } catch (_: Exception) {}
        }
    }
}

object Onboarding {
    private fun prefs(c: Context) = c.getSharedPreferences("lume_prefs", Context.MODE_PRIVATE)
    fun isDone(c: Context) = prefs(c).getBoolean("onboarded", false)
    fun setDone(c: Context) = prefs(c).edit().putBoolean("onboarded", true).apply()
    fun saveGenres(c: Context, ids: Set<String>) = prefs(c).edit().putStringSet("genres", ids).apply()
    fun genres(c: Context): Set<String> = prefs(c).getStringSet("genres", emptySet()) ?: emptySet()
}

private enum class Step { WELCOME, ACCESS, GENRES, ARTISTS, IMPORT, READY, LOADING }

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    val ctx = LocalContext.current
    val accessState by Access.service.state.collectAsState()
    val needsAccess = Access.service.gateEnabled() && accessState !is AccessState.Active
    var step by remember { mutableStateOf(Step.WELCOME) }
    var picked by remember { mutableStateOf(setOf<String>()) }
    var openImport by remember { mutableStateOf(false) }
    val order = listOf(Step.WELCOME, Step.ACCESS, Step.GENRES, Step.ARTISTS, Step.IMPORT, Step.READY, Step.LOADING)
    fun next() {
        var i = order.indexOf(step) + 1
        if (order[i] == Step.ACCESS && !needsAccess) i++
        step = order[i]
    }

    Box(Modifier.fillMaxSize().background(Theme.canvas)) {
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(Theme.peach.copy(0.30f), Color.Transparent), center = androidx.compose.ui.geometry.Offset(100f, 100f), radius = 1100f)))
        Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(Theme.lavender.copy(0.30f), Color.Transparent), center = androidx.compose.ui.geometry.Offset(1100f, 2200f), radius = 1400f)))
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(vertical = 20.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp), horizontalArrangement = Arrangement.Center) {
                for (s in order.dropLast(1)) {
                    if (s == Step.ACCESS && !needsAccess) continue
                    val on = order.indexOf(s) <= order.indexOf(step)
                    Box(Modifier.padding(horizontal = 3.dp).size(width = if (s == step) 22.dp else 7.dp, height = 7.dp).clip(CircleShape).background(if (on) Theme.rose else Theme.fillStrong))
                }
            }
            AnimatedContent(step, Modifier.weight(1f).fillMaxWidth(), label = "onb", transitionSpec = {
                (slideInHorizontally(tween(320)) { it / 4 } + fadeIn(tween(320))) togetherWith (slideOutHorizontally(tween(240)) { -it / 4 } + fadeOut(tween(200)))
            }) { s ->
                when (s) {
                    Step.WELCOME -> StepFrame("Bem-vindo à Lume", "Vamos deixar a Lume com a sua cara em menos de um minuto.", "Continuar", { next() }, hero = { LumeWordmark(40f) })
                    Step.ACCESS -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                        var done by remember { mutableStateOf<com.adriano.lumemusic.access.AccessInfo?>(null) }
                        if (done != null) AccessSuccessView(done!!, "Continuar") { next() }
                        else AccessCodeEntry("Digite seu código de acesso", "Quem te enviou o código também te mostra o prazo.", "Ativar") { done = it }
                    }
                    Step.GENRES -> StepFrame("Qual estilo você mais curte?", "Toque nos que combinam com você. Pode escolher vários.", "Continuar", { Onboarding.saveGenres(ctx, picked); next() }) {
                        FlowRow(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            MusicGenre.all.forEachIndexed { i, g ->
                                PrismChip(g.title, g.id in picked, g.icon) {
                                    picked = if (g.id in picked) picked - g.id else { SoundFX.chime(i); picked + g.id }
                                }
                            }
                        }
                    }
                    Step.ARTISTS -> {
                        val feed = AppModel.feed
                        val artists = remember(feed) { ((feed?.topArtists ?: emptyList()) + (feed?.globalTopArtists ?: emptyList())).distinctBy { it.name.lowercase() }.take(24) }
                        StepFrame("Artistas que você ama", "Opcional. Eles aparecem primeiro nos seus lançamentos.", "Continuar", { next() }, skip = "Pular") {
                            LazyVerticalGrid(GridCells.Fixed(3), Modifier.fillMaxWidth().height(430.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                items(artists, key = { it.id }) { a -> ArtistPick(a) }
                            }
                        }
                    }
                    Step.IMPORT -> StepFrame("Traga sua música", "Já tem playlists em outro serviço? Traga tudo para cá com um toque.", "Importar agora", { openImport = true; next() }, skip = "Agora não, importo depois", onSkip = { next() }) {
                        Box(Modifier.size(110.dp).glass(CircleShape), contentAlignment = Alignment.Center) { Icon(sf("square.and.arrow.down"), null, tint = Theme.sky, modifier = Modifier.size(52.dp)) }
                    }
                    Step.READY -> StepFrame("Tudo pronto!", "Você pode importar a qualquer hora em Biblioteca.", "Entrar na Lume", { next() }) {
                        Box(Modifier.size(110.dp).glass(CircleShape), contentAlignment = Alignment.Center) { Icon(sf("sparkles"), null, tint = Theme.rose, modifier = Modifier.size(52.dp)) }
                    }
                    Step.LOADING -> LoadingShelf {
                        Onboarding.setDone(ctx)
                        onFinished()
                        if (openImport) AppModel.push(LumeRoute.ImportHub)
                    }
                }
            }
        }
    }
}

@Composable
private fun ArtistPick(a: ArtistInfo) {
    val on = LibraryStore.isFollowing(a.name)
    Column(Modifier.pressable(0.95f) { Haptics.selection(); LibraryStore.toggleFollow(a.name) }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(contentAlignment = Alignment.BottomEnd) {
            ArtworkImage(a.pictureURL, Modifier.size(88.dp), shape = CircleShape, icon = "person.fill")
            if (on) Box(Modifier.size(26.dp).background(Theme.rose, CircleShape), contentAlignment = Alignment.Center) { Icon(sf("checkmark"), null, tint = Color.White, modifier = Modifier.size(16.dp)) }
        }
        Text(a.name, style = Theme.font(12.5f, FontWeight.Medium, Theme.text), maxLines = 1, textAlign = TextAlign.Center)
    }
}

@Composable
private fun StepFrame(title: String, subtitle: String, cta: String, onCta: () -> Unit, skip: String? = null, onSkip: () -> Unit = onCta, hero: @Composable () -> Unit = {}, content: @Composable () -> Unit = {}) {
    Column(Modifier.fillMaxSize().padding(top = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(Modifier.weight(1f).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically)) {
            hero()
            Text(title, style = Theme.font(28f, FontWeight.Bold, Theme.text), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 28.dp))
            Text(subtitle, style = Theme.font(15.5f, color = Theme.secondary), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 36.dp))
            content()
        }
        Column(Modifier.padding(horizontal = 28.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            PrismButton(cta) { onCta() }
            if (skip != null) Box(Modifier.fillMaxWidth().height(48.dp).pressable(0.97f) { onSkip() }, contentAlignment = Alignment.Center) { Text(skip, style = Theme.font(15f, FontWeight.Medium, Theme.secondary)) }
        }
    }
}

/** Carregamento ~5 s: capas voam para a estante enquanto a barra enche. */
@Composable
private fun LoadingShelf(onDone: () -> Unit) {
    val covers = remember { (AppModel.feed?.topBrazil ?: emptyList()).map { it.artworkURL }.filter { it.isNotEmpty() }.distinct().take(10) }
    var p by remember { mutableFloatStateOf(0f) }
    val density = LocalDensity.current
    LaunchedEffect(Unit) {
        val t0 = System.nanoTime()
        while (p < 1f) { delay(16); p = ((System.nanoTime() - t0) / 5e9f).coerceAtMost(1f) }
        delay(200); onDone()
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.align(Alignment.TopCenter).padding(top = 70.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Carregando suas músicas", style = Theme.font(24f, FontWeight.Bold, Theme.text))
            Text("Montando a estante da Lume…", style = Theme.font(14.5f, color = Theme.secondary))
        }
        covers.forEachIndexed { i, url ->
            val t = ((p * 1.35f - i * 0.07f)).coerceIn(0f, 1f)
            val e = t * t * (3 - 2 * t)
            val fromX = (((i * 97) % 5) - 2) * 90f
            val toX = (i - (covers.size - 1) / 2f) * 34f
            val size = 74.dp
            Box(Modifier.align(Alignment.Center).offset { IntOffset(with(density) { ((fromX + (toX - fromX) * e)).dp.roundToPx() }, with(density) { ((260f - 560f * e + 0f)).dp.roundToPx() }) }
                .graphicsLayer { alpha = if (t <= 0f) 0f else 1f; rotationZ = (1 - e) * (i % 3 - 1) * 14f; val s = 1.25f - 0.45f * e; scaleX = s; scaleY = s }.size(size)) {
                ArtworkImage(url, Modifier.size(size), 14.dp)
            }
        }
        Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 70.dp).fillMaxWidth(0.62f).height(6.dp).clip(CircleShape).background(Theme.fillStrong)) {
            Box(Modifier.fillMaxWidth(p).fillMaxSize().background(Theme.prismHorizontal))
        }
    }
}
