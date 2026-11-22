import SwiftUI

/// Opening animation for Lume Music — Liquid Glass Soundwave 1.0:
/// Obsidian cinema stage, harmonic amber→coral soundwave ribbon converging into the frosted
/// Liquid Glass musical emblem, orbital light halo, "lume" + "MUSIC" reveal, and smooth dive-through.
struct IntroView: View {
  let done: () -> Void
  @State private var start = Date()
  @State private var diveAt: Date?
  @State private var finished = false

  private var motion: Bool { Theme.motion }
  private static let enterTime = 1.72, exitTime = 0.54
  private static let particles: [(x: Double, y: Double, r: Double, speed: Double, phase: Double, tint: Int)] = {
    var g = SystemRandomNumberGenerator()
    return (0..<26).map { i in
      (Double.random(in: 0...1, using: &g), Double.random(in: 0...1, using: &g),
       Double.random(in: 0.7...2.1, using: &g), Double.random(in: 0.35...1.2, using: &g),
       Double.random(in: 0...6.28, using: &g), i % 4)
    }
  }()

  var body: some View {
    TimelineView(.animation(paused: finished)) { timeline in
      let t = timeline.date.timeIntervalSince(start)
      let enter = motion ? min(1, max(0, t / Self.enterTime)) : 1
      let exit = diveAt.map { min(1, max(0, timeline.date.timeIntervalSince($0) / (motion ? Self.exitTime : 0.22))) } ?? 0
      Canvas { ctx, size in draw(&ctx, size, enter: enter, exit: exit, life: t) }
        .opacity(1 - Self.smooth(Self.seg(exit, 0.22, 1)))
    }
    .ignoresSafeArea()
    .contentShape(Rectangle())
    .onTapGesture { if diveAt == nil { diveAt = Date() } }
    .accessibilityLabel("Lume Music")
    .task {
      start = Date()
      do { try await Task.sleep(for: .milliseconds(motion ? 1980 : 300)) } catch { return }
      if diveAt == nil { diveAt = Date() }
      let left = (motion ? Self.exitTime : 0.22) - Date().timeIntervalSince(diveAt ?? Date())
      if left > 0 { do { try await Task.sleep(for: .milliseconds(Int(left * 1000))) } catch { return } }
      guard !Task.isCancelled else { return }
      finished = true
      done()
    }
  }

  private static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { max(0, min(1, (t - a) / (b - a))) }
  private static func out(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
  private static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
  private static func spring(_ x: Double) -> Double { let s = 1.45, y = x - 1; return y * y * ((s + 1) * y + s) + 1 }

  private func glow(_ ctx: GraphicsContext, _ colors: [Color], at p: CGPoint, rx: Double, ry: Double, alpha: Double) {
    guard alpha > 0.004, rx > 0, ry > 0 else { return }
    var c = ctx
    c.opacity = min(1, alpha)
    c.translateBy(x: p.x, y: p.y)
    c.scaleBy(x: rx, y: ry)
    c.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
           with: .radialGradient(Gradient(stops: [.init(color: colors[0], location: 0), .init(color: colors[1], location: 0.36), .init(color: colors[2], location: 1)]), center: .zero, startRadius: 0, endRadius: 1))
  }

  private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, enter: Double, exit: Double, life: Double) {
    let w = size.width, h = size.height, unit = min(w, h)
    let cx = w / 2, cy = h / 2 - unit * 0.03
    let p = enter * 0.88
    let ignite = Self.out(Self.seg(p, 0, 0.20))
    let waveLife = 1 - Self.smooth(Self.seg(p, 0.36, 0.72))
    let emblemIn = Self.seg(p, 0.14, 0.48), emblemScale = emblemIn <= 0 ? 0 : Self.spring(emblemIn)
    let orbitIn = Self.smooth(Self.seg(p, 0.10, 0.56))
    let orbitFade = 1 - Self.smooth(Self.seg(p, 0.54, 0.86))
    let wordIn = Self.smooth(Self.seg(p, 0.34, 0.66))
    let tagIn = Self.out(Self.seg(p, 0.52, 0.84))
    let creditIn = Self.smooth(Self.seg(p, 0.56, 0.84))
    let dive = exit * exit
    let group = 1 - Self.smooth(Self.seg(exit, 0, 0.76))

    let amber = Theme.amber, coral = Theme.coral, white = Color.white
    let warmGlow = [amber.opacity(0.92), coral.opacity(0.32), coral.opacity(0)]
    let whiteGlow = [white, white.opacity(0.38), white.opacity(0)]

    // Obsidian stage
    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.bg))

    // Dual radial ambient cinema aura
    var room = ctx
    room.opacity = ignite * (1 - dive)
    room.fill(Path(CGRect(origin: .zero, size: size)),
              with: .radialGradient(Gradient(stops: [.init(color: amber.opacity(0.22), location: 0), .init(color: coral.opacity(0.08), location: 0.46), .init(color: .clear, location: 1)]),
                                    center: CGPoint(x: cx - unit * 0.15, y: cy - unit * 0.08), startRadius: 0, endRadius: unit * 0.95))
    room.fill(Path(CGRect(origin: .zero, size: size)),
              with: .radialGradient(Gradient(stops: [.init(color: coral.opacity(0.15), location: 0), .init(color: Color.blue.opacity(0.05), location: 0.5), .init(color: .clear, location: 1)]),
                                    center: CGPoint(x: cx + unit * 0.22, y: cy + unit * 0.15), startRadius: 0, endRadius: unit * 0.85))

    // Floating dust particles
    for d in Self.particles {
      let x = (d.x + life * d.speed * 0.022).truncatingRemainder(dividingBy: 1) * w
      var fy = (d.y - life * d.speed * 0.032).truncatingRemainder(dividingBy: 1)
      if fy < 0 { fy += 1 }
      let tw = 0.08 + 0.26 * abs(sin(d.phase + life * 2.5))
      let r = d.r * unit * 0.0022
      let col: Color = d.tint == 0 ? amber : (d.tint == 1 ? coral : white)
      ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: fy * h - r, width: r * 2, height: r * 2)),
               with: .color(col.opacity(tw * ignite * (1 - exit))))
    }

    // Harmonic Ares-inspired opening soundwave ribbon across the stage
    if motion, waveLife > 0.01 {
      let amp = unit * 0.068 * ignite * waveLife
      for layer in 0..<3 {
        var path = Path()
        let steps = 72
        let freq = 2.6 + Double(layer) * 0.9
        let phase = life * (4.8 + Double(layer) * 1.4) + Double(layer) * 1.3
        for i in 0...steps {
          let frac = Double(i) / Double(steps)
          let env = sin(frac * .pi)
          let x = frac * w
          let y = cy + sin(frac * .pi * freq + phase) * amp * env * (1.0 - Double(layer) * 0.24)
          if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        var wc = ctx
        wc.opacity = (layer == 0 ? 0.72 : 0.34) * waveLife * group
        wc.stroke(path,
                  with: .linearGradient(Gradient(colors: [.clear, amber, white, coral, .clear]),
                                        startPoint: CGPoint(x: 0, y: cy), endPoint: CGPoint(x: w, y: cy)),
                  style: StrokeStyle(lineWidth: layer == 0 ? 2.2 : 1.1, lineCap: .round))
      }
    }

    // Zoom stage for dive transition
    var stage = ctx
    let zoom = 1 + 1.15 * dive
    stage.translateBy(x: cx, y: cy); stage.scaleBy(x: zoom, y: zoom); stage.translateBy(x: -cx, y: -cy)

    let tileSize = min(104, unit * 0.25)
    let tileRect = CGRect(x: cx - tileSize / 2, y: cy - tileSize * 0.72, width: tileSize, height: tileSize)
    let tileCenter = CGPoint(x: tileRect.midX, y: tileRect.midY)
    let tilePath = Path(roundedRect: tileRect, cornerRadius: tileSize * 0.27, style: .continuous)

    // Backlight behind emblem
    let pulse = sin(.pi * Self.seg(p, 0.35, 0.74))
    glow(stage, warmGlow, at: tileCenter, rx: tileSize * (1.5 + 0.4 * pulse), ry: tileSize * (1.5 + 0.4 * pulse), alpha: (0.30 * emblemIn + 0.28 * pulse) * group)

    // Orbital glass halo ring
    if motion, orbitIn > 0, orbitFade > 0.01 {
      let r = tileSize * 0.74
      var arc = Path()
      arc.addArc(center: tileCenter, radius: r,
                 startAngle: .degrees(-120 + orbitIn * 170),
                 endAngle: .degrees(-120 + orbitIn * 170 + 215 * orbitIn), clockwise: false)
      var rc = stage
      rc.opacity = 0.78 * orbitIn * orbitFade * group
      rc.stroke(arc,
                with: .linearGradient(Gradient(colors: [amber.opacity(0), amber, white, coral, coral.opacity(0)]),
                                      startPoint: CGPoint(x: tileCenter.x - r, y: tileCenter.y - r),
                                      endPoint: CGPoint(x: tileCenter.x + r, y: tileCenter.y + r)),
                style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
    }

    // Sculpted Liquid Glass tile + glowing music note bars inside
    if emblemScale > 0 {
      var t = stage
      let s = 0.78 + 0.22 * emblemScale
      t.translateBy(x: tileCenter.x, y: tileCenter.y); t.scaleBy(x: s, y: s); t.translateBy(x: -tileCenter.x, y: -tileCenter.y)
      t.opacity = emblemIn * group
      t.fill(tilePath, with: .linearGradient(Gradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.23), Color(red: 0.06, green: 0.08, blue: 0.12), Color(red: 0.035, green: 0.043, blue: 0.065)]),
                                             startPoint: tileRect.origin, endPoint: CGPoint(x: tileRect.maxX, y: tileRect.maxY)))
      // Diagonal glass sheen sweep
      let shine = Self.seg(p, 0.46, 0.80)
      if shine > 0, shine < 1 {
        var sc = t
        sc.clip(to: tilePath)
        sc.translateBy(x: tileCenter.x, y: tileCenter.y); sc.rotate(by: .degrees(-24)); sc.translateBy(x: -tileCenter.x, y: -tileCenter.y)
        glow(sc, whiteGlow, at: CGPoint(x: tileRect.minX - tileSize * 0.4 + shine * tileSize * 1.9, y: tileCenter.y), rx: tileSize * 0.2, ry: tileSize * 1.3, alpha: 0.42)
      }
      t.stroke(tilePath,
               with: .linearGradient(Gradient(stops: [.init(color: Color(red: 1, green: 0.96, blue: 0.87).opacity(0.9), location: 0),
                                                      .init(color: amber.opacity(0.48), location: 0.36),
                                                      .init(color: coral.opacity(0.24), location: 0.72),
                                                      .init(color: white.opacity(0.10), location: 1)]),
                                     startPoint: tileRect.origin, endPoint: CGPoint(x: tileRect.maxX, y: tileRect.maxY)),
               lineWidth: 1.6)

      // Stylized harmonic 5-bar luminous sound emblem inside tile
      let heights: [Double] = [0.24, 0.44, 0.62, 0.38, 0.22]
      let barW = tileSize * 0.075
      let spacing = tileSize * 0.13
      let startX = tileCenter.x - spacing * 2
      let barShade = GraphicsContext.Shading.linearGradient(
        Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.88), amber, coral]),
        startPoint: CGPoint(x: tileCenter.x, y: tileCenter.y - tileSize * 0.32),
        endPoint: CGPoint(x: tileCenter.x, y: tileCenter.y + tileSize * 0.32))
      for (idx, hFrac) in heights.enumerated() {
        let waveMod = motion ? (0.88 + 0.16 * sin(life * 5.2 + Double(idx) * 0.9)) : 1.0
        let bh = tileSize * hFrac * waveMod * Self.out(Self.seg(p, 0.22 + Double(idx) * 0.04, 0.56))
        let bx = startX + Double(idx) * spacing - barW / 2
        let br = CGRect(x: bx, y: tileCenter.y - bh / 2, width: barW, height: bh)
        t.fill(Path(roundedRect: br, cornerRadius: barW / 2), with: barShade)
      }
    }

    // "lume" wordmark + luminous divider + "MUSIC"
    let wordY = tileRect.maxY + tileSize * 0.42
    if wordIn > 0 {
      let wordSize = min(56, unit * 0.14)
      let word = stage.resolve(Text("lume").font(Theme.font(wordSize, .heavy)).tracking(-wordSize * 0.035).foregroundColor(Color(white: 0.98)))
      var wctx = stage
      wctx.opacity = wordIn * group
      wctx.draw(word, at: CGPoint(x: cx, y: wordY + 10 * (1 - wordIn)), anchor: .center)
    }

    if tagIn > 0 {
      let divY = wordY + unit * 0.095
      let half = tileSize * 0.85 * tagIn
      var dv = stage
      dv.opacity = 0.6 * tagIn * group
      dv.fill(Path(CGRect(x: cx - half, y: divY - 0.8, width: half * 2, height: 1.6)),
              with: .linearGradient(Gradient(colors: [.clear, amber, white, coral, .clear]),
                                    startPoint: CGPoint(x: cx - half, y: divY), endPoint: CGPoint(x: cx + half, y: divY)))
      let tag = stage.resolve(Text("M U S I C").font(Theme.font(13, .bold)).tracking(4 + 4 * (1 - tagIn)).foregroundColor(amber.opacity(0.92 * tagIn * group)))
      stage.draw(tag, at: CGPoint(x: cx, y: divY + 22), anchor: .center)
    }

    if exit > 0 {
      glow(ctx, warmGlow, at: CGPoint(x: cx, y: cy), rx: unit * (0.35 + 1.3 * dive), ry: unit * (0.35 + 1.3 * dive), alpha: sin(.pi * exit) * 0.34)
    }

    let note = ctx.resolve(Text(Theme.credit).font(Theme.font(10.5, .medium)).foregroundColor(.white.opacity(0.45 * creditIn * (1 - exit))))
    ctx.draw(note, at: CGPoint(x: w / 2, y: h - 42), anchor: .center)
  }
}
