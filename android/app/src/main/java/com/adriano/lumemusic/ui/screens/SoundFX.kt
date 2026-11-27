package com.adriano.lumemusic.ui.screens

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.max
import kotlin.math.sin

/**
 * Efeitos sonoros sintetizados em código (SoundFX.swift) para a abertura/onboarding, com as MESMAS notas, parciais e
 * envelopes do iOS: "plink" de vidro (escala pentatônica que sobe a cada toque), "whoosh" de transição, acorde
 * Cmaj9 de conclusão, tom de erro e arpejo de sucesso. Volume 0,6 no volume de MÍDIA (USAGE_GAME, mistura com a música): o uso "sonificação" seguia o volume do sistema,
 * que muitos celulares (Xiaomi, Samsung) deixam no mudo ou silenciam no Não perturbe, e os sons sumiam.
 * Fora do onboarding o "motor" se desliga sozinho após 3,5 s sem sons.
 */
object SoundFX {
    enum class Effect { TAP, SELECT, DESELECT, WHOOSH, CHORD, ERROR, SUCCESS }

    private const val SR = 44_100
    private const val MASTER = 0.6f
    private val scale = doubleArrayOf(523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51, 1567.98)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val buffers = HashMap<String, ShortArray>()
    private val voices = arrayOfNulls<AudioTrack>(4)
    private var nextVoice = 0
    private var scaleIndex = 0
    private var started = false
    private var idleJob: Job? = null

    /** Onboarding aberto: mantém o motor ligado. */
    @Volatile var holdOpen = false

    @Synchronized fun begin() {
        if (started) return
        started = true
        scope.launch { synchronized(this@SoundFX) { for (e in listOf(Effect.TAP, Effect.SELECT, Effect.WHOOSH)) if (e != Effect.SELECT) buffer(e.name) { build(e) } } }
    }

    @Synchronized fun end() {
        holdOpen = false
        idleJob?.cancel()
        for (i in voices.indices) { runCatching { voices[i]?.release() }; voices[i] = null }
        buffers.clear()
        started = false
    }

    /** Zera a escala melódica (ao entrar numa tela nova). */
    fun resetScale() { scaleIndex = 0 }

    /** Compatibilidade: "plim" na escala. */
    fun chime(index: Int) = play(Effect.SELECT)

    fun play(effect: Effect) {
        scope.launch {
            try {
                val data: ShortArray = synchronized(this@SoundFX) {
                    if (!started) begin()
                    when (effect) {
                        Effect.SELECT -> {
                            val f = scale[scaleIndex % scale.size]
                            scaleIndex++
                            buffer("sel${scaleIndex % scale.size}") { plink(f, 0.8, 0.26) }
                        }
                        else -> buffer(effect.name) { build(effect) }
                    }
                }
                val track = AudioTrack.Builder()
                    .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                    .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(SR).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                    .setBufferSizeInBytes(data.size * 2).setTransferMode(AudioTrack.MODE_STATIC).build()
                track.write(data, 0, data.size)
                track.setVolume(MASTER)
                synchronized(this@SoundFX) {
                    val slot = nextVoice % voices.size
                    nextVoice++
                    runCatching { voices[slot]?.release() }
                    voices[slot] = track
                }
                track.play()
                scheduleIdleShutdown()
                delay(data.size * 1000L / SR + 300)
                synchronized(this@SoundFX) { val i = voices.indexOf(track); if (i >= 0) voices[i] = null }
                runCatching { track.release() }
            } catch (_: Exception) {}
        }
    }

    private fun scheduleIdleShutdown() {
        idleJob?.cancel()
        if (holdOpen) return
        idleJob = scope.launch { delay(3500); if (!holdOpen) end() }
    }

    private fun buffer(key: String, make: () -> FloatArray): ShortArray =
        buffers.getOrPut(key) { val f = make(); ShortArray(f.size) { (f[it].coerceIn(-1f, 1f) * 32767f).toInt().toShort() } }

    private fun build(e: Effect): FloatArray = when (e) {
        Effect.TAP -> plink(1318.51, 0.5, 0.16)
        Effect.SELECT -> plink(scale[0], 0.8, 0.26)
        Effect.DESELECT -> plink(392.0, 0.4, 0.12, 0.7f)
        Effect.WHOOSH -> whoosh()
        Effect.CHORD -> chord()
        Effect.ERROR -> errorTone()
        Effect.SUCCESS -> successArp()
    }

    // ------------------------------------------------------------ síntese (idêntica ao Swift)

    private fun fadeOut(i: Int, n: Int): Float { val tail = 600; return if (i > n - tail) (n - i).toFloat() / tail else 1f }

    /** Plink de vidro: fundamental + parciais inarmônicos com decaimento exponencial. */
    private fun plink(freq: Double, length: Double, decay: Double, gain: Float = 1f): FloatArray {
        val n = (length * SR).toInt()
        val out = FloatArray(n)
        val partials = arrayOf(doubleArrayOf(1.0, 1.0, 1.0), doubleArrayOf(2.76, 0.30, 0.55), doubleArrayOf(5.40, 0.11, 0.30))
        for (i in 0 until n) {
            val t = i.toDouble() / SR
            val attack = min(1.0, t / 0.003)
            var s = 0.0
            for (p in partials) s += p[1] * sin(2 * PI * freq * p[0] * t) * exp(-t / (decay * p[2]))
            out[i] = (s * attack).toFloat() * 0.30f * gain * fadeOut(i, n)
        }
        return out
    }

    /** Sopro filtrado que sobe de timbre (transição entre telas). */
    private fun whoosh(): FloatArray {
        val n = (0.42 * SR).toInt()
        val out = FloatArray(n)
        var lp = 0.0
        var seed = 0x1234ABCD
        for (i in 0 until n) {
            val t = i.toDouble() / n
            seed = seed * 1664525 + 1013904223
            val noise = seed.toDouble() / Int.MAX_VALUE
            val cutoff = 0.02 + 0.22 * sin(PI * t)
            lp += cutoff * (noise - lp)
            val env = sin(PI * t) * sin(PI * t)
            out[i] = (lp * env * 0.55).toFloat() * fadeOut(i, n)
        }
        return out
    }

    /** Acorde suave (Cmaj9) com ataque lento e cauda longa. */
    private fun chord(): FloatArray {
        val n = (2.2 * SR).toInt()
        val out = FloatArray(n)
        val freqs = doubleArrayOf(261.63, 329.63, 392.00, 493.88, 587.33, 783.99)
        for (i in 0 until n) {
            val t = i.toDouble() / SR
            val env = min(1.0, t / 0.07) * exp(-t / 0.95)
            var s = 0.0
            for ((k, f) in freqs.withIndex()) {
                val delay = k * 0.045
                val tt = max(0.0, t - delay)
                val e = if (tt > 0) min(1.0, tt / 0.05) else 0.0
                s += e * (sin(2 * PI * f * t) + 0.25 * sin(2 * PI * f * 2 * t)) / freqs.size
            }
            out[i] = (s * env).toFloat() * 0.55f * fadeOut(i, n)
        }
        return out
    }

    /** Dois tons graves curtos (erro suave). */
    private fun errorTone(): FloatArray {
        val n = (0.34 * SR).toInt()
        val out = FloatArray(n)
        for (i in 0 until n) {
            val t = i.toDouble() / SR
            val f = if (t < 0.14) 233.08 else 196.0
            val local = if (t < 0.14) t else t - 0.14
            val env = min(1.0, local / 0.004) * exp(-local / 0.09)
            out[i] = (sin(2 * PI * f * t) * env).toFloat() * 0.28f * fadeOut(i, n)
        }
        return out
    }

    /** Arpejo ascendente curto (código aceito). */
    private fun successArp(): FloatArray {
        val notes = doubleArrayOf(523.25, 659.25, 783.99, 1046.50)
        val n = (1.3 * SR).toInt()
        val out = FloatArray(n)
        for ((k, f) in notes.withIndex()) {
            val start = (k * 0.085 * SR).toInt()
            val tone = plink(f, 0.9, 0.3)
            for (j in tone.indices) if (start + j < n) out[start + j] += tone[j] * 0.8f
        }
        return out
    }
}
