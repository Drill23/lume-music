package com.adriano.lumemusic.ui.theme

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.core.graphics.ColorUtils
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.size.Size
import coil3.toBitmap
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Cores ambiente extraídas da capa (espelha ArtworkPalette do iOS). */
data class ArtworkPalette(val quadrants: List<Color>, val vibrant: Color, val vibrant2: Color) {
    companion object {
        val Fallback = ArtworkPalette(listOf(Theme.lavender, Theme.rose, Theme.sky, Theme.peach), Theme.rose, Theme.lavender)
    }
}

object ArtworkColors {
    private val cache = ConcurrentHashMap<String, ArtworkPalette>()

    suspend fun palette(context: Context, url: String): ArtworkPalette {
        cache[url]?.let { return it }
        val loader = SingletonImageLoader.get(context)
        val req = ImageRequest.Builder(context).data(url).size(Size(160, 160)).allowHardware(false).build()
        val res = loader.execute(req) as? SuccessResult ?: return ArtworkPalette.Fallback
        val bmp = try { res.image.toBitmap() } catch (_: Exception) { return ArtworkPalette.Fallback }
        val pal = extract(bmp) ?: return ArtworkPalette.Fallback
        cache[url] = pal
        return pal
    }

    private fun extract(src: Bitmap): ArtworkPalette? {
        val size = 24
        val small = Bitmap.createScaledBitmap(src, size, size, true)
        val px = IntArray(size * size)
        small.getPixels(px, 0, size, 0, 0, size, size)
        fun avg(x0: Int, y0: Int, x1: Int, y1: Int): Triple<Double, Double, Double> {
            var r = 0.0; var g = 0.0; var b = 0.0; var n = 0.0
            for (y in y0 until y1) for (x in x0 until x1) {
                val p = px[y * size + x]
                r += (p shr 16) and 0xFF; g += (p shr 8) and 0xFF; b += p and 0xFF; n += 1
            }
            return Triple(r / n / 255, g / n / 255, b / n / 255)
        }
        val h = size / 2
        val quads = listOf(avg(0, 0, h, h), avg(h, 0, size, h), avg(0, h, h, size), avg(h, h, size, size))
        var s1 = -1.0; var c1 = Triple(1.0, 0.48, 0.66)
        var s2 = -1.0; var c2 = Triple(0.68, 0.55, 1.0)
        for (p in px) {
            val r = ((p shr 16) and 0xFF) / 255.0; val g = ((p shr 8) and 0xFF) / 255.0; val b = (p and 0xFF) / 255.0
            val mx = max(r, max(g, b)); val mn = min(r, min(g, b))
            val sat = if (mx > 0.05) (mx - mn) / mx else 0.0
            val luma = 0.299 * r + 0.587 * g + 0.114 * b
            if (luma < 0.10 || luma > 0.94) continue
            val score = sat * 1.7 + (1 - abs(luma - 0.55)) * 0.5
            val dist = abs(r - c1.first) + abs(g - c1.second) + abs(b - c1.third)
            if (score > s1) {
                if (dist > 0.35) { s2 = s1; c2 = c1 }
                s1 = score; c1 = Triple(r, g, b)
            } else if (score > s2 && dist > 0.38) { s2 = score; c2 = Triple(r, g, b) }
        }
        fun color(c: Triple<Double, Double, Double>, boost: Double): Color {
            val hsv = FloatArray(3)
            android.graphics.Color.RGBToHSV((c.first * 255).toInt(), (c.second * 255).toInt(), (c.third * 255).toInt(), hsv)
            hsv[1] = min(1f, (hsv[1] * boost).toFloat())
            hsv[2] = max(0.22f, min(0.95f, hsv[2]))
            return Color(android.graphics.Color.HSVToColor(hsv))
        }
        return ArtworkPalette(quads.map { color(it, 1.3) }, color(c1, 1.1), color(c2, 1.1))
    }
}

fun Color.mix(other: Color, t: Float): Color = lerp(this, other, t)
@Suppress("unused") private fun blend(a: Int, b: Int, t: Float) = ColorUtils.blendARGB(a, b, t)
