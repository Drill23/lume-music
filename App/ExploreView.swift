import SwiftUI

/// Explorar — paradas por país (18 países), mais ouvidas, cantores mais ouvidos (Brasil/Mundo),
/// 20 gêneros reais, climas, décadas e lançamentos.
struct ExploreView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var player = AudioPlayer.shared

  @State private var selectedCountry: ChartCountry = ChartCountry.all[0]
  @State private var countryPreview: CountryChartBundle?
  @State private var loadingCountry = false
  @State private var chartMode: ChartMode = .brazil
  @State private var artistScope: ArtistScope = .brazil
  @State private var browseGroup: BrowseGroup = .brasil

  enum ChartMode: String, CaseIterable, Identifiable {
    case brazil = "Top 50 Brasil"
    case world = "Top 50 Mundo"
    case trending = "Em Alta"
    var id: String { rawValue }
  }

  enum ArtistScope: String, CaseIterable, Identifiable {
    case brazil = "Brasil"
    case world = "Mundo"
    var id: String { rawValue }
  }

  enum BrowseGroup: String, CaseIterable, Identifiable {
    case brasil = "Gêneros BR"
    case international = "Internacional"
    case moods = "Climas"
    case decades = "Décadas"
    var id: String { rawValue }
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 28) {
        header
        if let feed = app.feed {
          content(feed)
            .transition(.opacity)
        } else {
          skeleton
        }
      }
      .padding(.top, 6)
      .padding(.bottom, 16)
      .animation(.easeInOut(duration: 0.25), value: app.feed == nil)
    }
    .background(backdrop)
    .refreshable {
      await app.loadFeed(force: true)
      await app.refreshArtistReleases()
      await loadCountryPreview(force: true)
    }
    .task(id: selectedCountry.code) {
      await loadCountryPreview()
    }
  }

  private func loadCountryPreview(force: Bool = false) async {
    loadingCountry = true
    countryPreview = await CatalogExplorerService.shared.countryChart(for: selectedCountry, force: force)
    loadingCountry = false
  }

  private var backdrop: some View {
    ZStack(alignment: .top) {
      Theme.canvas
      LinearGradient(
        colors: [Theme.sky.opacity(0.14), Theme.lavender.opacity(0.06), .clear],
        startPoint: .top, endPoint: .bottom
      )
      .frame(height: 380)
      .blur(radius: 20)
    }
    .ignoresSafeArea()
  }

  // MARK: Cabeçalho

  private var header: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("Explorar")
        .font(Theme.font(34, .bold))
        .foregroundStyle(Theme.text)
      if let updated = app.feed?.updatedAt {
        Text(updatedText(updated))
          .font(Theme.font(14))
          .foregroundStyle(Theme.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
  }

  private func updatedText(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.unitsStyle = .full
    if abs(date.timeIntervalSinceNow) < 60 { return "Paradas atualizadas agora" }
    return "Paradas atualizadas " + f.localizedString(for: date, relativeTo: Date())
  }

  // MARK: Conteúdo

  @ViewBuilder
  private func content(_ feed: DiscoverFeed) -> some View {
    // 1. Paradas por País
    countrySpotlightSection

    // 2. Mais Tocadas (Brasil / Mundo / Em Alta) + Top Álbuns
    chartsSection(feed)

    let topAlbums = chartMode == .world
      ? (feed.topAlbumsGlobal ?? feed.newReleases)
      : (feed.topAlbumsBrazil ?? feed.brazilReleases)
    if !topAlbums.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(
          title: chartMode == .world ? "Álbuns mais ouvidos no Mundo" : "Álbuns mais ouvidos no Brasil",
          actionLabel: "Ver tudo"
        ) {
          app.push(.albums("Álbuns em destaque", topAlbums))
        }
        HRow {
          ForEach(topAlbums.prefix(16)) { a in
            AlbumTile(album: a, width: 150, showDate: a.releaseDate != nil)
          }
        }
      }
    }

    // 3. Cantores mais ouvidos (Brasil | Mundo)
    artistsSpotlight(feed)

    // 4. Gêneros, Climas e Décadas
    browseCategoriesSection

    // 5. Lançamentos
    if !app.artistReleases.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Dos seus artistas", subtitle: "Lançamentos de quem você ouve", actionLabel: "Ver tudo") {
          app.push(.releases)
        }
        HRow {
          ForEach(app.artistReleases.prefix(12)) { alb in
            AlbumTile(album: alb, width: 150, showDate: true)
          }
        }
      }
    }

    weekReleases(feed.newReleases.isEmpty ? feed.brazilReleases : feed.newReleases)
  }

  // MARK: Paradas por País

  private var countrySpotlightSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeader(title: "Paradas por País", subtitle: "Veja o Top 50 ao vivo em qualquer região", actionLabel: "Abrir país") {
        app.push(.country(selectedCountry))
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(ChartCountry.all) { c in
            PrismChip(title: "\(c.flag) \(c.name)", active: c.code == selectedCountry.code) {
              selectedCountry = c
            }
          }
        }
        .padding(.horizontal, 20)
      }
      .scrollClipDisabled()

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          HStack(spacing: 8) {
            Text(selectedCountry.flag).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 1) {
              Text("Top 50 · \(selectedCountry.name)")
                .font(Theme.font(17, .bold))
                .foregroundStyle(Theme.text)
              Text(selectedCountry.region)
                .font(Theme.font(12))
                .foregroundStyle(Theme.secondary)
            }
          }
          Spacer()
          Button {
            Haptics.light()
            app.push(.country(selectedCountry))
          } label: {
            Text("Ver Top 50")
              .font(Theme.font(12.5, .semibold))
              .foregroundStyle(Theme.onPrism)
              .padding(.horizontal, 12)
              .frame(height: 30)
              .background(Capsule().fill(Theme.prismDiagonal))
          }
          .buttonStyle(PressableStyle(scale: 0.95))
        }

        if loadingCountry && countryPreview == nil {
          VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
              HStack(spacing: 12) {
                SkeletonBlock(width: 44, height: 44, radius: 8)
                SkeletonBlock(width: 170, height: 14, radius: 6)
                Spacer()
              }
            }
          }
        } else if let preview = countryPreview, !preview.topSongs.isEmpty {
          VStack(spacing: 0) {
            ForEach(Array(preview.topSongs.prefix(5).enumerated()), id: \.element.id) { idx, tr in
              TrackRow(track: tr, rank: idx + 1, queue: preview.topSongs)
            }
          }
        }
      }
      .padding(16)
      .glass(24)
      .padding(.horizontal, 20)
    }
  }

  // MARK: Mais Tocadas

  private func chartsSection(_ feed: DiscoverFeed) -> some View {
    let tracks: [Track] = {
      switch chartMode {
      case .brazil: return feed.topBrazil
      case .world: return feed.topGlobal
      case .trending: return feed.trending
      }
    }()

    return VStack(alignment: .leading, spacing: 12) {
      SectionHeader(title: "Mais tocadas", actionLabel: "Ver Top 50") {
        app.push(.tracks(chartMode.rawValue, tracks))
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(ChartMode.allCases) { m in
            PrismChip(title: m.rawValue, active: chartMode == m) { chartMode = m }
          }
        }
        .padding(.horizontal, 20)
      }
      .scrollClipDisabled()

      if !tracks.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(tracks.prefix(10).enumerated()), id: \.element.id) { idx, tr in
            TrackRow(track: tr, rank: idx + 1, queue: tracks)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }

  // MARK: Cantores mais ouvidos

  private func artistsSpotlight(_ feed: DiscoverFeed) -> some View {
    let list = (artistScope == .world && !(feed.globalTopArtists ?? []).isEmpty)
      ? (feed.globalTopArtists ?? [])
      : feed.topArtists
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 1) {
          Text("Cantores mais ouvidos")
            .font(Theme.font(21, .bold))
            .foregroundStyle(Theme.text)
          Text(artistScope == .brazil ? "Ranking de popularidade no Brasil" : "Ranking global nas plataformas")
            .font(Theme.font(13))
            .foregroundStyle(Theme.secondary)
        }
        Spacer()
        HStack(spacing: 4) {
          ForEach(ArtistScope.allCases) { sc in
            Button {
              Haptics.selection()
              artistScope = sc
            } label: {
              Text(sc.rawValue)
                .font(Theme.font(12, .semibold))
                .foregroundStyle(artistScope == sc ? Theme.onPrism : Theme.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background {
                  if artistScope == sc { Capsule().fill(Theme.prism) } else { Capsule().fill(Theme.fill) }
                }
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(.horizontal, 20)

      HRow(spacing: 16) {
        ForEach(Array(list.prefix(20).enumerated()), id: \.element.id) { idx, a in
          ArtistBubble(name: a.name, pictureURL: a.pictureURL, deezerId: a.deezerId, rank: a.rank ?? (idx + 1))
        }
      }
    }
  }

  // MARK: Gêneros, Climas & Décadas

  private var browseCategoriesSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeader(title: "Gêneros, Climas & Décadas")

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(BrowseGroup.allCases) { g in
            PrismChip(title: g.rawValue, active: browseGroup == g) { browseGroup = g }
          }
        }
        .padding(.horizontal, 20)
      }
      .scrollClipDisabled()

      switch browseGroup {
      case .brasil:
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
          ForEach(MusicGenre.all.filter { $0.group == .brasil }) { g in GenreCard(genre: g) }
        }
        .padding(.horizontal, 20)
      case .international:
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
          ForEach(MusicGenre.all.filter { $0.group == .internacional }) { g in GenreCard(genre: g) }
        }
        .padding(.horizontal, 20)
      case .moods:
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
          ForEach(MoodCategory.activities) { m in MoodCard(mood: m) }
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

  @ViewBuilder
  private func weekReleases(_ albums: [AlbumShowcase]) -> some View {
    if !albums.isEmpty {
      VStack(alignment: .leading, spacing: 14) {
        SectionHeader(title: "Lançamentos da semana", actionLabel: "Ver tudo") {
          app.push(.albums("Lançamentos da semana", albums))
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
          ForEach(albums.prefix(6)) { a in
            GeometryReader { g in
              AlbumTile(album: a, width: g.size.width, showDate: true)
            }
            .aspectRatio(0.78, contentMode: .fit)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }

  private var skeleton: some View {
    VStack(alignment: .leading, spacing: 20) {
      SkeletonBlock(width: 200, height: 22, radius: 8).padding(.horizontal, 20)
      SkeletonBlock(height: 220, radius: 24).padding(.horizontal, 20)
      SkeletonBlock(width: 160, height: 22, radius: 8).padding(.horizontal, 20)
      ForEach(0..<5, id: \.self) { _ in
        HStack(spacing: 12) {
          SkeletonBlock(width: 50, height: 50, radius: 8)
          VStack(alignment: .leading, spacing: 6) {
            SkeletonBlock(width: 170, height: 14, radius: 6)
            SkeletonBlock(width: 110, height: 12, radius: 6)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }
}

// MARK: - Cartões de estilo / clima (reutilizados)

struct MoodGrid: View {
  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
      ForEach(MoodCategory.presets) { m in MoodCard(mood: m) }
    }
    .padding(.horizontal, 20)
  }
}

struct MoodCard: View {
  let mood: MoodCategory

  var body: some View {
    Button {
      Haptics.light()
      AppModel.shared.push(.mood(mood))
    } label: {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(colors: [Theme.hex(mood.hexA), Theme.hex(mood.hexB)], startPoint: .topLeading, endPoint: .bottomTrailing)
        LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
        Image(systemName: mood.icon)
          .font(.system(size: 64, weight: .bold))
          .foregroundStyle(.white.opacity(0.28))
          .rotationEffect(.degrees(15))
          .offset(x: 20, y: 6)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .padding(.top, 8)
          .padding(.trailing, 4)
        Text(mood.title)
          .font(Theme.font(17, .bold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
          .padding(.horizontal, 14)
          .padding(.bottom, 12)
      }
      .frame(height: 100)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.8))
      .lumeShadow(10, y: 6, opacity: 0.45)
      .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    .buttonStyle(PressableStyle(scale: 0.97))
    .accessibilityLabel(mood.title)
  }
}
