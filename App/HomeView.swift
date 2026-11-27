import SwiftUI

/// Início — poucas coisas por vez, bem espaçadas: saudação, continuar ouvindo, uma vitrine, atalhos,
/// "Para você", Top 10 com seletor de países e lançamentos. Tudo aparece na hora a partir do cache.
struct HomeView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var home = HomeStore.shared

  private let gutter: CGFloat = 20
  private let sectionGap: CGFloat = 32

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: sectionGap) {
        header
        searchPill
        continueSection
        showcase
        shortcuts
        forYou
        topTen
        releases
        Text(Theme.credit)
          .font(Theme.font(11.5))
          .foregroundStyle(Theme.tertiary)
          .frame(maxWidth: .infinity)
      }
      .padding(.top, 6)
      .padding(.bottom, 8)
    }
    .background(homeBackdrop)
    .refreshable {
      await home.refresh()
      await app.refreshArtistReleases()
    }
    .navigationDestination(for: LumeHub.self) { hub in
      switch hub {
      case .genres: GenresHubView()
      }
    }
    .task { home.start() }
  }

  private var homeBackdrop: some View {
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

  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: Date())
    if hour < 5 { return "Boa madrugada" }
    if hour < 12 { return "Bom dia" }
    if hour < 18 { return "Boa tarde" }
    return "Boa noite"
  }

  // MARK: Cabeçalho

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        LumeWordmark(size: 24)
        if store.offlineMode {
          Label("Offline", systemImage: "airplane")
            .font(Theme.font(11, .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .glassCapsule()
        }
        Spacer()
        GlassIconButton(systemName: "sparkles", size: 44) { app.push(.replay) }
          .accessibilityLabel("Lume Replay")
        GlassIconButton(systemName: "bell", size: 44, badge: app.hasUnseenReleases) { app.push(.releases) }
          .accessibilityLabel("Novidades dos seus artistas")
        GlassIconButton(systemName: "gearshape", size: 44) { app.push(.settings) }
          .accessibilityLabel("Ajustes")
      }
      .glassGroup()

      Text(greeting)
        .font(Theme.font(34, .bold))
        .foregroundStyle(Theme.text)
    }
    .padding(.horizontal, gutter)
  }

  private var searchPill: some View {
    HStack(spacing: 10) {
      Button {
        app.select(.search)
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 17, weight: .semibold))
          Text("Músicas, artistas, álbuns e trechos")
            .font(Theme.font(15.5))
            .lineLimit(1)
          Spacer()
        }
        .foregroundStyle(Theme.secondary)
        .frame(height: 50)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Button {
        Haptics.light()
        app.openLyricsSearch()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "quote.bubble.fill")
            .font(.system(size: 12, weight: .semibold))
          Text("Letra")
            .font(Theme.font(12, .semibold))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Capsule().fill(Theme.fillStrong))
        .frame(height: 44)
        .contentShape(Capsule())
      }
      .buttonStyle(PressableStyle(scale: 0.94))
      .accessibilityLabel("Buscar por trecho da letra")
    }
    .padding(.leading, 18)
    .padding(.trailing, 7)
    .frame(height: 50)
    .glassCapsule(interactive: true)
    .padding(.horizontal, gutter)
  }

  // MARK: Continuar ouvindo

  @ViewBuilder
  private var continueSection: some View {
    let recent = Array(store.recentTracks.prefix(10))
    if !recent.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Continuar ouvindo", actionLabel: "Histórico") {
          app.push(.tracks("Histórico", store.recentTracks))
        }
        HRow(spacing: 12) {
          ForEach(recent) { tr in PlayCard(track: tr, queue: recent, size: 128) }
        }
      }
    }
  }

  // MARK: Vitrine principal

  @ViewBuilder
  private var showcase: some View {
    let place = home.homePlace
    let chartAlbums = Array((home.homeList?.albums ?? []).prefix(6))
    let fallback = Array((home.feed?.newReleases ?? home.feed?.brazilReleases ?? []).prefix(6))
    let albums = chartAlbums.isEmpty ? fallback : chartAlbums
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(
        title: chartAlbums.isEmpty ? "Em destaque" : "Álbuns em alta · \(place.name)",
        subtitle: chartAlbums.isEmpty ? "Lançamentos que estão chamando atenção" : "Os mais ouvidos \(place.isGlobal ? "no mundo" : "no país") agora",
        actionLabel: albums.isEmpty ? nil : "Ver tudo"
      ) {
        app.push(.albums("Álbuns em alta · \(place.name)", chartAlbums.isEmpty ? fallback : (home.homeList?.albums ?? [])))
      }
      if albums.isEmpty {
        SoftBlock(height: 332, radius: 30).padding(.horizontal, gutter)
      } else {
        ReleaseHeroCarousel(albums: albums, kicker: chartAlbums.isEmpty ? nil : { idx, _ in
          "#\(idx + 1) · \(place.name.uppercased())"
        })
        .id(chartAlbums.isEmpty ? "fallback" : "chart_\(place.id)")
        .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.25), value: albums.first?.id)
  }

  // MARK: Atalhos (onde fica cada coisa)

  private struct Shortcut: Identifiable {
    let id: String
    let title: String
    let icon: String
    let action: () -> Void
  }

  private var shortcutItems: [Shortcut] {
    [
      Shortcut(id: "charts", title: "Paradas", icon: "chart.bar.fill") {
        app.push(.country(home.place.chartCountry))
      },
      Shortcut(id: "genres", title: "Gêneros", icon: "square.grid.2x2.fill") {
        app.homePath.append(LumeHub.genres)
      },
      Shortcut(id: "releases", title: "Lançamentos", icon: "sparkles.rectangle.stack.fill") {
        let list = releaseItems
        if list.isEmpty { app.push(.releases) } else { app.push(.albums("Lançamentos", list)) }
      },
      Shortcut(id: "coverflow", title: "Cover Flow", icon: "square.stack.3d.down.right.fill") {
        Haptics.medium()
        app.showCoverFlow = true
      },
      Shortcut(id: "playlists", title: "Minhas playlists", icon: "music.note.list") {
        app.select(.library)
      },
      Shortcut(id: "flow", title: "Lume Flow", icon: "infinity") {
        Haptics.medium()
        app.startFlow()
      },
    ]
  }

  private var shortcuts: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
      ForEach(shortcutItems) { item in
        Button {
          Haptics.light()
          item.action()
        } label: {
          VStack(spacing: 8) {
            Image(systemName: item.icon)
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(Theme.prism)
              .frame(height: 26)
            Text(item.title)
              .font(Theme.font(12.5, .semibold))
              .foregroundStyle(Theme.text)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          .frame(maxWidth: .infinity)
          .frame(height: 80)
          .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
          .glass(22, interactive: true)
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .accessibilityLabel(item.title)
      }
    }
    .glassGroup(spacing: 10)
    .padding(.horizontal, gutter)
  }

  // MARK: Para você

  private var forYouMixes: [PersonalizedMix] {
    var mixes = home.genreMixes
    let fromHistory = CatalogExplorerService.buildPersonalizedMixes(
      mostPlayed: store.mostPlayedTracks,
      favorites: store.favoriteTracks,
      recent: store.recentTracks,
      topArtists: store.topListenedArtists,
      feed: nil
    )
    mixes += fromHistory.filter { ["mix_norepeat", "mix_daily1", "mix_daily2", "mix_favorites"].contains($0.id) }
    return Array(mixes.prefix(6))
  }

  @ViewBuilder
  private var forYou: some View {
    let mixes = forYouMixes
    if !mixes.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Para você", subtitle: OnboardingGenres.selected().isEmpty
                      ? "Com base no que você ouve" : "Seus gêneros e o que você ouve")
        HRow(spacing: 14) {
          ForEach(mixes) { mix in PersonalizedMixCard(mix: mix) }
        }
      }
    }
  }

  // MARK: Top 10 com seletor de país

  private var topTen: some View {
    let place = home.place
    return VStack(alignment: .leading, spacing: 14) {
      SectionHeader(
        title: place.title,
        subtitle: home.current?.caption ?? (place.isGlobal ? "Parada mundial · Deezer" : "Carregando a parada…"),
        actionLabel: "Top 50"
      ) {
        app.push(.country(place.chartCountry))
      }

      PlaceChipsBar(selected: place.id) { p in
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { home.select(p) }
      }

      ChartTrackList(list: home.current, loading: home.isLoadingCurrent || !home.settled, limit: 10) {
        Task { await home.refresh() }
      }
      .id(place.id)
      .transition(.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 10)),
        removal: .opacity))
    }
    .animation(.spring(response: 0.36, dampingFraction: 0.86), value: place.id)
  }

  // MARK: Lançamentos

  private var releaseItems: [AlbumShowcase] {
    guard let feed = home.feed else { return app.artistReleases }
    let regional = home.homePlace.id == "br" ? (feed.brazilReleases + feed.newReleases) : (feed.newReleases + feed.brazilReleases)
    var seen = Set<String>()
    var out: [AlbumShowcase] = []
    for a in app.artistReleases + regional {
      let key = DiscText.normalize(a.title) + "|" + DiscText.normalize(a.artist)
      if seen.insert(key).inserted { out.append(a) }
    }
    return out
  }

  @ViewBuilder
  private var releases: some View {
    let items = releaseItems
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(
        title: "Lançamentos",
        subtitle: app.artistReleases.isEmpty ? "Álbuns e singles recentes" : "Novidades dos seus artistas e do que está em alta",
        actionLabel: items.isEmpty ? nil : "Ver tudo"
      ) {
        app.push(.albums("Lançamentos", items))
      }
      if items.isEmpty {
        HStack(spacing: 14) {
          ForEach(0..<3, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 8) {
              SoftBlock(width: 150, height: 150, radius: 12)
              SoftBlock(width: 110, height: 13, radius: 6)
            }
          }
        }
        .padding(.horizontal, gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
      } else {
        HRow {
          ForEach(items.prefix(16)) { a in AlbumTile(album: a, width: 150, showDate: a.releaseDate != nil) }
        }
      }
    }
  }
}

// MARK: - Hero release carousel

struct ReleaseHeroCarousel: View {
  let albums: [AlbumShowcase]
  /// Texto da etiqueta de cada capa (ex.: "#1 · BRASIL"). Se nil, usa tipo + data de lançamento.
  var kicker: ((Int, AlbumShowcase) -> String)? = nil
  @State private var page: Int? = 0

  var body: some View {
    VStack(spacing: 12) {
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 12) {
          ForEach(Array(albums.prefix(8).enumerated()), id: \.element.id) { idx, alb in
            ReleaseHeroCard(album: alb, strip: strip(after: idx), kickerOverride: kicker?(idx, alb))
              .containerRelativeFrame(.horizontal) { w, _ in w - 40 }
              .id(idx)
          }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 20)
      }
      .scrollTargetBehavior(.viewAligned)
      .scrollPosition(id: $page)
      .scrollClipDisabled()

      HStack(spacing: 6) {
        ForEach(0..<min(8, albums.count), id: \.self) { i in
          Capsule()
            .fill(i == (page ?? 0) ? AnyShapeStyle(Theme.prism) : AnyShapeStyle(Theme.tertiary))
            .frame(width: i == (page ?? 0) ? 18 : 6, height: 6)
        }
      }
      .frame(maxWidth: .infinity)
      .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
    }
  }

  private func strip(after idx: Int) -> [AlbumShowcase] {
    var out: [AlbumShowcase] = []
    var i = idx
    while out.count < 4 && !albums.isEmpty {
      out.append(albums[i % albums.count])
      i += 1
      if i - idx > albums.count { break }
    }
    return out
  }
}

struct ReleaseHeroCard: View {
  let album: AlbumShowcase
  let strip: [AlbumShowcase]
  var kickerOverride: String? = nil

  var body: some View {
    Button {
      Haptics.medium()
      AppModel.shared.push(.album(album))
    } label: {
      VStack(spacing: 0) {
        VStack(spacing: 8) {
          Text(kicker)
            .font(Theme.font(11.5, .semibold))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .glassCapsule(clear: true)
          Text(album.title)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
          Text(album.artist)
            .font(Theme.font(15, .medium))
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)

        Spacer(minLength: 16)

        HStack(spacing: 8) {
          ForEach(Array(strip.enumerated()), id: \.offset) { i, a in
            ArtworkImage(url: a.artworkURL, cornerRadius: 16, maxPixel: 360)
              .frame(maxWidth: .infinity)
              .frame(height: 124)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                  .stroke(.white.opacity(i == 0 ? 0.9 : 0.35), lineWidth: i == 0 ? 1.6 : 0.7)
              )
              .shadow(color: .black.opacity(0.35), radius: 8, y: 5)
              .onTapGesture {
                Haptics.light()
                AppModel.shared.push(.album(a))
              }
          }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
      }
      .frame(height: 332)
      .frame(maxWidth: .infinity)
      .background {
        ZStack {
          ArtworkImage(url: album.artworkURL, cornerRadius: 0, maxPixel: 300)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(1.5)
            .blur(radius: 34)
            .clipped()
          LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
          LinearGradient(colors: [Theme.lavender.opacity(0.18), Theme.rose.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 0.8))
      .lumeShadow(20, y: 12, opacity: 0.55)
      .environment(\.colorScheme, .dark)
    }
    .buttonStyle(PressableStyle(scale: 0.98))
  }

  private var kicker: String {
    if let kickerOverride { return kickerOverride }
    var parts: [String] = []
    parts.append((album.kind ?? "Lançamento").uppercased())
    let d = Theme.shortDate(album.releaseDate)
    if !d.isEmpty { parts.append(d.uppercased()) }
    return parts.joined(separator: " · ")
  }
}
