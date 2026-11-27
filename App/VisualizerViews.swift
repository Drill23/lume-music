import AVFoundation
import NaturalLanguage
import SwiftUI
import UIKit

// MARK: - Stage: Ondas 3D (real audio-reactive)

struct WavesStage: View {
  let track: Track
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var store = LibraryStore.shared

  private var style: VisualizerStyle { store.visualizerStyle.resolved }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      SpectrumVisualizer(style: style, palette: player.palette, artworkURL: player.currentArtwork, isPlaying: player.isPlaying)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
          Haptics.selection()
          let order = VisualizerStyle.activeStyles
          let i = order.firstIndex(of: style) ?? 0
          withAnimation(.easeInOut(duration: 0.32)) { store.visualizerStyle = order[(i + 1) % order.count] }
        }

      StageStyleOrb(icon: "waveform", accessibilityLabel: "Estilo das ondas") { dismiss in
        VStack(alignment: .leading, spacing: 5) {
          Text("VISUALIZADOR")
            .font(Theme.font(10, .heavy))
            .tracking(0.8)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 6)
            .padding(.bottom, 2)

          ForEach(VisualizerStyle.activeStyles) { st in
            let active = style == st
            Button {
              Haptics.selection()
              withAnimation(.easeInOut(duration: 0.3)) { store.visualizerStyle = st }
              dismiss()
            } label: {
              HStack(spacing: 8) {
                Image(systemName: st.icon)
                  .font(.system(size: 11.5, weight: .semibold))
                  .frame(width: 16)
                Text(st.title)
                  .font(Theme.font(12, active ? .bold : .semibold))
                Spacer(minLength: 4)
                if active {
                  Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                }
              }
              .foregroundStyle(active ? Theme.onPrism : Theme.text)
              .padding(.horizontal, 10)
              .frame(height: 44)
              .contentShape(Rectangle())
              .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .fill(active ? AnyShapeStyle(Theme.prismDiagonal) : AnyShapeStyle(Color.white.opacity(0.06)))
              }
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}

/// Peak-hold caps com gravidade para o visualizador Espectro.
final class PeakHoldState {
  var peaks: [Double] = Array(repeating: 0, count: 40)
  var lastT: Double = 0

  func update(_ vals: [Double], at t: Double) -> [Double] {
    let dt = lastT == 0 ? 0.016 : min(0.08, max(0.004, t - lastT))
    lastT = t
    if peaks.count != vals.count { peaks = Array(repeating: 0, count: vals.count) }
    for i in 0..<vals.count {
      if vals[i] >= peaks[i] {
        peaks[i] = vals[i]
      } else {
        peaks[i] = max(0, peaks[i] - dt * 0.45)
      }
    }
    return peaks
  }
}

/// Ondulações disparadas por cada batida (anéis que se expandem e somem em ~1,1 s).
final class BeatRippleState {
  struct Ripple { var t0: Double; var strength: Double }
  private(set) var ripples: [Ripple] = []
  private var lastBeat = Int.min

  func update(beat: Int, kick: Double, at t: Double) {
    if beat != lastBeat {
      if lastBeat != Int.min && kick > 0.25 {
        ripples.append(Ripple(t0: t, strength: min(1, kick)))
        if ripples.count > 4 { ripples.removeFirst(ripples.count - 4) }
      }
      lastBeat = beat
    }
    ripples.removeAll { t - $0.t0 > 1.1 }
  }
}

/// Visualizadores reativos à música (5.0).
///
/// • O espectro é LIDO por quadro (`AudioSpectrum.frame()`), sem @Published em alta frequência.
/// • Cada estilo recebe `kick` (pulso da batida, attack instantâneo / release ~170 ms), graves e nível.
/// • Sem filtros de blur por quadro: o "brilho" é feito com traços largos translúcidos (barato).
/// • ≤ 60 fps (30 no modo economia / aparelho quente / Pouca Energia); pausa fora da tela, com o app
///   inativo/tela bloqueada e logo depois que a música para.
struct SpectrumVisualizer: View {
  let style: VisualizerStyle
  let palette: ArtworkPalette
  var artworkURL: String = ""
  let isPlaying: Bool

  @ObservedObject private var spectrum = AudioSpectrum.shared   // só `isLive` publica
  @ObservedObject private var gov = PerfGovernor.shared
  @State private var peakHold = PeakHoldState()
  @State private var ripples = BeatRippleState()
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let paused = !gov.isActive || (!isPlaying && !spectrum.isLive)
    TimelineView(.animation(minimumInterval: gov.frameInterval, paused: paused)) { tl in
      let t = tl.date.timeIntervalSinceReferenceDate
      let f = spectrum.frame(isPlaying: isPlaying)
      let _ = ripples.update(beat: f.beat, kick: Double(f.kick), at: t)
      ZStack {
        if style.resolved == .orb {
          orbArtwork(kick: Double(f.kick))
        }
        Canvas { ctx, size in
          switch style.resolved {
          case .aurora: drawBars(&ctx, size: size, f: f, t: t)
          case .orb, .solarRing: drawOrb(&ctx, size: size, f: f, t: t)
          case .oscilloscope: drawOscilloscope(&ctx, size: size, f: f, t: t)
          case .nebula: drawNebula(&ctx, size: size, f: f, t: t)
          case .ares, .off: drawLiquid(&ctx, size: size, f: f, t: t)
          }
        }
      }
    }
  }

  private var dark: Bool { scheme == .dark }
  private var rich: Bool { !gov.reduced }

  /// Interpola as 24 bandas em `count` amostras suaves.
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

  private var iridescent: [Color] {
    [palette.vibrant, Theme.sky, Theme.lavender, Theme.rose, Theme.peach, palette.vibrant2]
  }

  /// Gradiente iridescente que "escorre" devagar com o tempo.
  private func flowingGradient(_ t: Double, width w: CGFloat, alpha: Double) -> (Gradient, CGPoint, CGPoint) {
    let cols = iridescent.map { $0.opacity(alpha) }
    let shift = CGFloat(sin(t * 0.23)) * w * 0.35
    return (Gradient(colors: cols), CGPoint(x: -w * 0.2 + shift, y: 0), CGPoint(x: w * 1.2 + shift, y: 0))
  }

  // MARK: Ondas Líquidas (vidro iridescente)

  private func drawLiquid(_ ctx: inout GraphicsContext, size: CGSize, f: SpectrumFrame, t: Double) {
    // 5.0: fitas de vidro iridescentes simétricas em torno do centro (estilo "Siri"), que se
    // misturam em cor sem estourar para branco e nunca encostam nas bordas do palco.
    let w = size.width, h = size.height
    let kick = Double(f.kick), level = Double(f.level), bass = Double(f.bass)
    let mid = h * 0.5
    let samples = rich ? 84 : 48
    let vals = resample(f.bands, count: samples, mirror: true)
    let maxAmp = h * 0.36

    // Clarão suave da batida atrás das fitas
    if kick > 0.02 {
      let r = w * (0.42 + 0.22 * kick)
      let glowRect = CGRect(x: w / 2 - r, y: mid - r * 0.55, width: 2 * r, height: r * 1.1)
      ctx.fill(Path(ellipseIn: glowRect), with: .radialGradient(
        Gradient(colors: [palette.vibrant.opacity((dark ? 0.26 : 0.18) * kick), palette.vibrant2.opacity(0.08 * kick), .clear]),
        center: CGPoint(x: w / 2, y: mid), startRadius: 0, endRadius: r))
    }

    // Ondulações de cada batida (anéis finos que se abrem a partir do centro)
    for rp in ripples.ripples {
      let age = (t - rp.t0) / 1.1
      guard age >= 0 && age < 1 else { continue }
      let rr = w * (0.10 + 0.55 * age)
      let ring = CGRect(x: w / 2 - rr, y: mid - rr * 0.34, width: 2 * rr, height: rr * 0.68)
      ctx.stroke(Path(ellipseIn: ring), with: .color((dark ? Color.white : palette.vibrant).opacity(0.30 * rp.strength * (1 - age))),
                 lineWidth: 1.2 + 1.8 * (1 - age))
    }

    // Cores saturadas (as pastel do tema somadas viravam branco puro no miolo)
    let ribbonColors: [Color] = [
      palette.vibrant,
      Color(hue: 0.92, saturation: 0.72, brightness: 1.0),   // rosa
      Color(hue: 0.74, saturation: 0.66, brightness: 1.0),   // violeta
      Color(hue: 0.55, saturation: 0.70, brightness: 1.0),   // céu
      Color(hue: 0.07, saturation: 0.66, brightness: 1.0),   // pêssego
    ]
    let layers = rich ? 5 : 3
    ctx.blendMode = dark ? .screen : .normal
    for layer in 0..<layers {
      let li = Double(layer)
      let speed = 0.30 + 0.14 * li
      let k1 = 1.0 + 0.30 * li, k2 = 2.1 + 0.45 * li
      let phase = li * 1.9
      let amp = maxAmp * (0.30 + 0.30 * level + 0.40 * kick) * (1.0 - 0.12 * li)
      var top = [CGPoint](), bottom = [CGPoint]()
      top.reserveCapacity(samples); bottom.reserveCapacity(samples)
      for i in 0..<samples {
        let u = Double(i) / Double(samples - 1)
        let x = w * CGFloat(u)
        let env = pow(sin(u * .pi), 2.2)             // pontas finas, barriga no meio
        let carrier = 0.6 * sin(2 * .pi * (u * k1 + t * speed * 0.5) + phase)
          + 0.4 * sin(2 * .pi * (u * k2 - t * speed * 0.35) + phase * 0.7)
        let energy = min(1.25, 0.25 + 0.9 * vals[i] + 0.3 * bass)
        let a = amp * env * energy
        let center = CGFloat(a * 0.35 * carrier)       // a fita "serpenteia" em torno do centro
        top.append(CGPoint(x: x, y: mid + center - CGFloat(a)))
        bottom.append(CGPoint(x: x, y: mid + center + CGFloat(a * 0.55)))
      }
      var ribbon = Path()
      ribbon.addLines(top)
      ribbon.addLines(bottom.reversed())
      ribbon.closeSubpath()
      var edge = Path()
      edge.addLines(top)

      let col = ribbonColors[layer % ribbonColors.count]
      let col2 = ribbonColors[(layer + 2) % ribbonColors.count]
      var lc = ctx
      lc.opacity = dark ? 0.26 + 0.14 * kick : 0.30 + 0.14 * kick
      lc.fill(ribbon, with: .linearGradient(
        Gradient(colors: [col.opacity(0), col, col2, col.opacity(0)]),
        startPoint: CGPoint(x: 0, y: mid), endPoint: CGPoint(x: w, y: mid)))
      // fio de luz na crista (vidro)
      var ec = ctx
      ec.opacity = dark ? 0.55 + 0.35 * kick : 0.45 + 0.30 * kick
      ec.stroke(edge, with: .linearGradient(
        Gradient(colors: [.clear, (dark ? Color.white : col2).opacity(0.9), .clear]),
        startPoint: CGPoint(x: 0, y: mid), endPoint: CGPoint(x: w, y: mid)),
        style: StrokeStyle(lineWidth: layer == 0 ? 1.6 : 1.0, lineCap: .round, lineJoin: .round))
    }
    ctx.blendMode = .normal
  }

  // MARK: Espectro (barras com peak-hold)

  private func drawBars(_ ctx: inout GraphicsContext, size: CGSize, f: SpectrumFrame, t: Double) {
    let count = 36
    let kick = Double(f.kick)
    let vals = resample(f.bands, count: count, mirror: true)
    let peaks = peakHold.update(vals, at: t)
    let gap: CGFloat = 4
    let bw = max(2, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
    let mid = size.height * 0.60
    let maxH = size.height * 0.44 * (1 + 0.08 * kick)
    let grad = Gradient(colors: [.white, palette.vibrant, palette.vibrant2])
    for i in 0..<count {
      let hh = max(3, CGFloat(vals[i]) * maxH)
      let x = CGFloat(i) * (bw + gap)
      let r = CGRect(x: x, y: mid - hh, width: bw, height: hh)
      let shade = GraphicsContext.Shading.linearGradient(grad, startPoint: CGPoint(x: x, y: mid - maxH), endPoint: CGPoint(x: x, y: mid))
      if rich {
        var halo = ctx
        halo.opacity = 0.16 + 0.3 * kick
        halo.fill(Path(roundedRect: r.insetBy(dx: -3, dy: -3), cornerRadius: bw / 2 + 3), with: shade)
      }
      ctx.fill(Path(roundedRect: r, cornerRadius: bw / 2), with: shade)
      let ph = max(3, CGFloat(peaks[i]) * maxH)
      let cap = CGRect(x: x, y: mid - ph - 5, width: bw, height: 2.5)
      ctx.fill(Path(roundedRect: cap, cornerRadius: 1.25), with: .color(.white.opacity(0.9)))
      var ref = ctx
      ref.opacity = 0.22
      ref.fill(Path(roundedRect: CGRect(x: x, y: mid + 6, width: bw, height: hh * 0.42), cornerRadius: bw / 2), with: shade)
    }
  }

  // MARK: Orbe

  private func drawOrb(_ ctx: inout GraphicsContext, size: CGSize, f: SpectrumFrame, t: Double) {
    let c = CGPoint(x: size.width / 2, y: size.height / 2)
    let kick = Double(f.kick)
    let base = min(size.width, size.height) * 0.27 * (1 + 0.05 * kick)
    let count = rich ? 96 : 64
    let vals = resample(f.bands, count: count / 2)
    let grad = Gradient(colors: [palette.vibrant, .white, palette.vibrant2, palette.vibrant])
    let shade = GraphicsContext.Shading.conicGradient(grad, center: c)

    for rp in ripples.ripples {
      let age = (t - rp.t0) / 1.1
      guard age >= 0 && age < 1 else { continue }
      let rr = base * (1.1 + 0.9 * age)
      ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)),
                 with: .color(.white.opacity(0.4 * rp.strength * (1 - age))), lineWidth: 1.5 + 2.5 * (1 - age))
    }

    var rays = Path()
    for i in 0..<count {
      let k = i < count / 2 ? i : count - 1 - i
      let v = vals[k]
      let a = Double(i) / Double(count) * 2 * .pi - .pi / 2 + t * 0.12
      let r0 = base * 1.06
      let r1 = r0 + base * (0.08 + 0.75 * v)
      rays.move(to: CGPoint(x: c.x + r0 * cos(a), y: c.y + r0 * sin(a)))
      rays.addLine(to: CGPoint(x: c.x + r1 * cos(a), y: c.y + r1 * sin(a)))
    }
    if rich {
      var halo = ctx
      halo.opacity = 0.22 + 0.3 * kick
      halo.stroke(rays, with: shade, style: StrokeStyle(lineWidth: 6, lineCap: .round))
    }
    ctx.stroke(rays, with: shade, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))

    var ring = Path()
    for i in 0...72 {
      let u = Double(i) / 72.0
      let a = u * 2 * .pi - t * 0.22
      let v = vals[i % vals.count]
      let rr = base * (1.28 + 0.12 * v + 0.10 * kick + 0.04 * sin(a * 6 + t * 2))
      let pt = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
      if i == 0 { ring.move(to: pt) } else { ring.addLine(to: pt) }
    }
    ring.closeSubpath()
    ctx.stroke(ring, with: .color(.white.opacity(0.35 + 0.4 * kick)), lineWidth: 1.4)
  }

  // MARK: Osciloscópio

  private func drawOscilloscope(_ ctx: inout GraphicsContext, size: CGSize, f: SpectrumFrame, t: Double) {
    let w = size.width, h = size.height
    let mid = h * 0.5
    let kick = Double(f.kick)
    var grid = Path()
    for gx in 1..<6 {
      let x = w * CGFloat(gx) / 6.0
      grid.move(to: CGPoint(x: x, y: h * 0.14)); grid.addLine(to: CGPoint(x: x, y: h * 0.86))
    }
    ctx.stroke(grid, with: .color(Theme.text.opacity(0.06)), lineWidth: 0.8)
    var midLine = Path(); midLine.move(to: CGPoint(x: 0, y: mid)); midLine.addLine(to: CGPoint(x: w, y: mid))
    ctx.stroke(midLine, with: .color(Theme.text.opacity(0.10)), lineWidth: 1)

    let vals = resample(f.bands, count: rich ? 96 : 64, mirror: true)
    let grad = Gradient(colors: [Theme.sky, Theme.lavender, .white, Theme.rose, Theme.peach])
    for layer in 0..<2 {
      var wave = Path()
      let phase = layer == 0 ? t * 4.5 : -t * 3.2 + 1.4
      let ampScale = (layer == 0 ? 0.36 : 0.22) * (1 + 0.5 * kick)
      for i in 0..<vals.count {
        let u = Double(i) / Double(vals.count - 1)
        let x = w * CGFloat(u)
        let env = sin(u * .pi)
        let carrier = sin(u * .pi * (layer == 0 ? 8.0 : 12.0) + phase)
        let y = mid + CGFloat(carrier * vals[i] * env * h * ampScale)
        if i == 0 { wave.move(to: CGPoint(x: x, y: y)) } else { wave.addLine(to: CGPoint(x: x, y: y)) }
      }
      let shade = GraphicsContext.Shading.linearGradient(grad, startPoint: .zero, endPoint: CGPoint(x: w, y: 0))
      if layer == 0 && rich {
        var halo = ctx
        halo.opacity = 0.22 + 0.3 * kick
        halo.stroke(wave, with: shade, style: StrokeStyle(lineWidth: 8, lineCap: .round))
      }
      ctx.stroke(wave, with: shade, style: StrokeStyle(lineWidth: layer == 0 ? 2.4 : 1.4, lineCap: .round))
    }
  }

  // MARK: Nebulosa

  private func drawNebula(_ ctx: inout GraphicsContext, size: CGSize, f: SpectrumFrame, t: Double) {
    let w = size.width, h = size.height
    let vals = resample(f.bands, count: rich ? 64 : 40)
    let bass = Double(f.bass), kick = Double(f.kick)
    let colors = [palette.vibrant, palette.vibrant2, Theme.sky, Theme.rose]
    if dark { ctx.blendMode = .plusLighter }
    for ribbon in 0..<4 {
      var path = Path()
      let baseY = h * (0.28 + 0.14 * Double(ribbon))
      for i in 0..<vals.count {
        let u = Double(i) / Double(vals.count - 1)
        let x = w * CGFloat(u)
        let lift = vals[i] * h * 0.22 * sin(u * .pi) * (1 + 0.4 * kick)
        let wave = sin(u * 6.0 + t * (1.2 + Double(ribbon) * 0.35) + Double(ribbon)) * (14 + 28 * bass)
        let y = baseY - lift + wave
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
      }
      let col = colors[ribbon % colors.count]
      if rich {
        ctx.stroke(path, with: .color(col.opacity(0.10 + 0.12 * kick)), style: StrokeStyle(lineWidth: 26, lineCap: .round))
      }
      ctx.stroke(path, with: .color(col.opacity(0.30 + 0.25 * kick)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
      ctx.stroke(path, with: .color(.white.opacity(0.65)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
    ctx.blendMode = .normal
    // Estrelas que acendem na batida (posições fixas, brilho guiado pelo pulso)
    for s in 0..<28 {
      let sx = w * CGFloat((Double((s * 37) % 100) / 100.0))
      let sy = h * CGFloat((Double((s * 73 + 19) % 100) / 100.0))
      let twinkle = 0.5 + 0.5 * sin(t * 1.3 + Double(s) * 2.4)
      let pulse = 1.5 + 2.0 * twinkle + 4.0 * kick * Double((s % 3) + 1) / 3
      ctx.fill(Path(ellipseIn: CGRect(x: sx - pulse / 2, y: sy - pulse / 2, width: pulse, height: pulse)),
               with: .color(.white.opacity(0.35 + 0.25 * twinkle + 0.4 * kick)))
    }
  }

  private func orbArtwork(kick: Double) -> some View {
    GeometryReader { g in
      let d = min(g.size.width, g.size.height) * 0.5
      ArtworkImage(url: artworkURL, cornerRadius: d / 2, maxPixel: 500)
        .frame(width: d, height: d)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.3 + 0.4 * kick), lineWidth: 1))
        .background {
          // brilho barato (gradiente estático) em vez de .shadow recalculada a cada quadro
          Circle().fill(RadialGradient(colors: [palette.vibrant.opacity(0.55), .clear], center: .center, startRadius: d * 0.4, endRadius: d * 0.75))
            .frame(width: d * 1.5, height: d * 1.5)
        }
        .scaleEffect(1 + CGFloat(kick) * 0.06)
        .position(x: g.size.width / 2, y: g.size.height / 2)
    }
  }
}

// MARK: - Stage: Lyrics (Apple Music style)

struct LyricsStage: View {
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var clock = PlaybackClock.shared
  @State private var lastUserScroll = Date.distantPast
  @State private var shareSnippet: String?

  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 8) {
        if let src = player.lyrics?.source {
          Text(src).font(Theme.font(12, .medium)).foregroundStyle(Theme.tertiary)
        }
        Spacer()
        if let lyr = player.lyrics, !lyr.lines.isEmpty {
          Button {
            Haptics.light()
            let idx = activeIndex(lyr)
            let picked = lyr.lines.indices.contains(idx) ? lyr.lines[idx].text : lyr.lines.first?.text ?? ""
            let next = lyr.lines.indices.contains(idx + 1) ? lyr.lines[idx + 1].text : ""
            shareSnippet = [picked, next].filter { !$0.isEmpty && $0 != "♪" }.joined(separator: "\n")
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "square.and.arrow.up").font(.system(size: 11.5, weight: .semibold))
              Text("Cartão").font(Theme.font(12, .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .glassCapsule(interactive: true)
          }
          .buttonStyle(.plain)
        }
        if let lyr = player.lyrics, !LyricsLanguage.isPortuguese(lyr) {
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
    .sheet(item: Binding(
      get: { shareSnippet.map { LyricCardPayload(text: $0) } },
      set: { shareSnippet = $0?.text }
    )) { payload in
      if let tr = player.currentTrack {
        LyricShareSheet(track: tr, artworkURL: player.currentArtwork, snippet: payload.text)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
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
    let t = clock.currentTime + 0.3
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

/// Detects whether lyrics are already in Portuguese (then the translate button is hidden).
enum LyricsLanguage {
  private static var cache: [String: Bool] = [:]
  static func isPortuguese(_ b: LyricsBundle) -> Bool {
    if let hit = cache[b.trackKey] { return hit }
    let sample = b.lines.prefix(40).map(\.text).joined(separator: " ")
    let r = NLLanguageRecognizer()
    r.processString(sample)
    let pt = r.dominantLanguage == .portuguese
    cache[b.trackKey] = pt
    return pt
  }
}

private struct LyricCardPayload: Identifiable {
  let id = UUID()
  let text: String
}

private struct LyricShareSheet: View {
  let track: Track
  let artworkURL: String
  let snippet: String
  @Environment(\.dismiss) private var dismiss
  @State private var rendered: UIImage?

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        cardView
          .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
        if let rendered {
          ShareLink(item: Image(uiImage: rendered), preview: SharePreview("\(track.title) — \(track.artist)", image: Image(uiImage: rendered))) {
            Label("Compartilhar imagem", systemImage: "square.and.arrow.up")
              .font(Theme.font(16, .bold))
              .foregroundStyle(Theme.onPrism)
              .frame(maxWidth: .infinity)
              .frame(height: 50)
              .background(Capsule().fill(Theme.prismDiagonal))
          }
          .padding(.horizontal, 24)
        } else {
          ShareLink(item: "“\(snippet)”\n— \(track.title), \(track.artist) · Lume Music") {
            Label("Compartilhar trecho", systemImage: "square.and.arrow.up")
              .font(Theme.font(16, .bold))
              .foregroundStyle(Theme.onPrism)
              .frame(maxWidth: .infinity)
              .frame(height: 50)
              .background(Capsule().fill(Theme.prismDiagonal))
          }
          .padding(.horizontal, 24)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Theme.canvas.ignoresSafeArea())
      .navigationTitle("Cartão de letra")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
      .task {
        let renderer = ImageRenderer(content: cardView.padding(16))
        renderer.scale = 3.0
        rendered = renderer.uiImage
      }
    }
  }

  private var cardView: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        ArtworkImage(url: artworkURL, cornerRadius: 10, maxPixel: 300)
          .frame(width: 52, height: 52)
        VStack(alignment: .leading, spacing: 2) {
          Text(track.title)
            .font(Theme.font(16, .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
          Text(track.artist)
            .font(Theme.font(13.5))
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
        }
        Spacer()
      }
      Text("“\(snippet)”")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Text("Lume Music")
          .font(Theme.font(11.5, .bold))
          .foregroundStyle(.white.opacity(0.78))
        Spacer()
        Image(systemName: "waveform")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white.opacity(0.8))
      }
    }
    .padding(22)
    .frame(width: 320)
    .background(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .fill(LinearGradient(colors: [Theme.rose, Theme.lavender, Theme.sky], startPoint: .topLeading, endPoint: .bottomTrailing))
    )
    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
  }
}
