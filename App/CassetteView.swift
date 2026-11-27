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

/// Posição "ao vivo" da fita: extrapola o relógio entre as atualizações do player.
struct CassetteLive {
  var playing: Bool
  var anchorTime: Double
  var anchorDate: Date
  var duration: Double

  func progress(at date: Date) -> Double {
    guard duration > 1 else { return 0 }
    let t = playing ? anchorTime + date.timeIntervalSince(anchorDate) : anchorTime
    return min(1, max(0, t / duration))
  }
}

// MARK: - Palco "K7"

struct CassetteStage: View {
  let track: Track
  @ObservedObject private var player = AudioPlayer.shared
  @ObservedObject private var clock = PlaybackClock.shared
  @ObservedObject private var art = ArtworkStore.shared
  @ObservedObject private var store = LibraryStore.shared
  @Environment(\.displayScale) private var displayScale

  @State private var sideB = false
  @State private var anchorTime: Double = 0
  @State private var anchorDate = Date()

  var body: some View {
    GeometryReader { g in
      let dockH: CGFloat = 44
      let availH = max(150, g.size.height - dockH - 40)
      let W = min(g.size.width - 28, availH * TapeGeo.aspect, 420)
      ZStack {
        VStack(spacing: 18) {
          Spacer(minLength: 0)
          freeCassette(W)
          dock
            .padding(.trailing, 52)
            .padding(.horizontal, 14)
            .frame(height: dockH)
        }
        .padding(.bottom, 8)
        .frame(width: g.size.width, height: g.size.height)

        StageStyleOrb(icon: "recordingtape", accessibilityLabel: "Estilo da fita K7", title: nil, placement: .bottomTrailing) { _ in
          VStack(alignment: .leading, spacing: 8) {
            StageSectionHeader(title: "FITA", trailing: store.cassetteStyle.rawValue)
            ForEach(CassetteStyle.allCases) { st in
              StageOptionRow(title: st.rawValue, subtitle: subtitle(for: st), selected: store.cassetteStyle == st) {
                Circle().fill(swatch(for: st)).overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 0.8))
              } action: {
                withAnimation(.easeInOut(duration: 0.3)) { store.cassetteStyle = st }
              }
            }
          }
          .padding(.bottom, 4)
        }
      }
    }
    .onAppear { anchor() }
    .onChange(of: clock.currentTime) { _, _ in anchor() }
    .onChange(of: player.isPlaying) { _, _ in anchor() }
    .onChange(of: track.id) { _, _ in sideB = false }
    .task(id: store.cassetteStyle) {
      // aquece o outro lado para o flip não piscar
      let px = Int(380 * displayScale)
      _ = await LumeTextures.shared.cassette(style: store.cassetteStyle, sideB: true, px: px)
    }
  }

  private func anchor() {
    anchorTime = clock.currentTime
    anchorDate = Date()
  }

  private func subtitle(for style: CassetteStyle) -> String {
    switch style {
    case .smokedStudio: return "Plástico fumê, engrenagens à vista"
    case .crystalClear: return "Transparente, mecanismo visível"
    case .metallicChrome: return "Cromo Tipo II, acabamento espelhado"
    case .vintageCream: return "Creme dos anos 80"
    }
  }

  private func swatch(for style: CassetteStyle) -> LinearGradient {
    switch style {
    case .smokedStudio: return LinearGradient(colors: [Color(white: 0.34), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
    case .crystalClear: return LinearGradient(colors: [Color(red: 0.85, green: 0.93, blue: 0.97), Color(red: 0.55, green: 0.68, blue: 0.78)], startPoint: .top, endPoint: .bottom)
    case .metallicChrome: return LinearGradient(colors: [Color(white: 0.95), Color(white: 0.45)], startPoint: .top, endPoint: .bottom)
    case .vintageCream: return LinearGradient(colors: [Color(red: 0.96, green: 0.92, blue: 0.80), Color(red: 0.80, green: 0.72, blue: 0.56)], startPoint: .top, endPoint: .bottom)
    }
  }

  // MARK: fita em primeiro plano

  private func freeCassette(_ W: CGFloat) -> some View {
    let live = CassetteLive(playing: player.isPlaying, anchorTime: anchorTime, anchorDate: anchorDate, duration: max(1, clock.duration))
    let seconds = max(1, clock.duration)
    return CassetteFlipWrapper(angle: sideB ? 180 : 0) {
      CassetteTape(width: W, title: track.title, artist: track.artist, artworkURL: player.currentArtwork,
                   sideB: false, progress: 0, seconds: seconds, style: store.cassetteStyle, live: live)
    } back: {
      CassetteTape(width: W, title: track.title, artist: track.artist, artworkURL: art.photo(for: track.artist) ?? player.currentArtwork,
                   sideB: true, progress: 0, seconds: seconds, style: store.cassetteStyle, live: live)
    }
    .frame(width: W, height: W / TapeGeo.aspect)
    .contentShape(Rectangle())
    .onTapGesture { Haptics.medium(); player.togglePlayPause() }
    .accessibilityElement()
    .accessibilityLabel("Fita K7")
    .accessibilityHint("Toque para tocar ou pausar")
    .accessibilityAddTraits(.isButton)
  }

  // MARK: doca

  private var dock: some View {
    HStack(spacing: 8) {
      Button {
        Haptics.medium()
        Task { await ArtworkStore.shared.ensurePhoto(track.artist) }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) { sideB.toggle() }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .semibold))
          Text(sideB ? "Lado A" : "Lado B").font(Theme.font(13.5, .semibold))
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14)
        .frame(minWidth: 108, minHeight: 44)
        .contentShape(Capsule())
        .glassCapsule(interactive: true)
      }
      .buttonStyle(PressableStyle(scale: 0.94))
      .accessibilityLabel(sideB ? "Virar para o lado A" : "Virar para o lado B")

      VUDock()
        .frame(minWidth: 100)
    }
    .glassGroup(spacing: 8)
  }
}

/// Dois VUs analógicos discretos. Observa o espectro só aqui (e só com a música tocando), sem refazer o palco inteiro.
private struct VUDock: View {
  @ObservedObject private var player = AudioPlayer.shared
  @State private var phys = VUBallistics()
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    GeometryReader { g in
      let w = min(64, (g.size.width - 30) / 2)
      let face = LumeTextures.shared.vuFace(px: Int(w * displayScale))
      TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !player.isPlaying)) { tl in
        let raw = levels(at: tl.date)
        let s = phys.step(now: tl.date.timeIntervalSinceReferenceDate, targetL: raw.0, targetR: raw.1)
        HStack(spacing: 10) {
          dial(face, w: w, level: s.0)
          dial(face, w: w, level: s.1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(height: 44)
    .glassCapsule()
    .accessibilityHidden(true)
  }

  private func dial(_ face: UIImage, w: CGFloat, level: Double) -> some View {
    let h = w * 0.62
    return ZStack {
      Image(uiImage: face).resizable().frame(width: w, height: h)
      Capsule()
        .fill(Color.black.opacity(0.85))
        .frame(width: 1.3, height: h * 0.80)
        .rotationEffect(.degrees(-48 + 96 * min(1, max(0, level))), anchor: .bottom)
        .position(x: w / 2, y: h - h * 0.40)
      Circle().fill(Color.black.opacity(0.85)).frame(width: h * 0.10).position(x: w / 2, y: h * 0.99)
      Circle()
        .fill(level > 0.84 ? Color.red : Color.red.opacity(0.2))
        .frame(width: h * 0.09)
        .position(x: w * 0.88, y: h * 0.84)
    }
    .frame(width: w, height: h)
    .clipShape(RoundedRectangle(cornerRadius: h * 0.16, style: .continuous))
  }

  private func levels(at date: Date) -> (Double, Double) {
    let sp = AudioSpectrum.shared
    if sp.isLive {
      let b = sp.bands
      let half = max(1, b.count / 2)
      let low = b.prefix(half).reduce(0, +) / Float(half)
      let high = b.suffix(half).reduce(0, +) / Float(half)
      let l = 0.06 + Double(sp.level) * 0.58 + Double(low) * 0.22
      let r = 0.06 + Double(sp.level) * 0.58 + Double(high) * 0.26
      return (min(1, l), min(1, r))
    }
    guard player.isPlaying else { return (0, 0) }
    let t = date.timeIntervalSinceReferenceDate
    let base = 0.55 + 0.20 * sin(t * 2.3) * cos(t * 0.7)
    let l = base + 0.16 * sin(t * 9.1) + 0.08 * sin(t * 17.3)
    let r = base + 0.16 * sin(t * 8.3 + 1) + 0.08 * cos(t * 15.1)
    return (min(1, max(0, l)), min(1, max(0, r)))
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

/// Estado dos carretéis (ângulos acumulados), mutável sem refazer a view.
final class ReelState {
  var aL: Double = 0
  var aR: Double = 0
  private var last: Double = 0
  func step(now: Double, rL: CGFloat, rR: CGFloat, animate: Bool) -> (Double, Double) {
    let dt = last == 0 ? 0 : min(0.1, max(0, now - last))
    last = now
    if animate {
      // velocidade linear da fita constante: ω = k / raio (carretel cheio gira mais devagar)
      aL -= 14.0 / Double(max(0.03, rL)) * dt
      aR -= 14.0 / Double(max(0.03, rR)) * dt
    }
    return (aL, aR)
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
  var live: CassetteLive? = nil

  @Environment(\.displayScale) private var displayScale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var layers: CassetteLayers?
  @State private var reels = ReelState()

  private var px: Int { Int((width * displayScale).rounded()) }

  var body: some View {
    let w = width
    let h = w / TapeGeo.aspect
    let L = layers ?? LumeTextures.shared.cachedCassette(style: style, sideB: sideB, px: px)
    let parts = LumeTextures.shared.tapeParts()
    ZStack {
      if let L {
        Image(uiImage: L.shadow)
          .resizable()
          .frame(width: w * (1 + 2 * TapeGeo.shadowMarginX), height: h + w * (TapeGeo.shadowMarginTop + TapeGeo.shadowMarginBottom))
          .offset(y: w * (TapeGeo.shadowMarginBottom - TapeGeo.shadowMarginTop) / 2)
          .allowsHitTesting(false)
        Image(uiImage: L.back).resizable().frame(width: w, height: h)
        reelLayer(w: w, h: h, parts: parts)
        Image(uiImage: L.front).resizable().frame(width: w, height: h)
        labelText(w: w)
      } else {
        RoundedRectangle(cornerRadius: w * 0.034, style: .continuous).fill(Color.white.opacity(0.08)).frame(width: w, height: h)
      }
    }
    .frame(width: w, height: h)
    .task(id: "\(style.rawValue)|\(sideB)|\(px)") {
      if let hit = LumeTextures.shared.cachedCassette(style: style, sideB: sideB, px: px) { layers = hit; return }
      layers = await LumeTextures.shared.cassette(style: style, sideB: sideB, px: px)
    }
  }

  // MARK: carretéis (única parte que anima)

  @ViewBuilder
  private func reelLayer(w: CGFloat, h: CGFloat, parts: (hub: UIImage, pack: UIImage)) -> some View {
    if let live {
      TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0, paused: !live.playing)) { tl in
        reelsView(p: live.progress(at: tl.date), now: tl.date.timeIntervalSinceReferenceDate, w: w, h: h, parts: parts, animate: live.playing && !reduceMotion)
      }
    } else {
      reelsView(p: progress, now: 0, w: w, h: h, parts: parts, animate: false)
    }
  }

  private func reelsView(p: Double, now: Double, w: CGFloat, h: CGFloat, parts: (hub: UIImage, pack: UIImage), animate: Bool) -> some View {
    let a = TapeGeo.rFull * TapeGeo.rFull - TapeGeo.rEmpty * TapeGeo.rEmpty
    let q = CGFloat(min(1, max(0, p)))
    let rL = sqrt(TapeGeo.rFull * TapeGeo.rFull - q * a)
    let rR = sqrt(TapeGeo.rEmpty * TapeGeo.rEmpty + q * a)
    let ang = animate ? reels.step(now: now, rL: rL, rR: rR, animate: true) : (reels.aL, reels.aR)
    let cL = CGPoint(x: TapeGeo.reelL.x * w, y: TapeGeo.reelL.y * w)
    let cR = CGPoint(x: TapeGeo.reelR.x * w, y: TapeGeo.reelR.y * w)
    return ZStack {
      tapePath(w: w, rL: rL, rR: rR)
        .stroke(Color(red: 0.30, green: 0.18, blue: 0.10), style: StrokeStyle(lineWidth: max(1, w * 0.0055), lineCap: .round))
      Image(uiImage: parts.pack).resizable()
        .frame(width: TapeGeo.rFull * 2 * w, height: TapeGeo.rFull * 2 * w)
        .scaleEffect(rL / TapeGeo.rFull)
        .position(cL)
      Image(uiImage: parts.pack).resizable()
        .frame(width: TapeGeo.rFull * 2 * w, height: TapeGeo.rFull * 2 * w)
        .scaleEffect(rR / TapeGeo.rFull)
        .position(cR)
      Image(uiImage: parts.hub).resizable()
        .frame(width: TapeGeo.hubR * 2 * w, height: TapeGeo.hubR * 2 * w)
        .rotationEffect(.degrees(ang.0))
        .position(cL)
      Image(uiImage: parts.hub).resizable()
        .frame(width: TapeGeo.hubR * 2 * w, height: TapeGeo.hubR * 2 * w)
        .rotationEffect(.degrees(ang.1))
        .position(cR)
    }
    .frame(width: w, height: h)
    .allowsHitTesting(false)
  }

  /// Fita saindo de cada rolo (tangente) até os roletes guia e esticada na borda inferior.
  private func tapePath(w: CGFloat, rL: CGFloat, rR: CGFloat) -> Path {
    func tangent(from p: CGPoint, center c: CGPoint, r: CGFloat, outerSign: CGFloat) -> CGPoint {
      let dx = p.x - c.x, dy = p.y - c.y
      let d = max(r + 0.001, hypot(dx, dy))
      let beta = atan2(dy, dx)
      let alpha = acos(min(1, r / d))
      let t = beta + outerSign * alpha
      return CGPoint(x: c.x + r * cos(t), y: c.y + r * sin(t))
    }
    let rolL = TapeGeo.rollerL, rolR = TapeGeo.rollerR
    let tL = tangent(from: CGPoint(x: rolL.x - 0.016, y: rolL.y), center: TapeGeo.reelL, r: rL, outerSign: 1)
    let tR = tangent(from: CGPoint(x: rolR.x + 0.016, y: rolR.y), center: TapeGeo.reelR, r: rR, outerSign: -1)
    var p = Path()
    p.move(to: CGPoint(x: tL.x * w, y: tL.y * w))
    p.addLine(to: CGPoint(x: (rolL.x - 0.016) * w, y: rolL.y * w))
    p.move(to: CGPoint(x: tR.x * w, y: tR.y * w))
    p.addLine(to: CGPoint(x: (rolR.x + 0.016) * w, y: rolR.y * w))
    return p
  }

  // MARK: escrita à mão na etiqueta

  private func handFont(_ size: CGFloat) -> Font {
    UIFont(name: "BradleyHandITCTT-Bold", size: size) != nil ? .custom("BradleyHandITCTT-Bold", size: size) : .custom("Noteworthy-Bold", size: size)
  }

  private func labelText(w: CGFloat) -> some View {
    let main = sideB ? artist : title
    let sub = sideB ? title : artist
    return ZStack {
      Text(main)
        .font(handFont(w * 0.054))
        .foregroundStyle(Color(red: 0.10, green: 0.14, blue: 0.46))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(width: w * 0.69, alignment: .leading)
        .rotationEffect(.degrees(-0.7))
        .position(x: w * (0.085 + 0.345), y: w * 0.133)
      Text(sub)
        .font(handFont(w * 0.040))
        .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.40).opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(width: w * 0.69, alignment: .leading)
        .rotationEffect(.degrees(-0.5))
        .position(x: w * (0.085 + 0.345), y: w * 0.172)
      ArtworkImage(url: artworkURL, cornerRadius: w * 0.004, maxPixel: 220, placeholderIcon: sideB ? "person.fill" : "music.note")
        .frame(width: w * 0.078, height: w * 0.078)
        .position(x: w * 0.873, y: w * 0.147)
    }
    // Mesmo quadro dos carretéis: sem ele as posições ficavam relativas ao quadro maior da sombra
    // e o título/capa escapavam para fora da etiqueta (canto superior esquerdo).
    .frame(width: w, height: w / TapeGeo.aspect)
    .allowsHitTesting(false)
  }
}
