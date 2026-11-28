import SwiftUI

// MARK: - Routes

enum LumeRoute: Hashable {
  case album(AlbumShowcase)
  case playlist(String)
  case remotePlaylist(RemotePlaylist)
  case artist(String, Int?)
  case importHub
  case mood(MoodCategory)
  case country(ChartCountry)
  case genre(MusicGenre)
  case mix(PersonalizedMix)
  case releases
  case downloads
  case replay
  case equalizer
  case settings
  case tracks(String, [Track])
  case albums(String, [AlbumShowcase])
  case artists(String, [ArtistInfo])
}

// MARK: - App state

@MainActor
final class AppModel: ObservableObject {
  static let shared = AppModel()

  @Published var tab: AppTab = .home
  @Published var homePath = NavigationPath()
  @Published var explorePath = NavigationPath()
  @Published var libraryPath = NavigationPath()
  @Published var searchPath = NavigationPath()

  @Published var feed: DiscoverFeed?
  @Published var loadingFeed = false
  @Published var artistReleases: [AlbumShowcase] = []

  @Published var showPlayer = false
  @Published var playerTab: PlayerSurfaceTab = .artwork
  /// Style chosen in Settings for the Now Playing stage (Capa, Vinil, K7, Ondas 3D).
  @Published var playerStyle: PlayerSurfaceTab = PlayerSurfaceTab(rawValue: UserDefaults.standard.string(forKey: "lume.playerStyle") ?? "") ?? .artwork {
    didSet {
      if playerStyle == .lyrics { playerStyle = .artwork }
      UserDefaults.standard.set(playerStyle.rawValue, forKey: "lume.playerStyle")
      if playerTab != .lyrics { playerTab = playerStyle }
      AudioPlayer.shared.refreshLockScreenArtwork()
    }
  }
  @Published var showCoverFlow = false
  @Published var playlistPickerTrack: Track?
  @Published var toast: String?
  @Published var searchFocusToken = 0
  @Published var searchLyricsToken = 0
  /// Depuração (`-LMDebugRoute search:<texto>`): texto que a busca deve preencher ao abrir.
  @Published var debugSearchText: String?
  /// Depuração (`-LMDebugRoute queue`): o Tocando agora abre já com a fila.
  @Published var debugOpenQueue = false

  func openLyricsSearch() {
    tab = .search
    searchPath = NavigationPath()
    searchLyricsToken += 1
    searchFocusToken += 1
  }

  private var lastFeedLoad: Date?

  /// `-LMDebugRoute <rota>` abre direto uma tela, para conferir no simulador:
  ///   artist:<nome> · album:<busca> · search:<texto> (teclado aberto) · library · settings · queue
  /// Também aceitos: home, explore, downloads, replay, releases, import, equalizer, genres, charts:<país>.
  func runDebugRouteIfNeeded() {
    let args = ProcessInfo.processInfo.arguments
    guard let i = args.firstIndex(of: "-LMDebugRoute"), i + 1 < args.count else { return }
    let raw = args[i + 1]
    let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let kind = String(parts.first ?? "").lowercased()
    let value = parts.count > 1 ? String(parts[1]) : ""
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(900))
      switch kind {
      case "home": tab = .home
      case "explore": tab = .explore
      case "artist":
        tab = .home
        push(.artist(value.isEmpty ? "Anitta" : value, nil))
      case "album":
        tab = .home
        let found = await SearchService.shared.albums(value.isEmpty ? "Anitta" : value)
        if let a = found.first { push(.album(a)) } else { showToast("Álbum não encontrado: \(value)") }
      case "search":
        debugSearchText = value
        tab = .search
        searchFocusToken += 1
      case "library": tab = .library
      case "settings":
        tab = .library
        push(.settings)
      case "downloads":
        tab = .library
        push(.downloads)
      case "replay":
        tab = .library
        push(.replay)
      case "releases":
        tab = .home
        push(.releases)
      case "import":
        tab = .library
        push(.importHub)
      case "equalizer":
        tab = .library
        push(.equalizer)
      case "queue":
        debugOpenQueue = true
        for _ in 0..<30 where AudioPlayer.shared.currentTrack == nil && feed == nil {
          try? await Task.sleep(for: .milliseconds(300))
        }
        openPlayer()
      default: break
      }
    }
  }

  var hasUnseenReleases: Bool {
    let seen = LibraryStore.shared.seenReleaseIds
    return artistReleases.contains { !seen.contains($0.id) }
  }

  func markReleasesSeen() {
    let store = LibraryStore.shared
    for r in artistReleases { store.seenReleaseIds.insert(r.id) }
    store.save()
    objectWillChange.send()
  }

  // MARK: Navigation

  func path(for t: AppTab) -> Binding<NavigationPath> {
    Binding(
      get: {
        switch t {
        case .home: return self.homePath
        case .explore: return self.explorePath
        case .library: return self.libraryPath
        case .search: return self.searchPath
        }
      },
      set: { newValue in
        switch t {
        case .home: self.homePath = newValue
        case .explore: self.explorePath = newValue
        case .library: self.libraryPath = newValue
        case .search: self.searchPath = newValue
        }
      }
    )
  }

  /// Quantas telas de detalhe estão empilhadas na aba atual (0 = tela-raiz da aba).
  var currentDepth: Int {
    switch tab {
    case .home: return homePath.count
    case .explore: return explorePath.count
    case .library: return libraryPath.count
    case .search: return searchPath.count
    }
  }

  func push(_ route: LumeRoute) {
    switch tab {
    case .home: homePath.append(route)
    case .explore: explorePath.append(route)
    case .library: libraryPath.append(route)
    case .search: searchPath.append(route)
    }
  }

  func select(_ t: AppTab) {
    Haptics.selection()
    if tab == t {
      withAnimation(.snappy) {
        switch t {
        case .home: homePath = NavigationPath()
        case .explore: explorePath = NavigationPath()
        case .library: libraryPath = NavigationPath()
        case .search: searchPath = NavigationPath(); searchFocusToken += 1
        }
      }
    } else {
      tab = t
      if t == .search { searchFocusToken += 1 }
    }
  }

  /// Navigate from inside the full-screen player (dismiss first, then push).
  func navigateFromPlayer(_ route: LumeRoute) {
    showPlayer = false
    Task {
      try? await Task.sleep(for: .milliseconds(420))
      push(route)
    }
  }

  func openArtist(_ name: String, deezerId: Int? = nil) {
    push(.artist(LibraryStore.mainArtist(name), deezerId))
  }

  // MARK: Feed

  func loadFeed(force: Bool = false) async {
    if feed == nil, let cached = await DiscoveryService.shared.cachedFeed() {
      feed = cached
    }
    if !force, let last = lastFeedLoad, Date().timeIntervalSince(last) < 600 { return }
    loadingFeed = feed == nil
    let fresh = force ? await DiscoveryService.shared.refresh() : await DiscoveryService.shared.feed()
    feed = fresh
    loadingFeed = false
    lastFeedLoad = Date()
  }

  func refreshArtistReleases() async {
    var names = Array(LibraryStore.shared.topListenedArtists.prefix(12))
    if names.isEmpty, let top = feed?.topArtists.prefix(6) { names = top.map(\.name) }
    guard !names.isEmpty else { return }
    let found = await DiscoveryService.shared.newReleases(forArtists: names)
    if !found.isEmpty { artistReleases = found }
  }

  // MARK: Player helpers

  func openPlayer(_ mode: PlayerSurfaceTab? = nil) {
    if let mode { playerTab = mode } else if playerTab != .lyrics { playerTab = playerStyle }
    let player = AudioPlayer.shared
    if player.currentTrack == nil {
      let list = feed?.topBrazil ?? []
      if let first = list.first { player.play(first, in: list) } else {
        showToast("Escolha uma música para começar")
        return
      }
    }
    showPlayer = true
  }

  /// "Lume Flow": an endless radio seeded by what you love (Deezer Flow–style).
  func startFlow() {
    let store = LibraryStore.shared
    var seeds = Array(store.mostPlayedTracks.prefix(12)) + Array(store.favoriteTracks.prefix(12)) + Array(store.recentTracks.prefix(8))
    if seeds.isEmpty { seeds = Array((feed?.topBrazil ?? []).prefix(15)) }
    guard let seed = seeds.randomElement() else {
      showToast("Carregando as paradas… tente de novo em instantes")
      return
    }
    let player = AudioPlayer.shared
    player.autoplayRadio = true
    player.play(seed, in: [seed])
    showToast("Lume Flow ligado · rádio infinita a partir de \(seed.artist)")
    showPlayer = true
  }

  func showToast(_ text: String) {
    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { toast = text }
    Task {
      try? await Task.sleep(for: .seconds(2.8))
      if toast == text { withAnimation(.easeOut(duration: 0.25)) { toast = nil } }
    }
  }
}

// MARK: - Root view

struct RootView: View {
  @ObservedObject private var app = AppModel.shared
  // 5.0 (desempenho): o RootView NÃO observa mais o player nem os downloads inteiros — qualquer
  // @Published deles re-renderizava as 4 abas (todas vivas no ZStack). Assina só o que usa.
  private let player = AudioPlayer.shared
  private let downloads = DownloadManager.shared
  @State private var hasTrack = AudioPlayer.shared.currentTrack != nil
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ZStack(alignment: .bottom) {
      Theme.canvas.ignoresSafeArea()

      ForEach(AppTab.allCases) { t in
        let active = app.tab == t
        let diff = tabOrder(t) - tabOrder(app.tab)
        tabStack(t)
          .opacity(active ? 1 : 0)
          .offset(x: active ? 0 : (diff < 0 ? -16 : 16))
          .scaleEffect(active ? 1 : 0.988)
          .allowsHitTesting(active)
          .accessibilityHidden(!active)
      }
      .animation(.spring(response: 0.30, dampingFraction: 0.90), value: app.tab)

      // Véu da barra de status: o conteúdo rolado some suavemente sob o relógio/bateria
      // (antes os textos passavam por baixo e se misturavam com a hora).
      VStack(spacing: 0) {
        GeometryReader { g in
          // Só nas telas-raiz das abas: nas telas de detalhe o véu é do cabeçalho (LumeChrome), que não pode
          // cobrir o botão de voltar.
          LinearGradient(
            stops: [
              .init(color: Theme.canvas, location: 0),
              .init(color: Theme.canvas.opacity(0.92), location: 0.55),
              .init(color: Theme.canvas.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
            .frame(height: g.safeAreaInsets.top + 14)
            .offset(y: -g.safeAreaInsets.top)
            .opacity(app.currentDepth == 0 ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: app.currentDepth)
        }
        .frame(height: 0)
        Spacer()
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)

      // Véu da base: o conteúdo rolado some suavemente atrás da barra flutuante (não captura toques).
      VStack(spacing: 0) {
        Spacer()
        GeometryReader { g in
          let chromeH = LumeLayout.tabBarHeight + (hasTrack ? LumeLayout.miniPlayerHeight : 0)
          LinearGradient(
            stops: [
              .init(color: Theme.canvas.opacity(0), location: 0),
              .init(color: Theme.canvas.opacity(0.86), location: 0.42),
              .init(color: Theme.canvas.opacity(0.97), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
            .frame(height: chromeH + g.safeAreaInsets.bottom + 14)
            .frame(maxWidth: .infinity)
            .offset(y: -(chromeH + 14))
        }
        .frame(height: 0)
      }
      .ignoresSafeArea(.keyboard)
      .allowsHitTesting(false)
      .accessibilityHidden(true)

      // A barra fica no pé da tela e o teclado passa por cima (antes ela "subia" junto, cobrindo a lista).
      BottomBar()
        .ignoresSafeArea(.keyboard)

      if let msg = app.toast {
        VStack {
          Text(msg)
            .font(Theme.font(14, .semibold))
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassCapsule()
            .lumeShadow(16, y: 6, opacity: 0.6)
            .padding(.horizontal, 24)
            .padding(.top, 6)
          Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .allowsHitTesting(false)   // o aviso nunca rouba toque do botão que está embaixo dele
        .zIndex(50)
      }
    }
    .fullScreenCover(isPresented: $app.showPlayer) {
      NowPlayingView()
    }
    .fullScreenCover(isPresented: $app.showCoverFlow) {
      CoverFlowScreen()
    }
    .sheet(item: $app.playlistPickerTrack) { tr in
      AddToPlaylistSheet(track: tr)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    .task {
      LumeKeyboard.install()
      player.runDebugHooksIfNeeded()
      app.runDebugRouteIfNeeded()
      await app.loadFeed()
      await app.refreshArtistReleases()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await app.loadFeed() } }
    }
    .onReceive(downloads.$lastMessage.removeDuplicates()) { msg in if let msg { app.showToast(msg) } }
    .onReceive(player.$errorToast.removeDuplicates()) { msg in if let msg { app.showToast(msg) } }
    .onReceive(player.$currentTrack.map { $0 != nil }.removeDuplicates()) { hasTrack = $0 }
  }

  private func tabOrder(_ t: AppTab) -> Int {
    switch t {
    case .home: return 0
    case .explore: return 1
    case .library: return 2
    case .search: return 3
    }
  }

  @ViewBuilder
  private func tabStack(_ t: AppTab) -> some View {
    NavigationStack(path: app.path(for: t)) {
      Group {
        switch t {
        case .home: HomeView()
        case .explore: ExploreView()
        case .library: LibraryView()
        case .search: SearchView()
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(for: LumeRoute.self) { route in
        RouteView(route: route)
      }
    }
    // O espaço no fim de cada rolagem vem de `.lumeTabScroll()` (LumeChrome.swift), aplicado em cada tela.
    .environment(\.lumeHasMiniPlayer, hasTrack)
    .tint(Theme.text)
  }
}

struct RouteView: View {
  let route: LumeRoute

  var body: some View {
    Group {
      switch route {
      case .album(let a): AlbumView(album: a)
      case .playlist(let id): PlaylistView(playlistId: id)
      case .remotePlaylist(let pl): RemotePlaylistView(playlist: pl)
      case .artist(let name, let dz): ArtistView(name: name, deezerId: dz)
      case .importHub: ImportView()
      case .mood(let m): MoodView(mood: m)
      case .country(let c): CountryChartView(country: c)
      case .genre(let g): GenreHubView(genre: g)
      case .mix(let mix): MixDetailView(mix: mix)
      case .releases: ReleasesView()
      case .downloads: DownloadsCenterView()
      case .replay: ReplayView()
      case .equalizer: EqualizerView()
      case .settings: SettingsView()
      case .tracks(let title, let tracks): TrackListView(title: title, tracks: tracks)
      case .albums(let title, let albums): AlbumGridView(title: title, albums: albums)
      case .artists(let title, let artists): ArtistGridView(title: title, artists: artists)
      }
    }
  }
}

// MARK: - Floating Liquid Glass bottom bar (tab capsule + search orb + mini player)

struct BottomBar: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var player = AudioPlayer.shared
  @Namespace private var ns

  var body: some View {
    VStack(spacing: 10) {
      if let tr = player.currentTrack {
        MiniPlayer(track: tr)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      HStack(spacing: 12) {
        HStack(spacing: 0) {
          ForEach(AppTab.bar) { t in
            let active = app.tab == t
            Button { app.select(t) } label: {
              VStack(spacing: 3) {
                Image(systemName: t.icon)
                  .font(.system(size: 19, weight: .semibold))
                  .symbolEffect(.bounce, value: active)
                  .frame(height: 24)
                Text(t.rawValue)
                  .font(Theme.font(10.5, .semibold))
              }
              .foregroundStyle(active ? Theme.accent : Theme.text.opacity(0.92))
              .frame(maxWidth: .infinity)
              .frame(height: 54)
              .background {
                if active {
                  Capsule()
                    .fill(Theme.fillStrong)
                    .matchedGeometryEffect(id: "tabSel", in: ns)
                }
              }
              .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .accessibilityLabel(t.rawValue)
          }
        }
        .padding(4)
        .glassCapsule(interactive: true)

        Button { app.select(.search) } label: {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(app.tab == .search ? Theme.accent : Theme.text)
            .frame(width: 62, height: 62)
            .background {
              if app.tab == .search { Circle().fill(Theme.fillStrong).padding(4) }
            }
            .contentShape(Circle())
            .glassCircle(interactive: true)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel("Buscar")
      }
    }
    .glassGroup(spacing: 14)
    .padding(.horizontal, 16)
    .padding(.bottom, 2)
    .animation(.spring(response: 0.36, dampingFraction: 0.84), value: app.tab)
    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: player.currentTrack?.id)
  }
}

struct MiniPlayer: View {
  let track: Track
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @State private var dragX: CGFloat = 0

  var body: some View {
    HStack(spacing: 10) {
      ArtworkImage(url: player.displayArtwork(for: track), cornerRadius: 10, maxPixel: 160)
        .frame(width: 42, height: 42)
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)

      VStack(alignment: .leading, spacing: 1) {
        Text(track.title)
          .font(Theme.font(15, .semibold))
          .foregroundStyle(Theme.text)
          .lineLimit(1)
        Text(track.artist)
          .font(Theme.font(13))
          .foregroundStyle(Theme.secondary)
          .lineLimit(1)
      }
      .offset(x: dragX * 0.4)
      .opacity(1 - Double(min(abs(dragX), 120) / 240))

      Spacer(minLength: 4)

      let fav = store.isFavorite(track.id)
      Button {
        store.toggleFavorite(track)
      } label: {
        Image(systemName: fav ? "heart.fill" : "heart")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(fav ? Theme.rose : Theme.secondary)
          .symbolEffect(.bounce, value: fav)
          .frame(width: 40, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(PressableStyle(scale: 0.85))
      .accessibilityLabel(fav ? "Remover das curtidas" : "Curtir")

      Button { player.togglePlayPause() } label: {
        ZStack {
          if player.isLoading {
            ProgressView().controlSize(.small).tint(Theme.text)
          } else {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(Theme.text)
              .contentTransition(.symbolEffect(.replace))
          }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(PressableStyle(scale: 0.85))

      Button { player.nextTrack() } label: {
        Image(systemName: "forward.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(PressableStyle(scale: 0.85))
    }
    .padding(.leading, 8)
    .padding(.trailing, 10)
    .frame(height: 60)
    .overlay(alignment: .bottom) {
      MiniPlayerProgressBar()
        .padding(.horizontal, 26)
        .padding(.bottom, 3)
        .allowsHitTesting(false)
    }
    .glassCapsule(interactive: true)
    .contentShape(Capsule())
    .onTapGesture { Haptics.light(); app.openPlayer() }
    .gesture(
      DragGesture(minimumDistance: 16)
        .onChanged { v in if abs(v.translation.width) > abs(v.translation.height) { dragX = v.translation.width } }
        .onEnded { v in
          if v.translation.width < -60 { player.nextTrack() }
          else if v.translation.width > 60 { player.previousTrack() }
          else if v.translation.height < -30 { app.openPlayer() }
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragX = 0 }
        }
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Tocando agora: \(track.title), \(track.artist)")
    .accessibilityAddTraits(.isButton)
  }
}

private struct MiniPlayerProgressBar: View {
  @ObservedObject private var clock = PlaybackClock.shared

  var body: some View {
    GeometryReader { g in
      let frac = clock.duration > 0 ? min(1, clock.currentTime / clock.duration) : 0
      Capsule().fill(Theme.text.opacity(0.10))
        .overlay(alignment: .leading) {
          Capsule().fill(Theme.prism).frame(width: g.size.width * frac)
        }
    }
    .frame(height: 2.5)
  }
}
