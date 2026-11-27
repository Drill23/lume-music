import CoreImage
import SwiftUI
import UIKit

/// Arte composta para a tela de bloqueio / Central de Controle (MPNowPlayingInfo).
///
/// No iOS a tela de bloqueio só mostra a arte do Now Playing (Live Activity exigiria extensão, o que
/// o LiveContainer não permite). Então desenhamos UMA imagem bonita por faixa+estilo:
///  • Vinil: o disco com sulcos, reflexos, selo = capa e o braço com a agulha pousada;
///  • Fita K7: cassete de plástico fumê com a capa impressa no rótulo, janela com os carretéis.
/// Renderização com Core Graphics em tarefa destacada (~1024 px), cache em memória. Nunca atrasa o
/// início da música: o AudioPlayer publica a capa simples primeiro e troca quando esta ficar pronta.
actor LockScreenArtwork {
  static let shared = LockScreenArtwork()

  private var cache: [String: UIImage] = [:]
  private var order: [String] = []
  private static let side: CGFloat = 1024

  func image(for track: Track, cover: UIImage, style: LockArtStyle, palette: ArtworkPalette) async -> UIImage? {
    guard style != .cover, style != .automatic else { return cover }
    let (edition, tapeStyle) = await MainActor.run { (LibraryStore.shared.vinylEdition, LibraryStore.shared.cassetteStyle) }
    let key = "\(track.id)#\(style.rawValue)#\(edition.rawValue)#\(tapeStyle.rawValue)"
    if let hit = cache[key] { return hit }
    let accent = await MainActor.run { (UIColor(palette.vibrant), UIColor(palette.vibrant2)) }
    let title = track.title
    let artist = track.artist
    let img = await Task.detached(priority: .utility) { () -> UIImage? in
      switch style {
      case .vinyl: return Self.renderVinyl(cover: cover, accent: accent.0, edition: edition)
      case .cassette: return Self.renderTape(cover: cover, title: title, artist: artist, style: tapeStyle)
      default: return cover
      }
    }.value
    guard let img else { return nil }
    cache[key] = img
    order.removeAll { $0 == key }
    order.append(key)
    while order.count > 4 { cache.removeValue(forKey: order.removeFirst()) }
    return img
  }

  // MARK: - Fundo comum (capa desfocada + véu escuro)

  private static let ci = CIContext(options: [.cacheIntermediates: false])

  private static func drawBackdrop(_ ctx: CGContext, cover: UIImage, size S: CGFloat) {
    if let cg = cover.cgImage {
      let input = CIImage(cgImage: cg)
      let scale = 160 / max(input.extent.width, 1)
      let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 14).cropped(to: small.extent)
      if let out = ci.createCGImage(blurred, from: small.extent) {
        UIImage(cgImage: out).draw(in: CGRect(x: -S * 0.15, y: -S * 0.15, width: S * 1.3, height: S * 1.3))
      }
    } else {
      UIColor(white: 0.08, alpha: 1).setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    }
    let colors = [UIColor.black.withAlphaComponent(0.30).cgColor, UIColor.black.withAlphaComponent(0.62).cgColor] as CFArray
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
      ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: S), options: [])
    }
  }

  private static func drawCover(_ cover: UIImage, in rect: CGRect) {
    let s = cover.size
    guard s.width > 0, s.height > 0 else { return }
    let k = max(rect.width / s.width, rect.height / s.height)
    let w = s.width * k, h = s.height * k
    cover.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
  }

  // MARK: - Vinil

  static func renderVinyl(cover: UIImage, accent: UIColor, edition: VinylEdition) -> UIImage {
    let S = side
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: S, height: S), format: fmt).image { rc in
      let ctx = rc.cgContext
      drawBackdrop(ctx, cover: cover, size: S)

      // Mesmas texturas do palco Vinil do app: prato de alumínio com estroboscópio + disco + reflexo parado.
      let c = CGPoint(x: S * 0.47, y: S * 0.52)
      let R = S * 0.40                                         // raio do disco
      let P = 2 * R * DeckGeo.platterD / DeckGeo.recordD       // diâmetro do prato
      let platter = CGRect(x: c.x - P / 2, y: c.y - P / 2, width: P, height: P)
      let disc = CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: S * 0.02), blur: S * 0.05, color: UIColor.black.withAlphaComponent(0.7).cgColor)
      LumeTextures.renderRecord(edition: edition, px: Int(P)).draw(in: platter)
      ctx.restoreGState()
      LumeTextures.renderSheen(prism: edition == .prismCrystal, size: Int(2 * R)).draw(in: disc, blendMode: .normal, alpha: 1)
      _ = accent

      // Selo = capa
      let L = R * DeckGeo.labelD / DeckGeo.recordD
      let label = CGRect(x: c.x - L, y: c.y - L, width: 2 * L, height: 2 * L)
      ctx.saveGState()
      ctx.addEllipse(in: label)
      ctx.clip()
      drawCover(cover, in: label)
      let gloss = [UIColor(white: 1, alpha: 0.22).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
      if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gloss, locations: [0, 1]) {
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: label.minX + L * 0.6, y: label.minY + L * 0.5), startRadius: 0,
                               endCenter: CGPoint(x: label.minX + L * 0.6, y: label.minY + L * 0.5), endRadius: L * 1.2, options: [])
      }
      ctx.restoreGState()
      ctx.setStrokeColor(UIColor(white: 0, alpha: 0.55).cgColor)
      ctx.setLineWidth(4)
      ctx.strokeEllipse(in: label)

      // Eixo central
      let h = R * 0.03
      UIColor(white: 0.78, alpha: 1).setFill()
      ctx.fillEllipse(in: CGRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h))
      UIColor(white: 0.35, alpha: 1).setFill()
      ctx.fillEllipse(in: CGRect(x: c.x - h * 0.45, y: c.y - h * 0.45, width: h * 0.9, height: h * 0.9))

      // Braço com a agulha pousada nos sulcos
      let pivot = CGPoint(x: S * 0.90, y: S * 0.13)
      let stylusAngle = 0.32
      let stylus = CGPoint(x: c.x + R * 0.74 * CGFloat(cos(stylusAngle)), y: c.y + R * 0.74 * CGFloat(sin(stylusAngle)))
      let dx = stylus.x - pivot.x, dy = stylus.y - pivot.y
      let len = sqrt(dx * dx + dy * dy)
      let ux = dx / len, uy = dy / len

      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: S * 0.012, height: S * 0.018), blur: S * 0.02, color: UIColor.black.withAlphaComponent(0.6).cgColor)
      // contrapeso
      ctx.setLineCap(.round)
      ctx.setStrokeColor(UIColor(white: 0.20, alpha: 1).cgColor)
      ctx.setLineWidth(S * 0.05)
      ctx.move(to: pivot)
      ctx.addLine(to: CGPoint(x: pivot.x - ux * S * 0.07, y: pivot.y - uy * S * 0.07))
      ctx.strokePath()
      // haste
      ctx.setStrokeColor(UIColor(white: 0.80, alpha: 1).cgColor)
      ctx.setLineWidth(S * 0.014)
      ctx.move(to: pivot)
      ctx.addLine(to: CGPoint(x: stylus.x - ux * S * 0.05, y: stylus.y - uy * S * 0.05))
      ctx.strokePath()
      // cápsula (headshell)
      ctx.translateBy(x: stylus.x, y: stylus.y)
      ctx.rotate(by: atan2(uy, ux) - .pi / 2)
      let head = CGRect(x: -S * 0.022, y: -S * 0.075, width: S * 0.044, height: S * 0.085)
      UIColor(white: 0.14, alpha: 1).setFill()
      UIBezierPath(roundedRect: head, cornerRadius: S * 0.008).fill()
      UIColor(white: 0.85, alpha: 1).setFill()
      UIBezierPath(roundedRect: CGRect(x: -S * 0.004, y: -S * 0.006, width: S * 0.008, height: S * 0.012), cornerRadius: 2).fill()
      ctx.restoreGState()
      // base do pivô
      let pb = S * 0.055
      let base = CGRect(x: pivot.x - pb, y: pivot.y - pb, width: 2 * pb, height: 2 * pb)
      let metal = [UIColor(white: 0.92, alpha: 1).cgColor, UIColor(white: 0.45, alpha: 1).cgColor] as CFArray
      ctx.saveGState()
      ctx.addEllipse(in: base)
      ctx.clip()
      if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: metal, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: base.minX, y: base.minY), end: CGPoint(x: base.maxX, y: base.maxY), options: [])
      }
      ctx.restoreGState()
      UIColor(white: 0.25, alpha: 1).setFill()
      ctx.fillEllipse(in: base.insetBy(dx: pb * 0.55, dy: pb * 0.55))
    }
  }

  // MARK: - Fita K7 (mesmas camadas do palco K7 do app)

  static func renderTape(cover: UIImage, title: String, artist: String, style: CassetteStyle) -> UIImage {
    let S = side
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = true
    let w = S * 0.86
    let h = w / TapeGeo.aspect
    let layers = LumeTextures.renderCassette(style: style, sideB: false, wpx: Int(w))
    let hub = LumeTextures.renderHub(px: Int(TapeGeo.hubR * 2 * w))
    let pack = LumeTextures.renderPack(px: Int(TapeGeo.rFull * 2 * w))
    return UIGraphicsImageRenderer(size: CGSize(width: S, height: S), format: fmt).image { rc in
      let ctx = rc.cgContext
      drawBackdrop(ctx, cover: cover, size: S)
      let o = CGPoint(x: (S - w) / 2, y: (S - h) / 2 - S * 0.02)
      // sombra
      let sw = w * (1 + 2 * TapeGeo.shadowMarginX)
      let sh = h + w * (TapeGeo.shadowMarginTop + TapeGeo.shadowMarginBottom)
      layers.shadow.draw(in: CGRect(x: o.x - w * TapeGeo.shadowMarginX, y: o.y - w * TapeGeo.shadowMarginTop, width: sw, height: sh))
      layers.back.draw(in: CGRect(x: o.x, y: o.y, width: w, height: h))
      // carretéis no meio da faixa (rolo da esquerda um pouco maior)
      let q: CGFloat = 0.38
      let a = TapeGeo.rFull * TapeGeo.rFull - TapeGeo.rEmpty * TapeGeo.rEmpty
      let rL = sqrt(TapeGeo.rFull * TapeGeo.rFull - q * a)
      let rR = sqrt(TapeGeo.rEmpty * TapeGeo.rEmpty + q * a)
      for (center, r, ang) in [(TapeGeo.reelL, rL, 0.4), (TapeGeo.reelR, rR, 1.1)] as [(CGPoint, CGFloat, CGFloat)] {
        let cc = CGPoint(x: o.x + center.x * w, y: o.y + center.y * w)
        pack.draw(in: CGRect(x: cc.x - r * w, y: cc.y - r * w, width: 2 * r * w, height: 2 * r * w))
        ctx.saveGState()
        ctx.translateBy(x: cc.x, y: cc.y)
        ctx.rotate(by: ang)
        let hr = TapeGeo.hubR * w
        hub.draw(in: CGRect(x: -hr, y: -hr, width: 2 * hr, height: 2 * hr))
        ctx.restoreGState()
      }
      layers.front.draw(in: CGRect(x: o.x, y: o.y, width: w, height: h))
      // escrita à mão na etiqueta (mesmas posições do app)
      let hand = UIFont(name: "BradleyHandITCTT-Bold", size: w * 0.054) ?? UIFont(name: "Noteworthy-Bold", size: w * 0.054) ?? .boldSystemFont(ofSize: w * 0.05)
      let hand2 = hand.withSize(w * 0.040)
      func write(_ text: String, font: UIFont, color: UIColor, y: CGFloat) {
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
        let rect = CGRect(x: o.x + w * 0.085, y: o.y + w * y - font.lineHeight / 2, width: w * 0.69, height: font.lineHeight * 1.2)
        ctx.saveGState()
        ctx.translateBy(x: rect.midX, y: rect.midY); ctx.rotate(by: -0.012); ctx.translateBy(x: -rect.midX, y: -rect.midY)
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
        ctx.restoreGState()
      }
      write(title, font: hand, color: UIColor(red: 0.10, green: 0.14, blue: 0.46, alpha: 1), y: 0.133)
      write(artist, font: hand2, color: UIColor(red: 0.16, green: 0.18, blue: 0.40, alpha: 0.85), y: 0.172)
      // capinha colada na etiqueta
      let side = w * 0.078
      let thumb = CGRect(x: o.x + w * 0.873 - side / 2, y: o.y + w * 0.147 - side / 2, width: side, height: side)
      ctx.saveGState()
      UIBezierPath(roundedRect: thumb, cornerRadius: w * 0.004).addClip()
      drawCover(cover, in: thumb)
      ctx.restoreGState()
    }
  }
}
