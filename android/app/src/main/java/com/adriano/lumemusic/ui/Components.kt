package com.adriano.lumemusic.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.ArtworkStore
import com.adriano.lumemusic.data.DownloadManager
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.theme.LocalDark
import com.adriano.lumemusic.ui.theme.LocalHaze
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.hex
import com.adriano.lumemusic.ui.theme.sf
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect

// ============================================================ Liquid Glass

val SquircleLarge = RoundedCornerShape(28.dp)
val SquircleMedium = RoundedCornerShape(22.dp)

/**
 * Vidro "Liquid Glass". Com [blur]=true usa blur real do Haze (RenderEffect, API 31+) sobre o conteúdo
 * marcado como fonte; em APIs antigas cai para um véu translúcido. Sem blur: preenchimento translúcido
 * + brilho superior + borda em gradiente (barato para botões dentro de listas).
 */
@Composable
fun Modifier.glass(
    shape: Shape = SquircleMedium,
    tint: Color? = null,
    blur: Boolean = false,
    elevation: Dp = 0.dp,
): Modifier {
    val dark = LocalDark.current
    val haze = LocalHaze.current
    val fill = if (dark) Color.White.copy(alpha = if (blur) 0.05f else 0.09f) else Color.White.copy(alpha = if (blur) 0.42f else 0.64f)
    val strokeColors = if (dark) listOf(Color.White.copy(0.34f), Color.White.copy(0.07f), Color.White.copy(0.18f))
    else listOf(Color.White.copy(0.95f), Color.Black.copy(0.035f), Color.Black.copy(0.07f))
    var m = this
    if (elevation > 0.dp) m = m.shadow(elevation, shape, ambientColor = Theme.shadow, spotColor = Theme.shadow)
    m = m.clip(shape)
    if (blur && haze != null) {
        val base = if (dark) hex(0x141418, 0.55f) else hex(0xF6F5FA, 0.50f)
        m = m.hazeEffect(haze, HazeStyle(
            backgroundColor = base, tint = HazeTint(base), blurRadius = 26.dp, noiseFactor = 0.03f,
            fallbackTint = HazeTint(if (dark) hex(0x1B1B20, 0.92f) else hex(0xFFFFFF, 0.90f)),
        ))
    }
    m = m.background(fill)
    if (tint != null) m = m.background(tint.copy(alpha = 0.18f))
    return m
        .background(Brush.verticalGradient(listOf(Color.White.copy(alpha = if (dark) 0.10f else 0.35f), Color.Transparent)))
        .border(0.8.dp, Brush.linearGradient(strokeColors), shape)
}

fun Modifier.pressable(scale: Float = 0.965f, enabled: Boolean = true, onClick: () -> Unit): Modifier = composed {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val s by animateFloatAsState(if (pressed) scale else 1f, spring(0.72f, Spring.StiffnessMedium), label = "press")
    graphicsLayer { scaleX = s; scaleY = s }.clickable(src, null, enabled = enabled, onClick = onClick)
}

// ============================================================ Botões e chips

@Composable
fun GlassIconButton(
    name: String, size: Dp = 40.dp, iconSize: Dp = size * 0.46f, tint: Color? = null,
    foreground: Color = Theme.text, badge: Boolean = false, desc: String = "", onClick: () -> Unit,
) {
    Box(
        Modifier.size(maxOf(size, 44.dp)).pressable(0.9f) { Haptics.light(); onClick() }.semantics { contentDescription = desc },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(size).glass(CircleShape, tint), contentAlignment = Alignment.Center) {
            Icon(sf(name), null, tint = foreground, modifier = Modifier.size(iconSize))
        }
        if (badge) Box(Modifier.align(Alignment.TopEnd).padding(top = 4.dp, end = 4.dp).size(10.dp).background(Theme.rose, CircleShape).border(1.5.dp, Theme.canvas, CircleShape))
    }
}

@Composable
fun PrismChip(title: String, active: Boolean, icon: String? = null, onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    Row(
        Modifier.height(44.dp).padding(vertical = 3.dp).pressable(0.94f) { Haptics.selection(); onClick() }
            .then(if (active) Modifier.shadow(8.dp, shape, spotColor = Theme.rose.copy(0.4f)).clip(shape).background(Theme.prismDiagonal).border(0.8.dp, Color.White.copy(0.55f), shape)
            else Modifier.glass(shape))
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (icon != null) Icon(sf(icon), null, tint = if (active) Theme.onPrism else Theme.text, modifier = Modifier.size(15.dp))
        Text(title, style = Theme.font(14f, FontWeight.SemiBold, if (active) Theme.onPrism else Theme.text), maxLines = 1)
    }
}

@Composable
fun PrismButton(title: String, icon: String? = null, height: Dp = 50.dp, modifier: Modifier = Modifier.fillMaxWidth(), onClick: () -> Unit) {
    val shape = RoundedCornerShape(50)
    Row(
        modifier.height(maxOf(height, 48.dp)).pressable { Haptics.medium(); onClick() }
            .shadow(12.dp, shape, spotColor = Theme.rose.copy(0.45f)).clip(shape).background(Theme.prismDiagonal).border(0.8.dp, Color.White.copy(0.5f), shape),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        if (icon != null) { Icon(sf(icon), null, tint = Theme.onPrism, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
        Text(title, style = Theme.font(16f, FontWeight.SemiBold, Theme.onPrism))
    }
}

@Composable
fun GlassButton(title: String, icon: String? = null, height: Dp = 50.dp, modifier: Modifier = Modifier.fillMaxWidth(), onClick: () -> Unit) {
    Row(
        modifier.height(maxOf(height, 48.dp)).pressable { Haptics.light(); onClick() }.glass(RoundedCornerShape(50)),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        if (icon != null) { Icon(sf(icon), null, tint = Theme.text, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
        Text(title, style = Theme.font(16f, FontWeight.SemiBold, Theme.text))
    }
}

@Composable
fun SectionHeader(title: String, subtitle: String? = null, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.Bottom) {
        Column(Modifier.weight(1f)) {
            Text(title, style = Theme.font(21f, FontWeight.Bold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, style = Theme.font(13f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (onAction != null) {
            Row(Modifier.height(44.dp).pressable(0.95f) { Haptics.light(); onAction() }, verticalAlignment = Alignment.CenterVertically) {
                Text(actionLabel ?: "Ver tudo", style = Theme.font(14f, FontWeight.Medium, Theme.secondary))
                Icon(sf("chevron.right"), null, tint = Theme.secondary, modifier = Modifier.size(16.dp))
            }
        }
    }
}

@Composable
fun EmptyState(icon: String, title: String, message: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(vertical = 36.dp, horizontal = 40.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(72.dp).glass(CircleShape), contentAlignment = Alignment.Center) {
            Icon(sf(icon), null, tint = Theme.rose, modifier = Modifier.size(32.dp))
        }
        Text(title, style = Theme.font(17f, FontWeight.SemiBold, Theme.text), textAlign = TextAlign.Center)
        Text(message, style = Theme.font(14f, color = Theme.secondary), textAlign = TextAlign.Center)
    }
}

@Composable
fun LumeMark(size: Dp = 32.dp) {
    // a mesma arte do ícone novo (PrismMark do iOS)
    androidx.compose.foundation.Image(androidx.compose.ui.res.painterResource(com.adriano.lumemusic.R.drawable.lume_mark), null, Modifier.size(size))
}

@Composable
fun LumeWordmark(size: Float = 26f) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy((size * 0.32f).dp)) {
        LumeMark((size * 1.22f).dp)
        Text("Lume", style = Theme.rounded(size, FontWeight.Bold, Theme.text))
    }
}

// ============================================================ Imagens

@Composable
fun ArtworkImage(url: String, modifier: Modifier = Modifier, cornerRadius: Dp = 12.dp, icon: String = "music.note", shape: Shape? = null) {
    val sh = shape ?: RoundedCornerShape(cornerRadius)
    val ctx = LocalContext.current
    Box(modifier.clip(sh).background(Brush.linearGradient(listOf(Theme.fillStrong, Theme.fill))), contentAlignment = Alignment.Center) {
        Icon(sf(icon), null, tint = Theme.tertiary, modifier = Modifier.size(22.dp))
        if (url.isNotEmpty()) {
            AsyncImage(
                model = remember(url) { ImageRequest.Builder(ctx).data(url).build() },
                contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
fun TrackArtwork(track: Track, modifier: Modifier = Modifier, cornerRadius: Dp = 10.dp, shape: Shape? = null) {
    LaunchedEffect(track.id) { ArtworkStore.ensure(track) }
    ArtworkImage(ArtworkStore.url(track), modifier, cornerRadius, shape = shape)
}

@Composable
fun ArtistAvatar(name: String, size: Dp = 32.dp) {
    LaunchedEffect(name) { ArtworkStore.ensurePhoto(name) }
    val url = ArtworkStore.photo(name)
    if (url != null) ArtworkImage(url, Modifier.size(size), shape = CircleShape, icon = "person.fill")
    else Box(Modifier.size(size).clip(CircleShape).background(Theme.prismDiagonal), contentAlignment = Alignment.Center) {
        Text(name.trim().take(1).uppercase(), style = Theme.rounded(size.value * 0.42f, FontWeight.Bold, Theme.onPrism))
    }
}

// ============================================================ Faixas

@Composable
fun TrackRow(track: Track, rank: Int? = null, queue: List<Track>? = null, showArtwork: Boolean = true, onPlay: (() -> Unit)? = null) {
    val active = AudioPlayer.currentTrack?.id == track.id
    val downloaded = track.id in LibraryStore.downloadedIds
    val progress = DownloadManager.progressById[track.id]
    Row(
        Modifier.fillMaxWidth().defaultMinHeight().pressable(0.985f) { Haptics.light(); if (onPlay != null) onPlay() else AudioPlayer.play(track, queue) }
            .padding(horizontal = 20.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (rank != null) {
            val c = when (rank) { 1 -> hex(0xF59E0B); 2 -> hex(0x94A3B8); 3 -> hex(0xD97706); else -> Theme.secondary }
            Text("$rank", style = Theme.font(14.5f, FontWeight.Bold, c), modifier = Modifier.width(26.dp), textAlign = TextAlign.Center)
        }
        if (showArtwork) {
            Box(Modifier.size(50.dp)) {
                TrackArtwork(track, Modifier.fillMaxSize(), 8.dp)
                if (active) Box(Modifier.fillMaxSize().clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(0.38f)), contentAlignment = Alignment.Center) {
                    Icon(sf("waveform"), null, tint = Color.White, modifier = Modifier.size(20.dp))
                }
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(track.title, style = Theme.font(16f, color = if (active) Theme.accent else Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (track.isExplicit) Icon(sf("e.square.fill"), null, tint = Theme.tertiary, modifier = Modifier.size(12.dp))
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                if (downloaded) Icon(sf("arrow.down.circle.fill"), null, tint = Theme.secondary, modifier = Modifier.size(12.dp))
                Text(track.artist, style = Theme.font(13.5f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (progress != null) Box(Modifier.size(18.dp).drawBehind {
            drawArc(Theme.accentStatic, -90f, (360f * progress.toFloat()), false, style = Stroke(2.2.dp.toPx(), cap = StrokeCap.Round))
        })
        Box(Modifier.size(width = 40.dp, height = 44.dp).pressable(0.85f) { AppModel.showTrackMenu(track, queue) }.semantics { contentDescription = "Mais opções" }, contentAlignment = Alignment.Center) {
            Icon(sf("ellipsis"), null, tint = Theme.secondary, modifier = Modifier.size(20.dp))
        }
    }
}

private fun Modifier.defaultMinHeight() = this.height(60.dp)
private val Theme.accentStatic: Color get() = Theme.rose

// ============================================================ Tiles

@Composable
fun AlbumTile(album: AlbumShowcase, width: Dp = 150.dp, subtitle: String? = null, onClick: () -> Unit) {
    Column(Modifier.width(width).pressable(0.96f) { Haptics.light(); onClick() }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ArtworkImage(album.artworkURL, Modifier.size(width), 16.dp, icon = "square.stack.fill")
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(album.title, style = Theme.font(14.5f, FontWeight.SemiBold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle ?: listOf(album.artist, album.year).filter { it.isNotEmpty() }.joinToString(" · "),
                style = Theme.font(12.5f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
fun ArtistBubble(artist: ArtistInfo, size: Dp = 96.dp, onClick: () -> Unit) {
    Column(Modifier.width(size + 8.dp).pressable(0.95f) { Haptics.light(); onClick() }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (artist.pictureURL.isNotEmpty()) ArtworkImage(artist.pictureURL, Modifier.size(size), shape = CircleShape, icon = "person.fill")
        else ArtistAvatar(artist.name, size)
        Text(artist.name, style = Theme.font(13f, FontWeight.Medium, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
    }
}

@Composable
fun TallTrackCard(track: Track, rank: Int? = null, queue: List<Track>, width: Dp = 150.dp) {
    Column(Modifier.width(width).pressable(0.96f) { Haptics.light(); AudioPlayer.play(track, queue) }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box {
            TrackArtwork(track, Modifier.size(width), 16.dp)
            if (rank != null) Text("$rank", style = Theme.rounded(13f, FontWeight.Bold, Color.White),
                modifier = Modifier.padding(8.dp).background(Color.Black.copy(0.45f), RoundedCornerShape(50)).padding(horizontal = 9.dp, vertical = 3.dp))
        }
        Column {
            Text(track.title, style = Theme.font(14.5f, FontWeight.SemiBold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(track.artist, style = Theme.font(12.5f, color = Theme.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Cartão com gradiente (moods, países, gêneros, mixes). */
@Composable
fun GradientCard(title: String, subtitle: String? = null, icon: String? = null, hexA: Long, hexB: Long, modifier: Modifier = Modifier, emoji: String? = null, onClick: () -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Box(
        modifier.pressable(0.96f) { Haptics.light(); onClick() }.clip(shape).background(Brush.linearGradient(listOf(hex(hexA), hex(hexB)))).border(0.7.dp, Color.White.copy(0.25f), shape).padding(14.dp),
    ) {
        if (icon != null) Icon(sf(icon), null, tint = Color.White.copy(0.28f), modifier = Modifier.size(54.dp).align(Alignment.BottomEnd))
        Column(Modifier.align(Alignment.TopStart), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (emoji != null) Text(emoji, style = Theme.font(24f))
            Text(title, style = Theme.font(16f, FontWeight.Bold, Color.White), maxLines = 2)
            if (subtitle != null) Text(subtitle, style = Theme.font(12f, color = Color.White.copy(0.85f)), maxLines = 2)
        }
    }
}

@Composable
fun Skeleton(modifier: Modifier, shape: Shape = RoundedCornerShape(12.dp)) {
    Box(modifier.clip(shape).background(Theme.fill))
}

@Composable
fun HRow(contentPadding: PaddingValues = PaddingValues(horizontal = 20.dp), spacing: Dp = 14.dp, content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
    LazyRow(contentPadding = contentPadding, horizontalArrangement = Arrangement.spacedBy(spacing), content = content)
}

/** Barra de topo das telas de detalhe (voltar + título). */
@Composable
fun DetailTopBar(title: String, trailing: @Composable (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        GlassIconButton("chevron.left", desc = "Voltar") { AppModel.pop() }
        Text(title, style = Theme.font(17f, FontWeight.SemiBold, Theme.text), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        trailing?.invoke()
    }
}


/** Preenche o glifo com o gradiente prisma horizontal (Theme.prism do iOS: pêssego → rosa → lavanda → céu). */
@Composable
fun PrismIcon(name: String, size: Dp, modifier: Modifier = Modifier) {
    val brush = Theme.prismHorizontal
    Icon(
        sf(name), null, tint = Color.Black,
        modifier = modifier.size(size).graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent { drawContent(); drawRect(brush, blendMode = BlendMode.SrcIn) },
    )
}
