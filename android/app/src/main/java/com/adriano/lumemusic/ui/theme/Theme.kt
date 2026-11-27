package com.adriano.lumemusic.ui.theme

import android.provider.Settings
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

val LocalDark = staticCompositionLocalOf { false }
val LocalHaze = staticCompositionLocalOf<HazeState?> { null }

fun hex(v: Long, alpha: Float = 1f): Color = Color(
    red = ((v shr 16) and 0xFF) / 255f,
    green = ((v shr 8) and 0xFF) / 255f,
    blue = (v and 0xFF) / 255f,
    alpha = alpha,
)

/** Design system "Prisma" (espelha Theme.swift): canvas neutro + acento iridescente pêssego → rosa → lavanda → céu. */
object Theme {
    const val credit = "Desenvolvido por A.A · Demerzel Studio"

    @Composable @ReadOnlyComposable
    fun dyn(light: Long, dark: Long, la: Float = 1f, da: Float = 1f): Color =
        if (LocalDark.current) hex(dark, da) else hex(light, la)

    val canvas: Color @Composable @ReadOnlyComposable get() = dyn(0xF3F2F7, 0x09090B)
    val canvasRaised: Color @Composable @ReadOnlyComposable get() = dyn(0xFFFFFF, 0x141418)
    val text: Color @Composable @ReadOnlyComposable get() = dyn(0x101013, 0xF5F5F7)
    val secondary: Color @Composable @ReadOnlyComposable get() = dyn(0x101013, 0xF5F5F7, 0.58f, 0.62f)
    val tertiary: Color @Composable @ReadOnlyComposable get() = dyn(0x101013, 0xF5F5F7, 0.32f, 0.34f)
    val hairline: Color @Composable @ReadOnlyComposable get() = dyn(0x000000, 0xFFFFFF, 0.08f, 0.10f)
    val fill: Color @Composable @ReadOnlyComposable get() = dyn(0x000000, 0xFFFFFF, 0.05f, 0.075f)
    val fillStrong: Color @Composable @ReadOnlyComposable get() = dyn(0x000000, 0xFFFFFF, 0.09f, 0.13f)
    val shadow: Color @Composable @ReadOnlyComposable get() = dyn(0x2A2440, 0x000000, 0.16f, 0.55f)
    val accent: Color @Composable @ReadOnlyComposable get() = dyn(0xE0457B, 0xFF7BA9)

    val peach = hex(0xFFB27A)
    val rose = hex(0xFF7BA9)
    val lavender = hex(0xAD8CFF)
    val sky = hex(0x7CC8FF)
    val mint = hex(0x6FE3C1)
    val ok = hex(0x30D158)
    val danger = hex(0xFF453A)
    val onPrism = Color(0.07f, 0.06f, 0.09f)

    val prismColors = listOf(peach, rose, lavender, sky)
    val prismHorizontal: Brush get() = Brush.horizontalGradient(prismColors)
    val prismDiagonal: Brush get() = Brush.linearGradient(prismColors)
    val prismVertical: Brush get() = Brush.verticalGradient(prismColors)
    val prismSweep: Brush get() = Brush.sweepGradient(prismColors + peach)

    val glassStrokeColors = listOf(Color.White.copy(alpha = 0.42f), Color.White.copy(alpha = 0.10f), Color.White.copy(alpha = 0.22f))

    // ---- tipografia (fonte do sistema com pesos equivalentes ao SF) ----

    fun font(size: Float, weight: FontWeight = FontWeight.Normal, color: Color = Color.Unspecified, letterSpacing: TextUnit = TextUnit.Unspecified): TextStyle =
        TextStyle(fontFamily = FontFamily.Default, fontSize = size.sp, fontWeight = weight, color = color, letterSpacing = letterSpacing, lineHeight = (size * 1.22f).sp)

    fun rounded(size: Float, weight: FontWeight = FontWeight.SemiBold, color: Color = Color.Unspecified): TextStyle =
        TextStyle(fontFamily = FontFamily.SansSerif, fontSize = size.sp, fontWeight = weight, color = color)

    fun formatTime(sec: Double): String {
        if (!sec.isFinite() || sec < 0) return "0:00"
        val s = sec.toInt()
        return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, (s % 3600) / 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
    }

    fun shortDate(iso: String?): String {
        if (iso == null || iso.length < 10) return ""
        val f = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val d = try { f.parse(iso.take(10)) } catch (_: Exception) { null } ?: return ""
        val days = ((System.currentTimeMillis() - d.time) / 86_400_000L).toInt()
        if (days <= 0) return "Hoje"
        if (days == 1) return "Ontem"
        if (days < 7) return "Há $days dias"
        return SimpleDateFormat("d MMM", Locale("pt", "BR")).format(Date(d.time)).replace(".", "")
    }
}

@Composable
fun reduceMotion(): Boolean {
    val ctx = LocalContext.current
    return try {
        Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    } catch (_: Exception) { false }
}

@Composable
fun LumeTheme(content: @Composable () -> Unit) {
    val dark = when (com.adriano.lumemusic.ui.AppModel.appearance) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() }
    val scheme = if (dark) darkColorScheme(
        primary = Theme.rose, onPrimary = Theme.onPrism, background = hex(0x09090B), surface = hex(0x141418),
        onBackground = hex(0xF5F5F7), onSurface = hex(0xF5F5F7),
    ) else lightColorScheme(
        primary = hex(0xE0457B), onPrimary = Color.White, background = hex(0xF3F2F7), surface = Color.White,
        onBackground = hex(0x101013), onSurface = hex(0x101013),
    )
    CompositionLocalProvider(LocalDark provides dark) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

/** Contador de dias simples usado por telas de lançamentos. */
fun daysSince(iso: String?): Int {
    if (iso == null || iso.length < 10) return 999
    val f = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    val d = try { f.parse(iso.take(10)) } catch (_: Exception) { null } ?: return 999
    val cal = Calendar.getInstance()
    return ((cal.timeInMillis - d.time) / 86_400_000L).toInt()
}
