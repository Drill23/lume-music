package com.adriano.lumemusic

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.ui.RootScreen
import com.adriano.lumemusic.ui.UpgradeModel
import com.adriano.lumemusic.ui.theme.LumeTheme
import com.adriano.lumemusic.update.UpdateController
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // A permissão de notificações NÃO é pedida aqui: só depois do onboarding, quando a primeira música começar (RootScreen).

        setContent {
            LumeTheme {
                // Código de Acesso + atualização do app: ao abrir e a cada 6 h (em segundo plano; nunca bloqueia a abertura).
                LaunchedEffect(Unit) {
                    while (true) {
                        try { Access.service.check() } catch (_: Exception) {}
                        try { UpdateController.check(force = true) } catch (_: Exception) {}
                        delay(com.adriano.lumemusic.access.AccessConfig.CHECK_INTERVAL_MS)
                    }
                }
                RootScreen()
            }
        }
        handleDebug(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDebug(intent)
    }

    /**
     * Intents de depuração para o orquestrador (só em build debug OU com lm_debug_token == "lume-orq-2026"):
     * lm_debug_welcome (Int dias), lm_debug_upgrade (Boolean) [+ lm_debug_manual], lm_debug_paid (String código),
     * lm_debug_update (Boolean), lm_debug_transfer (Boolean), lm_debug_pin (Boolean), lm_debug_trial (Int dias), lm_debug_trial_used (Boolean). Dados sempre falsos e locais.
     */
    private fun handleDebug(i: Intent?) {
        if (i == null) return
        if (!(BuildConfig.DEBUG || i.getStringExtra("lm_debug_token") == "lume-orq-2026")) return
        if (i.hasExtra("lm_debug_welcome")) UpgradeModel.debugWelcome(i.getIntExtra("lm_debug_welcome", 30))
        if (i.getBooleanExtra("lm_debug_upgrade", false)) UpgradeModel.debugUpgrade(i.getBooleanExtra("lm_debug_manual", false))
        i.getStringExtra("lm_debug_paid")?.let { UpgradeModel.debugPaid(it.uppercase().take(6)) }
        if (i.getBooleanExtra("lm_debug_update", false)) UpdateController.debugOffer()
        if (i.getBooleanExtra("lm_debug_transfer", false)) UpgradeModel.debugTransfer()
        if (i.getBooleanExtra("lm_debug_pin", false)) UpgradeModel.debugPin()
        if (i.hasExtra("lm_debug_trial")) UpgradeModel.debugTrial(i.getIntExtra("lm_debug_trial", 7))
        if (i.getBooleanExtra("lm_debug_trial_used", false)) UpgradeModel.debugTrialUsed()
    }
}
