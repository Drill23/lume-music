package com.adriano.lumemusic.ui.stage

import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.util.LruCache
import com.adriano.lumemusic.data.CassetteStyle
import com.adriano.lumemusic.data.TurntableFinish
import com.adriano.lumemusic.data.VinylEdition
import com.adriano.lumemusic.ui.stage.Cg.Companion.CENTER
import com.adriano.lumemusic.ui.stage.Cg.Companion.LEFT
import com.adriano.lumemusic.ui.stage.Cg.Companion.RIGHT
import com.adriano.lumemusic.ui.stage.Cg.Companion.cols
import com.adriano.lumemusic.ui.stage.Cg.Companion.gray
import com.adriano.lumemusic.ui.stage.Cg.Companion.hsb
import com.adriano.lumemusic.ui.stage.Cg.Companion.locs
import com.adriano.lumemusic.ui.stage.Cg.Companion.rgb
import com.adriano.lumemusic.ui.stage.Cg.Companion.roundRectPath
import com.adriano.lumemusic.ui.stage.Cg.Companion.withAlpha
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

// ============================================================ Geometria (unidade = altura do deck)

/** Todas as medidas do deck em "u" (altura do deck = 1.0). A largura é [aspect] u. Mesmas constantes de DeckGeo (Swift). */
object DeckGeo {
    const val aspect = 1.45f
    const val platterCx = 0.505f
    const val platterCy = 0.5f
    const val platterD = 0.92f
    const val recordD = 0.855f
    const val labelD = 0.29f
    const val pivotX = 1.30f
    const val pivotY = 0.20f
    const val armL = 0.74f
    const val restAngle = 24.0
    const val rOuter = 0.405f
    const val rInner = 0.195f
    const val marginX = 0.07f
    const val marginTop = 0.035f
    const val marginBottom = 0.13f
    const val thickness = 0.035f

    val restPostX: Float get() { val a = restAngle * Math.PI / 180; return (pivotX - armL * 0.66 * sin(a)).toFloat() }
    val restPostY: Float get() { val a = restAngle * Math.PI / 180; return (pivotY + armL * 0.66 * cos(a)).toFloat() }

    /** Ângulo do braço (graus, horário) para a agulha cair a r u do centro do prato (lei dos cossenos). */
    fun armAngle(forRadius: Float): Double {
        val dx = (pivotX - platterCx).toDouble()
        val dy = (platterCy - pivotY).toDouble()
        val d = hypot(dx, dy)
        val l = armL.toDouble()
        val phi = atan2(dx, dy)
        val c = ((d * d + l * l - forRadius.toDouble() * forRadius) / (2 * d * l)).coerceIn(-1.0, 1.0)
        return (phi - acos(c)) * 180 / Math.PI
    }

    fun angle(forProgress: Double): Double {
        val q = forProgress.coerceIn(0.0, 1.0).toFloat()
        return armAngle(rOuter + (rInner - rOuter) * q)
    }
}

object TapeGeo {
    const val aspect = 1.574f
    const val reelLx = 0.315f; const val reelLy = 0.288f
    const val reelRx = 0.685f; const val reelRy = 0.288f
    const val rEmpty = 0.041f
    const val rFull = 0.084f
    const val hubR = 0.036f
    const val rollerLx = 0.262f; const val rollerLy = 0.592f
    const val rollerRx = 0.738f; const val rollerRy = 0.592f
    // labelRect / windowRect como (x, y, w, h)
    val labelRect = floatArrayOf(0.055f, 0.045f, 0.89f, 0.352f)
    val windowRect = floatArrayOf(0.185f, 0.198f, 0.63f, 0.180f)
    const val shadowMarginX = 0.15f
    const val shadowMarginTop = 0.06f
    const val shadowMarginBottom = 0.18f
}

class CassetteLayers(val back: Bitmap, val front: Bitmap, val shadow: Bitmap)
class ArmImages(val arm: Bitmap, val shadow: Bitmap)

// ============================================================ API estável (com cache; gerar fora da main thread)

object StageTextures {
    private val lruBytes = 56 * 1024 * 1024
    private val lru = object : LruCache<String, Bitmap>(lruBytes) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }
    private val pinned = ConcurrentHashMap<String, Bitmap>()
    private val locks = ConcurrentHashMap<String, Any>()

    private fun get(key: String): Bitmap? = pinned[key] ?: synchronized(lru) { lru.get(key) }

    private inline fun cached(key: String, pin: Boolean = false, make: () -> Bitmap): Bitmap {
        get(key)?.let { return it }
        val lock = locks.getOrPut(key) { Any() }
        synchronized(lock) {
            get(key)?.let { return it }
            val b = make()
            if (pin) pinned[key] = b else synchronized(lru) { lru.put(key, b) }
            return b
        }
    }

    /** Prato + disco (sem o selo/capa), px × px. Bloqueante: chame de Dispatchers.Default. */
    fun record(edition: VinylEdition, px: Int): Bitmap = cached("rec_${edition.ordinal}_$px") { renderRecord(edition, px) }
    fun cachedRecord(edition: VinylEdition, px: Int): Bitmap? = get("rec_${edition.ordinal}_$px")

    /** Reflexo "gravata borboleta" parado (px × px). */
    fun sheen(prism: Boolean, px: Int = 360): Bitmap = cached("sheen_${prism}_$px", pin = true) { renderSheen(prism, px) }

    /** Chassi do deck (inclui margens de sombra/espessura). pxW = largura do deck em px. */
    fun deckBase(finish: TurntableFinish, thick: Boolean, pxW: Int): Bitmap =
        cached("deck_${finish.ordinal}_${thick}_$pxW") { renderDeckBase(finish, thick, pxW) }
    fun cachedDeck(finish: TurntableFinish, thick: Boolean, pxW: Int): Bitmap? = get("deck_${finish.ordinal}_${thick}_$pxW")

    /** Braço + sombra do braço (imagens estáticas; só giram em torno do pivô). */
    fun arm(): ArmImages {
        val a = get("arm_v50"); val s = get("armshadow_v50")
        if (a != null && s != null) return ArmImages(a, s)
        val lock = locks.getOrPut("arm") { Any() }
        synchronized(lock) {
            val a2 = get("arm_v50"); val s2 = get("armshadow_v50")
            if (a2 != null && s2 != null) return ArmImages(a2, s2)
            val (na, ns) = renderArm()
            pinned["arm_v50"] = na; pinned["armshadow_v50"] = ns
            return ArmImages(na, ns)
        }
    }

    /** Camadas da fita K7 (back sob os carretéis, front sobre eles, sombra). wpx = largura do corpo em px. */
    fun cassetteLayers(style: CassetteStyle, sideB: Boolean, wpx: Int): CassetteLayers {
        val kb = "k7b_${style.ordinal}_${sideB}_$wpx"; val kf = "k7f_${style.ordinal}_${sideB}_$wpx"; val ks = "k7s_$wpx"
        val b = get(kb); val f = get(kf); val s = get(ks)
        if (b != null && f != null && s != null) return CassetteLayers(b, f, s)
        val lock = locks.getOrPut(kb) { Any() }
        synchronized(lock) {
            val b2 = get(kb); val f2 = get(kf); val s2 = get(ks)
            if (b2 != null && f2 != null && s2 != null) return CassetteLayers(b2, f2, s2)
            val r = renderCassette(style, sideB, wpx)
            synchronized(lru) { lru.put(kb, r.back); lru.put(kf, r.front); lru.put(ks, r.shadow) }
            return r
        }
    }
    fun cachedCassette(style: CassetteStyle, sideB: Boolean, wpx: Int): CassetteLayers? {
        val b = get("k7b_${style.ordinal}_${sideB}_$wpx"); val f = get("k7f_${style.ordinal}_${sideB}_$wpx"); val s = get("k7s_$wpx")
        return if (b != null && f != null && s != null) CassetteLayers(b, f, s) else null
    }

    /** Carretel (hub) com dentes brancos. */
    fun hub(px: Int = 360): Bitmap = cached("k7hub_v50_$px", pin = true) { renderHub(px) }

    /** Rolo de fita marrom. */
    fun pack(px: Int = 420): Bitmap = cached("k7pack_v50_$px", pin = true) { renderPack(px) }

    /** Mostrador do VU analógico (a agulha é dinâmica). */
    fun vuFace(w: Int, h: Int = (w * 0.62).toInt()): Bitmap = cached("vu_${w}_$h", pin = true) { renderVUFace(w, h) }

    /** Superfície escovada do chassi (0 prata, 1 obsidiana, 2 nogueira, 3 titânio dourado). */
    fun surface(styleId: Int, size: Int = 512): Bitmap = cached("surf_${styleId}_$size", pin = true) { renderBrushedSurface(styleId, size) }
    fun surfaceFor(f: TurntableFinish): Bitmap = surface(shaderIndex(f))

    fun shaderIndex(f: TurntableFinish): Int = when (f) {
        TurntableFinish.SILVER -> 0; TurntableFinish.OBSIDIAN -> 1; TurntableFinish.WALNUT -> 2; TurntableFinish.GOLD -> 3
    }

    private val tiles = ConcurrentHashMap<Long, Bitmap>()
    internal fun noiseTile(seed: Long): Bitmap = tiles.getOrPut(seed) {
        val n = 128
        val rng = TextureRNG(seed)
        val px = IntArray(n * n)
        for (i in 0 until n * n) { val v = (rng.next() * 255).toInt(); px[i] = Color.argb(255, v, v, v) }
        Bitmap.createBitmap(px, n, n, Bitmap.Config.ARGB_8888)
    }

    /** Gera em background o que o jogador provavelmente vai precisar. */
    fun prewarm() {
        Thread {
            runCatching { for (i in 0..3) surface(i) }
            runCatching { arm() }
            runCatching { hub(); pack() }
        }.apply { priority = Thread.MIN_PRIORITY; isDaemon = true }.start()
    }

    // ------------------------------------------------------------ superfícies escovadas

    private fun renderBrushedSurface(styleId: Int, size: Int): Bitmap {
        val w = size; val h = size
        val px = IntArray(w * h)
        val invW = 1.0 / w; val invH = 1.0 / h
        val rowNoise = DoubleArray(h) { y -> val s = sin(y * 1.4 * 12.9898 + 4.1414) * 43758.5453; s - floor(s) }
        val colFine = DoubleArray(w) { x -> val s = sin((x / 3) * 12.9898 + 1.23) * 43758.5453; s - floor(s) }
        for (y in 0 until h) {
            val v = y * invH
            val rn = rowNoise[y]
            val edgeV = min(v, 1.0 - v)
            val woodBase = sin(v * 42.0)
            for (x in 0 until w) {
                val u = x * invW
                val diag = u * 0.65 + v * 0.35
                val d1 = (diag - 0.38) * 4.5
                val d2 = (diag - 0.78) * 6.0
                val sheen = exp(-(d1 * d1)) * 0.15 + exp(-(d2 * d2)) * 0.08
                val fine = abs(colFine[x] - rn * 0.37)
                val grain = rn * 0.78 + fine * 0.22
                val r: Double; val g: Double; val b: Double
                when (styleId) {
                    0 -> { r = 0.86 - 0.16 * v + (grain - 0.5) * 0.052 + sheen; g = 0.88 - 0.15 * v + (grain - 0.5) * 0.052 + sheen; b = 0.91 - 0.14 * v + (grain - 0.5) * 0.052 + sheen }
                    1 -> { r = 0.16 - 0.08 * v + (grain - 0.5) * 0.030 + sheen * 0.45; g = 0.165 - 0.08 * v + (grain - 0.5) * 0.030 + sheen * 0.45; b = 0.19 - 0.09 * v + (grain - 0.5) * 0.030 + sheen * 0.45 }
                    2 -> {
                        val ring = (woodBase * cos(sin(u * 6.5) * 2.2 + u * 3.0)) * 0.5 + 0.5
                        val wf = ring * 0.78 + fine * 0.12
                        r = 0.18 + (0.36 - 0.18) * wf + sheen * 0.30
                        g = 0.10 + (0.20 - 0.10) * wf + sheen * 0.24
                        b = 0.06 + (0.11 - 0.06) * wf + sheen * 0.18
                    }
                    else -> { r = 0.84 - 0.22 * v + (grain - 0.5) * 0.048 + sheen * 1.05; g = 0.74 - 0.23 * v + (grain - 0.5) * 0.048 + sheen * 0.95; b = 0.55 - 0.21 * v + (grain - 0.5) * 0.048 + sheen * 0.75 }
                }
                val edge = min(min(u, 1.0 - u), edgeV)
                val vig = if (edge < 0.05) 0.88 + 0.12 * (edge / 0.05) else 1.0
                px[y * w + x] = Color.argb(255, (r * vig * 255).toInt().coerceIn(0, 255), (g * vig * 255).toInt().coerceIn(0, 255), (b * vig * 255).toInt().coerceIn(0, 255))
            }
        }
        return Bitmap.createBitmap(px, w, h, Bitmap.Config.ARGB_8888)
    }

    // ------------------------------------------------------------ disco de vinil (prato + disco)

    private fun renderRecord(edition: VinylEdition, px: Int): Bitmap {
        val g = Cg(px, px)
        val d = px.toFloat()
        val cx = d / 2; val cy = d / 2
        val pR = d / 2
        val rR = pR * DeckGeo.recordD / DeckGeo.platterD
        val rng = TextureRNG((px + 11).toLong())

        // Prato de alumínio torneado
        g.save()
        g.clipEllipse(cx, cy, pR)
        val n = 120
        for (i in 0 until n) {
            val a0 = i.toFloat() / n * TAUF
            val a1 = (i + 1).toFloat() / n * TAUF + 0.01f
            val t = 0.5f + 0.5f * cosf(2 * (a0 - 0.7f))
            val l = 0.40f + 0.46f * t * t
            g.setFill(gray(l))
            g.fillPoly(cx, cy, cx + pR * 1.02f * cosf(a0), cy + pR * 1.02f * sinf(a0), cx + pR * 1.02f * cosf(a1), cy + pR * 1.02f * sinf(a1))
        }
        var rr = pR
        while (rr > rR) {
            g.setStroke(gray(if (rng.next() > 0.5f) 1f else 0f, rng.range(0.03f, 0.09f)))
            g.lw = 0.7f
            g.strokeEllipse(cx, cy, rr)
            rr -= rng.range(0.9f, 2.2f)
        }
        g.restore()

        // Pontos estroboscópicos (50 Hz / 60 Hz)
        for ((ring, count) in listOf(0.972f to 108, 0.944f to 90)) {
            val rad = pR * ring
            val len = pR * 0.020f
            val wid = (TAUF * rad / count) * 0.46f
            for (k in 0 until count) {
                val a = k.toFloat() / count * TAUF
                g.save()
                g.translate(cx + rad * cosf(a), cy + rad * sinf(a))
                g.rotate(a)
                g.setFill(gray(0.08f, 0.78f))
                g.fillRect(-len / 2, -wid / 2, len, wid)
                g.restore()
            }
        }
        g.setStroke(gray(1f, 0.65f)); g.lw = max(1f, d * 0.0035f)
        g.strokeEllipse(cx, cy, pR - d * 0.002f)
        g.setStroke(gray(0f, 0.55f)); g.lw = max(1f, d * 0.003f)
        g.strokeEllipse(cx, cy, rR + d * 0.004f)

        // Disco: base por edição + sombra de contato
        val light: Boolean
        g.save()
        g.setShadow(0f, d * 0.004f, d * 0.016f, gray(0f, 0.6f))
        when (edition) {
            VinylEdition.CLASSIC_BLACK -> { light = false; g.setFill(rgb(0.052f, 0.052f, 0.058f)); g.fillEllipse(cx, cy, rR) }
            VinylEdition.PRISM_CRYSTAL -> { light = true; g.setFill(gray(0.55f)); g.fillEllipse(cx, cy, rR) }
            VinylEdition.LIMITED_GOLD -> { light = true; g.setFill(rgb(0.72f, 0.52f, 0.18f)); g.fillEllipse(cx, cy, rR) }
            VinylEdition.WHITE_MARBLE -> { light = true; g.setFill(rgb(0.92f, 0.91f, 0.88f)); g.fillEllipse(cx, cy, rR) }
        }
        g.restore()

        g.save()
        g.clipEllipse(cx, cy, rR)
        when (edition) {
            VinylEdition.CLASSIC_BLACK ->
                g.radGrad(cols(gray(0.12f), gray(0.045f), gray(0.07f)), locs(0f, 0.55f, 1f), cx, cy, 0f, cx, cy, rR)
            VinylEdition.PRISM_CRYSTAL -> for (i in 0 until 180) {
                val a0 = i.toFloat() / 180 * TAUF
                val a1 = (i + 1).toFloat() / 180 * TAUF + 0.012f
                val hue = (i.toFloat() / 180 * 2) % 1f
                g.setFill(hsb(hue, 0.42f, 0.86f, 0.86f))
                g.fillPoly(cx, cy, cx + rR * 1.02f * cosf(a0), cy + rR * 1.02f * sinf(a0), cx + rR * 1.02f * cosf(a1), cy + rR * 1.02f * sinf(a1))
            }
            VinylEdition.LIMITED_GOLD ->
                g.radGrad(cols(rgb(0.96f, 0.80f, 0.38f), rgb(0.76f, 0.54f, 0.16f), rgb(0.50f, 0.33f, 0.08f)), locs(0f, 0.6f, 1f),
                    cx - rR * 0.2f, cy - rR * 0.2f, 0f, cx, cy, rR * 1.1f)
            VinylEdition.WHITE_MARBLE -> {
                g.radGrad(cols(gray(0.98f), gray(0.88f)), locs(0f, 1f), cx, cy, 0f, cx, cy, rR)
                for (q in 0 until 16) {
                    val p = Path()
                    var x = cx + rng.range(-rR, rR); var y = cy + rng.range(-rR, rR)
                    p.moveTo(x, y)
                    for (k in 0 until 3) {
                        val nx = x + rng.range(-rR * 0.5f, rR * 0.5f); val ny = y + rng.range(-rR * 0.5f, rR * 0.5f)
                        val qx = (x + nx) / 2 + rng.range(-40f, 40f); val qy = (y + ny) / 2 + rng.range(-40f, 40f)
                        p.quadTo(qx, qy, nx, ny)
                        x = nx; y = ny
                    }
                    g.setStroke(gray(rng.range(0.35f, 0.6f), rng.range(0.10f, 0.26f)))
                    g.lw = rng.range(1.5f, 6f)
                    g.setCap(Paint.Cap.ROUND)
                    g.strokePath(p)
                }
            }
        }

        // Faixas de "dinâmica"
        for (q in 0 until 22) {
            val rad = rng.range(rR * 0.40f, rR * 0.97f)
            g.setStroke(gray(if (light) 0f else 1f, rng.range(0.012f, 0.035f)))
            g.lw = rng.range(3f, 14f)
            g.strokeEllipse(cx, cy, rad)
        }

        // Sulcos finos com vãos entre faixas
        val gaps = floatArrayOf(0.50f, 0.625f, 0.745f, 0.86f)
        val pitch = max(1.15f, d / 640f)
        var r = rR * 0.968f
        while (r > rR * 0.405f) {
            val rn = r / rR
            val inGap = gaps.any { abs(rn - it) < 0.0075f }
            if (inGap) {
                g.setStroke(gray(1f, if (light) 0.20f else 0.045f))
                g.lw = pitch * 1.4f
            } else {
                val a = rng.range(0.035f, 0.11f)
                g.setStroke(gray(if (light) 0f else 1f, if (light) a * 0.9f else a * 0.55f))
                g.lw = pitch * rng.range(0.5f, 0.85f)
            }
            g.strokeEllipse(cx, cy, r)
            r -= pitch * rng.range(0.85f, 1.25f)
        }

        // Zona de saída lisa e assentamento do selo
        g.setFill(gray(if (light) 0.2f else 0f, if (light) 0.16f else 0.5f))
        g.fillEllipse(cx, cy, rR * 0.385f)
        g.setStroke(gray(1f, if (light) 0.5f else 0.16f)); g.lw = max(1f, d * 0.0018f)
        g.strokeEllipse(cx, cy, rR * 0.385f)
        g.setStroke(gray(0f, 0.5f))
        g.strokeEllipse(cx, cy, rR * 0.365f)
        g.restore()

        // Borda chanfrada
        g.setStroke(gray(1f, if (light) 0.55f else 0.22f)); g.lw = max(1f, d * 0.0035f)
        g.strokeEllipse(cx, cy, rR - d * 0.0025f)
        g.setStroke(gray(0f, 0.55f)); g.lw = max(1f, d * 0.002f)
        g.strokeEllipse(cx, cy, rR)
        return g.bmp
    }

    /** Reflexo anisotrópico em gravata borboleta: dois lóbulos opostos que ficam PARADOS enquanto o disco gira. */
    private fun renderSheen(prism: Boolean, n: Int): Bitmap {
        val px = IntArray(n * n)
        val half = n / 2.0
        val a0 = -0.62
        fun adiff(a: Double, b: Double): Double { var d = a - b; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return d }
        val hsv = FloatArray(3)
        for (y in 0 until n) for (x in 0 until n) {
            val dx = x + 0.5 - half; val dy = y + 0.5 - half
            val r = hypot(dx, dy) / half
            if (r <= 0.30 || r >= 1.0) continue
            val th = atan2(dy, dx)
            val w = 0.10 + 0.30 * r
            val d1 = adiff(th, a0) / w
            val d2 = adiff(th, a0 + Math.PI) / (w * 1.1)
            val lobe = exp(-d1 * d1) + 0.78 * exp(-d2 * d2)
            val q1 = adiff(th, a0 + Math.PI / 2) / 0.28
            val q2 = adiff(th, a0 - Math.PI / 2) / 0.28
            val minor = 0.20 * (exp(-q1 * q1) + exp(-q2 * q2))
            val fadeIn = min(1.0, (r - 0.30) / 0.14)
            val fadeOut = min(1.0, (1.0 - r) / 0.03)
            var intensity = (lobe + minor) * fadeIn * fadeOut * (0.45 + 0.55 * r)
            intensity = min(1.0, intensity)
            if (prism) {
                val hue = (th + Math.PI) / (2 * Math.PI)
                hsv[0] = (hue * 360).toFloat(); hsv[1] = 0.55f; hsv[2] = 1f
                val c = Color.HSVToColor(hsv)
                val a = intensity * 0.40
                // não pré-multiplicado: a cor mistura 0.55 + 0.45*canal; o alfa carrega a intensidade
                val rr = (0.55 + 0.45 * Color.red(c) / 255.0) * 255
                val gg = (0.55 + 0.45 * Color.green(c) / 255.0) * 255
                val bb = (0.55 + 0.45 * Color.blue(c) / 255.0) * 255
                px[y * n + x] = Color.argb(min(255.0, a * 255).toInt(), min(255.0, rr).toInt(), min(255.0, gg).toInt(), min(255.0, bb).toInt())
            } else {
                val a = intensity * 0.30
                px[y * n + x] = Color.argb(min(255.0, a * 255).toInt(), 255, 255, 255)
            }
        }
        return Bitmap.createBitmap(px, n, n, Bitmap.Config.ARGB_8888)
    }

    // ------------------------------------------------------------ base do deck (chassi + marcações impressas)

    private fun renderDeckBase(finish: TurntableFinish, thick: Boolean, pxW: Int): Bitmap {
        val w = pxW.toFloat()
        val h = (w / DeckGeo.aspect).roundToInt().toFloat()
        val u = h
        val dark = finish.isDarkChassis
        val corner = u * 0.06f
        val mx = DeckGeo.marginX * u; val mt = DeckGeo.marginTop * u; val mb = DeckGeo.marginBottom * u
        val t = if (thick) DeckGeo.thickness * u else 0f
        val g = Cg((w + 2 * mx).toInt(), (h + mt + mb).toInt())
        g.translate(mx, mt)
        fun rr(l: Float, tp: Float, r: Float, b: Float, c: Float) = roundRectPath(l, tp, r, b, c)
        val shape = rr(0.5f, 0.5f, w - 0.5f, h - 0.5f, corner)
        val shapeT = rr(0.5f, t + 0.5f, w - 0.5f, h + t - 0.5f, corner)

        // Sombra projetada, espessura do chassi e pés isoladores
        g.save()
        g.setShadow(0f, u * (if (thick) 0.05f else 0.03f), u * (if (thick) 0.07f else 0.05f), gray(0f, if (thick) 0.55f else 0.42f))
        g.setFill(gray(0.1f))
        g.fillPath(shapeT)
        g.restore()
        if (thick) {
            g.save()
            g.clipPath(shapeT)
            g.linGrad(if (dark) cols(gray(0.10f), gray(0.02f)) else cols(gray(0.56f), gray(0.26f)), null, 0f, t, 0f, h + t)
            g.linGrad(cols(gray(1f, if (dark) 0.12f else 0.30f), gray(1f, 0f), gray(0f, 0.25f)), locs(0f, 0.5f, 1f), 0f, 0f, w, 0f)
            g.restore()
            for (fx in floatArrayOf(0.10f * u, w - 0.10f * u - 0.12f * u)) {
                val foot = rr(fx, h + t - u * 0.004f, fx + 0.12f * u, h + t - u * 0.004f + u * 0.032f, u * 0.012f)
                g.save()
                g.setShadow(0f, u * 0.012f, u * 0.02f, gray(0f, 0.6f))
                g.setFill(gray(0.3f)); g.fillPath(foot)
                g.restore()
                g.save()
                g.clipPath(foot)
                g.linGrad(cols(gray(0.85f), gray(0.25f), gray(0.55f)), locs(0f, 0.6f, 1f), 0f, h + t, 0f, h + t + u * 0.03f)
                g.restore()
            }
        }

        g.save()
        g.clipPath(shape)
        g.drawBitmapScaled(surface(shaderIndex(finish)), 0f, 0f, w, h)
        g.linGrad(cols(gray(1f, if (dark) 0.10f else 0.28f), gray(1f, 0f), gray(0f, if (dark) 0.30f else 0.20f)), locs(0f, 0.45f, 1f), 0f, 0f, w * 0.3f, h)
        g.tileNoise(0f, 0f, w, h, 0.10f, PorterDuff.Mode.OVERLAY, 5)
        g.restore()

        // Chanfro externo e fio interno
        g.save()
        g.clipPath(shape)
        g.clipStroked(shape, u * 0.010f)
        g.linGrad(cols(gray(1f, if (dark) 0.40f else 0.95f), gray(1f, 0.18f), gray(0f, 0.42f)), locs(0f, 0.5f, 1f), 0f, 0f, w, h)
        g.restore()
        val inner = rr(u * 0.018f, u * 0.018f, w - u * 0.018f, h - u * 0.018f, corner * 0.85f)
        g.save()
        g.clipStroked(inner, max(1f, u * 0.0035f))
        g.linGrad(cols(gray(0f, 0.32f), gray(1f, if (dark) 0.18f else 0.5f)), locs(0f, 1f), 0f, 0f, w, h)
        g.restore()

        // Parafusos nos cantos
        for ((px, py) in listOf(0.04f to 0.05f, DeckGeo.aspect - 0.04f to 0.05f, 0.04f to 0.95f, DeckGeo.aspect - 0.04f to 0.95f)) {
            screw(g, px * u, py * u, u * 0.012f)
        }

        // Poço do prato
        val pcx = DeckGeo.platterCx * u; val pcy = DeckGeo.platterCy * u
        val wellR = u * (DeckGeo.platterD / 2 + 0.018f)
        g.save()
        g.setShadow(0f, 0f, u * 0.02f, gray(0f, 0.55f))
        g.setFill(gray(0.03f)); g.fillEllipse(pcx, pcy, wellR)
        g.restore()
        g.save()
        g.clipEllipse(pcx, pcy, wellR)
        g.linGrad(cols(gray(0f, 0.75f), gray(0f, 0f)), locs(0f, 1f), pcx - wellR, pcy - wellR, pcx + wellR * 0.2f, pcy + wellR * 0.2f)
        g.restore()
        g.setStroke(gray(1f, if (dark) 0.30f else 0.75f)); g.lw = max(1f, u * 0.004f)
        g.strokeEllipse(pcx, pcy, wellR + u * 0.002f)
        g.setStroke(gray(0f, 0.5f))
        g.strokeEllipse(pcx, pcy, wellR - u * 0.004f)

        // Base do pivô do braço
        val pvx = DeckGeo.pivotX * u; val pvy = DeckGeo.pivotY * u
        g.save()
        g.setShadow(u * 0.006f, u * 0.012f, u * 0.02f, gray(0f, 0.5f))
        g.setFill(gray(0.5f)); g.fillEllipse(pvx, pvy, u * 0.085f)
        g.restore()
        g.save()
        g.clipEllipse(pvx, pvy, u * 0.085f)
        g.linGrad(cols(gray(0.98f), gray(0.55f), gray(0.85f), gray(0.32f)), locs(0f, 0.4f, 0.6f, 1f), pvx - u * 0.085f, pvy - u * 0.085f, pvx + u * 0.085f, pvy + u * 0.085f)
        g.restore()
        g.setFill(gray(0.10f)); g.fillEllipse(pvx, pvy, u * 0.058f)
        g.save()
        g.clipEllipse(pvx, pvy, u * 0.058f)
        g.linGrad(cols(gray(0.32f), gray(0.05f)), locs(0f, 1f), pvx - u * 0.04f, pvy - u * 0.04f, pvx + u * 0.05f, pvy + u * 0.05f)
        g.restore()
        // régua do anti-skating
        g.setStroke(gray(1f, 0.5f)); g.lw = max(1f, u * 0.002f)
        for (k in 0 until 13) {
            val a = ((-60 + k * 10) * Math.PI / 180).toFloat()
            val r0 = u * 0.066f; val r1 = u * (if (k % 3 == 0) 0.078f else 0.072f)
            g.move(pvx + r0 * sinf(a), pvy - r0 * cosf(a))
            g.line(pvx + r1 * sinf(a), pvy - r1 * cosf(a))
        }
        g.strokeCur()

        // Apoio do braço
        val rpx = DeckGeo.restPostX * u; val rpy = DeckGeo.restPostY * u
        g.save()
        g.setShadow(u * 0.004f, u * 0.01f, u * 0.012f, gray(0f, 0.55f))
        g.setFill(gray(0.55f)); g.fillEllipse(rpx, rpy, u * 0.026f)
        g.restore()
        g.save()
        g.clipEllipse(rpx, rpy, u * 0.026f)
        g.radGrad(cols(gray(1f), gray(0.55f), gray(0.25f)), locs(0f, 0.55f, 1f), rpx - u * 0.008f, rpy - u * 0.008f, 0f, rpx, rpy, u * 0.03f)
        g.restore()
        g.setFill(gray(0.08f))
        g.fillRound(rpx - u * 0.013f, rpy - u * 0.004f, u * 0.026f, u * 0.012f, u * 0.005f)

        // Lâmpada do estroboscópio
        val lx = 1.17f * u; val ly = 0.80f * u
        g.setFill(gray(0.05f)); g.fillEllipse(lx, ly, u * 0.030f)
        g.save()
        g.clipEllipse(lx, ly, u * 0.028f)
        g.radGrad(cols(gray(0.65f), gray(0.28f), gray(0.12f)), locs(0f, 0.55f, 1f), lx - u * 0.008f, ly - u * 0.008f, 0f, lx, ly, u * 0.03f)
        g.restore()
        g.setStroke(gray(1f, 0.45f)); g.lw = max(1f, u * 0.0025f)
        g.strokeEllipse(lx, ly, u * 0.030f)

        // Marcação impressa
        val ink = if (dark) gray(1f, 0.55f) else gray(0f, 0.55f)
        g.text("LUME  DD-1", 0.034f * u, 800, ink, (DeckGeo.aspect - 0.07f) * u, 0.935f * u, RIGHT, 0.003f * u)
        g.text("DIRECT DRIVE · QUARTZ LOCK", 0.0155f * u, 600, ink, (DeckGeo.aspect - 0.07f) * u, 0.97f * u, RIGHT, 0.002f * u)

        // Canal do pitch
        val slotX = 1.395f * u
        val slot = rr(slotX - u * 0.008f, 0.40f * u, slotX - u * 0.008f + u * 0.016f, 0.40f * u + 0.34f * u, u * 0.008f)
        g.setFill(gray(0f, 0.7f)); g.fillPath(slot)
        g.setStroke(gray(1f, if (dark) 0.25f else 0.7f)); g.lw = 1f
        g.strokePath(slot)
        for (k in -4..4) {
            val y = (0.57f + k * 0.036f) * u
            g.setStroke(ink)
            g.lw = max(1f, u * (if (k == 0) 0.003f else 0.002f))
            g.move(slotX - u * (if (k == 0) 0.042f else 0.03f), y)
            g.line(slotX - u * 0.014f, y)
            g.strokeCur()
        }
        g.text("PITCH", 0.0145f * u, 800, ink, 1.395f * u, 0.775f * u, CENTER, 0.002f * u)
        return g.bmp
    }

    internal fun screw(g: Cg, px: Float, py: Float, r: Float) {
        g.save()
        g.setShadow(0f, r * 0.3f, r * 0.6f, gray(0f, 0.5f))
        g.setFill(gray(0.6f)); g.fillEllipse(px, py, r)
        g.restore()
        g.save()
        g.clipEllipse(px, py, r)
        g.radGrad(cols(gray(0.97f), gray(0.62f), gray(0.3f)), locs(0f, 0.6f, 1f), px - r * 0.3f, py - r * 0.35f, 0f, px, py, r * 1.1f)
        g.restore()
        g.setStroke(gray(0f, 0.55f)); g.lw = max(0.8f, r * 0.18f)
        g.move(px - r * 0.62f, py + r * 0.28f); g.line(px + r * 0.62f, py - r * 0.28f)
        g.strokeCur()
    }

    // ------------------------------------------------------------ braço do toca-discos

    const val armUnit = 800f
    const val armCanvasW = 0.30f
    const val armCanvasH = 1.17f
    const val armPivotX = 0.15f
    const val armPivotY = 0.27f

    private fun renderArm(): Pair<Bitmap, Bitmap> {
        val u = armUnit
        val w = (armCanvasW * u).toInt(); val h = (armCanvasH * u).toInt()
        val l = DeckGeo.armL

        fun draw(g: Cg, sil: Boolean) {
            g.translate(armPivotX * u, armPivotY * u)
            val black = gray(0f)
            fun metalH(x: Float, y: Float, rw: Float, rh: Float, c: IntArray, lc: FloatArray) {
                g.save()
                g.cv.clipRect(x, y, x + rw, y + rh)
                if (sil) { g.setFill(black); g.fillRect(x, y, rw, rh) } else g.linGrad(c, lc, x, 0f, x + rw, 0f)
                g.restore()
            }
            // Contrapeso
            val cwx = -0.056f * u; val cwy = -0.245f * u; val cww = 0.112f * u; val cwh = 0.125f * u
            val cwPath = roundRectPath(cwx, cwy, cwx + cww, cwy + cwh, 0.014f * u)
            g.save()
            g.clipPath(cwPath)
            if (sil) { g.setFill(black); g.fillRect(cwx, cwy, cww, cwh) } else {
                g.linGrad(cols(gray(0.18f), gray(0.62f), gray(0.92f), gray(0.5f), gray(0.16f)), locs(0f, 0.28f, 0.45f, 0.75f, 1f), cwx, 0f, cwx + cww, 0f)
                for (k in 0 until 9) {
                    val y = cwy + k * cwh / 8
                    g.setStroke(gray(0f, 0.32f)); g.lw = 1.4f
                    g.move(cwx, y); g.line(cwx + cww, y); g.strokeCur()
                }
                g.setFill(gray(0.04f))
                g.fillRect(cwx, cwy + cwh - 0.030f * u, cww, 0.030f * u)
                g.setStroke(gray(1f, 0.8f)); g.lw = 1.6f
                for (k in -4..4) {
                    val x = k * 0.011f * u
                    g.move(x, cwy + cwh - 0.027f * u); g.line(x, cwy + cwh - (if (k % 2 == 0) 0.012f else 0.018f) * u)
                }
                g.strokeCur()
            }
            g.restore()
            if (!sil) {
                g.setStroke(gray(1f, 0.35f)); g.lw = 2f
                g.strokePath(cwPath)
            }
            metalH(-0.010f * u, -0.125f * u, 0.020f * u, 0.14f * u, cols(gray(0.3f), gray(0.95f), gray(0.35f)), locs(0f, 0.5f, 1f))

            // Tubo em S
            val endX = 0.040f * u; val endY = (l - 0.168f) * u
            val tube = Path()
            tube.moveTo(0f, 0f)
            tube.cubicTo(0.052f * u, 0.22f * u, -0.034f * u, (l - 0.40f) * u, endX, endY)
            g.save()
            g.clipStroked(tube, 0.0225f * u, round = true)
            if (sil) { g.setFill(black); g.fillRect(-u, -u, 2 * u, 3 * u) } else
                g.linGrad(cols(gray(0.32f), gray(0.72f), gray(1.0f), gray(0.62f), gray(0.28f)), locs(0f, 0.3f, 0.46f, 0.72f, 1f), -0.04f * u, 0f, 0.07f * u, 0f)
            g.restore()

            // Headshell + cartucho
            g.save()
            g.translate(endX, endY)
            g.rotate((12.6 * Math.PI / 180).toFloat())
            val sx = -0.031f * u; val sy = -0.018f * u; val sw = 0.062f * u; val sh = 0.196f * u
            val shell = roundRectPath(sx, sy, sx + sw, sy + sh, 0.010f * u)
            if (sil) { g.setFill(black); g.fillPath(shell) } else {
                g.save(); g.clipPath(shell)
                g.linGrad(cols(gray(0.07f), gray(0.26f), gray(0.07f)), locs(0f, 0.45f, 1f), sx, 0f, sx + sw, 0f)
                g.restore()
                g.setStroke(gray(1f, 0.35f)); g.lw = 1.6f
                g.strokePath(shell)
                g.setFill(gray(0f, 0.8f))
                for (yy in floatArrayOf(0.010f, 0.030f)) g.fillEllipse(0f, yy * u, 0.0055f * u)
                val cx0 = -0.026f * u; val cy0 = 0.070f * u; val cw0 = 0.052f * u; val ch0 = 0.085f * u
                val cart = roundRectPath(cx0, cy0, cx0 + cw0, cy0 + ch0, 0.006f * u)
                g.save(); g.clipPath(cart)
                g.linGrad(cols(rgb(1f, 0.48f, 0.62f), rgb(0.62f, 0.24f, 0.45f)), locs(0f, 1f), 0f, cy0, 0f, cy0 + ch0)
                g.restore()
                g.setStroke(gray(0f, 0.4f)); g.lw = 1.4f
                g.strokePath(cart)
                g.setStroke(gray(0.05f)); g.lw = 0.004f * u; g.setCap(Paint.Cap.ROUND)
                g.move(0f, 0.150f * u); g.line(0f, 0.1745f * u); g.strokeCur()
                g.setFill(rgb(1f, 0.2f, 0.25f))
                g.fillEllipse(0f, 0.1745f * u, 0.0042f * u)
            }
            // alavanca de levantar
            g.setStroke(if (sil) black else gray(0.86f)); g.lw = 0.0075f * u; g.setCap(Paint.Cap.ROUND)
            val lift = Path(); lift.moveTo(0.030f * u, 0.040f * u); lift.quadTo(0.052f * u, 0.050f * u, 0.068f * u, 0.020f * u)
            g.strokePath(lift)
            g.restore()

            // Tampa do pivô
            val capR = 0.034f * u
            if (sil) { g.setFill(black); g.fillEllipse(0f, 0f, capR) } else {
                g.save(); g.clipEllipse(0f, 0f, capR)
                g.radGrad(cols(gray(1f), gray(0.65f), gray(0.28f)), locs(0f, 0.55f, 1f), -capR * 0.35f, -capR * 0.4f, 0f, 0f, 0f, capR * 1.2f)
                g.restore()
                g.setStroke(gray(0f, 0.4f)); g.lw = 2f
                g.strokeEllipse(0f, 0f, capR)
                g.setFill(gray(0.12f))
                g.fillEllipse(0f, 0f, capR * 0.32f)
            }
        }

        val gArm = Cg(w, h)
        draw(gArm, false)
        // Sombra: silhueta com alfa borrado (equivale à sombra deslocada de volta do CG, sem CoreImage)
        val gSil = Cg(w, h)
        draw(gSil, true)
        val rad = Cg.shadowRadius(0.016f * u)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { maskFilter = BlurMaskFilter(rad, BlurMaskFilter.Blur.NORMAL) }
        val off = IntArray(2)
        val alpha = gSil.bmp.extractAlpha(paint, off)
        val shadow = Cg(w, h)
        val black = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK }
        shadow.cv.drawBitmap(alpha, off[0].toFloat(), off[1].toFloat(), black)
        gSil.bmp.recycle(); alpha.recycle()
        return gArm.bmp to shadow.bmp
    }

    // ------------------------------------------------------------ fita K7

    private class TapePalette(
        val bodyTop: Int, val bodyBottom: Int, val overlayAlpha: Float, val bed: Int, val paper: Int, val stripe: Int, val dark: Boolean, val brand: String,
    )

    private fun palette(style: CassetteStyle): TapePalette = when (style) {
        CassetteStyle.SMOKED_STUDIO -> TapePalette(rgb(0.30f, 0.31f, 0.35f), rgb(0.10f, 0.10f, 0.12f), 0.80f, gray(0.03f), rgb(0.95f, 0.93f, 0.85f), rgb(0.88f, 0.28f, 0.20f), true, "LUME  ·  HIGH BIAS")
        CassetteStyle.CRYSTAL_CLEAR -> TapePalette(rgb(0.80f, 0.88f, 0.93f), rgb(0.55f, 0.66f, 0.74f), 0.30f, rgb(0.30f, 0.40f, 0.48f), rgb(0.98f, 0.98f, 0.95f), rgb(0.08f, 0.56f, 0.64f), false, "LUME  ·  CRYSTAL")
        CassetteStyle.METALLIC_CHROME -> TapePalette(gray(0.88f), gray(0.46f), 1f, gray(0.05f), rgb(0.96f, 0.95f, 0.93f), rgb(0.12f, 0.15f, 0.24f), false, "LUME  ·  CHROME TYPE II")
        CassetteStyle.VINTAGE_CREAM -> TapePalette(rgb(0.95f, 0.91f, 0.80f), rgb(0.80f, 0.74f, 0.61f), 1f, gray(0.07f), rgb(0.98f, 0.96f, 0.89f), rgb(0.64f, 0.24f, 0.14f), false, "LUME  ·  NORMAL BIAS")
    }

    private fun renderCassette(style: CassetteStyle, sideB: Boolean, wpx: Int): CassetteLayers {
        val pal = palette(style)
        val w = wpx.toFloat()
        val h = (w / TapeGeo.aspect).roundToInt().toFloat()
        val hC = h / w
        val corner = 0.034f * w
        fun px(x: Float) = x * w
        val bodyPath = roundRectPath(0.5f, 0.5f, w - 0.5f, h - 0.5f, corner)
        val lr = TapeGeo.labelRect; val wr = TapeGeo.windowRect
        val lx = lr[0] * w; val ly = lr[1] * w; val lw = lr[2] * w; val lh = lr[3] * w
        val wx = wr[0] * w; val wy = wr[1] * w; val ww = wr[2] * w; val wh = wr[3] * w
        val winPath = roundRectPath(wx, wy, wx + ww, wy + wh, 0.06f * w)
        val labelPath = roundRectPath(lx, ly, lx + lw, ly + lh, 0.014f * w)

        fun rp(x: Float, y: Float, rw: Float, rh: Float, c: Float) = roundRectPath(x * w, y * w, (x + rw) * w, (y + rh) * w, c)
        val holes = listOf(
            rp(0.452f, 0.572f, 0.096f, hC - 0.572f + 0.02f, 0.006f * w),
            rp(0.250f, 0.566f, 0.082f, hC - 0.566f + 0.02f, 0.012f * w),
            rp(0.668f, 0.566f, 0.082f, hC - 0.566f + 0.02f, 0.012f * w),
            Cg.ovalPath(0.118f * w - 0.0105f * w, 0.6035f * w - 0.0105f * w, 0.118f * w + 0.0105f * w, 0.6035f * w + 0.0105f * w),
            Cg.ovalPath(0.882f * w - 0.0105f * w, 0.6035f * w - 0.0105f * w, 0.882f * w + 0.0105f * w, 0.6035f * w + 0.0105f * w),
        )

        // Sombra (independente de estilo)
        val mX = TapeGeo.shadowMarginX * w; val mT = TapeGeo.shadowMarginTop * w; val mB = TapeGeo.shadowMarginBottom * w
        val gs = Cg((w + 2 * mX).toInt(), (h + mT + mB).toInt())
        gs.setShadow(0f, 0.035f * w, 0.05f * w, gray(0f, 0.62f))
        gs.setFill(Color.BLACK)
        gs.fillPath(roundRectPath(mX, mT, mX + w, mT + h, corner))
        gs.noShadow()
        gs.clearPath(roundRectPath(mX + 1, mT + 1, mX + w - 1, mT + h - 1, corner))

        // Camada de trás
        val gb = Cg(wpx, h.toInt())
        gb.save()
        gb.clipPath(bodyPath)
        gb.lin(pal.bodyTop, pal.bodyBottom, 0f, 0f, 0f, h)
        val bedPath = roundRectPath(wx - 0.012f * w, wy - 0.012f * w, wx + ww + 0.012f * w, wy + wh + 0.012f * w, 0.07f * w)
        gb.setFill(pal.bed); gb.fillPath(bedPath)
        for ((rx, ry) in listOf(TapeGeo.reelLx to TapeGeo.reelLy, TapeGeo.reelRx to TapeGeo.reelRy)) {
            val cx = rx * w; val cy = ry * w
            gb.save()
            gb.clipEllipse(cx, cy, 0.092f * w)
            gb.radGrad(cols(gray(if (pal.dark) 0.16f else 0.34f), gray(if (pal.dark) 0.02f else 0.10f)), locs(0f, 1f), cx, cy, 0.02f * w, cx, cy, 0.092f * w)
            gb.restore()
            gb.setStroke(gray(1f, 0.14f)); gb.lw = max(1f, 0.0025f * w)
            gb.strokeEllipse(cx, cy, 0.090f * w)
            gb.setStroke(gray(1f, 0.10f))
            for (k in 0 until 24) {
                val a = k.toFloat() / 24 * TAUF
                gb.move(cx + 0.047f * w * cosf(a), cy + 0.047f * w * sinf(a))
                gb.line(cx + 0.055f * w * cosf(a), cy + 0.055f * w * sinf(a))
            }
            gb.strokeCur()
        }
        for ((rx, ry) in listOf(TapeGeo.rollerLx to TapeGeo.rollerLy, TapeGeo.rollerRx to TapeGeo.rollerRy)) {
            val cx = rx * w; val cy = ry * w
            gb.save()
            gb.setShadow(0f, 0.004f * w, 0.008f * w, gray(0f, 0.6f))
            gb.setFill(gray(0.7f)); gb.fillEllipse(cx, cy, 0.0165f * w)
            gb.restore()
            gb.save()
            gb.clipEllipse(cx, cy, 0.0165f * w)
            gb.radGrad(cols(gray(1f), gray(0.7f), gray(0.35f)), locs(0f, 0.5f, 1f), cx - 0.005f * w, cy - 0.005f * w, 0f, cx, cy, 0.02f * w)
            gb.restore()
            gb.setFill(gray(0.1f)); gb.fillEllipse(cx, cy, 0.005f * w)
        }
        gb.setFill(gray(0.62f)); gb.fillRect(0.42f * w, 0.572f * w, 0.16f * w, 0.026f * w)
        gb.setFill(gray(1f, 0.35f)); gb.fillRect(0.42f * w, 0.572f * w, 0.16f * w, 0.004f * w)
        gb.setStroke(rgb(0.30f, 0.18f, 0.10f)); gb.lw = 0.0055f * w
        gb.move(TapeGeo.rollerLx * w, 0.6105f * w); gb.line(TapeGeo.rollerRx * w, 0.6105f * w); gb.strokeCur()
        gb.setStroke(gray(1f, 0.22f)); gb.lw = 0.0014f * w
        gb.move(TapeGeo.rollerLx * w, 0.6085f * w); gb.line(TapeGeo.rollerRx * w, 0.6085f * w); gb.strokeCur()
        gb.restore()

        // Camada da frente
        val gf = Cg(wpx, h.toInt())
        gf.save()
        gf.clipEvenOdd(bodyPath, labelPath)
        val top = withAlpha(pal.bodyTop, pal.overlayAlpha); val bot = withAlpha(pal.bodyBottom, pal.overlayAlpha)
        gf.lin(top, bot, 0f, 0f, 0f, h)
        gf.linGrad(cols(gray(1f, 0f), gray(1f, if (pal.dark) 0.10f else 0.30f), gray(1f, 0f)), locs(0f, 0.5f, 1f), 0f, 0f, 0.055f * w, 0f)
        gf.linGrad(cols(gray(1f, 0f), gray(1f, if (pal.dark) 0.06f else 0.20f), gray(1f, 0f)), locs(0f, 0.5f, 1f), 0.945f * w, 0f, w, 0f)
        val trap = Path()
        trap.moveTo(0.215f * w, 0.452f * w); trap.lineTo(0.785f * w, 0.452f * w)
        trap.lineTo(0.895f * w, (hC - 0.004f) * w); trap.lineTo(0.105f * w, (hC - 0.004f) * w); trap.close()
        gf.setFill(gray(0f, if (pal.dark) 0.34f else 0.20f)); gf.fillPath(trap)
        gf.setStroke(gray(1f, if (pal.dark) 0.20f else 0.55f)); gf.lw = max(1f, 0.0028f * w)
        gf.move(0.215f * w, 0.452f * w); gf.line(0.785f * w, 0.452f * w); gf.strokeCur()
        gf.setStroke(gray(0f, 0.40f))
        gf.move(0.215f * w, 0.4565f * w); gf.line(0.105f * w, (hC - 0.004f) * w)
        gf.move(0.785f * w, 0.4565f * w); gf.line(0.895f * w, (hC - 0.004f) * w); gf.strokeCur()
        gf.restore()

        // aberturas (vazadas)
        gf.save()
        for (hp in holes) gf.clearPath(hp)
        gf.restore()
        for (hp in holes) { gf.setStroke(gray(0f, 0.6f)); gf.lw = max(1f, 0.0025f * w); gf.strokePath(hp) }

        // etiqueta de papel com janela vazada
        gf.save()
        gf.setShadow(0f, 0.003f * w, 0.006f * w, gray(0f, 0.5f))
        gf.setFill(pal.paper)
        val labelWin = Path().apply { addPath(labelPath); addPath(winPath) }
        gf.fillPath(labelWin, evenOdd = true)
        gf.restore()

        gf.save()
        gf.clipEvenOdd(labelPath, winPath)
        gf.lin(gray(1f, 0.35f), gray(0f, 0.06f), 0f, ly, 0f, ly + lh)
        gf.tileNoise(lx, ly, lx + lw, ly + lh, 0.16f, PorterDuff.Mode.MULTIPLY, 9)
        // faixa colorida superior
        gf.setFill(pal.stripe); gf.fillRect(lx, ly, lw, 0.052f * w)
        gf.setFill(gray(1f, 0.16f)); gf.fillRect(lx, ly, lw, 0.0035f * w)
        // linhas pautadas
        gf.setStroke(rgb(0.42f, 0.52f, 0.70f, 0.55f)); gf.lw = max(0.8f, 0.0018f * w)
        for (y in floatArrayOf(0.152f, 0.190f)) { gf.move(0.085f * w, y * w); gf.line(0.775f * w, y * w) }
        gf.strokeCur()
        gf.restore()

        // moldura do espaço da capa
        gf.save()
        gf.setShadow(0f, 0.002f * w, 0.004f * w, gray(0f, 0.5f))
        gf.setFill(gray(0.99f))
        gf.fillRect(0.826f * w, 0.100f * w, 0.094f * w, 0.094f * w)
        gf.restore()

        // textos impressos
        val letter = if (sideB) "B" else "A"
        gf.setFill(gray(1f, 0.95f)); gf.fillEllipse(0.092f * w, 0.071f * w, 0.0205f * w)
        gf.text(letter, 0.030f * w, 900, pal.stripe, 0.092f * w, 0.0715f * w, CENTER)
        gf.text(pal.brand, 0.0175f * w, 800, gray(1f, 0.95f), 0.5f * w, 0.071f * w, CENTER, 0.002f * w)
        gf.text("C-60", 0.027f * w, 900, gray(1f, 0.95f), 0.925f * w, 0.071f * w, RIGHT, 0.001f * w)
        fun ink(a: Float) = gray(0.12f, 0.78f * a)
        gf.text(if (sideB) "LADO B" else "LADO A", 0.0125f * w, 800, ink(0.6f), 0.085f * w, 0.108f * w, LEFT, 0.003f * w)
        gf.text(letter, 0.098f * w, 900, withAlpha(pal.stripe, 0.9f), 0.120f * w, 0.288f * w, CENTER)
        gf.text("60", 0.066f * w, 900, ink(0.7f), 0.880f * w, 0.266f * w, CENTER)
        gf.text("MIN", 0.0155f * w, 800, ink(0.6f), 0.880f * w, 0.320f * w, CENTER, 0.002f * w)
        gf.text("NR  ·  TYPE I  ·  120 µs", 0.0128f * w, 600, ink(0.55f), 0.5f * w, 0.3875f * w, CENTER, 0.002f * w)

        // janela: chanfro + vidro com reflexo
        gf.setStroke(gray(0f, 0.75f)); gf.lw = max(1.2f, 0.005f * w)
        gf.strokePath(winPath)
        gf.save()
        gf.clipStroked(roundRectPath(wx + 0.002f * w, wy + 0.002f * w, wx + ww - 0.002f * w, wy + wh - 0.002f * w, 0.058f * w), max(1f, 0.0022f * w))
        gf.linGrad(cols(gray(1f, 0.65f), gray(1f, 0.05f), gray(0f, 0.35f)), locs(0f, 0.5f, 1f), 0f, wy, 0f, wy + wh)
        gf.restore()
        gf.save()
        gf.clipPath(winPath)
        val glare = Path()
        glare.moveTo(wx + ww * 0.10f, wy); glare.lineTo(wx + ww * 0.34f, wy); glare.lineTo(wx + ww * 0.18f, wy + wh); glare.lineTo(wx - ww * 0.06f, wy + wh); glare.close()
        gf.clipPath(glare)
        gf.linGrad(cols(gray(1f, 0f), gray(1f, 0.20f), gray(1f, 0f)), locs(0f, 0.5f, 1f), wx, 0f, wx + ww * 0.34f, 0f)
        gf.restore()
        gf.save()
        gf.clipPath(winPath)
        gf.lin(gray(1f, 0.14f), gray(1f, 0f), 0f, wy, 0f, wy + wh * 0.4f)
        gf.restore()

        // marcas de guia na borda da janela
        gf.setStroke(gray(0f, 0.4f)); gf.lw = max(0.8f, 0.0016f * w)
        for (k in 0 until 7) {
            val x = (0.43f + k * 0.023f) * w
            gf.move(x, wy + wh - 0.0075f * w); gf.line(x, wy + wh - 0.0015f * w)
        }
        gf.strokeCur()

        // parafusos
        for ((sx, sy) in listOf(0.040f to 0.040f, 0.960f to 0.040f, 0.040f to hC - 0.040f, 0.960f to hC - 0.040f, 0.5f to 0.0215f)) screw(gf, sx * w, sy * w, 0.0125f * w)
        screw(gf, 0.5f * w, 0.4765f * w, 0.0125f * w)

        // contorno chanfrado, brilho e grão de plástico
        gf.save()
        gf.clipPath(bodyPath)
        gf.linGrad(cols(gray(1f, if (pal.dark) 0.16f else 0.34f), gray(1f, 0f)), locs(0f, 1f), 0f, 0f, w * 0.5f, h * 0.9f)
        gf.restore()
        gf.save()
        gf.clipStroked(bodyPath, max(1.2f, 0.007f * w))
        gf.linGrad(cols(gray(1f, if (pal.dark) 0.55f else 0.95f), gray(1f, 0.12f), gray(0f, 0.45f)), locs(0f, 0.5f, 1f), 0f, 0f, w, h)
        gf.restore()
        gf.save()
        gf.clipStroked(roundRectPath(0.008f * w, 0.008f * w, w - 0.008f * w, h - 0.008f * w, corner * 0.8f), max(0.8f, 0.0018f * w))
        gf.linGrad(cols(gray(0f, 0.28f), gray(1f, 0.25f)), locs(0f, 1f), 0f, 0f, w, h)
        gf.restore()
        gf.save()
        gf.clipEvenOdd(bodyPath, labelPath)
        gf.tileNoise(0f, 0f, w, h, if (pal.dark) 0.16f else 0.10f, PorterDuff.Mode.OVERLAY, 21)
        gf.restore()
        return CassetteLayers(gb.bmp, gf.bmp, gs.bmp)
    }

    // ------------------------------------------------------------ carretel, rolo, VU

    private fun renderHub(px: Int): Bitmap {
        val g = Cg(px, px)
        val d = px.toFloat()
        val cx = d / 2; val cy = d / 2
        val r = d / 2 - 1
        g.save()
        g.setShadow(0f, 0f, d * 0.03f, gray(0f, 0.5f))
        g.setFill(gray(0.9f)); g.fillEllipse(cx, cy, r)
        g.restore()
        g.save()
        g.clipEllipse(cx, cy, r)
        g.radGrad(cols(gray(1f), gray(0.86f), gray(0.62f)), locs(0f, 0.6f, 1f), cx - r * 0.3f, cy - r * 0.3f, 0f, cx, cy, r * 1.1f)
        g.restore()
        val holeR = r * 0.60f
        g.setFill(gray(0.04f)); g.fillEllipse(cx, cy, holeR)
        g.save()
        g.clipEllipse(cx, cy, holeR)
        g.radGrad(cols(gray(0.02f), gray(0.16f)), locs(0f, 1f), cx, cy, 0f, cx, cy, holeR)
        g.restore()
        for (k in 0 until 6) {
            g.save()
            g.translate(cx, cy)
            g.rotate(k * PIF / 3)
            val tooth = roundRectPath(-r * 0.085f, -holeR - r * 0.02f, -r * 0.085f + r * 0.17f, -holeR - r * 0.02f + r * 0.30f, r * 0.03f)
            g.setFill(gray(0.95f)); g.fillPath(tooth)
            g.setStroke(gray(0f, 0.35f)); g.lw = max(1f, r * 0.018f)
            g.strokePath(tooth)
            g.restore()
        }
        g.setStroke(gray(0f, 0.4f)); g.lw = max(1f, r * 0.03f)
        g.strokeEllipse(cx, cy, r)
        g.setStroke(gray(1f, 0.8f)); g.lw = max(1f, r * 0.02f)
        g.strokeEllipse(cx, cy, r * 0.9f)
        return g.bmp
    }

    private fun renderPack(px: Int): Bitmap {
        val g = Cg(px, px)
        val d = px.toFloat()
        val cx = d / 2; val cy = d / 2
        val r0 = d / 2 - 1
        val rng = TextureRNG(77)
        g.save()
        g.clipEllipse(cx, cy, r0)
        g.radGrad(cols(rgb(0.20f, 0.12f, 0.07f), rgb(0.30f, 0.18f, 0.10f), rgb(0.24f, 0.14f, 0.08f)), locs(0f, 0.7f, 1f), cx, cy, 0f, cx, cy, r0)
        var r = r0
        while (r > r0 * 0.2f) {
            g.setStroke(gray(if (rng.next() > 0.5f) 1f else 0f, rng.range(0.03f, 0.10f)))
            g.lw = max(0.6f, d * 0.0022f)
            g.strokeEllipse(cx, cy, r)
            r -= rng.range(d * 0.004f, d * 0.011f)
        }
        for (ang in floatArrayOf(0.9f, 0.9f + PIF)) {
            g.save()
            g.translate(cx, cy); g.rotate(ang)
            g.linGrad(cols(gray(1f, 0f), gray(1f, 0.13f), gray(1f, 0f)), locs(0f, 0.5f, 1f), 0f, -r0 * 0.35f, 0f, r0 * 0.35f)
            g.restore()
        }
        g.restore()
        g.setStroke(rgb(0.42f, 0.27f, 0.16f, 0.9f)); g.lw = max(1f, d * 0.008f)
        g.strokeEllipse(cx, cy, r0 * 0.992f)
        return g.bmp
    }

    private fun renderVUFace(w: Int, h: Int): Bitmap {
        val g = Cg(w, h)
        val ww = w.toFloat(); val hh = h.toFloat()
        val path = roundRectPath(0.5f, 0.5f, ww - 0.5f, hh - 0.5f, hh * 0.16f)
        g.save()
        g.clipPath(path)
        g.lin(rgb(1.0f, 0.94f, 0.80f), rgb(0.97f, 0.80f, 0.54f), 0f, 0f, 0f, hh)
        g.radGrad(cols(gray(1f, 0.55f), gray(1f, 0f)), locs(0f, 1f), ww / 2, hh * 1.05f, 0f, ww / 2, hh * 1.05f, ww * 0.7f)
        val pvx = ww / 2; val pvy = hh * 1.0f
        val radius = hh * 0.82f
        val red = rgb(0.85f, 0.1f, 0.08f)
        for (k in 0..10) {
            val f = k / 10f
            val ang = ((-50 + 100 * f) * Math.PI / 180).toFloat()
            val inner = radius * (if (k % 2 == 0) 0.82f else 0.89f)
            g.setStroke(if (f > 0.72f) red else gray(0f, 0.75f))
            g.lw = max(1f, hh * (if (k % 2 == 0) 0.028f else 0.016f))
            g.move(pvx + inner * sinf(ang), pvy - inner * cosf(ang))
            g.line(pvx + radius * sinf(ang), pvy - radius * cosf(ang))
            g.strokeCur()
        }
        fun arcPath(r: Float, d0: Float, d1: Float) {
            for (k in 0..24) {
                val d = ((d0 + (d1 - d0) * k / 24) * Math.PI / 180).toFloat()
                val x = pvx + r * sinf(d); val y = pvy - r * cosf(d)
                if (k == 0) g.move(x, y) else g.line(x, y)
            }
        }
        g.setStroke(gray(0f, 0.6f)); g.lw = max(1f, hh * 0.016f)
        arcPath(radius, -50f, 50f); g.strokeCur()
        g.setStroke(red); g.lw = max(2f, hh * 0.05f)
        arcPath(radius * 0.97f, 22f, 50f); g.strokeCur()
        g.textTop("VU", hh * 0.26f, 800, gray(0f, 0.65f), ww / 2, hh * 0.40f, true)
        g.restore()
        g.setStroke(gray(0f, 0.55f)); g.lw = max(1f, hh * 0.03f)
        g.strokePath(path)
        g.save()
        g.clipPath(path)
        g.linGrad(cols(gray(1f, 0.35f), gray(1f, 0f), gray(1f, 0f)), locs(0f, 0.5f, 1f), 0f, 0f, 0f, hh)
        g.restore()
        return g.bmp
    }
}
