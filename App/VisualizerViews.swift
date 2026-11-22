import AVFoundation
import SwiftUI
import UIKit

/// Nostalgic Ares-inspired real-time audio wave visualizer reimagined in Liquid Glass:
/// supports 3 selectable live modes: Ondas Ares (oscilloscope ribbons + reflection),
/// Espectro Aurora (32 glass EQ bars with peak caps), and Orbe Líquido (pulsing aura).
struct AresVisualizerView: View {
  let style: VisualizerStyle
  let isPlaying: Bool
  let accentA: Color
  let accentB: Color
  var compact: Bool = false

  var body: some View {
    if style == .off {
      EmptyView()
    } else {
      TimelineView(.animation(paused: !isPlaying && !Theme.motion)) { timeline in
        let t = timeline.date.timeIntervalSinceReferenceDate
        Canvas { ctx, size in
          switch style {
          case .ares:
            drawAresWaves(&ctx, size: size, t: t)
          case .aurora:
            drawAuroraSpectrum(&ctx, size: size, t: t)
          case .orb:
            drawLiquidOrb(&ctx, size: size, t: t)
          case .off:
            break
          }
        }
      }
    }
  }

  private func drawAresWaves(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
    let w = size.width, h = size.height
    let midY = compact ? h * 0.54 : h * 0.50
    let energy: Double = isPlaying ? (0.76 + 0.24 * sin(t * 5.2) * cos(t * 2.1)) : 0.14
    let maxAmp = (compact ? h * 0.38 : h * 0.30) * energy

    // Subtle horizontal glass horizon line
    ctx.stroke(
      Path { p in p.move(to: CGPoint(x: 12, y: midY)); p.addLine(to: CGPoint(x: w - 12, y: midY)) },
      with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.16), .clear]), startPoint: CGPoint(x: 0, y: midY), endPoint: CGPoint(x: w, y: midY)),
      lineWidth: 0.7
    )

    // 5 layered harmonic oscilloscope ribbons (classic Ares/WMP nostalgia with Liquid Glass polish)
    let configs: [(freq: Double, speed: Double, amp: Double, width: Double, colors: [Color], alpha: Double)] = [
      (2.4, 3.6, 1.00, compact ? 2.4 : 3.2, [.clear, accentA, .white, accentB, .clear], 0.92),
      (3.7, -4.4, 0.78, compact ? 1.8 : 2.3, [.clear, accentB, accentA, .white.opacity(0.8), .clear], 0.72),
      (5.1, 5.2, 0.56, compact ? 1.3 : 1.7, [.clear, .cyan.opacity(0.8), .white, accentA, .clear], 0.55),
      (1.8, -2.5, 0.88, compact ? 4.5 : 8.0, [.clear, accentA.opacity(0.32), accentB.opacity(0.28), .clear], 0.42),
      (6.4, 6.8, 0.34, compact ? 1.0 : 1.2, [.clear, .white.opacity(0.75), accentA, .clear], 0.48),
    ]

    let steps = compact ? 64 : 96
    for (idx, cfg) in configs.enumerated() {
      var wave = Path()
      var mirror = Path()
      for i in 0...steps {
        let frac = Double(i) / Double(steps)
        let x = frac * w
        let envelope = pow(sin(frac * .pi), 1.35)
        let beat = sin(frac * .pi * cfg.freq + t * cfg.speed + Double(idx))
        let harmonic = 0.42 * sin(frac * .pi * (cfg.freq * 2.1) - t * (cfg.speed * 1.35) + Double(idx) * 1.7)
        let dy = (beat + harmonic) * maxAmp * cfg.amp * envelope
        let pt = CGPoint(x: x, y: midY - dy)
        let mpt = CGPoint(x: x, y: midY + dy * 0.46)
        if i == 0 {
          wave.move(to: pt)
          mirror.move(to: mpt)
        } else {
          wave.addLine(to: pt)
          mirror.addLine(to: mpt)
        }
      }
      let grad = GraphicsContext.Shading.linearGradient(
        Gradient(colors: cfg.colors),
        startPoint: CGPoint(x: 0, y: midY),
        endPoint: CGPoint(x: w, y: midY)
      )
      var mainCtx = ctx
      mainCtx.opacity = cfg.alpha
      mainCtx.stroke(wave, with: grad, style: StrokeStyle(lineWidth: cfg.width, lineCap: .round, lineJoin: .round))

      if !compact && idx < 2 {
        var refCtx = ctx
        refCtx.opacity = cfg.alpha * 0.24
        refCtx.stroke(mirror, with: grad, style: StrokeStyle(lineWidth: cfg.width * 0.8, lineCap: .round))
      }
    }
  }

  private func drawAuroraSpectrum(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
    let count = compact ? 22 : 30
    let padX: Double = 10
    let usableW = max(1, size.width - padX * 2)
    let gap: Double = compact ? 3.5 : 4.5
    let barW = max(2.5, (usableW - gap * Double(count - 1)) / Double(count))
    let baseY = compact ? size.height * 0.86 : size.height * 0.76
    let maxH = compact ? size.height * 0.72 : size.height * 0.56

    for i in 0..<count {
      let frac = Double(i) / Double(count - 1)
      let centerWeight = 0.45 + 0.55 * sin(frac * .pi)
      let raw = isPlaying
        ? abs(sin(t * 4.8 + Double(i) * 0.42) * 0.55 + cos(t * 7.6 - Double(i) * 0.71) * 0.30 + sin(t * 11.2 + Double(i) * 1.1) * 0.15)
        : 0.08
      let h = max(4, maxH * min(1.0, (0.14 + raw * 0.92) * centerWeight))
      let x = padX + Double(i) * (barW + gap)
      let rect = CGRect(x: x, y: baseY - h, width: barW, height: h)
      let shading = GraphicsContext.Shading.linearGradient(
        Gradient(colors: [.white.opacity(0.95), accentA, accentB]),
        startPoint: CGPoint(x: x, y: baseY - h),
        endPoint: CGPoint(x: x, y: baseY)
      )
      ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: shading)

      // Floating luminous peak cap + soft glass floor reflection
      if !compact {
        let capY = baseY - h - 6
        ctx.fill(Path(roundedRect: CGRect(x: x, y: capY, width: barW, height: 2.5), cornerRadius: 1.5),
                 with: .color(.white.opacity(0.85)))
        var ref = ctx
        ref.opacity = 0.22
        let refH = h * 0.28
        ref.fill(Path(roundedRect: CGRect(x: x, y: baseY + 3, width: barW, height: refH), cornerRadius: barW / 2), with: shading)
      }
    }
  }

  private func drawLiquidOrb(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
    let cx = size.width / 2, cy = size.height / 2
    let baseR = min(size.width, size.height) * (compact ? 0.34 : 0.27)
    let pulse = isPlaying ? (1.0 + 0.14 * sin(t * 5.2) + 0.06 * cos(t * 9.3)) : 0.92

    // Outer pulsing rings
    for ring in 0..<3 {
      let r = baseR * pulse * (1.0 + Double(ring) * 0.28 + (isPlaying ? 0.05 * sin(t * 3.1 + Double(ring)) : 0))
      var path = Path()
      let pts = 64
      for i in 0...pts {
        let a = Double(i) / Double(pts) * .pi * 2
        let wobble = isPlaying ? sin(a * Double(3 + ring) + t * (2.4 + Double(ring))) * (baseR * 0.055) : 0
        let px = cx + cos(a) * (r + wobble)
        let py = cy + sin(a) * (r + wobble)
        if i == 0 { path.move(to: CGPoint(x: px, y: py)) } else { path.addLine(to: CGPoint(x: px, y: py)) }
      }
      path.closeSubpath()
      var c = ctx
      c.opacity = 0.55 - Double(ring) * 0.15
      c.stroke(path, with: .linearGradient(Gradient(colors: [accentA, .white, accentB]),
                                           startPoint: CGPoint(x: cx - r, y: cy - r), endPoint: CGPoint(x: cx + r, y: cy + r)),
               lineWidth: ring == 0 ? 2.2 : 1.2)
    }

    // Core glowing glass sphere
    let cr = baseR * pulse * 0.84
    ctx.fill(
      Path(ellipseIn: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2)),
      with: .radialGradient(Gradient(stops: [
        .init(color: .white.opacity(0.85), location: 0),
        .init(color: accentA.opacity(0.75), location: 0.42),
        .init(color: accentB.opacity(0.32), location: 0.78),
        .init(color: .clear, location: 1)
      ]), center: CGPoint(x: cx - cr * 0.22, y: cy - cr * 0.22), startRadius: 0, endRadius: cr)
    )
  }
}

/// Official Apple Music Animated Artwork (.m3u8 seamless video loop) with instant static cover base
/// and smooth Liquid Glass Live Motion fallback for static album covers.
struct AnimatedArtworkView: View {
  let staticURL: String
  let animatedURL: String?
  let isPlaying: Bool
  var cornerRadius: CGFloat = 24
  var enableLiveMotion: Bool = true

  @State private var breathe = false
  @State private var videoReady = false

  var body: some View {
    GeometryReader { geo in
      ZStack {
        // Static high-res artwork base with subtle Live Motion when playing
        RemoteArtwork(url: staticURL, cornerRadius: cornerRadius)
          .frame(width: geo.size.width, height: geo.size.height)
          .scaleEffect(shouldLiveMotion ? (breathe ? 1.055 : 1.0) : 1.0)
          .animation(
            shouldLiveMotion ? .easeInOut(duration: 6.5).repeatForever(autoreverses: true) : .easeOut(duration: 0.4),
            value: breathe
          )

        // Real Apple Music HLS Animated Cover overlay (seamless muted loop)
        if enableLiveMotion, let anim = animatedURL, let url = URL(string: anim), !anim.isEmpty {
          LoopingVideoLayer(url: url, isPlaying: isPlaying, onReady: { videoReady = true })
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(videoReady ? 1 : 0)
            .animation(.easeInOut(duration: 0.45), value: videoReady)
        }

        // Subtle Liquid Glass top-left specular sheen
        LinearGradient(
          colors: [Color.white.opacity(0.18), Color.clear, Color.black.opacity(0.12)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .allowsHitTesting(false)
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(Theme.glassStroke, lineWidth: 1.0)
      )
      .onAppear { breathe = isPlaying }
      .onChange(of: isPlaying) { _, playing in breathe = playing }
      .onChange(of: animatedURL) { _, _ in videoReady = false }
    }
  }

  private var shouldLiveMotion: Bool {
    enableLiveMotion && isPlaying && Theme.motion && (animatedURL == nil || !videoReady)
  }
}

/// Zero-chrome muted seamless HLS video looper for official Apple Music animated album covers.
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
      let lp = AVPlayerLooper(player: qp, templateItem: item)
      view.playerLayer.player = qp
      view.playerLayer.videoGravity = .resizeAspectFill
      queuePlayer = qp
      looper = lp
      statusObs = item.observe(\.status, options: [.new]) { it, _ in
        if it.status == .readyToPlay {
          DispatchQueue.main.async { onReady() }
        }
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
