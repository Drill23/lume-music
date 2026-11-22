import SwiftUI

/// Importar músicas — Apple Music do iPhone, links (Spotify, YouTube, Apple, Amazon) e listas de texto/M3U.
struct ImportView: View {
  @ObservedObject private var store = LibraryStore.shared
  @Environment(\.dismiss) private var dismiss

  @State private var linkText = ""
  @State private var rawListText = ""
  @State private var rawListName = ""
  @State private var busy = false
  @State private var statusMsg: String?
  @State private var isError = false

  private var linkEmpty: Bool { linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  private var listEmpty: Bool { rawListText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    ScrollView(showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 18) {
        Text("Traga suas playlists e músicas de outros serviços para a Lume.")
          .font(Theme.font(15))
          .foregroundStyle(Theme.secondary)
          .padding(.horizontal, 4)

        appleMusicCard
        linkCard
        listCard

        if let msg = statusMsg { messageCard(msg) }
      }
      .padding(.horizontal, 20)
      .padding(.top, 4)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(Theme.canvas.ignoresSafeArea())
    .navigationTitle("Importar músicas")
    .navigationBarTitleDisplayMode(.large)
  }

  // MARK: Cartões

  private func cardHeader(icon: String, title: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(Theme.onPrism)
        .frame(width: 44, height: 44)
        .background(Circle().fill(Theme.prismDiagonal))
        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.8))
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(Theme.font(17, .semibold))
          .foregroundStyle(Theme.text)
        Text(text)
          .font(Theme.font(13.5))
          .foregroundStyle(Theme.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  private var appleMusicCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      cardHeader(
        icon: "music.note.house.fill",
        title: "Apple Music deste iPhone",
        text: "Traz suas músicas e playlists que já estão neste iPhone, com um toque."
      )
      PrismButton(title: busy ? "Importando…" : "Importar da Biblioteca", systemImage: busy ? nil : "square.and.arrow.down", height: 48) {
        Task { await runAppleMusicImport() }
      }
      .disabled(busy)
      .opacity(busy ? 0.6 : 1)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(24)
  }

  private var linkCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      cardHeader(
        icon: "link",
        title: "Por link",
        text: "Cole o link de uma playlist ou álbum público do Spotify, YouTube, Apple Music ou Amazon Music."
      )
      HStack(spacing: 8) {
        Image(systemName: "link").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondary)
        TextField("Cole o link aqui", text: $linkText)
          .font(Theme.font(15))
          .foregroundStyle(Theme.text)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
        if !linkText.isEmpty {
          Button {
            Haptics.light()
            linkText = ""
          } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
          }
          .accessibilityLabel("Limpar link")
        }
      }
      .padding(.horizontal, 16)
      .frame(height: 48)
      .glassCapsule()
      PrismButton(title: busy ? "Importando…" : "Importar do link", systemImage: busy ? nil : "arrow.down.circle", height: 48) {
        Task { await runLinkImport() }
      }
      .disabled(busy || linkEmpty)
      .opacity(busy || linkEmpty ? 0.5 : 1)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(24)
  }

  private var listCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      cardHeader(
        icon: "text.badge.plus",
        title: "Lista de texto ou M3U",
        text: "Escreva ou cole uma lista com uma música por linha, no formato Artista - Música."
      )
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
        Task { await runTextImport() }
      }
      .disabled(busy || listEmpty)
      .opacity(busy || listEmpty ? 0.5 : 1)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(24)
  }

  private func messageCard(_ msg: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(isError ? Theme.danger : Theme.ok)
      Text(msg)
        .font(Theme.font(14, .medium))
        .foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(20, tint: (isError ? Theme.danger : Theme.ok).opacity(0.35))
  }

  // MARK: Lógica (porta do ImportHubView antigo)

  private func runAppleMusicImport() async {
    busy = true; statusMsg = nil; isError = false
    do {
      let packs = try await ImportService.shared.importFromLocalAppleMusic()
      var total = 0
      for p in packs {
        store.createPlaylist(name: p.playlistName, sourceBadge: p.sourceBadge, artworkURL: p.artworkURL, tracks: p.tracks)
        total += p.tracks.count
      }
      Haptics.success()
      AppModel.shared.showToast("Importadas \(packs.count) playlists (\(total) músicas) do Apple Music")
      busy = false
      dismiss()
      return
    } catch {
      isError = true
      statusMsg = error.localizedDescription
    }
    busy = false
  }

  private func runLinkImport() async {
    busy = true; statusMsg = nil; isError = false
    do {
      let res = try await ImportService.shared.importFromURL(linkText)
      store.createPlaylist(name: res.playlistName, sourceBadge: res.sourceBadge, artworkURL: res.artworkURL, tracks: res.tracks)
      Haptics.success()
      AppModel.shared.showToast("Importada “\(res.playlistName)” (\(res.tracks.count) músicas)")
      busy = false
      dismiss()
      return
    } catch {
      isError = true
      statusMsg = error.localizedDescription
    }
    busy = false
  }

  private func runTextImport() async {
    statusMsg = nil; isError = false
    let res = await ImportService.shared.importFromText(rawListText, name: rawListName)
    guard !res.tracks.isEmpty else {
      isError = true
      statusMsg = "Cole pelo menos uma música na lista acima."
      return
    }
    store.createPlaylist(name: res.playlistName, sourceBadge: res.sourceBadge, tracks: res.tracks)
    Haptics.success()
    AppModel.shared.showToast("Criada “\(res.playlistName)” com \(res.tracks.count) músicas")
    dismiss()
  }
}
