import SwiftUI

// MARK: - Palco "Vinil"

/// Toca-discos de estúdio. O deck é uma imagem estática (chassi, marcações, parafusos) + prato/disco
/// pré-renderizados que só giram (rotationEffect) + reflexo parado + braço que só rotaciona em volta do pivô.
/// Os controles (33/45, iniciar/parar, pitch, estilos) ficam numa doca de vidro com alvos ≥ 44 pt.
struct TurntableStage: View {
  let track: Track
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var clock = PlaybackClock.shared
  @ObservedObject private var store = LibraryStore.shared
  @State private var rpm45 = false
  @State private var pitch: Double = 0

  var body: some View {
    GeometryReader { g in
      let dockH: CGFloat = 44
      let thick: CGFloat = store.turntable3D ? 0.035 : 0
      let availH = max(170, g.size.height - dockH - 36)
      let W = min(g.size.width - 24, availH / (1 + thick) * DeckGeo.aspect, 520)
      let H = W / DeckGeo.aspect
      let progress = clock.duration > 0 ? min(1, max(0, clock.currentTime / clock.duration)) : 0

      ZStack {
        VStack(spacing: 14) {
          Spacer(minLength: 0)
          TurntableDeck(
            height: H,
            artworkURL: player.currentArtwork,
            isPlaying: player.isPlaying,
            progress: (progress * 400).rounded() / 400,
            finish: store.turntableFinish,
            edition: store.vinylEdition,
            is3D: store.turntable3D,
            rpm45: rpm45,
            pitch: pitch
          )
          .frame(width: W, height: H * (1 + thick), alignment: .top)
          dock
            .padding(.trailing, 52)
            .padding(.horizontal, 14)
            .frame(height: dockH)
        }
        .padding(.bottom, 8)
        .frame(width: g.size.width, height: g.size.height)

        StageStyleOrb(icon: "slider.horizontal.3", accessibilityLabel: "Personalizar toca-discos", title: nil, placement: .bottomTrailing) { _ in
          orbPanel
        }
      }
    }
    .onAppear {
      if abs(player.varispeed - 1.0) > 0.005 {
        pitch = max(-1, min(1, Double(player.varispeed - 1.0) / 0.08))
      }
    }
  }

  // MARK: doca

  private var dock: some View {
    HStack(spacing: 8) {
      SpeedPicker(rpm45: $rpm45)
      Button {
        Haptics.rigid()
        player.togglePlayPause()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 16, weight: .bold))
            .contentTransition(.symbolEffect(.replace))
          Text(player.isPlaying ? "Parar" : "Iniciar")
            .font(Theme.font(13.5, .semibold))
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12)
        .frame(minWidth: 84, minHeight: 44)
        .contentShape(Capsule())
        .glassCapsule(tint: player.isPlaying ? Theme.mint.opacity(0.35) : nil, interactive: true)
      }
      .buttonStyle(PressableStyle(scale: 0.94))
      .accessibilityLabel(player.isPlaying ? "Parar o disco" : "Iniciar o disco")

      PitchSlider(value: $pitch) { v in
        player.setVarispeed(Float(1 + v * 0.08))
      }
      .frame(minWidth: 80)
    }
    .glassGroup(spacing: 8)
  }

  // MARK: painel de estilos

  private var orbPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      StageSegmented(items: [(true, "3D Estúdio"), (false, "Vista Topo")], selection: store.turntable3D) { v in
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { store.turntable3D = v }
      }

      StageSectionHeader(title: "MESA", trailing: store.turntableFinish.rawValue)
      HStack(spacing: 0) {
        ForEach(TurntableFinish.allCases) { f in
          StageSwatch(selected: store.turntableFinish == f, label: f.rawValue) {
            Image(uiImage: LumeTextures.surfaceImage(styleId: Int(f.shaderIndex)))
              .resizable().scaledToFill()
          } action: {
            withAnimation(.easeInOut(duration: 0.3)) { store.turntableFinish = f }
          }
          .frame(maxWidth: .infinity)
        }
      }

      StageSectionHeader(title: "VINIL", trailing: store.vinylEdition.rawValue)
      HStack(spacing: 0) {
        ForEach(VinylEdition.allCases) { e in
          StageSwatch(selected: store.vinylEdition == e, label: e.rawValue) {
            vinylSwatch(e)
          } action: {
            withAnimation(.easeInOut(duration: 0.3)) { store.vinylEdition = e }
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
    .padding(.bottom, 4)
  }

  @ViewBuilder
  private func vinylSwatch(_ e: VinylEdition) -> some View {
    switch e {
    case .classicBlack:
      RadialGradient(colors: [Color(white: 0.30), Color(white: 0.06)], center: .topLeading, startRadius: 0, endRadius: 40)
    case .prismCrystal:
      AngularGradient(colors: [.pink, .orange, .yellow, .mint, .cyan, .purple, .pink], center: .center)
    case .limitedGold:
      RadialGradient(colors: [Color(red: 0.98, green: 0.82, blue: 0.40), Color(red: 0.58, green: 0.38, blue: 0.10)], center: .topLeading, startRadius: 0, endRadius: 40)
    case .whiteMarble:
      RadialGradient(colors: [.white, Color(white: 0.78)], center: .topLeading, startRadius: 0, endRadius: 40)
    }
  }
}

// MARK: - Doca: velocidade, pitch

private struct SpeedPicker: View {
  @Binding var rpm45: Bool
  @Namespace private var ns

  var body: some View {
    HStack(spacing: 2) {
      seg("33⅓", active: !rpm45) { rpm45 = false }
      seg("45", active: rpm45) { rpm45 = true }
    }
    .padding(3)
    .glassCapsule()
  }

  private func seg(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
    Button {
      guard !active else { return }
      Haptics.rigid()
      withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { action() }
    } label: {
      Text(title)
        .font(Theme.font(14, .bold))
        .foregroundStyle(active ? Theme.onPrism : Theme.text)
        .frame(width: 48, height: 44)
        .background {
          if active { Capsule().fill(Theme.prismDiagonal).matchedGeometryEffect(id: "speed", in: ns) }
        }
        .contentShape(Capsule())
    }
    .buttonStyle(PressableStyle(scale: 0.94))
    .accessibilityLabel("\(title) rotações por minuto")
    .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
  }
}

private struct PitchSlider: View {
  @Binding var value: Double
  let onChange: (Double) -> Void

  var body: some View {
    GeometryReader { g in
      let pad: CGFloat = 18
      let trackW = max(1, g.size.width - pad * 2)
      let x = pad + CGFloat((value + 1) / 2) * trackW
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.18)).frame(height: 4).padding(.horizontal, pad)
        Capsule().fill(Theme.prismDiagonal)
          .frame(width: abs(x - (pad + trackW / 2)), height: 4)
          .offset(x: min(x, pad + trackW / 2))
        Rectangle().fill(Color.white.opacity(0.55)).frame(width: 1.5, height: 12).offset(x: pad + trackW / 2 - 0.75)
        Circle()
          .fill(Color.white)
          .frame(width: 22, height: 22)
          .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
          .offset(x: x - 11)
      }
      .frame(maxHeight: .infinity, alignment: .bottom)
      .padding(.bottom, 8)
      .overlay(alignment: .top) {
        Text(String(format: "PITCH %+.1f%%", value * 8))
          .font(Theme.font(10.5, .heavy))
          .tracking(0.4)
          .monospacedDigit()
          .foregroundStyle(abs(value) < 0.02 ? Theme.secondary : Theme.accent)
          .padding(.top, 5)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { v in
            var nv = Double((v.location.x - pad) / trackW) * 2 - 1
            nv = min(1, max(-1, nv))
            if abs(nv) < 0.07 { nv = 0 }
            if (nv == 0) != (value == 0) { Haptics.rigid() }
            value = nv
            onChange(nv)
          }
      )
      .simultaneousGesture(
        TapGesture(count: 2).onEnded {
          Haptics.medium()
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { value = 0 }
          onChange(0)
        }
      )
    }
    .frame(height: 44)
    .glassCapsule()
    .accessibilityElement()
    .accessibilityLabel("Ajuste de velocidade")
    .accessibilityValue(String(format: "%+.1f por cento", value * 8))
    .accessibilityAdjustableAction { dir in
      let nv = min(1, max(-1, value + (dir == .increment ? 0.125 : -0.125)))
      value = abs(nv) < 0.05 ? 0 : nv
      onChange(value)
    }
  }
}

// MARK: - Deck

struct TurntableDeck: View {
  let height: CGFloat
  let artworkURL: String
  let isPlaying: Bool
  let progress: Double
  var finish: TurntableFinish = .obsidian
  var edition: VinylEdition = .classicBlack
  var is3D: Bool = true
  var rpm45: Bool = false
  var pitch: Double = 0

  @Environment(\.displayScale) private var displayScale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject private var gov = PerfGovernor.shared
  @State private var baseImage: UIImage?
  @State private var recordImage: UIImage?
  @State private var spin = SpinModel()
  @State private var spinActive = false
  @State private var scratching = false
  @State private var scratchDelta: Double = 0
  @State private var scratchLast: Double?
  @State private var armAngle: Double = DeckGeo.restAngle
  @State private var armLift: Double = 1
  @State private var armTask: Task<Void, Never>?

  private var H: CGFloat { height }
  private var W: CGFloat { height * DeckGeo.aspect }
  private var platterPx: Int { Int((H * DeckGeo.platterD * displayScale / 2).rounded()) * 2 }
  private var basePx: Int { Int((W * displayScale).rounded()) }
  private var degPerSec: Double { (rpm45 ? 45 : 33.3333) * 6 * (1 + pitch * 0.08) }
  private var spinTarget: Double { (isPlaying && !scratching && !reduceMotion) ? degPerSec : 0 }
  private var loadKey: String { "\(finish.rawValue)|\(edition.rawValue)|\(is3D)|\(platterPx)|\(basePx)" }

  var body: some View {
    let arm = LumeTextures.shared.armImages()
    ZStack(alignment: .topLeading) {
      baseLayer
      lampGlow
      discLayer
      sheenLayer
      spindle
      armLayer(arm)
      pitchKnob
      if scratching { scratchBadge }
    }
    .frame(width: W, height: H, alignment: .topLeading)
    .task(id: loadKey) { await load() }
    .onAppear {
      spinActive = isPlaying && !reduceMotion
      armAngle = isPlaying ? DeckGeo.angle(forProgress: progress) : DeckGeo.restAngle
      armLift = isPlaying ? 0 : 1
    }
    .task(id: isPlaying) {
      if isPlaying {
        spinActive = !reduceMotion
      } else {
        // espera o prato parar por inércia e então desliga o relógio (nada roda com a música pausada)
        try? await Task.sleep(for: .seconds(2.8))
        if !Task.isCancelled && !scratching { spinActive = false }
      }
    }
    .onChange(of: isPlaying) { _, playing in moveArm(playing) }
    .onChange(of: progress) { _, _ in
      if isPlaying && armLift == 0 && !scratching {
        withAnimation(.linear(duration: 0.5)) { armAngle = DeckGeo.angle(forProgress: progress) }
      }
    }
  }

  private func load() async {
    if let b = LumeTextures.shared.cachedDeck(finish: finish, thick: is3D, px: basePx) { baseImage = b }
    if let r = LumeTextures.shared.cachedRecord(edition: edition, px: platterPx) { recordImage = r }
    async let r = LumeTextures.shared.recordImage(edition: edition, px: platterPx)
    async let b = LumeTextures.shared.deckBase(finish: finish, thick: is3D, px: basePx)
    let (ri, bi) = await (r, b)
    guard !Task.isCancelled else { return }
    recordImage = ri
    baseImage = bi
  }

  // MARK: braço

  private func moveArm(_ playing: Bool) {
    armTask?.cancel()
    armTask = Task { @MainActor in
      if playing {
        withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 1.15)) { armAngle = DeckGeo.angle(forProgress: progress) }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 980))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.5)) { armLift = 0 }
      } else {
        withAnimation(.easeOut(duration: 0.28)) { armLift = 1 }
        try? await Task.sleep(for: .milliseconds(240))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 1.05)) { armAngle = DeckGeo.restAngle }
      }
    }
  }

  // MARK: camadas

  private var baseLayer: some View {
    let mx = DeckGeo.marginX * H, mt = DeckGeo.marginTop * H, mb = DeckGeo.marginBottom * H
    return Color.clear
      .frame(width: W, height: H)
      .overlay(alignment: .topLeading) {
        if let baseImage {
          Image(uiImage: baseImage)
            .resizable()
            .frame(width: W + 2 * mx, height: H + mt + mb)
            .offset(x: -mx, y: -mt)
            .transition(.opacity)
        }
      }
      .animation(.easeOut(duration: 0.25), value: baseImage == nil)
  }

  private var lampGlow: some View {
    ZStack {
      Circle().fill(RadialGradient(colors: [Theme.peach.opacity(0.85), Theme.peach.opacity(0)], center: .center, startRadius: 0, endRadius: H * 0.09))
        .frame(width: H * 0.18, height: H * 0.18)
      Circle().fill(Color(red: 1, green: 0.85, blue: 0.7)).frame(width: H * 0.020, height: H * 0.020)
    }
    .opacity(isPlaying ? 1 : 0)
    .animation(.easeInOut(duration: 0.5), value: isPlaying)
    .position(x: 1.17 * H, y: 0.80 * H)
    .allowsHitTesting(false)
  }

  private var discLayer: some View {
    let D = DeckGeo.platterD * H
    let labelD = DeckGeo.labelD * H
    let c = CGPoint(x: DeckGeo.platterC.x * H, y: DeckGeo.platterC.y * H)
    return TimelineView(.animation(minimumInterval: gov.frameInterval, paused: !gov.isActive || (!spinActive && !scratching))) { tl in
      let a = spin.step(now: tl.date.timeIntervalSinceReferenceDate, target: spinTarget)
      ZStack {
        if let recordImage {
          Image(uiImage: recordImage).resizable().frame(width: D, height: D)
        }
        VinylLabel(diameter: labelD, artworkURL: artworkURL, rpmText: rpm45 ? "LADO A · 45 RPM" : "LADO A · 33⅓ RPM")
      }
      .rotationEffect(.degrees(a))
    }
    .frame(width: D, height: D)
    .contentShape(Circle())
    .gesture(scratchGesture(diameter: D))
    .onTapGesture {
      Haptics.medium()
      AudioPlayer.shared.togglePlayPause()
    }
    .position(c)
    .accessibilityLabel("Disco")
    .accessibilityHint("Toque para tocar ou pausar. Arraste em círculo para avançar ou voltar.")
    .accessibilityAddTraits(.isButton)
  }

  private var sheenLayer: some View {
    Image(uiImage: LumeTextures.shared.vinylSheen(prism: edition == .prismCrystal))
      .resizable()
      .frame(width: DeckGeo.recordD * H, height: DeckGeo.recordD * H)
      .position(x: DeckGeo.platterC.x * H, y: DeckGeo.platterC.y * H)
      .allowsHitTesting(false)
  }

  private var spindle: some View {
    let d = H * 0.030
    return ZStack {
      Circle().fill(RadialGradient(colors: [Color(white: 1), Color(white: 0.62), Color(white: 0.22)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.7))
      Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.6)
    }
    .frame(width: d, height: d)
    .shadow(color: .black.opacity(0.5), radius: 1.2, y: 1)
    .position(x: DeckGeo.platterC.x * H, y: DeckGeo.platterC.y * H)
    .allowsHitTesting(false)
  }

  private func armLayer(_ imgs: (arm: UIImage, shadow: UIImage)) -> some View {
    let aw = LumeTextures.armCanvas.width * H
    let ah = LumeTextures.armCanvas.height * H
    let anchor = UnitPoint(x: LumeTextures.armPivot.x / LumeTextures.armCanvas.width, y: LumeTextures.armPivot.y / LumeTextures.armCanvas.height)
    let cx = DeckGeo.pivot.x * H
    let cy = DeckGeo.pivot.y * H + (ah / 2 - LumeTextures.armPivot.y * H)
    return ZStack {
      Image(uiImage: imgs.shadow)
        .resizable()
        .frame(width: aw, height: ah)
        .opacity(0.55 - 0.22 * armLift)
        .rotationEffect(.degrees(armAngle), anchor: anchor)
        .offset(x: H * (0.010 + 0.034 * armLift), y: H * (0.014 + 0.046 * armLift))
      Image(uiImage: imgs.arm)
        .resizable()
        .frame(width: aw, height: ah)
        .scaleEffect(1 + 0.045 * armLift, anchor: anchor)
        .rotationEffect(.degrees(armAngle), anchor: anchor)
    }
    .position(x: cx, y: cy)
    .allowsHitTesting(false)
  }

  private var pitchKnob: some View {
    let r: CGFloat = H * 0.008
    let knobShape = RoundedRectangle(cornerRadius: r, style: .continuous)
    let fillGrad = LinearGradient(colors: [Color(white: 0.40), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
    let knobY: CGFloat = (0.57 + 0.144 * CGFloat(pitch)) * H
    return ZStack {
      knobShape.fill(fillGrad)
      Rectangle().fill(Theme.rose).frame(height: 1.3)
      knobShape.stroke(Color.white.opacity(0.35), lineWidth: 0.6)
    }
    .frame(width: H * 0.062, height: H * 0.032)
    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1.5)
    .position(x: 1.395 * H, y: knobY)
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pitch)
    .allowsHitTesting(false)
  }

  private var scratchBadge: some View {
    let secs = scratchDelta / degPerSec
    return Text((secs >= 0 ? "+" : "−") + String(format: "%.1fs", abs(secs)) + "  ·  " + Theme.formatTime(max(0, AudioPlayer.shared.currentTime + secs)))
      .font(Theme.font(13, .semibold))
      .monospacedDigit()
      .foregroundStyle(Theme.text)
      .padding(.horizontal, 14)
      .frame(height: 34)
      .glassCapsule()
      .position(x: DeckGeo.platterC.x * H, y: H * 0.06)
      .transition(.opacity.combined(with: .scale(scale: 0.9)))
  }

  // MARK: scratch

  private func scratchGesture(diameter D: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 10)
      .onChanged { v in
        let ang = atan2(Double(v.location.y - D / 2), Double(v.location.x - D / 2)) * 180 / .pi
        if let last = scratchLast {
          var d = ang - last
          if d > 180 { d -= 360 }
          if d < -180 { d += 360 }
          let before = Int(scratchDelta / 20)
          scratchDelta += d
          spin.angle += d
          if Int(scratchDelta / 20) != before { Haptics.soft() }
        } else {
          spinActive = true
          withAnimation(.easeOut(duration: 0.15)) { scratching = true }
        }
        scratchLast = ang
      }
      .onEnded { _ in
        let secs = scratchDelta / degPerSec
        if abs(secs) > 0.2 { AudioPlayer.shared.seek(to: max(0, AudioPlayer.shared.currentTime + secs)) }
        scratchDelta = 0
        scratchLast = nil
        withAnimation(.easeOut(duration: 0.25)) { scratching = false }
        if !isPlaying { Task { try? await Task.sleep(for: .milliseconds(300)); if !isPlaying && !scratching { spinActive = false } } }
      }
  }
}

/// Física do prato (referência mutável, zero churn no SwiftUI): aceleração e desaceleração lineares com inércia.
final class SpinModel {
  var angle: Double = 0
  private(set) var velocity: Double = 0
  private var last: Double = 0

  func step(now: Double, target: Double) -> Double {
    let dt = last == 0 ? 0 : min(0.1, max(0, now - last))
    last = now
    if velocity < target {
      velocity = min(target, velocity + 320 * dt)
    } else if velocity > target {
      velocity = max(target, velocity - 130 * dt)
    }
    angle += velocity * dt
    if angle > 360_000 || angle < -360_000 { angle = angle.truncatingRemainder(dividingBy: 360) }
    return angle
  }
}

// MARK: - Selo do disco (papel com a capa)

struct VinylLabel: View {
  let diameter: CGFloat
  let artworkURL: String
  let rpmText: String

  var body: some View {
    let D = diameter
    ZStack {
      ArtworkImage(url: artworkURL, cornerRadius: D / 2, maxPixel: 500)
        .frame(width: D, height: D)
        .clipShape(Circle())
      // véu de papel: dá a leitura de selo impresso, não de foto colada
      Circle().fill(RadialGradient(colors: [.clear, .clear, .black.opacity(0.30)], center: .center, startRadius: 0, endRadius: D / 2))
      Circle().fill(LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
      Circle().stroke(Color.black.opacity(0.28), lineWidth: max(0.6, D * 0.006)).frame(width: D * 0.62, height: D * 0.62)
      Circle().stroke(Color.white.opacity(0.22), lineWidth: max(0.5, D * 0.004)).frame(width: D * 0.92, height: D * 0.92)
      Circle().stroke(Color.black.opacity(0.7), lineWidth: max(1, D * 0.012))
      Text(rpmText)
        .font(.system(size: max(5, D * 0.062), weight: .heavy, design: .rounded))
        .tracking(0.6)
        .foregroundStyle(.white.opacity(0.92))
        .shadow(color: .black.opacity(0.8), radius: 1.5)
        .offset(y: D * 0.33)
      Text("STEREO")
        .font(.system(size: max(4.5, D * 0.050), weight: .heavy, design: .rounded))
        .tracking(1.2)
        .foregroundStyle(.white.opacity(0.8))
        .shadow(color: .black.opacity(0.8), radius: 1.5)
        .offset(y: -D * 0.33)
      Circle().fill(Color(white: 0.08)).frame(width: D * 0.075, height: D * 0.075)
    }
    .frame(width: D, height: D)
  }
}

/// Prévia compacta reutilizada em SettingsView (estática).
struct RecordDisc: View {
  let side: CGFloat
  let artworkURL: String
  var edition: VinylEdition = .classicBlack

  @Environment(\.displayScale) private var displayScale
  @State private var image: UIImage?

  var body: some View {
    let D = side * 0.83
    let px = Int((D * displayScale / 2).rounded()) * 2
    ZStack {
      if let image { Image(uiImage: image).resizable().frame(width: D, height: D) }
      VinylLabel(diameter: D * DeckGeo.labelD / DeckGeo.platterD, artworkURL: artworkURL, rpmText: "LADO A · 33⅓ RPM")
      Image(uiImage: LumeTextures.shared.vinylSheen(prism: edition == .prismCrystal))
        .resizable()
        .frame(width: D * DeckGeo.recordD / DeckGeo.platterD, height: D * DeckGeo.recordD / DeckGeo.platterD)
    }
    .frame(width: D, height: D)
    .task(id: "\(edition.rawValue)|\(px)") {
      if let hit = LumeTextures.shared.cachedRecord(edition: edition, px: px) { image = hit; return }
      image = await LumeTextures.shared.recordImage(edition: edition, px: px)
    }
  }
}
