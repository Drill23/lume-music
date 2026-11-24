import SwiftUI

/// Toca-discos Direct-Drive 3D de estúdio:
/// chassi com shader Metal em 4 acabamentos, profundidade 3D chanfrada com pés isoladores,
/// 4 edições de vinil com microssulcos e reflexo especular estacionário a 120Hz,
/// braço em S articulado com cálculo analítico O(1) e alavanca Cue real, pitch varispeed e scratch.
struct TurntableStage: View {
  let track: Track
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var clock = PlaybackClock.shared
  @ObservedObject private var store = LibraryStore.shared
  @State private var pitchPercent: Double = 0

  var body: some View {
    GeometryReader { g in
      let availH = max(230, g.size.height - 44)
      let side = min(g.size.width - 24, availH, 410)
      ZStack(alignment: .topTrailing) {
        VStack(spacing: 0) {
          Spacer(minLength: 20)
          TurntableDeck(
            side: side,
            artworkURL: player.currentArtwork,
            isPlaying: player.isPlaying,
            progress: clock.duration > 0 ? clock.currentTime / clock.duration : 0,
            finish: store.turntableFinish,
            edition: store.vinylEdition,
            is3D: store.turntable3D,
            onPitchChange: { pitchPercent = $0 * 8.0 }
          )
          .frame(width: side, height: side)
          Spacer(minLength: 0)
        }
        .frame(width: g.size.width, height: g.size.height)

        if abs(pitchPercent) >= 0.2 {
          Text(String(format: "Pitch %+.1f%%", pitchPercent))
            .font(Theme.font(11, .bold))
            .foregroundStyle(Theme.accent)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .frame(height: 28)
            .glassCapsule()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 18)
            .padding(.bottom, 6)
        }

        StageStyleOrb(icon: "record.circle", accessibilityLabel: "Personalizar toca-discos") { dismiss in
          let cols = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
              perspectivePill(title: "3D Estúdio", active: store.turntable3D) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.turntable3D = true }
                dismiss()
              }
              perspectivePill(title: "Vista Topo", active: !store.turntable3D) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { store.turntable3D = false }
                dismiss()
              }
            }

            sectionHeader("MESA")
            LazyVGrid(columns: cols, spacing: 6) {
              ForEach(TurntableFinish.allCases) { f in
                let active = store.turntableFinish == f
                orbOptionRow(title: f.rawValue, active: active) {
                  withAnimation(.easeInOut(duration: 0.25)) { store.turntableFinish = f }
                  dismiss()
                }
              }
            }

            sectionHeader("EDIÇÃO DO VINIL")
            LazyVGrid(columns: cols, spacing: 6) {
              ForEach(VinylEdition.allCases) { ed in
                let active = store.vinylEdition == ed
                orbOptionRow(title: ed.rawValue, active: active) {
                  withAnimation(.easeInOut(duration: 0.25)) { store.vinylEdition = ed }
                  dismiss()
                }
              }
            }
          }
        }
      }
    }
  }

  private func sectionHeader(_ text: String) -> some View {
    Text(text)
      .font(Theme.font(10, .heavy))
      .tracking(0.8)
      .foregroundStyle(Theme.secondary)
      .padding(.horizontal, 4)
  }

  private func perspectivePill(title: String, active: Bool, action: @escaping () -> Void) -> some View {
    Button {
      Haptics.selection()
      action()
    } label: {
      Text(title)
        .font(Theme.font(11.5, .bold))
        .foregroundStyle(active ? Theme.onPrism : Theme.text)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(active ? AnyShapeStyle(Theme.prismDiagonal) : AnyShapeStyle(Color.white.opacity(0.08)))
        }
    }
    .buttonStyle(.plain)
  }

  private func orbOptionRow(title: String, active: Bool, action: @escaping () -> Void) -> some View {
    Button {
      Haptics.selection()
      action()
    } label: {
      HStack {
        Text(title)
          .font(Theme.font(11, active ? .bold : .semibold))
          .foregroundStyle(active ? Theme.onPrism : Theme.text)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Spacer(minLength: 2)
        if active {
          Image(systemName: "checkmark")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(Theme.onPrism)
        }
      }
      .padding(.horizontal, 8)
      .frame(height: 29)
      .background {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(active ? AnyShapeStyle(Theme.prismDiagonal) : AnyShapeStyle(Color.white.opacity(0.06)))
      }
    }
    .buttonStyle(.plain)
  }
}

struct TurntableDeck: View {
  let side: CGFloat
  let artworkURL: String
  let isPlaying: Bool
  let progress: Double
  var finish: TurntableFinish = .obsidian
  var edition: VinylEdition = .classicBlack
  var is3D: Bool = true
  var onPitchChange: ((Double) -> Void)? = nil

  @ObservedObject private var player = AudioPlayer.shared
  @State private var spin = SpinModel()
  @State private var idleTick = false
  @State private var rpm45 = false
  @State private var scratchDelta: Double = 0
  @State private var scratchLastAngle: Double?
  @State private var scratching = false
  @State private var startPressed = false
  @State private var pitch: Double = 0

  private var S: CGFloat { side }
  private var center: CGPoint { CGPoint(x: S * 0.43, y: S * 0.50) }
  private var recordR: CGFloat { S * 0.385 }
  private var pivot: CGPoint { CGPoint(x: S * 0.845, y: S * 0.185) }
  private var armLen: CGFloat { S * 0.60 }
  private var degPerSec: Double { (rpm45 ? 45 : 33.333) * 6 * (1 + pitch * 0.08) }

  var body: some View {
    ZStack {
      // Base 3D física extrudada + pés isoladores
      if is3D {
        deckChassisDepth
      }

      deckTopSurface
    }
    .frame(width: S, height: S)
    .rotation3DEffect(.degrees(is3D ? 10 : 0), axis: (x: 1, y: -0.04, z: 0), perspective: 0.45)
    .shadow(color: .black.opacity(is3D ? 0.46 : 0.34), radius: S * (is3D ? 0.07 : 0.048), y: S * (is3D ? 0.05 : 0.032))
    .onChange(of: isPlaying) { _, now in
      if !now {
        Task {
          try? await Task.sleep(for: .seconds(5))
          idleTick.toggle()
        }
      }
    }
    .overlay { if idleTick { EmptyView() } }
  }

  private var deckChassisDepth: some View {
    let corner = S * 0.075
    return ZStack {
      // Pés isoladores cromados nos cantos inferiores
      HStack {
        isolationFoot
        Spacer()
        isolationFoot
      }
      .padding(.horizontal, S * 0.09)
      .offset(y: S * 0.49)

      // Borda lateral extrudada do chassi
      RoundedRectangle(cornerRadius: corner, style: .continuous)
        .fill(
          LinearGradient(
            colors: finish.isDarkChassis
              ? [Color(white: 0.06), Color(white: 0.02)]
              : [Color(white: 0.42), Color(white: 0.24)],
            startPoint: .leading, endPoint: .trailing
          )
        )
        .frame(width: S, height: S)
        .overlay(
          RoundedRectangle(cornerRadius: corner, style: .continuous)
            .stroke(Color.white.opacity(finish.isDarkChassis ? 0.10 : 0.28), lineWidth: 0.8)
        )
        .offset(y: S * 0.036)
    }
  }

  private var isolationFoot: some View {
    RoundedRectangle(cornerRadius: S * 0.015, style: .continuous)
      .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.18), Color(white: 0.4)], startPoint: .leading, endPoint: .trailing))
      .frame(width: S * 0.11, height: S * 0.038)
      .shadow(color: .black.opacity(0.6), radius: 4, y: 3)
  }

  private var deckTopSurface: some View {
    ZStack {
      PlinthView(side: S, finish: finish).equatable()

      // Seletor de velocidade 33 / 45
      HStack(spacing: S * 0.018) {
        speedKey("33", active: !rpm45) { rpm45 = false }
        speedKey("45", active: rpm45) { rpm45 = true }
      }
      .position(x: S * 0.135, y: S * 0.075)

      Text("LUME DD-1")
        .font(.system(size: S * 0.020, weight: .heavy, design: .rounded))
        .tracking(S * 0.002)
        .foregroundStyle(finish.isDarkChassis ? Color.white.opacity(0.45) : Color.black.opacity(0.42))
        .position(x: S * 0.132, y: S * 0.128)

      // Poço do prato
      Circle()
        .fill(Color.black.opacity(0.55))
        .frame(width: S * 0.835, height: S * 0.835)
        .blur(radius: S * 0.012)
        .position(x: center.x + S * 0.006, y: center.y + S * 0.010)
      strobeLight

      // Prato + Vinil com shader GPU 120Hz + selo giratório
      TimelineView(.animation(paused: !isPlaying && !scratching && !spin.isMoving)) { tl in
        let angle = spin.step(now: tl.date.timeIntervalSinceReferenceDate, target: (isPlaying && !scratching) ? degPerSec : 0)
        ZStack {
          PlatterStrobeRim(side: S)
            .rotationEffect(.degrees(angle))
          VinylGrooveDisc(side: S, edition: edition, rotationDeg: angle)
          VinylLabel(side: S, artworkURL: artworkURL, rpmText: rpm45 ? "LADO A · 45 RPM" : "LADO A · 33⅓")
            .rotationEffect(.degrees(angle))
        }
      }
      .frame(width: S * 0.83, height: S * 0.83)
      .position(center)
      .contentShape(Circle())
      .gesture(scratchGesture)
      .onTapGesture { Haptics.medium(); player.togglePlayPause() }

      // Descanso do braço
      ArmRest(side: S)
        .position(x: pivot.x - armLen * 0.73 * sin(2 * .pi / 180), y: pivot.y + armLen * 0.73 * cos(2 * .pi / 180))

      // Braço em S articulado com alavanca Cue real
      TonearmView(side: S, pivot: pivot, length: armLen, angle: armAngle, lift: isPlaying ? 0 : 1, darkChassis: finish.isDarkChassis)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.95, dampingFraction: 0.86), value: isPlaying)
        .animation(.linear(duration: 0.4), value: armAngle)

      startStopButton
        .position(x: S * 0.125, y: S * 0.905)

      PitchFader(side: S, value: $pitch, darkChassis: finish.isDarkChassis) { newValue in
        player.setVarispeed(Float(1 + newValue * 0.08))
        onPitchChange?(newValue)
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
  }

  /// Comportamento Cue real: se pausado no meio da música, o braço levanta sobre o sulco atual; só estaciona no início.
  private var armAngle: Double {
    guard isPlaying || progress > 0.002 else { return 2 }
    let p = min(1, max(0, progress))
    let r = recordR * (0.95 - 0.56 * p)
    return Self.angle(forRadius: r, pivot: pivot, center: center, length: armLen)
  }

  /// Cálculo analítico O(1) do ângulo do braço pela Lei dos Cossenos.
  static func angle(forRadius r: CGFloat, pivot: CGPoint, center: CGPoint, length: CGFloat) -> Double {
    let dx = Double(pivot.x - center.x)
    let dy = Double(center.y - pivot.y)
    let d = hypot(dx, dy)
    let L = Double(length)
    guard d > 0.001, L > 0.001 else { return 0 }
    let phi = atan2(dx, dy)
    let cosTheta = min(1.0, max(-1.0, (d * d + L * L - Double(r * r)) / (2.0 * d * L)))
    let theta = acos(cosTheta)
    let deg = (phi - theta) * 180.0 / .pi
    return min(70.0, max(0.0, deg))
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

/// Física do prato frame a frame (referência mutável, zero churn no SwiftUI).
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

// MARK: - Chassi Metal Shader

struct PlinthView: View, Equatable {
  let side: CGFloat
  var finish: TurntableFinish = .obsidian

  var body: some View {
    let corner = side * 0.075
    Image(uiImage: LumeTextures.shared.brushedSurface(styleId: Int(finish.shaderIndex)))
      .resizable()
      .scaledToFill()
      .frame(width: side, height: side)
      .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
      .overlay {
        Canvas { ctx, sz in
          let rect = CGRect(origin: .zero, size: sz)
          let shape = Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
          ctx.stroke(shape, with: .linearGradient(
            Gradient(colors: [.white.opacity(finish.isDarkChassis ? 0.35 : 0.95), .white.opacity(0.25), .black.opacity(0.35)]),
            startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)), lineWidth: 1.6)
          let inner = Path(roundedRect: rect.insetBy(dx: side * 0.012, dy: side * 0.012), cornerRadius: corner * 0.85, style: .continuous)
          ctx.stroke(inner, with: .linearGradient(
            Gradient(colors: [.black.opacity(0.18), .white.opacity(finish.isDarkChassis ? 0.14 : 0.45)]),
            startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)), lineWidth: 0.8)

          for p in [CGPoint(x: side * 0.045, y: side * 0.045), CGPoint(x: side * 0.955, y: side * 0.045),
                    CGPoint(x: side * 0.045, y: side * 0.955), CGPoint(x: side * 0.955, y: side * 0.955)] {
            let r = side * 0.009
            let screw = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.fill(screw, with: .radialGradient(Gradient(colors: [Color(white: 0.92), Color(white: 0.45)]), center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.3), startRadius: 0, endRadius: r * 1.4))
            var slot = Path()
            slot.move(to: CGPoint(x: p.x - r * 0.7, y: p.y + r * 0.2))
            slot.addLine(to: CGPoint(x: p.x + r * 0.7, y: p.y - r * 0.2))
            ctx.stroke(slot, with: .color(.black.opacity(0.4)), lineWidth: 0.6)
          }
        }
      }
      .drawingGroup()
      .frame(width: side, height: side)
  }
}

// MARK: - Prato & Disco GPU

struct PlatterStrobeRim: View {
  let side: CGFloat

  var body: some View {
    let platterD = side * 0.81
    Canvas { ctx, sz in
      let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
      let pr = platterD / 2
      let rim = Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2))
      ctx.fill(rim, with: .linearGradient(
        Gradient(colors: [Color(white: 0.88), Color(white: 0.40), Color(white: 0.78), Color(white: 0.30)]),
        startPoint: CGPoint(x: c.x - pr, y: c.y - pr), endPoint: CGPoint(x: c.x + pr, y: c.y + pr)))
      let mat = pr * 0.962
      ctx.fill(Path(ellipseIn: CGRect(x: c.x - mat, y: c.y - mat, width: mat * 2, height: mat * 2)), with: .color(Color(white: 0.08)))
      // Dupla fileira de pontos estroboscópicos
      for ring in [0.986, 0.974] {
        let dots = ring > 0.98 ? 120 : 90
        for k in 0..<dots {
          let a = Double(k) / Double(dots) * 2 * .pi
          let rr = pr * ring
          let p = CGPoint(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
          let d = side * (ring > 0.98 ? 0.0028 : 0.0020)
          ctx.fill(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2)), with: .color(Color.black.opacity(k % 2 == 0 ? 0.6 : 0.25)))
        }
      }
    }
    .frame(width: platterD, height: platterD)
    .drawingGroup()
  }
}

struct VinylGrooveDisc: View {
  let side: CGFloat
  let edition: VinylEdition
  let rotationDeg: Double

  var body: some View {
    let d = side * 0.77
    ZStack {
      Image(uiImage: LumeTextures.shared.vinylDisc(edition: edition))
        .resizable()
        .frame(width: d, height: d)
        .rotationEffect(.degrees(rotationDeg))
        .overlay(
          Circle()
            .stroke(
              LinearGradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing),
              lineWidth: 1.2
            )
        )

      // Reflexo especular de estúdio estacionário (não gira com o disco)
      VinylSpecularSheen(diameter: d, prism: edition == .prismCrystal)
        .allowsHitTesting(false)
    }
  }
}

struct VinylSpecularSheen: View {
  let diameter: CGFloat
  var prism: Bool = false

  var body: some View {
    AngularGradient(
      stops: prism ? [
        .init(color: .clear, location: 0.00),
        .init(color: Theme.sky.opacity(0.11), location: 0.06),
        .init(color: .white.opacity(0.20), location: 0.10),
        .init(color: Theme.rose.opacity(0.11), location: 0.14),
        .init(color: .clear, location: 0.22),
        .init(color: .clear, location: 0.50),
        .init(color: Theme.lavender.opacity(0.09), location: 0.56),
        .init(color: .white.opacity(0.14), location: 0.60),
        .init(color: Theme.peach.opacity(0.09), location: 0.64),
        .init(color: .clear, location: 0.72),
        .init(color: .clear, location: 1.00),
      ] : [
        .init(color: .clear, location: 0.00),
        .init(color: .white.opacity(0.04), location: 0.05),
        .init(color: .white.opacity(0.17), location: 0.095),
        .init(color: .white.opacity(0.04), location: 0.145),
        .init(color: .clear, location: 0.21),
        .init(color: .clear, location: 0.51),
        .init(color: .white.opacity(0.03), location: 0.56),
        .init(color: .white.opacity(0.10), location: 0.60),
        .init(color: .white.opacity(0.03), location: 0.64),
        .init(color: .clear, location: 0.70),
        .init(color: .clear, location: 1.00),
      ],
      center: .center,
      angle: .degrees(-36)
    )
    .frame(width: diameter, height: diameter)
    .mask(
      ZStack {
        Circle().frame(width: diameter * 0.985, height: diameter * 0.985)
        Circle().frame(width: diameter * 0.37, height: diameter * 0.37).blendMode(.destinationOut)
      }
      .compositingGroup()
    )
    .blendMode(.plusLighter)
  }
}

struct VinylLabel: View {
  let side: CGFloat
  let artworkURL: String
  let rpmText: String

  var body: some View {
    let R = side * 0.385
    ZStack {
      ArtworkImage(url: artworkURL, cornerRadius: R * 0.34, maxPixel: 600)
        .frame(width: R * 0.68, height: R * 0.68)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.black.opacity(0.65), lineWidth: 2))
        // Anel estampado característico de prensa de vinil no papel do selo
        .overlay(Circle().stroke(Color.black.opacity(0.22), lineWidth: 1).frame(width: R * 0.44, height: R * 0.44))
        .overlay(
          Circle().fill(RadialGradient(colors: [.clear, .clear, .black.opacity(0.32)], center: .center, startRadius: 0, endRadius: R * 0.34))
        )
        .overlay(alignment: .bottom) {
          Text(rpmText)
            .font(.system(size: max(6, R * 0.044), weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.75), radius: 2)
            .padding(.bottom, R * 0.048)
        }

      // Eixo metálico torneado central
      Circle()
        .fill(RadialGradient(colors: [Color(white: 0.98), Color(white: 0.56), Color(white: 0.22)], center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: R * 0.036))
        .frame(width: R * 0.066, height: R * 0.066)
        .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
    }
  }
}

/// Prévia compacta reutilizada em SettingsView.
struct RecordDisc: View, Equatable {
  let side: CGFloat
  let artworkURL: String
  var edition: VinylEdition = .classicBlack

  var body: some View {
    ZStack {
      PlatterStrobeRim(side: side)
      VinylGrooveDisc(side: side, edition: edition, rotationDeg: 0)
      VinylLabel(side: side, artworkURL: artworkURL, rpmText: "LADO A · 33⅓")
    }
    .frame(width: side * 0.83, height: side * 0.83)
  }
}

// MARK: - Braço em S (Tonearm S-Shaped animável)

struct TonearmView: View, Animatable {
  let side: CGFloat
  let pivot: CGPoint
  let length: CGFloat
  var angle: Double
  var lift: Double
  var darkChassis: Bool = true

  var animatableData: AnimatablePair<Double, Double> {
    get { AnimatablePair(angle, lift) }
    set { angle = newValue.first; lift = newValue.second }
  }

  var body: some View {
    Canvas { ctx, _ in
      let S = side
      let shadowOffset = CGSize(width: S * (0.012 + 0.022 * lift), height: S * (0.016 + 0.028 * lift))

      func drawArm(_ c: inout GraphicsContext, shadow: Bool) {
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: .degrees(angle))
        let scale = 1 + 0.03 * lift
        c.scaleBy(x: scale, y: scale)
        let tubeW = S * 0.021
        let metal: GraphicsContext.Shading = shadow ? .color(.black) :
          .linearGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.98), Color(white: 0.62), Color(white: 0.4)]),
                          startPoint: CGPoint(x: -tubeW, y: 0), endPoint: CGPoint(x: tubeW, y: 0))

        // Contrapeso graduado
        let cw = Path(roundedRect: CGRect(x: -S * 0.04, y: -S * 0.17, width: S * 0.08, height: S * 0.085), cornerRadius: S * 0.012)
        c.fill(cw, with: shadow ? .color(.black) : .linearGradient(
          Gradient(colors: [Color(white: 0.35), Color(white: 0.85), Color(white: 0.5), Color(white: 0.25)]),
          startPoint: CGPoint(x: -S * 0.04, y: 0), endPoint: CGPoint(x: S * 0.04, y: 0)))
        if !shadow {
          for k in 0..<5 {
            let yy = -S * 0.165 + CGFloat(k) * S * 0.017
            c.fill(Path(CGRect(x: -S * 0.04, y: yy, width: S * 0.08, height: 0.6)), with: .color(.black.opacity(0.28)))
          }
        }
        c.fill(Path(roundedRect: CGRect(x: -tubeW * 0.45, y: -S * 0.09, width: tubeW * 0.9, height: S * 0.09), cornerRadius: tubeW * 0.45), with: metal)

        // Tubo em curva S realista
        var sTube = Path()
        sTube.move(to: .zero)
        sTube.addCurve(
          to: CGPoint(x: S * 0.012, y: length * 0.85),
          control1: CGPoint(x: S * 0.042, y: length * 0.28),
          control2: CGPoint(x: -S * 0.036, y: length * 0.58)
        )
        c.stroke(sTube, with: metal, style: StrokeStyle(lineWidth: tubeW, lineCap: .round))

        // Headshell perfurado inclinado 22°
        var hs = c
        hs.translateBy(x: S * 0.012, y: length * 0.84)
        hs.rotate(by: .degrees(22))
        let shell = Path(roundedRect: CGRect(x: -S * 0.03, y: 0, width: S * 0.06, height: S * 0.115), cornerRadius: S * 0.012)
        hs.fill(shell, with: shadow ? .color(.black) : .linearGradient(
          Gradient(colors: [Color(white: 0.22), Color(white: 0.08)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: S * 0.115)))
        if !shadow {
          let cart = Path(roundedRect: CGRect(x: -S * 0.022, y: S * 0.035, width: S * 0.044, height: S * 0.058), cornerRadius: S * 0.006)
          hs.fill(cart, with: .linearGradient(Gradient(colors: [Theme.rose, Theme.lavender]), startPoint: CGPoint(x: 0, y: S * 0.035), endPoint: CGPoint(x: 0, y: S * 0.093)))
          hs.stroke(shell, with: .color(.white.opacity(0.28)), lineWidth: 0.6)
          // Furos do headshell
          for yHole in [S * 0.015, S * 0.027] {
            hs.fill(Path(ellipseIn: CGRect(x: -S * 0.005, y: yHole, width: S * 0.01, height: S * 0.01)), with: .color(.black.opacity(0.75)))
          }
          var liftBar = Path()
          liftBar.move(to: CGPoint(x: S * 0.03, y: S * 0.02))
          liftBar.addLine(to: CGPoint(x: S * 0.06, y: S * 0.005))
          hs.stroke(liftBar, with: .color(Color(white: 0.88)), style: StrokeStyle(lineWidth: S * 0.008, lineCap: .round))
        }
      }

      var sh = ctx
      sh.opacity = 0.34 - 0.12 * lift
      sh.addFilter(.blur(radius: S * (0.008 + 0.012 * lift)))
      sh.translateBy(x: shadowOffset.width, y: shadowOffset.height)
      drawArm(&sh, shadow: true)

      var arm = ctx
      drawArm(&arm, shadow: false)

      // Base do pivô + dial anti-skating
      let pr = S * 0.072
      ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - pr, y: pivot.y - pr, width: pr * 2, height: pr * 2)),
               with: .radialGradient(Gradient(colors: [Color(white: 0.97), Color(white: 0.7), Color(white: 0.45)]),
                                     center: CGPoint(x: pivot.x - pr * 0.4, y: pivot.y - pr * 0.4), startRadius: 0, endRadius: pr * 1.6))
      ctx.stroke(Path(ellipseIn: CGRect(x: pivot.x - pr, y: pivot.y - pr, width: pr * 2, height: pr * 2)), with: .color(.black.opacity(0.22)), lineWidth: 0.8)
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
  var darkChassis: Bool = true
  let onChange: (Double) -> Void

  var body: some View {
    GeometryReader { g in
      let h = g.size.height
      ZStack {
        RoundedRectangle(cornerRadius: g.size.width * 0.25)
          .fill(Color.black.opacity(0.62))
          .frame(width: g.size.width * 0.28)
          .overlay(RoundedRectangle(cornerRadius: g.size.width * 0.25).stroke(Color.white.opacity(0.4), lineWidth: 0.5).offset(x: 0.5, y: 0.8))
        ForEach(-4...4, id: \.self) { k in
          Rectangle()
            .fill((darkChassis ? Color.white : Color.black).opacity(k == 0 ? 0.65 : 0.3))
            .frame(width: g.size.width * (k == 0 ? 0.9 : 0.55), height: 0.7)
            .offset(x: -g.size.width * 0.6, y: CGFloat(k) * h * 0.1)
        }
        RoundedRectangle(cornerRadius: g.size.width * 0.12, style: .continuous)
          .fill(LinearGradient(colors: [Color(white: 0.34), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
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
        .foregroundStyle((darkChassis ? Color.white : Color.black).opacity(0.45))
        .fixedSize()
        .offset(y: side * 0.03)
    }
  }
}
