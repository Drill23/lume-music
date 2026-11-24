import SwiftUI

/// Balística física de agulha para VU meters analógicos (ataque rápido, decaimento suave sem jitter).
final class VUBallistics {
  private var l: Double = 0
  private var r: Double = 0
  private var last: Double = 0

  func step(now: Double, targetL: Double, targetR: Double) -> (Double, Double) {
    let dt = last == 0 ? 0.016 : min(0.08, max(0.004, now - last))
    last = now
    let tauL = targetL > l ? 0.045 : 0.24
    let tauR = targetR > r ? 0.045 : 0.24
    l += (targetL - l) * (1 - exp(-dt / tauL))
    r += (targetR - r) * (1 - exp(-dt / tauR))
    return (l, r)
  }
}

/// Deck de fita K7 3D com 4 estilos de fita, flip sem espelhamento Lado A/B,
/// cabeçote magnético dourado, pinch rollers girando, VU meters balísticos com LED PEAK e teclas físicas.
struct CassetteStage: View {
  let track: Track
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var clock = PlaybackClock.shared
  @ObservedObject private var spectrum = AudioSpectrum.shared
  @ObservedObject private var art = ArtworkStore.shared
  @ObservedObject private var store = LibraryStore.shared

  @State private var sideB = false
  @State private var anchorTime: Double = 0
  @State private var anchorDate = Date()
  @State private var vuPhysics = VUBallistics()

  var body: some View {
    GeometryReader { g in
      let availH = g.size.height - 54
      let W = min(g.size.width - 36, 385, max(220, availH) / 1.17)
      VStack(spacing: W * 0.034) {
        Spacer(minLength: 0)
        deckWindow(W)
        meters(W)
        keys(W)
        styleStrip
        Spacer(minLength: 0)
      }
      .frame(width: g.size.width, height: g.size.height)
    }
    .onAppear { anchor() }
    .onChange(of: clock.currentTime) { _, _ in anchor() }
    .onChange(of: player.isPlaying) { _, _ in anchor() }
    .onChange(of: track.id) { _, _ in sideB = false }
  }

  private func anchor() {
    anchorTime = clock.currentTime
    anchorDate = Date()
  }

  private var styleStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(CassetteStyle.allCases) { st in
          let active = store.cassetteStyle == st
          Button {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.25)) { store.cassetteStyle = st }
          } label: {
            Text(st.rawValue)
              .font(Theme.font(11, .semibold))
              .foregroundStyle(active ? Theme.onPrism : Theme.text)
              .padding(.horizontal, 10)
              .frame(height: 28)
              .background {
                if active { Capsule().fill(Theme.prismDiagonal) }
              }
              .modifier(ConditionalGlassCapsule(enabled: !active))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 20)
    }
    .scrollClipDisabled()
  }

  // MARK: Janela do deck + Fita

  private func deckWindow(_ W: CGFloat) -> some View {
    let H = W * 0.70
    return ZStack {
      // Espessura 3D sutil sob a porta
      RoundedRectangle(cornerRadius: W * 0.07, style: .continuous)
        .fill(Color(white: 0.35))
        .offset(y: W * 0.015)

      BrushedPanel(cornerRadius: W * 0.07, dark: false).equatable()
      // Recesso
      RoundedRectangle(cornerRadius: W * 0.045, style: .continuous)
        .fill(Color.black.opacity(0.88))
        .padding(W * 0.045)
        .shadow(color: .white.opacity(0.65), radius: 0, x: 0.8, y: 1)

      TimelineView(.animation(paused: !player.isPlaying)) { tl in
        let t = player.isPlaying ? anchorTime + tl.date.timeIntervalSince(anchorDate) : anchorTime
        let p = clock.duration > 1 ? min(1, max(0, t / clock.duration)) : 0
        CassetteFlipWrapper(angle: sideB ? 180 : 0) {
          CassetteTape(
            width: W * 0.80,
            title: track.title,
            artist: track.artist,
            artworkURL: player.currentArtwork,
            sideB: false,
            progress: p,
            seconds: max(1, clock.duration),
            style: store.cassetteStyle
          )
        } back: {
          CassetteTape(
            width: W * 0.80,
            title: track.title,
            artist: track.artist,
            artworkURL: art.photo(for: track.artist) ?? player.currentArtwork,
            sideB: true,
            progress: p,
            seconds: max(1, clock.duration),
            style: store.cassetteStyle
          )
        }
      }
      .animation(.spring(response: 0.65, dampingFraction: 0.82), value: sideB)

      // Porta de vidro fumê com reflexo
      RoundedRectangle(cornerRadius: W * 0.045, style: .continuous)
        .fill(
          LinearGradient(
            stops: [
              .init(color: .white.opacity(0.18), location: 0),
              .init(color: .white.opacity(0.03), location: 0.35),
              .init(color: .clear, location: 0.55),
              .init(color: .white.opacity(0.08), location: 0.82),
              .init(color: .clear, location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
          )
        )
        .overlay(RoundedRectangle(cornerRadius: W * 0.045, style: .continuous).stroke(Color.white.opacity(0.20), lineWidth: 0.8))
        .padding(W * 0.045)
        .allowsHitTesting(false)

      HStack {
        Text("LUME · CrO₂ STEREO DECK")
          .font(.system(size: W * 0.021, weight: .heavy, design: .rounded))
          .tracking(1.1)
          .foregroundStyle(Color.black.opacity(0.45))
          .shadow(color: .white.opacity(0.75), radius: 0, x: 0.5, y: 0.6)
        Spacer()
        Text("DOLBY NR")
          .font(.system(size: W * 0.019, weight: .bold, design: .rounded))
          .tracking(0.8)
          .foregroundStyle(Color.black.opacity(0.38))
      }
      .padding(.horizontal, W * 0.08)
      .frame(maxHeight: .infinity, alignment: .bottom)
      .padding(.bottom, W * 0.013)
    }
    .frame(width: W, height: H)
    .shadow(color: .black.opacity(0.38), radius: W * 0.045, y: W * 0.028)
    .onTapGesture { Haptics.medium(); player.togglePlayPause() }
  }

  // MARK: VU Meters Balísticos + Contador

  private func meters(_ W: CGFloat) -> some View {
    let H = W * 0.22
    return ZStack {
      BrushedPanel(cornerRadius: W * 0.05, dark: true).equatable()
      HStack(spacing: W * 0.03) {
        TimelineView(.animation(minimumInterval: 1 / 45, paused: !player.isPlaying && !spectrum.isLive)) { tl in
          let raw = rawLevels(at: tl.date)
          let smooth = vuPhysics.step(now: tl.date.timeIntervalSinceReferenceDate, targetL: raw.0, targetR: raw.1)
          HStack(spacing: W * 0.025) {
            VUMeter(level: smooth.0, label: "L").frame(width: W * 0.33, height: H * 0.74)
            VUMeter(level: smooth.1, label: "R").frame(width: W * 0.33, height: H * 0.74)
          }
        }
        VStack(spacing: W * 0.012) {
          TapeCounter(value: Int(clock.currentTime) % 1000, digitWidth: W * 0.05)
          Text("COUNTER")
            .font(.system(size: W * 0.02, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.45))
        }
      }
    }
    .frame(width: W, height: H)
  }

  private func rawLevels(at date: Date) -> (Double, Double) {
    if spectrum.isLive {
      let b = spectrum.bands
      let half = max(1, b.count / 2)
      let low = b.prefix(half).reduce(0, +) / Float(half)
      let high = b.suffix(half).reduce(0, +) / Float(half)
      let l = 0.06 + Double(spectrum.level) * 0.58 + Double(low) * 0.22
      let r = 0.06 + Double(spectrum.level) * 0.58 + Double(high) * 0.26
      return (min(1, l), min(1, r))
    }
    guard player.isPlaying else { return (0, 0) }
    let t = date.timeIntervalSinceReferenceDate
    let base = 0.55 + 0.20 * sin(t * 2.3) * cos(t * 0.7)
    let l = base + 0.16 * sin(t * 9.1) + 0.08 * sin(t * 17.3)
    let r = base + 0.16 * sin(t * 8.3 + 1) + 0.08 * cos(t * 15.1)
    return (min(1, max(0, l)), min(1, max(0, r)))
  }

  // MARK: Teclas Mecânicas

  private func keys(_ W: CGFloat) -> some View {
    let H = W * 0.15
    return ZStack {
      RoundedRectangle(cornerRadius: W * 0.04, style: .continuous)
        .fill(LinearGradient(colors: [Color(white: 0.08), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: W * 0.04, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
      HStack(spacing: W * 0.012) {
        PianoKey(icon: "backward.fill", label: "REW", latched: false, width: W * 0.17, height: H * 0.78) { player.previousTrack() }
        PianoKey(icon: "play.fill", label: "PLAY", latched: player.isPlaying, width: W * 0.2, height: H * 0.78) {
          if !player.isPlaying { player.togglePlayPause() }
        }
        PianoKey(icon: "stop.fill", label: "STOP", latched: false, width: W * 0.17, height: H * 0.78) {
          if player.isPlaying { player.togglePlayPause() }
        }
        PianoKey(icon: "forward.fill", label: "FF", latched: false, width: W * 0.17, height: H * 0.78) { player.nextTrack() }
        PianoKey(icon: "eject.fill", label: sideB ? "LADO A" : "LADO B", latched: sideB, width: W * 0.17, height: H * 0.78) {
          Task { await ArtworkStore.shared.ensurePhoto(track.artist) }
          sideB.toggle()
        }
      }
    }
    .frame(width: W, height: H)
  }
}

/// Flip 3D verdadeiro em 180° sem espelhar o texto do verso.
private struct CassetteFlipWrapper<Front: View, Back: View>: View, Animatable {
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

// MARK: - Fita K7

struct CassetteTape: View {
  let width: CGFloat
  let title: String
  let artist: String
  let artworkURL: String
  let sideB: Bool
  let progress: Double
  let seconds: Double
  var style: CassetteStyle = .smokedStudio

  var body: some View {
    let w = width
    let h = w / 1.574
    let hubR = h * 0.085
    let fullR = h * 0.25
    let a = fullR * fullR - hubR * hubR
    let rL = sqrt(fullR * fullR - progress * a)
    let rR = sqrt(hubR * hubR + progress * a)
    let vT = 3.456 * hubR * seconds
    let thetaL = -(vT * (2 / a) * (fullR - rL)) * 180 / .pi
    let thetaR = -(vT * (2 / a) * (rR - hubR)) * 180 / .pi
    let reelDX = w * 0.17

    ZStack {
      shellView(w: w, h: h)

      // Etiqueta ou modo Cristal Transparente
      if style == .crystalClear {
        crystalWindow(w: w, h: h, hubR: hubR, rL: rL, rR: rR, reelDX: reelDX, thetaL: thetaL, thetaR: thetaR)
      } else {
        labelSticker(w: w, h: h, hubR: hubR, rL: rL, rR: rR, reelDX: reelDX, thetaL: thetaL, thetaR: thetaR)
      }

      // Cabeçote magnético dourado + pinch rollers + trapézio inferior
      TrapezoidShape()
        .fill(LinearGradient(colors: headShellColors, startPoint: .top, endPoint: .bottom))
        .overlay(TrapezoidShape().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
        .frame(width: w * 0.62, height: h * 0.17)
        .overlay {
          HStack(spacing: w * 0.042) {
            // Pinch roller esquerdo
            Circle().fill(Color(white: 0.12))
              .overlay(Circle().stroke(Color(white: 0.55), lineWidth: 1))
              .frame(width: h * 0.062)
            RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: w * 0.075, height: h * 0.06)
            // Cabeçote magnético dourado central
            RoundedRectangle(cornerRadius: 2)
              .fill(LinearGradient(colors: [Color(hex: 0xF5D06B), Color(hex: 0xB8860B)], startPoint: .top, endPoint: .bottom))
              .frame(width: w * 0.065, height: h * 0.065)
            RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: w * 0.075, height: h * 0.06)
            // Pinch roller direito
            Circle().fill(Color(white: 0.12))
              .overlay(Circle().stroke(Color(white: 0.55), lineWidth: 1))
              .frame(width: h * 0.062)
          }
          .offset(y: h * 0.02)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)

      ForEach(Array(screwPoints(w: w, h: h).enumerated()), id: \.offset) { _, p in
        Screw(size: w * 0.022).offset(x: p.x, y: p.y)
      }

      RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
        .fill(LinearGradient(colors: [.white.opacity(0.12), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        .allowsHitTesting(false)
    }
    .frame(width: w, height: h)
    .shadow(color: .black.opacity(0.55), radius: 8, y: 5)
  }

  private func shellView(w: CGFloat, h: CGFloat) -> some View {
    let colors: [Color] = {
      switch style {
      case .smokedStudio: return [Color(white: 0.20), Color(white: 0.10)]
      case .crystalClear: return [Color.white.opacity(0.22), Color.white.opacity(0.08)]
      case .metallicChrome: return [Color(white: 0.58), Color(white: 0.32)]
      case .vintageCream: return [Color(red: 0.94, green: 0.90, blue: 0.80), Color(red: 0.84, green: 0.78, blue: 0.66)]
      }
    }()
    return RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
      .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
      .overlay(
        RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
          .stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
      )
  }

  private var headShellColors: [Color] {
    switch style {
    case .vintageCream: return [Color(red: 0.84, green: 0.78, blue: 0.66), Color(red: 0.70, green: 0.64, blue: 0.52)]
    case .metallicChrome: return [Color(white: 0.42), Color(white: 0.24)]
    default: return [Color(white: 0.18), Color(white: 0.09)]
    }
  }

  private func crystalWindow(w: CGFloat, h: CGFloat, hubR: CGFloat, rL: CGFloat, rR: CGFloat, reelDX: CGFloat, thetaL: Double, thetaR: Double) -> some View {
    ZStack {
      // Fundo interno transparente com guias de fita
      RoundedRectangle(cornerRadius: w * 0.02, style: .continuous)
        .fill(Color.black.opacity(0.62))
        .overlay(
          ArtworkImage(url: artworkURL, cornerRadius: 0, maxPixel: 500)
            .opacity(0.28)
        )
      Circle().fill(TapePack.gradient).frame(width: rL * 2, height: rL * 2).offset(x: -reelDX)
      Circle().fill(TapePack.gradient).frame(width: rR * 2, height: rR * 2).offset(x: reelDX)
      Rectangle().fill(Color(red: 0.34, green: 0.20, blue: 0.12)).frame(width: reelDX * 2.2, height: 1.8).offset(y: h * 0.22)
      ReelHub(radius: hubR).rotationEffect(.degrees(thetaL)).offset(x: -reelDX)
      ReelHub(radius: hubR).rotationEffect(.degrees(thetaR)).offset(x: reelDX)
      VStack {
        HStack {
          Text(sideB ? "B" : "A").font(.system(size: w * 0.042, weight: .black)).foregroundStyle(.white)
          Text(sideB ? artist : title).font(Theme.font(w * 0.036, .bold)).foregroundStyle(.white).lineLimit(1)
          Spacer()
          Text("CRYSTAL 90").font(.system(size: w * 0.024, weight: .heavy)).foregroundStyle(Theme.peach)
        }
        .padding(.horizontal, w * 0.035)
        .padding(.top, h * 0.035)
        Spacer()
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: w * 0.02, style: .continuous))
    .frame(width: w * 0.88, height: h * 0.70)
    .offset(y: -h * 0.09)
  }

  private func labelSticker(w: CGFloat, h: CGFloat, hubR: CGFloat, rL: CGFloat, rR: CGFloat, reelDX: CGFloat, thetaL: Double, thetaR: Double) -> some View {
    ZStack {
      ArtworkImage(url: artworkURL, cornerRadius: 0, maxPixel: 700, placeholderIcon: sideB ? "person.fill" : "music.note")
      LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
      VStack(spacing: 0) {
        HStack(spacing: w * 0.02) {
          Text(sideB ? "B" : "A")
            .font(.system(size: w * 0.05, weight: .black, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(width: w * 0.07, height: w * 0.065)
            .background(RoundedRectangle(cornerRadius: w * 0.01).fill(Color.white.opacity(0.9)))
          Text(sideB ? artist : title)
            .font(.custom("Noteworthy-Bold", size: w * 0.052))
            .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.32))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
          Spacer(minLength: 0)
          Text("90")
            .font(.system(size: w * 0.038, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.55))
        }
        .padding(.horizontal, w * 0.025)
        .frame(height: h * 0.17)
        .background(Color(red: 0.97, green: 0.96, blue: 0.92).opacity(0.94))

        Spacer(minLength: 0)

        VStack(spacing: 0) {
          ForEach(0..<4, id: \.self) { i in Theme.prismColors[i].frame(height: h * 0.022) }
        }
        .opacity(0.95)
        HStack {
          Text(sideB ? title : artist)
            .font(.custom("Noteworthy-Bold", size: w * 0.036))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 2)
            .lineLimit(1)
          Spacer()
          Text(style == .metallicChrome ? "CHROME · TYPE II" : "LUME · HIGH BIAS")
            .font(.system(size: w * 0.022, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.6), radius: 2)
        }
        .padding(.horizontal, w * 0.03)
        .frame(height: h * 0.11)
        .background(Color.black.opacity(0.35))
      }

      // Janela dos carretéis
      ZStack {
        RoundedRectangle(cornerRadius: h * 0.11, style: .continuous)
          .fill(Color(white: 0.04).opacity(0.92))
        Circle().fill(TapePack.gradient).frame(width: rL * 2, height: rL * 2).offset(x: -reelDX)
        Circle().fill(TapePack.gradient).frame(width: rR * 2, height: rR * 2).offset(x: reelDX)
        Rectangle().fill(Color(red: 0.28, green: 0.17, blue: 0.10)).frame(width: reelDX * 2, height: 1.4).offset(y: h * 0.13)
        ReelHub(radius: hubR).rotationEffect(.degrees(thetaL)).offset(x: -reelDX)
        ReelHub(radius: hubR).rotationEffect(.degrees(thetaR)).offset(x: reelDX)
        HStack(spacing: w * 0.018) {
          ForEach(0..<5, id: \.self) { _ in Rectangle().fill(Color.white.opacity(0.35)).frame(width: 0.8, height: h * 0.03) }
        }
        .offset(y: -h * 0.12)
        RoundedRectangle(cornerRadius: h * 0.11, style: .continuous)
          .fill(LinearGradient(colors: [.white.opacity(0.22), .clear, .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
        RoundedRectangle(cornerRadius: h * 0.11, style: .continuous)
          .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
      }
      .frame(width: w * 0.56, height: h * 0.27)
      .clipped()
      .offset(y: -h * 0.015)
    }
    .clipShape(RoundedRectangle(cornerRadius: w * 0.02, style: .continuous))
    .frame(width: w * 0.88, height: h * 0.70)
    .offset(y: -h * 0.09)
  }

  private func screwPoints(w: CGFloat, h: CGFloat) -> [CGPoint] {
    [CGPoint(x: -w * 0.465, y: -h * 0.44), CGPoint(x: w * 0.465, y: -h * 0.44),
     CGPoint(x: -w * 0.465, y: h * 0.44), CGPoint(x: w * 0.465, y: h * 0.44),
     CGPoint(x: 0, y: h * 0.33)]
  }
}

private enum TapePack {
  static let gradient = RadialGradient(
    colors: [Color(red: 0.30, green: 0.19, blue: 0.11), Color(red: 0.20, green: 0.12, blue: 0.07), Color(red: 0.26, green: 0.16, blue: 0.09)],
    center: .center, startRadius: 0, endRadius: 60
  )
}

struct ReelHub: View {
  let radius: CGFloat
  var body: some View {
    ZStack {
      Circle().fill(Color(white: 0.94)).frame(width: radius * 2, height: radius * 2)
        .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.6))
      Circle().fill(Color(white: 0.12)).frame(width: radius * 1.1, height: radius * 1.1)
      ForEach(0..<6, id: \.self) { i in
        RoundedRectangle(cornerRadius: 1)
          .fill(Color(white: 0.94))
          .frame(width: radius * 0.22, height: radius * 0.3)
          .offset(y: -radius * 0.48)
          .rotationEffect(.degrees(Double(i) * 60))
      }
      Circle().fill(Color(white: 0.12)).frame(width: radius * 0.42, height: radius * 0.42)
    }
  }
}

struct Screw: View {
  let size: CGFloat
  var body: some View {
    ZStack {
      Circle().fill(RadialGradient(colors: [Color(white: 0.85), Color(white: 0.4)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
      Rectangle().fill(Color.black.opacity(0.5)).frame(width: size * 0.7, height: size * 0.12).rotationEffect(.degrees(35))
    }
    .frame(width: size, height: size)
  }
}

struct TrapezoidShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    let inset = r.width * 0.1
    p.move(to: CGPoint(x: r.minX + inset, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
    p.closeSubpath()
    return p
  }
}

// MARK: - Painel metálico GPU

struct BrushedPanel: View, Equatable {
  let cornerRadius: CGFloat
  let dark: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    Image(uiImage: LumeTextures.shared.brushedSurface(styleId: dark ? 1 : 0))
      .resizable()
      .scaledToFill()
      .clipShape(shape)
      .overlay(
        shape.stroke(LinearGradient(colors: [.white.opacity(dark ? 0.3 : 0.95), .black.opacity(0.28)], startPoint: .zero, endPoint: .bottomTrailing), lineWidth: 1.2)
      )
      .drawingGroup()
  }
}

// MARK: - VU meter

struct VUMeter: View {
  let level: Double
  let label: String

  var body: some View {
    GeometryReader { g in
      let w = g.size.width, h = g.size.height
      let isPeak = level > 0.84
      ZStack {
        RoundedRectangle(cornerRadius: h * 0.12, style: .continuous)
          .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.78), Color(red: 0.98, green: 0.82, blue: 0.58)], startPoint: .top, endPoint: .bottom))
          .overlay(
            RoundedRectangle(cornerRadius: h * 0.12, style: .continuous)
              .fill(RadialGradient(colors: [.white.opacity(0.6), .clear], center: UnitPoint(x: 0.5, y: 1.1), startRadius: 0, endRadius: w * 0.75))
          )
        Canvas { ctx, sz in
          let pivot = CGPoint(x: sz.width / 2, y: sz.height * 1.02)
          let radius = sz.height * 0.82
          for k in 0...10 {
            let f = Double(k) / 10
            let ang = (-50 + 100 * f) * .pi / 180
            let inner = radius * (k % 2 == 0 ? 0.84 : 0.89)
            let p1 = CGPoint(x: pivot.x + inner * CGFloat(sin(ang)), y: pivot.y - inner * CGFloat(cos(ang)))
            let p2 = CGPoint(x: pivot.x + radius * CGFloat(sin(ang)), y: pivot.y - radius * CGFloat(cos(ang)))
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            ctx.stroke(path, with: .color(f > 0.72 ? Color(red: 0.85, green: 0.12, blue: 0.1) : Color.black.opacity(0.75)), lineWidth: k % 2 == 0 ? 1.2 : 0.7)
          }
          var arc = Path()
          arc.addArc(center: pivot, radius: radius, startAngle: .degrees(-140), endAngle: .degrees(-40), clockwise: false)
          ctx.stroke(arc, with: .color(.black.opacity(0.6)), lineWidth: 0.8)
          var red = Path()
          red.addArc(center: pivot, radius: radius * 0.98, startAngle: .degrees(-58), endAngle: .degrees(-40), clockwise: false)
          ctx.stroke(red, with: .color(Color(red: 0.85, green: 0.12, blue: 0.1)), lineWidth: 2.5)
        }
        Text("VU")
          .font(.system(size: h * 0.17, weight: .heavy, design: .serif))
          .foregroundStyle(.black.opacity(0.7))
          .offset(y: h * 0.12)
        Text(label)
          .font(.system(size: h * 0.12, weight: .bold, design: .rounded))
          .foregroundStyle(.black.opacity(0.5))
          .position(x: w * 0.12, y: h * 0.82)

        // LED PEAK vermelho
        Circle()
          .fill(isPeak ? Color.red : Color.red.opacity(0.18))
          .frame(width: h * 0.10, height: h * 0.10)
          .shadow(color: isPeak ? .red : .clear, radius: 4)
          .position(x: w * 0.88, y: h * 0.82)

        // Agulha direta (já suavizada por VUBallistics)
        Capsule()
          .fill(Color.black.opacity(0.85))
          .frame(width: 1.5, height: h * 0.86)
          .offset(y: -h * 0.43)
          .rotationEffect(.degrees(-48 + 96 * min(1, max(0, level))), anchor: .center)
          .position(x: w / 2, y: h * 1.02)
        Circle().fill(Color.black.opacity(0.8)).frame(width: h * 0.1).position(x: w / 2, y: h * 0.98)

        RoundedRectangle(cornerRadius: h * 0.12, style: .continuous)
          .fill(LinearGradient(colors: [.white.opacity(0.35), .clear, .clear], startPoint: .top, endPoint: .bottom))
        RoundedRectangle(cornerRadius: h * 0.12, style: .continuous)
          .stroke(Color.black.opacity(0.5), lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: h * 0.12, style: .continuous))
      .shadow(color: Color(red: 1, green: 0.75, blue: 0.4).opacity(0.35), radius: 6)
    }
  }
}

struct TapeCounter: View {
  let value: Int
  let digitWidth: CGFloat
  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(String(format: "%03d", value).enumerated()), id: \.offset) { _, ch in
        Text(String(ch))
          .font(.system(size: digitWidth * 1.15, weight: .semibold, design: .monospaced))
          .foregroundStyle(.white)
          .contentTransition(.numericText(countsDown: false))
          .frame(width: digitWidth, height: digitWidth * 1.5)
          .background(
            RoundedRectangle(cornerRadius: 3)
              .fill(LinearGradient(colors: [Color(white: 0.02), Color(white: 0.2), Color(white: 0.02)], startPoint: .top, endPoint: .bottom))
          )
      }
    }
    .padding(3)
    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black))
    .animation(.snappy, value: value)
  }
}

struct PianoKey: View {
  let icon: String
  let label: String
  let latched: Bool
  let width: CGFloat
  let height: CGFloat
  let action: () -> Void
  @State private var pressed = false

  var body: some View {
    let down = pressed || latched
    VStack(spacing: height * 0.06) {
      Image(systemName: icon)
        .font(.system(size: height * 0.26, weight: .bold))
      Text(label)
        .font(.system(size: height * 0.14, weight: .heavy, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .foregroundStyle(Color.black.opacity(down ? 0.55 : 0.7))
    .frame(width: width, height: height)
    .background {
      RoundedRectangle(cornerRadius: height * 0.12, style: .continuous)
        .fill(LinearGradient(colors: down ? [Color(white: 0.70), Color(white: 0.82)] : [Color(white: 0.96), Color(white: 0.74)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) {
          VStack(spacing: 1.5) {
            ForEach(0..<3, id: \.self) { _ in Rectangle().fill(Color.black.opacity(0.12)).frame(height: 0.7) }
          }
          .padding(.horizontal, width * 0.15)
          .padding(.bottom, height * 0.08)
        }
        .overlay(
          RoundedRectangle(cornerRadius: height * 0.12, style: .continuous)
            .stroke(LinearGradient(colors: [.white, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        )
    }
    .overlay(alignment: .top) {
      if latched {
        Capsule().fill(Theme.mint).frame(width: width * 0.25, height: 2.5).shadow(color: Theme.mint, radius: 3).padding(.top, 3)
      }
    }
    .shadow(color: .black.opacity(down ? 0.2 : 0.5), radius: down ? 1 : 3, y: down ? 1 : 3.5)
    .offset(y: down ? 2 : 0)
    .scaleEffect(y: down ? 0.97 : 1, anchor: .bottom)
    .animation(.spring(response: 0.18, dampingFraction: 0.6), value: down)
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in if !pressed { pressed = true; Haptics.rigid() } }
        .onEnded { _ in pressed = false; action() }
    )
    .accessibilityElement()
    .accessibilityLabel(label)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { action() }
  }
}
