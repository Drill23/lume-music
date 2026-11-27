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

    // Um só desenho fiel: as texturas (prato/disco, reflexo, fita K7, carretel, rolo) vêm de StageTextures,
    // as mesmas usadas pelos palcos Vinil/K7 do Tocando agora (porte de LumeTextures.swift / CassetteArt.swift).
    fun record(edition: VinylEdition, px: Int): Bitmap = StageTextures.record(edition, px)
    fun sheen(prism: Boolean, size: Int): Bitmap = StageTextures.sheen(prism, max(8, size))
    fun cassetteLayers(tape: CassetteStyle, sideB: Boolean, wpx: Int): CassetteLayers = StageTextures.cassetteLayers(tape, sideB, wpx)
    fun hub(px: Int): Bitmap = StageTextures.hub(px)
    fun pack(px: Int): Bitmap = StageTextures.pack(px)

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
