import SwiftUI

/// Buscar — autocomplete ao vivo, músicas, artistas, álbuns, playlists, busca por letra e navegador completo.
struct SearchView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared

  @State private var query = ""
  @State private var scope: Scope = .all
  @State private var browseTab: BrowseTab = .genres
  @State private var songs: [Track] = []
  @State private var artists: [ArtistInfo] = []
  @State private var albums: [AlbumShowcase] = []
  @State private var playlists: [RemotePlaylist] = []
  @State private var lyricHits: [LyricSearchHit] = []
  @State private var suggestions: [String] = []
  @State private var loading = false
  @State private var resultsFor = ""
  @FocusState private var focused: Bool

  enum Scope: String, CaseIterable, Identifiable {
    case all = "Tudo"
    case songs = "Músicas"
    case artists = "Artistas"
    case albums = "Álbuns"
    case playlists = "Playlists"
    case lyrics = "Letras"
    var id: String { rawValue }
  }

  enum BrowseTab: String, CaseIterable, Identifiable {
    case genres = "Gêneros"
    case moods = "Climas"
    case countries = "Países"
    case decades = "Décadas"
    var id: String { rawValue }
  }

  private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var hasResults: Bool {
    !songs.isEmpty || !artists.isEmpty || !albums.isEmpty || !playlists.isEmpty || !lyricHits.isEmpty
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 14) {
          Text("Buscar")
            .font(Theme.font(34, .bold))
            .foregroundStyle(Theme.text)
          searchField
          if !trimmed.isEmpty { chips }
        }
        .padding(.horizontal, 20)

        if trimmed.isEmpty {
          idleContent
        } else {
          if focused && !suggestions.isEmpty && resultsFor != trimmed {
            suggestionsBlock
          }
          resultsContent
        }
      }
      .padding(.top, 6)
      .padding(.bottom, 16)
    }
    .lumeTabScroll()
    .background(Theme.canvas.ignoresSafeArea())
    .task(id: query) { await runSearch() }
    .onChange(of: app.searchFocusToken) { _, _ in focused = true }
    .onChange(of: app.searchLyricsToken) { _, _ in
      scope = .lyrics
      focused = true
    }
    .onAppear { if app.tab == .search { focused = true } }
    .onChange(of: app.debugSearchText) { _, text in
      if let text { query = text; focused = true; app.debugSearchText = nil }
    }
  }

  // MARK: Campo de busca

  private var searchField: some View {
    HStack(spacing: 10) {
      Image(systemName: scope == .lyrics ? "quote.bubble.fill" : "magnifyingglass")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(scope == .lyrics ? Theme.accent : Theme.secondary)
      TextField(scope == .lyrics ? "Digite um verso da música…" : "Músicas, artistas, álbuns ou letra", text: $query)
        .font(Theme.font(16))
        .foregroundStyle(Theme.text)
        .focused($focused)
        .submitLabel(.search)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onSubmit {
          store.addSearchTerm(query)
          focused = false
        }
      if !query.isEmpty {
        Button {
          Haptics.light()
          query = ""
          focused = true
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 17))
            .foregroundStyle(Theme.tertiary)
            .frame(width: 30, height: 40)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Limpar busca")
      }
    }
    .padding(.horizontal, 18)
    .frame(height: 50)
    .glassCapsule()
  }

  private var chips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(Scope.allCases) { s in
          PrismChip(title: s.rawValue, active: scope == s) { scope = s }
        }
      }
      .padding(.vertical, 4)
    }
    .scrollClipDisabled()
  }

  // MARK: Sugestões ao vivo

  private var suggestionsBlock: some View {
    VStack(spacing: 0) {
      ForEach(suggestions.prefix(6), id: \.self) { sug in
        HStack(spacing: 12) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .frame(width: 22)
          Text(sug)
            .font(Theme.font(15.5))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
          Spacer()
          Image(systemName: "arrow.up.left")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.tertiary)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
          Haptics.light()
          query = sug
          store.addSearchTerm(sug)
          focused = false
        }
        if sug != suggestions.prefix(6).last {
          Divider().overlay(Theme.hairline).padding(.leading, 50)
        }
      }
    }
    .glass(20)
    .padding(.horizontal, 20)
  }

  // MARK: Estado Vazio

  @ViewBuilder
  private var idleContent: some View {
    if let feed = app.feed, !feed.topBrazil.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        SectionHeader(title: "Em alta nas buscas")
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(Array(feed.topBrazil.prefix(8)), id: \.id) { tr in
              Button {
                Haptics.light()
                query = tr.title
                focused = false
              } label: {
                HStack(spacing: 6) {
                  Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                  Text(tr.title)
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .glassCapsule(interactive: true)
              }
              .buttonStyle(PressableStyle(scale: 0.96))
            }
          }
          .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
      }
    }

    if !store.searchHistory.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "Buscas recentes", actionLabel: "Limpar") {
          store.searchHistory.removeAll()
          store.save()
        }
        VStack(spacing: 0) {
          ForEach(store.searchHistory, id: \.self) { term in
            HStack(spacing: 12) {
              Image(systemName: "clock")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 24)
              Text(term)
                .font(Theme.font(16))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
              Spacer(minLength: 6)
              Button {
                Haptics.light()
                withAnimation(.snappy) {
                  store.searchHistory.removeAll { $0 == term }
                  store.save()
                }
              } label: {
                Image(systemName: "xmark")
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(Theme.tertiary)
                  .frame(width: 44, height: 44)
                  .contentShape(Rectangle())
              }
              .accessibilityLabel("Remover \(term)")
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .onTapGesture {
              Haptics.light()
              query = term
              focused = false
            }
            if term != store.searchHistory.last {
              Divider().overlay(Theme.hairline).padding(.leading, 36)
            }
          }
        }
        .padding(.horizontal, 20)
      }
    }

    VStack(alignment: .leading, spacing: 14) {
      SectionHeader(title: "Navegar por categorias")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(BrowseTab.allCases) { tab in
            PrismChip(title: tab.rawValue, active: browseTab == tab) { browseTab = tab }
          }
        }
        .padding(.horizontal, 20)
      }
      .scrollClipDisabled()

      switch browseTab {
      case .genres:
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
          ForEach(MusicGenre.all) { g in GenreCard(genre: g) }
        }
        .padding(.horizontal, 20)
      case .moods:
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
          ForEach(MoodCategory.activities) { m in MoodCard(mood: m) }
        }
        .padding(.horizontal, 20)
      case .countries:
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
          ForEach(ChartCountry.all) { c in CountryFlagCard(country: c, width: nil) }
        }
        .padding(.horizontal, 20)
      case .decades:
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
          ForEach(MoodCategory.decades) { m in MoodCard(mood: m) }
        }
        .padding(.horizontal, 20)
      }
    }
  }

  // MARK: Resultados

  @ViewBuilder
  private var resultsContent: some View {
    if !hasResults {
      if loading || resultsFor != trimmed {
        ProgressView()
          .controlSize(.large)
          .frame(maxWidth: .infinity)
          .padding(.top, 60)
      } else {
        EmptyStateView(icon: "magnifyingglass", title: "Nada encontrado", message: "Não achamos resultados para “\(trimmed)”. Confira a grafia ou tente outro termo.")
          .padding(.top, 20)
      }
    } else {
      switch scope {
      case .all: allResults
      case .songs: songsList(songs)
      case .artists: artistsGrid
      case .albums: albumsGrid
      case .playlists: playlistsGrid
      case .lyrics: lyricsList
      }
    }
  }

  @ViewBuilder
  private var allResults: some View {
    if let best = bestResult { bestCard(best) }

    if !songs.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "Músicas", actionLabel: songs.count > 6 ? "Ver tudo" : nil, action: songs.count > 6 ? { scope = .songs } : nil)
        VStack(spacing: 0) {
          ForEach(songs.prefix(6)) { tr in
            TrackRow(track: tr, queue: songs) {
              store.addSearchTerm(trimmed)
              player.play(tr, in: songs)
            }
          }
        }
        .padding(.horizontal, 20)
      }
    }

    if !artists.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Artistas", actionLabel: artists.count > 3 ? "Ver tudo" : nil, action: artists.count > 3 ? { scope = .artists } : nil)
        HRow(spacing: 16) {
          ForEach(artists) { a in
            ArtistBubble(name: a.name, pictureURL: a.pictureURL, deezerId: a.deezerId)
              .simultaneousGesture(TapGesture().onEnded { store.addSearchTerm(trimmed) })
          }
        }
      }
    }

    if !albums.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Álbuns", actionLabel: albums.count > 2 ? "Ver tudo" : nil, action: albums.count > 2 ? { scope = .albums } : nil)
        HRow {
          ForEach(albums) { a in
            AlbumTile(album: a, width: 150)
              .simultaneousGesture(TapGesture().onEnded { store.addSearchTerm(trimmed) })
          }
        }
      }
    }

    if !playlists.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Playlists", actionLabel: playlists.count > 2 ? "Ver tudo" : nil, action: playlists.count > 2 ? { scope = .playlists } : nil)
        HRow {
          ForEach(playlists) { pl in
            RemotePlaylistCard(playlist: pl)
              .simultaneousGesture(TapGesture().onEnded { store.addSearchTerm(trimmed) })
          }
        }
      }
    }

    if !lyricHits.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        SectionHeader(title: "Trechos de letras", actionLabel: lyricHits.count > 3 ? "Ver tudo" : nil, action: lyricHits.count > 3 ? { scope = .lyrics } : nil)
        VStack(spacing: 10) {
          ForEach(lyricHits.prefix(3)) { hit in
            lyricHitCard(hit)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }

  private func songsList(_ list: [Track]) -> some View {
    VStack(spacing: 0) {
      ForEach(list) { tr in
        TrackRow(track: tr, queue: list) {
          store.addSearchTerm(trimmed)
          player.play(tr, in: list)
        }
      }
    }
    .padding(.horizontal, 20)
  }

  @ViewBuilder
  private var artistsGrid: some View {
    if artists.isEmpty {
      EmptyStateView(icon: "music.mic", title: "Nenhum artista", message: "Não encontramos artistas para essa busca.")
    } else {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 22) {
        ForEach(artists) { a in
          ArtistBubble(name: a.name, pictureURL: a.pictureURL, deezerId: a.deezerId, size: 96)
            .simultaneousGesture(TapGesture().onEnded { store.addSearchTerm(trimmed) })
        }
      }
      .padding(.horizontal, 16)
    }
  }

  @ViewBuilder
  private var albumsGrid: some View {
    if albums.isEmpty {
      EmptyStateView(icon: "square.stack", title: "Nenhum álbum", message: "Não encontramos álbuns para essa busca.")
    } else {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
        ForEach(albums) { a in
          GeometryReader { g in
            AlbumTile(album: a, width: g.size.width)
          }
          .aspectRatio(0.84, contentMode: .fit)
          .simultaneousGesture(TapGesture().onEnded { store.addSearchTerm(trimmed) })
        }
      }
      .padding(.horizontal, 20)
    }
  }

  @ViewBuilder
  private var playlistsGrid: some View {
    if playlists.isEmpty {
      EmptyStateView(icon: "music.note.list", title: "Nenhuma playlist", message: "Não encontramos playlists para essa busca.")
    } else {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
        ForEach(playlists) { pl in
          GeometryReader { g in
            RemotePlaylistCard(playlist: pl, width: g.size.width)
          }
          .aspectRatio(0.80, contentMode: .fit)
          .simultaneousGesture(TapGesture().onEnded { store.addSearchTerm(trimmed) })
        }
      }
      .padding(.horizontal, 20)
    }
  }

  @ViewBuilder
  private var lyricsList: some View {
    if lyricHits.isEmpty {
      EmptyStateView(icon: "quote.bubble", title: "Nenhuma letra encontrada", message: "Digite algumas palavras exatas de um verso da música.")
    } else {
      VStack(spacing: 12) {
        ForEach(lyricHits) { hit in
          lyricHitCard(hit)
        }
      }
      .padding(.horizontal, 20)
    }
  }

  private func lyricHitCard(_ hit: LyricSearchHit) -> some View {
    Button {
      Haptics.medium()
      store.addSearchTerm(trimmed)
      player.play(hit.track, in: lyricHits.map(\.track))
    } label: {
      HStack(spacing: 12) {
        TrackArtwork(track: hit.track, cornerRadius: 10, maxPixel: 200)
          .frame(width: 54, height: 54)
        VStack(alignment: .leading, spacing: 3) {
          Text(hit.track.title)
            .font(Theme.font(15.5, .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
          Text(hit.track.artist)
            .font(Theme.font(13))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
          if !hit.snippet.isEmpty {
            Text("“\(hit.snippet)”")
              .font(Theme.font(12.5, .medium))
              .foregroundStyle(Theme.accent)
              .lineLimit(2)
          }
        }
        Spacer(minLength: 4)
        Image(systemName: "play.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(Theme.text)
          .frame(width: 34, height: 34)
          .glassCircle()
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .glass(20, interactive: true)
    }
    .buttonStyle(PressableStyle(scale: 0.98))
    .contextMenu { TrackMenuItems(track: hit.track) }
  }

  // MARK: Melhor resultado

  private enum Best {
    case artist(ArtistInfo)
    case song(Track)
  }

  private var bestResult: Best? {
    if let a = artists.first, Self.similar(a.name, trimmed) { return .artist(a) }
    if let s = songs.first { return .song(s) }
    if let a = artists.first { return .artist(a) }
    return nil
  }

  private static func fold(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func similar(_ name: String, _ q: String) -> Bool {
    let n = fold(name), s = fold(q)
    guard !n.isEmpty, !s.isEmpty else { return false }
    if n == s { return true }
    if s.count >= 3 && (n.hasPrefix(s) || s.hasPrefix(n)) { return true }
    return false
  }

  @ViewBuilder
  private func bestCard(_ best: Best) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionHeader(title: "Melhor resultado")
      switch best {
      case .artist(let a):
        Button {
          Haptics.light()
          store.addSearchTerm(trimmed)
          focused = false
          app.push(.artist(a.name, a.deezerId))
        } label: {
          HStack(spacing: 16) {
            ArtworkImage(url: a.pictureURL, cornerRadius: 42, maxPixel: 300, placeholderIcon: "person.fill")
              .frame(width: 84, height: 84)
              .clipShape(Circle())
              .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 3) {
              Text(a.name)
                .font(Theme.font(20, .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
              Text("Artista")
                .font(Theme.font(14))
                .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Theme.tertiary)
          }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .glass(24, interactive: true)
          .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .padding(.horizontal, 20)
      case .song(let t):
        Button {
          Haptics.medium()
          store.addSearchTerm(trimmed)
          focused = false
          player.play(t, in: songs)
        } label: {
          HStack(spacing: 16) {
            TrackArtwork(track: t, cornerRadius: 14, maxPixel: 300)
              .frame(width: 84, height: 84)
              .lumeShadow(10, y: 6, opacity: 0.5)
            VStack(alignment: .leading, spacing: 3) {
              Text(t.title)
                .font(Theme.font(19, .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
              Text("Música · \(t.artist)")
                .font(Theme.font(14))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "play.fill")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(Theme.onPrism)
              .frame(width: 46, height: 46)
              .background(Circle().fill(Theme.prismDiagonal))
              .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.8))
          }
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .glass(24, interactive: true)
          .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .padding(.horizontal, 20)
      }
    }
  }

  // MARK: Busca com debounce + sugestões instantâneas

  private func runSearch() async {
    let q = trimmed
    if q.isEmpty {
      songs = []; artists = []; albums = []; playlists = []; lyricHits = []; suggestions = []
      loading = false
      resultsFor = ""
      return
    }
    loading = true

    // 1. Sugestões instantâneas aparecem enquanto o usuário ainda digita (antes do debounce completo).
    let sugJob = Task { await SearchService.shared.suggestions(q) }
    Task { @MainActor in
      let foundSug = await sugJob.value
      guard !Task.isCancelled, self.trimmed == q else { return }
      self.suggestions = foundSug
    }

    try? await Task.sleep(for: .milliseconds(260))
    if Task.isCancelled { sugJob.cancel(); return }

    // 2. Publica cada fonte assim que responder (músicas/artistas/álbuns não ficam presos esperando letra).
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        let foundSongs = await MusicEngine.shared.searchSongs(query: q, limit: 25)
        await MainActor.run {
          guard !Task.isCancelled, self.trimmed == q else { return }
          self.songs = foundSongs
          self.resultsFor = q
        }
      }
      group.addTask {
        let foundArtists = await SearchService.shared.artists(q)
        await MainActor.run {
          guard !Task.isCancelled, self.trimmed == q else { return }
          ArtworkStore.shared.register(foundArtists)
          self.artists = foundArtists
          self.resultsFor = q
        }
      }
      group.addTask {
        let foundAlbums = await SearchService.shared.albums(q)
        await MainActor.run {
          guard !Task.isCancelled, self.trimmed == q else { return }
          self.albums = foundAlbums
          self.resultsFor = q
        }
      }
      group.addTask {
        let foundPlaylists = await SearchService.shared.playlists(q, limit: 12)
        await MainActor.run {
          guard !Task.isCancelled, self.trimmed == q else { return }
          self.playlists = foundPlaylists
          self.resultsFor = q
        }
      }
      group.addTask {
        let foundLyrics = await SearchService.shared.searchByLyrics(q)
        await MainActor.run {
          guard !Task.isCancelled, self.trimmed == q else { return }
          self.lyricHits = foundLyrics
          self.resultsFor = q
        }
      }
    }
    if Task.isCancelled { return }
    resultsFor = q
    loading = false
  }
}
