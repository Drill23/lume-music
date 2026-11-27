package com.adriano.lumemusic.audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Processador de áudio no pipeline do ExoPlayer (não precisa de permissão de microfone):
 *  1. Equalizador de 5 bandas (biquads — 60 Hz / 230 Hz / 910 Hz / 3,6 kHz / 14 kHz), igual ao do iOS.
 *  2. Análise FFT real (1024 pts, janela Hann) → 24 bandas log (40 Hz–16 kHz) + nível RMS.
 * O áudio segue adiante (com EQ aplicado); a análise é publicada com timestamp para o AudioSpectrum.
 */
class LumeAudioProcessor : BaseAudioProcessor() {
    companion object {
        const val BANDS = 24
        private const val FFT = 1024
        private const val LOG2N = 10
        private const val RING = 8192
        private const val HOP = 512
        private val EQ_FREQS = doubleArrayOf(60.0, 230.0, 910.0, 3600.0, 14000.0)
    }

    // ---- estado de formato ----
    private var channels = 2
    private var sampleRate = 44100
    private var encoding = C.ENCODING_PCM_16BIT

    // ---- EQ ----
    private val eqLock = Any()
    private val eqGains = FloatArray(5)
    private val coeffs = DoubleArray(25)          // b0,b1,b2,a1,a2 normalizados por banda
    @Volatile private var eqBypass = true
    private var z1 = Array(8) { DoubleArray(5) }  // por canal, por banda (DF2 transposta)
    private var z2 = Array(8) { DoubleArray(5) }

    // ---- análise ----
    private val ring = FloatArray(RING)
    private var writeCount = 0L
    private var sinceLast = 0
    private val frame = FloatArray(FFT)
    private val re = FloatArray(FFT)
    private val im = FloatArray(FFT)
    private val window = FloatArray(FFT) { (0.5 * (1 - cos(2 * PI * it / FFT))).toFloat() }
    private val cosT = FloatArray(FFT / 2) { cos(2 * PI * it / FFT).toFloat() }
    private val sinT = FloatArray(FFT / 2) { (-sin(2 * PI * it / FFT)).toFloat() }
    private val bitrev = IntArray(FFT).also { arr ->
        for (i in 0 until FFT) { var x = i; var r = 0; for (b in 0 until LOG2N) { r = (r shl 1) or (x and 1); x = x shr 1 }; arr[i] = r }
    }
    private val db = FloatArray(FFT / 2 + 1)
    private val bandLo = IntArray(BANDS) { 1 }
    private val bandHi = IntArray(BANDS) { 1 }
    private val bandPos = FloatArray(BANDS)
    private val localBands = FloatArray(BANDS)

    private val pubLock = Any()
    private val pubBands = FloatArray(BANDS)
    private var pubLevel = 0f
    private var pubTimeNs = 0L
    private var pubHasData = false
    @Volatile private var analysisActive = false

    class Snapshot(val level: Float, val timeNs: Long, val hasData: Boolean)

    fun setEQGains(gains: List<Float>) {
        synchronized(eqLock) {
            for (i in 0 until 5) eqGains[i] = gains.getOrElse(i) { 0f }
            recomputeCoeffsLocked()
        }
    }

    fun setAnalysisActive(active: Boolean) { analysisActive = active }

    fun snapshot(out: FloatArray): Snapshot {
        synchronized(pubLock) {
            if (pubHasData) System.arraycopy(pubBands, 0, out, 0, BANDS)
            return Snapshot(pubLevel, pubTimeNs, pubHasData)
        }
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT && inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT) {
            return AudioProcessor.AudioFormat.NOT_SET // inativo: o áudio passa direto
        }
        channels = min(inputAudioFormat.channelCount, 8)
        sampleRate = inputAudioFormat.sampleRate
        encoding = inputAudioFormat.encoding
        synchronized(eqLock) { recomputeCoeffsLocked() }
        computeBands()
        for (c in 0 until 8) { z1[c].fill(0.0); z2[c].fill(0.0) }
        writeCount = 0; sinceLast = 0
        return inputAudioFormat
    }

    override fun onFlush() {
        for (c in 0 until 8) { z1[c].fill(0.0); z2[c].fill(0.0) }
        sinceLast = 0
    }

    override fun onReset() {
        synchronized(pubLock) { pubHasData = false; pubLevel = 0f; pubBands.fill(0f) }
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val size = inputBuffer.remaining()
        if (size == 0) return
        val out = replaceOutputBuffer(size)
        val is16 = encoding == C.ENCODING_PCM_16BIT
        val bytesPerSample = if (is16) 2 else 4
        val ch = channels
        val frameBytes = bytesPerSample * ch
        val frames = size / frameBytes
        val doEq = !eqBypass
        val doAnalysis = analysisActive
        val order = java.nio.ByteOrder.nativeOrder()
        inputBuffer.order(order)
        out.order(order)
        val base = inputBuffer.position()
        val mono = if (doAnalysis) FloatArray(frames) else null

        for (f in 0 until frames) {
            var sum = 0f
            for (c in 0 until ch) {
                val idx = base + f * frameBytes + c * bytesPerSample
                var x = if (is16) inputBuffer.getShort(idx) / 32768.0 else inputBuffer.getFloat(idx).toDouble()
                if (doEq) {
                    for (b in 0 until 5) {
                        val o = b * 5
                        val b0 = coeffs[o]; val b1 = coeffs[o + 1]; val b2 = coeffs[o + 2]; val a1 = coeffs[o + 3]; val a2 = coeffs[o + 4]
                        val y = b0 * x + z1[c][b]
                        z1[c][b] = b1 * x - a1 * y + z2[c][b]
                        z2[c][b] = b2 * x - a2 * y
                        x = y
                    }
                }
                if (is16) {
                    val v = (x * 32768.0).toInt().coerceIn(-32768, 32767)
                    out.putShort(v.toShort())
                } else {
                    out.putFloat(max(-1.0, min(1.0, x)).toFloat())
                }
                sum += x.toFloat()
            }
            if (mono != null) mono[f] = sum / ch
        }
        // sobra (frames incompletos): copia crua
        val used = frames * frameBytes
        if (used < size) { inputBuffer.position(base + used); out.put(inputBuffer) }
        inputBuffer.position(base + size)
        out.flip()
        if (mono != null) feed(mono)
    }

    // ---------------- análise ----------------

    private fun feed(mono: FloatArray) {
        val mask = RING - 1
        for (s in mono) {
            ring[(writeCount and mask.toLong()).toInt()] = s
            writeCount++
            sinceLast++
            if (sinceLast >= HOP && writeCount >= FFT) { sinceLast = 0; analyze() }
        }
    }

    private fun analyze() {
        val mask = RING - 1
        val start = ((writeCount - FFT) and mask.toLong()).toInt()
        for (i in 0 until FFT) frame[i] = ring[(start + i) and mask]

        var acc = 0.0
        for (i in 0 until FFT) acc += frame[i] * frame[i].toDouble()
        val rms = sqrt(acc / FFT).toFloat()
        val rmsDb = 20f * log10(max(rms, 1e-7f))
        val level = ((rmsDb + 50f) / 41f).coerceIn(0f, 1f)

        for (i in 0 until FFT) { re[bitrev[i]] = frame[i] * window[i]; im[bitrev[i]] = 0f }
        var len = 2
        while (len <= FFT) {
            val half = len / 2
            val step = FFT / len
            var i = 0
            while (i < FFT) {
                var k = 0
                for (j in i until i + half) {
                    val wr = cosT[k]; val wi = sinT[k]
                    val tr = re[j + half] * wr - im[j + half] * wi
                    val ti = re[j + half] * wi + im[j + half] * wr
                    re[j + half] = re[j] - tr; im[j + half] = im[j] - ti
                    re[j] += tr; im[j] += ti
                    k += step
                }
                i += len
            }
            len *= 2
        }
        val half = FFT / 2
        re[0] = 0f; im[0] = 0f
        val scale = 16f / (FFT.toFloat() * FFT)
        for (k in 0 until half) {
            val p = (re[k] * re[k] + im[k] * im[k]) * scale + 1e-12f
            db[k] = 10f * log10(p)
        }
        db[half] = db[half - 1]

        for (i in 0 until BANDS) {
            val lo = bandLo[i]; val hi = bandHi[i]
            var d: Float
            if (hi >= lo) {
                d = db[lo]
                for (k in lo + 1..hi) if (db[k] > d) d = db[k]
            } else {
                val pos = bandPos[i]
                val i0 = min(max(pos.toInt(), 1), half - 1)
                val fr = min(max(pos - i0, 0f), 1f)
                d = db[i0] * (1 - fr) + db[i0 + 1] * fr
            }
            val t = i.toFloat() / (BANDS - 1)
            d += 3 + 14 * t
            localBands[i] = ((d + 65f) / 55f).coerceIn(0f, 1f)
        }
        synchronized(pubLock) {
            System.arraycopy(localBands, 0, pubBands, 0, BANDS)
            pubLevel = level
            pubTimeNs = System.nanoTime()
            pubHasData = true
        }
    }

    private fun computeBands() {
        val binHz = sampleRate.toDouble() / FFT
        val fMin = 40.0
        val fMax = min(16000.0, sampleRate * 0.5 * 0.97)
        val ratio = fMax / fMin
        val maxBin = FFT / 2 - 1
        for (i in 0 until BANDS) {
            val f0 = fMin * ratio.pow(i.toDouble() / BANDS)
            val f1 = fMin * ratio.pow((i + 1).toDouble() / BANDS)
            val lo = ceil(f0 / binHz).toInt()
            val hi = floor(f1 / binHz).toInt()
            bandLo[i] = min(max(lo, 1), maxBin)
            bandHi[i] = min(hi, maxBin)
            bandPos[i] = (sqrt(f0 * f1) / binHz).toFloat()
        }
    }

    // ---------------- EQ (idêntico ao iOS) ----------------

    private fun recomputeCoeffsLocked() {
        val fs = max(8000.0, sampleRate.toDouble())
        var any = false
        for (b in 0 until 5) {
            val dbG = eqGains[b].toDouble()
            if (abs(dbG) >= 0.05) any = true
            val a = 10.0.pow(dbG / 40.0)
            val w0 = 2.0 * PI * min(EQ_FREQS[b], fs * 0.45) / fs
            val cosW = cos(w0); val sinW = sin(w0)
            val q = 1.0
            val alpha = sinW / (2.0 * q)
            val b0: Double; val b1: Double; val b2: Double; val a0: Double; val a1: Double; val a2: Double
            if (b == 0) {
                val t = 2.0 * sqrt(a) * (sinW / 2.0 * sqrt(2.0))
                b0 = a * ((a + 1) - (a - 1) * cosW + t)
                b1 = 2 * a * ((a - 1) - (a + 1) * cosW)
                b2 = a * ((a + 1) - (a - 1) * cosW - t)
                a0 = (a + 1) + (a - 1) * cosW + t
                a1 = -2 * ((a - 1) + (a + 1) * cosW)
                a2 = (a + 1) + (a - 1) * cosW - t
            } else if (b == 4) {
                val t = 2.0 * sqrt(a) * (sinW / 2.0 * sqrt(2.0))
                b0 = a * ((a + 1) + (a - 1) * cosW + t)
                b1 = -2 * a * ((a - 1) + (a + 1) * cosW)
                b2 = a * ((a + 1) + (a - 1) * cosW - t)
                a0 = (a + 1) - (a - 1) * cosW + t
                a1 = 2 * ((a - 1) - (a + 1) * cosW)
                a2 = (a + 1) - (a - 1) * cosW - t
            } else {
                b0 = 1 + alpha * a; b1 = -2 * cosW; b2 = 1 - alpha * a
                a0 = 1 + alpha / a; a1 = -2 * cosW; a2 = 1 - alpha / a
            }
            val o = b * 5
            coeffs[o] = b0 / a0; coeffs[o + 1] = b1 / a0; coeffs[o + 2] = b2 / a0; coeffs[o + 3] = a1 / a0; coeffs[o + 4] = a2 / a0
        }
        eqBypass = !any
    }
}
