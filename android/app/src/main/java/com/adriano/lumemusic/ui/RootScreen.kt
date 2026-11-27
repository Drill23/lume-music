package com.adriano.lumemusic.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.audio.PlaybackClock
import com.adriano.lumemusic.data.AppTab
import com.adriano.lumemusic.data.DownloadManager
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.screens.AlbumGridScreen
import com.adriano.lumemusic.ui.screens.AlbumScreen
import com.adriano.lumemusic.ui.screens.ArtistGridScreen
import com.adriano.lumemusic.ui.screens.ArtistScreen
import com.adriano.lumemusic.ui.screens.CountryChartScreen
import com.adriano.lumemusic.ui.screens.DownloadsScreen
import com.adriano.lumemusic.ui.screens.EqualizerScreen
import com.adriano.lumemusic.ui.screens.ExploreScreen
import com.adriano.lumemusic.ui.screens.GenreHubScreen
import com.adriano.lumemusic.ui.screens.HomeScreen
import com.adriano.lumemusic.ui.screens.ImportScreen
import com.adriano.lumemusic.ui.screens.LibraryScreen
import com.adriano.lumemusic.ui.screens.MixScreen
import com.adriano.lumemusic.ui.screens.MoodScreen
import com.adriano.lumemusic.ui.screens.NowPlayingScreen
import com.adriano.lumemusic.ui.screens.PlaylistScreen
import com.adriano.lumemusic.ui.screens.RemotePlaylistScreen
import com.adriano.lumemusic.ui.screens.ReleasesScreen
import com.adriano.lumemusic.ui.screens.ReplayScreen
import com.adriano.lumemusic.ui.screens.SearchScreen
import com.adriano.lumemusic.ui.screens.SettingsScreen
import com.adriano.lumemusic.ui.screens.TrackListScreen
import com.adriano.lumemusic.ui.theme.LocalHaze
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import kotlin.math.abs
import kotlin.math.roundToInt

@Composable
fun RootScreen() {
    val haze = rememberHazeState()
    val visited = remember { mutableSetOf(AppTab.HOME) }
    visited.add(AppModel.tab)
    val hasTrack = AudioPlayer.currentTrack != null
    val bottomInset = if (hasTrack) 150.dp else 92.dp
    val appCtx = androidx.compose.ui.platform.LocalContext.current
    var onboarding by remember { androidx.compose.runtime.mutableStateOf(LibraryStore.introEnabled && !com.adriano.lumemusic.ui.screens.Onboarding.isDone(appCtx)) }

    // Permissão de notificações (Android 13+): só depois do onboarding, na primeira vez que uma música começa a tocar.
    val notifLauncher = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(onboarding, AudioPlayer.isPlaying) {
        if (onboarding || !AudioPlayer.isPlaying || android.os.Build.VERSION.SDK_INT < 33) return@LaunchedEffect
        val prefs = appCtx.getSharedPreferences("lume_prefs", android.content.Context.MODE_PRIVATE)
        val granted = androidx.core.content.ContextCompat.checkSelfPermission(appCtx, android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!granted && !prefs.getBoolean("notifAsked", false)) {
            prefs.edit().putBoolean("notifAsked", true).apply()
            notifLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    LaunchedEffect(Unit) {
        AppModel.loadFeed()
        AppModel.refreshArtistReleases()
    }
    LaunchedEffect(DownloadManager.lastMessage) { DownloadManager.lastMessage?.let { AppModel.showToast(it) } }
    LaunchedEffect(AudioPlayer.errorToast) { AudioPlayer.errorToast?.let { AppModel.showToast(it) } }

    BackHandler(enabled = AppModel.showCoverFlow || AppModel.showPlayer || AppModel.showQueue || AppModel.currentStack.isNotEmpty() || AppModel.tab != AppTab.HOME) {
        when {
            AppModel.showCoverFlow -> AppModel.showCoverFlow = false
            AppModel.showQueue -> AppModel.showQueue = false
            AppModel.showPlayer -> AppModel.showPlayer = false
            AppModel.pop() -> {}
            else -> AppModel.tab = AppTab.HOME
        }
    }

    androidx.compose.runtime.CompositionLocalProvider(LocalHaze provides haze) {
        Box(Modifier.fillMaxSize().background(Theme.canvas)) {
            Box(Modifier.fillMaxSize().hazeSource(haze)) {
                for (t in AppTab.entries) {
                    if (t !in visited) continue
                    val active = AppModel.tab == t
                    Box(Modifier.fillMaxSize().graphicsLayer { alpha = if (active) 1f else 0f }.then(if (active) Modifier else Modifier.size(0.dp))) {
                        TabHost(t, bottomInset)
                    }
                }
            }

            // Véu da barra de status (RootView do iOS): cobre a barra + 14dp, opaco → 0.92 → transparente; não captura toques.
            val statusH = with(LocalDensity.current) { WindowInsets.statusBars.getTop(this).toDp() }
            Box(
                Modifier.align(Alignment.TopCenter).fillMaxWidth().height(statusH + 14.dp).background(
                    Brush.verticalGradient(0f to Theme.canvas, 0.55f to Theme.canvas.copy(0.92f), 1f to Theme.canvas.copy(0f)),
                ),
            )

            Box(Modifier.align(Alignment.BottomCenter)) { BottomBar() }
            Toast(Modifier.align(Alignment.TopCenter))

            AnimatedVisibility(
                AppModel.showPlayer,
                enter = slideInVertically(spring(0.9f, 380f)) { it } + fadeIn(tween(180)),
                exit = slideOutVertically(tween(260)) { it } + fadeOut(tween(220)),
            ) { NowPlayingScreen() }

            SheetsHost()

            AnimatedVisibility(AppModel.showCoverFlow, enter = fadeIn(tween(250)), exit = fadeOut(tween(200))) { com.adriano.lumemusic.ui.screens.CoverFlowScreen() }

            if (onboarding) com.adriano.lumemusic.ui.screens.OnboardingScreen { onboarding = false }
            else com.adriano.lumemusic.ui.screens.AccessGateScreen()
        }
    }
}

@Composable
private fun TabHost(tab: AppTab, bottomInset: androidx.compose.ui.unit.Dp) {
    val stack = AppModel.stacks.getValue(tab)
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().padding(bottom = 0.dp)) {
            when (tab) {
                AppTab.HOME -> HomeScreen(bottomInset)
                AppTab.EXPLORE -> ExploreScreen(bottomInset)
                AppTab.LIBRARY -> LibraryScreen(bottomInset)
                AppTab.SEARCH -> SearchScreen(bottomInset)
            }
        }
        stack.forEachIndexed { i, route ->
            androidx.compose.runtime.key(i, route) {
                val state = remember { MutableTransitionState(false).apply { targetState = true } }
                AnimatedVisibility(
                    state,
                    enter = slideInHorizontally(spring(0.92f, 420f)) { (it * 0.28f).toInt() } + fadeIn(tween(200)),
                    exit = fadeOut(tween(120)),
                ) {
                    Box(Modifier.fillMaxSize().background(Theme.canvas).statusBarsPadding()) { RouteHost(route, bottomInset) }
                }
            }
        }
    }
}

@Composable
private fun RouteHost(route: LumeRoute, bottomInset: androidx.compose.ui.unit.Dp) {
    when (route) {
        is LumeRoute.Album -> AlbumScreen(route.album, bottomInset)
        is LumeRoute.Playlist -> PlaylistScreen(route.id, bottomInset)
        is LumeRoute.RemotePlaylistRoute -> RemotePlaylistScreen(route.playlist, bottomInset)
        is LumeRoute.Artist -> ArtistScreen(route.name, route.deezerId, bottomInset)
        LumeRoute.ImportHub -> ImportScreen(bottomInset)
        is LumeRoute.Mood -> MoodScreen(route.mood, bottomInset)
        is LumeRoute.Country -> CountryChartScreen(route.country, bottomInset)
        is LumeRoute.Genre -> GenreHubScreen(route.genre, bottomInset)
        is LumeRoute.Mix -> MixScreen(route.mix, bottomInset)
        LumeRoute.Releases -> ReleasesScreen(bottomInset)
        LumeRoute.GenresHub -> com.adriano.lumemusic.ui.screens.GenresHubScreen(bottomInset)
        LumeRoute.Downloads -> DownloadsScreen(bottomInset)
        LumeRoute.Replay -> ReplayScreen(bottomInset)
        LumeRoute.Equalizer -> EqualizerScreen(bottomInset)
        LumeRoute.Settings -> SettingsScreen(bottomInset)
        is LumeRoute.Tracks -> TrackListScreen(route.title, route.tracks, bottomInset)
        is LumeRoute.Albums -> AlbumGridScreen(route.title, route.albums, bottomInset)
        is LumeRoute.Artists -> ArtistGridScreen(route.title, route.artists, bottomInset)
    }
}

// ============================================================ Barra inferior flutuante

@Composable
fun BottomBar() {
    val track = AudioPlayer.currentTrack
    Column(
        Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 16.dp).padding(bottom = 6.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        AnimatedVisibility(track != null, enter = slideInVertically(spring(0.86f, 420f)) { it / 2 } + fadeIn(), exit = fadeOut(tween(150))) {
            if (track != null) MiniPlayer(track)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f).height(62.dp).glass(RoundedCornerShape(50), blur = true, elevation = 10.dp).padding(4.dp)) {
                for (t in AppTab.bar) {
                    val active = AppModel.tab == t
                    val iconColor = if (active) Theme.accent else Theme.text.copy(0.92f)
                    Column(
                        Modifier.weight(1f).height(54.dp).clip(RoundedCornerShape(50))
                            .background(if (active) Theme.fillStrong else androidx.compose.ui.graphics.Color.Transparent)
                            .pressable(0.92f) { AppModel.select(t) },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(sf(t.icon), t.title, tint = iconColor, modifier = Modifier.size(24.dp))
                        Text(t.title, style = Theme.font(10.5f, FontWeight.SemiBold, iconColor), maxLines = 1)
                    }
                }
            }
            val searchActive = AppModel.tab == AppTab.SEARCH
            Box(
                Modifier.size(62.dp).pressable(0.9f) { AppModel.select(AppTab.SEARCH) }.glass(CircleShape, blur = true, elevation = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (searchActive) Box(Modifier.size(54.dp).background(Theme.fillStrong, CircleShape))
                Icon(sf("magnifyingglass"), "Buscar", tint = if (searchActive) Theme.accent else Theme.text, modifier = Modifier.size(26.dp))
            }
        }
    }
}

@Composable
fun MiniPlayer(track: com.adriano.lumemusic.data.Track) {
    var dragX by remember { mutableFloatStateOf(0f) }
    val density = LocalDensity.current
    Box(
        Modifier.fillMaxWidth().height(60.dp).glass(RoundedCornerShape(50), blur = true, elevation = 10.dp)
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragEnd = {
                        val w = 60.dp.toPx()
                        if (dragX < -w) AudioPlayer.nextTrack() else if (dragX > w) AudioPlayer.previousTrack()
                        dragX = 0f
                    },
                    onDragCancel = { dragX = 0f },
                ) { _, d -> dragX += d }
            }
            .pressable(0.99f) { Haptics.light(); AppModel.openPlayer() },
    ) {
        Row(
            Modifier.fillMaxSize().padding(start = 8.dp, end = 6.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ArtworkImage(AudioPlayer.currentArtwork.ifEmpty { track.artworkURL }, Modifier.size(42.dp), 10.dp)
            Column(
                Modifier.weight(1f).offset { IntOffset((dragX * 0.4f).roundToInt(), 0) }.graphicsLayer { alpha = 1f - (minOf(abs(dragX), 300f) / 600f) },
            ) {
                Text(track.title, style = Theme.font(15f, FontWeight.SemiBold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(track.artist, style = Theme.font(13f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            val fav = track.id in LibraryStore.favoriteIds
            Box(Modifier.size(44.dp).pressable(0.85f) { LibraryStore.toggleFavorite(track) }, contentAlignment = Alignment.Center) {
                Icon(sf(if (fav) "heart.fill" else "heart"), if (fav) "Remover das curtidas" else "Curtir", tint = if (fav) Theme.rose else Theme.secondary,
                    modifier = Modifier.size(22.dp), )
            }
            Box(Modifier.size(44.dp).pressable(0.85f) { AudioPlayer.togglePlayPause() }, contentAlignment = Alignment.Center) {
                if (AudioPlayer.isLoading) CircularProgressIndicator(Modifier.size(20.dp), color = Theme.text, strokeWidth = 2.dp)
                else Icon(sf(if (AudioPlayer.isPlaying) "pause.fill" else "play.fill"), "Tocar/Pausar", tint = Theme.text, modifier = Modifier.size(26.dp))
            }
            Box(Modifier.size(44.dp).pressable(0.85f) { AudioPlayer.nextTrack() }, contentAlignment = Alignment.Center) {
                Icon(sf("forward.fill"), "Próxima", tint = Theme.text, modifier = Modifier.size(24.dp))
            }
        }
        MiniProgress(Modifier.align(Alignment.BottomCenter).padding(horizontal = 26.dp).padding(bottom = 3.dp))
    }
}

@Composable
private fun MiniProgress(modifier: Modifier) {
    val frac = if (PlaybackClock.duration > 0) (PlaybackClock.currentTime / PlaybackClock.duration).toFloat().coerceIn(0f, 1f) else 0f
    Box(modifier.fillMaxWidth().height(2.5.dp).clip(CircleShape).background(Theme.text.copy(0.10f))) {
        Box(Modifier.fillMaxWidth(frac).fillMaxSize().background(Theme.prismHorizontal))
    }
}

@Composable
private fun Toast(modifier: Modifier) {
    val msg = AppModel.toast
    AnimatedVisibility(msg != null, modifier = modifier.statusBarsPadding().padding(top = 6.dp),
        enter = slideInVertically(spring(0.82f, 380f)) { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut()) {
        Text(msg ?: "", style = Theme.font(14f, FontWeight.SemiBold, Theme.text), textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 24.dp).glass(RoundedCornerShape(50), elevation = 8.dp).padding(horizontal = 18.dp, vertical = 12.dp))
    }
}

