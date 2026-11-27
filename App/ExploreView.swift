import SwiftUI

/// Explorar — paradas por país e Global (seletor), cantores mais ouvidos (Brasil/Mundo),
/// gêneros reais, climas, décadas e lançamentos.
struct ExploreView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var home = HomeStore.shared

  @State private var place: ChartPlace = HomeStore.shared.place
  @State private var list: ChartList?
  @State private var loadingChart = false
  @State private var artistScope: ArtistScope = .brazil
  @State private var browseGroup: BrowseGroup = .brasil

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
      LazyVStack(alignment: .leading, spacing: 30) {
        header
        chartsSection
        if let feed = app.feed ?? home.feed {
          content(feed)
            .transition(.opacity)
        } else {
          skeleton
        }
      }
      .padding(.top, 6)
      .padding(.bottom, 16)
      .animation(.spring(response: 0.3, dampingFraction: 0.88), value: artistScope)
      .animation(.spring(response: 0.3, dampingFraction: 0.88), value: browseGroup)
      .animation(.easeInOut(duration: 0.25), value: app.feed == nil)
    }
    .lumeTabScroll()
    .background(backdrop)
    .refreshable {
      await home.refresh()
      await app.refreshArtistReleases()
      await loadChart(force: true)
    }
    .navigationDestination(for: LumeHub.self) { hub in
      switch hub {
      case .genres: GenresHubView()
      }
    }
    .task(id: place.id) { await loadChart() }
  }

  /// Mostra o cache na hora e atualiza em seguida.
  private func loadChart(force: Bool = false) async {
    if let cached = await ChartsService.shared.cached(place) { list = cached } else { list = nil }
    loadingChart = true
    let fresh = await ChartsService.shared.load(place, force: force)
    guard !Task.isCancelled else { return }
    withAnimation(.easeOut(duration: 0.2)) { if let fresh { list = fresh } }
    loadingChart = false
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
      Text(list?.caption ?? "Paradas do mundo inteiro")
        .font(Theme.font(14))
        .foregroundStyle(Theme.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
  }

  // MARK: Paradas (país / Global)

  private var chartsSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeader(title: "Paradas", subtitle: "Top 10 de cada país e do mundo", actionLabel: "Top 50") {
        app.push(.country(place.chartCountry))
      }
      PlaceChipsBar(selected: place.id) { p in
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { place = p }
      }
      ChartTrackList(list: list, loading: loadingChart, limit: 10) {
        Task { await loadChart(force: true) }
      }
      .id(place.id)
      .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))

      if let albums = list?.albums, !albums.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          SectionHeader(
            title: place.isGlobal ? "Álbuns em alta no mundo" : "Álbuns mais ouvidos · \(place.name)",
            actionLabel: "Ver tudo"
          ) {
            app.push(.albums("Álbuns · \(place.name)", albums))
          }
          HRow {
            ForEach(albums.prefix(16)) { a in AlbumTile(album: a, width: 150, showDate: a.releaseDate != nil) }
          }
        }
        .padding(.top, 8)
      }
    }
    .animation(.spring(response: 0.36, dampingFraction: 0.86), value: place.id)
  }

  // MARK: Conteúdo

  @ViewBuilder
  private func content(_ feed: DiscoverFeed) -> some View {
    // Música brasileira de verdade (playlist "Top Brasil" do Deezer) — a parada da Apple traz muitos hits gringos.
    if let hits = feed.brazilianHits, !hits.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Música brasileira", subtitle: "Só o que é nacional e está tocando agora", actionLabel: "Tocar") {
          if let f = hits.first { AudioPlayer.shared.play(f, in: hits, context: "Música brasileira") }
        }
        HRow(spacing: 14) {
          ForEach(Array(hits.prefix(15).enumerated()), id: \.element.id) { idx, tr in
            TallTrackCard(track: tr, rank: idx + 1, caption: "música brasileira") {
              AudioPlayer.shared.play(tr, in: hits, context: "Música brasileira")
            }
          }
        }
      }
    }

    // Cantores mais ouvidos (Brasil | Mundo)
    artistsSpotlight(feed)

    // Em alta no YouTube Music Brasil
    if !feed.trending.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Em alta no YouTube Music", subtitle: "Vídeos de música em alta no Brasil", actionLabel: "Ver tudo") {
          app.push(.tracks("Em alta · YouTube Music Brasil", feed.trending))
        }
        HRow(spacing: 12) {
          ForEach(feed.trending.prefix(12)) { tr in PlayCard(track: tr, queue: feed.trending) }
        }
      }
    }

    // Gêneros, Climas e Décadas
    browseCategoriesSection

    // Lançamentos
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
          Text(artistScope == .brazil ? "Os mais tocados na parada brasileira" : "Os mais tocados na parada mundial")
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
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background {
                  if artistScope == sc { Capsule().fill(Theme.prism) } else { Capsule().fill(Theme.fill) }
                }
                .frame(height: 44)
                .contentShape(Capsule())
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
      .id(artistScope)
      .transition(.opacity)
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
      SoftBlock(width: 200, height: 22, radius: 8).padding(.horizontal, 20)
      HStack(spacing: 14) {
        SoftBlock(width: 206, height: 276, radius: 26)
        SoftBlock(width: 206, height: 276, radius: 26)
      }
      .padding(.horizontal, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .clipped()
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
