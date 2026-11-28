import SwiftUI

/// Ajustes › "Backup da biblioteca" (contrato 5.2 A).
struct SettingsBackupSection: View {
  @ObservedObject private var backup = LibraryBackupService.shared
  @ObservedObject private var access = AccessService.shared
  @State private var confirmRestore = false

  private var ready: Bool { backup.sessionReady }

  var body: some View {
    Section {
      Label(LibraryBackupService.lastBackupText(backup.lastBackupAt), systemImage: "clock.arrow.circlepath")
        .foregroundStyle(Theme.text)
      Button {
        Haptics.light()
        backup.message = nil
        Task { await backup.backupNow(manual: true) }
      } label: {
        row("Fazer backup agora", icon: "icloud.and.arrow.up")
      }
      .buttonStyle(.plain)
      .disabled(!ready || backup.busy)
      Button {
        Haptics.light()
        backup.message = nil
        confirmRestore = true
      } label: {
        row("Restaurar do backup", icon: "icloud.and.arrow.down")
      }
      .buttonStyle(.plain)
      .disabled(!ready || backup.busy)
      if let m = backup.message {
        Text(m)
          .font(Theme.font(13.5))
          .foregroundStyle(Theme.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    } header: {
      Text("Backup da biblioteca")
    } footer: {
      Text("Suas playlists, curtidas e artistas ficam guardados com o seu acesso. Ao levar o Vitalício para outro celular, tudo vem junto."
        + (ready ? "" : " O backup funciona quando o seu acesso está ativo."))
    }
    .listRowBackground(Theme.canvasRaised)
    .confirmationDialog("Restaurar do backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
      Button("Restaurar") { Task { await backup.restoreNow(manual: true) } }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("O que está guardado no backup é mesclado com a sua biblioteca daqui. Nada do que você tem neste celular é apagado.")
    }
  }

  private func row(_ title: String, icon: String) -> some View {
    HStack {
      Label(title, systemImage: icon).foregroundStyle(Theme.text)
      Spacer()
      if backup.busy { ProgressView().controlSize(.small) }
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .contentShape(Rectangle())
    .opacity(ready ? 1 : 0.45)
  }
}
