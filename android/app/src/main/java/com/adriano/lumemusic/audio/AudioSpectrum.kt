package com.adriano.lumemusic.audio

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.exp

/**
 * Espectro de áudio real (24 bandas + nível) vindo do LumeAudioProcessor, com suavização attack/release
 * idêntica à do iOS. Só roda enquanto houver algum "consumidor" visível (acquire/release).
 */
object AudioSpectrum {
    const val BAND_COUNT = LumeAudioProcessor.BANDS
    private const val ATTACK = 0.060f
    private const val RELEASE = 0.220f
    private const val FRESH_NS = 120_000_000L
    private const val LIVE_NS = 500_000_000L

    var bands by mutableStateOf(FloatArray(BAND_COUNT)); private set
    var level by mutableFloatStateOf(0f); private set
    var isLive by mutableStateOf(false); private set

    private var processor: LumeAudioProcessor? = null
    private var eq: List<Float> = listOf(0f, 0f, 0f, 0f, 0f)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    private var consumers = 0
    private val smoothed = FloatArray(BAND_COUNT)
    private var smoothedLevel = 0f
    private val target = FloatArray(BAND_COUNT)

    fun attach(p: LumeAudioProcessor) {
        processor = p
        p.setEQGains(eq)
        p.setAnalysisActive(consumers > 0)
    }

    fun setEQGains(g: List<Float>) { eq = g; processor?.setEQGains(g) }

    fun acquire() {
        consumers++
        processor?.setAnalysisActive(true)
        if (job == null) job = scope.launch { loop() }
    }

    fun release() {
        consumers = (consumers - 1).coerceAtLeast(0)
        if (consumers == 0) {
            processor?.setAnalysisActive(false)
            job?.cancel(); job = null
            smoothed.fill(0f); smoothedLevel = 0f
            bands = FloatArray(BAND_COUNT); level = 0f; isLive = false
        }
    }

    private suspend fun loop() {
        var last = System.nanoTime()
        while (scope.isActive) {
            delay(33)
            val now = System.nanoTime()
            val dt = ((now - last) / 1e9f).coerceIn(0.005f, 0.1f)
            last = now
            target.fill(0f)
            var targetLevel = 0f
            var live = false
            val snap = processor?.snapshot(target)
            if (snap != null && snap.hasData) {
                val age = now - snap.timeNs
                live = age < LIVE_NS
                if (age < FRESH_NS) targetLevel = snap.level else target.fill(0f)
            } else target.fill(0f)
            val aA = 1 - exp(-dt / ATTACK)
            val aR = 1 - exp(-dt / RELEASE)
            var changed = false
            for (i in 0 until BAND_COUNT) {
                val cur = smoothed[i]
                var v = cur + (target[i] - cur) * (if (target[i] > cur) aA else aR)
                if (v < 0.003f) v = 0f
                if (v != cur) changed = true
                smoothed[i] = v
            }
            var lv = smoothedLevel + (targetLevel - smoothedLevel) * (if (targetLevel > smoothedLevel) aA else aR)
            if (lv < 0.003f) lv = 0f
            smoothedLevel = lv
            if (changed) bands = smoothed.copyOf()
            if (level != lv) level = lv
            if (isLive != live) isLive = live
        }
    }
}
