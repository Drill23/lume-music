import SwiftUI

/// Navigation destinations pushed inside NavigationStack so native iOS swipe-from-left-edge back works everywhere!
enum LumeRoute: Hashable {
  case album(AlbumShowcase)
  case playlist(String)
  case importHub
  case coverFlow3D
  case mood(MoodCategory)
}

/// Main Lume Music 2.0 shell:
/// - True iOS 26 Native Liquid Glass Floating Tab Pill (.glassEffect) + Sleek Floating MiniPlayer
/// - Pinterest-inspired editorial Home (generous spacing, Hero multi-cover glass card, Tall full-bleed cards,
///   iridescent Import banner, 3D Cover Flow with real album art, Recently Played grid)
/// - Native NavigationStack swipe-to-go-back across all detail screens
struct RootTabShell: View {
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var downloads = DownloadManager.shared

  @State private var tab: AppTab = .home
  @State private var path = NavigationPath()
  @State private var topBrazil: [Track] = []
  @State private var newAlbums: [AlbumShowcase] = []
  @State private var globalHits: [Track] = []
  @State private var loadingFeed = false

  @State private var showPlayer = false
  @State private var playerTab: PlayerSurfaceTab = .artwork
  @State private var playlistPickerTrack: Track?
  @State private var toastText: String?

  var body: some View {
    ZStack(alignment: .bottom) {
      NavigationStack(path: $path) {
        ZStack {
          Theme.bg.ignoresSafeArea()
          RadialGradient(
            colors: [player.accentPrimary.opacity(0.18), player.accentSecondary.opacity(0.06), .clear],
            center: .top,
            startRadius: 10,
            endRadius: 460
          )
          .ignoresSafeArea()

          Group {
            switch tab {
            case .home:
              HomeScreen(
                topBrazil: topBrazil,
                newAlbums: newAlbums,
                loading: loadingFeed,
                onJumpSearch: { tab = .search },
                onOpenCoverFlow: { path.append(LumeRoute.coverFlow3D) },
                onOpenImport: { path.append(LumeRoute.importHub) },
                onOpenAlbum: { path.append(LumeRoute.album($0)) },
                onOpenPlayerMode: { mode in openPlayer(mode: mode) },
                onOpenOffline: { tab = .library },
                onAddToPlaylist: { playlistPickerTrack = $0 },
                onRefresh: { await loadFeed() }
              )
            case .explore:
              ExploreScreen(
                globalHits: globalHits,
                onOpenMood: { path.append(LumeRoute.mood($0)) },
                onAddToPlaylist: { playlistPickerTrack = $0 }
              )
            case .search:
              SearchScreen(
                onPlayAndOpen: { tr, list in
                  player.play(tr, in: list)
                },
                onAddToPlaylist: { playlistPickerTrack = $0 }
              )
            case .library:
              LibraryScreen(
                onOpenImport: { path.append(LumeRoute.importHub) },
                onOpenPlaylist: { path.append(LumeRoute.playlist($0.id)) },
                onAddToPlaylist: { playlistPickerTrack = $0 }
              )
            }
          }
        }
        .navigationDestination(for: LumeRoute.self) { route in
          switch route {
          case .album(let alb):
            AlbumDetailView(album: alb, onAddToPlaylist: { playlistPickerTrack = $0 })
          case .playlist(let plId):
            PlaylistDetailView(playlistId: plId, onAddToPlaylist: { playlistPickerTrack = $0 })
          case .importHub:
            ImportHubView(onImported: { msg in showToast(msg) })
          case .coverFlow3D:
            CoverFlowFullScreenView(items: coverFlowItems) { item in
              if let alb = item.album { path.append(LumeRoute.album(alb)) }
              else if let tr = item.track { player.play(tr, in: topBrazil); showPlayer = true }
            }
          case .mood(let mood):
            MoodDetailView(mood: mood, onAddToPlaylist: { playlistPickerTrack = $0 })
          }
        }
      }
      .tint(Theme.amber)

      // Floating Liquid Glass MiniPlayer + Compact iOS 26 Liquid Glass Tab Pill
      VStack(spacing: 10) {
        if let tr = player.currentTrack {
          MiniPlayerBar(track: tr) {
            showPlayer = true
          }
          .padding(.horizontal, 18)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        floatingGlassTabPill
      }
      .padding(.bottom, 10)

      // Top Feedback Toast
      if let msg = toastText {
        VStack {
          Text(msg)
            .font(Theme.font(13, .bold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .liquidGlassCapsule(tint: Theme.amber)
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            .padding(.top, 10)
          Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(99)
      }
    }
    .task {
      if topBrazil.isEmpty { await loadFeed() }
    }
    .onChange(of: downloads.lastMessage) { _, msg in if let msg { showToast(msg) } }
    .onChange(of: player.errorToast) { _, msg in if let msg { showToast(msg) } }
    .fullScreenCover(isPresented: $showPlayer) {
      PlayerSheetView(surfaceTab: $playerTab)
    }
    .sheet(item: $playlistPickerTrack) { tr in
      AddToPlaylistSheet(track: tr)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
  }

  private func openPlayer(mode: PlayerSurfaceTab) {
    playerTab = mode
    if player.currentTrack == nil, let first = topBrazil.first {
      player.play(first, in: topBrazil)
    }
    showPlayer = true
  }

  private var coverFlowItems: [CoverFlowView.CoverFlowItem] {
    var list: [CoverFlowView.CoverFlowItem] = []
    for alb in newAlbums.prefix(10) {
      list.append(.init(id: alb.id, title: alb.title, subtitle: alb.artist, badge: alb.year.isEmpty ? "NOVO" : alb.year, artworkURL: alb.artworkURL, track: nil, album: alb))
    }
    if list.isEmpty {
      for tr in (store.recentTracks + topBrazil).prefix(10) {
        list.append(.init(id: tr.id, title: tr.title, subtitle: tr.artist, badge: "EM ALTA", artworkURL: tr.artworkURL, track: tr, album: nil))
      }
    }
    return list
  }

  /// Compact floating iOS 26 Native Liquid Glass Tab Capsule (inspired by Serene reference!)
  @ViewBuilder
  private var floatingGlassTabPill: some View {
    let pill = HStack(spacing: 6) {
      ForEach(AppTab.allCases) { item in
        let active = tab == item && path.isEmpty
        Button {
          Haptics.selection()
          if !path.isEmpty { path = NavigationPath() }
          tab = item
        } label: {
          VStack(spacing: 3) {
            Image(systemName: item.icon)
              .font(.system(size: 18, weight: active ? .bold : .medium))
            Circle()
              .fill(active ? Theme.amber : Color.clear)
              .frame(width: 4.5, height: 4.5)
          }
          .foregroundStyle(active ? Color.white : Color.white.opacity(0.62))
          .frame(width: 58, height: 46)
          .background(
            Group {
              if active {
                Capsule().fill(Color.white.opacity(0.14))
              }
            }
          )
        }
        .accessibilityLabel(item.rawValue)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .liquidGlassCapsule(interactive: true)
    .shadow(color: .black.opacity(0.42), radius: 20, y: 10)

    if #available(iOS 26.0, *) {
      GlassEffectContainer { pill }
    } else {
      pill
    }
  }

  private func loadFeed() async {
    if let cached = await MusicEngine.shared.cachedHomeFeed() {
      topBrazil = cached.topBrazil
      newAlbums = cached.newAlbums
      globalHits = cached.globalHits
    }
    loadingFeed = topBrazil.isEmpty
    let feed = await MusicEngine.shared.fetchHomeFeed()
    if !feed.topBrazil.isEmpty { topBrazil = feed.topBrazil }
    if !feed.newAlbums.isEmpty { newAlbums = feed.newAlbums }
    if !feed.globalHits.isEmpty { globalHits = feed.globalHits }
    loadingFeed = false
  }

  private func showToast(_ text: String) {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toastText = text }
    Task {
      try? await Task.sleep(for: .seconds(3.0))
      if toastText == text {
        withAnimation(.easeOut(duration: 0.25)) { toastText = nil }
      }
    }
  }
}

// MARK: - Floating Liquid Glass MiniPlayer

struct MiniPlayerBar: View {
  let track: Track
  let onOpen: () -> Void
  @ObservedObject private var player = AudioPlayer.shared

  var body: some View {
    HStack(spacing: 12) {
      RemoteArtwork(url: track.artworkURL, cornerRadius: 18)
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.glassStroke, lineWidth: 0.8))

      VStack(alignment: .leading, spacing: 1) {
        Text(track.title)
          .font(Theme.font(13.5, .bold))
          .foregroundStyle(Theme.text)
          .lineLimit(1)
        Text(track.artist)
          .font(Theme.font(11.5, .medium))
          .foregroundStyle(Theme.text.opacity(0.68))
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      Button { player.togglePlayPause() } label: {
        Group {
          if player.isLoading {
            ProgressView().tint(Color.white).scaleEffect(0.8)
          } else {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(Color.white)
          }
        }
        .frame(width: 34, height: 34)
      }

      Button { player.nextTrack() } label: {
        Image(systemName: "forward.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.85))
          .frame(width: 32, height: 34)
      }
    }
    .padding(.leading, 8)
    .padding(.trailing, 10)
    .frame(height: 54)
    .liquidGlassCapsule(tint: player.accentPrimary, interactive: true)
    .shadow(color: .black.opacity(0.40), radius: 16, y: 6)
    .contentShape(Capsule())
    .onTapGesture { Haptics.light(); onOpen() }
    .gesture(
      DragGesture(minimumDistance: 24)
        .onEnded { val in
          if val.translation.width < -38 { player.nextTrack() }
          else if val.translation.width > 38 { player.previousTrack() }
          else if val.translation.height < -32 { onOpen() }
        }
    )
  }
}

// MARK: - Editorial Liquid Glass Home Screen (Inspired by Pinterest Reference #1!)

struct HomeScreen: View {
  let topBrazil: [Track]
  let newAlbums: [AlbumShowcase]
  let loading: Bool
  let onJumpSearch: () -> Void
  let onOpenCoverFlow: () -> Void
  let onOpenImport: () -> Void
  let onOpenAlbum: (AlbumShowcase) -> Void
  let onOpenPlayerMode: (PlayerSurfaceTab) -> Void
  let onOpenOffline: () -> Void
  let onAddToPlaylist: (Track) -> Void
  let onRefresh: () async -> Void

  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared
  @State private var activeChip = "Tudo"

  private let chips = ["Tudo", "Vinil", "K7", "Ondas Ares", "3D", "Offline"]

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 26) {
        // 1. Clean Minimal Header (Mark + "Lume" + 2 crisp Liquid Glass circular buttons)
        HStack(spacing: 10) {
          Image("Mark")
            .resizable()
            .scaledToFill()
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.glassStroke, lineWidth: 0.7))

          Text("Lume")
            .font(Theme.font(24, .heavy))
            .tracking(-0.6)
            .foregroundStyle(Theme.text)

          Spacer()

          Button { Haptics.light(); onOpenCoverFlow() } label: {
            Image(systemName: "square.stack.3d.forward.dottedline")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(Theme.text)
              .frame(width: 38, height: 38)
              .liquidGlassCircle(interactive: true)
          }

          Button { Haptics.light(); onOpenImport() } label: {
            Image(systemName: "square.and.arrow.down")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(Theme.amber)
              .frame(width: 38, height: 38)
              .liquidGlassCircle(interactive: true)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)

        // 2. Clean Search Bar Pill + Sleek Horizontal Category Chips (inspired by Serene!)
        VStack(spacing: 14) {
          Button {
            Haptics.light()
            onJumpSearch()
          } label: {
            HStack(spacing: 10) {
              Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
              Text("Buscar músicas, artistas, álbuns…")
                .font(Theme.font(14.5, .medium))
                .foregroundStyle(Theme.muted)
              Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .liquidGlassCapsule(interactive: true)
          }
          .padding(.horizontal, 20)

          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
              ForEach(chips, id: \.self) { chip in
                let isSelected = activeChip == chip
                Button {
                  Haptics.selection()
                  switch chip {
                  case "Vinil": onOpenPlayerMode(.vinyl)
                  case "K7": onOpenPlayerMode(.cassette)
                  case "Ondas Ares": onOpenPlayerMode(.waves)
                  case "3D": onOpenCoverFlow()
                  case "Offline": onOpenOffline()
                  default: activeChip = chip
                  }
                } label: {
                  Text(chip)
                    .font(Theme.font(13, .bold))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.text.opacity(0.88))
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(
                      Group {
                        if isSelected {
                          Capsule().fill(Theme.aurora)
                        }
                      }
                    )
                    .modifier(ChipGlassModifier(useGlass: !isSelected))
                }
              }
            }
            .padding(.horizontal, 20)
            .padding(.trailing, 12)
          }
          .mask(
            LinearGradient(
              stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.90), .init(color: .clear, location: 1)],
              startPoint: .leading, endPoint: .trailing
            )
          )
        }

        // 3. Hero Multi-Cover Liquid Glass Showcase Card (directly inspired by right phone in Reference #1!)
        if !newAlbums.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            SectionTitleRow(title: "Lançamentos da Semana", actionLabel: "Vitrine 3D", action: onOpenCoverFlow)

            HeroAlbumsGlassCard(albums: Array(newAlbums.prefix(4)), onOpenAlbum: onOpenAlbum)
              .padding(.horizontal, 20)
          }
        } else if loading {
          HStack { Spacer(); ProgressView().tint(Theme.amber).padding(.vertical, 50); Spacer() }
        }

        // 4. Tall Full-Bleed Editorial Feature Cards ("Em Alta no Brasil" — inspired by left phone in Reference #1!)
        if !topBrazil.isEmpty {
          VStack(alignment: .leading, spacing: 14) {
            SectionTitleRow(title: "Em Alta no Brasil", actionLabel: "Tocar tudo") {
              if let first = topBrazil.first { player.play(first, in: topBrazil) }
            }

            ScrollView(.horizontal, showsIndicators: false) {
              LazyHStack(spacing: 16) {
                ForEach(Array(topBrazil.prefix(10).enumerated()), id: \.element.id) { idx, tr in
                  TallEditorialTrackCard(
                    track: tr,
                    rank: idx + 1,
                    onPlay: { player.play(tr, in: topBrazil) }
                  )
                }
              }
              .padding(.horizontal, 20)
            }
          }
        }

        // 5. Iridescent Liquid Glass Action Banner (inspired by Special Offer card in Reference #1!)
        Button {
          Haptics.medium()
          onOpenImport()
        } label: {
          HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
              Text("Importe suas playlists")
                .font(Theme.font(17, .heavy))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.leading)
              Text("Traga do Apple Music, Spotify, YouTube Music ou Amazon em 1 clique.")
                .font(Theme.font(12.5, .medium))
                .foregroundStyle(Color.white.opacity(0.86))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            }
            Spacer(minLength: 6)
            Image(systemName: "arrow.right")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(Theme.ink)
              .frame(width: 34, height: 34)
              .background(Color.white, in: Circle())
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 18)
          .background(
            LinearGradient(
              colors: [
                Color(red: 0.44, green: 0.72, blue: 0.90).opacity(0.82),
                Color(red: 0.96, green: 0.62, blue: 0.44).opacity(0.88),
                Color(red: 0.88, green: 0.46, blue: 0.68).opacity(0.86)
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .stroke(Color.white.opacity(0.35), lineWidth: 1)
          )
          .shadow(color: Theme.coral.opacity(0.24), radius: 18, y: 8)
        }
        .padding(.horizontal, 20)

        // 6. Nostalgic iPod 3D Cover Flow (spacious, clean, with real album art!)
        if !newAlbums.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            SectionTitleRow(title: "Cover Flow 3D", actionLabel: "Tela cheia", action: onOpenCoverFlow)
            let cfItems: [CoverFlowView.CoverFlowItem] = newAlbums.prefix(10).map {
              .init(id: $0.id, title: $0.title, subtitle: $0.artist, badge: $0.year.isEmpty ? "NOVO" : $0.year, artworkURL: $0.artworkURL, track: nil, album: $0)
            }
            CoverFlowView(items: cfItems, cardSize: 194) { item in
              if let alb = item.album { onOpenAlbum(alb) }
            }
          }
        }

        // 7. Recently Played / Quick Art Grid (inspired by bottom of Reference #1!)
        let recentOrHits = store.recentTracks.isEmpty ? Array(topBrazil.dropFirst(10).prefix(6)) : Array(store.recentTracks.prefix(6))
        if !recentOrHits.isEmpty {
          VStack(alignment: .leading, spacing: 14) {
            SectionTitleRow(title: store.recentTracks.isEmpty ? "Descobertas do Dia" : "Ouvidas Recentemente")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
              ForEach(recentOrHits) { tr in
                Button {
                  Haptics.light()
                  player.play(tr, in: recentOrHits)
                } label: {
                  VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .bottomLeading) {
                      RemoteArtwork(url: tr.artworkURL, cornerRadius: 16)
                        .aspectRatio(1, contentMode: .fit)
                      Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(7)
                        .liquidGlassCircle()
                        .padding(7)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.glassStroke, lineWidth: 0.7))

                    Text(tr.title).font(Theme.font(12, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(tr.artist).font(Theme.font(10.5, .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                  }
                }
              }
            }
            .padding(.horizontal, 20)
          }
        }

        Text(Theme.credit)
          .font(Theme.font(11, .medium))
          .foregroundStyle(Theme.dim)
          .frame(maxWidth: .infinity)
          .padding(.top, 4)
          .padding(.bottom, player.currentTrack != nil ? 156 : 110)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .refreshable { await onRefresh() }
  }
}

private struct ChipGlassModifier: ViewModifier {
  let useGlass: Bool
  func body(content: Content) -> some View {
    if useGlass { content.liquidGlassCapsule(interactive: true) } else { content }
  }
}

/// Editorial Hero Glass Card with blurred artwork atmosphere + 4 floating rounded album covers inside (Reference #1 right!).
private struct HeroAlbumsGlassCard: View {
  let albums: [AlbumShowcase]
  let onOpenAlbum: (AlbumShowcase) -> Void

  var body: some View {
    VStack(spacing: 16) {
      VStack(spacing: 5) {
        Text("Som Que Inspira")
          .font(Theme.font(22, .heavy))
          .foregroundStyle(Color.white)
          .multilineTextAlignment(.center)
        Text("Novos álbuns e sucessos atualizados todo dia, prontos para tocar ou baixar.")
          .font(Theme.font(12.5, .medium))
          .foregroundStyle(Color.white.opacity(0.84))
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
      }
      .padding(.top, 22)

      // 4 floating mini album cards inside the hero container
      HStack(spacing: 10) {
        ForEach(albums.prefix(4)) { alb in
          Button {
            Haptics.light()
            onOpenAlbum(alb)
          } label: {
            RemoteArtwork(url: alb.artworkURL, cornerRadius: 14)
              .aspectRatio(0.86, contentMode: .fit)
              .frame(maxWidth: .infinity)
              .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .stroke(Color.white.opacity(0.30), lineWidth: 0.85)
              )
              .shadow(color: .black.opacity(0.42), radius: 10, y: 6)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 18)
    }
    .frame(maxWidth: .infinity)
    .background {
      ZStack {
        if let lead = albums.first {
          RemoteArtwork(url: lead.artworkURL, cornerRadius: 28)
            .blur(radius: 32)
            .scaleEffect(1.25)
            .opacity(0.68)
        }
        LinearGradient(
          colors: [Color(red: 0.14, green: 0.12, blue: 0.22).opacity(0.40), Color.black.opacity(0.58)],
          startPoint: .top,
          endPoint: .bottom
        )
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .stroke(Theme.glassStroke, lineWidth: 1.0)
    )
    .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
  }
}

/// Tall full-bleed editorial feature card with floating Liquid Glass mini-pill at top (Reference #1 left!).
private struct TallEditorialTrackCard: View {
  let track: Track
  let rank: Int
  let onPlay: () -> Void

  var body: some View {
    Button {
      Haptics.medium()
      onPlay()
    } label: {
      ZStack(alignment: .bottomLeading) {
        RemoteArtwork(url: track.artworkURL, cornerRadius: 24)
          .frame(width: 212, height: 268)

        // Subtle dual scrim so top glass pill and bottom typography always stay crisp over bright covers
        LinearGradient(
          stops: [
            .init(color: Color.black.opacity(0.36), location: 0),
            .init(color: .clear, location: 0.30),
            .init(color: Color.black.opacity(0.16), location: 0.58),
            .init(color: Color.black.opacity(0.88), location: 1.0)
          ],
          startPoint: .top,
          endPoint: .bottom
        )

        VStack(alignment: .leading) {
          // Floating Liquid Glass mini-pill at top of the tall card
          HStack(spacing: 7) {
            RemoteArtwork(url: track.artworkURL, cornerRadius: 12)
              .frame(width: 24, height: 24)
              .clipShape(Circle())
            VStack(alignment: .leading, spacing: 0) {
              Text(track.artist)
                .font(Theme.font(11.5, .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
              Text("Top #\(rank) · Brasil")
                .font(Theme.font(9.5, .medium))
                .foregroundStyle(Color.white.opacity(0.76))
                .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 2)
            Image(systemName: "play.fill")
              .font(.system(size: 9.5, weight: .bold))
              .foregroundStyle(Theme.amber)
          }
          .padding(.horizontal, 9)
          .padding(.vertical, 6)
          .liquidGlass(radius: 15)

          Spacer()

          VStack(alignment: .leading, spacing: 4) {
            Text(track.title.uppercased())
              .font(Theme.font(14.5, .heavy))
              .tracking(0.25)
              .foregroundStyle(Color.white)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
        }
        .padding(13)
      }
      .frame(width: 212, height: 268)
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(Theme.glassStroke, lineWidth: 0.9)
      )
      .shadow(color: .black.opacity(0.42), radius: 16, y: 8)
    }
  }
}

// MARK: - Explore Screen

struct ExploreScreen: View {
  let globalHits: [Track]
  let onOpenMood: (MoodCategory) -> Void
  let onAddToPlaylist: (Track) -> Void
  @ObservedObject private var player = AudioPlayer.shared

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 26) {
        Text("Explorar")
          .font(Theme.font(28, .heavy))
          .foregroundStyle(Theme.text)
          .padding(.horizontal, 20)
          .padding(.top, 10)

        VStack(alignment: .leading, spacing: 14) {
          SectionTitleRow(title: "Estilos & Climas")
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(MoodCategory.presets) { mood in
              Button {
                Haptics.selection()
                onOpenMood(mood)
              } label: {
                HStack(spacing: 10) {
                  Image(systemName: mood.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.20), in: Circle())
                  Text(mood.title)
                    .font(Theme.font(14, .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                  Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 62)
                .background(
                  LinearGradient(colors: [Theme.hex(mood.hexA).opacity(0.84), Theme.hex(mood.hexB).opacity(0.76)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                  in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.24), lineWidth: 0.8))
              }
            }
          }
          .padding(.horizontal, 20)
        }

        if !globalHits.isEmpty {
          VStack(alignment: .leading, spacing: 14) {
            SectionTitleRow(title: "Sucessos Globais", actionLabel: "Tocar tudo") {
              if let f = globalHits.first { player.play(f, in: globalHits) }
            }
            LazyVStack(spacing: 10) {
              ForEach(Array(globalHits.prefix(20).enumerated()), id: \.element.id) { idx, tr in
                TrackRowView(track: tr, rank: idx + 1, onPlay: { player.play(tr, in: globalHits) }, onAddToPlaylist: { onAddToPlaylist(tr) })
              }
            }
            .padding(.horizontal, 20)
          }
        }

        Spacer().frame(height: player.currentTrack != nil ? 156 : 100)
      }
    }
  }
}

struct MoodDetailView: View {
  let mood: MoodCategory
  let onAddToPlaylist: (Track) -> Void
  @ObservedObject private var player = AudioPlayer.shared
  @State private var tracks: [Track] = []
  @State private var loading = true

  var body: some View {
    ZStack {
      Theme.bg.ignoresSafeArea()
      RadialGradient(colors: [Theme.hex(mood.hexA).opacity(0.32), .clear], center: .top, startRadius: 10, endRadius: 420).ignoresSafeArea()
      ScrollView(showsIndicators: false) {
        VStack(spacing: 16) {
          if loading {
            ProgressView().tint(Theme.amber).padding(.top, 60)
          } else {
            Button {
              if let f = tracks.first { player.play(f, in: tracks) }
            } label: {
              Label("Tocar Mix \(mood.title)", systemImage: "play.fill")
                .font(Theme.font(15, .bold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Theme.aurora, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            LazyVStack(spacing: 10) {
              ForEach(tracks) { tr in
                TrackRowView(track: tr, onPlay: { player.play(tr, in: tracks) }, onAddToPlaylist: { onAddToPlaylist(tr) })
              }
            }
            .padding(.horizontal, 20)
          }
          Spacer().frame(height: 150)
        }
      }
    }
    .navigationTitle(mood.title)
    .navigationBarTitleDisplayMode(.large)
    .task {
      tracks = await MusicEngine.shared.searchSongs(query: mood.query, limit: 22)
      loading = false
    }
  }
}

// MARK: - Search Screen

struct SearchScreen: View {
  let onPlayAndOpen: (Track, [Track]) -> Void
  let onAddToPlaylist: (Track) -> Void
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared

  @State private var query = ""
  @State private var results: [Track] = []
  @State private var searching = false
  @State private var searchTask: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 14) {
        Text("Buscar")
          .font(Theme.font(28, .heavy))
          .foregroundStyle(Theme.text)

        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.amber)
          TextField("Músicas, artistas, álbuns…", text: $query)
            .font(Theme.font(15, .medium))
            .foregroundStyle(Theme.text)
            .submitLabel(.search)
            .onSubmit { triggerSearch(immediate: true) }
          if !query.isEmpty {
            Button { query = ""; results = [] } label: {
              Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
            }
          }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .liquidGlassCapsule(interactive: true)
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 14) {
          if searching {
            HStack { Spacer(); ProgressView().tint(Theme.amber).padding(.top, 44); Spacer() }
          } else if !results.isEmpty {
            LazyVStack(spacing: 10) {
              ForEach(results) { tr in
                TrackRowView(
                  track: tr,
                  onPlay: {
                    store.addSearchTerm(query)
                    onPlayAndOpen(tr, results)
                  },
                  onAddToPlaylist: { onAddToPlaylist(tr) }
                )
              }
            }
            .padding(.horizontal, 20)
          } else if !query.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(Theme.muted)
              Text("Nenhum resultado para “\(query)”").font(Theme.font(14.5, .bold)).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 54)
          } else if !store.searchHistory.isEmpty {
            SectionTitleRow(title: "Buscas recentes")
            VStack(spacing: 8) {
              ForEach(store.searchHistory, id: \.self) { term in
                Button { query = term; triggerSearch(immediate: true) } label: {
                  HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.muted)
                    Text(term).font(Theme.font(14.5, .medium)).foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: "arrow.up.left").font(.system(size: 12)).foregroundStyle(Theme.muted)
                  }
                  .padding(.horizontal, 16)
                  .frame(height: 46)
                  .liquidGlass(radius: 15)
                }
              }
            }
            .padding(.horizontal, 20)
          } else {
            VStack(spacing: 12) {
              Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Theme.amber.opacity(0.85))
              Text("Busque qualquer música")
                .font(Theme.font(17, .bold)).foregroundStyle(Theme.text)
              Text("Toque na hora, curta no Vinil ou K7, cante com letra traduzida e baixe offline.")
                .font(Theme.font(13, .medium)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 64)
          }
          Spacer().frame(height: player.currentTrack != nil ? 156 : 100)
        }
      }
    }
    .onChange(of: query) { _, _ in triggerSearch(immediate: false) }
  }

  private func triggerSearch(immediate: Bool) {
    searchTask?.cancel()
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { results = []; searching = false; return }
    searchTask = Task {
      if !immediate {
        try? await Task.sleep(for: .milliseconds(380))
        guard !Task.isCancelled else { return }
      }
      searching = true
      let found = await MusicEngine.shared.searchSongs(query: q, limit: 25)
      guard !Task.isCancelled else { return }
      results = found
      searching = false
    }
  }
}

// MARK: - Library Screen

struct LibraryScreen: View {
  let onOpenImport: () -> Void
  let onOpenPlaylist: (MusicPlaylist) -> Void
  let onAddToPlaylist: (Track) -> Void

  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared
  @State private var segment = 0
  @State private var showCreatePlaylist = false
  @State private var newPlaylistName = ""

  private let tabs = ["Playlists", "Curtidas", "Baixadas", "Histórico"]

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          Text("Biblioteca")
            .font(Theme.font(28, .heavy))
            .foregroundStyle(Theme.text)
          Spacer()
          Button { Haptics.light(); showCreatePlaylist = true } label: {
            Image(systemName: "plus")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(Theme.text)
              .frame(width: 38, height: 38)
              .liquidGlassCircle(interactive: true)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)

        Button { Haptics.medium(); onOpenImport() } label: {
          HStack(spacing: 14) {
            ZStack {
              Circle().fill(Theme.aurora).frame(width: 44, height: 44)
              Image(systemName: "arrow.down.doc.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: 3) {
              Text("Importar suas músicas em 1 clique").font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
              Text("Apple Music, Spotify, YouTube Music, Amazon ou lista").font(Theme.font(12, .medium)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.amber)
          }
          .padding(14)
          .liquidGlass(radius: 22, tint: Theme.amber, interactive: true)
        }
        .padding(.horizontal, 20)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 10) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { idx, label in
              let active = segment == idx
              Button { Haptics.selection(); segment = idx } label: {
                Text(label)
                  .font(Theme.font(13, .bold))
                  .foregroundStyle(active ? Theme.ink : Theme.text.opacity(0.84))
                  .padding(.horizontal, 18)
                  .frame(height: 36)
                  .background(active ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.clear), in: Capsule())
                  .modifier(ChipGlassModifier(useGlass: !active))
              }
            }
          }
          .padding(.horizontal, 20)
        }

        Group {
          if segment == 0 {
            playlistsSection
          } else if segment == 1 {
            tracksListSection(tracks: store.favoriteTracks, emptyTitle: "Nenhuma música curtida", emptySub: "Toque no coração em qualquer música para salvar aqui.")
          } else if segment == 2 {
            VStack(alignment: .leading, spacing: 12) {
              Text("Armazenamento offline: \(store.offlineStorageFormatted)")
                .font(Theme.font(12.5, .semibold))
                .foregroundStyle(Theme.ok)
                .padding(.horizontal, 20)
              tracksListSection(tracks: store.downloadedTracks, emptyTitle: "Nenhuma música baixada", emptySub: "Toque na seta ↓ em qualquer faixa ou playlist para ouvir sem internet.")
            }
          } else {
            tracksListSection(tracks: store.recentTracks, emptyTitle: "Histórico vazio", emptySub: "As músicas que você ouvir aparecem aqui.")
          }
        }

        Spacer().frame(height: player.currentTrack != nil ? 156 : 100)
      }
    }
    .alert("Nova Playlist", isPresented: $showCreatePlaylist) {
      TextField("Ex.: Estrada, Treino, Favoritas…", text: $newPlaylistName)
      Button("Cancelar", role: .cancel) { newPlaylistName = "" }
      Button("Criar") {
        let clean = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { store.createPlaylist(name: clean); Haptics.success() }
        newPlaylistName = ""
      }
    }
  }

  private var playlistsSection: some View {
    Group {
      if store.playlists.isEmpty {
        VStack(spacing: 10) {
          Image(systemName: "music.note.list").font(.system(size: 32)).foregroundStyle(Theme.muted)
          Text("Suas playlists aparecem aqui").font(Theme.font(15.5, .bold)).foregroundStyle(Theme.text)
          Text("Crie uma no botão + ou importe do Apple Music, Spotify e YouTube Music.")
            .font(Theme.font(13, .medium)).foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center).padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity).padding(.top, 36)
      } else {
        LazyVStack(spacing: 12) {
          ForEach(store.playlists) { pl in
            Button { Haptics.light(); onOpenPlaylist(pl) } label: {
              HStack(spacing: 14) {
                RemoteArtwork(url: pl.artworkURL, cornerRadius: 14, placeholderIcon: "music.note.list")
                  .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                  Text(pl.name).font(Theme.font(15.5, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                  HStack(spacing: 6) {
                    Text("\(pl.trackIds.count) faixas").font(Theme.font(12, .medium)).foregroundStyle(Theme.muted)
                    Text("· \(pl.sourceBadge)").font(Theme.font(11.5, .bold)).foregroundStyle(Theme.amber)
                  }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
              }
              .padding(10)
              .liquidGlass(radius: 18)
            }
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }

  private func tracksListSection(tracks: [Track], emptyTitle: String, emptySub: String) -> some View {
    Group {
      if tracks.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(Theme.muted)
          Text(emptyTitle).font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
          Text(emptySub).font(Theme.font(13, .medium)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 34)
        }
        .frame(maxWidth: .infinity).padding(.top, 36)
      } else {
        LazyVStack(spacing: 10) {
          ForEach(tracks) { tr in
            TrackRowView(track: tr, onPlay: { player.play(tr, in: tracks) }, onAddToPlaylist: { onAddToPlaylist(tr) })
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }
}

// MARK: - Native Pushed Detail Views (Swipe from Left Edge to Go Back!)

struct ImportHubView: View {
  let onImported: (String) -> Void
  @ObservedObject private var store = LibraryStore.shared
  @Environment(\.dismiss) private var dismiss

  @State private var linkText = ""
  @State private var rawListText = ""
  @State private var rawListName = ""
  @State private var busy = false
  @State private var statusMsg: String?
  @State private var isError = false

  var body: some View {
    ZStack {
      Theme.bg.ignoresSafeArea()
      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 10) {
            Text("APPLE MUSIC DESTE IPHONE").font(Theme.font(11, .bold)).tracking(1.6).foregroundStyle(Theme.amber)
            Button { Task { await runAppleMusicImport() } } label: {
              HStack(spacing: 12) {
                Image(systemName: "applelogo")
                  .font(.system(size: 20, weight: .bold))
                  .foregroundStyle(Theme.ink)
                  .frame(width: 42, height: 42)
                  .background(Theme.aurora, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                  Text("Importar da Biblioteca Apple Music").font(Theme.font(15, .bold)).foregroundStyle(Theme.text)
                  Text("Traz suas músicas e playlists do iPhone em 1 clique").font(Theme.font(12, .medium)).foregroundStyle(Theme.muted)
                }
                Spacer()
              }
              .padding(14)
              .liquidGlass(radius: 18, tint: Theme.coral, interactive: true)
            }
            .disabled(busy)
          }

          VStack(alignment: .leading, spacing: 10) {
            Text("POR LINK (SPOTIFY · YOUTUBE · APPLE · AMAZON)").font(Theme.font(11, .bold)).tracking(1.4).foregroundStyle(Theme.amber)
            TextField("Cole o link da playlist ou álbum público…", text: $linkText)
              .font(Theme.font(14, .medium)).foregroundStyle(Theme.text)
              .autocorrectionDisabled().textInputAutocapitalization(.never)
              .padding(.horizontal, 16).frame(height: 46).liquidGlassCapsule()
            Button { Task { await runLinkImport() } } label: {
              HStack {
                if busy { ProgressView().tint(Theme.ink) }
                Text("Importar Playlist do Link").font(Theme.font(14.5, .bold))
              }
              .foregroundStyle(Theme.ink)
              .frame(maxWidth: .infinity).frame(height: 46)
              .background(Theme.aurora, in: Capsule())
            }
            .disabled(busy || linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }

          VStack(alignment: .leading, spacing: 10) {
            Text("LISTA DE TEXTO OU M3U").font(Theme.font(11, .bold)).tracking(1.4).foregroundStyle(Theme.amber)
            TextField("Nome da playlist", text: $rawListName)
              .font(Theme.font(14, .medium)).foregroundStyle(Theme.text)
              .padding(.horizontal, 16).frame(height: 44).liquidGlassCapsule()
            TextEditor(text: $rawListText)
              .font(Theme.font(13, .regular)).foregroundStyle(Theme.text)
              .scrollContentBackground(.hidden).frame(height: 110).padding(12)
              .liquidGlass(radius: 18)
              .overlay(alignment: .topLeading) {
                if rawListText.isEmpty {
                  Text("Uma música por linha:\nThe Weeknd - Blinding Lights\nDaft Punk - Instant Crush")
                    .font(Theme.font(12.5, .regular)).foregroundStyle(Theme.dim)
                    .padding(18).allowsHitTesting(false)
                }
              }
            Button { Task { await runTextImport() } } label: {
              Text("Criar Playlist da Lista")
                .font(Theme.font(14, .bold)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity).frame(height: 46)
                .liquidGlassCapsule(interactive: true)
            }
            .disabled(busy || rawListText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }

          if let msg = statusMsg {
            Text(msg)
              .font(Theme.font(13, .semibold))
              .foregroundStyle(isError ? Theme.coral : Theme.ok)
              .padding(14).frame(maxWidth: .infinity, alignment: .leading)
              .liquidGlass(radius: 14, tint: isError ? Theme.coral : Theme.ok)
          }
          Spacer().frame(height: 130)
        }
        .padding(20)
      }
    }
    .navigationTitle("Importar Músicas")
    .navigationBarTitleDisplayMode(.large)
  }

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
      onImported("Importadas \(packs.count) playlists (\(total) faixas) do Apple Music!")
      dismiss()
    } catch { isError = true; statusMsg = error.localizedDescription }
    busy = false
  }

  private func runLinkImport() async {
    busy = true; statusMsg = nil; isError = false
    do {
      let res = try await ImportService.shared.importFromURL(linkText)
      store.createPlaylist(name: res.playlistName, sourceBadge: res.sourceBadge, artworkURL: res.artworkURL, tracks: res.tracks)
      Haptics.success()
      onImported("Importada “\(res.playlistName)” (\(res.tracks.count) faixas)!")
      dismiss()
    } catch { isError = true; statusMsg = error.localizedDescription }
    busy = false
  }

  private func runTextImport() async {
    let res = await ImportService.shared.importFromText(rawListText, name: rawListName)
    guard !res.tracks.isEmpty else { isError = true; statusMsg = "Cole pelo menos uma música acima."; return }
    store.createPlaylist(name: res.playlistName, sourceBadge: res.sourceBadge, tracks: res.tracks)
    Haptics.success()
    onImported("Criada “\(res.playlistName)” com \(res.tracks.count) faixas!")
    dismiss()
  }
}

struct AlbumDetailView: View {
  let album: AlbumShowcase
  let onAddToPlaylist: (Track) -> Void
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var downloads = DownloadManager.shared
  @State private var tracks: [Track] = []
  @State private var loading = true

  var body: some View {
    ZStack {
      Theme.bg.ignoresSafeArea()
      ScrollView(showsIndicators: false) {
        VStack(spacing: 20) {
          RemoteArtwork(url: album.artworkURL, cornerRadius: 24)
            .frame(width: 224, height: 224)
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.glassStroke, lineWidth: 1))
            .shadow(color: Theme.amber.opacity(0.24), radius: 26, y: 12)
            .padding(.top, 12)

          VStack(spacing: 4) {
            Text(album.title).font(Theme.font(22, .heavy)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Text("\(album.artist)\(album.year.isEmpty ? "" : " · \(album.year)")").font(Theme.font(14, .semibold)).foregroundStyle(Theme.muted)
          }
          .padding(.horizontal, 24)

          HStack(spacing: 12) {
            Button {
              if let f = tracks.first { player.play(f, in: tracks) }
            } label: {
              Label("Tocar", systemImage: "play.fill")
                .font(Theme.font(14.5, .bold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(Theme.aurora, in: Capsule())
            }
            Button {
              for t in tracks { downloads.download(t) }
            } label: {
              Label("Baixar tudo", systemImage: "arrow.down.to.line")
                .font(Theme.font(14.5, .bold)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity).frame(height: 46)
                .liquidGlassCapsule(interactive: true)
            }
          }
          .padding(.horizontal, 20)
          .disabled(tracks.isEmpty)

          if loading {
            ProgressView().tint(Theme.amber).padding(.top, 28)
          } else {
            LazyVStack(spacing: 10) {
              ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, tr in
                TrackRowView(track: tr, rank: idx + 1, onPlay: { player.play(tr, in: tracks) }, onAddToPlaylist: { onAddToPlaylist(tr) })
              }
            }
            .padding(.horizontal, 20)
          }
          Spacer().frame(height: 150)
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .task {
      tracks = await MusicEngine.shared.fetchAlbumTracks(albumTitle: album.title, artist: album.artist, fallbackArtwork: album.artworkURL)
      loading = false
    }
  }
}

struct PlaylistDetailView: View {
  let playlistId: String
  let onAddToPlaylist: (Track) -> Void
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var downloads = DownloadManager.shared
  @Environment(\.dismiss) private var dismiss

  private var playlist: MusicPlaylist? { store.playlists.first(where: { $0.id == playlistId }) }

  var body: some View {
    ZStack {
      Theme.bg.ignoresSafeArea()
      if let pl = playlist {
        let tracks = store.tracks(in: pl)
        ScrollView(showsIndicators: false) {
          VStack(spacing: 20) {
            RemoteArtwork(url: pl.artworkURL, cornerRadius: 24, placeholderIcon: "music.note.list")
              .frame(width: 200, height: 200)
              .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.glassStroke, lineWidth: 1))
              .padding(.top, 12)

            VStack(spacing: 4) {
              Text(pl.name).font(Theme.font(22, .heavy)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
              Text("\(tracks.count) faixas · \(pl.sourceBadge)").font(Theme.font(13, .semibold)).foregroundStyle(Theme.amber)
            }

            HStack(spacing: 12) {
              Button { if let f = tracks.first { player.play(f, in: tracks) } } label: {
                Label("Tocar", systemImage: "play.fill")
                  .font(Theme.font(14.5, .bold)).foregroundStyle(Theme.ink)
                  .frame(maxWidth: .infinity).frame(height: 46)
                  .background(Theme.aurora, in: Capsule())
              }
              Button { downloads.downloadPlaylist(pl) } label: {
                Label("Baixar offline", systemImage: "arrow.down.to.line")
                  .font(Theme.font(14.5, .bold)).foregroundStyle(Theme.text)
                  .frame(maxWidth: .infinity).frame(height: 46)
                  .liquidGlassCapsule(interactive: true)
              }
            }
            .padding(.horizontal, 20)
            .disabled(tracks.isEmpty)

            LazyVStack(spacing: 10) {
              ForEach(tracks) { tr in
                TrackRowView(track: tr, onPlay: { player.play(tr, in: tracks) }, onAddToPlaylist: { onAddToPlaylist(tr) })
              }
            }
            .padding(.horizontal, 20)

            Button(role: .destructive) { store.deletePlaylist(pl.id); dismiss() } label: {
              Text("Excluir playlist").font(Theme.font(13.5, .bold)).foregroundStyle(Theme.coral).padding(.vertical, 12)
            }
            Spacer().frame(height: 150)
          }
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Clean Reusable Components

struct SectionTitleRow: View {
  let title: String
  var actionLabel: String? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    HStack {
      Text(title)
        .font(Theme.font(19, .heavy))
        .foregroundStyle(Theme.text)
      Spacer()
      if let lbl = actionLabel, let act = action {
        Button { Haptics.light(); act() } label: {
          Text(lbl)
            .font(Theme.font(13, .semibold))
            .foregroundStyle(Theme.muted)
        }
      }
    }
    .padding(.horizontal, 20)
  }
}

struct TrackRowView: View {
  let track: Track
  var rank: Int? = nil
  let onPlay: () -> Void
  let onAddToPlaylist: () -> Void

  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared
  @ObservedObject private var downloads = DownloadManager.shared

  var body: some View {
    let active = player.currentTrack?.id == track.id
    HStack(spacing: 13) {
      if let r = rank {
        Text("\(r)")
          .font(Theme.font(13.5, .bold))
          .foregroundStyle(r <= 3 ? Theme.amber : Theme.muted)
          .frame(width: 22, alignment: .center)
          .monospacedDigit()
      }

      RemoteArtwork(url: track.artworkURL, cornerRadius: 12)
        .frame(width: 52, height: 52)
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(active ? Theme.amber : Color.white.opacity(0.12), lineWidth: active ? 1.6 : 0.6)
        )

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 5) {
          Text(track.title)
            .font(Theme.font(15, active ? .heavy : .semibold))
            .foregroundStyle(active ? Theme.amber : Theme.text)
            .lineLimit(1)
          if store.isDownloaded(track.id) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.ok)
          }
        }
        Text(track.artist)
          .font(Theme.font(12.5, .medium))
          .foregroundStyle(Theme.muted)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      if let p = downloads.progressById[track.id] {
        Circle()
          .trim(from: 0, to: CGFloat(p))
          .stroke(Theme.amber, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .frame(width: 18, height: 18)
      }

      Menu {
        Button { onPlay() } label: { Label("Tocar agora", systemImage: "play.fill") }
        Button { player.playNextInQueue(track) } label: { Label("Tocar a seguir", systemImage: "text.insert") }
        Button { store.toggleFavorite(track) } label: {
          Label(store.isFavorite(track.id) ? "Descurtir" : "Curtir", systemImage: store.isFavorite(track.id) ? "heart.slash" : "heart")
        }
        Button { onAddToPlaylist() } label: { Label("Adicionar à playlist", systemImage: "plus.circle") }
        if store.isDownloaded(track.id) {
          Button(role: .destructive) { store.removeDownload(track.id) } label: { Label("Remover download", systemImage: "trash") }
        } else {
          Button { downloads.download(track) } label: { Label("Baixar offline", systemImage: "arrow.down.to.line") }
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.muted)
          .frame(width: 34, height: 40)
      }
    }
    .padding(.vertical, 5)
    .contentShape(Rectangle())
    .onTapGesture {
      Haptics.light()
      onPlay()
    }
  }
}
