import SwiftUI

/// Home — editorial, airy, Liquid Glass. Inspired by the Serene mockups: clean header, glass search pill,
/// prism filter chips, a hero release carousel, tall editorial cards and a prism banner.
struct HomeView: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared
  @State private var filter: HomeFilter = .all

  enum HomeFilter: String, CaseIterable, Identifiable {
    case all = "Tudo"
    case releases = "Lançamentos"
    case trending = "Em alta"
    case artists = "Artistas"
    case brazil = "Brasil"
    case world = "Mundo"
    var id: String { rawValue }
  }

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 26) {
        header
        searchPill
        chips
        if let feed = app.feed {
          content(feed)
            .transition(.opacity)
        } else {
          skeleton
        }
        Text(Theme.credit)
          .font(Theme.font(11.5))
          .foregroundStyle(Theme.tertiary)
          .frame(maxWidth: .infinity)
          .padding(.top, 6)
      }
      .padding(.top, 6)
      .animation(.easeInOut(duration: 0.25), value: filter)
    }
    .background(homeBackdrop)
    .refreshable {
      await app.loadFeed(force: true)
      await app.refreshArtistReleases()
    }
    .onChange(of: app.feed?.topArtists.count) { _, _ in
      if let a = app.feed?.topArtists { ArtworkStore.shared.register(a) }
    }
    .onAppear { if let a = app.feed?.topArtists { ArtworkStore.shared.register(a) } }
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

  // MARK: Header

  private var header: some View {
    HStack(spacing: 12) {
      LumeWordmark(size: 27)
      Spacer()
      GlassIconButton(systemName: "bell", size: 42, badge: app.hasUnseenReleases) {
        app.push(.releases)
      }
      .accessibilityLabel("Novidades dos seus artistas")
      GlassIconButton(systemName: "gearshape", size: 42) {
        app.push(.settings)
      }
      .accessibilityLabel("Ajustes")
    }
    .glassGroup()
    .padding(.horizontal, 20)
  }

  private var searchPill: some View {
    Button {
      app.select(.search)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 16, weight: .semibold))
        Text("Músicas, artistas, álbuns e letras")
          .font(Theme.font(16))
        Spacer()
        Image(systemName: "mic.fill")
          .font(.system(size: 14))
      }
      .foregroundStyle(Theme.secondary)
      .padding(.horizontal, 18)
      .frame(height: 50)
      .glassCapsule(interactive: true)
    }
    .buttonStyle(PressableStyle(scale: 0.98))
    .padding(.horizontal, 20)
  }

  private var chips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(HomeFilter.allCases) { f in
          PrismChip(title: f.rawValue, active: filter == f) { filter = f }
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 4)
    }
    .scrollClipDisabled()
  }

  // MARK: Content per filter

  @ViewBuilder
  private func content(_ feed: DiscoverFeed) -> some View {
    switch filter {
    case .all:
      VStack(alignment: .leading, spacing: 30) {
        if !app.artistReleases.isEmpty { yourArtistsReleases }
        heroSection(feed.newReleases.isEmpty ? feed.brazilReleases : feed.newReleases)
        trendingBrazil(feed.topBrazil)
        flowBanner
        artistsRow(feed.topArtists)
        recentSection
        topGrid(title: "Top 50 Mundo", subtitle: "As mais tocadas no planeta agora", tracks: feed.topGlobal)
        coverFlowCard(feed)
        albumRow(title: "Novidades do Brasil", albums: feed.brazilReleases)
        topGrid(title: "Em alta", subtitle: "Subindo rápido nas paradas", tracks: feed.trending)
        albumRow(title: "Lançamentos no mundo", albums: Array(feed.newReleases.dropFirst(5)))
      }
    case .releases:
      VStack(alignment: .leading, spacing: 30) {
        if !app.artistReleases.isEmpty { yourArtistsReleases }
        heroSection(feed.newReleases)
        albumGrid(feed.newReleases + feed.brazilReleases)
      }
    case .trending:
      VStack(alignment: .leading, spacing: 30) {
        trendingBrazil(feed.topBrazil)
        topGrid(title: "Top 50 Mundo", subtitle: nil, tracks: feed.topGlobal)
        topGrid(title: "Em alta", subtitle: nil, tracks: feed.trending)
      }
    case .artists:
      artistGrid(feed.topArtists)
    case .brazil:
      VStack(alignment: .leading, spacing: 30) {
        trendingBrazil(feed.topBrazil)
        albumRow(title: "Novidades do Brasil", albums: feed.brazilReleases)
        topList(title: "Top 50 Brasil", tracks: feed.topBrazil)
      }
    case .world:
      VStack(alignment: .leading, spacing: 30) {
        heroSection(feed.newReleases)
        topList(title: "Top 50 Mundo", tracks: feed.topGlobal)
      }
    }
  }

  // MARK: Sections

  private var yourArtistsReleases: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(title: "Novidades dos seus artistas", subtitle: "Lançamentos de quem você ouve", actionLabel: "Ver tudo") {
        app.push(.releases)
      }
      HRow {
        ForEach(app.artistReleases.prefix(12)) { alb in
          AlbumTile(album: alb, width: 150, showDate: true)
        }
      }
    }
  }

  @ViewBuilder
  private func heroSection(_ albums: [AlbumShowcase]) -> some View {
    if !albums.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Lançamentos da semana", actionLabel: "Ver tudo") {
          app.push(.albums("Lançamentos", albums))
        }
        ReleaseHeroCarousel(albums: Array(albums.prefix(20)))
      }
    }
  }

  @ViewBuilder
  private func trendingBrazil(_ tracks: [Track]) -> some View {
    if !tracks.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Em alta no Brasil", actionLabel: "Tocar tudo") {
          if let f = tracks.first { player.play(f, in: tracks); app.showPlayer = true }
        }
        HRow(spacing: 14) {
          ForEach(Array(tracks.prefix(15).enumerated()), id: \.element.id) { idx, tr in
            TallTrackCard(track: tr, rank: idx + 1) { player.play(tr, in: tracks) }
          }
        }
      }
    }
  }

  /// Prism banner (Serene "Special Offer"-style) with a stacked glass shadow card.
  private var flowBanner: some View {
    Button {
      Haptics.medium()
      app.startFlow()
    } label: {
      ZStack(alignment: .bottom) {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .fill(Theme.text.opacity(0.08))
          .frame(height: 30)
          .padding(.horizontal, 36)
          .offset(y: 14)
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .fill(Theme.text.opacity(0.10))
          .frame(height: 30)
          .padding(.horizontal, 18)
          .offset(y: 7)
        HStack(spacing: 14) {
          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
              Image(systemName: "infinity").font(.system(size: 15, weight: .bold))
              Text("Lume Flow").font(.system(size: 22, weight: .bold, design: .rounded))
            }
            Text("Uma rádio infinita com a sua cara, criada a partir do que você mais ouve.")
              .font(Theme.font(13.5, .medium))
              .multilineTextAlignment(.leading)
              .opacity(0.8)
          }
          Spacer(minLength: 4)
          Image(systemName: "play.fill")
            .font(.system(size: 18, weight: .bold))
            .frame(width: 50, height: 50)
            .background(Circle().fill(.white.opacity(0.55)))
            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 0.8))
        }
        .foregroundStyle(Theme.onPrism)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background {
          ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.prismDiagonal)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
              .fill(LinearGradient(colors: [.white.opacity(0.45), .clear, .white.opacity(0.15)], startPoint: .top, endPoint: .bottom))
          }
        }
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.65), lineWidth: 1))
        .shadow(color: Theme.rose.opacity(0.30), radius: 20, y: 10)
      }
      .padding(.bottom, 12)
    }
    .buttonStyle(PressableStyle(scale: 0.98))
    .padding(.horizontal, 20)
  }

  @ViewBuilder
  private func artistsRow(_ artists: [ArtistInfo]) -> some View {
    if !artists.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Cantores mais ouvidos", subtitle: "Os nomes do momento nas plataformas", actionLabel: "Ver todos") {
          app.push(.artists("Cantores mais ouvidos", artists))
        }
        HRow(spacing: 16) {
          ForEach(artists.prefix(20)) { a in
            ArtistBubble(name: a.name, pictureURL: a.pictureURL, deezerId: a.deezerId)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var recentSection: some View {
    let recent = Array(store.recentTracks.prefix(14))
    if !recent.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: "Tocadas recentemente", actionLabel: "Histórico") {
          app.push(.tracks("Histórico", store.recentTracks))
        }
        HRow(spacing: 12) {
          ForEach(recent) { tr in PlayCard(track: tr, queue: recent) }
        }
      }
    }
  }

  @ViewBuilder
  private func topGrid(title: String, subtitle: String?, tracks: [Track]) -> some View {
    if !tracks.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        SectionHeader(title: title, subtitle: subtitle, actionLabel: "Ver tudo") {
          app.push(.tracks(title, tracks))
        }
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHGrid(rows: Array(repeating: GridItem(.fixed(62), spacing: 2), count: 4), spacing: 18) {
            ForEach(Array(tracks.prefix(20).enumerated()), id: \.element.id) { idx, tr in
              TrackRow(track: tr, rank: idx + 1, queue: tracks)
                .containerRelativeFrame(.horizontal) { w, _ in w - 56 }
            }
          }
          .scrollTargetLayout()
          .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
      }
    }
  }

  @ViewBuilder
  private func topList(title: String, tracks: [Track]) -> some View {
    if !tracks.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: title, actionLabel: "Tocar") {
          if let f = tracks.first { player.play(f, in: tracks) }
        }
        LazyVStack(spacing: 0) {
          ForEach(Array(tracks.prefix(50).enumerated()), id: \.element.id) { idx, tr in
            TrackRow(track: tr, rank: idx + 1, queue: tracks)
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }

  @ViewBuilder
  private func albumRow(title: String, albums: [AlbumShowcase]) -> some View {
    if !albums.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        SectionHeader(title: title, actionLabel: "Ver tudo") {
          app.push(.albums(title, albums))
        }
        HRow {
          ForEach(albums.prefix(16)) { a in AlbumTile(album: a, width: 150, showDate: a.releaseDate != nil) }
        }
      }
    }
  }

  private func albumGrid(_ albums: [AlbumShowcase]) -> some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 20) {
      ForEach(albums) { a in
        GeometryReader { g in
          AlbumTile(album: a, width: g.size.width, showDate: true)
        }
        .aspectRatio(0.78, contentMode: .fit)
      }
    }
    .padding(.horizontal, 20)
  }

  private func artistGrid(_ artists: [ArtistInfo]) -> some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 22) {
      ForEach(artists) { a in ArtistBubble(name: a.name, pictureURL: a.pictureURL, deezerId: a.deezerId, size: 96) }
    }
    .padding(.horizontal, 16)
  }

  private func coverFlowCard(_ feed: DiscoverFeed) -> some View {
    let covers = Array((feed.newReleases + feed.brazilReleases).prefix(5))
    return Button {
      Haptics.medium()
      app.showCoverFlow = true
    } label: {
      VStack(spacing: 14) {
        ZStack {
          ForEach(Array(covers.enumerated()), id: \.element.id) { idx, a in
            let d = Double(idx - 2)
            ArtworkImage(url: a.artworkURL, cornerRadius: 6, maxPixel: 300)
              .frame(width: 112, height: 112)
              .rotation3DEffect(.degrees(d == 0 ? 0 : (d > 0 ? -62 : 62)), axis: (0, 1, 0), perspective: 0.5)
              .offset(x: d == 0 ? 0 : (d > 0 ? 50 + (d - 1) * 30 : -50 + (d + 1) * 30))
              .scaleEffect(d == 0 ? 1.08 : 0.92)
              .zIndex(10 - abs(d))
              .shadow(color: .black.opacity(0.5), radius: 8, y: 6)
          }
        }
        .frame(height: 130)
        .padding(.top, 18)
        VStack(spacing: 3) {
          Text("Cover Flow").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
          Text("Folheie as capas em 3D, como no iPod clássico")
            .font(Theme.font(13.5)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(.bottom, 20)
      }
      .frame(maxWidth: .infinity)
      .background {
        ZStack {
          LinearGradient(colors: [Color(white: 0.13), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)
          LinearGradient(colors: [.clear, Theme.lavender.opacity(0.22)], startPoint: .top, endPoint: .bottom)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.8))
      .lumeShadow(18, y: 10, opacity: 0.6)
    }
    .buttonStyle(PressableStyle(scale: 0.98))
    .padding(.horizontal, 20)
  }

  private var skeleton: some View {
    VStack(alignment: .leading, spacing: 18) {
      SkeletonBlock(width: 180, height: 22, radius: 8).padding(.horizontal, 20)
      SkeletonBlock(height: 360, radius: 30).padding(.horizontal, 20)
      SkeletonBlock(width: 160, height: 22, radius: 8).padding(.horizontal, 20)
      HStack(spacing: 14) {
        SkeletonBlock(width: 206, height: 276, radius: 26)
        SkeletonBlock(width: 206, height: 276, radius: 26)
      }
      .padding(.horizontal, 20)
    }
  }
}

// MARK: - Hero release carousel (Serene right-phone card)

struct ReleaseHeroCarousel: View {
  let albums: [AlbumShowcase]
  @State private var page: Int? = 0

  var body: some View {
    VStack(spacing: 12) {
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 12) {
          ForEach(Array(albums.prefix(8).enumerated()), id: \.element.id) { idx, alb in
            ReleaseHeroCard(album: alb, strip: strip(after: idx))
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
    var parts: [String] = []
    parts.append((album.kind ?? "Lançamento").uppercased())
    let d = Theme.shortDate(album.releaseDate)
    if !d.isEmpty { parts.append(d.uppercased()) }
    return parts.joined(separator: " · ")
  }
}
