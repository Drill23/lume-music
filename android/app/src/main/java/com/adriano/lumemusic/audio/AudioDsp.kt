package com.adriano.lumemusic.audio

import kotlin.math.log10
import kotlin.math.max
import kotlin.math.pow

/** Matemática pura do "Volume igual entre as músicas" (testável na JVM, sem Android). */
object AudioDsp {
    const val MIN_GAIN_DB = -12.0
    const val MAX_GAIN_DB = 6.0
    const val LIMITER_CEILING_DB = -1.0
    const val RAMP_MS = 300.0

    /** Alvo 3 dB acima da referência do YouTube (≈ -11 LUFS, como o "Alto" do Spotify): o app não fica mais baixo que antes. */
    const val TARGET_OFFSET_DB = 3.0

    /** Ganho = 3 - loudnessDb, limitado a [-12, +6] dB. Sem dado (ou valor inválido) → 0 dB. */
    fun normalizationGainDb(loudnessDb: Double?): Double {
        if (loudnessDb == null || !loudnessDb.isFinite()) return 0.0
        return (TARGET_OFFSET_DB - loudnessDb).coerceIn(MIN_GAIN_DB, MAX_GAIN_DB)
    }

    fun dbToLinear(db: Double): Double = 10.0.pow(db / 20.0)
    fun linearToDb(linear: Double): Double = 20.0 * log10(max(linear, 1e-12))
}

/**
 * Rampa linear do ganho (~300 ms) para trocar de nível sem estalo. Só a thread de áudio usa.
 * O primeiro alvo vira o valor atual direto (não há o que suavizar antes do primeiro som).
 */
class GainRamp {
    var current = Double.NaN; private set
    var target = 1.0; private set
    private var step = 0.0

    fun setTarget(t: Double, sampleRate: Int, rampMs: Double = AudioDsp.RAMP_MS) {
        if (current.isNaN()) { current = t; target = t; step = 0.0; return }
        if (t == target) return
        target = t
        step = (t - current) / max(1.0, sampleRate * rampMs / 1000.0)
    }

    val isSettled: Boolean get() = current == target

    /** Avança um quadro e devolve o ganho a aplicar nele. */
    fun next(): Double {
        if (current != target) {
            current += step
            if (step == 0.0 || (step > 0 && current >= target) || (step < 0 && current <= target)) current = target
        }
        return current
    }
}
