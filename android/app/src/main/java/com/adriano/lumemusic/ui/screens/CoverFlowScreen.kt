package com.adriano.lumemusic.ui.screens

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.zIndex
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.ArtworkImage
import com.adriano.lumemusic.ui.GlassButton
import com.adriano.lumemusic.ui.TrackArtwork
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlin.math.abs

/** Cover Flow estilo iPod: aviso "Vire o celular", acelerômetro, paisagem com reflexo e flip 3D com as faixas. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CoverFlowScreen() {
    val ctx = LocalContext.current
    var landscape by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        val sm = ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val acc = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val activity = ctx as? Activity
        val l = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val isLand = abs(e.values[0]) > 6.5f && abs(e.values[1]) < 5f
                if (isLand != landscape) {
                    landscape = isLand
                    activity?.requestedOrientation = if (isLand) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
            }
            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }
        if (acc != null) sm.registerListener(l, acc, SensorManager.SENSOR_DELAY_UI)
        onDispose { sm.unregisterListener(l); activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED }
    }
    val pool: List<Track> = remember {
        (LibraryStore.favoriteTracks + LibraryStore.recentTracks + LibraryStore.downloadedTracks + LibraryStore.savedAlbums.flatMap { it.tracks.take(1) } + (AppModel.feed?.topBrazil ?: emptyList()) + (AppModel.feed?.topGlobal ?: emptyList()))
            .filter { it.artworkURL.isNotEmpty() }.distinctBy { it.album.ifEmpty { it.id } + it.artist }.take(60)
    }
    Box(Modifier.fillMaxSize().background(Color(0xFF050507))) {
        if (!landscape) {
            Column(Modifier.align(Alignment.Center).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.size(96.dp).glass(RoundedCornerShape(28.dp)).graphicsLayer { rotationZ = -90f }, contentAlignment = Alignment.Center) { Icon(sf("square.stack.fill"), null, tint = Color.White, modifier = Modifier.size(48.dp)) }
                Text("Vire o celular", style = Theme.font(24f, FontWeight.Bold, Color.White))
                Text("Folheie as capas em 3D, como no iPod clássico.", style = Theme.font(15f, color = Color.White.copy(0.7f)), textAlign = TextAlign.Center)
                GlassButton("Fechar", modifier = Modifier.size(width = 160.dp, height = 50.dp)) { AppModel.showCoverFlow = false }
            }
        } else if (pool.isEmpty()) {
            Text("Ouça ou curta algumas músicas para ver as capas aqui.", style = Theme.font(16f, color = Color.White.copy(0.8f)), modifier = Modifier.align(Alignment.Center))
        } else FlowStage(pool)
        if (landscape) Box(Modifier.statusBarsPadding().padding(12.dp).size(44.dp).glass(androidx.compose.foundation.shape.CircleShape).pressable(0.9f) { AppModel.showCoverFlow = false }, contentAlignment = Alignment.Center) {
            Icon(sf("xmark"), "Fechar", tint = Color.White, modifier = Modifier.size(20.dp))
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FlowStage(pool: List<Track>) {
    val pager = rememberPagerState(pageCount = { pool.size })
    var flipped by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(horizontal = 260.dp), pageSpacing = (-120).dp, userScrollEnabled = !flipped) { page ->
            val off = (pager.currentPage - page) + pager.currentPageOffsetFraction
            val t = pool[page]
            val front = page == pager.currentPage
            val flip by animateFloatAsState(if (front && flipped) 180f else 0f, tween(550), label = "flip")
            Box(Modifier.fillMaxHeight().graphicsLayer {
                val a = off.coerceIn(-2f, 2f)
                rotationY = if (front && flip > 0f) flip else -a * 58f
                cameraDistance = 16f * density
                val s = 1f - 0.18f * abs(a).coerceAtMost(1f); scaleX = s; scaleY = s
                translationX = -a * 70f
                transformOrigin = TransformOrigin.Center
            }.zIndex(1f - abs(off)), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(210.dp).pressable(0.98f) { if (front) { flipped = !flipped } else { /* centraliza ao tocar nas laterais */ } }) {
                        if (flip > 90f) {
                            Column(Modifier.fillMaxSize().graphicsLayer { rotationY = 180f }.clip(RoundedCornerShape(14.dp)).background(Color(0xFF16161B)).padding(10.dp)) {
                                Text(t.album.ifEmpty { t.title }, style = Theme.font(14f, FontWeight.Bold, Color.White), maxLines = 1)
                                val tracks = remember(t.id) { LibraryStore.tracksById.values.filter { it.album.isNotEmpty() && it.album == t.album && it.artist == t.artist }.ifEmpty { listOf(t) } }
                                LazyColumn { itemsIndexed(tracks) { i, tr ->
                                    Text("${i + 1}  ${tr.title}", style = Theme.font(12.5f, color = Color.White.copy(0.9f)), maxLines = 1, modifier = Modifier.fillMaxWidth().height(32.dp).pressable(0.98f) { AudioPlayer.play(tr, tracks); AppModel.showCoverFlow = false; AppModel.openPlayer() })
                                } }
                            }
                        } else TrackArtwork(t, Modifier.fillMaxSize(), 12.dp)
                    }
                    // reflexo
                    Box(Modifier.size(width = 210.dp, height = 70.dp).clip(RoundedCornerShape(12.dp))) {
                        Box(Modifier.size(210.dp).graphicsLayer { scaleY = -1f; translationY = -70f; alpha = 0.35f }) { TrackArtwork(t, Modifier.fillMaxSize(), 12.dp) }
                        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xFF050507)))))
                    }
                }
            }
        }
        val cur = pool[pager.currentPage]
        Column(Modifier.padding(bottom = 18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(cur.title, style = Theme.font(17f, FontWeight.Bold, Color.White), maxLines = 1)
            Text(cur.artist, style = Theme.font(13.5f, color = Color.White.copy(0.65f)), maxLines = 1)
        }
    }
}
