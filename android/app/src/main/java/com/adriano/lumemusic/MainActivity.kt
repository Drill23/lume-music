package com.adriano.lumemusic

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.core.content.ContextCompat
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.ui.RootScreen
import com.adriano.lumemusic.ui.theme.LumeTheme
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    private val notifPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)

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
