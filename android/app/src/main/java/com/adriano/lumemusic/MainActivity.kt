package com.adriano.lumemusic

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.ui.RootScreen
import com.adriano.lumemusic.ui.theme.LumeTheme
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // A permissão de notificações NÃO é pedida aqui: só depois do onboarding, quando a primeira música começar (RootScreen).

        setContent {
            LumeTheme {
                // Código de Acesso: verificação em segundo plano (a tela do portão entra na fase 2).
                LaunchedEffect(Unit) {
                    while (true) {
                        try { Access.service.check() } catch (_: Exception) {}
                        delay(com.adriano.lumemusic.access.AccessConfig.CHECK_INTERVAL_MS)
                    }
                }
                RootScreen()
            }
        }
    }
}
