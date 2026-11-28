import SwiftUI

/// Ajustes › "Registrar o que eu ouço" › ListenBrainz (contrato 5.2 B).
struct SettingsScrobbleSection: View {
  @ObservedObject private var lb = ListenBrainzService.shared
  @State private var tokenText = ""
  @FocusState private var focused: Bool

  var body: some View {
    Section {
      if lb.connected {
        Toggle(isOn: $lb.enabled) {
          Label("Registrar no ListenBrainz", systemImage: "waveform.badge.mic")
        }
        LabeledContent {
          Text(lb.userName ?? "").foregroundStyle(Theme.secondary)
        } label: {
          Label("Conectado como", systemImage: "person.crop.circle.badge.checkmark")
        }
        if lb.pending > 0 {
          LabeledContent {
            Text("\(lb.pending)").foregroundStyle(Theme.secondary)
          } label: {
            Label("Aguardando envio", systemImage: "tray.and.arrow.up")
          }
        }
        Button(role: .destructive) {
          Haptics.light()
          tokenText = ""
          lb.disconnect()
        } label: {
          Label("Desconectar", systemImage: "xmark.circle")
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.danger)
      } else {
        SecureField("Cole o seu token do ListenBrainz", text: $tokenText)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($focused)
          .submitLabel(.go)
          .onSubmit { connect() }
          .frame(minHeight: 44)
        if let url = URL(string: "https://listenbrainz.org/settings/") {
          Link(destination: url) {
            Label("Pegar meu token", systemImage: "arrow.up.right.square")
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              .contentShape(Rectangle())
          }
        }
        Button {
          connect()
        } label: {
          HStack {
            Label("Conectar", systemImage: "link").foregroundStyle(Theme.text)
            Spacer()
            if lb.busy { ProgressView().controlSize(.small) }
          }
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(lb.busy || tokenText.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      if let m = lb.message {
        Text(m)
          .font(Theme.font(13.5))
          .foregroundStyle(Theme.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    } header: {
      Text("Registrar o que eu ouço")
    } footer: {
      Text("Envia ao ListenBrainz as músicas que você ouve (a faixa que começa agora e as que passam da metade). Fica desligado até você conectar. O token fica guardado com segurança no Keychain.")
    }
    .listRowBackground(Theme.canvasRaised)
  }

  private func connect() {
    focused = false
    let t = tokenText
    Task {
      await lb.connect(token: t)
      if lb.connected { tokenText = "" }
    }
  }
}
