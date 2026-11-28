package com.adriano.lumemusic.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.audio.AudioPrefs
import com.adriano.lumemusic.ui.pressable
import com.adriano.lumemusic.ui.theme.Theme
import com.adriano.lumemusic.ui.theme.sf

/**
 * Linhas extras do cartão Áudio (logo abaixo do equalizador): Volume igual entre as músicas, Limitador de pico
 * (informativo: é automático) e Pular silêncio. Chamado de dentro do cartão em SettingsScreens.
 */
@Composable
fun AudioExtrasRows() {
    AudioDivider()
    AudioToggleRow(
        "speaker.wave.3.fill", "Volume igual entre as músicas",
        "Ajusta cada faixa para o mesmo nível, sem sustos entre uma música e outra",
        AudioPrefs.normalize,
    ) { AudioPlayer.setNormalizeVolume(it) }
    AudioDivider()
    AudioInfoRow(
        "waveform", "Limitador de pico", "Automático",
        "Evita distorção quando o volume igual ou o equalizador aumentam o som",
    )
    AudioDivider()
    AudioToggleRow(
        "forward.fill", "Pular silêncio",
        "Pula o silêncio do começo e do fim de cada música; pausas no meio nunca são puladas",
        AudioPrefs.skipSilence,
    ) { AudioPlayer.setSkipSilence(it) }
}

@Composable
private fun AudioDivider() {
    HorizontalDivider(Modifier.padding(start = 52.dp, end = 16.dp), thickness = 0.5.dp, color = Theme.hairline)
}

@Composable
private fun AudioToggleRow(icon: String, title: String, subtitle: String?, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).pressable(0.995f) { onChange(!value) }.padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(sf(icon), null, tint = Theme.accent, modifier = Modifier.size(21.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = Theme.font(15.5f, FontWeight.Medium, Theme.text))
            if (subtitle != null) Text(subtitle, style = Theme.font(12.5f, color = Theme.secondary))
        }
        Switch(
            value, onChange,
            colors = SwitchDefaults.colors(
                checkedTrackColor = Theme.accent,
                checkedThumbColor = Color.White,
                uncheckedTrackColor = Theme.fillStrong,
                uncheckedThumbColor = Theme.canvasRaised,
                uncheckedBorderColor = Theme.hairline,
            ),
        )
    }
}

@Composable
private fun AudioInfoRow(icon: String, title: String, detail: String, subtitle: String?) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(sf(icon), null, tint = Theme.accent, modifier = Modifier.size(21.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = Theme.font(15.5f, FontWeight.Medium, Theme.text))
            if (subtitle != null) Text(subtitle, style = Theme.font(12.5f, color = Theme.secondary))
        }
        Text(detail, style = Theme.font(14f, color = Theme.secondary))
    }
}
