import SwiftUI

/// Biblioteca — filtro rápido, central de downloads, Lume Replay, álbuns salvos, histórico e playlists.
struct LibraryView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @State private var showNewPlaylist = false
  @State private var newName = ""
  @State private var filterText = ""
  @State private var category: LibraryFilter = .all
  @State private var sortMode: SortMode = .recent

  enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "Tudo"
    case playlists = "Playlists"
    case albums = "Álbuns"
    case artists = "Artistas"
    case downloaded = "Baixadas"
    var id: String { rawValue }
  }

  enum SortMode: String, CaseIterable, Identifiable {
    case recent = "Recentes"
    case alphabetical = "A–Z"
    case mostTracks = "Mais faixas"
    var id: String { rawValue }
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 24) {
        header
        librarySearchBar
        filterChips
        LibraryDownloadBanner()
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && category == .all {
          shortcuts
          replayBanner
        }
        contentForFilter
      }
      .padding(.top, 6)
      .padding(.bottom, 16)
    }
    .lumeTabScroll()
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

  // MARK: Cabeçalho & Filtro

  private var header: some View {
    HStack(spacing: 10) {
      Text("Biblioteca")
        .font(Theme.font(34, .bold))
        .foregroundStyle(Theme.text)
      Spacer()
      Menu {
        ForEach(SortMode.allCases) { m in
          Button {
            Haptics.selection()
            sortMode = m
          } label: {
            if sortMode == m { Label(m.rawValue, systemImage: "checkmark") }
            else { Text(m.rawValue) }
          }
        }
      } label: {
        Image(systemName: "arrow.up.arrow.down")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(width: 44, height: 44)
          .glassCircle(interactive: true)
      }
      GlassIconButton(systemName: "plus", size: 44) { showNewPlaylist = true }
        .accessibilityLabel("Nova playlist")
      GlassIconButton(systemName: "square.and.arrow.down", size: 44) { app.push(.importHub) }
        .accessibilityLabel("Importar músicas")
    }
    .glassGroup()
    .padding(.horizontal, 20)
  }

  private var librarySearchBar: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Theme.secondary)
      TextField("Filtrar playlists, álbuns e músicas", text: $filterText)
        .font(Theme.font(15))
        .foregroundStyle(Theme.text)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .onSubmit { LumeKeyboard.dismiss() }
      if !filterText.isEmpty {
        Button { filterText = "" } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(Theme.tertiary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Limpar filtro")
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 42)
    .glassCapsule()
    .padding(.horizontal, 20)
  }

  private var filterChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(LibraryFilter.allCases) { f in
          PrismChip(title: f.rawValue, active: category == f) { category = f }
        }
      }
      .padding(.horizontal, 20)
    }
    .scrollClipDisabled()
  }

  private var replayBanner: some View {
    Button {
      Haptics.light()
      app.push(.replay)
    } label: {
      HStack(spacing: 14) {
        Image(systemName: "sparkles")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(Theme.onPrism)
          .frame(width: 44, height: 44)
          .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.prismDiagonal))
        VStack(alignment: .leading, spacing: 2) {
          Text("Lume Replay · Seu Resumo")
            .font(Theme.font(15.5, .bold))
            .foregroundStyle(Theme.text)
          let rep = store.replaySummary
          Text(rep.totalPlays > 0 ? "\(rep.totalPlays) \(rep.totalPlays == 1 ? "reprodução" : "reproduções") · \(rep.totalMinutes) min ouvindo" : "Descubra suas mais ouvidas e artistas favoritos")
            .font(Theme.font(12.5))
            .foregroundStyle(Theme.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Theme.tertiary)
      }
      .padding(12)
      .glass(20, interactive: true)
      .padding(.horizontal, 20)
    }
    .buttonStyle(PressableStyle(scale: 0.985))
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
               count: store.downloadedTracks.count, colors: [Theme.sky, Theme.mint], route: .downloads),
      Shortcut(id: "alb", icon: "square.stack.fill", title: "Álbuns salvos", count: store.savedAlbums.count,
               colors: [Theme.lavender, Theme.rose], route: .albums("Álbuns salvos", store.savedAlbums)),
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

  // MARK: Conteúdo filtrado

  @ViewBuilder
  private var contentForFilter: some View {
    switch category {
    case .all:
      recent
      savedAlbumsSection
      playlists
    case .playlists:
      playlists
    case .albums:
      savedAlbumsSection
      if filteredAlbums.isEmpty {
        EmptyStateView(icon: "square.stack", title: "Nenhum álbum salvo", message: "Abra qualquer álbum e toque em salvar para vê-lo aqui.")
      }
    case .artists:
      let list = filteredArtists
      if list.isEmpty {
        EmptyStateView(icon: "music.mic", title: "Nenhum artista encontrado", message: "Ouça ou siga artistas para montar sua coleção.")
      } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 22) {
          ForEach(list) { a in
            ArtistBubble(name: a.name, pictureURL: a.pictureURL, deezerId: a.deezerId, size: 96)
          }
        }
        .padding(.horizontal, 16)
      }
    case .downloaded:
      let tracks = filteredDownloaded
      if tracks.isEmpty {
        EmptyStateView(icon: "arrow.down.circle", title: "Nenhuma música baixada", message: "Baixe suas músicas ou playlists favoritas para ouvir sem internet.")
      } else {
        VStack(alignment: .leading, spacing: 12) {
          SectionHeader(title: "Baixadas (\(tracks.count))", actionLabel: "Gerenciar") {
            app.push(.downloads)
          }
          VStack(spacing: 0) {
            ForEach(tracks) { tr in TrackRow(track: tr, queue: tracks) }
          }
          .padding(.horizontal, 20)
        }
      }
    }
  }

  private var q: String { filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

  private var filteredPlaylists: [MusicPlaylist] {
    var list = store.playlists
    if !q.isEmpty {
      list = list.filter { $0.name.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }
    }
    switch sortMode {
    case .recent: return list
    case .alphabetical: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    case .mostTracks: return list.sorted { $0.trackIds.count > $1.trackIds.count }
    }
  }

  private var filteredAlbums: [AlbumShowcase] {
    let list = store.savedAlbums
    if q.isEmpty { return list }
    return list.filter { $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q) }
  }

  private var filteredArtists: [ArtistInfo] {
    let names = store.topListenedArtists.filter { q.isEmpty || $0.lowercased().contains(q) }
    return names.map { ArtistInfo(id: "lib_" + $0, name: $0, pictureURL: "", deezerId: nil, fans: nil, rank: nil) }
  }

  private var filteredDownloaded: [Track] {
    let list = store.downloadedTracks
    if q.isEmpty { return list }
    return list.filter { $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q) }
  }

  @ViewBuilder
  private var recent: some View {
    let tracks = Array(store.recentTracks.prefix(12))
    if !tracks.isEmpty && q.isEmpty {
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

  @ViewBuilder
  private var savedAlbumsSection: some View {
    if !filteredAlbums.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Álbuns salvos", actionLabel: "Ver tudo") {
          app.push(.albums("Álbuns salvos", filteredAlbums))
        }
        HRow {
          ForEach(filteredAlbums) { a in AlbumTile(album: a, width: 146, showDate: true) }
        }
      }
    }
  }

  private var playlists: some View {
    let list = filteredPlaylists
    return VStack(alignment: .leading, spacing: 14) {
      SectionHeader(title: "Suas playlists", subtitle: list.isEmpty ? nil : "\(list.count) \(list.count == 1 ? "playlist" : "playlists")")
      if list.isEmpty {
        VStack(spacing: 14) {
          EmptyStateView(
            icon: "music.note.list",
            title: q.isEmpty ? "Nenhuma playlist ainda" : "Nenhuma playlist encontrada",
            message: q.isEmpty ? "Crie uma playlist ou traga as suas do Apple Music, Spotify e YouTube." : "Tente outro termo para filtrar."
          )
          if q.isEmpty {
            PrismButton(title: "Importar", systemImage: "square.and.arrow.down", height: 48) { app.push(.importHub) }
              .frame(maxWidth: 220)
          }
        }
        .frame(maxWidth: .infinity)
      } else {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 22) {
          ForEach(list) { pl in
            PlaylistCard(playlist: pl)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }
}

// MARK: - Banner isolado de downloads (não re-renderiza a Biblioteca inteira a cada tick)

private struct LibraryDownloadBanner: View {
  @ObservedObject private var downloads = DownloadManager.shared

  var body: some View {
    if downloads.pendingCount > 0 || !downloads.failedItems.isEmpty {
      Button {
        Haptics.light()
        AppModel.shared.push(.downloads)
      } label: {
        HStack(spacing: 12) {
          Image(systemName: downloads.pendingCount > 0 ? "arrow.down.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(downloads.pendingCount > 0 ? Theme.accent : Theme.danger)
          VStack(alignment: .leading, spacing: 2) {
            if downloads.pendingCount > 0 {
              Text(downloads.paused ? "Downloads pausados (\(downloads.pendingCount))" : "Baixando \(downloads.pendingCount) \(downloads.pendingCount == 1 ? "música" : "músicas")")
                .font(Theme.font(14.5, .semibold))
                .foregroundStyle(Theme.text)
              ProgressView(value: downloads.overallProgress).tint(Theme.accent)
            } else {
              Text("\(downloads.failedItems.count) downloads falharam")
                .font(Theme.font(14.5, .semibold))
                .foregroundStyle(Theme.text)
              Text("Toque para tentar novamente")
                .font(Theme.font(12.5))
                .foregroundStyle(Theme.secondary)
            }
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.tertiary)
        }
        .padding(14)
        .glass(20, interactive: true)
        .padding(.horizontal, 20)
      }
      .buttonStyle(PressableStyle(scale: 0.98))
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
      Button {
        let tracks = store.tracks(in: playlist)
        if let first = tracks.first { AudioPlayer.shared.play(first, in: tracks, context: playlist.name) }
      } label: { Label("Tocar", systemImage: "play.fill") }
      Button {
        DownloadManager.shared.downloadPlaylist(playlist)
      } label: { Label("Baixar playlist", systemImage: "arrow.down.circle") }
      Button(role: .destructive) {
        store.deletePlaylist(playlist.id)
      } label: { Label("Excluir playlist", systemImage: "trash") }
    }
  }
}

/// Capa de playlist: imagem própria ou mosaico 2×2 com as capas das primeiras faixas.
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
