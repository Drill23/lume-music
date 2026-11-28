package com.adriano.lumemusic

import com.adriano.lumemusic.audio.AudioDsp
import com.adriano.lumemusic.audio.GainRamp
import com.adriano.lumemusic.audio.PeakLimiter
import com.adriano.lumemusic.audio.SilenceDecision
import com.adriano.lumemusic.audio.SilenceMeter
import com.adriano.lumemusic.audio.SilencePolicy
import com.adriano.lumemusic.engine.MusicEngine
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sin

/** Seção C do contrato 5.2: volume igual, limitador de pico e pular silêncio (começo/fim). */
class AudioSectionCTest {
    private val sr = 48000

    // ---------- dB → ganho ----------

    @Test fun gainIsMinusLoudnessWithinLimits() {
        assertEquals(4.0, AudioDsp.normalizationGainDb(-1.0), 1e-9)
        assertEquals(-4.5, AudioDsp.normalizationGainDb(7.5), 1e-9)
        assertEquals(3.0, AudioDsp.normalizationGainDb(0.0), 1e-9)
    }

    @Test fun gainIsClampedToMinus12AndPlus6() {
        assertEquals(6.0, AudioDsp.normalizationGainDb(-20.0), 1e-9)
        assertEquals(6.0, AudioDsp.normalizationGainDb(-6.0), 1e-9)
        assertEquals(-12.0, AudioDsp.normalizationGainDb(30.0), 1e-9)
        assertEquals(-12.0, AudioDsp.normalizationGainDb(15.0), 1e-9)
    }

    @Test fun missingLoudnessMeansZeroDb() {
        assertEquals(0.0, AudioDsp.normalizationGainDb(null), 0.0)
        assertEquals(0.0, AudioDsp.normalizationGainDb(Double.NaN), 0.0)
        assertEquals(0.0, AudioDsp.normalizationGainDb(Double.POSITIVE_INFINITY), 0.0)
    }

    @Test fun dbToLinear() {
        assertEquals(1.0, AudioDsp.dbToLinear(0.0), 1e-12)
        assertEquals(1.9953, AudioDsp.dbToLinear(6.0), 1e-3)
        assertEquals(0.2512, AudioDsp.dbToLinear(-12.0), 1e-3)
        assertEquals(-12.0, AudioDsp.linearToDb(AudioDsp.dbToLinear(-12.0)), 1e-9)
    }

    @Test fun parsesLoudnessFromPlayerResponse() {
        val ok = Json.parseToJsonElement("""{"playerConfig":{"audioConfig":{"loudnessDb":-3.5,"perceptualLoudnessDb":-9}}}""")
        assertEquals(-3.5, MusicEngine.parseLoudnessDb(ok)!!, 1e-9)
        assertNull(MusicEngine.parseLoudnessDb(Json.parseToJsonElement("""{"playerConfig":{"audioConfig":{}}}""")))
        assertNull(MusicEngine.parseLoudnessDb(Json.parseToJsonElement("""{"streamingData":{}}""")))
        assertNull(MusicEngine.parseLoudnessDb(Json.parseToJsonElement("""{"playerConfig":{"audioConfig":{"loudnessDb":999}}}""")))
    }

    // ---------- rampa de ganho ----------

    @Test fun rampTakesAbout300msAndIsMonotonic() {
        val r = GainRamp()
        r.setTarget(1.0, sr)                       // primeiro alvo: entra direto
        assertEquals(1.0, r.current, 0.0)
        r.setTarget(2.0, sr)
        val frames = (sr * 0.3).toInt()
        var prev = r.current
        var maxStep = 0.0
        for (i in 0 until frames) {
            val g = r.next()
            assertTrue(g >= prev)
            maxStep = max(maxStep, g - prev); prev = g
        }
        assertEquals(2.0, r.current, 1e-9)
        assertTrue("degrau por amostra deve ser pequeno", maxStep < 0.001)
        assertTrue(r.isSettled)
    }

    // ---------- limitador ----------

    private fun sine(frames: Int, ch: Int, amp: Double, hz: Double = 1000.0, startFrame: Int = 0): FloatArray {
        val a = FloatArray(frames * ch)
        for (f in 0 until frames) for (c in 0 until ch) a[f * ch + c] = (amp * sin(2 * PI * hz * (startFrame + f) / sr)).toFloat()
        return a
    }

    @Test fun limiterKeepsPlus6dbSineBelowMinus1dbfs() {
        val ceiling = AudioDsp.dbToLinear(-1.0)
        val lim = PeakLimiter(sr, 2)
        val amp = AudioDsp.dbToLinear(6.0)                 // senoide com +6 dB (pico ≈ 2,0)
        var peak = 0f
        var maxJump = 0f
        var last = 0f
        var pos = 0
        val total = sr                                     // 1 s, em blocos de 480 quadros como o decodificador entrega
        while (pos < total) {
            val n = 480
            val buf = sine(n, 2, amp, startFrame = pos)
            lim.process(buf, n)
            for (i in buf.indices step 2) {
                peak = max(peak, abs(buf[i])); peak = max(peak, abs(buf[i + 1]))
                if (pos + i / 2 > 100) maxJump = max(maxJump, abs(buf[i] - last))
                last = buf[i]
            }
            pos += n
        }
        assertTrue("pico ${AudioDsp.linearToDb(peak.toDouble())} dBFS passou de -1 dBFS", peak <= ceiling + 1e-6)
        assertTrue("limitou demais: ${AudioDsp.linearToDb(peak.toDouble())} dBFS", peak > ceiling - 0.05)
        assertTrue("estalo: salto $maxJump", maxJump < 0.25)
    }

    @Test fun limiterAlsoCatchesSuddenSingleSamplePeak() {
        val ceiling = AudioDsp.dbToLinear(-1.0).toFloat()
        val lim = PeakLimiter(sr, 1)
        val buf = FloatArray(4800) { 0.1f }
        buf[2000] = 3.0f; buf[2001] = -3.0f
        lim.process(buf, buf.size)
        assertTrue(buf.all { abs(it) <= ceiling + 1e-6f })
    }

    @Test fun limiterLeavesQuietSignalUntouchedAndRecoversAfterBurst() {
        val lim = PeakLimiter(sr, 2)
        val lat = lim.latencyFrames
        assertTrue(lat in 40..60)                          // ~1 ms a 48 kHz
        val quiet = sine(sr / 2, 2, 0.1)
        val copy = quiet.copyOf()
        lim.process(quiet, sr / 2)
        for (f in lat until sr / 2) assertEquals(copy[(f - lat) * 2], quiet[f * 2], 1e-6f)

        // rajada alta e depois sinal baixo: o ganho volta a 1 (release ~100 ms)
        val burst = sine(sr / 10, 2, 2.0)
        lim.process(burst, sr / 10)
        val after = sine(sr, 2, 0.1)
        val ref = after.copyOf()
        lim.process(after, sr)
        val f = sr - 10 - lat                              // quadro de entrada perto do fim; sai `lat` quadros depois
        assertEquals(ref[f * 2], after[(f + lat) * 2], 0.02f) // ganho voltou a ~1
    }

    @Test fun limiterCeilingRaisesTo0dbfsWhenNotEngaged() {
        val lim = PeakLimiter(sr, 1)
        lim.ceiling = 1f
        val buf = sine(4800, 1, 0.97)                      // acima de -1 dBFS, mas abaixo de 0 dBFS: passa inteiro
        val peakIn = buf.maxOf { abs(it) }
        lim.process(buf, buf.size)
        assertEquals(peakIn.toDouble(), buf.maxOf { abs(it) }.toDouble(), 1e-3)
    }

    // ---------- silêncio ----------

    private fun feed(m: SilenceMeter, seconds: Double, amp: Double) {
        val n = (seconds * sr).toInt()
        for (i in 0 until n) { val v = amp * sin(2 * PI * 440.0 * i / sr); m.addFrame((v * v).toFloat()) }
    }

    private fun meter() = SilenceMeter().also { it.configure(sr) }

    @Test fun meterCountsOnlyContinuousSilenceBelowMinus50() {
        val m = meter()
        // seno constante com RMS de -45 dBFS: tem som; -60 dBFS: silêncio
        feed(m, 1.0, AudioDsp.dbToLinear(-45.0) * 1.4142)
        assertEquals(0.0, m.silentRunSec, 1e-9)
        feed(m, 2.0, AudioDsp.dbToLinear(-60.0) * 1.4142)
        assertEquals(2.0, m.silentRunSec, 0.05)
        feed(m, 0.5, 0.5)                                  // voltou o som: zera
        assertEquals(0.0, m.silentRunSec, 1e-9)
        assertEquals(3.5, m.processedSec, 0.05)
    }

    @Test fun endSilenceInLast20sGoesToNextTrack() {
        val m = meter()
        feed(m, 1.0, 0.5)
        feed(m, 1.6, 0.0)                                  // 1,6 s de silêncio
        val d = SilencePolicy.decide(positionSec = 190.0, durationSec = 200.0, silentRunSec = m.silentRunSec, processedSec = m.processedSec, originSec = 188.0)
        assertEquals(SilenceDecision.NextTrack, d)
    }

    @Test fun shortSilenceAtEndDoesNotSkip() {
        val d = SilencePolicy.decide(190.0, 200.0, 1.2, 5.0, 185.0)
        assertEquals(SilenceDecision.None, d)
    }

    @Test fun silenceInTheMiddleOfTheSongNeverSkips() {
        // 5 s de silêncio aos 100 s de uma faixa de 200 s (fora dos primeiros 15 s e dos últimos 20 s)
        for (pos in listOf(30.0, 100.0, 170.0, 179.0)) {
            val d = SilencePolicy.decide(pos, 200.0, 5.0, 20.0, pos - 6.0)
            assertEquals("pos=$pos", SilenceDecision.None, d)
        }
    }

    @Test fun silenceAtTheStartSkipsInSmallJumpsAndKeepsTheAttack() {
        // 1 s de silêncio desde o começo: pula até um pouco antes do fim do silêncio já medido
        val d = SilencePolicy.decide(positionSec = 0.4, durationSec = 200.0, silentRunSec = 1.0, processedSec = 1.0, originSec = 0.0)
        assertTrue(d is SilenceDecision.SkipTo)
        val to = (d as SilenceDecision.SkipTo).seconds
        assertTrue("alvo $to precisa ficar antes do fim do silêncio medido (1,0 s)", to < 1.0 && to > 0.4)
        // silêncio longo: o salto é limitado (pequenos saltos)
        val big = SilencePolicy.decide(0.5, 200.0, 8.0, 8.0, 0.0) as SilenceDecision.SkipTo
        assertTrue(big.seconds <= 0.5 + SilencePolicy.START_MAX_JUMP_SEC + 1e-9)
    }

    @Test fun startDoesNotSkipOnceSoundHasStartedOrAfter15s() {
        // já houve som desde o recomeço (processado 3 s, silêncio seguido só 0,6 s): é pausa de introdução, não pula
        assertEquals(SilenceDecision.None, SilencePolicy.decide(3.0, 200.0, 0.6, 3.0, 0.0))
        // depois dos 15 s não é "começo"
        assertEquals(SilenceDecision.None, SilencePolicy.decide(20.0, 200.0, 2.0, 2.0, 18.0))
        // silêncio ainda curto demais para confirmar
        assertEquals(SilenceDecision.None, SilencePolicy.decide(0.1, 200.0, 0.2, 0.2, 0.0))
    }

    @Test fun veryShortTracksAreIgnored() {
        assertEquals(SilenceDecision.None, SilencePolicy.decide(8.0, 10.0, 2.0, 2.0, 6.0))
    }
}
