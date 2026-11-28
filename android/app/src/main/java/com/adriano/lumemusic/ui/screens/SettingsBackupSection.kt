package com.adriano.lumemusic.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.access.AccessState
import com.adriano.lumemusic.data.BackupOutcome
import com.adriano.lumemusic.data.BackupText
import com.adriano.lumemusic.data.LibraryBackup
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.GlassButton
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import kotlinx.coroutines.launch

/** Ajustes › "Backup da biblioteca" (contrato 5.2 A). Só aparece com acesso ativo (teste grátis ou vitalício). */
@Composable
fun SettingsBackupSection() {
    val state by Access.service.state.collectAsState()
    if (state !is AccessState.Active) return
    val scope = rememberCoroutineScope()
    var confirmRestore by remember { mutableStateOf(false) }
    val busy = LibraryBackup.busy

    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("BACKUP DA BIBLIOTECA", style = Theme.font(12f, FontWeight.SemiBold, Theme.secondary), modifier = Modifier.padding(start = 6.dp))
        Column(Modifier.fillMaxWidth().glass(RoundedCornerShape(22.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Icon(sf("cloud"), null, tint = Theme.accent, modifier = Modifier.size(26.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Suas playlists, curtidas e artistas ficam guardados com o seu acesso. Ao levar o Vitalício para outro celular, tudo vem junto.",
                        style = Theme.font(13.5f, color = Theme.secondary))
                    Text(if (busy) "Sincronizando…" else BackupText.last(LibraryBackup.lastBackupAt), style = Theme.font(13.5f, FontWeight.Medium, Theme.text))
                }
            }
            GlassButton(if (busy) "Aguarde…" else "Fazer backup agora", "cloud") {
                if (busy) return@GlassButton
                scope.launch {
                    when (val r = LibraryBackup.backup(manual = true)) {
                        is BackupOutcome.Done -> AppModel.showToast("Backup feito")
                        is BackupOutcome.Failed -> AppModel.showToast(r.message)
                        BackupOutcome.Skipped -> AppModel.showToast("Não foi possível fazer o backup agora")
                    }
                }
            }
            GlassButton("Restaurar do backup", "arrow.counterclockwise") { if (!busy) confirmRestore = true }
        }
    }

    if (confirmRestore) AlertDialog(
        onDismissRequest = { confirmRestore = false }, containerColor = Theme.canvasRaised,
        title = { Text("Restaurar do backup?", color = Theme.text) },
        text = { Text("Vamos juntar o que está guardado com a sua biblioteca deste celular. Nada do que você tem aqui é apagado: só entram playlists, curtidas e artistas que estiverem faltando.", color = Theme.secondary) },
        confirmButton = { TextButton({
            confirmRestore = false
            scope.launch {
                when (val r = LibraryBackup.restore(manual = true)) {
                    is BackupOutcome.Done -> AppModel.showToast(
                        if (r.changed) "Biblioteca restaurada e mesclada" else if (r.savedAt > 0) "Sua biblioteca já está igual ao backup" else "Ainda não há backup guardado")
                    is BackupOutcome.Failed -> AppModel.showToast(r.message)
                    BackupOutcome.Skipped -> AppModel.showToast("Não foi possível restaurar agora")
                }
            }
        }) { Text("Restaurar", color = Theme.accent) } },
        dismissButton = { TextButton({ confirmRestore = false }) { Text("Cancelar", color = Theme.secondary) } },
    )
}
