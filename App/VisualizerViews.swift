import AVFoundation
import SwiftUI
import UIKit

// MARK: - Stage: Ondas 3D (real audio-reactive)

struct WavesStage: View {
  let track: Track
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared
  @State private var hintVisible = true

  private var style: VisualizerStyle { store.visualizerStyle == .off ? .ares : store.visualizerStyle }

  var body: some View {
    ZStack(alignment: .bottom) {
      SpectrumVisualizer(style: style, palette: player.palette, artworkURL: player.currentArtwork, isPlaying: player.isPlaying)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
          Haptics.selection()
          let order: [VisualizerStyle] = [.ares, .aurora, .orb]
          let i = order.firstIndex(of: style) ?? 0
          withAnimation(.easeInOut(duration: 0.35)) { store.visualizerStyle = order[(i + 1) % order.count] }
        }
      if hintVisible {
        Text("\(style.title) · toque para trocar")
          .font(Theme.font(12.5, .medium))
          .foregroundStyle(Theme.secondary)
          .padding(.horizontal, 12)
          .frame(height: 28)
          .glassCapsule()
          .transition(.opacity)
          .padding(.bottom, 6)
      }
    }
    .task {
      try? await Task.sleep(for: .seconds(2.6))
      withAnimation(.easeOut(duration: 0.6)) { hintVisible = false }
    }
  }
}

/// Holds a short history of spectrum frames for the 3D ridgeline (reference type: mutated while drawing).
final class RidgeHistory {
  var frames: [[Float]] = []
  var lastPush: Double = 0
  let depth = 26

  func push(_ f: [Float], at t: Double) {
    guard t - lastPush >= 1.0 / 22 else { return }
    lastPush = t
    frames.insert(f, at: 0)
    if frames.count > depth { frames.removeLast(frames.count - depth) }
  }
}

struct SpectrumVisualizer: View {
  let style: VisualizerStyle
  let palette: ArtworkPalette
  var artworkURL: String = ""
  let isPlaying: Bool

  @ObservedObject private var spectrum = AudioSpectrum.shared
  @State private var history = RidgeHistory()
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    ZStack {
      if style == .orb {
        orbArtwork
      }
      TimelineView(.animation(minimumInterval: 1 / 45, paused: !isPlaying && !spectrum.isLive)) { tl in
        let t = tl.date.timeIntervalSinceReferenceDate
        let bands = currentBands(t: t)
        Canvas { ctx, size in
          switch style {
          case .ares, .off: drawRidges(&ctx, size: size, bands: bands, t: t)
          case .aurora: drawBars(&ctx, size: size, bands: bands)
          case .orb: drawOrb(&ctx, size: size, bands: bands, t: t)
          }
        }
      }
    }
  }

  private func currentBands(t: Double) -> [Float] {
    if spectrum.isLive { return spectrum.bands }
    let n = AudioSpectrum.bandCount
    guard isPlaying else { return Array(repeating: 0.02, count: n) }
    return (0..<n).map { i in
      let f = Double(i) / Double(n)
      let beat = 0.5 + 0.5 * sin(t * 7.8)
      let v = 0.42 * (1 - f) * (0.6 + 0.4 * beat)
        + 0.22 * abs(sin(t * 3.1 + Double(i) * 0.55))
        + 0.14 * abs(sin(t * 11.3 + Double(i) * 1.7))
      return Float(min(1, max(0.02, v)))
    }
  }

  /// Interpolate the 24 bands into `count` smooth samples.
  private func resample(_ b: [Float], count: Int, mirror: Bool = false) -> [Double] {
    guard b.count > 1 else { return Array(repeating: 0, count: count) }
    return (0..<count).map { i in
      var u = Double(i) / Double(count - 1)
      if mirror { u = abs(u - 0.5) * 2 }
      let x = u * Double(b.count - 1)
      let i0 = Int(x), i1 = min(b.count - 1, i0 + 1)
      let fr = x - Double(i0)
      let s = fr * fr * (3 - 2 * fr)
      return Double(b[i0]) * (1 - s) + Double(b[i1]) * s
    }
  }

  // Joy-Division-like 3D terrain marching toward the viewer.
  private func drawRidges(_ ctx: inout GraphicsContext, size: CGSize, bands: [Float], t: Double) {
    history.push(bands, at: t)
    let w = size.width, h = size.height
    let horizon = h * 0.16
    let front = h * 0.92
    let samples = 72
    let frames = history.frames
    guard !frames.isEmpty else { return }
    let dark = scheme == .dark
    let lineGrad = Gradient(colors: [palette.vibrant2, palette.vibrant, .white, palette.vibrant, palette.vibrant2])

    for row in stride(from: frames.count - 1, through: 0, by: -1) {
      let z = Double(row) / Double(history.depth)
      let persp = 1 / (1 + z * 2.6)
      let baseY = horizon + (front - horizon) * persp
      let half = w * 0.56 * persp
      let amp = h * 0.42 * persp
      let vals = resample(frames[row], count: samples, mirror: true)
      var line = Path()
      for i in 0..<samples {
        let u = Double(i) / Double(samples - 1)
        let x = w / 2 + (u - 0.5) * 2 * half
        let env = pow(sin(u * .pi), 1.6)
        let jitter = 0.04 * sin(u * 31 + Double(row) * 1.7 + t * 0.8)
        let y = baseY - (vals[i] * 0.92 + jitter) * amp * env
        if i == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
      }
      var fill = line
      fill.addLine(to: CGPoint(x: w / 2 + half, y: baseY + 2))
      fill.addLine(to: CGPoint(x: w / 2 - half, y: baseY + 2))
      fill.closeSubpath()
      ctx.fill(fill, with: .color(dark ? Color.black.opacity(0.55) : Color.white.opacity(0.55)))
      var lc = ctx
      lc.opacity = (1 - z) * 0.95 + 0.05
      if row == 0 {
        var glow = ctx
        glow.addFilter(.blur(radius: 6))
        glow.opacity = 0.8
        glow.stroke(line, with: .linearGradient(lineGrad, startPoint: CGPoint(x: 0, y: baseY), endPoint: CGPoint(x: w, y: baseY)), lineWidth: 4)
      }
      lc.stroke(line, with: .linearGradient(lineGrad, startPoint: CGPoint(x: w / 2 - half, y: baseY), endPoint: CGPoint(x: w / 2 + half, y: baseY)),
                style: StrokeStyle(lineWidth: row == 0 ? 2.4 : max(0.7, 1.6 * persp), lineCap: .round, lineJoin: .round))
    }
  }

  private func drawBars(_ ctx: inout GraphicsContext, size: CGSize, bands: [Float]) {
    let count = 40
    let vals = resample(bands, count: count, mirror: true)
    let gap: CGFloat = 4
    let bw = max(2, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
    let mid = size.height * 0.56
    let maxH = size.height * 0.42
    let grad = Gradient(colors: [.white, palette.vibrant, palette.vibrant2])
    var glow = ctx
    glow.addFilter(.blur(radius: 10))
    glow.opacity = 0.65
    for i in 0..<count {
      let hh = max(3, CGFloat(vals[i]) * maxH)
      let x = CGFloat(i) * (bw + gap)
      let r = CGRect(x: x, y: mid - hh, width: bw, height: hh)
      let shade = GraphicsContext.Shading.linearGradient(grad, startPoint: CGPoint(x: x, y: mid - maxH), endPoint: CGPoint(x: x, y: mid))
      glow.fill(Path(roundedRect: r, cornerRadius: bw / 2), with: shade)
      ctx.fill(Path(roundedRect: r, cornerRadius: bw / 2), with: shade)
      var ref = ctx
      ref.opacity = 0.22
      ref.fill(Path(roundedRect: CGRect(x: x, y: mid + 6, width: bw, height: hh * 0.45), cornerRadius: bw / 2), with: shade)
    }
  }

  private func drawOrb(_ ctx: inout GraphicsContext, size: CGSize, bands: [Float], t: Double) {
    let c = CGPoint(x: size.width / 2, y: size.height / 2)
    let base = min(size.width, size.height) * 0.27
    let count = 96
    let vals = resample(bands, count: count / 2)
    let grad = Gradient(colors: [palette.vibrant, .white, palette.vibrant2, palette.vibrant])
    var glow = ctx
    glow.addFilter(.blur(radius: 8))
    glow.opacity = 0.7
    for i in 0..<count {
      let k = i < count / 2 ? i : count - 1 - i
      let v = vals[k]
      let a = Double(i) / Double(count) * 2 * .pi - .pi / 2 + t * 0.12
      let r0 = base * 1.06
      let r1 = r0 + base * (0.08 + 0.75 * v)
      var p = Path()
      p.move(to: CGPoint(x: c.x + r0 * cos(a), y: c.y + r0 * sin(a)))
      p.addLine(to: CGPoint(x: c.x + r1 * cos(a), y: c.y + r1 * sin(a)))
      let shade = GraphicsContext.Shading.conicGradient(grad, center: c)
      glow.stroke(p, with: shade, style: StrokeStyle(lineWidth: 3, lineCap: .round))
      ctx.stroke(p, with: shade, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    }
  }

  private var orbArtwork: some View {
    GeometryReader { g in
      let d = min(g.size.width, g.size.height) * 0.5
      ArtworkImage(url: artworkURL, cornerRadius: d / 2, maxPixel: 500)
        .frame(width: d, height: d)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
        .scaleEffect(1 + CGFloat(spectrum.level) * 0.06)
        .shadow(color: palette.vibrant.opacity(0.6), radius: 24)
        .rotationEffect(.degrees(isPlaying ? 0 : 0))
        .position(x: g.size.width / 2, y: g.size.height / 2)
        .animation(.easeOut(duration: 0.12), value: spectrum.level)
    }
  }
}

// MARK: - Stage: Lyrics (Apple Music style)

struct LyricsStage: View {
  @ObservedObject private var player = AudioPlayer.shared
  @State private var lastUserScroll = Date.distantPast

  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 8) {
        if let src = player.lyrics?.source {
          Text(src).font(Theme.font(12, .medium)).foregroundStyle(Theme.tertiary)
        }
        Spacer()
        if player.lyrics != nil {
          Button { player.toggleTranslation() } label: {
            HStack(spacing: 5) {
              if player.isTranslatingLyrics {
                ProgressView().controlSize(.mini)
              } else {
                Image(systemName: "translate").font(.system(size: 12, weight: .semibold))
              }
              Text(player.showTranslation ? "Tradução" : "Traduzir").font(Theme.font(12.5, .semibold))
            }
            .foregroundStyle(player.showTranslation ? Theme.onPrism : Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background { if player.showTranslation { Capsule().fill(Theme.prismDiagonal) } }
            .modifier(ConditionalGlassCapsule(enabled: !player.showTranslation))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 26)

      if player.isLoadingLyrics {
        VStack(alignment: .leading, spacing: 18) {
          ForEach(0..<6, id: \.self) { i in
            SkeletonBlock(width: [260, 200, 290, 170, 240, 210][i], height: 26, radius: 8)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 20)
      } else if let bundle = player.lyrics, !bundle.lines.isEmpty {
        lyricsScroll(bundle)
      } else {
        VStack(spacing: 14) {
          Spacer()
          EmptyStateView(icon: "quote.bubble", title: "Letra indisponível", message: "Procuramos em LRCLIB, NetEase, YouTube Music e Letras.mus.br e não encontramos esta letra ainda.")
          Button { player.reloadLyrics() } label: {
            Label("Tentar de novo", systemImage: "arrow.clockwise")
              .font(Theme.font(14, .semibold))
              .foregroundStyle(Theme.text)
              .padding(.horizontal, 18)
              .frame(height: 40)
              .glassCapsule(interactive: true)
          }
          .buttonStyle(.plain)
          Spacer()
        }
      }
    }
  }

  private func lyricsScroll(_ bundle: LyricsBundle) -> some View {
    let active = activeIndex(bundle)
    return ScrollViewReader { proxy in
      ScrollView(showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: bundle.synced ? 26 : 16) {
          Color.clear.frame(height: 40)
          ForEach(Array(bundle.lines.enumerated()), id: \.element.id) { idx, line in
            LyricLineView(
              line: line,
              synced: bundle.synced,
              state: !bundle.synced ? .plain : (idx == active ? .current : (idx < active ? .past : .future)),
              showTranslation: player.showTranslation,
              nextTime: idx + 1 < bundle.lines.count ? bundle.lines[idx + 1].time : line.time + 6
            )
            .id(line.id)
            .onTapGesture {
              guard bundle.synced else { return }
              Haptics.light()
              player.seek(to: line.time)
              lastUserScroll = .distantPast
            }
          }
          Color.clear.frame(height: 220)
        }
        .padding(.horizontal, 26)
      }
      .onScrollPhaseChange { _, phase in
        if phase == .interacting || phase == .decelerating { lastUserScroll = Date() }
      }
      .mask(
        LinearGradient(stops: [
          .init(color: .clear, location: 0), .init(color: .black, location: 0.08),
          .init(color: .black, location: 0.82), .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
      )
      .onChange(of: active) { _, idx in
        guard bundle.synced, idx >= 0, idx < bundle.lines.count, Date().timeIntervalSince(lastUserScroll) > 3 else { return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
          proxy.scrollTo(bundle.lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.3))
        }
      }
      .onAppear {
        if bundle.synced, active >= 0, active < bundle.lines.count {
          proxy.scrollTo(bundle.lines[active].id, anchor: UnitPoint(x: 0.5, y: 0.3))
        }
      }
    }
  }

  private func activeIndex(_ bundle: LyricsBundle) -> Int {
    guard bundle.synced else { return -1 }
    let t = player.currentTime + 0.3
    var best = -1
    for (i, l) in bundle.lines.enumerated() {
      if l.time <= t { best = i } else { break }
    }
    return max(0, best)
  }
}

private struct LyricLineView: View {
  enum LineState { case current, past, future, plain }
  let line: LyricLine
  let synced: Bool
  let state: LineState
  let showTranslation: Bool
  let nextTime: Double

  var body: some View {
    let isBreak = line.text == "♪" || line.text.trimmingCharacters(in: .whitespaces).isEmpty
    VStack(alignment: .leading, spacing: 6) {
      if isBreak {
        BreathingDots(active: state == .current)
          .frame(height: 30)
      } else {
        Text(line.text)
          .font(.system(size: synced ? 30 : 22, weight: .bold))
          .foregroundStyle(Theme.text.opacity(opacity))
          .fixedSize(horizontal: false, vertical: true)
          .blur(radius: state == .future || state == .past ? 0.6 : 0)
          .scaleEffect(state == .current ? 1 : 0.97, anchor: .leading)
        if showTranslation, let tr = line.translated, !tr.isEmpty {
          Text(tr)
            .font(.system(size: synced ? 18 : 16, weight: .semibold))
            .foregroundStyle(Theme.text.opacity(opacity * 0.7))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .animation(.easeOut(duration: 0.35), value: state == .current)
  }

  private var opacity: Double {
    switch state {
    case .current: return 1
    case .past: return 0.32
    case .future: return 0.38
    case .plain: return 0.88
    }
  }
}

private struct BreathingDots: View {
  let active: Bool
  var body: some View {
    TimelineView(.animation(paused: !active)) { tl in
      let t = tl.date.timeIntervalSinceReferenceDate
      HStack(spacing: 10) {
        ForEach(0..<3, id: \.self) { i in
          Circle()
            .fill(Theme.text.opacity(active ? 0.9 : 0.3))
            .frame(width: 11, height: 11)
            .scaleEffect(active ? 0.75 + 0.35 * CGFloat(abs(sin(t * 2.2 + Double(i) * 0.6))) : 0.8)
        }
      }
    }
  }
}

// MARK: - Animated artwork (Apple Music motion covers + gentle live motion)

struct AnimatedArtworkView: View {
  let staticURL: String
  let animatedURL: String?
  let isPlaying: Bool
  var cornerRadius: CGFloat = 16
  var enableLiveMotion: Bool = true

  @State private var videoReady = false

  var body: some View {
    GeometryReader { geo in
      ZStack {
        ArtworkImage(url: staticURL, cornerRadius: 0, maxPixel: 1200)
          .frame(width: geo.size.width, height: geo.size.height)
        if enableLiveMotion, let anim = animatedURL, let url = URL(string: anim), !anim.isEmpty {
          LoopingVideoLayer(url: url, isPlaying: isPlaying, onReady: { videoReady = true })
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(videoReady ? 1 : 0)
            .animation(.easeInOut(duration: 0.5), value: videoReady)
        }
        LinearGradient(colors: [.white.opacity(0.10), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
          .allowsHitTesting(false)
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.6))
      .onChange(of: animatedURL) { _, _ in videoReady = false }
    }
  }
}

/// Zero-chrome muted seamless HLS looper for Apple Music animated covers.
struct LoopingVideoLayer: UIViewRepresentable {
  let url: URL
  let isPlaying: Bool
  let onReady: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> PlayerHostView {
    let view = PlayerHostView()
    context.coordinator.load(url: url, into: view, isPlaying: isPlaying, onReady: onReady)
    return view
  }

  func updateUIView(_ uiView: PlayerHostView, context: Context) {
    if context.coordinator.currentURL != url {
      context.coordinator.load(url: url, into: uiView, isPlaying: isPlaying, onReady: onReady)
    } else {
      context.coordinator.setPlaying(isPlaying)
    }
  }

  static func dismantleUIView(_ uiView: PlayerHostView, coordinator: Coordinator) {
    coordinator.stop()
  }

  final class PlayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
  }

  final class Coordinator {
    var currentURL: URL?
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var statusObs: NSKeyValueObservation?

    func load(url: URL, into view: PlayerHostView, isPlaying: Bool, onReady: @escaping () -> Void) {
      stop()
      currentURL = url
      let item = AVPlayerItem(url: url)
      let qp = AVQueuePlayer(playerItem: item)
      qp.isMuted = true
      qp.actionAtItemEnd = .none
      qp.preventsDisplaySleepDuringVideoPlayback = false
      let lp = AVPlayerLooper(player: qp, templateItem: item)
      view.playerLayer.player = qp
      view.playerLayer.videoGravity = .resizeAspectFill
      queuePlayer = qp
      looper = lp
      statusObs = item.observe(\.status, options: [.new]) { it, _ in
        if it.status == .readyToPlay { DispatchQueue.main.async { onReady() } }
      }
      if isPlaying { qp.play() }
    }

    func setPlaying(_ playing: Bool) {
      if playing { queuePlayer?.play() } else { queuePlayer?.pause() }
    }

    func stop() {
      statusObs?.invalidate()
      statusObs = nil
      looper?.disableLooping()
      looper = nil
      queuePlayer?.pause()
      queuePlayer?.removeAllItems()
      queuePlayer = nil
    }
  }
}
