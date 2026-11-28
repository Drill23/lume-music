package com.adriano.lumemusic.audio

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Medidor de silêncio. Roda na thread de áudio (só escreve variáveis @Volatile); quem decide é o AudioPlayer.
 * Mede o RMS em blocos de 20 ms do áudio ORIGINAL (antes do ganho/EQ) e acumula "tempo seguido em silêncio".
 * Tudo é contado desde o último flush (troca de faixa, seek): [epoch] muda a cada recomeço.
 */
class SilenceMeter(thresholdDb: Double = SilencePolicy.THRESHOLD_DBFS) {
    private val thresholdMeanSquare = 10.0.pow(thresholdDb / 10.0)
    private var sampleRate = 44100
    private var blockFrames = 882
    private var acc = 0.0
    private var count = 0

    /** Segundos seguidos abaixo do limiar, até o último áudio medido. 0 se o último bloco tinha som. */
    @Volatile var silentRunSec = 0.0; private set
    /** Segundos de áudio medidos desde o último recomeço. */
    @Volatile var processedSec = 0.0; private set
    @Volatile var epoch = 0; private set

    fun configure(sampleRate: Int) {
        this.sampleRate = max(8000, sampleRate)
        blockFrames = max(1, this.sampleRate / 50)
        reset()
    }

    fun reset() {
        acc = 0.0; count = 0
        silentRunSec = 0.0; processedSec = 0.0
        epoch += 1
    }

    /** [meanSquare] = média dos quadrados das amostras do quadro (média entre os canais). */
    fun addFrame(meanSquare: Float) {
        acc += meanSquare
        count += 1
        if (count >= blockFrames) {
            val dur = count.toDouble() / sampleRate
            val silent = acc / count < thresholdMeanSquare
            processedSec += dur
            silentRunSec = if (silent) silentRunSec + dur else 0.0
            acc = 0.0; count = 0
        }
    }
}

sealed interface SilenceDecision {
    data object None : SilenceDecision
    /** Avançar a reprodução para [seconds] (só no começo da faixa). */
    data class SkipTo(val seconds: Double) : SilenceDecision
    /** Fim da faixa em silêncio: ir para a próxima, como no fim natural. */
    data object NextTrack : SilenceDecision
}

/** Regra de "Pular silêncio": só começo e fim da faixa, nunca pausas no meio da música. */
object SilencePolicy {
    const val THRESHOLD_DBFS = -50.0
    const val END_WINDOW_SEC = 20.0
    const val END_SILENCE_SEC = 1.5
    const val START_WINDOW_SEC = 15.0
    const val START_CONFIRM_SEC = 0.3
    /** Margem antes do ponto onde o silêncio medido termina, para não cortar o ataque da primeira nota. */
    const val START_GUARD_SEC = 0.25
    const val START_MAX_JUMP_SEC = 2.0
    const val START_MIN_JUMP_SEC = 0.2
    /** Faixas muito curtas (vinhetas) não entram na regra. */
    const val MIN_DURATION_SEC = 30.0

    /**
     * @param positionSec posição atual de reprodução
     * @param durationSec duração da faixa
     * @param silentRunSec silêncio seguido medido (desde o último recomeço do medidor)
     * @param processedSec áudio medido desde o último recomeço
     * @param originSec posição da faixa em que o medidor recomeçou
     */
    fun decide(positionSec: Double, durationSec: Double, silentRunSec: Double, processedSec: Double, originSec: Double): SilenceDecision {
        if (!(durationSec >= MIN_DURATION_SEC) || positionSec < 0) return SilenceDecision.None
        // Fim: nos últimos 20 s, 1,5 s seguidos de silêncio.
        if (durationSec - positionSec <= END_WINDOW_SEC && silentRunSec >= END_SILENCE_SEC) return SilenceDecision.NextTrack
        // Começo: nos primeiros 15 s, enquanto ainda não houve som desde o recomeço.
        if (positionSec < START_WINDOW_SEC && silentRunSec >= START_CONFIRM_SEC && silentRunSec >= processedSec - 0.05) {
            val knownSilentUntil = originSec + silentRunSec
            val target = min(min(knownSilentUntil - START_GUARD_SEC, positionSec + START_MAX_JUMP_SEC), durationSec - 1.0)
            if (target - positionSec >= START_MIN_JUMP_SEC) return SilenceDecision.SkipTo(target)
        }
        return SilenceDecision.None
    }
}
