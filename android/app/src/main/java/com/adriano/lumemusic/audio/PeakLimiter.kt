package com.adriano.lumemusic.audio

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Limitador de pico com antecipação (lookahead), sem alocação por amostra.
 *
 *  - O áudio passa por uma linha de atraso de ~1 ms (o "attack").
 *  - Para cada quadro calcula-se o ganho necessário para ficar sob o teto; o mínimo desse ganho numa janela de
 *    [lookahead] quadros, suavizado (release ~100 ms para subir de volta) e depois por uma média móvel de
 *    [lookahead] quadros, garante que o ganho já desceu quando o pico sai da linha de atraso → sem estalos e
 *    sem ultrapassar o teto. Um clamp final no teto cobre erros de arredondamento.
 *  - Sinal abaixo do teto sai igual (ganho 1), só atrasado em [latencyFrames].
 *
 * Processa em lugar um vetor intercalado de floats (-1..1) com [channels] canais.
 */
class PeakLimiter(sampleRate: Int, private val channels: Int) {
    companion object {
        const val ATTACK_MS = 1.0
        const val RELEASE_MS = 100.0
    }

    private val look = max(2, (sampleRate * ATTACK_MS / 1000.0).roundToInt())
    private val delayBuf = FloatArray(look * channels)
    private val reqRing = FloatArray(look) { 1f }
    private val sRing = FloatArray(look) { 1f }
    private var sSum = look.toDouble()
    private var s = 1f
    private var idx = 0
    private var unity = look
    private val relCoef = (1.0 - exp(-1.0 / (sampleRate * RELEASE_MS / 1000.0))).toFloat()

    /** Teto linear (1.0 = 0 dBFS). Mudado só pela thread que processa. */
    var ceiling: Float = AudioDsp.dbToLinear(AudioDsp.LIMITER_CEILING_DB).toFloat()

    /** Atraso total (quadros) entre entrada e saída. */
    val latencyFrames: Int get() = look - 1

    fun reset() {
        delayBuf.fill(0f); reqRing.fill(1f); sRing.fill(1f)
        sSum = look.toDouble(); s = 1f; idx = 0; unity = look
    }

    /** Processa [frames] quadros de [data] (intercalado) no lugar. */
    fun process(data: FloatArray, frames: Int) {
        val ch = channels
        val ceil = ceiling
        for (f in 0 until frames) {
            val base = f * ch
            var peak = 0f
            for (c in 0 until ch) { val a = abs(data[base + c]); if (a > peak) peak = a }
            val r = if (peak > ceil) ceil / peak else 1f
            reqRing[idx] = r
            if (r == 1f) { if (unity < look) unity++ } else unity = 0
            var m = 1f
            if (unity < look) for (k in 0 until look) { val v = reqRing[k]; if (v < m) m = v }
            s = if (m < s) m else s + (m - s) * relCoef
            sSum += s.toDouble() - sRing[idx].toDouble()
            sRing[idx] = s
            val g = (sSum / look).toFloat()
            val readBase = ((idx + 1) % look) * ch
            val writeBase = idx * ch
            for (c in 0 until ch) {
                val o = delayBuf[readBase + c] * g
                delayBuf[writeBase + c] = data[base + c]
                data[base + c] = if (o > ceil) ceil else if (o < -ceil) -ceil else o
            }
            idx = (idx + 1) % look
        }
    }
}
