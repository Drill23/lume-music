import SwiftUI
import UIKit

/// Camadas pré-renderizadas da fita K7. `back` fica sob os carretéis, `front` (etiqueta com janela vazada,
/// plástico, parafusos, brilho) fica sobre eles. Nada disso é redesenhado por frame.
struct CassetteLayers {
  let back: UIImage
  let front: UIImage
  let shadow: UIImage
}

extension TapeGeo {
  static let shadowMarginX: CGFloat = 0.15
  static let shadowMarginTop: CGFloat = 0.06
  static let shadowMarginBottom: CGFloat = 0.18
}

private struct TapePalette {
  let bodyTop: UIColor
  let bodyBottom: UIColor
  let overlayAlpha: CGFloat
  let bed: UIColor
  let paper: UIColor
  let stripe: UIColor
  let dark: Bool
  let brand: String

  static func of(_ style: CassetteStyle) -> TapePalette {
    switch style {
    case .smokedStudio:
      return TapePalette(bodyTop: UIColor(red: 0.30, green: 0.31, blue: 0.35, alpha: 1), bodyBottom: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),
                         overlayAlpha: 0.80, bed: UIColor(white: 0.03, alpha: 1),
                         paper: UIColor(red: 0.95, green: 0.93, blue: 0.85, alpha: 1), stripe: UIColor(red: 0.88, green: 0.28, blue: 0.20, alpha: 1),
                         dark: true, brand: "LUME  ·  HIGH BIAS")
    case .crystalClear:
      return TapePalette(bodyTop: UIColor(red: 0.80, green: 0.88, blue: 0.93, alpha: 1), bodyBottom: UIColor(red: 0.55, green: 0.66, blue: 0.74, alpha: 1),
                         overlayAlpha: 0.30, bed: UIColor(red: 0.30, green: 0.40, blue: 0.48, alpha: 1),
                         paper: UIColor(red: 0.98, green: 0.98, blue: 0.95, alpha: 1), stripe: UIColor(red: 0.08, green: 0.56, blue: 0.64, alpha: 1),
                         dark: false, brand: "LUME  ·  CRYSTAL")
    case .metallicChrome:
      return TapePalette(bodyTop: UIColor(white: 0.88, alpha: 1), bodyBottom: UIColor(white: 0.46, alpha: 1),
                         overlayAlpha: 1, bed: UIColor(white: 0.05, alpha: 1),
                         paper: UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1), stripe: UIColor(red: 0.12, green: 0.15, blue: 0.24, alpha: 1),
                         dark: false, brand: "LUME  ·  CHROME TYPE II")
    case .vintageCream:
      return TapePalette(bodyTop: UIColor(red: 0.95, green: 0.91, blue: 0.80, alpha: 1), bodyBottom: UIColor(red: 0.80, green: 0.74, blue: 0.61, alpha: 1),
                         overlayAlpha: 1, bed: UIColor(white: 0.07, alpha: 1),
                         paper: UIColor(red: 0.98, green: 0.96, blue: 0.89, alpha: 1), stripe: UIColor(red: 0.64, green: 0.24, blue: 0.14, alpha: 1),
                         dark: false, brand: "LUME  ·  NORMAL BIAS")
    }
  }
}

extension LumeTextures {
  // MARK: corpo + camadas

  nonisolated static func renderCassette(style: CassetteStyle, sideB: Bool, wpx: Int) -> CassetteLayers {
    let pal = TapePalette.of(style)
    let W = CGFloat(wpx)
    let H = (W / TapeGeo.aspect).rounded()
    let hC = H / W
    let corner = 0.034 * W
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * W, y: y * W) }
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * W, y: y * W, width: w * W, height: h * W) }
    let bodyRect = CGRect(x: 0, y: 0, width: W, height: H)
    let bodyPath = UIBezierPath(roundedRect: bodyRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: corner)
    let labelRect = R(TapeGeo.labelRect.minX, TapeGeo.labelRect.minY, TapeGeo.labelRect.width, TapeGeo.labelRect.height)
    let winRect = R(TapeGeo.windowRect.minX, TapeGeo.windowRect.minY, TapeGeo.windowRect.width, TapeGeo.windowRect.height)
    let winPath = UIBezierPath(roundedRect: winRect, cornerRadius: 0.06 * W)
    let labelPath = UIBezierPath(roundedRect: labelRect, cornerRadius: 0.014 * W)

    // Aberturas da borda inferior (cabeçote, roletes, furos de guia)
    let holes: [UIBezierPath] = [
      UIBezierPath(roundedRect: R(0.452, 0.572, 0.096, hC - 0.572 + 0.02), cornerRadius: 0.006 * W),
      UIBezierPath(roundedRect: R(0.250, 0.566, 0.082, hC - 0.566 + 0.02), cornerRadius: 0.012 * W),
      UIBezierPath(roundedRect: R(0.668, 0.566, 0.082, hC - 0.566 + 0.02), cornerRadius: 0.012 * W),
      UIBezierPath(ovalIn: CGRect(x: 0.118 * W - 0.0105 * W, y: 0.6035 * W - 0.0105 * W, width: 0.021 * W, height: 0.021 * W)),
      UIBezierPath(ovalIn: CGRect(x: 0.882 * W - 0.0105 * W, y: 0.6035 * W - 0.0105 * W, width: 0.021 * W, height: 0.021 * W)),
    ]

    // ---------- Sombra (independente de estilo)
    let mX = TapeGeo.shadowMarginX * W, mT = TapeGeo.shadowMarginTop * W, mB = TapeGeo.shadowMarginBottom * W
    let shadow = canvas(Int(W + 2 * mX), Int(H + mT + mB)) { ctx in
      let r = CGRect(x: mX, y: mT, width: W, height: H)
      ctx.setShadow(offset: CGSize(width: 0, height: 0.035 * W), blur: 0.05 * W, color: UIColor(white: 0, alpha: 0.62).cgColor)
      ctx.setFillColor(UIColor.black.cgColor)
      ctx.addPath(UIBezierPath(roundedRect: r, cornerRadius: corner).cgPath)
      ctx.fillPath()
      ctx.setShadow(offset: .zero, blur: 0, color: nil)
      ctx.setBlendMode(.clear)
      ctx.addPath(UIBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: corner).cgPath)
      ctx.fillPath()
    }

    // ---------- Camada de trás
    let back = canvas(wpx, Int(H)) { ctx in
      ctx.saveGState()
      ctx.addPath(bodyPath.cgPath); ctx.clip()
      ctx.drawLinearGradient(gradient([pal.bodyTop, pal.bodyBottom]), start: .zero, end: CGPoint(x: 0, y: H), options: [])

      // Leito escuro da janela + poços dos carretéis
      let bed = winRect.insetBy(dx: -0.012 * W, dy: -0.012 * W)
      ctx.setFillColor(pal.bed.cgColor)
      ctx.addPath(UIBezierPath(roundedRect: bed, cornerRadius: 0.07 * W).cgPath); ctx.fillPath()
      for rc in [TapeGeo.reelL, TapeGeo.reelR] {
        let c = P(rc.x, rc.y)
        ctx.saveGState()
        ctx.addEllipse(in: circle(c, 0.092 * W)); ctx.clip()
        ctx.drawRadialGradient(gradient([UIColor(white: pal.dark ? 0.16 : 0.34, alpha: 1), UIColor(white: pal.dark ? 0.02 : 0.10, alpha: 1)], [0, 1]),
                               startCenter: c, startRadius: 0.02 * W, endCenter: c, endRadius: 0.092 * W, options: [])
        ctx.restoreGState()
        ctx.setStrokeColor(gray(1, 0.14).cgColor)
        ctx.setLineWidth(max(1, 0.0025 * W))
        ctx.strokeEllipse(in: circle(c, 0.090 * W))
        // dentes da engrenagem do carretel (anel de 24 dentes sob a fita)
        ctx.setStrokeColor(gray(1, 0.10).cgColor)
        for k in 0..<24 {
          let a = CGFloat(k) / 24 * 2 * .pi
          ctx.move(to: CGPoint(x: c.x + 0.047 * W * cos(a), y: c.y + 0.047 * W * sin(a)))
          ctx.addLine(to: CGPoint(x: c.x + 0.055 * W * cos(a), y: c.y + 0.055 * W * sin(a)))
        }
        ctx.strokePath()
      }

      // Roletes guia, sapata e fita esticada na borda inferior
      for rp in [TapeGeo.rollerL, TapeGeo.rollerR] {
        let c = P(rp.x, rp.y)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 0.004 * W), blur: 0.008 * W, color: gray(0, 0.6).cgColor)
        ctx.setFillColor(gray(0.7).cgColor)
        ctx.fillEllipse(in: circle(c, 0.0165 * W))
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addEllipse(in: circle(c, 0.0165 * W)); ctx.clip()
        ctx.drawRadialGradient(gradient([gray(1), gray(0.7), gray(0.35)], [0, 0.5, 1]),
                               startCenter: CGPoint(x: c.x - 0.005 * W, y: c.y - 0.005 * W), startRadius: 0, endCenter: c, endRadius: 0.02 * W, options: [])
        ctx.restoreGState()
        ctx.setFillColor(gray(0.1).cgColor)
        ctx.fillEllipse(in: circle(c, 0.005 * W))
      }
      ctx.setFillColor(UIColor(white: 0.62, alpha: 1).cgColor)
      ctx.fill(R(0.42, 0.572, 0.16, 0.026))
      ctx.setFillColor(gray(1, 0.35).cgColor)
      ctx.fill(R(0.42, 0.572, 0.16, 0.004))
      // fita esticada
      ctx.setStrokeColor(UIColor(red: 0.30, green: 0.18, blue: 0.10, alpha: 1).cgColor)
      ctx.setLineWidth(0.0055 * W)
      ctx.move(to: P(TapeGeo.rollerL.x, 0.6105)); ctx.addLine(to: P(TapeGeo.rollerR.x, 0.6105)); ctx.strokePath()
      ctx.setStrokeColor(gray(1, 0.22).cgColor)
      ctx.setLineWidth(0.0014 * W)
      ctx.move(to: P(TapeGeo.rollerL.x, 0.6085)); ctx.addLine(to: P(TapeGeo.rollerR.x, 0.6085)); ctx.strokePath()
      ctx.restoreGState()
    }

    // ---------- Camada da frente
    let front = canvas(wpx, Int(H)) { ctx in
      // 1) plástico (translúcido no fumê/cristal) com o recorte da etiqueta e das aberturas
      ctx.saveGState()
      ctx.addPath(bodyPath.cgPath)
      ctx.addPath(labelPath.cgPath)
      ctx.clip(using: .evenOdd)
      let top = pal.bodyTop.withAlphaComponent(pal.overlayAlpha), bot = pal.bodyBottom.withAlphaComponent(pal.overlayAlpha)
      ctx.drawLinearGradient(gradient([top, bot]), start: .zero, end: CGPoint(x: 0, y: H), options: [])
      // reflexos de plástico nas laterais
      ctx.drawLinearGradient(gradient([gray(1, 0.0), gray(1, pal.dark ? 0.10 : 0.30), gray(1, 0.0)], [0, 0.5, 1]),
                             start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0.055 * W, y: 0), options: [])
      ctx.drawLinearGradient(gradient([gray(1, 0.0), gray(1, pal.dark ? 0.06 : 0.20), gray(1, 0.0)], [0, 0.5, 1]),
                             start: CGPoint(x: 0.945 * W, y: 0), end: CGPoint(x: W, y: 0), options: [])
      // recesso trapezoidal inferior
      let trap = UIBezierPath()
      trap.move(to: P(0.215, 0.452)); trap.addLine(to: P(0.785, 0.452))
      trap.addLine(to: P(0.895, hC - 0.004)); trap.addLine(to: P(0.105, hC - 0.004)); trap.close()
      ctx.setFillColor(UIColor(white: 0, alpha: pal.dark ? 0.34 : 0.20).cgColor)
      ctx.addPath(trap.cgPath); ctx.fillPath()
      ctx.setStrokeColor(gray(1, pal.dark ? 0.20 : 0.55).cgColor)
      ctx.setLineWidth(max(1, 0.0028 * W))
      ctx.move(to: P(0.215, 0.452)); ctx.addLine(to: P(0.785, 0.452)); ctx.strokePath()
      ctx.setStrokeColor(gray(0, 0.40).cgColor)
      ctx.move(to: P(0.215, 0.4565)); ctx.addLine(to: P(0.105, hC - 0.004)); ctx.move(to: P(0.785, 0.4565)); ctx.addLine(to: P(0.895, hC - 0.004)); ctx.strokePath()
      ctx.restoreGState()

      // aberturas (vazadas)
      ctx.saveGState()
      ctx.setBlendMode(.clear)
      for h in holes { ctx.addPath(h.cgPath); ctx.fillPath() }
      ctx.restoreGState()
      for h in holes {
        ctx.setStrokeColor(gray(0, 0.6).cgColor); ctx.setLineWidth(max(1, 0.0025 * W))
        ctx.addPath(h.cgPath); ctx.strokePath()
      }

      // 2) etiqueta de papel com janela vazada
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: 0.003 * W), blur: 0.006 * W, color: gray(0, 0.5).cgColor)
      ctx.setFillColor(pal.paper.cgColor)
      ctx.addPath(labelPath.cgPath); ctx.addPath(winPath.cgPath)
      ctx.fillPath(using: .evenOdd)
      ctx.restoreGState()

      ctx.saveGState()
      ctx.addPath(labelPath.cgPath); ctx.addPath(winPath.cgPath)
      ctx.clip(using: .evenOdd)
      ctx.drawLinearGradient(gradient([gray(1, 0.35), gray(0, 0.06)]), start: CGPoint(x: 0, y: labelRect.minY), end: CGPoint(x: 0, y: labelRect.maxY), options: [])
      tileNoise(ctx, rect: labelRect, alpha: 0.16, mode: .multiply, seed: 9)

      // faixa colorida superior
      let stripeR = R(TapeGeo.labelRect.minX, TapeGeo.labelRect.minY, TapeGeo.labelRect.width, 0.052)
      ctx.setFillColor(pal.stripe.cgColor); ctx.fill(stripeR)
      ctx.setFillColor(gray(1, 0.16).cgColor); ctx.fill(CGRect(x: stripeR.minX, y: stripeR.minY, width: stripeR.width, height: 0.0035 * W))

      // linhas pautadas para a escrita à mão
      ctx.setStrokeColor(UIColor(red: 0.42, green: 0.52, blue: 0.70, alpha: 0.55).cgColor)
      ctx.setLineWidth(max(0.8, 0.0018 * W))
      for y in [0.152, 0.190] as [CGFloat] {
        ctx.move(to: P(0.085, y)); ctx.addLine(to: P(0.775, y))
      }
      ctx.strokePath()
      ctx.restoreGState()

      // moldura do espaço da capa (estilo foto instantânea)
      let artFrame = R(0.826, 0.100, 0.094, 0.094)
      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: 0.002 * W), blur: 0.004 * W, color: gray(0, 0.5).cgColor)
      ctx.setFillColor(gray(0.99).cgColor)
      ctx.fill(artFrame)
      ctx.restoreGState()

      // textos impressos
      func text(_ s: String, size: CGFloat, weight: UIFont.Weight, color: UIColor, x: CGFloat, y: CGFloat, align: NSTextAlignment, kern: CGFloat = 0, font: UIFont? = nil) {
        let f = font ?? UIFont.systemFont(ofSize: size * W, weight: weight)
        let para = NSMutableParagraphStyle(); para.alignment = align
        let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color, .kern: kern * W, .paragraphStyle: para])
        let sz = a.size()
        let ox = align == .right ? x * W - sz.width : (align == .center ? x * W - sz.width / 2 : x * W)
        a.draw(at: CGPoint(x: ox, y: y * W - sz.height / 2))
      }
      let letter = sideB ? "B" : "A"
      ctx.setFillColor(gray(1, 0.95).cgColor)
      ctx.fillEllipse(in: circle(P(0.092, 0.071), 0.0205 * W))
      text(letter, size: 0.030, weight: .black, color: pal.stripe, x: 0.092, y: 0.0715, align: .center)
      text(pal.brand, size: 0.0175, weight: .heavy, color: gray(1, 0.95), x: 0.5, y: 0.071, align: .center, kern: 0.002)
      text("C-60", size: 0.027, weight: .black, color: gray(1, 0.95), x: 0.925, y: 0.071, align: .right, kern: 0.001)
      let ink = UIColor(white: 0.12, alpha: 0.78)
      text(sideB ? "LADO B" : "LADO A", size: 0.0125, weight: .heavy, color: ink.withAlphaComponent(0.6), x: 0.085, y: 0.108, align: .left, kern: 0.003)
      text(letter, size: 0.098, weight: .black, color: pal.stripe.withAlphaComponent(0.9), x: 0.120, y: 0.288, align: .center)
      text("60", size: 0.066, weight: .black, color: ink.withAlphaComponent(0.7), x: 0.880, y: 0.266, align: .center)
      text("MIN", size: 0.0155, weight: .heavy, color: ink.withAlphaComponent(0.6), x: 0.880, y: 0.320, align: .center, kern: 0.002)
      text("NR  ·  TYPE I  ·  120 µs", size: 0.0128, weight: .semibold, color: ink.withAlphaComponent(0.55), x: 0.5, y: 0.3875, align: .center, kern: 0.002)

      // 3) janela: chanfro + vidro com reflexo
      ctx.setStrokeColor(gray(0, 0.75).cgColor)
      ctx.setLineWidth(max(1.2, 0.005 * W))
      ctx.addPath(winPath.cgPath); ctx.strokePath()
      ctx.saveGState()
      ctx.addPath(UIBezierPath(roundedRect: winRect.insetBy(dx: 0.002 * W, dy: 0.002 * W), cornerRadius: 0.058 * W).cgPath)
      ctx.setLineWidth(max(1, 0.0022 * W)); ctx.replacePathWithStrokedPath(); ctx.clip()
      ctx.drawLinearGradient(gradient([gray(1, 0.65), gray(1, 0.05), gray(0, 0.35)], [0, 0.5, 1]),
                             start: CGPoint(x: 0, y: winRect.minY), end: CGPoint(x: 0, y: winRect.maxY), options: [])
      ctx.restoreGState()
      ctx.saveGState()
      ctx.addPath(winPath.cgPath); ctx.clip()
      let glare = UIBezierPath()
      glare.move(to: CGPoint(x: winRect.minX + winRect.width * 0.10, y: winRect.minY))
      glare.addLine(to: CGPoint(x: winRect.minX + winRect.width * 0.34, y: winRect.minY))
      glare.addLine(to: CGPoint(x: winRect.minX + winRect.width * 0.18, y: winRect.maxY))
      glare.addLine(to: CGPoint(x: winRect.minX - winRect.width * 0.06, y: winRect.maxY))
      glare.close()
      ctx.addPath(glare.cgPath); ctx.clip()
      ctx.drawLinearGradient(gradient([gray(1, 0.0), gray(1, 0.20), gray(1, 0.0)], [0, 0.5, 1]),
                             start: CGPoint(x: winRect.minX, y: 0), end: CGPoint(x: winRect.minX + winRect.width * 0.34, y: 0), options: [])
      ctx.restoreGState()
      ctx.saveGState()
      ctx.addPath(winPath.cgPath); ctx.clip()
      ctx.drawLinearGradient(gradient([gray(1, 0.14), gray(1, 0)]), start: CGPoint(x: 0, y: winRect.minY), end: CGPoint(x: 0, y: winRect.minY + winRect.height * 0.4), options: [])
      ctx.restoreGState()

      // marcas de guia na borda da janela (régua de fita)
      ctx.setStrokeColor(gray(0, 0.4).cgColor); ctx.setLineWidth(max(0.8, 0.0016 * W))
      for k in 0..<7 {
        let x = (0.43 + CGFloat(k) * 0.023) * W
        ctx.move(to: CGPoint(x: x, y: winRect.maxY - 0.0075 * W)); ctx.addLine(to: CGPoint(x: x, y: winRect.maxY - 0.0015 * W))
      }
      ctx.strokePath()

      // 4) parafusos
      for p in [P(0.040, 0.040), P(0.960, 0.040), P(0.040, hC - 0.040), P(0.960, hC - 0.040), P(0.5, 0.0215)] {
        screw(ctx, at: p, r: 0.0125 * W)
      }
      screw(ctx, at: P(0.5, 0.4765), r: 0.0125 * W)

      // 5) contorno chanfrado, brilho e grão de plástico
      ctx.saveGState()
      ctx.addPath(bodyPath.cgPath); ctx.clip()
      ctx.drawLinearGradient(gradient([gray(1, pal.dark ? 0.16 : 0.34), gray(1, 0)], [0, 1]),
                             start: .zero, end: CGPoint(x: W * 0.5, y: H * 0.9), options: [])
      ctx.restoreGState()
      ctx.saveGState()
      ctx.addPath(bodyPath.cgPath)
      ctx.setLineWidth(max(1.2, 0.007 * W)); ctx.replacePathWithStrokedPath(); ctx.clip()
      ctx.drawLinearGradient(gradient([gray(1, pal.dark ? 0.55 : 0.95), gray(1, 0.12), gray(0, 0.45)], [0, 0.5, 1]),
                             start: .zero, end: CGPoint(x: W, y: H), options: [])
      ctx.restoreGState()
      ctx.saveGState()
      ctx.addPath(UIBezierPath(roundedRect: bodyRect.insetBy(dx: 0.008 * W, dy: 0.008 * W), cornerRadius: corner * 0.8).cgPath)
      ctx.setLineWidth(max(0.8, 0.0018 * W)); ctx.replacePathWithStrokedPath(); ctx.clip()
      ctx.drawLinearGradient(gradient([gray(0, 0.28), gray(1, 0.25)], [0, 1]), start: .zero, end: CGPoint(x: W, y: H), options: [])
      ctx.restoreGState()
      ctx.saveGState()
      ctx.addPath(bodyPath.cgPath)
      ctx.addPath(labelPath.cgPath)
      ctx.clip(using: .evenOdd)
      tileNoise(ctx, rect: bodyRect, alpha: pal.dark ? 0.16 : 0.10, mode: .overlay, seed: 21)
      ctx.restoreGState()
    }
    return CassetteLayers(back: back, front: front, shadow: shadow)
  }

  // MARK: carretel (hub) com dentes brancos

  nonisolated static func renderHub(px: Int) -> UIImage {
    canvas(px, px) { ctx in
      let D = CGFloat(px)
      let c = CGPoint(x: D / 2, y: D / 2)
      let R = D / 2 - 1
      ctx.saveGState()
      ctx.setShadow(offset: .zero, blur: D * 0.03, color: gray(0, 0.5).cgColor)
      ctx.setFillColor(gray(0.9).cgColor)
      ctx.fillEllipse(in: circle(c, R))
      ctx.restoreGState()
      ctx.saveGState()
      ctx.addEllipse(in: circle(c, R)); ctx.clip()
      ctx.drawRadialGradient(gradient([gray(1), gray(0.86), gray(0.62)], [0, 0.6, 1]),
                             startCenter: CGPoint(x: c.x - R * 0.3, y: c.y - R * 0.3), startRadius: 0, endCenter: c, endRadius: R * 1.1, options: [])
      ctx.restoreGState()
      // furo central escuro
      let holeR = R * 0.60
      ctx.setFillColor(gray(0.04).cgColor)
      ctx.fillEllipse(in: circle(c, holeR))
      ctx.saveGState()
      ctx.addEllipse(in: circle(c, holeR)); ctx.clip()
      ctx.drawRadialGradient(gradient([gray(0.02), gray(0.16)], [0, 1]), startCenter: c, startRadius: 0, endCenter: c, endRadius: holeR, options: [])
      ctx.restoreGState()
      // 6 dentes brancos voltados para dentro
      for k in 0..<6 {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: CGFloat(k) * .pi / 3)
        let tooth = UIBezierPath(roundedRect: CGRect(x: -R * 0.085, y: -holeR - R * 0.02, width: R * 0.17, height: R * 0.30), cornerRadius: R * 0.03)
        ctx.addPath(tooth.cgPath)
        ctx.setFillColor(gray(0.95).cgColor)
        ctx.fillPath()
        ctx.setStrokeColor(gray(0, 0.35).cgColor); ctx.setLineWidth(max(1, R * 0.018))
        ctx.addPath(tooth.cgPath); ctx.strokePath()
        ctx.restoreGState()
      }
      ctx.setStrokeColor(gray(0, 0.4).cgColor)
      ctx.setLineWidth(max(1, R * 0.03))
      ctx.strokeEllipse(in: circle(c, R))
      ctx.setStrokeColor(gray(1, 0.8).cgColor)
      ctx.setLineWidth(max(1, R * 0.02))
      ctx.strokeEllipse(in: circle(c, R * 0.9))
    }
  }

  // MARK: rolo de fita marrom

  nonisolated static func renderPack(px: Int) -> UIImage {
    canvas(px, px) { ctx in
      let D = CGFloat(px)
      let c = CGPoint(x: D / 2, y: D / 2)
      let R = D / 2 - 1
      var rng = TextureRNG(77)
      ctx.saveGState()
      ctx.addEllipse(in: circle(c, R)); ctx.clip()
      ctx.drawRadialGradient(gradient([UIColor(red: 0.20, green: 0.12, blue: 0.07, alpha: 1), UIColor(red: 0.30, green: 0.18, blue: 0.10, alpha: 1), UIColor(red: 0.24, green: 0.14, blue: 0.08, alpha: 1)], [0, 0.7, 1]),
                             startCenter: c, startRadius: 0, endCenter: c, endRadius: R, options: [])
      var r = R
      while r > R * 0.2 {
        ctx.setStrokeColor(UIColor(white: rng.next() > 0.5 ? 1 : 0, alpha: rng.range(0.03, 0.10)).cgColor)
        ctx.setLineWidth(max(0.6, D * 0.0022))
        ctx.strokeEllipse(in: circle(c, r))
        r -= rng.range(D * 0.004, D * 0.011)
      }
      // brilho do óxido: lóbulos opostos (anisotropia da fita)
      for ang in [0.9, 0.9 + Double.pi] {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: CGFloat(ang))
        ctx.drawLinearGradient(gradient([gray(1, 0), gray(1, 0.13), gray(1, 0)], [0, 0.5, 1]),
                               start: CGPoint(x: 0, y: -R * 0.35), end: CGPoint(x: 0, y: R * 0.35), options: [])
        ctx.restoreGState()
      }
      ctx.restoreGState()
      ctx.setStrokeColor(UIColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 0.9).cgColor)
      ctx.setLineWidth(max(1, D * 0.008))
      ctx.strokeEllipse(in: circle(c, R * 0.992))
    }
  }

  // MARK: mostrador do VU analógico (a agulha é dinâmica)

  nonisolated static func renderVUFace(w: Int, h: Int) -> UIImage {
    canvas(w, h) { ctx in
      let W = CGFloat(w), H = CGFloat(h)
      let rect = CGRect(x: 0, y: 0, width: W, height: H)
      let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: H * 0.16)
      ctx.saveGState()
      ctx.addPath(path.cgPath); ctx.clip()
      ctx.drawLinearGradient(gradient([UIColor(red: 1.0, green: 0.94, blue: 0.80, alpha: 1), UIColor(red: 0.97, green: 0.80, blue: 0.54, alpha: 1)]),
                             start: .zero, end: CGPoint(x: 0, y: H), options: [])
      ctx.drawRadialGradient(gradient([gray(1, 0.55), gray(1, 0)]), startCenter: CGPoint(x: W / 2, y: H * 1.05), startRadius: 0,
                             endCenter: CGPoint(x: W / 2, y: H * 1.05), endRadius: W * 0.7, options: [])
      let pivot = CGPoint(x: W / 2, y: H * 1.0)
      let radius = H * 0.82
      for k in 0...10 {
        let f = CGFloat(k) / 10
        let ang = (-50 + 100 * f) * .pi / 180
        let inner = radius * (k % 2 == 0 ? 0.82 : 0.89)
        ctx.setStrokeColor(f > 0.72 ? UIColor(red: 0.85, green: 0.1, blue: 0.08, alpha: 1).cgColor : gray(0, 0.75).cgColor)
        ctx.setLineWidth(max(1, H * (k % 2 == 0 ? 0.028 : 0.016)))
        ctx.move(to: CGPoint(x: pivot.x + inner * sin(ang), y: pivot.y - inner * cos(ang)))
        ctx.addLine(to: CGPoint(x: pivot.x + radius * sin(ang), y: pivot.y - radius * cos(ang)))
        ctx.strokePath()
      }
      func arcPath(_ r: CGFloat, _ d0: CGFloat, _ d1: CGFloat) {
        // polilinha (evita a ambiguidade de sentido do addArc em contexto invertido)
        for k in 0...24 {
          let d = (d0 + (d1 - d0) * CGFloat(k) / 24) * .pi / 180
          let pt = CGPoint(x: pivot.x + r * sin(d), y: pivot.y - r * cos(d))
          if k == 0 { ctx.move(to: pt) } else { ctx.addLine(to: pt) }
        }
      }
      ctx.setStrokeColor(gray(0, 0.6).cgColor); ctx.setLineWidth(max(1, H * 0.016))
      arcPath(radius, -50, 50); ctx.strokePath()
      ctx.setStrokeColor(UIColor(red: 0.85, green: 0.1, blue: 0.08, alpha: 1).cgColor); ctx.setLineWidth(max(2, H * 0.05))
      arcPath(radius * 0.97, 22, 50); ctx.strokePath()
      let f = UIFont.systemFont(ofSize: H * 0.26, weight: .heavy)
      let a = NSAttributedString(string: "VU", attributes: [.font: f, .foregroundColor: UIColor(white: 0, alpha: 0.65)])
      a.draw(at: CGPoint(x: W / 2 - a.size().width / 2, y: H * 0.40))
      ctx.restoreGState()
      ctx.addPath(path.cgPath)
      ctx.setStrokeColor(gray(0, 0.55).cgColor); ctx.setLineWidth(max(1, H * 0.03)); ctx.strokePath()
      ctx.saveGState()
      ctx.addPath(path.cgPath); ctx.clip()
      ctx.drawLinearGradient(gradient([gray(1, 0.35), gray(1, 0), gray(1, 0)], [0, 0.5, 1]), start: .zero, end: CGPoint(x: 0, y: H), options: [])
      ctx.restoreGState()
    }
  }
}
