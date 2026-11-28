package com.adriano.lumemusic.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.data.LbConnect
import com.adriano.lumemusic.data.ListenBrainz
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.GlassButton
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.launch

/** Ajustes › "Registrar o que eu ouço" › ListenBrainz (contrato 5.2 B). Desligado até colar um token válido. */
@Composable
fun SettingsScrobbleSection() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var token by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val user = ListenBrainz.connectedUser

    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("REGISTRAR O QUE EU OUÇO", style = Theme.font(12f, FontWeight.SemiBold, Theme.secondary), modifier = Modifier.padding(start = 6.dp))
        Column(Modifier.fillMaxWidth().glass(RoundedCornerShape(22.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Icon(sf("waveform"), null, tint = Theme.accent, modifier = Modifier.size(26.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("ListenBrainz", style = Theme.font(16f, FontWeight.SemiBold, Theme.text))
                    Text(
                        if (user != null) "Conectado como $user" else "Envia as músicas que você ouve para o seu perfil no ListenBrainz.",
                        style = Theme.font(13.5f, color = if (user != null) Theme.ok else Theme.secondary),
                    )
                }
            }
            if (user != null) {
                if (ListenBrainz.queuedCount > 0) Text("${ListenBrainz.queuedCount} ouvidas aguardando conexão para serem enviadas.", style = Theme.font(13f, color = Theme.secondary))
                GlassButton("Desconectar", "xmark") { ListenBrainz.disconnect(); token = ""; AppModel.showToast("ListenBrainz desconectado") }
            } else {
                Box(Modifier.fillMaxWidth().height(50.dp).glass(RoundedCornerShape(16.dp)).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
                    if (token.isEmpty()) Text("Cole o seu token aqui", style = Theme.font(15f, color = Theme.tertiary))
                    BasicTextField(
                        token, { token = it.trim(); error = null }, singleLine = true,
                        modifier = Modifier.fillMaxWidth(), textStyle = Theme.font(15f, color = Theme.text),
                        cursorBrush = SolidColor(Theme.accent), visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                    )
                }
                Text("Pegar meu token", style = Theme.font(14f, FontWeight.Medium, Theme.accent),
                    modifier = Modifier.pressable(0.97f) {
                        try { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(ListenBrainz.TOKEN_URL)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
                    }.padding(vertical = 4.dp, horizontal = 6.dp))
                error?.let { Text(it, style = Theme.font(13f, color = Theme.danger)) }
                GlassButton(if (busy) "Conectando…" else "Conectar", "link") {
                    if (busy) return@GlassButton
                    busy = true
                    scope.launch {
                        when (val r = ListenBrainz.connect(token)) {
                            is LbConnect.Ok -> { token = ""; AppModel.showToast("Conectado como ${r.user}") }
                            is LbConnect.Failed -> error = r.message
                        }
                        busy = false
                    }
                }
            }
        }
    }
}
