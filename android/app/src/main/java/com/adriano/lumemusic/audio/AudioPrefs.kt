package com.adriano.lumemusic.audio

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.concurrent.ConcurrentHashMap

/** Preferências de áudio da seção C (mesmo arquivo de preferências que o app já usa). */
object AudioPrefs {
    private const val FILE = "lume_prefs"
    const val KEY_NORMALIZE = "audio.normalize"
    const val KEY_SKIP_SILENCE = "audio.skipSilence"

    var normalize by mutableStateOf(true); private set
    var skipSilence by mutableStateOf(false); private set
    private var ctx: Context? = null

    fun init(context: Context) {
        val app = context.applicationContext
        ctx = app
        try {
            val p = app.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            normalize = p.getBoolean(KEY_NORMALIZE, true)
            skipSilence = p.getBoolean(KEY_SKIP_SILENCE, false)
        } catch (_: Exception) {}
    }

    fun updateNormalize(v: Boolean) { normalize = v; save(KEY_NORMALIZE, v) }
    fun updateSkipSilence(v: Boolean) { skipSilence = v; save(KEY_SKIP_SILENCE, v) }

    private fun save(key: String, v: Boolean) {
        try { ctx?.getSharedPreferences(FILE, Context.MODE_PRIVATE)?.edit()?.putBoolean(key, v)?.apply() } catch (_: Exception) {}
    }
}

/**
 * Sonoridade (loudnessDb do YouTube) por faixa. Fica guardada à parte, no armazenamento privado do app,
 * para valer também nas músicas baixadas (tocadas sem rede) e para o ganho certo desde o primeiro instante.
 */
object LoudnessStore {
    private const val FILE = "lume_loudness"
    private val map = ConcurrentHashMap<String, Double>()
    private var ctx: Context? = null
    private var loaded = false

    @Synchronized fun init(context: Context) {
        if (loaded) return
        val app = context.applicationContext
        ctx = app
        try {
            for ((k, v) in app.getSharedPreferences(FILE, Context.MODE_PRIVATE).all) {
                (v as? Float)?.let { map[k] = it.toDouble() }
            }
        } catch (_: Exception) {}
        loaded = true
    }

    fun get(trackId: String): Double? = map[trackId]

    fun put(trackId: String, loudnessDb: Double) {
        if (!loudnessDb.isFinite()) return
        val old = map.put(trackId, loudnessDb)
        if (old != null && kotlin.math.abs(old - loudnessDb) < 0.01) return
        try { ctx?.getSharedPreferences(FILE, Context.MODE_PRIVATE)?.edit()?.putFloat(trackId, loudnessDb.toFloat())?.apply() } catch (_: Exception) {}
    }
}
