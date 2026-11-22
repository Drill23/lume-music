import SwiftUI

/// Realistic cassette deck (inspired by the brushed-metal tape mockup):
/// smoked-glass door, cassette whose label is the album cover (side B shows the artist photo),
/// physically-correct reels (supply slows, take-up speeds… by tape-pack radius), analog VU meters
/// driven by the real audio spectrum, rolling tape counter and latching piano keys.
struct CassetteStage: View {
  let track: Track
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var spectrum = AudioSpectrum.shared
  @ObservedObject private var art = ArtworkStore.shared
  @State private var sideB = false
  @State private var anchorTime: Double = 0
  @State private var anchorDate = Date()

  var body: some View {
    GeometryReader { g in
      let W = min(g.size.width - 40, 390, (g.size.height - 20) / 1.17)
      VStack(spacing: W * 0.035) {
        deckWindow(W)
        meters(W)
        keys(W)
      }
      .frame(width: W)
      .position(x: g.size.width / 2, y: g.size.height / 2)
    }
    .onAppear { anchor() }
    .onChange(of: player.currentTime) { _, _ in anchor() }
    .onChange(of: player.isPlaying) { _, _ in anchor() }
    .onChange(of: track.id) { _, _ in sideB = false }
  }

  private func anchor() {
    anchorTime = player.currentTime
    anchorDate = Date()
  }

  // MARK: Window + cassette

  private func deckWindow(_ W: CGFloat) -> some View {
    let H = W * 0.70
    return ZStack {
      BrushedPanel(cornerRadius: W * 0.07, dark: false).equatable()
      // Recess
      RoundedRectangle(cornerRadius: W * 0.045, style: .continuous)
        .fill(Color.black.opacity(0.85))
        .padding(W * 0.045)
        .shadow(color: .white.opacity(0.7), radius: 0, x: 0.8, y: 1)
      TimelineView(.animation(paused: !player.isPlaying)) { tl in
        let t = player.isPlaying ? anchorTime + tl.date.timeIntervalSince(anchorDate) : anchorTime
        let p = player.duration > 1 ? min(1, max(0, t / player.duration)) : 0
        CassetteTape(
          width: W * 0.80,
          title: track.title,
          artist: track.artist,
          artworkURL: sideB ? (art.photo(for: track.artist) ?? player.currentArtwork) : player.currentArtwork,
          sideB: sideB,
          progress: p,
          seconds: max(1, player.duration)
        )
      }
      .rotation3DEffect(.degrees(sideB ? 180 : 0), axis: (0, 1, 0), perspective: 0.5)
      .scaleEffect(x: sideB ? -1 : 1)
      .animation(.spring(response: 0.7, dampingFraction: 0.8), value: sideB)
      // Smoked glass door with reflections
      RoundedRectangle(cornerRadius: W * 0.045, style: .continuous)
        .fill(
          LinearGradient(
            stops: [
              .init(color: .white.opacity(0.16), location: 0),
              .init(color: .white.opacity(0.03), location: 0.35),
              .init(color: .clear, location: 0.55),
              .init(color: .white.opacity(0.07), location: 0.8),
              .init(color: .clear, location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
          )
        )
        .overlay(RoundedRectangle(cornerRadius: W * 0.045, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
        .padding(W * 0.045)
        .allowsHitTesting(false)
      // Door brand
      Text("LUME · STEREO CASSETTE DECK")
        .font(.system(size: W * 0.022, weight: .heavy, design: .rounded))
        .tracking(1.2)
        .foregroundStyle(Color.black.opacity(0.42))
        .shadow(color: .white.opacity(0.7), radius: 0, x: 0.5, y: 0.6)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, W * 0.012)
    }
    .frame(width: W, height: H)
    .shadow(color: .black.opacity(0.35), radius: W * 0.04, y: W * 0.025)
    .onTapGesture { Haptics.medium(); player.togglePlayPause() }
  }

  // MARK: VU meters + counter

  private func meters(_ W: CGFloat) -> some View {
    let H = W * 0.22
    return ZStack {
      BrushedPanel(cornerRadius: W * 0.05, dark: true).equatable()
      HStack(spacing: W * 0.03) {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !player.isPlaying && !spectrum.isLive)) { tl in
          let lv = levels(at: tl.date)
          HStack(spacing: W * 0.025) {
            VUMeter(level: lv.0, label: "L").frame(width: W * 0.33, height: H * 0.74)
            VUMeter(level: lv.1, label: "R").frame(width: W * 0.33, height: H * 0.74)
          }
        }
        VStack(spacing: W * 0.012) {
          TapeCounter(value: Int(player.currentTime) % 1000, digitWidth: W * 0.05)
          Text("COUNTER")
            .font(.system(size: W * 0.02, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.45))
        }
      }
    }
    .frame(width: W, height: H)
  }

  private func levels(at date: Date) -> (Double, Double) {
    if spectrum.isLive {
      let b = spectrum.bands
      let half = max(1, b.count / 2)
      let low = b.prefix(half).reduce(0, +) / Float(half)
      let high = b.suffix(half).reduce(0, +) / Float(half)
      let l = 0.06 + Double(spectrum.level) * 0.55 + Double(low) * 0.16
      let r = 0.06 + Double(spectrum.level) * 0.55 + Double(high) * 0.22
      return (min(1, l), min(1, r))
    }
    guard player.isPlaying else { return (0, 0) }
    let t = date.timeIntervalSinceReferenceDate
    let base = 0.55 + 0.18 * sin(t * 2.3) * cos(t * 0.7)
    let l = base + 0.14 * sin(t * 9.1) + 0.08 * sin(t * 17.3)
    let r = base + 0.14 * sin(t * 8.3 + 1) + 0.08 * cos(t * 15.1)
    return (min(1, max(0, l)), min(1, max(0, r)))
  }

  // MARK: Piano keys

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

// MARK: - Cassette

struct CassetteTape: View {
  let width: CGFloat
  let title: String
  let artist: String
  let artworkURL: String
  let sideB: Bool
  let progress: Double
  let seconds: Double

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
      // Shell (smoked translucent)
      RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
        .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))
        .overlay(
          RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
            .stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )

      // Label sticker with album art
      ZStack {
        ArtworkImage(url: artworkURL, cornerRadius: 0, maxPixel: 700, placeholderIcon: sideB ? "person.fill" : "music.note")
        LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)
        VStack(spacing: 0) {
          // Handwritten band
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

          // Prism stripe
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
            Text("LUME · HIGH BIAS")
              .font(.system(size: w * 0.022, weight: .heavy, design: .rounded))
              .foregroundStyle(.white.opacity(0.85))
              .shadow(color: .black.opacity(0.6), radius: 2)
          }
          .padding(.horizontal, w * 0.03)
          .frame(height: h * 0.11)
          .background(Color.black.opacity(0.35))
        }

        // Window cut-out with reels
        ZStack {
          RoundedRectangle(cornerRadius: h * 0.11, style: .continuous)
            .fill(Color(white: 0.04).opacity(0.92))
          // Tape packs
          Circle().fill(TapePack.gradient).frame(width: rL * 2, height: rL * 2).offset(x: -reelDX)
          Circle().fill(TapePack.gradient).frame(width: rR * 2, height: rR * 2).offset(x: reelDX)
          // Tape path along the bottom
          Rectangle().fill(Color(red: 0.28, green: 0.17, blue: 0.10)).frame(width: reelDX * 2, height: 1.4).offset(y: h * 0.13)
          ReelHub(radius: hubR).rotationEffect(.degrees(thetaL)).offset(x: -reelDX)
          ReelHub(radius: hubR).rotationEffect(.degrees(thetaR)).offset(x: reelDX)
          // Window scale marks
          HStack(spacing: w * 0.018) {
            ForEach(0..<5, id: \.self) { _ in Rectangle().fill(Color.white.opacity(0.35)).frame(width: 0.8, height: h * 0.03) }
          }
          .offset(y: -h * 0.12)
          // Acrylic reflection
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

      // Bottom head area (trapezoid)
      TrapezoidShape()
        .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
        .overlay(TrapezoidShape().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
        .frame(width: w * 0.62, height: h * 0.17)
        .overlay {
          HStack(spacing: w * 0.05) {
            Circle().fill(Color.black).frame(width: h * 0.05)
            RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: w * 0.09, height: h * 0.06)
            RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: w * 0.06, height: h * 0.06)
            RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: w * 0.09, height: h * 0.06)
            Circle().fill(Color.black).frame(width: h * 0.05)
          }
          .offset(y: h * 0.02)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)

      // Screws
      ForEach(Array(screwPoints(w: w, h: h).enumerated()), id: \.offset) { _, p in
        Screw(size: w * 0.022).offset(x: p.x, y: p.y)
      }

      // Shell gloss
      RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
        .fill(LinearGradient(colors: [.white.opacity(0.10), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
        .allowsHitTesting(false)
    }
    .frame(width: w, height: h)
    .shadow(color: .black.opacity(0.55), radius: 8, y: 5)
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

// MARK: - Brushed metal panel

struct BrushedPanel: View, Equatable {
  let cornerRadius: CGFloat
  let dark: Bool

  var body: some View {
    Canvas { ctx, sz in
      let shape = Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: cornerRadius, style: .continuous)
      let colors = dark
        ? [Color(hex: 0x3A3D43), Color(hex: 0x24262B), Color(hex: 0x1A1B1F)]
        : [Color(hex: 0xEEF0F2), Color(hex: 0xC9CDD3), Color(hex: 0xA8ADB5)]
      ctx.fill(shape, with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)))
      var c = ctx
      c.clip(to: shape)
      var y: CGFloat = 0
      var i = 0
      while y < sz.height {
        let h = abs(sin(Double(i) * 78.233) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let alpha = (dark ? 0.03 : 0.02) + 0.05 * h
        let col = i % 3 == 0 ? Color.black.opacity(alpha) : Color.white.opacity(alpha * (dark ? 0.6 : 1.2))
        c.fill(Path(CGRect(x: 0, y: y, width: sz.width, height: 0.55)), with: .color(col))
        y += 1.1
        i += 1
      }
      c.fill(shape, with: .linearGradient(
        Gradient(stops: [.init(color: .white.opacity(0), location: 0.2), .init(color: .white.opacity(dark ? 0.10 : 0.32), location: 0.42), .init(color: .white.opacity(0), location: 0.6)]),
        startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)))
      ctx.stroke(shape, with: .linearGradient(Gradient(colors: [.white.opacity(dark ? 0.3 : 0.95), .black.opacity(0.25)]), startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)), lineWidth: 1.2)
    }
  }
}

// MARK: - VU meter

struct VUMeter: View {
  let level: Double
  let label: String

  var body: some View {
    GeometryReader { g in
      let w = g.size.width, h = g.size.height
      ZStack {
        RoundedRectangle(cornerRadius: h * 0.12, style: .continuous)
          .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.78), Color(red: 0.98, green: 0.82, blue: 0.58)], startPoint: .top, endPoint: .bottom))
          .overlay(
            RoundedRectangle(cornerRadius: h * 0.12, style: .continuous)
              .fill(RadialGradient(colors: [.white.opacity(0.55), .clear], center: UnitPoint(x: 0.5, y: 1.1), startRadius: 0, endRadius: w * 0.7))
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
        // Needle
        Capsule()
          .fill(Color.black.opacity(0.85))
          .frame(width: 1.4, height: h * 0.86)
          .offset(y: -h * 0.43)
          .rotationEffect(.degrees(-48 + 96 * min(1, max(0, level))), anchor: .center)
          .position(x: w / 2, y: h * 1.02)
          .animation(.interpolatingSpring(stiffness: 180, damping: 16), value: level)
        Circle().fill(Color.black.opacity(0.8)).frame(width: h * 0.1).position(x: w / 2, y: h * 0.98)
        // Glass
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
