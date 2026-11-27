import SwiftUI

/// Importar músicas — Apple Music do iPhone (1 toque), links de Spotify / Deezer / YouTube Music / Amazon / Tidal,
/// arquivos CSV/M3U/TXT e listas de texto. Usa o mesmo painel do onboarding (`ImportHubPanel`).
struct ImportView: View {
  @StateObject private var coordinator = ImportCoordinator()

  @State private var rawListText = ""
  @State private var rawListName = ""
  @State private var showList = false

  private var listEmpty: Bool { rawListText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    ScrollView(showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 18) {
        Text("Traga suas playlists e músicas de outros serviços para a Lume.")
          .font(Theme.font(15))
          .foregroundStyle(Theme.secondary)
          .padding(.horizontal, 4)

        ImportHubPanel(coordinator: coordinator)

        if coordinator.phase == .idle { listCard }
      }
      .padding(.horizontal, 20)
      .padding(.top, 4)
      .padding(.bottom, 24)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(Theme.canvas.ignoresSafeArea())
    .navigationTitle("Importar músicas")
    .navigationBarTitleDisplayMode(.large)
    .onChange(of: coordinator.importedTracks) { _, new in
      if new > 0 { AppModel.shared.showToast("\(new) músicas importadas para a sua biblioteca") }
    }
  }

  // MARK: Lista de texto

  private var listCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Button {
        Haptics.light()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showList.toggle() }
      } label: {
        HStack(spacing: 14) {
          Image(systemName: "text.badge.plus")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Theme.onPrism)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.prismDiagonal))
            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.8))
          VStack(alignment: .leading, spacing: 3) {
            Text("Lista de texto")
              .font(Theme.font(17, .semibold)).foregroundStyle(Theme.text)
            Text("Uma música por linha, no formato Artista - Música.")
              .font(Theme.font(13.5)).foregroundStyle(Theme.secondary)
              .multilineTextAlignment(.leading)
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.down")
            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.tertiary)
            .rotationEffect(.degrees(showList ? 180 : 0))
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if showList {
        TextField("Nome da playlist", text: $rawListName)
          .font(Theme.font(15))
          .foregroundStyle(Theme.text)
          .padding(.horizontal, 16)
          .frame(height: 48)
          .glassCapsule()
        TextEditor(text: $rawListText)
          .font(Theme.font(14))
          .foregroundStyle(Theme.text)
          .scrollContentBackground(.hidden)
          .frame(height: 120)
          .padding(10)
          .glass(18)
          .overlay(alignment: .topLeading) {
            if rawListText.isEmpty {
              Text("Uma música por linha:\nArtista - Música\nOutro Artista - Outra Música")
                .font(Theme.font(13.5))
                .foregroundStyle(Theme.tertiary)
                .padding(.horizontal, 15)
                .padding(.vertical, 18)
                .allowsHitTesting(false)
            }
          }
        GlassButton(title: "Criar playlist da lista", systemImage: "music.note.list", height: 48) {
          coordinator.runText(rawListText, name: rawListName)
          rawListText = ""; rawListName = ""; showList = false
        }
        .disabled(listEmpty)
        .opacity(listEmpty ? 0.5 : 1)
        .transition(.opacity)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(24)
  }
}
