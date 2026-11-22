import SwiftUI

/// Classic iPod-style Cover Flow, rebuilt: continuous drag with momentum, tightly stacked
/// side covers at ~70°, glossy floor reflections, iPod scrubber, and tap-to-flip tracklists.
struct CoverFlowItem: Identifiable, Hashable {
  let id: String
  let title: String
  let subtitle: String
  let artworkURL: String
  var album: AlbumShowcase? = nil
  var track: Track? = nil
  var localTracks: [Track] = []
}

struct CoverFlowScreen: View {
  @ObservedObject private var app = AppModel.shared
  @ObservedObject private var store = LibraryStore.shared
  @Environment(\.dismiss) private var dismiss
  @State private var source: Source = .releases

  enum Source: String, CaseIterable, Identifiable {
    case releases = "Lançamentos"
    case trending = "Em alta"
    case library = "Sua biblioteca"
    var id: String { rawValue }
  }

  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(white: 0.10), .black, .black], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
      RadialGradient(colors: [Theme.lavender.opacity(0.18), .clear], center: .init(x: 0.5, y: 0.62), startRadius: 10, endRadius: 360)
        .ignoresSafeArea()

      VStack(spacing: 14) {
        HStack {
          GlassIconButton(systemName: "xmark", size: 40, foreground: .white) { dismiss() }
          Spacer()
          Text("Cover Flow")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
          Spacer()
          Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)

        HStack(spacing: 6) {
          ForEach(Source.allCases) { s in
            PrismChip(title: s.rawValue, active: source == s) { source = s }
          }
        }

        CoverFlowCarousel(items: items)
          .id(source)
          .frame(maxHeight: .infinity)
      }
      .padding(.top, 8)
    }
    .environment(\.colorScheme, .dark)
  }

  private var items: [CoverFlowItem] {
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

struct CoverFlowCarousel: View {
  let items: [CoverFlowItem]

  @State private var pos: Double = 0
  @State private var dragStart: Double?
  @State private var flippedId: String?
  @State private var lastHapticIndex = 0

  var body: some View {
    GeometryReader { g in
      let W = g.size.width
      let C = min(W * 0.58, g.size.height * 0.40)
      VStack(spacing: 0) {
        Spacer(minLength: 0).frame(maxHeight: 50)
        ZStack {
          ForEach(visibleIndices, id: \.self) { idx in
            let item = items[idx]
            CoverFlowCard(item: item, size: C, flipped: flippedId == item.id) {
              flippedId = nil
            }
            .modifier(CoverFlowTransform(delta: Double(idx) - pos, width: W, cardSize: C))
            .onTapGesture { tap(idx) }
          }
        }
        .frame(width: W, height: C * 1.55)
        .contentShape(Rectangle())
        .gesture(drag(spacing: W * 0.16))

        if !items.isEmpty {
          let cur = items[currentIndex]
          VStack(spacing: 4) {
            Text(cur.title)
              .font(Theme.font(19, .semibold))
              .foregroundStyle(.white)
              .lineLimit(1)
            Text(cur.subtitle)
              .font(Theme.font(15))
              .foregroundStyle(.white.opacity(0.6))
              .lineLimit(1)
          }
          .padding(.horizontal, 30)
          .animation(.none, value: currentIndex)
          .padding(.top, 6)

          Spacer(minLength: 10)
            .frame(maxHeight: 90)

          scrubber
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        } else {
          EmptyStateView(icon: "square.stack.3d.forward.dottedline", title: "Nada por aqui ainda", message: "Curta músicas ou abra os lançamentos para preencher o Cover Flow.")
        }
      }
    }
  }

  private var currentIndex: Int {
    guard !items.isEmpty else { return 0 }
    return min(items.count - 1, max(0, Int(pos.rounded())))
  }

  private var visibleIndices: [Int] {
    guard !items.isEmpty else { return [] }
    let c = currentIndex
    return Array(max(0, c - 7)...min(items.count - 1, c + 7))
  }

  private var scrubber: some View {
    VStack(spacing: 8) {
      Slider(
        value: Binding(get: { pos }, set: { v in
          flippedId = nil
          pos = v
          tick()
        }),
        in: 0...Double(max(1, items.count - 1)),
        onEditingChanged: { editing in
          if !editing { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { pos = pos.rounded() } }
        }
      )
      .tint(.white.opacity(0.85))
      Text("\(currentIndex + 1) de \(items.count)")
        .font(Theme.font(12, .medium))
        .foregroundStyle(.white.opacity(0.45))
        .monospacedDigit()
    }
  }

  private func drag(spacing: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { v in
        if dragStart == nil { dragStart = pos; flippedId = nil }
        let raw = (dragStart ?? 0) - Double(v.translation.width / spacing)
        pos = rubberBand(raw)
        tick()
      }
      .onEnded { v in
        let projected = (dragStart ?? pos) - Double(v.predictedEndTranslation.width / spacing)
        let target = min(Double(items.count - 1), max(0, projected.rounded()))
        dragStart = nil
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { pos = target }
      }
  }

  private func rubberBand(_ x: Double) -> Double {
    let maxV = Double(max(0, items.count - 1))
    if x < 0 { return x * 0.3 }
    if x > maxV { return maxV + (x - maxV) * 0.3 }
    return x
  }

  private func tick() {
    let i = currentIndex
    if i != lastHapticIndex {
      lastHapticIndex = i
      Haptics.selection()
    }
  }

  private func tap(_ idx: Int) {
    if idx != currentIndex {
      flippedId = nil
      withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { pos = Double(idx) }
      return
    }
    let item = items[idx]
    if let t = item.track {
      Haptics.medium()
      AudioPlayer.shared.play(t, in: items.compactMap(\.track))
      return
    }
    Haptics.medium()
    withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
      flippedId = flippedId == item.id ? nil : item.id
    }
  }
}

/// Piecewise Cover Flow geometry, animatable on `delta` so in-between frames stay correct.
struct CoverFlowTransform: ViewModifier, Animatable {
  var delta: Double
  let width: CGFloat
  let cardSize: CGFloat

  var animatableData: Double {
    get { delta }
    set { delta = newValue }
  }

  func body(content: Content) -> some View {
    let a = abs(delta)
    let s = delta >= 0 ? 1.0 : -1.0
    let near = min(a, 1)
    let gap = Double(width) * 0.405
    let step = Double(width) * 0.10
    let x = s * (gap * near + step * max(0, a - 1))
    let angle = -s * 72 * near
    let scale = 1 - 0.12 * near
    return content
      .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.42)
      .scaleEffect(scale)
      .offset(x: x)
      .zIndex(-a)
      .opacity(a > 6.5 ? 0 : 1)
  }
}

struct CoverFlowCard: View {
  let item: CoverFlowItem
  let size: CGFloat
  let flipped: Bool
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 2) {
      FlipCard(angle: flipped ? 180 : 0) {
        front
      } back: {
        CoverFlowBack(item: item, size: size, onClose: onClose)
      }
      .frame(width: size, height: size)
      // Floor reflection
      ArtworkImage(url: item.artworkURL, cornerRadius: 3, maxPixel: 500)
        .frame(width: size, height: size)
        .scaleEffect(x: 1, y: -1)
        .frame(width: size, height: size * 0.45, alignment: .top)
        .clipped()
        .mask(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
        .opacity(flipped ? 0 : 1)
    }
    .animation(.easeInOut(duration: 0.3), value: flipped)
  }

  private var front: some View {
    ArtworkImage(url: item.artworkURL, cornerRadius: 3, maxPixel: 700)
      .frame(width: size, height: size)
      .overlay(
        LinearGradient(colors: [.white.opacity(0.16), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
      )
      .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
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
    .scaleEffect(1 + 0.18 * sin(angle * .pi / 180) * 0.5 + (angle > 90 ? 0.12 : 0))
  }
}

struct CoverFlowBack: View {
  let item: CoverFlowItem
  let size: CGFloat
  let onClose: () -> Void
  @ObservedObject private var player = AudioPlayer.shared
  @State private var tracks: [Track] = []
  @State private var loading = true

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        ArtworkImage(url: item.artworkURL, cornerRadius: 4, maxPixel: 120)
          .frame(width: 36, height: 36)
        VStack(alignment: .leading, spacing: 0) {
          Text(item.title).font(Theme.font(13, .semibold)).lineLimit(1)
          Text(item.subtitle).font(Theme.font(11.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
        Spacer(minLength: 0)
        Button {
          if let f = tracks.first { player.play(f, in: tracks) }
        } label: {
          Image(systemName: "play.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.onPrism)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Theme.prismDiagonal))
        }
        .buttonStyle(.plain)
      }
      .padding(10)
      Divider().overlay(Color.white.opacity(0.15))
      if loading {
        ProgressView().tint(.white).frame(maxHeight: .infinity)
      } else {
        ScrollView(showsIndicators: false) {
          LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
              Button {
                Haptics.light()
                player.play(t, in: tracks)
              } label: {
                HStack(spacing: 8) {
                  Text("\(i + 1)").font(Theme.font(11.5, .medium)).foregroundStyle(.white.opacity(0.45)).frame(width: 18)
                  Text(t.title).font(Theme.font(13)).lineLimit(1)
                    .foregroundStyle(player.currentTrack?.id == t.id ? Theme.rose : .white)
                  Spacer(minLength: 4)
                  Text(t.formattedDuration).font(Theme.font(11)).foregroundStyle(.white.opacity(0.45)).monospacedDigit()
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .foregroundStyle(.white)
    .frame(width: size, height: size)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
    )
    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.8))
    .shadow(color: .black.opacity(0.6), radius: 16, y: 8)
    .task {
      if !item.localTracks.isEmpty {
        tracks = item.localTracks
      } else if let a = item.album {
        tracks = await DiscoveryService.shared.albumTracks(a)
      }
      loading = false
    }
  }
}
