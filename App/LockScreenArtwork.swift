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
    let key = "\(track.id)#\(style.rawValue)"
    if let hit = cache[key] { return hit }
    let accent = await MainActor.run { (UIColor(palette.vibrant), UIColor(palette.vibrant2)) }
    let title = track.title
    let artist = track.artist
    let img = await Task.detached(priority: .utility) { () -> UIImage? in
      switch style {
      case .vinyl: return Self.renderVinyl(cover: cover, accent: accent.0)
      case .cassette: return Self.renderCassette(cover: cover, title: title, artist: artist, accent: accent.0, accent2: accent.1)
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

  static func renderVinyl(cover: UIImage, accent: UIColor) -> UIImage {
    let S = side
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: S, height: S), format: fmt).image { rc in
      let ctx = rc.cgContext
      drawBackdrop(ctx, cover: cover, size: S)

      let c = CGPoint(x: S * 0.47, y: S * 0.52)
      let R = S * 0.42
      let disc = CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)

      // Sombra do disco
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: S * 0.02), blur: S * 0.05, color: UIColor.black.withAlphaComponent(0.7).cgColor)
      UIColor(red: 0.035, green: 0.035, blue: 0.045, alpha: 1).setFill()
      ctx.fillEllipse(in: disc)
      ctx.restoreGState()

      ctx.saveGState()
      ctx.addEllipse(in: disc)
      ctx.clip()

      // Sulcos: anéis finos com brilho levemente variável + faixas de separação entre músicas
      var r = R * 0.36
      var i = 0
      while r < R * 0.985 {
        let a = 0.035 + 0.03 * (0.5 + 0.5 * sin(Double(i) * 0.37)) + 0.015 * sin(Double(i) * 2.1)
        ctx.setStrokeColor(UIColor(white: 1, alpha: CGFloat(a)).cgColor)
        ctx.setLineWidth(0.9)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        r += 2.4
        i += 1
      }
      for gap in [0.55, 0.71, 0.86] as [CGFloat] {
        let gr = R * gap
        ctx.setStrokeColor(UIColor(white: 0, alpha: 0.85).cgColor)
        ctx.setLineWidth(3.2)
        ctx.strokeEllipse(in: CGRect(x: c.x - gr, y: c.y - gr, width: 2 * gr, height: 2 * gr))
      }

      // Reflexos de luz: duas "gravatas" opostas com bordas suaves (camadas sobrepostas)
      for base in [-0.62, -0.62 + Double.pi] {
        for layer in 0..<7 {
          let half = 0.30 - Double(layer) * 0.036
          let path = CGMutablePath()
          path.move(to: c)
          path.addArc(center: c, radius: R * 1.02, startAngle: CGFloat(base - half), endAngle: CGFloat(base + half), clockwise: false)
          path.closeSubpath()
          ctx.addPath(path)
          ctx.setFillColor(UIColor(white: 1, alpha: 0.022).cgColor)
          ctx.fillPath()
        }
      }
      // Brilho iridescente sutil com a cor da capa
      ctx.setBlendMode(.screen)
      let iri = [accent.withAlphaComponent(0.0).cgColor, accent.withAlphaComponent(0.16).cgColor, accent.withAlphaComponent(0.0).cgColor] as CFArray
      if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: iri, locations: [0, 0.5, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: disc.minX, y: disc.maxY), end: CGPoint(x: disc.maxX, y: disc.minY), options: [])
      }
      ctx.setBlendMode(.normal)
      ctx.restoreGState()

      // Borda do disco
      ctx.setStrokeColor(UIColor(white: 1, alpha: 0.10).cgColor)
      ctx.setLineWidth(2)
      ctx.strokeEllipse(in: disc.insetBy(dx: 1, dy: 1))

      // Selo = capa
      let L = R * 0.36
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

  // MARK: - Fita K7

  static func renderCassette(cover: UIImage, title: String, artist: String, accent: UIColor, accent2: UIColor) -> UIImage {
    let S = side
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: S, height: S), format: fmt).image { rc in
      let ctx = rc.cgContext
      drawBackdrop(ctx, cover: cover, size: S)
      let space = CGColorSpaceCreateDeviceRGB()

      let W = S * 0.90, H = W * 0.64
      let body = CGRect(x: (S - W) / 2, y: (S - H) / 2 + S * 0.01, width: W, height: H)
      let bodyPath = UIBezierPath(roundedRect: body, cornerRadius: W * 0.035)

      // Corpo de plástico fumê
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: S * 0.025), blur: S * 0.05, color: UIColor.black.withAlphaComponent(0.7).cgColor)
      UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1).setFill()
      bodyPath.fill()
      ctx.restoreGState()
      ctx.saveGState()
      bodyPath.addClip()
      let shell = [UIColor(white: 0.26, alpha: 1).cgColor, UIColor(white: 0.09, alpha: 1).cgColor] as CFArray
      if let g = CGGradient(colorsSpace: space, colors: shell, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.minX, y: body.maxY), options: [])
      }
      // textura de plástico: riscas horizontais finíssimas
      for k in stride(from: body.minY, to: body.maxY, by: 3) {
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.012).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: body.minX, y: k)); ctx.addLine(to: CGPoint(x: body.maxX, y: k))
        ctx.strokePath()
      }
      ctx.restoreGState()
      ctx.setStrokeColor(UIColor(white: 1, alpha: 0.16).cgColor)
      ctx.setLineWidth(2)
      UIBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1), cornerRadius: W * 0.034).stroke()

      // Parafusos
      func screw(_ p: CGPoint) {
        let r = W * 0.014
        UIColor(white: 0.55, alpha: 1).setFill()
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        ctx.setStrokeColor(UIColor(white: 0.2, alpha: 1).cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: p.x - r * 0.6, y: p.y)); ctx.addLine(to: CGPoint(x: p.x + r * 0.6, y: p.y))
        ctx.move(to: CGPoint(x: p.x, y: p.y - r * 0.6)); ctx.addLine(to: CGPoint(x: p.x, y: p.y + r * 0.6))
        ctx.strokePath()
      }
      let m = W * 0.03
      screw(CGPoint(x: body.minX + m, y: body.minY + m))
      screw(CGPoint(x: body.maxX - m, y: body.minY + m))
      screw(CGPoint(x: body.minX + m, y: body.maxY - m))
      screw(CGPoint(x: body.maxX - m, y: body.maxY - m))
      screw(CGPoint(x: body.midX, y: body.maxY - m * 0.9))

      // Rótulo = capa do álbum impressa
      let label = CGRect(x: body.minX + W * 0.065, y: body.minY + H * 0.075, width: W * 0.87, height: H * 0.64)
      let labelPath = UIBezierPath(roundedRect: label, cornerRadius: W * 0.018)
      ctx.saveGState()
      labelPath.addClip()
      drawCover(cover, in: label)
      // faixa de título (papel claro) com listras de cor da capa
      let band = CGRect(x: label.minX, y: label.minY, width: label.width, height: label.height * 0.25)
      UIColor(white: 0.97, alpha: 0.92).setFill()
      ctx.fill(band)
      accent.withAlphaComponent(0.95).setFill()
      ctx.fill(CGRect(x: band.minX, y: band.maxY, width: band.width, height: H * 0.016))
      accent2.withAlphaComponent(0.95).setFill()
      ctx.fill(CGRect(x: band.minX, y: band.maxY + H * 0.016, width: band.width, height: H * 0.010))
      ctx.restoreGState()
      ctx.setStrokeColor(UIColor(white: 0, alpha: 0.35).cgColor)
      ctx.setLineWidth(1.5)
      labelPath.stroke()

      // Lado "A" + título/artista
      let aR = band.height * 0.30
      let aC = CGPoint(x: band.minX + band.height * 0.5, y: band.midY)
      UIColor(white: 0.12, alpha: 1).setFill()
      ctx.fillEllipse(in: CGRect(x: aC.x - aR, y: aC.y - aR, width: 2 * aR, height: 2 * aR))
      let aStyle = NSMutableParagraphStyle(); aStyle.alignment = .center
      ("A" as NSString).draw(in: CGRect(x: aC.x - aR, y: aC.y - aR * 0.62, width: 2 * aR, height: 2 * aR),
                             withAttributes: [.font: UIFont.systemFont(ofSize: aR * 1.05, weight: .black), .foregroundColor: UIColor.white, .paragraphStyle: aStyle])
      let textX = aC.x + aR * 1.6
      let textW = band.maxX - textX - W * 0.03
      let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
      (title as NSString).draw(in: CGRect(x: textX, y: band.minY + band.height * 0.14, width: textW, height: band.height * 0.45),
                               withAttributes: [.font: UIFont.systemFont(ofSize: band.height * 0.34, weight: .heavy), .foregroundColor: UIColor(white: 0.1, alpha: 1), .paragraphStyle: para])
      (artist as NSString).draw(in: CGRect(x: textX, y: band.minY + band.height * 0.56, width: textW, height: band.height * 0.36),
                                withAttributes: [.font: UIFont.systemFont(ofSize: band.height * 0.24, weight: .semibold), .foregroundColor: UIColor(white: 0.3, alpha: 1), .paragraphStyle: para])

      // Janela com carretéis
      let win = CGRect(x: body.midX - W * 0.27, y: label.minY + label.height * 0.46, width: W * 0.54, height: H * 0.22)
      let winPath = UIBezierPath(roundedRect: win, cornerRadius: win.height * 0.5)
      ctx.saveGState()
      winPath.addClip()
      UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 0.95).setFill()
      ctx.fill(win)
      let hubY = win.midY
      let hubs = [CGPoint(x: win.minX + win.width * 0.21, y: hubY), CGPoint(x: win.maxX - win.width * 0.21, y: hubY)]
      let packs: [CGFloat] = [win.height * 0.95, win.height * 0.62]   // lado A no começo: mais fita à esquerda
      for (k, hub) in hubs.enumerated() {
        let pr = packs[k]
        let tape = [UIColor(red: 0.36, green: 0.22, blue: 0.13, alpha: 1).cgColor, UIColor(red: 0.18, green: 0.10, blue: 0.06, alpha: 1).cgColor] as CFArray
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: hub.x - pr, y: hub.y - pr, width: 2 * pr, height: 2 * pr))
        ctx.clip()
        if let g = CGGradient(colorsSpace: space, colors: tape, locations: [0, 1]) {
          ctx.drawRadialGradient(g, startCenter: hub, startRadius: 0, endCenter: hub, endRadius: pr, options: [])
        }
        for rr in stride(from: pr * 0.4, to: pr, by: 3) {
          ctx.setStrokeColor(UIColor(white: 1, alpha: 0.03).cgColor)
          ctx.setLineWidth(0.8)
          ctx.strokeEllipse(in: CGRect(x: hub.x - rr, y: hub.y - rr, width: 2 * rr, height: 2 * rr))
        }
        ctx.restoreGState()
      }
      // fita esticada entre os carretéis (embaixo)
      ctx.setStrokeColor(UIColor(red: 0.30, green: 0.18, blue: 0.10, alpha: 1).cgColor)
      ctx.setLineWidth(3)
      ctx.move(to: CGPoint(x: hubs[0].x, y: hubY + packs[0] - 2)); ctx.addLine(to: CGPoint(x: hubs[1].x, y: hubY + packs[1] - 2))
      ctx.strokePath()
      // cubos brancos dentados
      for hub in hubs {
        let hr = win.height * 0.24
        UIColor(white: 0.93, alpha: 1).setFill()
        ctx.fillEllipse(in: CGRect(x: hub.x - hr, y: hub.y - hr, width: 2 * hr, height: 2 * hr))
        UIColor(white: 0.08, alpha: 1).setFill()
        ctx.fillEllipse(in: CGRect(x: hub.x - hr * 0.55, y: hub.y - hr * 0.55, width: hr * 1.1, height: hr * 1.1))
        for t in 0..<6 {
          let a = CGFloat(t) / 6 * 2 * .pi
          let tp = CGPoint(x: hub.x + cos(a) * hr * 0.55, y: hub.y + sin(a) * hr * 0.55)
          UIColor(white: 0.93, alpha: 1).setFill()
          ctx.fillEllipse(in: CGRect(x: tp.x - hr * 0.13, y: tp.y - hr * 0.13, width: hr * 0.26, height: hr * 0.26))
        }
      }
      // reflexo do acrílico
      let glass = [UIColor(white: 1, alpha: 0.18).cgColor, UIColor(white: 1, alpha: 0.0).cgColor] as CFArray
      if let g = CGGradient(colorsSpace: space, colors: glass, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: win.minX, y: win.minY), end: CGPoint(x: win.minX, y: win.midY), options: [])
      }
      ctx.restoreGState()
      ctx.setStrokeColor(UIColor(white: 1, alpha: 0.25).cgColor)
      ctx.setLineWidth(2)
      winPath.stroke()

      // Trapézio inferior com as janelas da cabeça
      let topW = W * 0.68, botW = W * 0.58
      let ty = body.maxY - H * 0.17, by = body.maxY - 2
      let trap = UIBezierPath()
      trap.move(to: CGPoint(x: body.midX - topW / 2, y: ty))
      trap.addLine(to: CGPoint(x: body.midX + topW / 2, y: ty))
      trap.addLine(to: CGPoint(x: body.midX + botW / 2, y: by))
      trap.addLine(to: CGPoint(x: body.midX - botW / 2, y: by))
      trap.close()
      UIColor(white: 0.16, alpha: 1).setFill()
      trap.fill()
      ctx.setStrokeColor(UIColor(white: 1, alpha: 0.12).cgColor)
      ctx.setLineWidth(1.5)
      trap.stroke()
      let holeY = ty + (by - ty) * 0.5
      for fx in [-0.36, 0.36] as [CGFloat] {
        let r = H * 0.022
        UIColor.black.setFill()
        ctx.fillEllipse(in: CGRect(x: body.midX + fx * topW * 0.9 - r, y: holeY - r, width: 2 * r, height: 2 * r))
      }
      for fx in [-0.14, 0.14] as [CGFloat] {
        let s = H * 0.04
        UIColor.black.setFill()
        ctx.fill(CGRect(x: body.midX + fx * topW - s / 2, y: holeY - s / 2, width: s, height: s))
      }
    }
  }
}
