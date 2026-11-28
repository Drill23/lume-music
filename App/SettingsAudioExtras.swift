import SwiftUI

/// Ajustes › Áudio (5.2): volume igual entre as músicas, limitador de pico (automático) e pular silêncio.
/// Fica numa View própria para a SettingsView só precisar de uma linha.
struct SettingsAudioExtras: View {
  @AppStorage(AudioPrefs.normalizeKey) private var normalize = true
  @AppStorage(AudioPrefs.skipSilenceKey) private var skipSilence = false

  var body: some View {
    Section {
      Toggle(isOn: $normalize) {
        Label("Volume igual entre as músicas", systemImage: "speaker.wave.2.circle")
      }
      Toggle(isOn: $skipSilence) {
        Label("Pular silêncio", systemImage: "forward.end.alt")
      }
    } header: {
      Text("Áudio")
    } footer: {
      Text("O volume igual deixa todas as faixas com a mesma força, sem você mexer no volume. Um limitador de pico protege contra distorção quando o som é aumentado. Pular silêncio corta só o vazio do começo e do fim de cada faixa, nunca as pausas no meio da música.")
    }
    .listRowBackground(Theme.canvasRaised)
    .onChange(of: normalize) { _, _ in
      Haptics.selection()
      AudioPlayer.shared.audioPrefsChanged()
    }
    .onChange(of: skipSilence) { _, _ in
      Haptics.selection()
      AudioPlayer.shared.audioPrefsChanged()
    }
  }
}
