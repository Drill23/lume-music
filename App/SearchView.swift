import SwiftUI

/// Buscar — músicas, artistas e álbuns. Raiz da aba (a barra de navegação fica escondida).
struct SearchView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared

  @State private var query = ""
  @State private var scope: Scope = .all
  @State private var songs: [Track] = []
  @State private var artists: [ArtistInfo] = []
  @State private var albums: [AlbumShowcase] = []
  @State private var loading = false
  @State private var resultsFor = ""
  @FocusState private var focused: Bool

  enum Scope: String, CaseIterable, Identifiable {
    case all = "Tudo"
    case songs = "Músicas"
    case artists = "Artistas"
    case albums = "Álbuns"
    var id: String { rawValue }
  }

  private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var hasResults: Bool { !songs.isEmpty || !artists.isEmpty || !albums.isEmpty }

  var body: some View {
    ScrollView(showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 16) {
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
          resultsContent
        }
      }
      .padding(.top, 6)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(Theme.canvas.ignoresSafeArea())
    .task(id: query) { await runSearch() }
    .onChange(of: app.searchFocusToken) { _, _ in focused = true }
    .onAppear { if app.tab == .search { focused = true } }
  }

  // MARK: Campo de busca

  private var searchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.secondary)
      TextField("Músicas, artistas, álbuns", text: $query)
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

  // MARK: Consulta vazia

  @ViewBuilder
  private var idleContent: some View {
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
                  .frame(width: 40, height: 44)
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
      MoodGrid()
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

  /// Nome do artista ≈ consulta (igual, um contém o outro ou começa com ela).
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

  // MARK: Busca com debounce

  private func runSearch() async {
    let q = trimmed
    if q.isEmpty {
      songs = []; artists = []; albums = []
      loading = false
      resultsFor = ""
      return
    }
    loading = true
    try? await Task.sleep(for: .milliseconds(350))
    if Task.isCancelled { return }
    async let s = MusicEngine.shared.searchSongs(query: q, limit: 25)
    async let a = SearchService.shared.artists(q)
    async let al = SearchService.shared.albums(q)
    let (foundSongs, foundArtists, foundAlbums) = await (s, a, al)
    if Task.isCancelled { return }
    ArtworkStore.shared.register(foundArtists)
    songs = foundSongs
    artists = foundArtists
    albums = foundAlbums
    resultsFor = q
    loading = false
  }
}
