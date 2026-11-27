import SwiftUI
import UIKit

// MARK: - Geometria do toca-discos (unidade = altura do deck)

/// Todas as medidas do deck em "u" (altura do deck = 1.0). A largura é `aspect` u.
enum DeckGeo {
  static let aspect: CGFloat = 1.45
  static let platterC = CGPoint(x: 0.505, y: 0.5)
  static let platterD: CGFloat = 0.92
  static let recordD: CGFloat = 0.855
  static let labelD: CGFloat = 0.29
  static let pivot = CGPoint(x: 1.30, y: 0.20)
  static let armL: CGFloat = 0.74
  static let restAngle: Double = 24
  static let rOuter: CGFloat = 0.405
  static let rInner: CGFloat = 0.195
  /// Margens da imagem de base (sombra + espessura do chassi), em u.
  static let marginX: CGFloat = 0.07
  static let marginTop: CGFloat = 0.035
  static let marginBottom: CGFloat = 0.13
  static let thickness: CGFloat = 0.035

  /// Posição (em u) do apoio do braço.
  static var restPost: CGPoint {
    let a = restAngle * .pi / 180
    let d = armL * 0.66
    return CGPoint(x: pivot.x - d * CGFloat(sin(a)), y: pivot.y + d * CGFloat(cos(a)))
  }

  /// Ângulo do braço (graus, horário) para a agulha cair a `r` u do centro do prato (lei dos cossenos).
  static func armAngle(forRadius r: CGFloat) -> Double {
    let dx = Double(pivot.x - platterC.x)
    let dy = Double(platterC.y - pivot.y)
    let d = hypot(dx, dy)
    let L = Double(armL)
    let phi = atan2(dx, dy)
    let c = min(1.0, max(-1.0, (d * d + L * L - Double(r * r)) / (2 * d * L)))
    return (phi - acos(c)) * 180 / .pi
  }

  static func angle(forProgress p: Double) -> Double {
    let q = CGFloat(min(1, max(0, p)))
    return armAngle(forRadius: rOuter + (rInner - rOuter) * q)
  }
}

// MARK: - Geometria da fita K7 (unidade = largura da fita)

enum TapeGeo {
  static let aspect: CGFloat = 1.574
  static let reelL = CGPoint(x: 0.315, y: 0.288)
  static let reelR = CGPoint(x: 0.685, y: 0.288)
  static let rEmpty: CGFloat = 0.041
  static let rFull: CGFloat = 0.084
  static let hubR: CGFloat = 0.036
  static let rollerL = CGPoint(x: 0.262, y: 0.592)
  static let rollerR = CGPoint(x: 0.738, y: 0.592)
  static let labelRect = CGRect(x: 0.055, y: 0.045, width: 0.89, height: 0.352)
  static let windowRect = CGRect(x: 0.185, y: 0.198, width: 0.63, height: 0.180)
}

// MARK: - Cache e geração de texturas

/// Texturas procedurais pesadas (prato, disco, base do deck, braço, fita K7) desenhadas UMA vez em CoreGraphics,
/// guardadas em cache e só giradas/transladadas pelo SwiftUI. Nada é redesenhado por frame.
final class LumeTextures: @unchecked Sendable {
  static let shared = LumeTextures()

  private let lock = NSLock()
  private var store: [String: UIImage] = [:]
  private var order: [String] = []
  private var didPrewarm = false

  private static let cacheDir: URL? = {
    guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    let dir = base.appendingPathComponent("LumeTextures", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()

  private init() {}

  // MARK: cache

  private func get(_ key: String) -> UIImage? {
    lock.lock(); defer { lock.unlock() }
    return store[key] ?? pinned[key]
  }

  private var pinned: [String: UIImage] = [:]

  private func put(_ key: String, _ img: UIImage, limit: Int = 14, pin: Bool = false) {
    lock.lock(); defer { lock.unlock() }
    if pin { pinned[key] = img; return }
    if store[key] == nil { order.append(key) }
    store[key] = img
    while order.count > limit {
      let old = order.removeFirst()
      store[old] = nil
    }
  }

  // MARK: API pública

  func cachedRecord(edition: VinylEdition, px: Int) -> UIImage? { get("rec_\(edition.rawValue)_\(px)") }

  func recordImage(edition: VinylEdition, px: Int) async -> UIImage {
    let key = "rec_\(edition.rawValue)_\(px)"
    if let hit = get(key) { return hit }
    let img = await Task.detached(priority: .userInitiated) { Self.renderRecord(edition: edition, px: px) }.value
    put(key, img)
    return img
  }

  func cachedDeck(finish: TurntableFinish, thick: Bool, px: Int) -> UIImage? { get("deck_\(finish.rawValue)_\(thick)_\(px)") }

  func deckBase(finish: TurntableFinish, thick: Bool, px: Int) async -> UIImage {
    let key = "deck_\(finish.rawValue)_\(thick)_\(px)"
    if let hit = get(key) { return hit }
    let img = await Task.detached(priority: .userInitiated) { Self.renderDeckBase(finish: finish, thick: thick, pxW: px) }.value
    put(key, img)
    return img
  }

  /// Reflexo anisotrópico "gravata borboleta" (luz parada por cima do disco).
  func vinylSheen(prism: Bool) -> UIImage {
    let key = "sheen_\(prism)"
    if let hit = get(key) { return hit }
    let img = Self.renderSheen(prism: prism, size: 360)
    put(key, img, pin: true)
    return img
  }

  /// Braço + sombra do braço (imagens estáticas; o SwiftUI só gira em torno do pivô).
  func armImages() -> (arm: UIImage, shadow: UIImage) {
    if let a = get("arm_v50"), let s = get("armshadow_v50") { return (a, s) }
    let (a, s) = Self.renderArm()
    put("arm_v50", a, pin: true)
    put("armshadow_v50", s, pin: true)
    return (a, s)
  }

  func cachedCassette(style: CassetteStyle, sideB: Bool, px: Int) -> CassetteLayers? {
    guard let b = get("k7b_\(style.rawValue)_\(sideB)_\(px)"), let f = get("k7f_\(style.rawValue)_\(sideB)_\(px)"),
          let s = get("k7s_\(px)") else { return nil }
    return CassetteLayers(back: b, front: f, shadow: s)
  }

  func cassette(style: CassetteStyle, sideB: Bool, px: Int) async -> CassetteLayers {
    if let hit = cachedCassette(style: style, sideB: sideB, px: px) { return hit }
    let r = await Task.detached(priority: .userInitiated) { Self.renderCassette(style: style, sideB: sideB, wpx: px) }.value
    put("k7b_\(style.rawValue)_\(sideB)_\(px)", r.back)
    put("k7f_\(style.rawValue)_\(sideB)_\(px)", r.front)
    put("k7s_\(px)", r.shadow)
    return r
  }

  /// Carretel (hub) e rolo de fita: independentes de estilo.
  func tapeParts() -> (hub: UIImage, pack: UIImage) {
    if let h = get("k7hub_v50"), let p = get("k7pack_v50") { return (h, p) }
    let h = Self.renderHub(px: 360)
    let p = Self.renderPack(px: 420)
    put("k7hub_v50", h, pin: true)
    put("k7pack_v50", p, pin: true)
    return (h, p)
  }

  func vuFace(px: Int) -> UIImage {
    let key = "vu_\(px)"
    if let hit = get(key) { return hit }
    let img = Self.renderVUFace(w: px, h: Int(Double(px) * 0.62))
    put(key, img, pin: true)
    return img
  }

  /// Gera em background o que o jogador provavelmente vai precisar e limpa caches antigos.
  @MainActor func prewarmInBackground() {
    guard !didPrewarm else { return }
    didPrewarm = true
    Task.detached(priority: .utility) {
      if let dir = Self.cacheDir, let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
        for f in files where f.contains("_v42_") { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
      }
      for styleId in 0..<4 { _ = Self.surfaceImage(styleId: styleId) }
    }
    StageDebug.bootstrapIfNeeded()
  }

  // MARK: Superfícies escovadas (disco)

  nonisolated static func surfaceImage(styleId: Int, size: Int = 512) -> UIImage {
    let key = "surf_v42_\(styleId)_\(size)"
    if let url = diskURL(key: key), let disk = UIImage(contentsOfFile: url.path) { return disk }
    let img = renderBrushedSurface(styleId: styleId, size: size)
    if let url = diskURL(key: key), let data = img.pngData() { try? data.write(to: url, options: .atomic) }
    return img
  }

  nonisolated private static func diskURL(key: String) -> URL? {
    let safe = key.replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "_", options: .regularExpression)
    return cacheDir?.appendingPathComponent("\(safe).png")
  }

  nonisolated static func renderBrushedSurface(styleId: Int, size: Int) -> UIImage {
    let w = size, h = size
    var px = [UInt8](repeating: 255, count: w * h * 4)
    let invW = 1.0 / Double(w)
    let invH = 1.0 / Double(h)

    var rowNoise = [Double](repeating: 0, count: h)
    for y in 0..<h {
      let s = sin(Double(y) * 1.4 * 12.9898 + 4.1414) * 43758.5453
      rowNoise[y] = s - floor(s)
    }
    var colFine = [Double](repeating: 0, count: w)
    for x in 0..<w {
      let s = sin(Double(x / 3) * 12.9898 + 1.23) * 43758.5453
      colFine[x] = s - floor(s)
    }

    for y in 0..<h {
      let v = Double(y) * invH
      let rn = rowNoise[y]
      let edgeV = min(v, 1.0 - v)
      let woodBase = sin(v * 42.0)
      for x in 0..<w {
        let u = Double(x) * invW
        let diag = u * 0.65 + v * 0.35
        let d1 = (diag - 0.38) * 4.5
        let d2 = (diag - 0.78) * 6.0
        let sheen = exp(-(d1 * d1)) * 0.15 + exp(-(d2 * d2)) * 0.08
        let fine = abs(colFine[x] - rn * 0.37)
        let grain = rn * 0.78 + fine * 0.22
        var r: Double, g: Double, b: Double
        switch styleId {
        case 0:
          r = 0.86 - 0.16 * v + (grain - 0.5) * 0.052 + sheen
          g = 0.88 - 0.15 * v + (grain - 0.5) * 0.052 + sheen
          b = 0.91 - 0.14 * v + (grain - 0.5) * 0.052 + sheen
        case 1:
          r = 0.16 - 0.08 * v + (grain - 0.5) * 0.030 + sheen * 0.45
          g = 0.165 - 0.08 * v + (grain - 0.5) * 0.030 + sheen * 0.45
          b = 0.19 - 0.09 * v + (grain - 0.5) * 0.030 + sheen * 0.45
        case 2:
          let ring = (woodBase * cos(sin(u * 6.5) * 2.2 + u * 3.0)) * 0.5 + 0.5
          let wFactor = ring * 0.78 + fine * 0.12
          r = 0.18 + (0.36 - 0.18) * wFactor + sheen * 0.30
          g = 0.10 + (0.20 - 0.10) * wFactor + sheen * 0.24
          b = 0.06 + (0.11 - 0.06) * wFactor + sheen * 0.18
        default:
          r = 0.84 - 0.22 * v + (grain - 0.5) * 0.048 + sheen * 1.05
          g = 0.74 - 0.23 * v + (grain - 0.5) * 0.048 + sheen * 0.95
          b = 0.55 - 0.21 * v + (grain - 0.5) * 0.048 + sheen * 0.75
        }
        let edge = min(min(u, 1.0 - u), edgeV)
        let vig = edge < 0.05 ? (0.88 + 0.12 * (edge / 0.05)) : 1.0
        let i = (y * w + x) * 4
        px[i] = UInt8(min(255, max(0, r * vig * 255.0)))
        px[i + 1] = UInt8(min(255, max(0, g * vig * 255.0)))
        px[i + 2] = UInt8(min(255, max(0, b * vig * 255.0)))
        px[i + 3] = 255
      }
    }
    return imageFromRGBA(px, width: w, height: h, premultiplied: false)
  }

  nonisolated static func imageFromRGBA(_ px: [UInt8], width: Int, height: Int, premultiplied: Bool) -> UIImage {
    let data = Data(px)
    guard let provider = CGDataProvider(data: data as CFData),
          let cg = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: premultiplied ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
          ) else { return UIImage() }
    return UIImage(cgImage: cg)
  }
}

// MARK: - Helpers de desenho

struct TextureRNG {
  var s: UInt64
  init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 | 1 }
  mutating func next() -> CGFloat {
    s ^= s << 13; s ^= s >> 7; s ^= s << 17
    return CGFloat(s % 100_000) / 100_000
  }
  mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

extension LumeTextures {
  nonisolated static func gray(_ w: CGFloat, _ a: CGFloat = 1) -> UIColor { UIColor(white: w, alpha: a) }

  nonisolated static func gradient(_ colors: [UIColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: locs)!
  }

  nonisolated static func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> UIImage {
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = false
    return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { draw($0.cgContext) }
  }

  nonisolated static func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect {
    CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
  }

  /// Ruído fino (grão de plástico / papel) em ladrilho 128×128, desenhado com mistura suave.
  nonisolated static func noiseTile(seed: UInt64) -> CGImage? {
    let n = 128
    var rng = TextureRNG(seed)
    var px = [UInt8](repeating: 0, count: n * n * 4)
    for i in 0..<(n * n) {
      let v = UInt8(rng.next() * 255)
      px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = 255
    }
    return imageFromRGBA(px, width: n, height: n, premultiplied: false).cgImage
  }

  nonisolated static func tileNoise(_ ctx: CGContext, rect: CGRect, alpha: CGFloat, mode: CGBlendMode = .overlay, seed: UInt64 = 3) {
    guard let tile = noiseTile(seed: seed) else { return }
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.setAlpha(alpha)
    ctx.setBlendMode(mode)
    let t: CGFloat = 128
    var y = rect.minY
    while y < rect.maxY {
      var x = rect.minX
      while x < rect.maxX {
        ctx.draw(tile, in: CGRect(x: x, y: y, width: t, height: t))
        x += t
      }
      y += t
    }
    ctx.restoreGState()
  }
}

// MARK: - Disco de vinil (prato + disco)

extension LumeTextures {
  /// Prato metálico com pontos estroboscópicos + disco com sulcos finos, vãos entre faixas e borda chanfrada.
  /// Renderizado no tamanho exato em pixels (1:1) para não ter moiré. O selo (capa) é desenhado pelo SwiftUI.
  nonisolated static func renderRecord(edition: VinylEdition, px: Int) -> UIImage {
    canvas(px, px) { ctx in
      let D = CGFloat(px)
      let c = CGPoint(x: D / 2, y: D / 2)
      let pR = D / 2
      let rR = pR * DeckGeo.recordD / DeckGeo.platterD
      var rng = TextureRNG(UInt64(px) &+ 11)

      // Prato de alumínio torneado
      ctx.saveGState()
      ctx.addEllipse(in: circle(c, pR)); ctx.clip()
      let n = 120
      for i in 0..<n {
        let a0 = CGFloat(i) / CGFloat(n) * 2 * .pi
        let a1 = CGFloat(i + 1) / CGFloat(n) * 2 * .pi + 0.01
        let t = 0.5 + 0.5 * cos(2 * (a0 - 0.7))
        let l = 0.40 + 0.46 * t * t
        ctx.setFillColor(gray(l).cgColor)
        ctx.move(to: c)
        ctx.addLine(to: CGPoint(x: c.x + pR * 1.02 * cos(a0), y: c.y + pR * 1.02 * sin(a0)))
        ctx.addLine(to: CGPoint(x: c.x + pR * 1.02 * cos(a1), y: c.y + pR * 1.02 * sin(a1)))
        ctx.closePath()
        ctx.fillPath()
      }
      var rr = pR
      while rr > rR {
        ctx.setStrokeColor(UIColor(white: rng.next() > 0.5 ? 1 : 0, alpha: rng.range(0.03, 0.09)).cgColor)
        ctx.setLineWidth(0.7)
        ctx.strokeEllipse(in: circle(c, rr))
        rr -= rng.range(0.9, 2.2)
      }
      ctx.restoreGState()

      // Pontos estroboscópicos (50 Hz / 60 Hz)
      for (ring, count) in [(0.972, 108), (0.944, 90)] as [(CGFloat, Int)] {
        let rad = pR * ring
        let len = pR * 0.020
        let wid = (2 * .pi * rad / CGFloat(count)) * 0.46
        for k in 0..<count {
          let a = CGFloat(k) / CGFloat(count) * 2 * .pi
          ctx.saveGState()
          ctx.translateBy(x: c.x + rad * cos(a), y: c.y + rad * sin(a))
          ctx.rotate(by: a)
          ctx.setFillColor(gray(0.08, 0.78).cgColor)
          ctx.fill(CGRect(x: -len / 2, y: -wid / 2, width: len, height: wid))
          ctx.restoreGState()
        }
      }
      ctx.setStrokeColor(gray(1, 0.65).cgColor)
      ctx.setLineWidth(max(1, D * 0.0035))
      ctx.strokeEllipse(in: circle(c, pR - D * 0.002))
      ctx.setStrokeColor(gray(0, 0.55).cgColor)
      ctx.setLineWidth(max(1, D * 0.003))
      ctx.strokeEllipse(in: circle(c, rR + D * 0.004))

      // Disco: base por edição + sombra de contato
      let light: Bool
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: D * 0.004), blur: D * 0.016, color: gray(0, 0.6).cgColor)
      switch edition {
      case .classicBlack:
        light = false
        ctx.setFillColor(UIColor(red: 0.052, green: 0.052, blue: 0.058, alpha: 1).cgColor)
        ctx.fillEllipse(in: circle(c, rR))
      case .prismCrystal:
        light = true
        ctx.setFillColor(UIColor(white: 0.55, alpha: 1).cgColor)
        ctx.fillEllipse(in: circle(c, rR))
      case .limitedGold:
        light = true
        ctx.setFillColor(UIColor(red: 0.72, green: 0.52, blue: 0.18, alpha: 1).cgColor)
        ctx.fillEllipse(in: circle(c, rR))
      case .whiteMarble:
        light = true
        ctx.setFillColor(UIColor(red: 0.92, green: 0.91, blue: 0.88, alpha: 1).cgColor)
        ctx.fillEllipse(in: circle(c, rR))
      }
      ctx.restoreGState()

      ctx.saveGState()
      ctx.addEllipse(in: circle(c, rR)); ctx.clip()
      switch edition {
      case .classicBlack:
        ctx.drawRadialGradient(gradient([gray(0.12), gray(0.045), gray(0.07)], [0, 0.55, 1]),
                               startCenter: c, startRadius: 0, endCenter: c, endRadius: rR, options: [])
      case .prismCrystal:
        for i in 0..<180 {
          let a0 = CGFloat(i) / 180 * 2 * .pi
          let a1 = CGFloat(i + 1) / 180 * 2 * .pi + 0.012
          let hue = (CGFloat(i) / 180 * 2).truncatingRemainder(dividingBy: 1)
          ctx.setFillColor(UIColor(hue: hue, saturation: 0.42, brightness: 0.86, alpha: 0.86).cgColor)
          ctx.move(to: c)
          ctx.addLine(to: CGPoint(x: c.x + rR * 1.02 * cos(a0), y: c.y + rR * 1.02 * sin(a0)))
          ctx.addLine(to: CGPoint(x: c.x + rR * 1.02 * cos(a1), y: c.y + rR * 1.02 * sin(a1)))
          ctx.closePath(); ctx.fillPath()
        }
      case .limitedGold:
        ctx.drawRadialGradient(gradient([UIColor(red: 0.96, green: 0.80, blue: 0.38, alpha: 1), UIColor(red: 0.76, green: 0.54, blue: 0.16, alpha: 1), UIColor(red: 0.50, green: 0.33, blue: 0.08, alpha: 1)], [0, 0.6, 1]),
                               startCenter: CGPoint(x: c.x - rR * 0.2, y: c.y - rR * 0.2), startRadius: 0, endCenter: c, endRadius: rR * 1.1, options: [])
      case .whiteMarble:
        ctx.drawRadialGradient(gradient([gray(0.98), gray(0.88)], [0, 1]), startCenter: c, startRadius: 0, endCenter: c, endRadius: rR, options: [])
        for _ in 0..<16 {
          var p = CGMutablePath()
          var x = c.x + rng.range(-rR, rR), y = c.y + rng.range(-rR, rR)
          p.move(to: CGPoint(x: x, y: y))
          for _ in 0..<3 {
            let nx = x + rng.range(-rR * 0.5, rR * 0.5), ny = y + rng.range(-rR * 0.5, rR * 0.5)
            p.addQuadCurve(to: CGPoint(x: nx, y: ny), control: CGPoint(x: (x + nx) / 2 + rng.range(-40, 40), y: (y + ny) / 2 + rng.range(-40, 40)))
            x = nx; y = ny
          }
          ctx.addPath(p)
          ctx.setStrokeColor(UIColor(white: rng.range(0.35, 0.6), alpha: rng.range(0.10, 0.26)).cgColor)
          ctx.setLineWidth(rng.range(1.5, 6))
          ctx.setLineCap(.round)
          ctx.strokePath()
        }
      }

      // Faixas de "dinâmica" (largas, quase imperceptíveis) — variam o brilho como num disco real
      for _ in 0..<22 {
        let rad = rng.range(rR * 0.40, rR * 0.97)
        ctx.setStrokeColor(UIColor(white: light ? 0 : 1, alpha: rng.range(0.012, 0.035)).cgColor)
        ctx.setLineWidth(rng.range(3, 14))
        ctx.strokeEllipse(in: circle(c, rad))
      }

      // Sulcos finos (passo ~1,6 px, sem periodicidade para não dar moiré) com vãos entre faixas
      let gaps: [CGFloat] = [0.50, 0.625, 0.745, 0.86]
      let pitch = max(1.15, D / 640)
      var r = rR * 0.968
      while r > rR * 0.405 {
        let rn = r / rR
        let inGap = gaps.contains { abs(rn - $0) < 0.0075 }
        if inGap {
          ctx.setStrokeColor(UIColor(white: light ? 1 : 1, alpha: light ? 0.20 : 0.045).cgColor)
          ctx.setLineWidth(pitch * 1.4)
        } else {
          let a = rng.range(0.035, 0.11)
          ctx.setStrokeColor(UIColor(white: light ? 0 : 1, alpha: light ? a * 0.9 : a * 0.55).cgColor)
          ctx.setLineWidth(pitch * rng.range(0.5, 0.85))
        }
        ctx.strokeEllipse(in: circle(c, r))
        r -= pitch * rng.range(0.85, 1.25)
      }

      // Zona de saída (run-out) lisa e assentamento do selo
      ctx.setFillColor(UIColor(white: light ? 0.2 : 0, alpha: light ? 0.16 : 0.5).cgColor)
      ctx.fillEllipse(in: circle(c, rR * 0.385))
      ctx.setStrokeColor(gray(1, light ? 0.5 : 0.16).cgColor)
      ctx.setLineWidth(max(1, D * 0.0018))
      ctx.strokeEllipse(in: circle(c, rR * 0.385))
      ctx.setStrokeColor(gray(0, 0.5).cgColor)
      ctx.strokeEllipse(in: circle(c, rR * 0.365))
      ctx.restoreGState()

      // Borda chanfrada (realce interno claro + fio escuro)
      ctx.setStrokeColor(gray(1, light ? 0.55 : 0.22).cgColor)
      ctx.setLineWidth(max(1, D * 0.0035))
      ctx.strokeEllipse(in: circle(c, rR - D * 0.0025))
      ctx.setStrokeColor(gray(0, 0.55).cgColor)
      ctx.setLineWidth(max(1, D * 0.002))
      ctx.strokeEllipse(in: circle(c, rR))
    }
  }

  /// Reflexo anisotrópico em gravata borboleta: dois lóbulos opostos que ficam PARADOS enquanto o disco gira.
  nonisolated static func renderSheen(prism: Bool, size: Int) -> UIImage {
    let n = size
    var px = [UInt8](repeating: 0, count: n * n * 4)
    let half = Double(n) / 2
    let a0 = -0.62
    func adiff(_ a: Double, _ b: Double) -> Double {
      var d = a - b
      while d > .pi { d -= 2 * .pi }
      while d < -.pi { d += 2 * .pi }
      return d
    }
    for y in 0..<n {
      for x in 0..<n {
        let dx = Double(x) + 0.5 - half, dy = Double(y) + 0.5 - half
        let r = hypot(dx, dy) / half
        guard r > 0.30, r < 1.0 else { continue }
        let th = atan2(dy, dx)
        let w = 0.10 + 0.30 * r
        let d1 = adiff(th, a0) / w
        let d2 = adiff(th, a0 + .pi) / (w * 1.1)
        let lobe = exp(-d1 * d1) + 0.78 * exp(-d2 * d2)
        let q1 = adiff(th, a0 + .pi / 2) / 0.28
        let q2 = adiff(th, a0 - .pi / 2) / 0.28
        let minor = 0.20 * (exp(-q1 * q1) + exp(-q2 * q2))
        let fadeIn = min(1, (r - 0.30) / 0.14)
        let fadeOut = min(1, (1.0 - r) / 0.03)
        var I = (lobe + minor) * fadeIn * fadeOut * (0.45 + 0.55 * r)
        I = min(1, I)
        let i = (y * n + x) * 4
        if prism {
          let hue = (th + .pi) / (2 * .pi)
          let col = UIColor(hue: CGFloat(hue), saturation: 0.55, brightness: 1, alpha: 1)
          var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0
          col.getRed(&rr, green: &gg, blue: &bb, alpha: nil)
          let a = I * 0.40
          px[i] = UInt8(min(255, (0.55 + 0.45 * Double(rr)) * a * 255))
          px[i + 1] = UInt8(min(255, (0.55 + 0.45 * Double(gg)) * a * 255))
          px[i + 2] = UInt8(min(255, (0.55 + 0.45 * Double(bb)) * a * 255))
          px[i + 3] = UInt8(min(255, a * 255))
        } else {
          let a = I * 0.30
          let v = UInt8(min(255, a * 255))
          px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = v
        }
      }
    }
    return imageFromRGBA(px, width: n, height: n, premultiplied: true)
  }
}

// MARK: - Base do deck (chassi + marcações impressas)

extension LumeTextures {
  nonisolated static func renderDeckBase(finish: TurntableFinish, thick: Bool, pxW: Int) -> UIImage {
    let W = CGFloat(pxW)
    let H = (W / DeckGeo.aspect).rounded()
    let u = H
    let dark = finish.isDarkChassis
    let corner = u * 0.06
    let mx = DeckGeo.marginX * u, mt = DeckGeo.marginTop * u, mb = DeckGeo.marginBottom * u
    let t = thick ? DeckGeo.thickness * u : 0
    return canvas(Int(W + 2 * mx), Int(H + mt + mb)) { ctx in
      ctx.translateBy(x: mx, y: mt)
      let rect = CGRect(x: 0, y: 0, width: W, height: H)
      let shape = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: corner)

      // Sombra projetada, espessura do chassi e pés isoladores (tudo estático e pré-renderizado)
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: u * (thick ? 0.05 : 0.03)), blur: u * (thick ? 0.07 : 0.05), color: gray(0, thick ? 0.55 : 0.42).cgColor)
      ctx.setFillColor(gray(0.1).cgColor)
      ctx.addPath(UIBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: t).insetBy(dx: 0.5, dy: 0.5), cornerRadius: corner).cgPath)
      ctx.fillPath()
      ctx.restoreGState()
      if thick {
        let side = UIBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: t).insetBy(dx: 0.5, dy: 0.5), cornerRadius: corner)
        ctx.saveGState()
        ctx.addPath(side.cgPath); ctx.clip()
        ctx.drawLinearGradient(gradient(dark ? [gray(0.10), gray(0.02)] : [gray(0.56), gray(0.26)]),
                               start: CGPoint(x: 0, y: t), end: CGPoint(x: 0, y: H + t), options: [])
        ctx.drawLinearGradient(gradient([gray(1, dark ? 0.12 : 0.30), gray(1, 0), gray(0, 0.25)], [0, 0.5, 1]),
                               start: CGPoint(x: 0, y: 0), end: CGPoint(x: W, y: 0), options: [])
        ctx.restoreGState()
        for fx in [0.10 * u, W - 0.10 * u - 0.12 * u] {
          let foot = UIBezierPath(roundedRect: CGRect(x: fx, y: H + t - u * 0.004, width: 0.12 * u, height: u * 0.032), cornerRadius: u * 0.012)
          ctx.saveGState()
          ctx.setShadow(offset: CGSize(width: 0, height: u * 0.012), blur: u * 0.02, color: gray(0, 0.6).cgColor)
          ctx.setFillColor(gray(0.3).cgColor); ctx.addPath(foot.cgPath); ctx.fillPath()
          ctx.restoreGState()
          ctx.saveGState()
          ctx.addPath(foot.cgPath); ctx.clip()
          ctx.drawLinearGradient(gradient([gray(0.85), gray(0.25), gray(0.55)], [0, 0.6, 1]),
                                 start: CGPoint(x: 0, y: H + t), end: CGPoint(x: 0, y: H + t + u * 0.03), options: [])
          ctx.restoreGState()
        }
      }

      ctx.saveGState()
      shape.addClip()
      surfaceImage(styleId: Int(finish.shaderIndex)).draw(in: rect)
      ctx.drawLinearGradient(gradient([gray(1, dark ? 0.10 : 0.28), gray(1, 0), gray(0, dark ? 0.30 : 0.20)], [0, 0.45, 1]),
                             start: .zero, end: CGPoint(x: W * 0.3, y: H), options: [])
      tileNoise(ctx, rect: rect, alpha: 0.10, mode: .overlay, seed: 5)
      ctx.restoreGState()

      // Chanfro externo e fio interno
      ctx.saveGState()
      shape.addClip()
      ctx.addPath(shape.cgPath)
      ctx.setLineWidth(u * 0.010)
      ctx.replacePathWithStrokedPath()
      ctx.clip()
      ctx.drawLinearGradient(gradient([gray(1, dark ? 0.40 : 0.95), gray(1, 0.18), gray(0, 0.42)], [0, 0.5, 1]),
                             start: .zero, end: CGPoint(x: W, y: H), options: [])
      ctx.restoreGState()
      let inner = UIBezierPath(roundedRect: rect.insetBy(dx: u * 0.018, dy: u * 0.018), cornerRadius: corner * 0.85)
      ctx.saveGState()
      ctx.addPath(inner.cgPath)
      ctx.setLineWidth(max(1, u * 0.0035))
      ctx.replacePathWithStrokedPath()
      ctx.clip()
      ctx.drawLinearGradient(gradient([gray(0, 0.32), gray(1, dark ? 0.18 : 0.5)], [0, 1]),
                             start: .zero, end: CGPoint(x: W, y: H), options: [])
      ctx.restoreGState()

      // Parafusos nos cantos
      for p in [CGPoint(x: 0.04, y: 0.05), CGPoint(x: DeckGeo.aspect - 0.04, y: 0.05),
                CGPoint(x: 0.04, y: 0.95), CGPoint(x: DeckGeo.aspect - 0.04, y: 0.95)] {
        screw(ctx, at: CGPoint(x: p.x * u, y: p.y * u), r: u * 0.012)
      }

      // Poço do prato
      let pc = CGPoint(x: DeckGeo.platterC.x * u, y: DeckGeo.platterC.y * u)
      let wellR = u * (DeckGeo.platterD / 2 + 0.018)
      ctx.saveGState()
      ctx.setShadow(offset: .zero, blur: u * 0.02, color: gray(0, 0.55).cgColor)
      ctx.setFillColor(gray(0.03).cgColor)
      ctx.fillEllipse(in: circle(pc, wellR))
      ctx.restoreGState()
      ctx.saveGState()
      ctx.addEllipse(in: circle(pc, wellR)); ctx.clip()
      ctx.drawLinearGradient(gradient([gray(0, 0.75), gray(0, 0)], [0, 1]),
                             start: CGPoint(x: pc.x - wellR, y: pc.y - wellR), end: CGPoint(x: pc.x + wellR * 0.2, y: pc.y + wellR * 0.2), options: [])
      ctx.restoreGState()
      ctx.setStrokeColor(gray(1, dark ? 0.30 : 0.75).cgColor)
      ctx.setLineWidth(max(1, u * 0.004))
      ctx.strokeEllipse(in: circle(pc, wellR + u * 0.002))
      ctx.setStrokeColor(gray(0, 0.5).cgColor)
      ctx.strokeEllipse(in: circle(pc, wellR - u * 0.004))

      // Base do pivô do braço
      let pv = CGPoint(x: DeckGeo.pivot.x * u, y: DeckGeo.pivot.y * u)
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: u * 0.006, height: u * 0.012), blur: u * 0.02, color: gray(0, 0.5).cgColor)
      ctx.setFillColor(gray(0.5).cgColor)
      ctx.fillEllipse(in: circle(pv, u * 0.085))
      ctx.restoreGState()
      ctx.saveGState()
      ctx.addEllipse(in: circle(pv, u * 0.085)); ctx.clip()
      ctx.drawLinearGradient(gradient([gray(0.98), gray(0.55), gray(0.85), gray(0.32)], [0, 0.4, 0.6, 1]),
                             start: CGPoint(x: pv.x - u * 0.085, y: pv.y - u * 0.085), end: CGPoint(x: pv.x + u * 0.085, y: pv.y + u * 0.085), options: [])
      ctx.restoreGState()
      ctx.setFillColor(gray(0.10).cgColor)
      ctx.fillEllipse(in: circle(pv, u * 0.058))
      ctx.saveGState()
      ctx.addEllipse(in: circle(pv, u * 0.058)); ctx.clip()
      ctx.drawLinearGradient(gradient([gray(0.32), gray(0.05)], [0, 1]),
                             start: CGPoint(x: pv.x - u * 0.04, y: pv.y - u * 0.04), end: CGPoint(x: pv.x + u * 0.05, y: pv.y + u * 0.05), options: [])
      ctx.restoreGState()
      // régua do anti-skating
      ctx.setStrokeColor(gray(1, 0.5).cgColor)
      ctx.setLineWidth(max(1, u * 0.002))
      for k in 0..<13 {
        let a = (-60 + Double(k) * 10) * .pi / 180
        let r0 = u * 0.066, r1 = u * (k % 3 == 0 ? 0.078 : 0.072)
        ctx.move(to: CGPoint(x: pv.x + r0 * CGFloat(sin(a)), y: pv.y - r0 * CGFloat(cos(a)) + u * 0.0))
        ctx.addLine(to: CGPoint(x: pv.x + r1 * CGFloat(sin(a)), y: pv.y - r1 * CGFloat(cos(a))))
      }
      ctx.strokePath()

      // Apoio do braço
      let rp = CGPoint(x: DeckGeo.restPost.x * u, y: DeckGeo.restPost.y * u)
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: u * 0.004, height: u * 0.01), blur: u * 0.012, color: gray(0, 0.55).cgColor)
      ctx.setFillColor(gray(0.55).cgColor)
      ctx.fillEllipse(in: circle(rp, u * 0.026))
      ctx.restoreGState()
      ctx.saveGState()
      ctx.addEllipse(in: circle(rp, u * 0.026)); ctx.clip()
      ctx.drawRadialGradient(gradient([gray(1), gray(0.55), gray(0.25)], [0, 0.55, 1]),
                             startCenter: CGPoint(x: rp.x - u * 0.008, y: rp.y - u * 0.008), startRadius: 0, endCenter: rp, endRadius: u * 0.03, options: [])
      ctx.restoreGState()
      ctx.setFillColor(gray(0.08).cgColor)
      let cradle = UIBezierPath(roundedRect: CGRect(x: rp.x - u * 0.013, y: rp.y - u * 0.004, width: u * 0.026, height: u * 0.012), cornerRadius: u * 0.005)
      cradle.fill()

      // Lâmpada do estroboscópio (a luz acesa é uma camada dinâmica)
      let lamp = CGPoint(x: 1.17 * u, y: 0.80 * u)
      ctx.setFillColor(gray(0.05).cgColor)
      ctx.fillEllipse(in: circle(lamp, u * 0.030))
      ctx.saveGState()
      ctx.addEllipse(in: circle(lamp, u * 0.028)); ctx.clip()
      ctx.drawRadialGradient(gradient([gray(0.65), gray(0.28), gray(0.12)], [0, 0.55, 1]),
                             startCenter: CGPoint(x: lamp.x - u * 0.008, y: lamp.y - u * 0.008), startRadius: 0, endCenter: lamp, endRadius: u * 0.03, options: [])
      ctx.restoreGState()
      ctx.setStrokeColor(gray(1, 0.45).cgColor)
      ctx.setLineWidth(max(1, u * 0.0025))
      ctx.strokeEllipse(in: circle(lamp, u * 0.030))

      // Marcação impressa
      let ink = dark ? UIColor(white: 1, alpha: 0.55) : UIColor(white: 0, alpha: 0.55)
      func text(_ s: String, size: CGFloat, weight: UIFont.Weight, x: CGFloat, y: CGFloat, align: NSTextAlignment, kern: CGFloat = 0.0) {
        let font = UIFont.systemFont(ofSize: size * u, weight: weight)
        let para = NSMutableParagraphStyle(); para.alignment = align
        let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: ink, .kern: kern * u, .paragraphStyle: para])
        let sz = a.size()
        let ox = align == .right ? x * u - sz.width : (align == .center ? x * u - sz.width / 2 : x * u)
        a.draw(at: CGPoint(x: ox, y: y * u - sz.height / 2))
      }
      text("LUME  DD-1", size: 0.034, weight: .heavy, x: DeckGeo.aspect - 0.07, y: 0.935, align: .right, kern: 0.003)
      text("DIRECT DRIVE · QUARTZ LOCK", size: 0.0155, weight: .semibold, x: DeckGeo.aspect - 0.07, y: 0.97, align: .right, kern: 0.002)

      // Canal do pitch (a alavanca é dinâmica)
      let slotX = 1.395 * u
      let slot = UIBezierPath(roundedRect: CGRect(x: slotX - u * 0.008, y: 0.40 * u, width: u * 0.016, height: 0.34 * u), cornerRadius: u * 0.008)
      ctx.setFillColor(gray(0, 0.7).cgColor)
      slot.fill()
      ctx.setStrokeColor(gray(1, dark ? 0.25 : 0.7).cgColor)
      ctx.setLineWidth(max(1, u * 0.0025))
      slot.stroke()
      for k in -4...4 {
        let y = (0.57 + CGFloat(k) * 0.036) * u
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(max(1, u * (k == 0 ? 0.003 : 0.002)))
        ctx.move(to: CGPoint(x: slotX - u * (k == 0 ? 0.042 : 0.03), y: y))
        ctx.addLine(to: CGPoint(x: slotX - u * 0.014, y: y))
        ctx.strokePath()
      }
      text("PITCH", size: 0.0145, weight: .heavy, x: 1.395, y: 0.775, align: .center, kern: 0.002)
    }
  }

  nonisolated static func screw(_ ctx: CGContext, at p: CGPoint, r: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: r * 0.3), blur: r * 0.6, color: gray(0, 0.5).cgColor)
    ctx.setFillColor(gray(0.6).cgColor)
    ctx.fillEllipse(in: circle(p, r))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: circle(p, r)); ctx.clip()
    ctx.drawRadialGradient(gradient([gray(0.97), gray(0.62), gray(0.3)], [0, 0.6, 1]),
                           startCenter: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.35), startRadius: 0, endCenter: p, endRadius: r * 1.1, options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(gray(0, 0.55).cgColor)
    ctx.setLineWidth(max(0.8, r * 0.18))
    ctx.move(to: CGPoint(x: p.x - r * 0.62, y: p.y + r * 0.28))
    ctx.addLine(to: CGPoint(x: p.x + r * 0.62, y: p.y - r * 0.28))
    ctx.strokePath()
  }
}

// MARK: - Braço do toca-discos

extension LumeTextures {
  static let armUnit: CGFloat = 800
  static let armCanvas = CGSize(width: 0.30, height: 1.17)
  static let armPivot = CGPoint(x: 0.15, y: 0.27)

  nonisolated static func renderArm() -> (UIImage, UIImage) {
    let u = armUnit
    let w = Int(armCanvas.width * u), h = Int(armCanvas.height * u)
    let L = DeckGeo.armL
    let sil = false
    _ = sil

    func draw(_ ctx: CGContext, silhouette: Bool) {
      ctx.translateBy(x: armPivot.x * u, y: armPivot.y * u)
      let black = gray(0).cgColor
      func metalH(_ rect: CGRect, _ cols: [UIColor], _ locs: [CGFloat]) {
        ctx.saveGState()
        ctx.clip(to: rect)
        if silhouette { ctx.setFillColor(black); ctx.fill(rect) } else {
          ctx.drawLinearGradient(gradient(cols, locs), start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
        }
        ctx.restoreGState()
      }

      // Contrapeso (cilindro anodizado com anéis e escala)
      let cw = CGRect(x: -0.056 * u, y: -0.245 * u, width: 0.112 * u, height: 0.125 * u)
      ctx.saveGState()
      ctx.addPath(UIBezierPath(roundedRect: cw, cornerRadius: 0.014 * u).cgPath); ctx.clip()
      if silhouette { ctx.setFillColor(black); ctx.fill(cw) } else {
        ctx.drawLinearGradient(gradient([gray(0.18), gray(0.62), gray(0.92), gray(0.5), gray(0.16)], [0, 0.28, 0.45, 0.75, 1]),
                               start: CGPoint(x: cw.minX, y: 0), end: CGPoint(x: cw.maxX, y: 0), options: [])
        for k in 0..<9 {
          let y = cw.minY + CGFloat(k) * cw.height / 8
          ctx.setStrokeColor(gray(0, 0.32).cgColor); ctx.setLineWidth(1.4)
          ctx.move(to: CGPoint(x: cw.minX, y: y)); ctx.addLine(to: CGPoint(x: cw.maxX, y: y)); ctx.strokePath()
        }
        ctx.setFillColor(gray(0.04).cgColor)
        ctx.fill(CGRect(x: cw.minX, y: cw.maxY - 0.030 * u, width: cw.width, height: 0.030 * u))
        ctx.setStrokeColor(gray(1, 0.8).cgColor); ctx.setLineWidth(1.6)
        for k in -4...4 {
          let x = CGFloat(k) * 0.011 * u
          ctx.move(to: CGPoint(x: x, y: cw.maxY - 0.027 * u)); ctx.addLine(to: CGPoint(x: x, y: cw.maxY - (k % 2 == 0 ? 0.012 : 0.018) * u))
        }
        ctx.strokePath()
      }
      ctx.restoreGState()
      if !silhouette {
        ctx.setStrokeColor(gray(1, 0.35).cgColor); ctx.setLineWidth(2)
        ctx.addPath(UIBezierPath(roundedRect: cw, cornerRadius: 0.014 * u).cgPath); ctx.strokePath()
      }
      metalH(CGRect(x: -0.010 * u, y: -0.125 * u, width: 0.020 * u, height: 0.14 * u), [gray(0.3), gray(0.95), gray(0.35)], [0, 0.5, 1])

      // Tubo em S
      let end = CGPoint(x: 0.040 * u, y: (L - 0.168) * u)
      let tube = CGMutablePath()
      tube.move(to: .zero)
      tube.addCurve(to: end, control1: CGPoint(x: 0.052 * u, y: 0.22 * u), control2: CGPoint(x: -0.034 * u, y: (L - 0.40) * u))
      ctx.saveGState()
      ctx.addPath(tube)
      ctx.setLineWidth(0.0225 * u); ctx.setLineCap(.round)
      ctx.replacePathWithStrokedPath(); ctx.clip()
      if silhouette { ctx.setFillColor(black); ctx.fill(CGRect(x: -u, y: -u, width: 2 * u, height: 3 * u)) } else {
        ctx.drawLinearGradient(gradient([gray(0.32), gray(0.72), gray(1.0), gray(0.62), gray(0.28)], [0, 0.3, 0.46, 0.72, 1]),
                               start: CGPoint(x: -0.04 * u, y: 0), end: CGPoint(x: 0.07 * u, y: 0), options: [])
      }
      ctx.restoreGState()

      // Headshell + cartucho
      ctx.saveGState()
      ctx.translateBy(x: end.x, y: end.y)
      ctx.rotate(by: 12.6 * .pi / 180)
      let shell = CGRect(x: -0.031 * u, y: -0.018 * u, width: 0.062 * u, height: 0.196 * u)
      ctx.addPath(UIBezierPath(roundedRect: shell, cornerRadius: 0.010 * u).cgPath)
      if silhouette { ctx.setFillColor(black); ctx.fillPath() } else {
        ctx.saveGState(); ctx.clip()
        ctx.drawLinearGradient(gradient([gray(0.07), gray(0.26), gray(0.07)], [0, 0.45, 1]),
                               start: CGPoint(x: shell.minX, y: 0), end: CGPoint(x: shell.maxX, y: 0), options: [])
        ctx.restoreGState()
        ctx.setStrokeColor(gray(1, 0.35).cgColor); ctx.setLineWidth(1.6)
        ctx.addPath(UIBezierPath(roundedRect: shell, cornerRadius: 0.010 * u).cgPath); ctx.strokePath()
        // furos do headshell
        ctx.setFillColor(gray(0, 0.8).cgColor)
        for yy in [0.010, 0.030] as [CGFloat] { ctx.fillEllipse(in: circle(CGPoint(x: 0, y: yy * u), 0.0055 * u)) }
        // cartucho
        let cart = CGRect(x: -0.026 * u, y: 0.070 * u, width: 0.052 * u, height: 0.085 * u)
        ctx.addPath(UIBezierPath(roundedRect: cart, cornerRadius: 0.006 * u).cgPath)
        ctx.saveGState(); ctx.clip()
        ctx.drawLinearGradient(gradient([UIColor(red: 1.0, green: 0.48, blue: 0.62, alpha: 1), UIColor(red: 0.62, green: 0.24, blue: 0.45, alpha: 1)], [0, 1]),
                               start: CGPoint(x: 0, y: cart.minY), end: CGPoint(x: 0, y: cart.maxY), options: [])
        ctx.restoreGState()
        ctx.setStrokeColor(gray(0, 0.4).cgColor); ctx.setLineWidth(1.4)
        ctx.addPath(UIBezierPath(roundedRect: cart, cornerRadius: 0.006 * u).cgPath); ctx.strokePath()
        // agulha
        ctx.setStrokeColor(gray(0.05).cgColor); ctx.setLineWidth(0.004 * u); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 0, y: 0.150 * u)); ctx.addLine(to: CGPoint(x: 0, y: 0.1745 * u)); ctx.strokePath()
        ctx.setFillColor(UIColor(red: 1, green: 0.2, blue: 0.25, alpha: 1).cgColor)
        ctx.fillEllipse(in: circle(CGPoint(x: 0, y: 0.1745 * u), 0.0042 * u))
      }
      // alavanca de levantar (finger lift)
      ctx.setStrokeColor(silhouette ? black : gray(0.86).cgColor)
      ctx.setLineWidth(0.0075 * u); ctx.setLineCap(.round)
      ctx.move(to: CGPoint(x: 0.030 * u, y: 0.040 * u))
      ctx.addQuadCurve(to: CGPoint(x: 0.068 * u, y: 0.020 * u), control: CGPoint(x: 0.052 * u, y: 0.050 * u))
      ctx.strokePath()
      ctx.restoreGState()

      // Tampa do pivô
      let capR = 0.034 * u
      if silhouette { ctx.setFillColor(black); ctx.fillEllipse(in: circle(.zero, capR)) } else {
        ctx.saveGState(); ctx.addEllipse(in: circle(.zero, capR)); ctx.clip()
        ctx.drawRadialGradient(gradient([gray(1), gray(0.65), gray(0.28)], [0, 0.55, 1]),
                               startCenter: CGPoint(x: -capR * 0.35, y: -capR * 0.4), startRadius: 0, endCenter: .zero, endRadius: capR * 1.2, options: [])
        ctx.restoreGState()
        ctx.setStrokeColor(gray(0, 0.4).cgColor); ctx.setLineWidth(2)
        ctx.strokeEllipse(in: circle(.zero, capR))
        ctx.setFillColor(gray(0.12).cgColor)
        ctx.fillEllipse(in: circle(.zero, capR * 0.32))
      }
    }

    let arm = canvas(w, h) { draw($0, silhouette: false) }
    // Sombra: silhueta desenhada fora da tela com sombra desfocada deslocada de volta (sem CoreImage).
    let off = CGFloat(w) * 3
    let shadow = canvas(w, h) { ctx in
      ctx.setShadow(offset: CGSize(width: off, height: 0), blur: 0.016 * u, color: gray(0, 1).cgColor)
      ctx.translateBy(x: -off, y: 0)
      draw(ctx, silhouette: true)
    }
    return (arm, shadow)
  }
}
