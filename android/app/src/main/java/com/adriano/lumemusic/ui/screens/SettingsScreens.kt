package com.adriano.lumemusic.ui.screens

import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.BuildConfig
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.data.CassetteStyle
import com.adriano.lumemusic.data.LockArtStyle
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.PlayerSurfaceTab
import com.adriano.lumemusic.data.SleepTimerOption
import com.adriano.lumemusic.data.SoundProfile
import com.adriano.lumemusic.data.TurntableFinish
import com.adriano.lumemusic.data.VinylEdition
import com.adriano.lumemusic.data.VisualizerStyle
import com.adriano.lumemusic.engine.DiscNet
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.DetailHeader
import com.adriano.lumemusic.ui.GlassButton
import com.adriano.lumemusic.ui.HRow
import com.adriano.lumemusic.ui.LumeRoute
import com.adriano.lumemusic.ui.PrismChip
import com.adriano.lumemusic.ui.glass
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf
import com.adriano.lumemusic.update.UpdateCheckOutcome
import com.adriano.lumemusic.update.UpdateController
import java.io.File

@Composable
private fun Card(title: String? = null, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (title != null) Text(title.uppercase(), style = Theme.font(12f, FontWeight.SemiBold, Theme.secondary), modifier = Modifier.padding(start = 6.dp))
        Column(Modifier.fillMaxWidth().glass(RoundedCornerShape(22.dp)).padding(vertical = 4.dp)) { content() }
    }
}

@Composable
private fun CardDivider(inset: Boolean = true) {
    HorizontalDivider(Modifier.padding(start = if (inset) 52.dp else 16.dp, end = 16.dp), thickness = 0.5.dp, color = Theme.hairline)
}

@Composable
private fun ToggleRow(icon: String, title: String, subtitle: String? = null, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn56().pressable(0.995f) { onChange(!value) }.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Icon(sf(icon), null, tint = Theme.accent, modifier = Modifier.size(21.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = Theme.font(15.5f, FontWeight.Medium, Theme.text))
            if (subtitle != null) Text(subtitle, style = Theme.font(12.5f, color = Theme.secondary))
        }
        Switch(
            value, onChange,
            colors = SwitchDefaults.colors(
                checkedTrackColor = Theme.accent,
                checkedThumbColor = androidx.compose.ui.graphics.Color.White,
                uncheckedTrackColor = Theme.fillStrong,
                uncheckedThumbColor = Theme.canvasRaised,
                uncheckedBorderColor = Theme.hairline,
            ),
        )
    }
}

private fun Modifier.heightIn56() = this.then(Modifier.heightIn(min = 56.dp))

@Composable
private fun LinkRow(icon: String, title: String, detail: String? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 54.dp).pressable(0.995f) { onClick() }.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Icon(sf(icon), null, tint = Theme.accent, modifier = Modifier.size(21.dp))
        Text(title, style = Theme.font(15.5f, FontWeight.Medium, Theme.text), modifier = Modifier.weight(1f))
        if (detail != null) Text(detail, style = Theme.font(14f, color = Theme.secondary))
        Icon(sf("chevron.right"), null, tint = Theme.tertiary, modifier = Modifier.size(17.dp))
    }
}

@Composable
private fun <T> ChipsRow(items: List<Pair<String, T>>, selected: T, onSelect: (T) -> Unit) {
    HRow(spacing = 8.dp, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)) { items(items) { (label, v) -> PrismChip(label, v == selected) { onSelect(v) } } }
}

@Composable
private fun Section(title: String, subtitle: String? = null, content: @Composable () -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, style = Theme.font(16f, color = Theme.text))
        if (subtitle != null) Text(subtitle, style = Theme.font(12.5f, color = Theme.secondary))
    }
    content()
}

@Composable
fun SettingsScreen(bottomInset: Dp) {
    val s = LibraryStore
    val ctx = LocalContext.current
    var confirmCache by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        DetailHeader("Ajustes")
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            item { AccessStatusCard() }
            item {
                Card("Tocando agora") {
                    Section("Estilo do Tocando agora", "Escolha como a capa aparece na tela de reprodução.") {
                        ChipsRow(listOf(PlayerSurfaceTab.ARTWORK, PlayerSurfaceTab.VINYL, PlayerSurfaceTab.CASSETTE, PlayerSurfaceTab.WAVES).map { it.raw to it }, AppModel.playerStyle) { AppModel.playerStyle = it }
                    }
                    CardDivider(false)
                    Section("Estilo das ondas") {
                        ChipsRow(VisualizerStyle.entries.map { it.title to it }, s.visualizerStyle) { s.visualizerStyle = it }
                    }
                    CardDivider(false)
                    Section("Aparência") {
                        ChipsRow(listOf("Automático" to "auto", "Claro" to "light", "Escuro" to "dark"), AppModel.appearance) { AppModel.setAppearance(ctx, it) }
                    }
                    CardDivider(false)
                    ToggleRow("sparkles", "Abertura animada", null, s.introEnabled) { s.introEnabled = it }
                }
            }
            item {
                Card("Áudio") {
                    ToggleRow("infinity", "Rádio automática", "Continua tocando músicas parecidas quando a fila acaba", AudioPlayer.autoplayRadio) { AudioPlayer.autoplayRadio = it }
                    CardDivider()
                    LinkRow("slider.vertical.3", "Equalizador (5 bandas)", s.soundProfile.raw) { AppModel.push(LumeRoute.Equalizer) }
                    AudioExtrasRows()
                    CardDivider()
                    Section("Crossfade entre faixas") {
                        ChipsRow(listOf("Desligado" to 0.0, "3 segundos" to 3.0, "6 segundos" to 6.0, "9 segundos" to 9.0), s.crossfadeSeconds) { s.crossfadeSeconds = it }
                    }
                    CardDivider(false)
                    LinkRow("moon.zzz.fill", "Timer de dormir", AudioPlayer.sleepTimerOption.takeIf { it != SleepTimerOption.OFF }?.label) { AppModel.tabletSheet = "sleep" }
                }
            }
            item {
                Card("Letras e capas") {
                    ToggleRow("photo.on.rectangle.angled", "Capas animadas", "Usa as capas em movimento do Apple Music quando existirem", s.animatedArtEnabled) { s.animatedArtEnabled = it }
                    CardDivider()
                    ToggleRow("translate", "Traduzir letras automaticamente", "Mostra a tradução em português abaixo de cada linha", s.autoTranslateLyrics) { s.autoTranslateLyrics = it }
                }
            }
            item {
                Card("Estúdio Vinil & K7") {
                    Section("Acabamento do toca-discos") { ChipsRow(TurntableFinish.entries.map { it.raw to it }, s.turntableFinish) { s.turntableFinish = it } }
                    CardDivider(false)
                    Section("Edição do disco") { ChipsRow(VinylEdition.entries.map { it.raw to it }, s.vinylEdition) { s.vinylEdition = it } }
                    CardDivider(false)
                    ToggleRow("cube", "Perspectiva 3D no Vinil", null, s.turntable3D) { s.turntable3D = it }
                    CardDivider()
                    Section("Estilo da fita K7") { ChipsRow(CassetteStyle.entries.map { it.raw to it }, s.cassetteStyle) { s.cassetteStyle = it } }
                }
            }
            item {
                Card("Tela de bloqueio") {
                    Section("Arte da tela de bloqueio", "Com o celular bloqueado aparece o disco de vinil ou a fita K7 com a capa da música. No Automático, segue o estilo do Tocando agora.") {
                        ChipsRow(LockArtStyle.entries.map { it.title to it }, s.lockArtStyle) {
                            s.lockArtStyle = it
                            com.adriano.lumemusic.audio.AudioPlayer.refreshLockScreenArtwork()
                        }
                    }
                }
            }
            item {
                Card("Biblioteca") {
                    LinkRow("sparkles", "Lume Replay · Seu Resumo") { AppModel.push(LumeRoute.Replay) }
                    CardDivider()
                    LinkRow("square.and.arrow.down", "Importar músicas") { AppModel.push(LumeRoute.ImportHub) }
                    CardDivider()
                    LinkRow("person.2", "Artistas seguidos", "${s.followedArtists.size}") { AppModel.select(com.adriano.lumemusic.data.AppTab.LIBRARY) }
                }
            }
            item {
                Card("Armazenamento & Offline") {
                    ToggleRow("airplane", "Modo offline", "Toca apenas músicas baixadas", s.offlineMode) { s.offlineMode = it }
                    CardDivider()
                    ToggleRow("arrow.down.circle", "Baixar curtidas automaticamente", null, s.autoDownloadFavorites) { s.autoDownloadFavorites = it }
                    CardDivider()
                    LinkRow("arrow.down.circle.fill", "Central de Downloads", s.offlineStorageFormatted) { AppModel.push(LumeRoute.Downloads) }
                    CardDivider()
                    LinkRow("trash", "Limpar cache de imagens e letras") { confirmCache = true }
                }
            }
            item {
                Card("Sobre") {
                    LinkRow(
                        "system.update",
                        if (UpdateController.checking) "Verificando atualizações…" else "Verificar atualizações",
                        "v${BuildConfig.VERSION_NAME}",
                    ) {
                        UpdateController.checkManual { outcome ->
                            when (outcome) {
                                UpdateCheckOutcome.Found -> {}
                                UpdateCheckOutcome.UpToDate -> AppModel.showToast("Você já está na versão mais recente (${BuildConfig.VERSION_NAME})")
                                UpdateCheckOutcome.Offline -> AppModel.showToast("Sem conexão para verificar atualizações")
                            }
                        }
                    }
                    CardDivider(false)
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("Lume Music ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", style = Theme.font(16f, FontWeight.SemiBold, Theme.text))
                        Text(Theme.credit, style = Theme.font(13.5f, color = Theme.secondary))
                        Text("Fontes: Apple Music · Deezer · YouTube Music · LRCLIB · NetEase · Letras.mus.br", style = Theme.font(12.5f, color = Theme.tertiary))
                    }
                }
            }
        }
    }
    if (confirmCache) AlertDialog(
        onDismissRequest = { confirmCache = false }, containerColor = Theme.canvasRaised, title = { Text("Limpar cache?", color = Theme.text) },
        text = { Text("Capas e letras serão baixadas de novo quando precisar. Suas músicas e playlists não são afetadas.", color = Theme.secondary) },
        confirmButton = { TextButton({
            File(DiscNet.cacheDir, "LumeMusicLyrics").deleteRecursively(); File(DiscNet.cacheDir, "img").deleteRecursively()
            confirmCache = false; AppModel.showToast("Cache limpo")
        }) { Text("Limpar", color = Theme.danger) } },
        dismissButton = { TextButton({ confirmCache = false }) { Text("Cancelar", color = Theme.secondary) } },
    )
}

private val bandLabels = listOf("60 Hz", "230 Hz", "910 Hz", "3,6 kHz", "14 kHz")

@Composable
fun EqualizerScreen(bottomInset: Dp) {
    val s = LibraryStore
    val gains = s.effectiveEQGains
    Column(Modifier.fillMaxSize()) {
        DetailHeader("Equalizador")
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = bottomInset), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Perfil de som", style = Theme.font(21f, FontWeight.Bold, Theme.text), modifier = Modifier.padding(horizontal = 20.dp))
                    HRow(spacing = 8.dp) { items(SoundProfile.entries) { p -> PrismChip(p.raw, s.soundProfile == p) { AudioPlayer.applySoundProfile(p) } } }
                    Text(s.soundProfile.subtitle, style = Theme.font(13.5f, color = Theme.secondary), modifier = Modifier.padding(horizontal = 20.dp))
                }
            }
            item {
                Card("Bandas") {
                    for (i in 0 until 5) {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).height(56.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(bandLabels[i], style = Theme.font(13.5f, FontWeight.Medium, Theme.secondary), modifier = Modifier.width(64.dp))
                            Slider(
                                value = gains[i], onValueChange = { v -> AudioPlayer.applyCustomEQ(gains.toMutableList().also { it[i] = Math.round(v * 2) / 2f }) },
                                valueRange = -12f..12f, modifier = Modifier.weight(1f),
                                colors = SliderDefaults.colors(thumbColor = Theme.rose, activeTrackColor = Theme.rose, inactiveTrackColor = Theme.fillStrong),
                            )
                            Text("%+.1f dB".format(gains[i]), style = Theme.font(13f, FontWeight.SemiBold, Theme.text), modifier = Modifier.width(62.dp))
                        }
                    }
                }
            }
            item { Box(Modifier.padding(horizontal = 20.dp)) { GlassButton("Restaurar Natural", "arrow.counterclockwise") { AudioPlayer.applySoundProfile(SoundProfile.NATURAL) } } }
            item { Text("O equalizador atua direto no áudio (5 filtros biquad), sem permissão de microfone.", style = Theme.font(12.5f, color = Theme.tertiary), modifier = Modifier.padding(horizontal = 20.dp)) }
        }
    }
}
