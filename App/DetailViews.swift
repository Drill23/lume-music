import SwiftUI

// MARK: - Helpers compartilhados das telas de detalhe

enum DetailFormat {
  /// "41 min" ou "1 h 12 min". nil se não houver duração conhecida.
  static func duration(_ tracks: [Track]) -> String? {
    let total = tracks.reduce(0) { $0 + $1.duration }
    guard total > 0 else { return nil }
    let minutes = Int((total / 60).rounded())
    if minutes >= 60 { return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min" }
    return "\(max(1, minutes)) min"
  }

  static func songCount(_ n: Int) -> String { "\(n) \(n == 1 ? "música" : "músicas")" }

  /// "2,1 mi de fãs", "850 mil fãs".
  static func fans(_ n: Int) -> String {
    if n >= 1_000_000 {
      var s = String(format: "%.1f", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",")
      if s.hasSuffix(",0") { s.removeLast(2) }
      return "\(s) mi de fãs"
    }
    if n >= 1000 { return "\(n / 1000) mil fãs" }
    return "\(n) \(n == 1 ? "fã" : "fãs")"
  }

  /// "21 de novembro de 2026" a partir de "2026-11-21".
  private static let isoDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private static let brLongFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "d 'de' MMMM 'de' yyyy"
    return f
  }()

  static func longDate(_ iso: String?) -> String? {
    guard let iso, iso.count >= 10,
          let d = isoDayFormatter.date(from: String(iso.prefix(10))) else { return nil }
    return brLongFormatter.string(from: d)
  }
}

/// Botões "Tocar" e "Aleatório" usados em álbuns, playlists e listas.
struct PlayShuffleBar: View {
  let tracks: [Track]
  var context: String? = nil

  var body: some View {
    HStack(spacing: 12) {
      PrismButton(title: "Tocar", systemImage: "play.fill") {
        guard let first = tracks.first else { return }
        AudioPlayer.shared.shuffleEnabled = false
        AudioPlayer.shared.play(first, in: tracks, context: context)
      }
      GlassButton(title: "Aleatório", systemImage: "shuffle") {
        guard let pick = tracks.randomElement() else { return }
        AudioPlayer.shared.shuffleEnabled = true
        AudioPlayer.shared.play(pick, in: tracks, context: context)
      }
    }
    .glassGroup()
    .disabled(tracks.isEmpty)
    .opacity(tracks.isEmpty ? 0.5 : 1)
  }
}

private struct TrackSkeletonRows: View {
  var count: Int = 6
  var body: some View {
    VStack(spacing: 14) {
      ForEach(0..<count, id: \.self) { _ in
        HStack(spacing: 12) {
          SkeletonBlock(width: 50, height: 50, radius: 8)
          VStack(alignment: .leading, spacing: 6) {
            SkeletonBlock(width: 170, height: 14, radius: 6)
            SkeletonBlock(width: 110, height: 12, radius: 6)
          }
          Spacer()
        }
      }
    }
  }
}

// MARK: - Álbum

struct AlbumView: View {
  let album: AlbumShowcase
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @State private var tracks: [Track]
  @State private var loading: Bool
  @State private var palette: ArtworkPalette = .fallback

  init(album: AlbumShowcase) {
    self.album = album
    _tracks = State(initialValue: album.tracks)
    _loading = State(initialValue: album.tracks.isEmpty)
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(spacing: 0) {
        header
        actions
        trackList
        footer
      }
      .padding(.bottom, 20)
    }
    .lumeTabScroll()
    .background { backdrop }
    .lumeDetailChrome(title: album.title, threshold: 290)
    .task {
      let found = await DiscoveryService.shared.albumTracks(album)
      if !found.isEmpty { tracks = found }
      loading = false
    }
    .task(id: album.artworkURL) {
      palette = await ArtworkColorExtractor.shared.palette(for: album.artworkURL)
    }
  }

  private var backdrop: some View {
    VStack(spacing: 0) {
      AmbientMeshBackground(palette: palette, artworkURL: album.artworkURL, animate: false)
        .frame(height: 520)
        .mask(
          LinearGradient(colors: [.black, .black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
        )
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Theme.canvas)
    .ignoresSafeArea()
  }

  private var header: some View {
    VStack(spacing: 6) {
      ArtworkImage(url: album.artworkURL, cornerRadius: 14, maxPixel: 800)
        .frame(width: 250, height: 250)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.32), radius: 24, y: 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
      Text(album.title)
        .font(Theme.font(24, .bold))
        .foregroundStyle(Theme.text)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .padding(.horizontal, 28)
      Button {
        Haptics.light()
        app.push(.artist(LibraryStore.mainArtist(album.artist), nil))
      } label: {
        Text(album.artist)
          .font(Theme.font(18, .semibold))
          .foregroundStyle(Theme.accent)
          .lineLimit(1)
      }
      .buttonStyle(PressableStyle(scale: 0.96))
      Text(metaLine)
        .font(Theme.font(13.5))
        .foregroundStyle(Theme.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
    }
    .frame(maxWidth: .infinity)
  }

  private var metaLine: String {
    var parts: [String] = [album.kind ?? "Álbum"]
    let year = album.year.isEmpty ? String((album.releaseDate ?? "").prefix(4)) : album.year
    if !year.isEmpty { parts.append(year) }
    if !tracks.isEmpty { parts.append(DetailFormat.songCount(tracks.count)) }
    if let d = DetailFormat.duration(tracks) { parts.append(d) }
    return parts.joined(separator: " · ")
  }

  private var actions: some View {
    let saved = store.isAlbumSaved(album.id)
    let downloadedCount = tracks.filter { store.isDownloaded($0.id) }.count
    let allDownloaded = !tracks.isEmpty && downloadedCount == tracks.count
    return VStack(spacing: 16) {
      PlayShuffleBar(tracks: tracks, context: album.title)
      HStack(spacing: 14) {
        GlassIconButton(systemName: allDownloaded ? "checkmark.circle.fill" : "arrow.down.circle", size: 46, foreground: allDownloaded ? Theme.ok : Theme.text) {
          downloadAll()
        }
        .accessibilityLabel("Baixar todas")
        GlassIconButton(systemName: saved ? "heart.fill" : "plus.circle", size: 46, foreground: saved ? Theme.rose : Theme.text) {
          saveToLibrary()
        }
        .accessibilityLabel(saved ? "Remover álbum salvo" : "Salvar álbum na biblioteca")
      }
      .glassGroup()
      .disabled(tracks.isEmpty)
      .opacity(tracks.isEmpty ? 0.5 : 1)
      if downloadedCount > 0 && !allDownloaded {
        Text("\(downloadedCount) de \(tracks.count) baixadas")
          .font(Theme.font(12))
          .foregroundStyle(Theme.secondary)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 20)
  }

  @ViewBuilder
  private var trackList: some View {
    VStack(alignment: .leading, spacing: 0) {
      if loading {
        TrackSkeletonRows()
      } else if tracks.isEmpty {
        EmptyStateView(icon: "music.note.list", title: "Faixas indisponíveis", message: "Não foi possível carregar as músicas deste lançamento agora. Tente de novo mais tarde.")
      } else {
        ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, tr in
          TrackRow(track: tr, rank: idx + 1, queue: tracks, showArtwork: false)
          if idx < tracks.count - 1 {
            Divider().overlay(Theme.hairline).padding(.leading, 36)
          }
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
  }

  @ViewBuilder
  private var footer: some View {
    if let date = DetailFormat.longDate(album.releaseDate) {
      Text("Lançado em \(date)")
        .font(Theme.font(12.5))
        .foregroundStyle(Theme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }
  }

  private func downloadAll() {
    let pending = tracks.filter { !store.isDownloaded($0.id) }
    guard !pending.isEmpty else { app.showToast("Todas as músicas já estão baixadas"); return }
    DownloadManager.shared.downloadBatch(pending)
    app.showToast("Baixando \(DetailFormat.songCount(pending.count))")
  }

  private func saveToLibrary() {
    let wasSaved = store.isAlbumSaved(album.id)
    store.toggleSaveAlbum(album, tracks: tracks)
    app.showToast(wasSaved ? "Álbum removido dos salvos" : "Álbum salvo na biblioteca")
  }
}

// MARK: - Artista

struct ArtistView: View {
  let name: String
  let deezerId: Int?
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared
  @State private var detail: ArtistDetail?
  @State private var loading = true
  @State private var expandTop = false
  @State private var discogFilter: DiscogFilter = .all

  enum DiscogFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case albums = "Álbuns"
    case singles = "Singles e EPs"
    var id: String { rawValue }
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 28) {
        if let d = detail {
          loadedHeader(d)
          actions(d)
          sections(d)
        } else if loading {
          loadingHeader
          skeleton
        } else {
          failed
        }
      }
      .padding(.bottom, 20)
    }
    .ignoresSafeArea(edges: .top)
    .lumeTabScroll()
    .background(Theme.canvas.ignoresSafeArea())
    .lumeDetailChrome(title: detail?.artist.name ?? name, threshold: 260, veilAfter: 80)
    .task(id: name) { await load() }
  }

  private func load() async {
    loading = true
    let d = await DiscoveryService.shared.artistDetail(name: name, deezerId: deezerId)
    if let d { ArtworkStore.shared.register([d.artist] + d.related) }
    detail = d
    loading = false
  }

  // MARK: Cabeçalho

  private func photo(_ url: String) -> some View {
    ZStack {
      if url.isEmpty {
        Theme.prismDiagonal.opacity(0.6)
        Image(systemName: "person.fill")
          .font(.system(size: 80, weight: .semibold))
          .foregroundStyle(.white.opacity(0.8))
          .offset(y: -30)
      } else {
        ArtworkImage(url: url, cornerRadius: 0, maxPixel: 1100, placeholderIcon: "person.fill")
      }
    }
  }

  private func loadedHeader(_ d: ArtistDetail) -> some View {
    ZStack(alignment: .bottomLeading) {
      photo(d.artist.pictureURL)
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .clipped()
      LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .center)
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0.45),
          .init(color: Theme.canvas.opacity(0.75), location: 0.82),
          .init(color: Theme.canvas, location: 1),
        ],
        startPoint: .top, endPoint: .bottom
      )
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(d.artist.name)
            .font(.system(size: 36, weight: .heavy))
            .foregroundStyle(Theme.text)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
          Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 20))
            .foregroundStyle(Theme.accent)
        }
        if let fans = d.artist.fans, fans > 0 {
          Text(DetailFormat.fans(fans))
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.secondary)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 6)
    }
    .frame(height: 380)
  }

  private var loadingHeader: some View {
    ZStack(alignment: .bottomLeading) {
      Rectangle().fill(Theme.fill).frame(height: 380)
      LinearGradient(
        colors: [.clear, Theme.canvas], startPoint: .center, endPoint: .bottom
      )
      Text(name)
        .font(.system(size: 38, weight: .heavy))
        .foregroundStyle(Theme.text)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
    .frame(height: 380)
  }

  private var skeleton: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 12) {
        SkeletonBlock(height: 50, radius: 25)
        SkeletonBlock(height: 50, radius: 25)
      }
      .padding(.horizontal, 20)
      SkeletonBlock(width: 160, height: 22, radius: 8).padding(.horizontal, 20)
      TrackSkeletonRows(count: 5).padding(.horizontal, 20)
    }
  }

  private var failed: some View {
    VStack(spacing: 18) {
      Spacer().frame(height: 140)
      EmptyStateView(icon: "wifi.exclamationmark", title: "Não foi possível carregar", message: "Não encontramos as informações de \(name) agora. Confira sua conexão e tente de novo.")
      GlassButton(title: "Tentar de novo", systemImage: "arrow.clockwise", height: 48) {
        Task { await load() }
      }
      .frame(maxWidth: 220)
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: Ações

  private func actions(_ d: ArtistDetail) -> some View {
    let following = store.isFollowing(d.artist.name)
    return HStack(spacing: 10) {
      PrismButton(title: "Tocar", systemImage: "play.fill", height: 48) {
        guard let first = d.topTracks.first else { return }
        player.shuffleEnabled = false
        player.play(first, in: d.topTracks, context: d.artist.name)
      }
      GlassButton(title: "Rádio", systemImage: "dot.radiowaves.left.and.right", height: 48) {
        guard let first = d.topTracks.first else { app.showToast("Sem músicas para iniciar a rádio"); return }
        player.startRadio(from: first)
      }
      Button {
        store.toggleFollow(d.artist.name)
        Haptics.light()
        app.showToast(store.isFollowing(d.artist.name) ? "Você segue \(d.artist.name)" : "Você deixou de seguir \(d.artist.name)")
      } label: {
        HStack(spacing: 6) {
          Image(systemName: following ? "checkmark" : "plus")
            .font(.system(size: 13, weight: .bold))
            .contentTransition(.symbolEffect(.replace))
          Text(following ? "Seguindo" : "Seguir")
            .font(Theme.font(15, .semibold))
        }
        .foregroundStyle(following ? Theme.text : Theme.accent)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .glassCapsule(tint: following ? nil : Theme.rose.opacity(0.28), interactive: true)
      }
      .buttonStyle(PressableStyle())
      .fixedSize()
    }
    .glassGroup()
    .padding(.horizontal, 20)
    .animation(.snappy, value: following)
  }

  // MARK: Seções

  @ViewBuilder
  private func sections(_ d: ArtistDetail) -> some View {
    if let latest = d.albums.first {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Lançamento mais recente")
        latestCard(latest)
      }
    }

    if !d.topTracks.isEmpty {
      let limit = expandTop ? 20 : 5
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "Mais tocadas", actionLabel: d.topTracks.count > 5 ? (expandTop ? "Ver menos" : "Ver tudo") : nil, action: d.topTracks.count > 5 ? {
          withAnimation(.snappy) { expandTop.toggle() }
        } : nil)
        VStack(spacing: 0) {
          ForEach(Array(d.topTracks.prefix(limit).enumerated()), id: \.element.id) { idx, tr in
            TrackRow(track: tr, rank: idx + 1, queue: d.topTracks)
          }
        }
        .padding(.horizontal, 20)
      }
    }

    if !d.albums.isEmpty {
      let filtered = d.albums.filter { alb in
        switch discogFilter {
        case .all: return true
        case .albums: return (alb.kind ?? "Álbum") == "Álbum"
        case .singles: return alb.kind == "Single" || alb.kind == "EP"
        }
      }
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Discografia", actionLabel: "Ver tudo") {
          app.push(.albums("Discografia · \(d.artist.name)", filtered.isEmpty ? d.albums : filtered))
        }
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(DiscogFilter.allCases) { f in
              PrismChip(title: f.rawValue, active: discogFilter == f) { discogFilter = f }
            }
          }
          .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
        HRow {
          ForEach((filtered.isEmpty ? d.albums : filtered).prefix(20)) { a in AlbumTile(album: a, width: 150, showDate: true) }
        }
      }
    }

    if !d.related.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Artistas parecidos")
        HRow(spacing: 16) {
          ForEach(d.related) { a in ArtistBubble(name: a.name, pictureURL: a.pictureURL, deezerId: a.deezerId) }
        }
      }
    }
  }

  private func latestCard(_ a: AlbumShowcase) -> some View {
    HStack(spacing: 14) {
      ArtworkImage(url: a.artworkURL, cornerRadius: 12, maxPixel: 400)
        .frame(width: 96, height: 96)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
        .lumeShadow(8, y: 5, opacity: 0.5)
      VStack(alignment: .leading, spacing: 3) {
        let when = Theme.shortDate(a.releaseDate)
        Text(when.isEmpty ? (a.kind ?? "Álbum") : "\(a.kind ?? "Álbum") · \(when)")
          .font(Theme.font(12.5, .medium))
          .foregroundStyle(Theme.secondary)
          .lineLimit(1)
        Text(a.title)
          .font(Theme.font(17, .bold))
          .foregroundStyle(Theme.text)
          .lineLimit(2)
        Spacer(minLength: 4)
        Button {
          Haptics.medium()
          Task {
            let list = await DiscoveryService.shared.albumTracks(a)
            if let first = list.first {
              player.shuffleEnabled = false
              player.play(first, in: list, context: a.title)
            } else {
              app.showToast("Não foi possível carregar as faixas")
            }
          }
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
            Text("Ouvir").font(Theme.font(14, .semibold))
          }
          .foregroundStyle(Theme.onPrism)
          .padding(.horizontal, 18)
          .frame(height: 44)
          .background(Capsule().fill(Theme.prismDiagonal))
          .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 0.8))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
      }
      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(24)
    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .onTapGesture {
      Haptics.light()
      app.push(.album(a))
    }
    .padding(.horizontal, 20)
  }
}

// MARK: - Playlist

struct PlaylistView: View {
  let playlistId: String
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var app = AppModel.shared
  @Environment(\.dismiss) private var dismiss
  @State private var showRename = false
  @State private var renameText = ""
  @State private var confirmDelete = false
  @State private var editing = false

  private var playlist: MusicPlaylist? { store.playlists.first { $0.id == playlistId } }

  var body: some View {
    Group {
      if let pl = playlist {
        content(pl)
      } else {
        EmptyStateView(icon: "music.note.list", title: "Playlist não encontrada", message: "Esta playlist não existe mais.")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(background)
    .lumeDetailChrome(title: playlist?.name ?? "", threshold: 250) {
      if playlist != nil {
        Menu {
          Button {
            renameText = playlist?.name ?? ""
            showRename = true
          } label: { Label("Renomear", systemImage: "pencil") }
          Button {
            withAnimation(.snappy) { editing.toggle() }
          } label: { Label(editing ? "Concluir edição" : "Editar ordem e faixas", systemImage: editing ? "checkmark" : "arrow.up.arrow.down") }
          Divider()
          Button(role: .destructive) { confirmDelete = true } label: { Label("Excluir playlist", systemImage: "trash") }
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 44, height: 44)
            .glassCircle(interactive: true)
            .contentShape(Circle())
        }
        .accessibilityLabel("Mais opções da playlist")
      }
    }
    .alert("Renomear playlist", isPresented: $showRename) {
      TextField("Nome da playlist", text: $renameText)
      Button("Salvar") {
        let new = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !new.isEmpty, let idx = store.playlists.firstIndex(where: { $0.id == playlistId }) {
          store.playlists[idx].name = new
          store.save()
        }
      }
      Button("Cancelar", role: .cancel) {}
    }
    .confirmationDialog("Excluir esta playlist?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Excluir playlist", role: .destructive) {
        store.deletePlaylist(playlistId)
        Haptics.success()
        dismiss()
      }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text("As músicas continuam disponíveis no app. Só a playlist será removida.")
    }
  }

  private var background: some View {
    ZStack(alignment: .top) {
      Theme.canvas
      LinearGradient(
        colors: [Theme.lavender.opacity(0.16), Theme.rose.opacity(0.06), .clear],
        startPoint: .top, endPoint: .bottom
      )
      .frame(height: 420)
      .blur(radius: 20)
    }
    .ignoresSafeArea()
  }

  private func content(_ pl: MusicPlaylist) -> some View {
    let tracks = store.tracks(in: pl)
    return ScrollView(showsIndicators: false) {
      VStack(spacing: 0) {
        VStack(spacing: 6) {
          PlaylistCover(playlist: pl, cornerRadius: 18)
            .frame(width: 220, height: 220)
            .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
            .padding(.top, 8)
            .padding(.bottom, 14)
          Text(pl.name)
            .font(Theme.font(24, .bold))
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 28)
          Text(subtitle(pl, tracks))
            .font(Theme.font(13.5))
            .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)

        VStack(spacing: 16) {
          PlayShuffleBar(tracks: tracks, context: pl.name)
          GlassIconButton(systemName: "arrow.down.circle", size: 46) {
            DownloadManager.shared.downloadPlaylist(pl)
            app.showToast("Baixando as músicas da playlist")
          }
          .accessibilityLabel("Baixar todas")
          .disabled(tracks.isEmpty)
          .opacity(tracks.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)

        if tracks.isEmpty {
          EmptyStateView(icon: "music.note", title: "Playlist vazia", message: "Adicione músicas pelo menu de três pontos de qualquer faixa.")
            .padding(.top, 20)
        } else {
          VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, tr in
              HStack(spacing: 4) {
                if editing {
                  Button {
                    Haptics.light()
                    withAnimation(.snappy) { store.removeTrack(tr.id, fromPlaylist: pl.id) }
                  } label: {
                    Image(systemName: "minus.circle.fill")
                      .font(.system(size: 22))
                      .foregroundStyle(Theme.danger)
                      .frame(width: 44, height: 44)
                      .contentShape(Rectangle())
                  }
                  .accessibilityLabel("Remover da playlist")
                  .transition(.move(edge: .leading).combined(with: .opacity))

                  VStack(spacing: 2) {
                    Button {
                      guard idx > 0 else { return }
                      Haptics.light()
                      withAnimation(.snappy) { store.reorderPlaylist(pl.id, from: IndexSet(integer: idx), to: idx - 1) }
                    } label: {
                      Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(idx > 0 ? Theme.text : Theme.tertiary)
                        .frame(width: 44, height: 26)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Subir na playlist")
                    .disabled(idx == 0)
                    Button {
                      guard idx + 1 < tracks.count else { return }
                      Haptics.light()
                      withAnimation(.snappy) { store.reorderPlaylist(pl.id, from: IndexSet(integer: idx), to: idx + 2) }
                    } label: {
                      Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(idx + 1 < tracks.count ? Theme.text : Theme.tertiary)
                        .frame(width: 44, height: 26)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Descer na playlist")
                    .disabled(idx + 1 >= tracks.count)
                  }
                }
                TrackRow(track: tr, queue: tracks)
              }
              if idx < tracks.count - 1 {
                Divider().overlay(Theme.hairline).padding(.leading, editing ? 112 : 62)
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 14)
        }
      }
      .padding(.bottom, 20)
    }
    .lumeTabScroll()
  }

  private func subtitle(_ pl: MusicPlaylist, _ tracks: [Track]) -> String {
    var parts = [DetailFormat.songCount(pl.trackIds.count)]
    if let d = DetailFormat.duration(tracks) { parts.append(d) }
    return parts.joined(separator: " · ")
  }
}

// MARK: - Lista de músicas

struct TrackListView: View {
  let title: String
  let tracks: [Track]

  /// Posição só faz sentido em listas ranqueadas (paradas, mais ouvidas...).
  private var showRank: Bool { !["Curtidas", "Baixadas", "Histórico"].contains(title) }

  var body: some View {
    ScrollView(showsIndicators: false) {
      LumeLargeTitle(title)
      if tracks.isEmpty {
        EmptyStateView(icon: "music.note.list", title: "Nada por aqui ainda", message: "Quando houver músicas nesta lista, elas aparecem aqui.")
          .padding(.top, 60)
      } else {
        LazyVStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 14) {
            Text(DetailFormat.songCount(tracks.count))
              .font(Theme.font(14))
              .foregroundStyle(Theme.secondary)
            PlayShuffleBar(tracks: tracks, context: title)
          }
          .padding(.horizontal, 20)
          LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, tr in
              TrackRow(track: tr, rank: showRank ? idx + 1 : nil, queue: tracks)
            }
          }
          .padding(.horizontal, 20)
        }
        .padding(.top, 6)
        .padding(.bottom, 20)
      }
    }
    .lumeTabScroll()
    .background(Theme.canvas.ignoresSafeArea())
    .lumeDetailChrome(title: title)
  }
}

// MARK: - Grade de álbuns

struct AlbumGridView: View {
  let title: String
  let albums: [AlbumShowcase]

  var body: some View {
    ScrollView(showsIndicators: false) {
      LumeLargeTitle(title)
      if albums.isEmpty {
        EmptyStateView(icon: "square.stack", title: "Nenhum lançamento", message: "Não encontramos álbuns para mostrar agora.")
          .padding(.top, 60)
      } else {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
          ForEach(albums) { a in
            GeometryReader { g in
              AlbumTile(album: a, width: g.size.width, showDate: true)
            }
            .aspectRatio(0.78, contentMode: .fit)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 20)
      }
    }
    .lumeTabScroll()
    .background(Theme.canvas.ignoresSafeArea())
    .lumeDetailChrome(title: title)
  }
}

// MARK: - Grade de artistas

struct ArtistGridView: View {
  let title: String
  let artists: [ArtistInfo]

  var body: some View {
    ScrollView(showsIndicators: false) {
      LumeLargeTitle(title)
      if artists.isEmpty {
        EmptyStateView(icon: "music.mic", title: "Nenhum artista ainda", message: "Ouça algumas músicas ou siga artistas para vê-los aqui.")
          .padding(.top, 60)
      } else {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 22) {
          ForEach(artists) { a in
            ArtistBubble(name: a.name, pictureURL: a.pictureURL, deezerId: a.deezerId, size: 96)
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 20)
      }
    }
    .lumeTabScroll()
    .background(Theme.canvas.ignoresSafeArea())
    .lumeDetailChrome(title: title)
    .onAppear { ArtworkStore.shared.register(artists) }
  }
}

// MARK: - Estilo (mood)

struct MoodView: View {
  let mood: MoodCategory
  @State private var tracks: [Track] = []
  @State private var loading = true

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 20) {
        header
        if loading {
          TrackSkeletonRows(count: 8).padding(.horizontal, 20)
        } else if tracks.isEmpty {
          EmptyStateView(icon: "wifi.exclamationmark", title: "Sem resultados", message: "Não foi possível carregar este estilo agora. Tente de novo em instantes.")
        } else {
          PrismButton(title: "Tocar mix", systemImage: "play.fill") {
            guard let first = tracks.first else { return }
            AudioPlayer.shared.shuffleEnabled = false
            AudioPlayer.shared.play(first, in: tracks, context: mood.title)
          }
          .padding(.horizontal, 20)
          LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, tr in
              TrackRow(track: tr, rank: idx + 1, queue: tracks)
            }
          }
          .padding(.horizontal, 20)
        }
      }
      .padding(.bottom, 20)
    }
    .ignoresSafeArea(edges: .top)
    .lumeTabScroll()
    .background(Theme.canvas.ignoresSafeArea())
    .lumeDetailChrome(title: mood.title, threshold: 150, veilAfter: 90)
    .task {
      let found = await MusicEngine.shared.searchSongs(query: mood.query, limit: 30)
      tracks = found
      loading = false
    }
  }

  private var header: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(colors: [Theme.hex(mood.hexA), Theme.hex(mood.hexB)], startPoint: .topLeading, endPoint: .bottomTrailing)
      LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
      Image(systemName: mood.icon)
        .font(.system(size: 130, weight: .bold))
        .foregroundStyle(.white.opacity(0.25))
        .rotationEffect(.degrees(15))
        .offset(x: 36, y: -6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      Text(mood.title)
        .font(Theme.font(34, .bold))
        .foregroundStyle(.white)
        .lineLimit(2)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    .frame(height: 262)
    .clipped()
  }
}

// MARK: - Novidades dos seus artistas (sino)

struct ReleasesView: View {
  @ObservedObject private var app = AppModel.shared
  @State private var refreshing = false

  var body: some View {
    ScrollView(showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 24) {
        LumeLargeTitle("Novidades dos seus artistas")
        if app.artistReleases.isEmpty {
          EmptyStateView(
            icon: "bell.slash",
            title: "Sem novidades por enquanto",
            message: "Quando os artistas que você segue e mais ouve lançarem algo novo, aparece aqui."
          )
        } else {
          VStack(spacing: 10) {
            ForEach(app.artistReleases) { a in ReleaseRow(album: a) }
          }
          .padding(.horizontal, 20)
        }

        Text("Mostramos o que saiu nos últimos 45 dias dos artistas que você segue e mais ouve. Para seguir, abra a página do artista.")
          .font(Theme.font(12.5))
          .foregroundStyle(Theme.secondary)
          .padding(.horizontal, 24)

        if let week = app.feed?.newReleases, !week.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Lançamentos da semana")
            VStack(spacing: 10) {
              ForEach(week.prefix(20)) { a in ReleaseRow(album: a) }
            }
            .padding(.horizontal, 20)
          }
        }
      }
      .padding(.top, 2)
      .padding(.bottom, 20)
    }
    .lumeTabScroll()
    .background(Theme.canvas.ignoresSafeArea())
    .lumeDetailChrome(title: "Novidades dos seus artistas") {
      Button {
        Haptics.light()
        Task {
          refreshing = true
          await app.refreshArtistReleases()
          refreshing = false
        }
      } label: {
        Group {
          if refreshing {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "arrow.clockwise").font(.system(size: 16, weight: .semibold))
          }
        }
        .foregroundStyle(Theme.text)
        .frame(width: 44, height: 44)
        .glassCircle(interactive: true)
        .contentShape(Circle())
      }
      .disabled(refreshing)
      .accessibilityLabel("Atualizar")
    }
    .onAppear { app.markReleasesSeen() }
  }
}

private struct ReleaseRow: View {
  let album: AlbumShowcase

  var body: some View {
    Button {
      Haptics.light()
      AppModel.shared.push(.album(album))
    } label: {
      HStack(spacing: 14) {
        ArtworkImage(url: album.artworkURL, cornerRadius: 12, maxPixel: 240)
          .frame(width: 64, height: 64)
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 0.5))
        VStack(alignment: .leading, spacing: 2) {
          Text(album.title)
            .font(Theme.font(16, .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
          Text(album.artist)
            .font(Theme.font(14))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
          Text(meta)
            .font(Theme.font(12.5))
            .foregroundStyle(Theme.tertiary)
            .lineLimit(1)
        }
        Spacer(minLength: 6)
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Theme.tertiary)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .glass(20, interactive: true)
      .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .buttonStyle(PressableStyle(scale: 0.985))
  }

  private var meta: String {
    let kind = album.kind ?? "Álbum"
    let when = Theme.shortDate(album.releaseDate)
    return when.isEmpty ? kind : "\(kind) · \(when)"
  }
}
