import SwiftUI

/// Realistic top-down direct-drive turntable (inspired by the silver deck mockup):
/// brushed aluminum plinth, strobe-dotted platter, grooved record with a *stationary* sheen
/// (like real light on vinyl), album art label, articulated tonearm that tracks the song,
/// START·STOP button, 33/45 selector, varispeed pitch fader, and "scratch to seek".
struct TurntableStage: View {
  let track: Track
  @ObservedObject private var player = AudioPlayer.shared

  var body: some View {
    GeometryReader { g in
      let side = min(g.size.width - 28, g.size.height - 12, 410)
      TurntableDeck(
        side: side,
        artworkURL: player.currentArtwork,
        isPlaying: player.isPlaying,
        progress: player.duration > 0 ? player.currentTime / player.duration : 0
      )
      .frame(width: side, height: side)
      .position(x: g.size.width / 2, y: g.size.height / 2)
    }
  }
}

struct TurntableDeck: View {
  let side: CGFloat
  let artworkURL: String
  let isPlaying: Bool
  let progress: Double

  @ObservedObject private var player = AudioPlayer.shared
  @State private var spin = SpinModel()
  @State private var idleTick = false
  @State private var rpm45 = false
  @State private var scratchDelta: Double = 0      // degrees while scratching
  @State private var scratchLastAngle: Double?
  @State private var scratching = false
  @State private var startPressed = false
  @State private var pitch: Double = 0             // -1...1  (±8 %)

  private var S: CGFloat { side }
  private var center: CGPoint { CGPoint(x: S * 0.43, y: S * 0.50) }
  private var recordR: CGFloat { S * 0.385 }
  private var pivot: CGPoint { CGPoint(x: S * 0.845, y: S * 0.185) }
  private var armLen: CGFloat { S * 0.60 }
  private var degPerSec: Double { (rpm45 ? 45 : 33.333) * 6 * (1 + pitch * 0.08) }

  var body: some View {
    ZStack {
      PlinthView(side: S).equatable()

      // Engraved brand + speed selector (top-left)
      HStack(spacing: S * 0.018) {
        speedKey("33", active: !rpm45) { rpm45 = false }
        speedKey("45", active: rpm45) { rpm45 = true }
      }
      .position(x: S * 0.135, y: S * 0.075)

      Text("LUME  DD-1")
        .font(.system(size: S * 0.026, weight: .heavy, design: .rounded))
        .tracking(S * 0.004)
        .foregroundStyle(Color.black.opacity(0.38))
        .shadow(color: .white.opacity(0.8), radius: 0, x: 0.6, y: 0.8)
        .position(x: S * 0.135, y: S * 0.135)

      // Platter well + strobe light
      Circle()
        .fill(Color.black.opacity(0.45))
        .frame(width: S * 0.83, height: S * 0.83)
        .blur(radius: S * 0.012)
        .position(x: center.x + S * 0.008, y: center.y + S * 0.012)
      strobeLight

      // Spinning platter + record
      TimelineView(.animation(paused: !isPlaying && !scratching && !spin.isMoving)) { tl in
        let angle = spin.step(now: tl.date.timeIntervalSinceReferenceDate, target: (isPlaying && !scratching) ? degPerSec : 0)
        ZStack {
          RecordDisc(side: S, artworkURL: artworkURL).equatable()
            .rotationEffect(.degrees(angle))
          RecordSheen(radius: recordR)
            .allowsHitTesting(false)
        }
      }
      .frame(width: S * 0.83, height: S * 0.83)
      .position(center)
      .contentShape(Circle().inset(by: 0))
      .gesture(scratchGesture)
      .onTapGesture { Haptics.medium(); player.togglePlayPause() }

      // Arm rest post
      ArmRest(side: S)
        .position(x: pivot.x - armLen * 0.73 * sin(2 * .pi / 180), y: pivot.y + armLen * 0.73 * cos(2 * .pi / 180))

      // Tonearm (animatable)
      TonearmView(side: S, pivot: pivot, length: armLen, angle: armAngle, lift: isPlaying ? 0 : 1)
        .allowsHitTesting(false)
        .animation(.spring(response: 1.15, dampingFraction: 0.9), value: isPlaying)
        .animation(.linear(duration: 0.5), value: armAngle)

      startStopButton
        .position(x: S * 0.125, y: S * 0.905)

      PitchFader(side: S, value: $pitch) { newValue in
        player.setVarispeed(Float(1 + newValue * 0.08))
      }
      .frame(width: S * 0.05, height: S * 0.30)
      .position(x: S * 0.935, y: S * 0.77)

      if scratching {
        let secs = scratchDelta / degPerSec
        Text((secs >= 0 ? "+" : "−") + String(format: "%.1fs", abs(secs)) + "  ·  " + Theme.formatTime(max(0, player.currentTime + secs)))
          .font(Theme.font(13, .semibold))
          .monospacedDigit()
          .foregroundStyle(Theme.text)
          .padding(.horizontal, 14)
          .frame(height: 34)
          .glassCapsule()
          .position(x: center.x, y: S * 0.04)
          .transition(.opacity)
      }
    }
    .frame(width: S, height: S)
    .shadow(color: .black.opacity(0.35), radius: S * 0.05, y: S * 0.035)
    .onChange(of: isPlaying) { _, now in
      if !now {
        // Let the platter coast to a stop, then let the timeline pause.
        Task {
          try? await Task.sleep(for: .seconds(5))
          idleTick.toggle()
        }
      }
    }
    .overlay { if idleTick { EmptyView() } }
  }

  // Arm angle: parked at 2°, otherwise tracks from outer groove to the run-out as the song plays.
  private var armAngle: Double {
    guard isPlaying || progress > 0.001 else { return 2 }
    if !isPlaying { return 2 }
    let p = min(1, max(0, progress))
    let r = recordR * (0.95 - 0.56 * p)
    return Self.angle(forRadius: r, pivot: pivot, center: center, length: armLen)
  }

  static func angle(forRadius r: CGFloat, pivot: CGPoint, center: CGPoint, length: CGFloat) -> Double {
    var best = 0.0, bestErr = CGFloat.greatestFiniteMagnitude
    var a = 0.0
    while a <= 70 {
      let rad = a * .pi / 180
      let tip = CGPoint(x: pivot.x - length * CGFloat(sin(rad)), y: pivot.y + length * CGFloat(cos(rad)))
      let d = hypot(tip.x - center.x, tip.y - center.y)
      let err = abs(d - r)
      if err < bestErr { bestErr = err; best = a }
      a += 0.1
    }
    return best
  }

  private var scratchGesture: some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { v in
        let local = CGPoint(x: v.location.x - S * 0.415, y: v.location.y - S * 0.415)
        let ang = atan2(Double(local.y), Double(local.x)) * 180 / .pi
        if let last = scratchLastAngle {
          var d = ang - last
          if d > 180 { d -= 360 }
          if d < -180 { d += 360 }
          let before = Int(scratchDelta / 20)
          scratchDelta += d
          spin.angle += d
          if Int(scratchDelta / 20) != before { Haptics.soft() }
        } else {
          withAnimation(.easeOut(duration: 0.15)) { scratching = true }
        }
        scratchLastAngle = ang
      }
      .onEnded { _ in
        let secs = scratchDelta / degPerSec
        if abs(secs) > 0.2 { player.seek(to: max(0, player.currentTime + secs)) }
        scratchDelta = 0
        scratchLastAngle = nil
        withAnimation(.easeOut(duration: 0.25)) { scratching = false }
      }
  }

  private func speedKey(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
    Button {
      Haptics.rigid()
      withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { action() }
    } label: {
      Text(label)
        .font(.system(size: S * 0.026, weight: .bold, design: .rounded))
        .foregroundStyle(active ? Color.white : Color.white.opacity(0.55))
        .frame(width: S * 0.085, height: S * 0.05)
        .background(
          RoundedRectangle(cornerRadius: S * 0.012, style: .continuous)
            .fill(LinearGradient(colors: active ? [Color(white: 0.16), Color(white: 0.06)] : [Color(white: 0.28), Color(white: 0.14)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(alignment: .top) {
          Capsule().fill(active ? Theme.rose : Color.white.opacity(0.15))
            .frame(width: S * 0.03, height: S * 0.005)
            .shadow(color: active ? Theme.rose : .clear, radius: 3)
            .padding(.top, S * 0.006)
        }
        .shadow(color: .black.opacity(active ? 0.15 : 0.35), radius: active ? 1 : 2.5, y: active ? 0.5 : 2)
        .scaleEffect(active ? 0.96 : 1)
    }
    .buttonStyle(.plain)
  }

  private var startStopButton: some View {
    Button {
      Haptics.rigid()
      player.togglePlayPause()
    } label: {
      VStack(spacing: S * 0.006) {
        Text("START · STOP")
          .font(.system(size: S * 0.021, weight: .heavy, design: .rounded))
          .tracking(0.5)
          .foregroundStyle(.white.opacity(0.85))
        Circle()
          .fill(isPlaying ? Theme.mint : Color.white.opacity(0.18))
          .frame(width: S * 0.012, height: S * 0.012)
          .shadow(color: isPlaying ? Theme.mint : .clear, radius: 4)
      }
      .frame(width: S * 0.19, height: S * 0.085)
      .background(
        RoundedRectangle(cornerRadius: S * 0.016, style: .continuous)
          .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
      )
      .overlay(
        RoundedRectangle(cornerRadius: S * 0.016, style: .continuous)
          .stroke(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
      )
      .shadow(color: .black.opacity(0.4), radius: startPressed ? 1 : 3, y: startPressed ? 0.5 : 2.5)
      .scaleEffect(startPressed ? 0.95 : 1)
    }
    .buttonStyle(.plain)
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in if !startPressed { withAnimation(.easeOut(duration: 0.08)) { startPressed = true } } }
        .onEnded { _ in withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { startPressed = false } }
    )
  }

  private var strobeLight: some View {
    ZStack {
      Circle()
        .fill(RadialGradient(colors: [Color(white: 0.35), Color(white: 0.12)], center: .topLeading, startRadius: 0, endRadius: S * 0.03))
        .frame(width: S * 0.05, height: S * 0.05)
        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.6))
      Circle()
        .fill(isPlaying ? Theme.peach : Color(white: 0.3))
        .frame(width: S * 0.018, height: S * 0.018)
        .shadow(color: isPlaying ? Theme.peach : .clear, radius: 6)
    }
    .overlay {
      if isPlaying {
        Circle()
          .fill(RadialGradient(colors: [Theme.peach.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: S * 0.09))
          .frame(width: S * 0.18, height: S * 0.18)
          .offset(x: S * 0.05, y: -S * 0.03)
          .blendMode(.plusLighter)
          .allowsHitTesting(false)
      }
    }
    .position(x: S * 0.07, y: S * 0.79)
    .animation(.easeInOut(duration: 0.4), value: isPlaying)
  }
}

/// Platter physics integrated frame by frame (reference type, mutated while drawing — no SwiftUI state churn):
/// the motor spins up in ~0.5 s, coasts down in ~1 s, and a finger on the record brakes it like real vinyl.
final class SpinModel {
  var angle: Double = 0
  private(set) var velocity: Double = 0
  private var last: Double = 0

  var isMoving: Bool { abs(velocity) > 0.5 }

  func step(now: Double, target: Double) -> Double {
    let dt = last == 0 ? 0 : min(0.1, max(0, now - last))
    last = now
    let tau = target > velocity ? 0.45 : (target == 0 ? 0.85 : 0.3)
    velocity += (target - velocity) * (1 - exp(-dt / tau))
    angle += velocity * dt
    if angle > 360_000 { angle = angle.truncatingRemainder(dividingBy: 360) }
    return angle
  }
}

// MARK: - Plinth (brushed aluminum)

struct PlinthView: View, Equatable {
  let side: CGFloat

  var body: some View {
    Canvas { ctx, sz in
      let rect = CGRect(origin: .zero, size: sz)
      let corner = side * 0.075
      let shape = Path(roundedRect: rect, cornerRadius: corner, style: .continuous)

      ctx.fill(shape, with: .linearGradient(
        Gradient(colors: [Color(hex: 0xF4F5F7), Color(hex: 0xD9DCE1), Color(hex: 0xBFC4CB), Color(hex: 0xAEB3BB)]),
        startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)))

      var c = ctx
      c.clip(to: shape)
      // Brushed grain
      let step: CGFloat = 1.1
      var i = 0
      var y: CGFloat = 0
      while y < sz.height {
        let h = abs(sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let alpha = 0.015 + 0.055 * h
        let col = i % 3 == 0 ? Color.black.opacity(alpha * 0.9) : Color.white.opacity(alpha * 1.2)
        c.fill(Path(CGRect(x: 0, y: y, width: sz.width, height: 0.55)), with: .color(col))
        y += step
        i += 1
      }
      // Soft anisotropic sheen bands
      c.fill(shape, with: .linearGradient(
        Gradient(stops: [
          .init(color: .white.opacity(0), location: 0.18),
          .init(color: .white.opacity(0.38), location: 0.36),
          .init(color: .white.opacity(0), location: 0.52),
          .init(color: .white.opacity(0.18), location: 0.74),
          .init(color: .white.opacity(0), location: 0.9),
        ]),
        startPoint: CGPoint(x: 0, y: sz.height * 0.1), endPoint: CGPoint(x: sz.width, y: sz.height * 0.9)))

      // Chamfered edge: bright top-left, dark bottom-right
      ctx.stroke(shape, with: .linearGradient(
        Gradient(colors: [.white, .white.opacity(0.4), .black.opacity(0.25)]),
        startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)), lineWidth: 1.6)
      let inner = Path(roundedRect: rect.insetBy(dx: side * 0.012, dy: side * 0.012), cornerRadius: corner * 0.85, style: .continuous)
      ctx.stroke(inner, with: .linearGradient(
        Gradient(colors: [.black.opacity(0.12), .white.opacity(0.5)]),
        startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)), lineWidth: 0.8)

      // Feet hint at corners (screws)
      for p in [CGPoint(x: side * 0.045, y: side * 0.045), CGPoint(x: side * 0.955, y: side * 0.045),
                CGPoint(x: side * 0.045, y: side * 0.955), CGPoint(x: side * 0.955, y: side * 0.955)] {
        let r = side * 0.009
        let screw = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.fill(screw, with: .radialGradient(Gradient(colors: [Color(white: 0.92), Color(white: 0.55)]), center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.4))
        var slot = Path()
        slot.move(to: CGPoint(x: p.x - r * 0.7, y: p.y + r * 0.2))
        slot.addLine(to: CGPoint(x: p.x + r * 0.7, y: p.y - r * 0.2))
        ctx.stroke(slot, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
      }
    }
    .frame(width: side, height: side)
  }
}

// MARK: - Record

struct RecordDisc: View, Equatable {
  let side: CGFloat
  let artworkURL: String

  var body: some View {
    let platterD = side * 0.81
    let R = side * 0.385
    ZStack {
      // Platter (metal rim + strobe dots)
      Canvas { ctx, sz in
        let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
        let pr = platterD / 2
        let rim = Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2))
        ctx.fill(rim, with: .linearGradient(Gradient(colors: [Color(white: 0.86), Color(white: 0.42), Color(white: 0.78), Color(white: 0.35)]),
                                            startPoint: CGPoint(x: c.x - pr, y: c.y - pr), endPoint: CGPoint(x: c.x + pr, y: c.y + pr)))
        let mat = pr * 0.965
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - mat, y: c.y - mat, width: mat * 2, height: mat * 2)), with: .color(Color(white: 0.09)))
        // Strobe dots on the rim
        let dots = 120
        for k in 0..<dots {
          let a = Double(k) / Double(dots) * 2 * .pi
          let rr = pr * 0.985
          let p = CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
          let d = side * 0.0028
          ctx.fill(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2)), with: .color(Color.black.opacity(k % 2 == 0 ? 0.55 : 0.25)))
        }
        // Vinyl
        let vinyl = Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
        ctx.fill(vinyl, with: .radialGradient(Gradient(colors: [Color(white: 0.05), Color(white: 0.09), Color(white: 0.06), Color(white: 0.11)]),
                                              center: c, startRadius: R * 0.3, endRadius: R))
        // Grooves
        var r = R * 0.37
        var n = 0
        while r < R * 0.975 {
          let isGap = [0.54, 0.66, 0.79, 0.9].contains { abs(Double(r / R) - $0) < 0.006 }
          let alpha = isGap ? 0.14 : (n % 2 == 0 ? 0.045 : 0.022)
          let w: CGFloat = isGap ? 1.4 : 0.55
          ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(alpha)), lineWidth: w)
          r += R * 0.0075
          n += 1
        }
        // Lead-in edge
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R * 0.995, y: c.y - R * 0.995, width: R * 1.99, height: R * 1.99)), with: .color(.white.opacity(0.16)), lineWidth: 1)
      }
      .frame(width: platterD, height: platterD)

      // Album-art label
      ArtworkImage(url: artworkURL, cornerRadius: R * 0.34, maxPixel: 600)
        .frame(width: R * 0.68, height: R * 0.68)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 2))
        .overlay(
          Circle().fill(RadialGradient(colors: [.clear, .clear, .black.opacity(0.28)], center: .center, startRadius: 0, endRadius: R * 0.34))
        )
        .overlay(alignment: .bottom) {
          Text("LADO A · 33⅓")
            .font(.system(size: max(6, R * 0.045), weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.7), radius: 2)
            .padding(.bottom, R * 0.05)
        }

      // Spindle
      Circle()
        .fill(RadialGradient(colors: [Color(white: 0.98), Color(white: 0.6), Color(white: 0.3)], center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: R * 0.035))
        .frame(width: R * 0.06, height: R * 0.06)
        .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
    }
    .frame(width: side * 0.83, height: side * 0.83)
  }
}

/// Light reflections on vinyl stay put while the record spins — that is what sells the realism.
struct RecordSheen: View {
  let radius: CGFloat
  var body: some View {
    ZStack {
      AngularGradient(
        stops: [
          .init(color: .clear, location: 0.00),
          .init(color: Theme.sky.opacity(0.10), location: 0.06),
          .init(color: .white.opacity(0.20), location: 0.10),
          .init(color: Theme.rose.opacity(0.10), location: 0.14),
          .init(color: .clear, location: 0.22),
          .init(color: .clear, location: 0.50),
          .init(color: Theme.lavender.opacity(0.08), location: 0.56),
          .init(color: .white.opacity(0.15), location: 0.60),
          .init(color: Theme.peach.opacity(0.08), location: 0.64),
          .init(color: .clear, location: 0.72),
          .init(color: .clear, location: 1.00),
        ],
        center: .center,
        angle: .degrees(-35)
      )
      .mask(
        ZStack {
          Circle().frame(width: radius * 1.95, height: radius * 1.95)
          Circle().frame(width: radius * 0.72, height: radius * 0.72).blendMode(.destinationOut)
        }
        .compositingGroup()
      )
      .blendMode(.plusLighter)
    }
  }
}

// MARK: - Tonearm (animatable angle + lift)

struct TonearmView: View, Animatable {
  let side: CGFloat
  let pivot: CGPoint
  let length: CGFloat
  var angle: Double
  var lift: Double

  var animatableData: AnimatablePair<Double, Double> {
    get { AnimatablePair(angle, lift) }
    set { angle = newValue.first; lift = newValue.second }
  }

  var body: some View {
    Canvas { ctx, _ in
      let S = side
      let shadowOffset = CGSize(width: S * (0.012 + 0.02 * lift), height: S * (0.016 + 0.026 * lift))

      func drawArm(_ c: inout GraphicsContext, shadow: Bool) {
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: .degrees(angle))
        let scale = 1 + 0.025 * lift
        c.scaleBy(x: scale, y: scale)
        let tubeW = S * 0.021
        let metal: GraphicsContext.Shading = shadow ? .color(.black) :
          .linearGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.98), Color(white: 0.62), Color(white: 0.4)]),
                          startPoint: CGPoint(x: -tubeW, y: 0), endPoint: CGPoint(x: tubeW, y: 0))

        // Counterweight (behind pivot)
        let cw = Path(roundedRect: CGRect(x: -S * 0.04, y: -S * 0.17, width: S * 0.08, height: S * 0.085), cornerRadius: S * 0.012)
        c.fill(cw, with: shadow ? .color(.black) : .linearGradient(
          Gradient(colors: [Color(white: 0.35), Color(white: 0.85), Color(white: 0.5), Color(white: 0.25)]),
          startPoint: CGPoint(x: -S * 0.04, y: 0), endPoint: CGPoint(x: S * 0.04, y: 0)))
        if !shadow {
          for k in 0..<5 {
            let yy = -S * 0.165 + CGFloat(k) * S * 0.017
            c.fill(Path(CGRect(x: -S * 0.04, y: yy, width: S * 0.08, height: 0.6)), with: .color(.black.opacity(0.25)))
          }
        }
        // Rear stub
        c.fill(Path(roundedRect: CGRect(x: -tubeW * 0.45, y: -S * 0.09, width: tubeW * 0.9, height: S * 0.09), cornerRadius: tubeW * 0.45), with: metal)

        // Main tube
        let tube = Path(roundedRect: CGRect(x: -tubeW / 2, y: 0, width: tubeW, height: length * 0.86), cornerRadius: tubeW / 2)
        c.fill(tube, with: metal)

        // Headshell (bent ~22°)
        var hs = c
        hs.translateBy(x: 0, y: length * 0.84)
        hs.rotate(by: .degrees(22))
        let shell = Path(roundedRect: CGRect(x: -S * 0.03, y: 0, width: S * 0.06, height: S * 0.115), cornerRadius: S * 0.012)
        hs.fill(shell, with: shadow ? .color(.black) : .linearGradient(
          Gradient(colors: [Color(white: 0.22), Color(white: 0.08)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: S * 0.115)))
        if !shadow {
          // Cartridge
          let cart = Path(roundedRect: CGRect(x: -S * 0.022, y: S * 0.035, width: S * 0.044, height: S * 0.058), cornerRadius: S * 0.006)
          hs.fill(cart, with: .linearGradient(Gradient(colors: [Theme.rose, Theme.lavender]), startPoint: CGPoint(x: 0, y: S * 0.035), endPoint: CGPoint(x: 0, y: S * 0.093)))
          hs.stroke(shell, with: .color(.white.opacity(0.25)), lineWidth: 0.6)
          // Finger lift
          var lift = Path()
          lift.move(to: CGPoint(x: S * 0.03, y: S * 0.02))
          lift.addLine(to: CGPoint(x: S * 0.06, y: S * 0.005))
          hs.stroke(lift, with: .color(Color(white: 0.85)), style: StrokeStyle(lineWidth: S * 0.008, lineCap: .round))
        }
      }

      // Soft shadow first
      var sh = ctx
      sh.opacity = 0.32 - 0.12 * lift
      sh.addFilter(.blur(radius: S * (0.008 + 0.012 * lift)))
      sh.translateBy(x: shadowOffset.width, y: shadowOffset.height)
      drawArm(&sh, shadow: true)

      var arm = ctx
      drawArm(&arm, shadow: false)

      // Pivot bearing (does not rotate)
      let pr = S * 0.072
      ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - pr, y: pivot.y - pr, width: pr * 2, height: pr * 2)),
               with: .radialGradient(Gradient(colors: [Color(white: 0.97), Color(white: 0.7), Color(white: 0.45)]),
                                     center: CGPoint(x: pivot.x - pr * 0.4, y: pivot.y - pr * 0.4), startRadius: 0, endRadius: pr * 1.6))
      ctx.stroke(Path(ellipseIn: CGRect(x: pivot.x - pr, y: pivot.y - pr, width: pr * 2, height: pr * 2)), with: .color(.black.opacity(0.18)), lineWidth: 0.8)
      let gr = S * 0.038
      ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - gr, y: pivot.y - gr, width: gr * 2, height: gr * 2)),
               with: .radialGradient(Gradient(colors: [Color(white: 0.3), Color(white: 0.08)]), center: CGPoint(x: pivot.x - gr * 0.3, y: pivot.y - gr * 0.3), startRadius: 0, endRadius: gr * 1.4))
      let cr = S * 0.013
      ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - cr, y: pivot.y - cr, width: cr * 2, height: cr * 2)), with: .color(Color(white: 0.85)))
    }
    .frame(width: side, height: side)
  }
}

struct ArmRest: View {
  let side: CGFloat
  var body: some View {
    ZStack {
      Circle()
        .fill(RadialGradient(colors: [Color(white: 0.95), Color(white: 0.55)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: side * 0.03))
        .frame(width: side * 0.045, height: side * 0.045)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 2)
      Capsule()
        .fill(Color(white: 0.15))
        .frame(width: side * 0.035, height: side * 0.012)
    }
  }
}

struct PitchFader: View {
  let side: CGFloat
  @Binding var value: Double
  let onChange: (Double) -> Void

  var body: some View {
    GeometryReader { g in
      let h = g.size.height
      ZStack {
        RoundedRectangle(cornerRadius: g.size.width * 0.25)
          .fill(Color.black.opacity(0.55))
          .frame(width: g.size.width * 0.28)
          .overlay(RoundedRectangle(cornerRadius: g.size.width * 0.25).stroke(Color.white.opacity(0.5), lineWidth: 0.5).offset(x: 0.5, y: 0.8))
        // Center detent marks
        ForEach(-4...4, id: \.self) { k in
          Rectangle()
            .fill(Color.black.opacity(k == 0 ? 0.6 : 0.3))
            .frame(width: g.size.width * (k == 0 ? 0.9 : 0.55), height: 0.7)
            .offset(x: -g.size.width * 0.6, y: CGFloat(k) * h * 0.1)
        }
        RoundedRectangle(cornerRadius: g.size.width * 0.12, style: .continuous)
          .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
          .frame(width: g.size.width * 0.95, height: h * 0.13)
          .overlay(Rectangle().fill(Theme.rose).frame(height: 1.2))
          .shadow(color: .black.opacity(0.45), radius: 2.5, y: 2)
          .offset(y: CGFloat(value) * h * 0.42)
      }
      .frame(width: g.size.width, height: h)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { v in
            var nv = Double((v.location.y - h / 2) / (h * 0.42))
            nv = min(1, max(-1, nv))
            if abs(nv) < 0.08 { nv = 0 }
            if (nv == 0) != (value == 0) { Haptics.rigid() }
            value = nv
            onChange(nv)
          }
      )
      .onTapGesture(count: 2) {
        withAnimation(.spring) { value = 0 }
        onChange(0)
      }
    }
    .overlay(alignment: .bottom) {
      Text("PITCH")
        .font(.system(size: side * 0.018, weight: .heavy, design: .rounded))
        .foregroundStyle(Color.black.opacity(0.4))
        .fixedSize()
        .offset(y: side * 0.03)
    }
  }
}
