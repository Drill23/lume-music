import SwiftUI

/// Biblioteca — atalhos, tocadas recentemente e playlists. Raiz da aba (a barra de navegação fica escondida).
struct LibraryView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @State private var showNewPlaylist = false
  @State private var newName = ""

  var body: some View {
    ScrollView(showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 28) {
        header
        shortcuts
        recent
        playlists
      }
      .padding(.top, 6)
    }
    .background(backdrop)
    .alert("Nova playlist", isPresented: $showNewPlaylist) {
      TextField("Nome da playlist", text: $newName)
      Button("Criar") {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
          let pl = store.createPlaylist(name: name)
          Haptics.success()
          app.push(.playlist(pl.id))
        }
        newName = ""
      }
      Button("Cancelar", role: .cancel) { newName = "" }
    } message: {
      Text("Dê um nome para a sua nova playlist.")
    }
  }

  private var backdrop: some View {
    ZStack(alignment: .top) {
      Theme.canvas
      LinearGradient(
        colors: [Theme.rose.opacity(0.12), Theme.lavender.opacity(0.05), .clear],
        startPoint: .top, endPoint: .bottom
      )
      .frame(height: 360)
      .blur(radius: 20)
    }
    .ignoresSafeArea()
  }

  // MARK: Cabeçalho

  private var header: some View {
    HStack(spacing: 12) {
      Text("Biblioteca")
        .font(Theme.font(34, .bold))
        .foregroundStyle(Theme.text)
      Spacer()
      GlassIconButton(systemName: "plus", size: 42) { showNewPlaylist = true }
        .accessibilityLabel("Nova playlist")
      GlassIconButton(systemName: "square.and.arrow.down", size: 42) { app.push(.importHub) }
        .accessibilityLabel("Importar músicas")
    }
    .glassGroup()
    .padding(.horizontal, 20)
  }

  // MARK: Atalhos

  private struct Shortcut: Identifiable {
    let id: String
    let icon: String
    let title: String
    var subtitle: String? = nil
    let count: Int
    let colors: [Color]
    let route: LumeRoute
  }

  private var shortcutItems: [Shortcut] {
    let artists = store.topListenedArtists
    return [
      Shortcut(id: "fav", icon: "heart.fill", title: "Curtidas", count: store.favoriteIds.count,
               colors: [Theme.rose, Theme.peach], route: .tracks("Curtidas", store.favoriteTracks)),
      Shortcut(id: "dl", icon: "arrow.down.circle.fill", title: "Baixadas", subtitle: store.offlineStorageFormatted,
               count: store.downloadedTracks.count, colors: [Theme.sky, Theme.mint], route: .tracks("Baixadas", store.downloadedTracks)),
      Shortcut(id: "top", icon: "chart.bar.fill", title: "Mais ouvidas", count: store.mostPlayedTracks.count,
               colors: [Theme.peach, Theme.rose], route: .tracks("Mais ouvidas", store.mostPlayedTracks)),
      Shortcut(id: "hist", icon: "clock.fill", title: "Histórico", count: store.recentIds.count,
               colors: [Theme.lavender, Theme.sky], route: .tracks("Histórico", store.recentTracks)),
      Shortcut(id: "art", icon: "music.mic", title: "Artistas", count: artists.count,
               colors: [Theme.rose, Theme.lavender],
               route: .artists("Seus artistas", artists.map { ArtistInfo(id: "lib_" + $0, name: $0, pictureURL: "", deezerId: nil, fans: nil, rank: nil) })),
    ]
  }

  private var shortcuts: some View {
    let items = shortcutItems
    return VStack(spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
        Button {
          Haptics.light()
          app.push(item.route)
        } label: {
          HStack(spacing: 14) {
            Image(systemName: item.icon)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 30, height: 30)
              .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .fill(LinearGradient(colors: item.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
              )
              .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 0.6))
            VStack(alignment: .leading, spacing: 1) {
              Text(item.title)
                .font(Theme.font(17))
                .foregroundStyle(Theme.text)
              if let sub = item.subtitle {
                Text(sub)
                  .font(Theme.font(12.5))
                  .foregroundStyle(Theme.secondary)
              }
            }
            Spacer(minLength: 8)
            Text("\(item.count)")
              .font(Theme.font(16))
              .foregroundStyle(Theme.secondary)
              .monospacedDigit()
            Image(systemName: "chevron.right")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Theme.tertiary)
          }
          .padding(.horizontal, 16)
          .frame(minHeight: 54)
          .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.985))
        if idx < items.count - 1 {
          Divider().overlay(Theme.hairline).padding(.leading, 60)
        }
      }
    }
    .padding(.vertical, 4)
    .glass(24)
    .padding(.horizontal, 20)
  }

  // MARK: Tocadas recentemente

  @ViewBuilder
  private var recent: some View {
    let tracks = Array(store.recentTracks.prefix(12))
    if !tracks.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Tocadas recentemente", actionLabel: "Histórico") {
          app.push(.tracks("Histórico", store.recentTracks))
        }
        HRow(spacing: 12) {
          ForEach(tracks) { tr in PlayCard(track: tr, queue: tracks) }
        }
      }
    }
  }

  // MARK: Playlists

  private var playlists: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeader(title: "Suas playlists", subtitle: store.playlists.isEmpty ? nil : "\(store.playlists.count) \(store.playlists.count == 1 ? "playlist" : "playlists")")
      if store.playlists.isEmpty {
        VStack(spacing: 14) {
          EmptyStateView(
            icon: "music.note.list",
            title: "Nenhuma playlist ainda",
            message: "Crie uma playlist ou traga as suas do Apple Music, Spotify e YouTube."
          )
          PrismButton(title: "Importar", systemImage: "square.and.arrow.down", height: 48) { app.push(.importHub) }
            .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity)
      } else {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 22) {
          ForEach(store.playlists) { pl in
            PlaylistCard(playlist: pl)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }
}

// MARK: - Cartão de playlist

struct PlaylistCard: View {
  let playlist: MusicPlaylist
  @ObservedObject private var store = LibraryStore.shared

  var body: some View {
    Button {
      Haptics.light()
      AppModel.shared.push(.playlist(playlist.id))
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        PlaylistCover(playlist: playlist, cornerRadius: 14)
          .lumeShadow(10, y: 6, opacity: 0.5)
        VStack(alignment: .leading, spacing: 2) {
          Text(playlist.name)
            .font(Theme.font(14.5, .medium))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
          HStack(spacing: 6) {
            Text("\(playlist.trackIds.count) \(playlist.trackIds.count == 1 ? "música" : "músicas")")
              .font(Theme.font(12.5))
              .foregroundStyle(Theme.secondary)
              .lineLimit(1)
            Text(playlist.sourceBadge)
              .font(Theme.font(10.5, .semibold))
              .foregroundStyle(Theme.secondary)
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(Capsule().fill(Theme.fillStrong))
              .lineLimit(1)
          }
        }
      }
    }
    .buttonStyle(PressableStyle())
    .contextMenu {
      Button(role: .destructive) {
        store.deletePlaylist(playlist.id)
      } label: { Label("Excluir playlist", systemImage: "trash") }
    }
  }
}

/// Capa de playlist: imagem própria ou mosaico 2×2 com as capas das primeiras faixas. Quadrada, ocupa a largura disponível.
struct PlaylistCover: View {
  let playlist: MusicPlaylist
  var cornerRadius: CGFloat = 14
  @ObservedObject private var store = LibraryStore.shared

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    Color.clear
      .aspectRatio(1, contentMode: .fit)
      .overlay { content }
      .clipShape(shape)
      .overlay(shape.stroke(Theme.hairline, lineWidth: 0.5))
  }

  @ViewBuilder
  private var content: some View {
    let tracks = Array(store.tracks(in: playlist).prefix(4))
    if !playlist.artworkURL.isEmpty {
      ArtworkImage(url: playlist.artworkURL, cornerRadius: 0, maxPixel: 500)
    } else if tracks.count >= 4 {
      VStack(spacing: 1) {
        HStack(spacing: 1) { cell(tracks[0]); cell(tracks[1]) }
        HStack(spacing: 1) { cell(tracks[2]); cell(tracks[3]) }
      }
    } else if let first = tracks.first {
      TrackArtwork(track: first, cornerRadius: 0, maxPixel: 500)
    } else {
      ZStack {
        Theme.prismDiagonal.opacity(0.55)
        Image(systemName: "music.note.list")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(.white.opacity(0.9))
      }
    }
  }

  private func cell(_ t: Track) -> some View {
    Color.clear
      .aspectRatio(1, contentMode: .fit)
      .overlay { TrackArtwork(track: t, cornerRadius: 0, maxPixel: 260) }
      .clipped()
  }
}
