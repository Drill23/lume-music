package com.adriano.lumemusic.ui.stage

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import com.adriano.lumemusic.data.CassetteStyle
import com.adriano.lumemusic.data.VinylEdition
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Renderizador (android.graphics, sem Compose) das artes compostas da tela de bloqueio — porte de
 * App/LockScreenArtwork.swift + as texturas LumeTextures.renderRecord/renderSheen e CassetteArt.renderCassette.
 * Tudo roda em thread de fundo e devolve um Bitmap de 1024 px.
 *
 * Funções de textura com nomes estáveis (usadas só aqui, prontas para a outra frente trocar pelas dela):
 * [record], [sheen], [cassetteLayers], [hub], [pack].
 */
object LockArtRender {
    const val SIDE = 1024

    // Geometria (DeckGeo / TapeGeo do iOS)
    private const val PLATTER_D = 0.92f
    private const val RECORD_D = 0.855f
    private const val LABEL_D = 0.29f
    private const val TAPE_ASPECT = 1.574f
    private val REEL_L = 0.315f to 0.288f
    private val REEL_R = 0.685f to 0.288f
    private const val R_EMPTY = 0.041f
    private const val R_FULL = 0.084f
    private const val HUB_R = 0.036f
    private val ROLLER_L = 0.262f to 0.592f
    private val ROLLER_R = 0.738f to 0.592f
    private val LABEL_RECT = RectF(0.055f, 0.045f, 0.055f + 0.89f, 0.045f + 0.352f)
    private val WINDOW_RECT = RectF(0.185f, 0.198f, 0.185f + 0.63f, 0.198f + 0.180f)
    private const val SHADOW_MX = 0.15f
    private const val SHADOW_MT = 0.06f
    private const val SHADOW_MB = 0.18f

    // ---------------- helpers ----------------

    private fun g(w: Float, a: Float = 1f): Int =
        Color.argb((a.coerceIn(0f, 1f) * 255).roundToInt(), (w.coerceIn(0f, 1f) * 255).roundToInt(), (w.coerceIn(0f, 1f) * 255).roundToInt(), (w.coerceIn(0f, 1f) * 255).roundToInt())

    private fun rgb(r: Float, gg: Float, b: Float, a: Float = 1f): Int =
        Color.argb((a * 255).roundToInt(), (r * 255).roundToInt(), (gg * 255).roundToInt(), (b * 255).roundToInt())

    private fun withAlpha(c: Int, a: Float): Int = Color.argb((a.coerceIn(0f, 1f) * 255).roundToInt(), Color.red(c), Color.green(c), Color.blue(c))

    private fun fillPaint(c: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; color = c }
    private fun strokePaint(c: Int, w: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = c; strokeWidth = w }

    private class Rng(seed: Long) {
        private var s = (seed xor 0x2545F4914F6CDD1DL) or 1L
        fun next(): Float {
            s = s xor (s shl 13); s = s xor (s ushr 7); s = s xor (s shl 17)
            return ((s ushr 11) and 0xFFFFFFL).toFloat() / 0x1000000.toFloat()
        }
        fun range(a: Float, b: Float) = a + (b - a) * next()
    }

    private fun bitmap(w: Int, h: Int, draw: (Canvas) -> Unit): Bitmap {
        val b = Bitmap.createBitmap(max(1, w), max(1, h), Bitmap.Config.ARGB_8888)
        draw(Canvas(b))
        return b
    }

    private fun linear(x0: Float, y0: Float, x1: Float, y1: Float, colors: IntArray, pos: FloatArray? = null) =
        Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = LinearGradient(x0, y0, x1, y1, colors, pos, Shader.TileMode.CLAMP) }

    private fun radial(cx: Float, cy: Float, r: Float, colors: IntArray, pos: FloatArray? = null) =
        Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = RadialGradient(cx, cy, max(0.01f, r), colors, pos, Shader.TileMode.CLAMP) }

    /** Desenha [src] preenchendo [dst] (aspect-fill, centralizado) — drawCover do iOS. */
    private fun drawCover(c: Canvas, src: Bitmap, dst: RectF) {
        if (src.width <= 0 || src.height <= 0) return
        val k = max(dst.width() / src.width, dst.height() / src.height)
        val sw = dst.width() / k; val sh = dst.height() / k
        val sx = (src.width - sw) / 2f; val sy = (src.height - sh) / 2f
        c.drawBitmap(src, Rect(sx.roundToInt(), sy.roundToInt(), (sx + sw).roundToInt(), (sy + sh).roundToInt()), dst,
            Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
    }

    // ---------------- fundo comum: capa desfocada + véu escuro ----------------

    private fun boxBlur(px: IntArray, w: Int, h: Int, radius: Int) {
        val tmp = IntArray(px.size)
        fun pass(src: IntArray, dst: IntArray, horizontal: Boolean) {
            val len = if (horizontal) w else h
            val lines = if (horizontal) h else w
            for (line in 0 until lines) {
                var sr = 0; var sg = 0; var sb = 0
                val win = 2 * radius + 1
                fun idx(i: Int) = if (horizontal) line * w + i.coerceIn(0, len - 1) else i.coerceIn(0, len - 1) * w + line
                for (i in -radius..radius) { val p = src[idx(i)]; sr += Color.red(p); sg += Color.green(p); sb += Color.blue(p) }
                for (i in 0 until len) {
                    dst[if (horizontal) line * w + i else i * w + line] = Color.rgb(sr / win, sg / win, sb / win)
                    val add = src[idx(i + radius + 1)]; val rem = src[idx(i - radius)]
                    sr += Color.red(add) - Color.red(rem); sg += Color.green(add) - Color.green(rem); sb += Color.blue(add) - Color.blue(rem)
                }
            }
        }
        repeat(3) { pass(px, tmp, true); pass(tmp, px, false) }
    }

    private fun drawBackdrop(c: Canvas, cover: Bitmap, s: Float) {
        val small = Bitmap.createScaledBitmap(cover, 160, max(1, (160f * cover.height / max(1, cover.width)).roundToInt()), true)
        val px = IntArray(small.width * small.height)
        small.getPixels(px, 0, small.width, 0, 0, small.width, small.height)
        boxBlur(px, small.width, small.height, 8)   // ≈ sigma 14 do iOS
        val blurred = Bitmap.createBitmap(px, small.width, small.height, Bitmap.Config.ARGB_8888)
        c.drawBitmap(blurred, null, RectF(-s * 0.15f, -s * 0.15f, s * 1.15f, s * 1.15f), Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        c.drawRect(0f, 0f, s, s, linear(0f, 0f, 0f, s, intArrayOf(rgb(0f, 0f, 0f, 0.30f), rgb(0f, 0f, 0f, 0.62f))))
        if (small !== cover) small.recycle()
    }

    // ---------------- Vinil ----------------

    fun vinyl(cover: Bitmap, edition: VinylEdition): Bitmap {
        val s = SIDE.toFloat()
        return bitmap(SIDE, SIDE) { c ->
            drawBackdrop(c, cover, s)
            val cx = s * 0.47f; val cy = s * 0.52f
            val rr = s * 0.40f                                  // raio do disco
            val p = 2 * rr * PLATTER_D / RECORD_D               // diâmetro do prato
            val platter = RectF(cx - p / 2, cy - p / 2, cx + p / 2, cy + p / 2)
            val disc = RectF(cx - rr, cy - rr, cx + rr, cy + rr)
            // sombra do prato
            c.drawCircle(cx, cy + s * 0.02f, p / 2 * 0.985f, fillPaint(Color.BLACK).apply { setShadowLayer(s * 0.05f, 0f, 0f, rgb(0f, 0f, 0f, 0.7f)) })
            c.drawBitmap(record(edition, p.roundToInt()), null, platter, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
            c.drawBitmap(sheen(edition == VinylEdition.PRISM_CRYSTAL, (2 * rr).roundToInt()), null, disc, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))

            // selo = capa
            val l = rr * LABEL_D / RECORD_D
            val label = RectF(cx - l, cy - l, cx + l, cy + l)
            c.save()
            c.clipPath(Path().apply { addOval(label, Path.Direction.CW) })
            drawCover(c, cover, label)
            val gx = label.left + l * 0.6f; val gy = label.top + l * 0.5f
            c.drawCircle(gx, gy, l * 1.2f, radial(gx, gy, l * 1.2f, intArrayOf(g(1f, 0.22f), g(1f, 0f))))
            c.restore()
            c.drawOval(label, strokePaint(g(0f, 0.55f), 4f))

            // eixo central
            val h = rr * 0.03f
            c.drawCircle(cx, cy, h, fillPaint(g(0.78f)))
            c.drawCircle(cx, cy, h * 0.45f, fillPaint(g(0.35f)))

            // braço com a agulha pousada nos sulcos
            val pvx = s * 0.90f; val pvy = s * 0.13f
            val ang = 0.32
            val sx = cx + rr * 0.74f * cos(ang).toFloat(); val sy = cy + rr * 0.74f * sin(ang).toFloat()
            val dx = sx - pvx; val dy = sy - pvy
            val len = sqrt(dx * dx + dy * dy)
            val ux = dx / len; val uy = dy / len
            val shadow = { Paint(Paint.ANTI_ALIAS_FLAG).apply { setShadowLayer(s * 0.02f, s * 0.012f, s * 0.018f, rgb(0f, 0f, 0f, 0.6f)) } }
            // contrapeso
            c.drawLine(pvx, pvy, pvx - ux * s * 0.07f, pvy - uy * s * 0.07f,
                shadow().apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; color = g(0.20f); strokeWidth = s * 0.05f })
            // haste
            c.drawLine(pvx, pvy, sx - ux * s * 0.05f, sy - uy * s * 0.05f,
                shadow().apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; color = g(0.80f); strokeWidth = s * 0.014f })
            // cápsula (headshell)
            c.save()
            c.translate(sx, sy)
            c.rotate(Math.toDegrees(atan2(uy, ux).toDouble() - PI / 2).toFloat())
            c.drawRoundRect(RectF(-s * 0.022f, -s * 0.075f, s * 0.022f, s * 0.010f), s * 0.008f, s * 0.008f,
                shadow().apply { style = Paint.Style.FILL; color = g(0.14f) })
            c.drawRoundRect(RectF(-s * 0.004f, -s * 0.006f, s * 0.004f, s * 0.006f), 2f, 2f, fillPaint(g(0.85f)))
            c.restore()
            // base do pivô
            val pb = s * 0.055f
            c.drawCircle(pvx, pvy, pb, linear(pvx - pb, pvy - pb, pvx + pb, pvy + pb, intArrayOf(g(0.92f), g(0.45f))))
            c.drawCircle(pvx, pvy, pb * 0.45f, fillPaint(g(0.25f)))
        }
    }

    /** Prato de alumínio com pontos estroboscópicos + disco com sulcos finos, vãos entre faixas e borda chanfrada. */
    fun record(edition: VinylEdition, px: Int): Bitmap = bitmap(px, px) { c ->
        val d = px.toFloat()
        val cx = d / 2; val cy = d / 2
        val pR = d / 2
        val rR = pR * RECORD_D / PLATTER_D
        val rng = Rng(px + 11L)

        // prato de alumínio torneado
        c.save()
        c.clipPath(Path().apply { addCircle(cx, cy, pR, Path.Direction.CW) })
        val n = 120
        for (i in 0 until n) {
            val a0 = i.toFloat() / n * 2 * PI.toFloat()
            val a1 = (i + 1).toFloat() / n * 2 * PI.toFloat() + 0.01f
            val t = 0.5f + 0.5f * cos(2 * (a0 - 0.7f))
            val l = 0.40f + 0.46f * t * t
            val wedge = Path().apply {
                moveTo(cx, cy)
                lineTo(cx + pR * 1.02f * cos(a0), cy + pR * 1.02f * sin(a0))
                lineTo(cx + pR * 1.02f * cos(a1), cy + pR * 1.02f * sin(a1))
                close()
            }
            c.drawPath(wedge, fillPaint(g(l)))
        }
        var rr = pR
        while (rr > rR) {
            c.drawCircle(cx, cy, rr, strokePaint(if (rng.next() > 0.5f) g(1f, rng.range(0.03f, 0.09f)) else g(0f, rng.range(0.03f, 0.09f)), 0.7f))
            rr -= rng.range(0.9f, 2.2f)
        }
        c.restore()

        // pontos estroboscópicos (50 Hz / 60 Hz)
        for ((ring, count) in listOf(0.972f to 108, 0.944f to 90)) {
            val rad = pR * ring
            val len = pR * 0.020f
            val wid = (2 * PI.toFloat() * rad / count) * 0.46f
            for (k in 0 until count) {
                val a = k.toFloat() / count * 2 * PI.toFloat()
                c.save()
                c.translate(cx + rad * cos(a), cy + rad * sin(a))
                c.rotate(Math.toDegrees(a.toDouble()).toFloat())
                c.drawRect(-len / 2, -wid / 2, len / 2, wid / 2, fillPaint(g(0.08f, 0.78f)))
                c.restore()
            }
        }
        c.drawCircle(cx, cy, pR - d * 0.002f, strokePaint(g(1f, 0.65f), max(1f, d * 0.0035f)))
        c.drawCircle(cx, cy, rR + d * 0.004f, strokePaint(g(0f, 0.55f), max(1f, d * 0.003f)))

        // disco: base por edição + sombra de contato
        val light = edition != VinylEdition.CLASSIC_BLACK
        val base = when (edition) {
            VinylEdition.CLASSIC_BLACK -> rgb(0.052f, 0.052f, 0.058f)
            VinylEdition.PRISM_CRYSTAL -> g(0.55f)
            VinylEdition.LIMITED_GOLD -> rgb(0.72f, 0.52f, 0.18f)
            VinylEdition.WHITE_MARBLE -> rgb(0.92f, 0.91f, 0.88f)
        }
        c.drawCircle(cx, cy, rR, fillPaint(base).apply { setShadowLayer(d * 0.016f, 0f, d * 0.004f, g(0f, 0.6f)) })

        c.save()
        c.clipPath(Path().apply { addCircle(cx, cy, rR, Path.Direction.CW) })
        when (edition) {
            VinylEdition.CLASSIC_BLACK -> c.drawCircle(cx, cy, rR, radial(cx, cy, rR, intArrayOf(g(0.12f), g(0.045f), g(0.07f)), floatArrayOf(0f, 0.55f, 1f)))
            VinylEdition.PRISM_CRYSTAL -> for (i in 0 until 180) {
                val a0 = i.toFloat() / 180 * 2 * PI.toFloat()
                val a1 = (i + 1).toFloat() / 180 * 2 * PI.toFloat() + 0.012f
                val hue = ((i.toFloat() / 180 * 2) % 1f) * 360f
                val col = withAlpha(Color.HSVToColor(floatArrayOf(hue, 0.42f, 0.86f)), 0.86f)
                c.drawPath(Path().apply {
                    moveTo(cx, cy)
                    lineTo(cx + rR * 1.02f * cos(a0), cy + rR * 1.02f * sin(a0))
                    lineTo(cx + rR * 1.02f * cos(a1), cy + rR * 1.02f * sin(a1))
                    close()
                }, fillPaint(col))
            }
            VinylEdition.LIMITED_GOLD -> c.drawCircle(cx, cy, rR * 1.1f, radial(cx - rR * 0.2f, cy - rR * 0.2f, rR * 1.3f,
                intArrayOf(rgb(0.96f, 0.80f, 0.38f), rgb(0.76f, 0.54f, 0.16f), rgb(0.50f, 0.33f, 0.08f)), floatArrayOf(0f, 0.6f, 1f)))
            VinylEdition.WHITE_MARBLE -> {
                c.drawCircle(cx, cy, rR, radial(cx, cy, rR, intArrayOf(g(0.98f), g(0.88f))))
                repeat(16) {
                    var x = cx + rng.range(-rR, rR); var y = cy + rng.range(-rR, rR)
                    val path = Path().apply { moveTo(x, y) }
                    repeat(3) {
                        val nx = x + rng.range(-rR * 0.5f, rR * 0.5f); val ny = y + rng.range(-rR * 0.5f, rR * 0.5f)
                        path.quadTo((x + nx) / 2 + rng.range(-40f, 40f), (y + ny) / 2 + rng.range(-40f, 40f), nx, ny)
                        x = nx; y = ny
                    }
                    c.drawPath(path, strokePaint(g(rng.range(0.35f, 0.6f), rng.range(0.10f, 0.26f)), rng.range(1.5f, 6f)).apply { strokeCap = Paint.Cap.ROUND })
                }
            }
        }
        // faixas de "dinâmica" (largas, quase imperceptíveis)
        repeat(22) {
            val rad = rng.range(rR * 0.40f, rR * 0.97f)
            c.drawCircle(cx, cy, rad, strokePaint(if (light) g(0f, rng.range(0.012f, 0.035f)) else g(1f, rng.range(0.012f, 0.035f)), rng.range(3f, 14f)))
        }
        // sulcos finos com vãos entre faixas
        val gaps = floatArrayOf(0.50f, 0.625f, 0.745f, 0.86f)
        val pitch = max(1.15f, d / 640f)
        var r = rR * 0.968f
        while (r > rR * 0.405f) {
            val rn = r / rR
            val inGap = gaps.any { abs(rn - it) < 0.0075f }
            if (inGap) {
                c.drawCircle(cx, cy, r, strokePaint(g(1f, if (light) 0.20f else 0.045f), pitch * 1.4f))
            } else {
                val a = rng.range(0.035f, 0.11f)
                c.drawCircle(cx, cy, r, strokePaint(if (light) g(0f, a * 0.9f) else g(1f, a * 0.55f), pitch * rng.range(0.5f, 0.85f)))
            }
            r -= pitch * rng.range(0.85f, 1.25f)
        }
        // zona de saída lisa e assentamento do selo
        c.drawCircle(cx, cy, rR * 0.385f, fillPaint(if (light) g(0.2f, 0.16f) else g(0f, 0.5f)))
        c.drawCircle(cx, cy, rR * 0.385f, strokePaint(g(1f, if (light) 0.5f else 0.16f), max(1f, d * 0.0018f)))
        c.drawCircle(cx, cy, rR * 0.365f, strokePaint(g(0f, 0.5f), max(1f, d * 0.0018f)))
        c.restore()

        // borda chanfrada
        c.drawCircle(cx, cy, rR - d * 0.0025f, strokePaint(g(1f, if (light) 0.55f else 0.22f), max(1f, d * 0.0035f)))
        c.drawCircle(cx, cy, rR, strokePaint(g(0f, 0.55f), max(1f, d * 0.002f)))
    }

    /** Reflexo anisotrópico em gravata borboleta (dois lóbulos opostos, parados). */
    fun sheen(prism: Boolean, size: Int): Bitmap {
        val n = max(8, size)
        val px = IntArray(n * n)
        val half = n / 2.0
        val a0 = -0.62
        fun adiff(a: Double, b: Double): Double {
            var d = a - b
            while (d > PI) d -= 2 * PI
            while (d < -PI) d += 2 * PI
            return d
        }
        for (y in 0 until n) for (x in 0 until n) {
            val dx = x + 0.5 - half; val dy = y + 0.5 - half
            val r = hypot(dx, dy) / half
            if (r <= 0.30 || r >= 1.0) continue
            val th = atan2(dy, dx)
            val w = 0.10 + 0.30 * r
            val d1 = adiff(th, a0) / w
            val d2 = adiff(th, a0 + PI) / (w * 1.1)
            val lobe = exp(-d1 * d1) + 0.78 * exp(-d2 * d2)
            val q1 = adiff(th, a0 + PI / 2) / 0.28
            val q2 = adiff(th, a0 - PI / 2) / 0.28
            val minor = 0.20 * (exp(-q1 * q1) + exp(-q2 * q2))
            val fadeIn = min(1.0, (r - 0.30) / 0.14)
            val fadeOut = min(1.0, (1.0 - r) / 0.03)
            val intensity = min(1.0, (lobe + minor) * fadeIn * fadeOut * (0.45 + 0.55 * r))
            if (prism) {
                val hue = ((th + PI) / (2 * PI) * 360.0).toFloat()
                val col = Color.HSVToColor(floatArrayOf(hue, 0.55f, 1f))
                val a = intensity * 0.40
                val rr = (0.55 + 0.45 * Color.red(col) / 255.0).coerceIn(0.0, 1.0)
                val gg = (0.55 + 0.45 * Color.green(col) / 255.0).coerceIn(0.0, 1.0)
                val bb = (0.55 + 0.45 * Color.blue(col) / 255.0).coerceIn(0.0, 1.0)
                px[y * n + x] = Color.argb((a * 255).toInt().coerceIn(0, 255), (rr * 255).toInt(), (gg * 255).toInt(), (bb * 255).toInt())
            } else {
                px[y * n + x] = Color.argb((intensity * 0.30 * 255).toInt().coerceIn(0, 255), 255, 255, 255)
            }
        }
        return Bitmap.createBitmap(px, n, n, Bitmap.Config.ARGB_8888)
    }

    // ---------------- Fita K7 ----------------

    private class TapePalette(
        val bodyTop: Int, val bodyBottom: Int, val overlayAlpha: Float, val bed: Int,
        val paper: Int, val stripe: Int, val dark: Boolean, val brand: String,
    )

    private fun palette(style: CassetteStyle): TapePalette = when (style) {
        CassetteStyle.SMOKED_STUDIO -> TapePalette(rgb(0.30f, 0.31f, 0.35f), rgb(0.10f, 0.10f, 0.12f), 0.80f, g(0.03f),
            rgb(0.95f, 0.93f, 0.85f), rgb(0.88f, 0.28f, 0.20f), true, "LUME  ·  HIGH BIAS")
        CassetteStyle.CRYSTAL_CLEAR -> TapePalette(rgb(0.80f, 0.88f, 0.93f), rgb(0.55f, 0.66f, 0.74f), 0.30f, rgb(0.30f, 0.40f, 0.48f),
            rgb(0.98f, 0.98f, 0.95f), rgb(0.08f, 0.56f, 0.64f), false, "LUME  ·  CRYSTAL")
        CassetteStyle.METALLIC_CHROME -> TapePalette(g(0.88f), g(0.46f), 1f, g(0.05f),
            rgb(0.96f, 0.95f, 0.93f), rgb(0.12f, 0.15f, 0.24f), false, "LUME  ·  CHROME TYPE II")
        CassetteStyle.VINTAGE_CREAM -> TapePalette(rgb(0.95f, 0.91f, 0.80f), rgb(0.80f, 0.74f, 0.61f), 1f, g(0.07f),
            rgb(0.98f, 0.96f, 0.89f), rgb(0.64f, 0.24f, 0.14f), false, "LUME  ·  NORMAL BIAS")
    }

    class CassetteLayers(val back: Bitmap, val front: Bitmap, val shadow: Bitmap)

    private fun screw(c: Canvas, x: Float, y: Float, r: Float) {
        c.drawCircle(x, y, r, radial(x - r * 0.3f, y - r * 0.3f, r * 1.2f, intArrayOf(g(0.95f), g(0.62f), g(0.30f)), floatArrayOf(0f, 0.6f, 1f)))
        c.drawCircle(x, y, r, strokePaint(g(0f, 0.55f), max(1f, r * 0.12f)))
        c.save(); c.rotate(35f, x, y)
        c.drawLine(x - r * 0.65f, y, x + r * 0.65f, y, strokePaint(g(0f, 0.65f), max(1.2f, r * 0.2f)))
        c.restore()
    }

    /** Camadas da fita: `back` fica sob os carretéis; `front` (etiqueta com janela vazada, plástico, parafusos, brilho) sobre eles. */
    fun cassetteLayers(tape: CassetteStyle, sideB: Boolean, wpx: Int): CassetteLayers {
        val pal = palette(tape)
        val w = wpx.toFloat()
        val h = (w / TAPE_ASPECT).roundToInt().toFloat()
        val hC = h / w
        val corner = 0.034f * w
        fun px(x: Float) = x * w
        fun rect(x: Float, y: Float, ww: Float, hh: Float) = RectF(x * w, y * w, (x + ww) * w, (y + hh) * w)
        val bodyRect = RectF(0.5f, 0.5f, w - 0.5f, h - 0.5f)
        val bodyPath = Path().apply { addRoundRect(bodyRect, corner, corner, Path.Direction.CW) }
        val labelRect = rect(LABEL_RECT.left, LABEL_RECT.top, LABEL_RECT.width(), LABEL_RECT.height())
        val winRect = rect(WINDOW_RECT.left, WINDOW_RECT.top, WINDOW_RECT.width(), WINDOW_RECT.height())
        val winPath = Path().apply { addRoundRect(winRect, 0.06f * w, 0.06f * w, Path.Direction.CW) }
        val labelPath = Path().apply { addRoundRect(labelRect, 0.014f * w, 0.014f * w, Path.Direction.CW) }

        // aberturas da borda inferior (cabeçote, roletes, furos de guia)
        val holes = listOf(
            Path().apply { addRoundRect(rect(0.452f, 0.572f, 0.096f, hC - 0.572f + 0.02f), 0.006f * w, 0.006f * w, Path.Direction.CW) },
            Path().apply { addRoundRect(rect(0.250f, 0.566f, 0.082f, hC - 0.566f + 0.02f), 0.012f * w, 0.012f * w, Path.Direction.CW) },
            Path().apply { addRoundRect(rect(0.668f, 0.566f, 0.082f, hC - 0.566f + 0.02f), 0.012f * w, 0.012f * w, Path.Direction.CW) },
            Path().apply { addOval(RectF(0.118f * w - 0.0105f * w, 0.6035f * w - 0.0105f * w, 0.118f * w + 0.0105f * w, 0.6035f * w + 0.0105f * w), Path.Direction.CW) },
            Path().apply { addOval(RectF(0.882f * w - 0.0105f * w, 0.6035f * w - 0.0105f * w, 0.882f * w + 0.0105f * w, 0.6035f * w + 0.0105f * w), Path.Direction.CW) },
        )

        // ---------- sombra (independente de estilo)
        val mX = SHADOW_MX * w; val mT = SHADOW_MT * w; val mB = SHADOW_MB * w
        val shadow = bitmap((w + 2 * mX).toInt(), (h + mT + mB).toInt()) { c ->
            val r = RectF(mX, mT, mX + w, mT + h)
            c.drawRoundRect(r, corner, corner, fillPaint(Color.BLACK).apply { setShadowLayer(0.05f * w, 0f, 0.035f * w, g(0f, 0.62f)) })
            val clear = Paint(Paint.ANTI_ALIAS_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR) }
            c.drawRoundRect(RectF(r.left + 1, r.top + 1, r.right - 1, r.bottom - 1), corner, corner, clear)
        }

        // ---------- camada de trás
        val back = bitmap(wpx, h.toInt()) { c ->
            c.save()
            c.clipPath(bodyPath)
            c.drawRect(0f, 0f, w, h, linear(0f, 0f, 0f, h, intArrayOf(pal.bodyTop, pal.bodyBottom)))
            // leito escuro da janela + poços dos carretéis
            val bed = RectF(winRect.left - 0.012f * w, winRect.top - 0.012f * w, winRect.right + 0.012f * w, winRect.bottom + 0.012f * w)
            c.drawRoundRect(bed, 0.07f * w, 0.07f * w, fillPaint(pal.bed))
            for (rc in listOf(REEL_L, REEL_R)) {
                val rx = px(rc.first); val ry = px(rc.second)
                c.save()
                c.clipPath(Path().apply { addCircle(rx, ry, 0.092f * w, Path.Direction.CW) })
                c.drawCircle(rx, ry, 0.092f * w, radial(rx, ry, 0.092f * w,
                    intArrayOf(g(if (pal.dark) 0.16f else 0.34f), g(if (pal.dark) 0.02f else 0.10f)), null))
                c.restore()
                c.drawCircle(rx, ry, 0.090f * w, strokePaint(g(1f, 0.14f), max(1f, 0.0025f * w)))
                val teeth = strokePaint(g(1f, 0.10f), max(1f, 0.0025f * w))
                for (k in 0 until 24) {
                    val a = k.toFloat() / 24 * 2 * PI.toFloat()
                    c.drawLine(rx + 0.047f * w * cos(a), ry + 0.047f * w * sin(a), rx + 0.055f * w * cos(a), ry + 0.055f * w * sin(a), teeth)
                }
            }
            // roletes guia, sapata e fita esticada na borda inferior
            for (rp in listOf(ROLLER_L, ROLLER_R)) {
                val rx = px(rp.first); val ry = px(rp.second)
                c.drawCircle(rx, ry, 0.0165f * w, fillPaint(g(0.7f)).apply { setShadowLayer(0.008f * w, 0f, 0.004f * w, g(0f, 0.6f)) })
                c.save()
                c.clipPath(Path().apply { addCircle(rx, ry, 0.0165f * w, Path.Direction.CW) })
                c.drawCircle(rx, ry, 0.02f * w, radial(rx - 0.005f * w, ry - 0.005f * w, 0.02f * w, intArrayOf(g(1f), g(0.7f), g(0.35f)), floatArrayOf(0f, 0.5f, 1f)))
                c.restore()
                c.drawCircle(rx, ry, 0.005f * w, fillPaint(g(0.1f)))
            }
            c.drawRect(rect(0.42f, 0.572f, 0.16f, 0.026f), fillPaint(g(0.62f)))
            c.drawRect(rect(0.42f, 0.572f, 0.16f, 0.004f), fillPaint(g(1f, 0.35f)))
            c.drawLine(px(ROLLER_L.first), 0.6105f * w, px(ROLLER_R.first), 0.6105f * w, strokePaint(rgb(0.30f, 0.18f, 0.10f), 0.0055f * w))
            c.drawLine(px(ROLLER_L.first), 0.6085f * w, px(ROLLER_R.first), 0.6085f * w, strokePaint(g(1f, 0.22f), 0.0014f * w))
            c.restore()
        }

        // ---------- camada da frente
        val front = bitmap(wpx, h.toInt()) { c ->
            val clear = Paint(Paint.ANTI_ALIAS_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR) }
            // 1) plástico (translúcido no fumê/cristal) com o recorte da etiqueta
            val plastic = Path().apply { fillType = Path.FillType.EVEN_ODD; addPath(bodyPath); addPath(labelPath) }
            c.save()
            c.clipPath(plastic)
            c.drawRect(0f, 0f, w, h, linear(0f, 0f, 0f, h, intArrayOf(withAlpha(pal.bodyTop, pal.overlayAlpha), withAlpha(pal.bodyBottom, pal.overlayAlpha))))
            c.drawRect(0f, 0f, 0.055f * w, h, linear(0f, 0f, 0.055f * w, 0f, intArrayOf(g(1f, 0f), g(1f, if (pal.dark) 0.10f else 0.30f), g(1f, 0f)), floatArrayOf(0f, 0.5f, 1f)))
            c.drawRect(0.945f * w, 0f, w, h, linear(0.945f * w, 0f, w, 0f, intArrayOf(g(1f, 0f), g(1f, if (pal.dark) 0.06f else 0.20f), g(1f, 0f)), floatArrayOf(0f, 0.5f, 1f)))
            // recesso trapezoidal inferior
            val trap = Path().apply {
                moveTo(0.215f * w, 0.452f * w); lineTo(0.785f * w, 0.452f * w)
                lineTo(0.895f * w, (hC - 0.004f) * w); lineTo(0.105f * w, (hC - 0.004f) * w); close()
            }
            c.drawPath(trap, fillPaint(g(0f, if (pal.dark) 0.34f else 0.20f)))
            c.drawLine(0.215f * w, 0.452f * w, 0.785f * w, 0.452f * w, strokePaint(g(1f, if (pal.dark) 0.20f else 0.55f), max(1f, 0.0028f * w)))
            val edge = strokePaint(g(0f, 0.40f), max(1f, 0.0028f * w))
            c.drawLine(0.215f * w, 0.4565f * w, 0.105f * w, (hC - 0.004f) * w, edge)
            c.drawLine(0.785f * w, 0.4565f * w, 0.895f * w, (hC - 0.004f) * w, edge)
            c.restore()

            // aberturas (vazadas)
            for (hole in holes) c.drawPath(hole, clear)
            for (hole in holes) c.drawPath(hole, strokePaint(g(0f, 0.6f), max(1f, 0.0025f * w)))

            // 2) etiqueta de papel com janela vazada
            val labelWithWin = Path().apply { fillType = Path.FillType.EVEN_ODD; addPath(labelPath); addPath(winPath) }
            c.drawPath(labelWithWin, fillPaint(pal.paper).apply { setShadowLayer(0.006f * w, 0f, 0.003f * w, g(0f, 0.5f)) })
            c.save()
            c.clipPath(labelWithWin)
            c.drawRect(labelRect, linear(0f, labelRect.top, 0f, labelRect.bottom, intArrayOf(g(1f, 0.35f), g(0f, 0.06f))))
            // faixa colorida superior
            val stripeR = rect(LABEL_RECT.left, LABEL_RECT.top, LABEL_RECT.width(), 0.052f)
            c.drawRect(stripeR, fillPaint(pal.stripe))
            c.drawRect(stripeR.left, stripeR.top, stripeR.right, stripeR.top + 0.0035f * w, fillPaint(g(1f, 0.16f)))
            // linhas pautadas para a escrita à mão
            val rule = strokePaint(rgb(0.42f, 0.52f, 0.70f, 0.55f), max(0.8f, 0.0018f * w))
            for (yy in listOf(0.152f, 0.190f)) c.drawLine(0.085f * w, yy * w, 0.775f * w, yy * w, rule)
            c.restore()

            // moldura do espaço da capa (foto instantânea)
            c.drawRect(rect(0.826f, 0.100f, 0.094f, 0.094f), fillPaint(g(0.99f)).apply { setShadowLayer(0.004f * w, 0f, 0.002f * w, g(0f, 0.5f)) })

            // textos impressos
            fun text(s: String, size: Float, bold: Int, color: Int, x: Float, y: Float, align: Paint.Align, kern: Float = 0f) {
                val tp = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    typeface = if (android.os.Build.VERSION.SDK_INT >= 28) Typeface.create(Typeface.DEFAULT, bold, false)
                    else Typeface.create(Typeface.DEFAULT, if (bold >= 700) Typeface.BOLD else Typeface.NORMAL)
                    textSize = size * w; this.color = color
                    textAlign = align; letterSpacing = if (kern == 0f) 0f else kern / size
                }
                val fm = tp.fontMetrics
                c.drawText(s, x * w, y * w - (fm.ascent + fm.descent) / 2, tp)
            }
            val letter = if (sideB) "B" else "A"
            c.drawCircle(0.092f * w, 0.071f * w, 0.0205f * w, fillPaint(g(1f, 0.95f)))
            text(letter, 0.030f, 900, pal.stripe, 0.092f, 0.0715f, Paint.Align.CENTER)
            text(pal.brand, 0.0175f, 800, g(1f, 0.95f), 0.5f, 0.071f, Paint.Align.CENTER, 0.002f)
            text("C-60", 0.027f, 900, g(1f, 0.95f), 0.925f, 0.071f, Paint.Align.RIGHT, 0.001f)
            val ink = g(0.12f, 0.78f)
            text(if (sideB) "LADO B" else "LADO A", 0.0125f, 800, withAlpha(ink, 0.6f), 0.085f, 0.108f, Paint.Align.LEFT, 0.003f)
            text(letter, 0.098f, 900, withAlpha(pal.stripe, 0.9f), 0.120f, 0.288f, Paint.Align.CENTER)
            text("60", 0.066f, 900, withAlpha(ink, 0.7f), 0.880f, 0.266f, Paint.Align.CENTER)
            text("MIN", 0.0155f, 800, withAlpha(ink, 0.6f), 0.880f, 0.320f, Paint.Align.CENTER, 0.002f)
            text("NR  ·  TYPE I  ·  120 µs", 0.0128f, 600, withAlpha(ink, 0.55f), 0.5f, 0.3875f, Paint.Align.CENTER, 0.002f)

            // 3) janela: chanfro + vidro com reflexo
            c.drawPath(winPath, strokePaint(g(0f, 0.75f), max(1.2f, 0.005f * w)))
            c.save()
            c.clipPath(winPath)
            val glare = Path().apply {
                moveTo(winRect.left + winRect.width() * 0.10f, winRect.top); lineTo(winRect.left + winRect.width() * 0.34f, winRect.top)
                lineTo(winRect.left + winRect.width() * 0.18f, winRect.bottom); lineTo(winRect.left - winRect.width() * 0.06f, winRect.bottom); close()
            }
            c.save()
            c.clipPath(glare)
            c.drawRect(winRect, linear(winRect.left, 0f, winRect.left + winRect.width() * 0.34f, 0f, intArrayOf(g(1f, 0f), g(1f, 0.20f), g(1f, 0f)), floatArrayOf(0f, 0.5f, 1f)))
            c.restore()
            c.drawRect(winRect.left, winRect.top, winRect.right, winRect.top + winRect.height() * 0.4f,
                linear(0f, winRect.top, 0f, winRect.top + winRect.height() * 0.4f, intArrayOf(g(1f, 0.14f), g(1f, 0f))))
            c.restore()
            c.drawRoundRect(RectF(winRect.left + 0.002f * w, winRect.top + 0.002f * w, winRect.right - 0.002f * w, winRect.bottom - 0.002f * w),
                0.058f * w, 0.058f * w,
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE; strokeWidth = max(1f, 0.0022f * w)
                    shader = LinearGradient(0f, winRect.top, 0f, winRect.bottom, intArrayOf(g(1f, 0.65f), g(1f, 0.05f), g(0f, 0.35f)), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
                })
            // marcas de guia na borda da janela
            val tick = strokePaint(g(0f, 0.4f), max(0.8f, 0.0016f * w))
            for (k in 0 until 7) {
                val x = (0.43f + k * 0.023f) * w
                c.drawLine(x, winRect.bottom - 0.0075f * w, x, winRect.bottom - 0.0015f * w, tick)
            }

            // 4) parafusos
            for ((sx, sy) in listOf(0.040f to 0.040f, 0.960f to 0.040f, 0.040f to hC - 0.040f, 0.960f to hC - 0.040f, 0.5f to 0.0215f, 0.5f to 0.4765f)) {
                screw(c, sx * w, sy * w, 0.0125f * w)
            }

            // 5) contorno chanfrado e brilho
            c.save()
            c.clipPath(bodyPath)
            c.drawRect(0f, 0f, w, h, linear(0f, 0f, w * 0.5f, h * 0.9f, intArrayOf(g(1f, if (pal.dark) 0.16f else 0.34f), g(1f, 0f))))
            c.restore()
            c.drawRoundRect(bodyRect, corner, corner, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE; strokeWidth = max(1.2f, 0.007f * w)
                shader = LinearGradient(0f, 0f, w, h, intArrayOf(g(1f, if (pal.dark) 0.55f else 0.95f), g(1f, 0.12f), g(0f, 0.45f)), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
            })
            val inner = RectF(0.008f * w, 0.008f * w, w - 0.008f * w, h - 0.008f * w)
            c.drawRoundRect(inner, corner * 0.8f, corner * 0.8f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE; strokeWidth = max(0.8f, 0.0018f * w)
                shader = LinearGradient(0f, 0f, w, h, intArrayOf(g(0f, 0.28f), g(1f, 0.25f)), null, Shader.TileMode.CLAMP)
            })
        }
        return CassetteLayers(back, front, shadow)
    }

    /** Carretel (hub) com dentes brancos. */
    fun hub(px: Int): Bitmap = bitmap(px, px) { c ->
        val d = px.toFloat(); val cx = d / 2; val cy = d / 2; val r = d / 2 - 1
        c.drawCircle(cx, cy, r, fillPaint(g(0.9f)).apply { setShadowLayer(d * 0.03f, 0f, 0f, g(0f, 0.5f)) })
        c.save()
        c.clipPath(Path().apply { addCircle(cx, cy, r, Path.Direction.CW) })
        c.drawCircle(cx, cy, r * 1.1f, radial(cx - r * 0.3f, cy - r * 0.3f, r * 1.4f, intArrayOf(g(1f), g(0.86f), g(0.62f)), floatArrayOf(0f, 0.6f, 1f)))
        c.restore()
        val holeR = r * 0.60f
        c.drawCircle(cx, cy, holeR, radial(cx, cy, holeR, intArrayOf(g(0.02f), g(0.16f))))
        for (k in 0 until 6) {
            c.save(); c.translate(cx, cy); c.rotate(k * 60f)
            val tooth = RectF(-r * 0.085f, -holeR - r * 0.02f, r * 0.085f, -holeR - r * 0.02f + r * 0.30f)
            c.drawRoundRect(tooth, r * 0.03f, r * 0.03f, fillPaint(g(0.95f)))
            c.drawRoundRect(tooth, r * 0.03f, r * 0.03f, strokePaint(g(0f, 0.35f), max(1f, r * 0.018f)))
            c.restore()
        }
        c.drawCircle(cx, cy, r, strokePaint(g(0f, 0.4f), max(1f, r * 0.03f)))
        c.drawCircle(cx, cy, r * 0.9f, strokePaint(g(1f, 0.8f), max(1f, r * 0.02f)))
    }

    /** Rolo de fita marrom. */
    fun pack(px: Int): Bitmap = bitmap(px, px) { c ->
        val d = px.toFloat(); val cx = d / 2; val cy = d / 2; val r = d / 2 - 1
        val rng = Rng(77)
        c.save()
        c.clipPath(Path().apply { addCircle(cx, cy, r, Path.Direction.CW) })
        c.drawCircle(cx, cy, r, radial(cx, cy, r, intArrayOf(rgb(0.20f, 0.12f, 0.07f), rgb(0.30f, 0.18f, 0.10f), rgb(0.24f, 0.14f, 0.08f)), floatArrayOf(0f, 0.7f, 1f)))
        var rr = r
        while (rr > r * 0.2f) {
            c.drawCircle(cx, cy, rr, strokePaint(if (rng.next() > 0.5f) g(1f, rng.range(0.03f, 0.10f)) else g(0f, rng.range(0.03f, 0.10f)), max(0.6f, d * 0.0022f)))
            rr -= rng.range(d * 0.004f, d * 0.011f)
        }
        for (ang in listOf(0.9f, 0.9f + PI.toFloat())) {
            c.save(); c.translate(cx, cy); c.rotate(Math.toDegrees(ang.toDouble()).toFloat())
            c.drawRect(-r, -r * 0.35f, r, r * 0.35f, linear(0f, -r * 0.35f, 0f, r * 0.35f, intArrayOf(g(1f, 0f), g(1f, 0.13f), g(1f, 0f)), floatArrayOf(0f, 0.5f, 1f)))
            c.restore()
        }
        c.restore()
        c.drawCircle(cx, cy, r * 0.992f, strokePaint(rgb(0.42f, 0.27f, 0.16f, 0.9f), max(1f, d * 0.008f)))
    }

    fun cassette(cover: Bitmap, title: String, artist: String, style: CassetteStyle): Bitmap {
        val s = SIDE.toFloat()
        val w = s * 0.86f
        val h = w / TAPE_ASPECT
        val layers = cassetteLayers(style, false, w.toInt())
        val hubBmp = hub((HUB_R * 2 * w).toInt())
        val packBmp = pack((R_FULL * 2 * w).toInt())
        return bitmap(SIDE, SIDE) { c ->
            drawBackdrop(c, cover, s)
            val ox = (s - w) / 2; val oy = (s - h) / 2 - s * 0.02f
            val bmpPaint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
            // sombra
            c.drawBitmap(layers.shadow, null, RectF(ox - w * SHADOW_MX, oy - w * SHADOW_MT, ox - w * SHADOW_MX + (w * (1 + 2 * SHADOW_MX)), oy - w * SHADOW_MT + (h + w * (SHADOW_MT + SHADOW_MB))), bmpPaint)
            c.drawBitmap(layers.back, null, RectF(ox, oy, ox + w, oy + h), bmpPaint)
            // carretéis no meio da faixa (rolo da esquerda um pouco maior)
            val q = 0.38f
            val a = R_FULL * R_FULL - R_EMPTY * R_EMPTY
            val rL = sqrt(R_FULL * R_FULL - q * a)
            val rR = sqrt(R_EMPTY * R_EMPTY + q * a)
            for ((center, r, ang) in listOf(Triple(REEL_L, rL, 0.4f), Triple(REEL_R, rR, 1.1f))) {
                val ccx = ox + center.first * w; val ccy = oy + center.second * w
                c.drawBitmap(packBmp, null, RectF(ccx - r * w, ccy - r * w, ccx + r * w, ccy + r * w), bmpPaint)
                c.save(); c.translate(ccx, ccy); c.rotate(Math.toDegrees(ang.toDouble()).toFloat())
                val hr = HUB_R * w
                c.drawBitmap(hubBmp, null, RectF(-hr, -hr, hr, hr), bmpPaint)
                c.restore()
            }
            c.drawBitmap(layers.front, null, RectF(ox, oy, ox + w, oy + h), bmpPaint)

            // escrita à mão na etiqueta (mesmas posições do app)
            val hand = Typeface.create("cursive", Typeface.BOLD)
            fun write(text: String, size: Float, color: Int, y: Float) {
                val tp = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = hand; textSize = size; this.color = color }
                val avail = w * 0.69f
                val txt = TextUtils.ellipsize(text, tp, avail, TextUtils.TruncateAt.END).toString()
                val fm = tp.fontMetrics
                val cx = ox + w * 0.085f + avail / 2
                val cy = oy + w * y
                c.save(); c.rotate(Math.toDegrees(-0.012).toFloat(), cx, cy)
                c.drawText(txt, ox + w * 0.085f, cy - (fm.ascent + fm.descent) / 2, tp)
                c.restore()
            }
            write(title, w * 0.054f, rgb(0.10f, 0.14f, 0.46f), 0.133f)
            write(artist, w * 0.040f, rgb(0.16f, 0.18f, 0.40f, 0.85f), 0.172f)

            // capinha colada na etiqueta
            val sd = w * 0.078f
            val thumb = RectF(ox + w * 0.873f - sd / 2, oy + w * 0.147f - sd / 2, ox + w * 0.873f + sd / 2, oy + w * 0.147f + sd / 2)
            c.save()
            c.clipPath(Path().apply { addRoundRect(thumb, w * 0.004f, w * 0.004f, Path.Direction.CW) })
            drawCover(c, cover, thumb)
            c.restore()
        }
    }
}
