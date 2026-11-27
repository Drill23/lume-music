package com.adriano.lumemusic.ui.stage

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Pequena camada sobre android.graphics.Canvas que imita o CGContext usado em LumeTextures.swift / CassetteArt.swift
 * (cor de preenchimento/traço, sombra, gradientes sem extensão, clip, path acumulado), para o código de desenho ser
 * portado linha a linha. Coordenadas com origem no canto superior esquerdo, y para baixo, como no UIKit.
 */
internal class Cg(val bmp: Bitmap) {
    constructor(w: Int, h: Int) : this(Bitmap.createBitmap(maxOf(1, w), maxOf(1, h), Bitmap.Config.ARGB_8888))

    val cv = Canvas(bmp)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val tmp = Path()
    private val tmp2 = Path()
    var cur = Path()

    private class St(
        val fill: Int, val stroke: Int, val lw: Float, val cap: Paint.Cap,
        val shOn: Boolean, val shR: Float, val shDx: Float, val shDy: Float, val shCol: Int,
        val mode: PorterDuff.Mode?,
    )

    private var fill = Color.BLACK
    private var stroke = Color.BLACK
    var lw = 1f
    private var cap = Paint.Cap.BUTT
    private var shOn = false
    private var shR = 0f
    private var shDx = 0f
    private var shDy = 0f
    private var shCol = 0
    var mode: PorterDuff.Mode? = null
    private val stack = ArrayList<St>()

    fun setFill(c: Int) { fill = c }
    fun setStroke(c: Int) { stroke = c }
    fun setCap(c: Paint.Cap) { cap = c }
    fun setShadow(dx: Float, dy: Float, blur: Float, color: Int) {
        shOn = true; shDx = dx; shDy = dy; shCol = color; shR = shadowRadius(blur)
    }
    fun noShadow() { shOn = false }

    fun save() {
        stack.add(St(fill, stroke, lw, cap, shOn, shR, shDx, shDy, shCol, mode))
        cv.save()
    }
    fun restore() {
        cv.restore()
        val s = stack.removeAt(stack.size - 1)
        fill = s.fill; stroke = s.stroke; lw = s.lw; cap = s.cap; shOn = s.shOn; shR = s.shR; shDx = s.shDx; shDy = s.shDy; shCol = s.shCol; mode = s.mode
    }

    fun translate(x: Float, y: Float) = cv.translate(x, y)
    fun rotate(rad: Float) = cv.rotate(Math.toDegrees(rad.toDouble()).toFloat())

    private fun prep(style: Paint.Style, color: Int): Paint {
        paint.reset()
        paint.isAntiAlias = true
        paint.style = style
        paint.color = color
        if (style == Paint.Style.STROKE) { paint.strokeWidth = lw; paint.strokeCap = cap }
        if (shOn) paint.setShadowLayer(shR, shDx, shDy, shCol)
        if (mode != null) paint.xfermode = PorterDuffXfermode(mode)
        return paint
    }

    // ---- primitivas (preenchimento/traço imediato)
    fun fillEllipse(cx: Float, cy: Float, r: Float) = cv.drawCircle(cx, cy, r, prep(Paint.Style.FILL, fill))
    fun strokeEllipse(cx: Float, cy: Float, r: Float) = cv.drawCircle(cx, cy, r, prep(Paint.Style.STROKE, stroke))
    fun fillRect(x: Float, y: Float, w: Float, h: Float) = cv.drawRect(x, y, x + w, y + h, prep(Paint.Style.FILL, fill))
    fun fillPath(p: Path, evenOdd: Boolean = false) {
        p.fillType = if (evenOdd) Path.FillType.EVEN_ODD else Path.FillType.WINDING
        cv.drawPath(p, prep(Paint.Style.FILL, fill))
        p.fillType = Path.FillType.WINDING
    }
    fun strokePath(p: Path) = cv.drawPath(p, prep(Paint.Style.STROKE, stroke))
    fun fillRound(x: Float, y: Float, w: Float, h: Float, r: Float) = cv.drawRoundRect(x, y, x + w, y + h, r, r, prep(Paint.Style.FILL, fill))
    fun strokeRound(x: Float, y: Float, w: Float, h: Float, r: Float) = cv.drawRoundRect(x, y, x + w, y + h, r, r, prep(Paint.Style.STROKE, stroke))
    fun fillPoly(vararg pts: Float) {
        val p = Path(); p.moveTo(pts[0], pts[1])
        var i = 2
        while (i < pts.size) { p.lineTo(pts[i], pts[i + 1]); i += 2 }
        p.close()
        cv.drawPath(p, prep(Paint.Style.FILL, fill))
    }

    // ---- path corrente (move/line/stroke como no CG)
    fun move(x: Float, y: Float) = cur.moveTo(x, y)
    fun line(x: Float, y: Float) = cur.lineTo(x, y)
    fun strokeCur() { cv.drawPath(cur, prep(Paint.Style.STROKE, stroke)); cur = Path() }

    /** Apaga (BlendMode.clear) o preenchimento do path. */
    fun clearPath(p: Path) {
        paint.reset(); paint.isAntiAlias = true; paint.style = Paint.Style.FILL
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
        cv.drawPath(p, paint)
    }

    // ---- clip
    fun clipEllipse(cx: Float, cy: Float, r: Float) { tmp.reset(); tmp.addCircle(cx, cy, r, Path.Direction.CW); cv.clipPath(tmp) }
    fun clipPath(p: Path) { cv.clipPath(p) }
    fun clipEvenOdd(a: Path, b: Path) {
        tmp2.reset(); tmp2.addPath(a); tmp2.addPath(b); tmp2.fillType = Path.FillType.EVEN_ODD
        cv.clipPath(tmp2)
    }
    /** replacePathWithStrokedPath + clip. */
    fun clipStroked(p: Path, width: Float, round: Boolean = false) {
        val pt = Paint(Paint.ANTI_ALIAS_FLAG)
        pt.style = Paint.Style.STROKE; pt.strokeWidth = width
        if (round) pt.strokeCap = Paint.Cap.ROUND
        val out = Path()
        pt.getFillPath(p, out)
        cv.clipPath(out)
    }

    // ---- gradientes (sem extensão fora do intervalo, como drawLinearGradient(options: []))
    fun linGrad(colors: IntArray, locs: FloatArray?, x0: Float, y0: Float, x1: Float, y1: Float) {
        val dx = x1 - x0; val dy = y1 - y0
        val len = hypot(dx, dy)
        if (len < 1e-3f) return
        val big = 20000f
        val nx = -dy / len * big; val ny = dx / len * big
        cv.save()
        tmp.reset()
        tmp.moveTo(x0 + nx, y0 + ny); tmp.lineTo(x1 + nx, y1 + ny); tmp.lineTo(x1 - nx, y1 - ny); tmp.lineTo(x0 - nx, y0 - ny); tmp.close()
        cv.clipPath(tmp)
        paint.reset(); paint.isAntiAlias = true
        paint.shader = LinearGradient(x0, y0, x1, y1, colors, locs, Shader.TileMode.CLAMP)
        cv.drawPaint(paint)
        cv.restore()
    }
    fun lin(c0: Int, c1: Int, x0: Float, y0: Float, x1: Float, y1: Float) = linGrad(intArrayOf(c0, c1), null, x0, y0, x1, y1)

    fun radGrad(colors: IntArray, locs: FloatArray?, sx: Float, sy: Float, sr: Float, ex: Float, ey: Float, er: Float) {
        cv.save()
        var cx = ex; var cy = ey; var rad = er; var stops = locs
        val shifted = sx != ex || sy != ey
        if (shifted) {
            // cone do CG aproximado por um radial com foco deslocado: centro no ponto inicial, alcance até a borda oposta
            cx = sx; cy = sy; rad = er + hypot(ex - sx, ey - sy)
        }
        tmp.reset(); tmp.addCircle(ex, ey, er, Path.Direction.CW)
        if (sr > 0f && !shifted) {
            tmp2.reset(); tmp2.addCircle(ex, ey, sr, Path.Direction.CW)
            tmp.op(tmp2, Path.Op.DIFFERENCE)
            val f = sr / er
            val n = colors.size
            val l = locs ?: FloatArray(n) { it / (n - 1f) }
            stops = FloatArray(n) { f + (1f - f) * l[it] }
        }
        cv.clipPath(tmp)
        paint.reset(); paint.isAntiAlias = true
        paint.shader = RadialGradient(cx, cy, rad, colors, stops, Shader.TileMode.CLAMP)
        cv.drawPaint(paint)
        cv.restore()
    }

    // ---- ruído em ladrilho
    fun tileNoise(l: Float, t: Float, r: Float, b: Float, alpha: Float, m: PorterDuff.Mode, seed: Long) {
        val tile = StageTextures.noiseTile(seed)
        val sh = BitmapShader(tile, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT)
        val mx = android.graphics.Matrix(); mx.setTranslate(l, t); sh.setLocalMatrix(mx)
        paint.reset(); paint.isAntiAlias = false
        paint.shader = sh
        paint.alpha = (alpha * 255).roundToInt()
        paint.xfermode = PorterDuffXfermode(m)
        cv.save(); cv.clipRect(l, t, r, b); cv.drawRect(l, t, r, b, paint); cv.restore()
    }

    fun drawBitmapScaled(b: Bitmap, l: Float, t: Float, r: Float, bt: Float) {
        paint.reset(); paint.isFilterBitmap = true; paint.isAntiAlias = true
        cv.drawBitmap(b, null, RectF(l, t, r, bt), paint)
    }

    /** Texto com o centro vertical da linha em y (a.draw(at: y - h/2)); kernEm em "em" (kern/size). */
    fun text(s: String, size: Float, weight: Int, color: Int, x: Float, y: Float, align: Int, kern: Float = 0f) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.typeface = weightFace(weight)
        p.textSize = size
        p.color = color
        p.letterSpacing = if (size > 0) kern / size else 0f
        val fm = p.fontMetrics
        val h = fm.descent - fm.ascent
        val w = p.measureText(s)
        val ox = when (align) { RIGHT -> x - w; CENTER -> x - w / 2; else -> x }
        cv.drawText(s, ox, y - h / 2 - fm.ascent, p)
    }

    /** Texto com o topo da caixa da linha em yTop. */
    fun textTop(s: String, size: Float, weight: Int, color: Int, x: Float, yTop: Float, centered: Boolean) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.typeface = weightFace(weight); p.textSize = size; p.color = color
        val fm = p.fontMetrics
        val w = p.measureText(s)
        cv.drawText(s, if (centered) x - w / 2 else x, yTop - fm.ascent, p)
    }

    companion object {
        const val LEFT = 0
        const val CENTER = 1
        const val RIGHT = 2

        /** Blur do CGContext (≈ 2σ) → raio do setShadowLayer do Android. */
        fun shadowRadius(blur: Float): Float = max(0.5f, (blur / 2f - 0.5f) / 0.57735f)

        fun gray(w: Float, a: Float = 1f): Int {
            val v = (w * 255f).roundToInt().coerceIn(0, 255)
            return Color.argb((a * 255f).roundToInt().coerceIn(0, 255), v, v, v)
        }
        fun rgb(r: Float, g: Float, b: Float, a: Float = 1f): Int =
            Color.argb((a * 255f).roundToInt().coerceIn(0, 255), (r * 255f).roundToInt().coerceIn(0, 255), (g * 255f).roundToInt().coerceIn(0, 255), (b * 255f).roundToInt().coerceIn(0, 255))
        fun hsb(h: Float, s: Float, b: Float, a: Float = 1f): Int =
            Color.HSVToColor((a * 255f).roundToInt().coerceIn(0, 255), floatArrayOf((h - kotlin.math.floor(h)) * 360f, s, b))
        fun withAlpha(c: Int, a: Float): Int = (c and 0x00FFFFFF) or ((a * 255f).roundToInt().coerceIn(0, 255) shl 24)

        fun cols(vararg c: Int): IntArray = c
        fun locs(vararg l: Float): FloatArray = l

        private val faces = HashMap<Int, Typeface>()
        fun weightFace(w: Int): Typeface = synchronized(faces) {
            faces.getOrPut(w) {
                if (android.os.Build.VERSION.SDK_INT >= 28) Typeface.create(Typeface.DEFAULT, w, false)
                else when {
                    w >= 800 -> Typeface.create("sans-serif-black", Typeface.NORMAL)
                    w >= 600 -> Typeface.create("sans-serif-medium", Typeface.BOLD)
                    w >= 500 -> Typeface.create("sans-serif-medium", Typeface.NORMAL)
                    else -> Typeface.DEFAULT
                }
            }
        }

        fun roundRectPath(l: Float, t: Float, r: Float, b: Float, rad: Float): Path =
            Path().apply { addRoundRect(RectF(l, t, r, b), rad, rad, Path.Direction.CW) }
        fun ovalPath(l: Float, t: Float, r: Float, b: Float): Path = Path().apply { addOval(RectF(l, t, r, b), Path.Direction.CW) }
    }
}

/** Gerador pseudoaleatório idêntico ao TextureRNG do Swift (xorshift64). */
internal class TextureRNG(seed: Long) {
    private var s: Long = (seed * -7046029254386353131L) or 1L   // 0x9E3779B97F4A7C15
    fun next(): Float {
        s = s xor (s shl 13); s = s xor (s ushr 7); s = s xor (s shl 17)
        return java.lang.Long.remainderUnsigned(s, 100_000L).toFloat() / 100_000f
    }
    fun range(a: Float, b: Float): Float = a + (b - a) * next()
}

internal const val PIF = PI.toFloat()
internal const val TAUF = (2 * PI).toFloat()
internal fun cosf(x: Float) = cos(x.toDouble()).toFloat()
internal fun sinf(x: Float) = sin(x.toDouble()).toFloat()
