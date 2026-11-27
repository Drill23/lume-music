import SwiftUI

// MARK: - Cover Flow (Lume Music 5.0)
//
// Fluxo: ao abrir em retrato mostra "Vire o celular". O acelerômetro (OrientationKit) detecta o aparelho na
// horizontal e a interface é FORÇADA para paisagem; lá o Cover Flow clássico do iPod (capas a ~70°, reflexo no
// chão, vidro). Tocar na capa central vira em 3D e mostra as faixas. "Continuar na vertical" abre uma versão
// retrato preenchida (carrossel + lista de faixas). Ao sair, a interface volta a retrato.

struct CoverFlowItem: Identifiable, Hashable {
  let id: String
  let title: String
  let subtitle: String
  let artworkURL: String
  var album: AlbumShowcase? = nil
  var track: Track? = nil
  var localTracks: [Track] = []
}

// MARK: - Estado compartilhado (fora do SwiftUI para sobreviver à troca retrato <-> paisagem)

/// Posição contínua do carrossel (muda a cada frame do arraste; só o palco observa).
final class CoverFlowPosition: ObservableObject {
  @Published var value: Double = 0
}

/// Seleção discreta (índice arredondado e capa virada). Muda raramente; legendas e painéis observam.
final class CoverFlowSelection: ObservableObject {
  @Published var index: Int = 0
  @Published var flippedId: String?
}

/// Faixas por capa, carregadas sob demanda e guardadas em cache.
@MainActor
final class CoverFlowTrackStore: ObservableObject {
  @Published private(set) var cache: [String: [Track]] = [:]
  private var inflight: Set<String> = []

  func load(_ item: CoverFlowItem) async {
    guard cache[item.id] == nil else { return }
    if !item.localTracks.isEmpty { cache[item.id] = item.localTracks; return }
    if let t = item.track { cache[item.id] = [t]; return }
    guard let album = item.album, inflight.insert(item.id).inserted else { return }
    let tracks = await DiscoveryService.shared.albumTracks(album)
    cache[item.id] = tracks
    inflight.remove(item.id)
  }
}

// MARK: - Tela

struct CoverFlowScreen: View {
  @Environment(\.dismiss) private var dismiss
  @State private var source: Source = .releases
  @State private var items: [CoverFlowItem] = []
  @State private var choosePortrait = false
  @State private var forcedLandscape = false
  @State private var closing = false
  @State private var position = CoverFlowPosition()
  @State private var selection = CoverFlowSelection()
  @State private var trackStore = CoverFlowTrackStore()
  @StateObject private var motion = MotionOrientationMonitor()

  enum Source: String, CaseIterable, Identifiable {
    case releases = "Lançamentos"
    case trending = "Em alta"
    case library = "Sua biblioteca"
    var id: String { rawValue }
  }

  var body: some View {
    ZStack {
      CoverFlowBackdrop()
      GeometryReader { g in
        let landscape = g.size.width > g.size.height
        ZStack {
          if landscape {
            CoverFlowLandscapeLayout(size: g.size, items: items, source: $source, position: position, selection: selection,
                                     tracks: trackStore, onClose: close, onPlay: playCurrent)
              .transition(.opacity)
          } else if choosePortrait {
            CoverFlowPortraitLayout(size: g.size, items: items, source: $source, position: position, selection: selection,
                                    tracks: trackStore, onClose: close, onPlay: playCurrent)
              .transition(.opacity)
          } else {
            CoverFlowRotatePrompt(onContinue: {
              Haptics.light()
              withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { choosePortrait = true }
            }, onClose: close)
              .transition(.opacity)
          }
        }
        .frame(width: g.size.width, height: g.size.height)
        .animation(.easeInOut(duration: 0.3), value: landscape)
        .animation(.easeInOut(duration: 0.3), value: choosePortrait)
      }
    }
    .environment(\.colorScheme, .dark)
    .statusBarHidden(forcedLandscape)
    .onAppear {
      rebuild()
      motion.start()
      runDebugHooks()
    }
    .onDisappear {
      motion.stop()
      if forcedLandscape || OrientationLock.shared.mask != OrientationLock.defaultMask {
        OrientationLock.shared.lockPortrait()
      }
    }
    .onChange(of: motion.current) { _, new in handleMotion(new) }
    .onChange(of: source) { _, _ in
      selection.flippedId = nil
      selection.index = 0
      position.value = 0
      rebuild()
    }
    .onReceive(AppModel.shared.$feed.dropFirst()) { _ in rebuild() }
    .onReceive(LibraryStore.shared.objectWillChange.debounce(for: .seconds(1), scheduler: DispatchQueue.main)) { _ in
      if source == .library { rebuild() }
    }
  }

  // MARK: Orientação

  private func handleMotion(_ orientation: PhysicalOrientation?) {
    guard !closing, let orientation else { return }
    switch orientation {
    case .landscapeLeft, .landscapeRight:
      if let mask = orientation.interfaceMask {
        forcedLandscape = true
        OrientationLock.shared.forceLandscape(mask)
      }
    case .portrait:
      // Voltou a segurar em pé: devolve a interface a retrato (e mostra a versão vertical preenchida).
      if forcedLandscape {
        forcedLandscape = false
        choosePortrait = true
        OrientationLock.shared.lockPortrait()
      }
    }
  }

  private func close() {
    guard !closing else { return }
    closing = true
    motion.stop()
    Haptics.light()
    selection.flippedId = nil
    if forcedLandscape {
      forcedLandscape = false
      OrientationLock.shared.lockPortrait()
      // Dá tempo da interface girar de volta antes de fechar a cobertura.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
    } else {
      dismiss()
    }
  }

  private func playCurrent() {
    guard items.indices.contains(selection.index) else { return }
    let item = items[selection.index]
    let store = trackStore
    let all = items.compactMap(\.track)
    Task { @MainActor in
      if let t = item.track {
        Haptics.medium()
        AudioPlayer.shared.play(t, in: all)
        return
      }
      await store.load(item)
      if let tracks = store.cache[item.id], let first = tracks.first {
        Haptics.medium()
        AudioPlayer.shared.play(first, in: tracks)
      }
    }
  }

  private func runDebugHooks() {
    if CoverFlowDebug.portrait {
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))
        withAnimation { choosePortrait = true }
      }
    }
    if CoverFlowDebug.landscape {
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(1.5))
        motion.inject(.landscapeLeft)   // mesmo caminho do acelerômetro real
      }
    }
    if CoverFlowDebug.flip {
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(4))
        if let it = items.first {
          await trackStore.load(it)
          withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) { selection.flippedId = it.id }
        }
      }
    }
  }

  // MARK: Dados

  private func rebuild() {
    var list = buildItems()
    if (list.isEmpty && CoverFlowDebug.open) || CoverFlowDebug.fake { list = CoverFlowDebug.fakeItems() }
    items = list
    let maxIndex = max(0, list.count - 1)
    if selection.index > maxIndex {
      selection.index = maxIndex
      position.value = Double(maxIndex)
    }
  }

  private func buildItems() -> [CoverFlowItem] {
    let app = AppModel.shared
    let store = LibraryStore.shared
    switch source {
    case .releases:
      let albums = (app.feed?.newReleases ?? []) + (app.feed?.brazilReleases ?? [])
      var seen = Set<String>()
      return albums.compactMap { a in
        guard seen.insert(a.id).inserted else { return nil }
        return CoverFlowItem(id: a.id, title: a.title, subtitle: a.artist, artworkURL: a.artworkURL, album: a)
      }
    case .trending:
      return (app.feed?.topBrazil ?? []).map { t in
        CoverFlowItem(id: t.id, title: t.title, subtitle: t.artist, artworkURL: ArtworkStore.shared.url(for: t), track: t)
      }
    case .library:
      var groups: [String: [Track]] = [:]
      var order: [String] = []
      for t in store.favoriteTracks + store.recentTracks + store.playlists.flatMap({ store.tracks(in: $0) }) {
        let key = (t.album.isEmpty ? t.title : t.album).lowercased() + "|" + LibraryStore.mainArtist(t.artist).lowercased()
        if groups[key] == nil { order.append(key) }
        if !(groups[key]?.contains(where: { $0.id == t.id }) ?? false) { groups[key, default: []].append(t) }
      }
      return order.compactMap { k in
        guard let tracks = groups[k], let f = tracks.first else { return nil }
        return CoverFlowItem(id: k, title: f.album.isEmpty ? f.title : f.album, subtitle: LibraryStore.mainArtist(f.artist),
                             artworkURL: ArtworkStore.shared.url(for: f), localTracks: tracks)
      }
    }
  }
}

// MARK: - Fundo (preto profundo com vinheta)

struct CoverFlowBackdrop: View {
  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(white: 0.11), Color(white: 0.02), .black], startPoint: .top, endPoint: .bottom)
      RadialGradient(colors: [Theme.lavender.opacity(0.16), .clear], center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: 380)
      EllipticalGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.85), location: 1)],
                         center: .center)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}

// MARK: - Métricas

struct CoverFlowMetrics {
  var width: CGFloat
  var height: CGFloat
  var cover: CGFloat
  var coverTop: CGFloat
  var backAspect: CGFloat
  var flipScale: CGFloat
  var flipCenterY: CGFloat
  var interactTop: CGFloat
  var interactBottom: CGFloat
  var artPixel: CGFloat

  var sideGap: CGFloat { cover * 0.80 }
  var step: CGFloat { cover * 0.30 }
  var dragSpacing: CGFloat { cover * 0.34 }
  var flipShift: CGFloat { flipCenterY - (coverTop + cover / 2) }

  static let barHeight: CGFloat = 44

  static func landscape(_ s: CGSize) -> CoverFlowMetrics {
    let barBottom: CGFloat = 8 + barHeight
    let cover = min(s.height * 0.54, s.width * 0.27)
    let coverTop = barBottom + 8
    let flipCenterY = (barBottom + s.height) / 2
    let scale = min(1.6, (s.height - barBottom - 8) / cover)
    return CoverFlowMetrics(width: s.width, height: s.height, cover: cover, coverTop: coverTop, backAspect: 1.55,
                            flipScale: scale, flipCenterY: flipCenterY, interactTop: barBottom, interactBottom: s.height, artPixel: 460)
  }

  static func portrait(_ s: CGSize) -> CoverFlowMetrics {
    let coverTop = portraitCoverTop
    let cover = min(s.width * 0.64, (s.height - coverTop) * 0.36)
    let scale = min(1.5, (s.width * 0.92) / cover)
    return CoverFlowMetrics(width: s.width, height: s.height, cover: cover, coverTop: coverTop, backAspect: 1.0,
                            flipScale: scale, flipCenterY: coverTop + cover * scale / 2, interactTop: coverTop - 8,
                            interactBottom: coverTop + cover * 1.28, artPixel: 560)
  }

  static var portraitCoverTop: CGFloat { 4 + barHeight + 8 + barHeight + 18 }
}

// MARK: - Layout paisagem (Cover Flow clássico)

struct CoverFlowLandscapeLayout: View {
  let size: CGSize
  let items: [CoverFlowItem]
  @Binding var source: CoverFlowScreen.Source
  let position: CoverFlowPosition
  @ObservedObject var selection: CoverFlowSelection
  let tracks: CoverFlowTrackStore
  let onClose: () -> Void
  let onPlay: () -> Void

  var body: some View {
    let m = CoverFlowMetrics.landscape(size)
    let captionH: CGFloat = 56
    ZStack(alignment: .top) {
      CoverFlowStage(items: items, m: m, position: position, selection: selection, tracks: tracks)
      if items.isEmpty { CoverFlowEmpty(source: source) }
      HStack(spacing: 12) {
        GlassIconButton(systemName: "xmark", size: 44, iconSize: 17, foreground: .white, action: onClose)
        Spacer(minLength: 0)
        CoverFlowSourcePicker(source: $source)
        Spacer(minLength: 0)
        GlassIconButton(systemName: "play.fill", size: 44, iconSize: 17, foreground: .white, action: onPlay)
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .opacity(selection.flippedId == nil ? 1 : 0.0)
      .allowsHitTesting(selection.flippedId == nil)
      .animation(.easeOut(duration: 0.2), value: selection.flippedId)

      if !items.isEmpty {
        CoverFlowCaption(items: items, selection: selection)
          .frame(height: captionH)
          .padding(.top, size.height - captionH - 4)
          .opacity(selection.flippedId == nil ? 1 : 0)
          .animation(.easeOut(duration: 0.2), value: selection.flippedId)
          .allowsHitTesting(false)
      }

    }
    .frame(width: size.width, height: size.height, alignment: .top)
  }
}

// MARK: - Layout retrato preenchido

struct CoverFlowPortraitLayout: View {
  let size: CGSize
  let items: [CoverFlowItem]
  @Binding var source: CoverFlowScreen.Source
  let position: CoverFlowPosition
  @ObservedObject var selection: CoverFlowSelection
  let tracks: CoverFlowTrackStore
  let onClose: () -> Void
  let onPlay: () -> Void

  var body: some View {
    let m = CoverFlowMetrics.portrait(size)
    let captionY = m.coverTop + m.cover * 1.30
    let captionH: CGFloat = 60
    let sliderY = captionY + captionH + 4
    let panelY = sliderY + 40
    let panelH = max(120, size.height - panelY - 8)
    ZStack(alignment: .top) {
      VStack(spacing: 8) {
        HStack {
          GlassIconButton(systemName: "xmark", size: 44, iconSize: 17, foreground: .white, action: onClose)
          Spacer()
          Text("Cover Flow")
            .font(Theme.rounded(17, .semibold))
            .foregroundStyle(.white)
          Spacer()
          GlassIconButton(systemName: "play.fill", size: 44, iconSize: 17, foreground: .white, action: onPlay)
        }
        .padding(.horizontal, 16)
        CoverFlowSourcePicker(source: $source)
      }
      .padding(.top, 4)

      if items.isEmpty {
        CoverFlowEmpty(source: source).padding(.top, m.coverTop)
      } else {
        CoverFlowCaption(items: items, selection: selection)
          .frame(height: captionH)
          .padding(.top, captionY)
          .opacity(selection.flippedId == nil ? 1 : 0)
          .allowsHitTesting(false)
          .animation(.easeOut(duration: 0.2), value: selection.flippedId)

        CoverFlowScrubber(count: items.count, position: position, selection: selection)
          .padding(.horizontal, 28)
          .padding(.top, sliderY)

        CoverFlowTrackPanel(items: items, selection: selection, store: tracks)
          .frame(height: panelH)
          .padding(.horizontal, 16)
          .padding(.top, panelY)
      }

      CoverFlowStage(items: items, m: m, position: position, selection: selection, tracks: tracks)
    }
    .frame(width: size.width, height: size.height, alignment: .top)
  }
}

// MARK: - Seletor de fonte (vidro)

struct CoverFlowSourcePicker: View {
  @Binding var source: CoverFlowScreen.Source

  var body: some View {
    HStack(spacing: 2) {
      ForEach(CoverFlowScreen.Source.allCases) { s in
        let active = source == s
        Button {
          guard !active else { return }
          Haptics.selection()
          withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { source = s }
        } label: {
          Text(s.rawValue)
            .font(Theme.font(13, .semibold))
            .foregroundStyle(active ? Theme.onPrism : .white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
              if active { Capsule().fill(Theme.prismDiagonal) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 4)
    .frame(height: 44)
    .glassCapsule()
  }
}

// MARK: - Legenda (título/artista em vidro)

struct CoverFlowCaption: View {
  let items: [CoverFlowItem]
  @ObservedObject var selection: CoverFlowSelection

  var body: some View {
    let i = min(max(0, selection.index), max(0, items.count - 1))
    let cur = items[i]
    VStack(spacing: 3) {
      Text(cur.title)
        .font(Theme.rounded(17, .bold))
        .foregroundStyle(.white)
        .lineLimit(1)
      Text("\(cur.subtitle)  ·  \(i + 1) de \(items.count)")
        .font(Theme.font(13, .medium))
        .foregroundStyle(.white.opacity(0.62))
        .lineLimit(1)
        .monospacedDigit()
    }
    .padding(.horizontal, 22)
    .frame(maxWidth: 440, maxHeight: .infinity)
    .glass(22)
    .padding(.horizontal, 24)
    .id(cur.id)
    .transition(.opacity)
    .animation(.easeOut(duration: 0.18), value: cur.id)
  }
}

// MARK: - Scrubber (retrato)

struct CoverFlowScrubber: View {
  let count: Int
  @ObservedObject var position: CoverFlowPosition
  @ObservedObject var selection: CoverFlowSelection

  var body: some View {
    Slider(
      value: Binding(get: { position.value }, set: { v in
        selection.flippedId = nil
        position.value = v
        let idx = min(max(0, Int(v.rounded())), max(0, count - 1))
        if idx != selection.index { selection.index = idx; Haptics.selection() }
      }),
      in: 0...Double(max(1, count - 1)),
      onEditingChanged: { editing in
        if !editing { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { position.value = position.value.rounded() } }
      }
    )
    .tint(.white.opacity(0.85))
    .frame(height: 36)
  }
}

// MARK: - Palco 3D

struct CoverFlowStage: View {
  let items: [CoverFlowItem]
  let m: CoverFlowMetrics
  @ObservedObject var position: CoverFlowPosition
  @ObservedObject var selection: CoverFlowSelection
  @ObservedObject var tracks: CoverFlowTrackStore

  @State private var dragStart: Double?

  var body: some View {
    let pos = position.value
    let current = currentIndex(pos)
    ZStack(alignment: .top) {
      // Área de arraste/toque em todo o palco (um toque no fundo desvira a capa).
      Color.clear
        .frame(width: m.width, height: max(0, m.interactBottom - m.interactTop))
        .contentShape(Rectangle())
        .offset(y: m.interactTop)
        .onTapGesture { unflip() }

      CoverFlowFloor(width: m.width, cover: m.cover)
        .offset(y: m.coverTop + m.cover)
        .opacity(selection.flippedId == nil ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: selection.flippedId)
        .allowsHitTesting(false)

      ZStack(alignment: .top) {
        ForEach(visibleIndices(current), id: \.self) { idx in
          let item = items[idx]
          let isFlipped = selection.flippedId == item.id
          CoverFlowCard(item: item, size: m.cover, aspect: m.backAspect, artPixel: m.artPixel, flipped: isFlipped,
                        store: tracks, onClose: unflip, onPlayAll: playAll)
            .equatable()
            .scaleEffect(isFlipped ? m.flipScale : 1, anchor: UnitPoint(x: 0.5, y: 1.0 / 3.0))
            .offset(y: isFlipped ? m.flipShift : 0)
            .modifier(CoverFlowTransform(delta: Double(idx) - pos, cover: m.cover, gap: m.sideGap, step: m.step))
            .zIndex(isFlipped ? 100 : -abs(Double(idx) - pos))
            .onTapGesture { tap(idx) }
        }
      }
      .padding(.top, m.coverTop)

      if items.isEmpty {
        Color.clear
      }
    }
    .frame(width: m.width, height: m.height, alignment: .top)
    .gesture(drag, including: selection.flippedId == nil ? .all : .subviews)
    .task(id: current) {
      // Pré-carrega as faixas da capa central (e vizinhas) para o giro ser instantâneo.
      guard items.indices.contains(current) else { return }
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      await tracks.load(items[current])
    }
  }

  private func currentIndex(_ pos: Double) -> Int {
    guard !items.isEmpty else { return 0 }
    return min(items.count - 1, max(0, Int(pos.rounded())))
  }

  /// Só as ~9 capas perto do centro são montadas.
  private func visibleIndices(_ c: Int) -> [Int] {
    guard !items.isEmpty else { return [] }
    return Array(max(0, c - 4)...min(items.count - 1, c + 4))
  }

  // MARK: Arraste com momentum

  private var drag: some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { v in
        if dragStart == nil { dragStart = position.value; unflip() }
        let raw = (dragStart ?? 0) - Double(v.translation.width / m.dragSpacing)
        setPosition(rubberBand(raw), haptic: true)
      }
      .onEnded { v in
        let start = dragStart ?? position.value
        let projected = start - Double(v.predictedEndTranslation.width / m.dragSpacing)
        let from = position.value
        let target = min(Double(items.count - 1), max(0, projected.rounded()))
        // Limita o voo para a rolagem continuar "tátil".
        let clamped = min(from + 9, max(from - 9, target))
        dragStart = nil
        let distance = abs(clamped - from)
        let response = 0.42 + min(0.4, distance * 0.05)
        withAnimation(.spring(response: response, dampingFraction: 0.86)) {
          setPosition(clamped, haptic: false)
        }
      }
  }

  private func rubberBand(_ x: Double) -> Double {
    let maxV = Double(max(0, items.count - 1))
    if x < 0 { return x * 0.3 }
    if x > maxV { return maxV + (x - maxV) * 0.3 }
    return x
  }

  private func setPosition(_ v: Double, haptic: Bool) {
    position.value = v
    let idx = currentIndex(v)
    if idx != selection.index {
      selection.index = idx
      if haptic { Haptics.selection() }
    }
  }

  // MARK: Toques

  private func unflip() {
    guard selection.flippedId != nil else { return }
    withAnimation(.spring(response: 0.6, dampingFraction: 0.84)) { selection.flippedId = nil }
  }

  private func tap(_ idx: Int) {
    guard items.indices.contains(idx) else { return }
    if idx != selection.index {
      // Toque numa lateral leva até ela.
      if selection.flippedId != nil { selection.flippedId = nil }
      Haptics.light()
      withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { setPosition(Double(idx), haptic: false) }
      return
    }
    let item = items[idx]
    if selection.flippedId == item.id { return } // o verso tem os próprios controles
    if let t = item.track {
      Haptics.medium()
      AudioPlayer.shared.play(t, in: items.compactMap(\.track))
      return
    }
    Haptics.medium()
    withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) { selection.flippedId = item.id }
  }

  private func playAll() {
    guard items.indices.contains(selection.index) else { return }
    let item = items[selection.index]
    if let list = tracks.cache[item.id], let first = list.first {
      Haptics.medium()
      AudioPlayer.shared.play(first, in: list)
    }
  }
}

/// Geometria do Cover Flow, animável em `delta` (distância ao centro) para os quadros intermediários ficarem certos.
struct CoverFlowTransform: ViewModifier, Animatable {
  var delta: Double
  let cover: CGFloat
  let gap: CGFloat
  let step: CGFloat

  var animatableData: Double {
    get { delta }
    set { delta = newValue }
  }

  func body(content: Content) -> some View {
    let a = abs(delta)
    let s: Double = delta >= 0 ? 1 : -1
    let near = min(a, 1)
    let x = s * (Double(gap) * near + Double(step) * max(0, a - 1))
    let angle = -s * 70 * near
    let scale = 1 - 0.10 * near
    let fade = a > 3.2 ? max(0, 1 - (a - 3.2) / 1.2) : 1
    let shade = 1 - 0.55 * near
    return content
      .colorMultiply(Color(white: shade))
      .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: UnitPoint(x: 0.5, y: 1.0 / 3.0), perspective: 0.5)
      .scaleEffect(scale, anchor: UnitPoint(x: 0.5, y: 1.0 / 3.0))
      .offset(x: x)
      .opacity(fade)
  }
}

/// Brilho do "chão" sob as capas.
struct CoverFlowFloor: View {
  let width: CGFloat
  let cover: CGFloat

  var body: some View {
    VStack(spacing: 0) {
      Rectangle()
        .fill(LinearGradient(colors: [.clear, .white.opacity(0.30), .clear], startPoint: .leading, endPoint: .trailing))
        .frame(height: 1)
      Rectangle()
        .fill(LinearGradient(colors: [.white.opacity(0.075), .clear], startPoint: .top, endPoint: .bottom))
        .frame(height: cover * 0.62)
    }
    .frame(width: width * 0.96)
    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.18),
                                 .init(color: .white, location: 0.82), .init(color: .clear, location: 1)],
                         startPoint: .leading, endPoint: .trailing))
  }
}

// MARK: - Capa (frente + reflexo + verso)

struct CoverFlowCard: View, Equatable {
  let item: CoverFlowItem
  let size: CGFloat
  let aspect: CGFloat
  let artPixel: CGFloat
  let flipped: Bool
  let store: CoverFlowTrackStore
  let onClose: () -> Void
  let onPlayAll: () -> Void

  static func == (l: CoverFlowCard, r: CoverFlowCard) -> Bool {
    l.item.id == r.item.id && l.size == r.size && l.aspect == r.aspect && l.artPixel == r.artPixel && l.flipped == r.flipped
  }

  var body: some View {
    ZStack(alignment: .top) {
      reflection
        .offset(y: size + 2)
        .allowsHitTesting(false)
        .opacity(flipped ? 0 : 1)
        .animation(.easeOut(duration: 0.25), value: flipped)
      FlipCard(angle: flipped ? 180 : 0) {
        front
      } back: {
        CoverFlowBack(item: item, size: size, aspect: aspect, store: store, onClose: onClose, onPlayAll: onPlayAll)
      }
      .frame(width: size * aspect, height: size)
    }
    .frame(width: size * aspect, height: size * 1.5, alignment: .top)
  }

  private var front: some View {
    ArtworkImage(url: item.artworkURL, cornerRadius: 2, maxPixel: artPixel)
      .frame(width: size, height: size)
      .overlay(
        LinearGradient(colors: [.white.opacity(0.16), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
          .allowsHitTesting(false)
      )
      .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
  }

  /// Reflexo barato: a mesma imagem (já em cache) espelhada, com máscara de gradiente. Sem blur.
  private var reflection: some View {
    ArtworkImage(url: item.artworkURL, cornerRadius: 2, maxPixel: artPixel)
      .frame(width: size, height: size)
      .scaleEffect(x: 1, y: -1)
      .frame(width: size, height: size * 0.5, alignment: .top)
      .clipped()
      .mask(LinearGradient(colors: [.white.opacity(0.46), .white.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom))
  }
}

struct FlipCard<Front: View, Back: View>: View, Animatable {
  var angle: Double
  @ViewBuilder var front: () -> Front
  @ViewBuilder var back: () -> Back

  var animatableData: Double {
    get { angle }
    set { angle = newValue }
  }

  var body: some View {
    ZStack {
      if angle < 90 {
        front()
      } else {
        back().rotation3DEffect(.degrees(180), axis: (0, 1, 0))
      }
    }
    .rotation3DEffect(.degrees(angle), axis: (0, 1, 0), perspective: 0.45)
  }
}

// MARK: - Verso: faixas em vidro

struct CoverFlowBack: View {
  let item: CoverFlowItem
  let size: CGFloat
  let aspect: CGFloat
  @ObservedObject var store: CoverFlowTrackStore
  let onClose: () -> Void
  let onPlayAll: () -> Void
  @ObservedObject private var player = AudioPlayer.shared

  private var wide: Bool { aspect > 1.2 }
  private var tracks: [Track]? { store.cache[item.id] }
  private var w: CGFloat { size * aspect }

  var body: some View {
    ZStack {
      // Fundo: a própria capa em miniatura (fica naturalmente desfocada ao esticar; zero custo de blur).
      ArtworkImage(url: item.artworkURL, cornerRadius: 0, maxPixel: 40)
        .frame(width: w, height: size)
      Color.black.opacity(0.58)
      LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)

      Group {
        if wide { wideLayout } else { squareLayout }
      }
      .padding(10)
    }
    .foregroundStyle(.white)
    .frame(width: w, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.glassStroke, lineWidth: 0.8))
    .shadow(color: .black.opacity(0.55), radius: 14, y: 6)
  }

  // Paisagem: coluna da esquerda (capa + título + tocar) e lista à direita.
  private var wideLayout: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 6) {
        ArtworkImage(url: item.artworkURL, cornerRadius: 6, maxPixel: 240)
          .frame(width: size * 0.32, height: size * 0.32)
          .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        Text(item.title).font(Theme.rounded(13, .bold)).lineLimit(2).minimumScaleFactor(0.75).fixedSize(horizontal: false, vertical: true)
        Text(item.subtitle).font(Theme.font(11)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
        Spacer(minLength: 0)
        HStack(spacing: 8) {
          playButton
          closeButton
        }
      }
      .frame(width: size * 0.40)
      .contentShape(Rectangle())
      .onTapGesture { onClose() }

      trackList
        .glass(14)
    }
  }

  private var squareLayout: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        ArtworkImage(url: item.artworkURL, cornerRadius: 5, maxPixel: 120)
          .frame(width: 38, height: 38)
        VStack(alignment: .leading, spacing: 0) {
          Text(item.title).font(Theme.rounded(13, .bold)).lineLimit(1)
          Text(item.subtitle).font(Theme.font(11)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
        }
        Spacer(minLength: 0)
        playButton
        closeButton
      }
      trackList
        .glass(14)
    }
  }

  private var playButton: some View {
    Button(action: onPlayAll) {
      Image(systemName: "play.fill")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(Theme.onPrism)
        .frame(width: 36, height: 36)
        .background(Circle().fill(Theme.prismDiagonal))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
  }

  private var closeButton: some View {
    Button(action: onClose) {
      Image(systemName: "chevron.backward")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 36, height: 36)
        .background(Circle().fill(.white.opacity(0.16)))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var trackList: some View {
    if let tracks {
      if tracks.isEmpty {
        Text("Sem faixas disponíveis")
          .font(Theme.font(12))
          .foregroundStyle(.white.opacity(0.6))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        if tracks.count <= 4 {
          // Single/EP: lista do tamanho do conteúdo + resumo embaixo (sem painel vazio enorme)
          VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in backRow(i, t, tracks) }
            Spacer(minLength: 8)
            VStack(spacing: 4) {
              Image(systemName: tracks.count == 1 ? "music.note" : "square.stack")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.prismDiagonal)
              Text(tracks.count == 1 ? "Single" : "EP · \(tracks.count) faixas")
                .font(Theme.font(12, .semibold))
              Text(Self.totalDuration(tracks))
                .font(Theme.font(11)).foregroundStyle(.white.opacity(0.55)).monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 8)
          }
          .padding(.vertical, 4)
        } else {
          ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
              ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in backRow(i, t, tracks) }
            }
            .padding(.vertical, 4)
          }
        }
      }
    } else {
      ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}


extension CoverFlowBack {
  fileprivate func backRow(_ i: Int, _ t: Track, _ tracks: [Track]) -> some View {
    let playing = player.currentTrack?.id == t.id
    return Button {
      Haptics.light()
      player.play(t, in: tracks)
    } label: {
      HStack(spacing: 8) {
        Group {
          if playing { Image(systemName: "waveform").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.rose) }
          else { Text("\(i + 1)").font(Theme.font(11, .medium)).foregroundStyle(.white.opacity(0.45)).monospacedDigit() }
        }
        .frame(width: 18, alignment: .trailing)
        Text(t.title)
          .font(Theme.font(13, playing ? .semibold : .regular)).lineLimit(1)
          .foregroundStyle(playing ? Theme.rose : .white)
        Spacer(minLength: 4)
        Text(t.formattedDuration)
          .font(Theme.font(11)).foregroundStyle(.white.opacity(0.45)).monospacedDigit()
      }
      .padding(.horizontal, 10)
      .frame(height: 40)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  static func totalDuration(_ tracks: [Track]) -> String {
    let secs = Int(tracks.reduce(0) { $0 + $1.duration })
    return secs >= 3600 ? "\(secs / 3600) h \((secs % 3600) / 60) min" : "\(max(1, secs / 60)) min"
  }
}

// MARK: - Retrato: lista de faixas da capa atual

struct CoverFlowTrackPanel: View {
  let items: [CoverFlowItem]
  @ObservedObject var selection: CoverFlowSelection
  @ObservedObject var store: CoverFlowTrackStore
  @ObservedObject private var player = AudioPlayer.shared

  var body: some View {
    let i = min(max(0, selection.index), max(0, items.count - 1))
    let item = items[i]
    let isChart = item.track != nil
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 1) {
          Text(isChart ? "Em alta agora" : "Faixas")
            .font(Theme.rounded(16, .bold)).foregroundStyle(.white)
          Text(isChart ? "\(items.count) músicas" : item.title)
            .font(Theme.font(12.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
      .frame(height: 52)

      Divider().overlay(.white.opacity(0.12))

      if isChart {
        chartList(current: i)
      } else {
        albumList(item)
      }
    }
    .glass(26)
    .id(isChart)
  }

  @ViewBuilder
  private func albumList(_ item: CoverFlowItem) -> some View {
    if let tracks = store.cache[item.id] {
      if tracks.isEmpty {
        Text("Sem faixas disponíveis")
          .font(Theme.font(14)).foregroundStyle(.white.opacity(0.6))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView(showsIndicators: false) {
          LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
              row(number: i + 1, title: t.title, subtitle: nil, duration: t.formattedDuration, active: player.currentTrack?.id == t.id) {
                player.play(t, in: tracks)
              }
            }
          }
          .padding(.vertical, 4)
        }
        .id(item.id)
      }
    } else {
      ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) { await store.load(item) }
    }
  }

  private func chartList(current: Int) -> some View {
    let all = items.compactMap(\.track)
    return ScrollViewReader { proxy in
      ScrollView(showsIndicators: false) {
        LazyVStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
            if let t = it.track {
              row(number: i + 1, title: t.title, subtitle: t.artist, duration: t.formattedDuration,
                  active: i == current || player.currentTrack?.id == t.id) {
                player.play(t, in: all)
              }
              .id(it.id)
            }
          }
        }
        .padding(.vertical, 4)
      }
      .onChange(of: current) { _, new in
        guard items.indices.contains(new) else { return }
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(items[new].id, anchor: .center) }
      }
    }
  }

  private func row(number: Int, title: String, subtitle: String?, duration: String, active: Bool, action: @escaping () -> Void) -> some View {
    Button {
      Haptics.light()
      action()
    } label: {
      HStack(spacing: 12) {
        Text("\(number)")
          .font(Theme.font(13, .medium)).foregroundStyle(.white.opacity(0.45))
          .frame(width: 24, alignment: .trailing).monospacedDigit()
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(Theme.font(15, active ? .semibold : .regular)).lineLimit(1)
            .foregroundStyle(active ? Theme.rose : .white)
          if let subtitle {
            Text(subtitle).font(Theme.font(12.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
          }
        }
        Spacer(minLength: 6)
        Text(duration).font(Theme.font(12.5)).foregroundStyle(.white.opacity(0.45)).monospacedDigit()
      }
      .padding(.horizontal, 16)
      .frame(height: subtitle == nil ? 44 : 52)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - "Vire o celular"

struct CoverFlowRotatePrompt: View {
  let onContinue: () -> Void
  let onClose: () -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      VStack(spacing: 30) {
        Spacer(minLength: 0)
        CoverFlowPhoneIllustration()
        VStack(spacing: 10) {
          Text("Vire o celular")
            .font(Theme.rounded(30, .bold))
            .foregroundStyle(.white)
          Text("O Cover Flow fica ainda mais bonito\ncom o celular na horizontal.")
            .font(Theme.font(16))
            .foregroundStyle(.white.opacity(0.62))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
        }
        Spacer(minLength: 0)
        Button(action: onContinue) {
          Text("Continuar na vertical")
            .font(Theme.font(16, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .frame(height: 52)
            .contentShape(Capsule())
            .glassCapsule(interactive: true)
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .padding(.bottom, 12)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      GlassIconButton(systemName: "xmark", size: 44, iconSize: 17, foreground: .white, action: onClose)
        .padding(.leading, 16)
        .padding(.top, 4)
    }
  }
}

/// Celular que gira de pé para deitado em loop (só anima enquanto a tela está visível).
struct CoverFlowPhoneIllustration: View {
  @State private var turned = false

  var body: some View {
    ZStack {
      Circle()
        .fill(RadialGradient(colors: [Theme.lavender.opacity(0.32), Theme.rose.opacity(0.10), .clear],
                             center: .center, startRadius: 0, endRadius: 120))
        .frame(width: 240, height: 240)

      phone
        .rotationEffect(.degrees(turned ? -90 : 0))

      Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: 52, height: 52)
        .glassCircle()
        .offset(x: 84, y: 70)
        .opacity(turned ? 0.25 : 1)
    }
    .frame(width: 240, height: 240)
    .task {
      guard Theme.motion else { turned = true; return }
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.spring(response: 0.95, dampingFraction: 0.78)) { turned = true }
        try? await Task.sleep(for: .milliseconds(1700))
        withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { turned = false }
        try? await Task.sleep(for: .milliseconds(900))
      }
    }
  }

  private var phone: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
      // Mini Cover Flow na tela
      HStack(spacing: -10) {
        ForEach(0..<3, id: \.self) { i in
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.prismDiagonal.opacity(i == 1 ? 1 : 0.55))
            .frame(width: i == 1 ? 26 : 16, height: i == 1 ? 26 : 22)
            .rotation3DEffect(.degrees(i == 0 ? 55 : (i == 2 ? -55 : 0)), axis: (0, 1, 0))
            .zIndex(i == 1 ? 1 : 0)
        }
      }
      .offset(y: 4)
      Capsule().fill(.black).frame(width: 22, height: 6).offset(y: -50)
    }
    .frame(width: 66, height: 128)
    .shadow(color: Theme.lavender.opacity(0.35), radius: 18, y: 6)
  }
}

// MARK: - Vazio / carregando

struct CoverFlowEmpty: View {
  let source: CoverFlowScreen.Source

  var body: some View {
    if source != .library && AppModel.shared.feed == nil {
      VStack(spacing: 12) {
        ProgressView().tint(.white)
        Text("Carregando capas…").font(Theme.font(14)).foregroundStyle(.white.opacity(0.6))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      EmptyStateView(icon: "square.stack.3d.forward.dottedline", title: "Nada por aqui ainda",
                     message: "Curta músicas ou abra os lançamentos para preencher o Cover Flow.")
        .frame(maxHeight: .infinity)
    }
  }
}
