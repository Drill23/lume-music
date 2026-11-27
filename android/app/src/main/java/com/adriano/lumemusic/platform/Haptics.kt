package com.adriano.lumemusic.platform

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/** Feedback háptico leve (equivalente ao Haptics do iOS). */
object Haptics {
    private var vibrator: Vibrator? = null
    @Volatile var enabled = true

    fun init(context: Context) {
        val app = context.applicationContext
        vibrator = if (Build.VERSION.SDK_INT >= 31) {
            (app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION") app.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun play(effectId: Int, fallbackMs: Long, amp: Int = 60) {
        if (!enabled) return
        val v = vibrator ?: return
        try {
            if (!v.hasVibrator()) return
            if (Build.VERSION.SDK_INT >= 29) v.vibrate(VibrationEffect.createPredefined(effectId))
            else v.vibrate(VibrationEffect.createOneShot(fallbackMs, amp))
        } catch (_: Exception) {}
    }

    fun light() = play(VibrationEffect.EFFECT_TICK, 8, 40)
    fun selection() = play(VibrationEffect.EFFECT_TICK, 6, 30)
    fun medium() = play(VibrationEffect.EFFECT_CLICK, 14, 90)
    fun success() = play(VibrationEffect.EFFECT_CLICK, 18, 100)
}
