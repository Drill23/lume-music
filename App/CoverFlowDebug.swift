import SwiftUI
import UIKit

/// Argumentos de depuração do Cover Flow (só para validar no Simulator; sem efeito no uso normal):
///  -LMDebugCoverFlow           abre o Cover Flow logo após o lançamento
///  -LMDebugCoverFlowFake       força capas/faixas de mentira geradas localmente (sem rede)
///  -LMDebugCoverFlowLandscape  simula o acelerômetro avisando "aparelho na horizontal" (usa o mesmo caminho real)
///  -LMDebugCoverFlowFlip       vira a capa central sozinha
///  -LMDebugCoverFlowPortrait   escolhe "Continuar na vertical" sozinho
enum CoverFlowDebug {
  static func has(_ flag: String) -> Bool { CommandLine.arguments.contains(flag) }

  static var open: Bool { has("-LMDebugCoverFlow") }
  static var fake: Bool { has("-LMDebugCoverFlowFake") }
  static var landscape: Bool { has("-LMDebugCoverFlowLandscape") }
  static var flip: Bool { has("-LMDebugCoverFlowFlip") }
  static var portrait: Bool { has("-LMDebugCoverFlowPortrait") }
  static var demo: Bool { has("-LMDebugCoverFlowDemo") }

  static func launchIfRequested() {
    guard open else { return }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(3))
      AppModel.shared.showCoverFlow = true
    }
  }

  /// Capas geradas em código (gradientes + inicial), salvas em tmp como file:// para passar pelo ImagePipeline.
  @MainActor
  static func fakeItems() -> [CoverFlowItem] {
    let names: [(String, String)] = [
      ("Prisma", "Aurora Vale"), ("Noite Azul", "Lume Quartet"), ("Maré Alta", "Sol & Sal"), ("Horizonte", "Vento Norte"),
      ("Cristal", "Neon Garden"), ("Veludo", "Clara Mendes"), ("Atlas", "Os Cartógrafos"), ("Fogo Lento", "Brasa"),
      ("Lunar", "Dona Estrela"), ("Ressaca", "Maré Viva"), ("Eclipse", "Alvorada"), ("Verão 99", "Pôr do Sol Club"),
      ("Origami", "Papel & Tinta"), ("Cobre", "Metais da Serra"), ("Ondas", "Mar de Dentro"),
    ]
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lm-coverflow-debug", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return names.enumerated().map { i, n in
      let url = dir.appendingPathComponent("c\(i).png")
      if !FileManager.default.fileExists(atPath: url.path) {
        try? art(index: i, title: n.0).pngData()?.write(to: url)
      }
      let tracks = (1...9).map { k in
        Track(id: "dbg-\(i)-\(k)", title: ["Abertura", "Quase Lá", "Todo Dia", "Maré", "Interlúdio", "Fogo e Vento", "Dentro de Mim", "Última Dança", "Epílogo"][k - 1],
              artist: n.1, album: n.0, duration: Double(140 + k * 17), artworkURL: url.absoluteString)
      }
      return CoverFlowItem(id: "dbg-\(i)", title: n.0, subtitle: n.1, artworkURL: url.absoluteString, localTracks: tracks)
    }
  }

  private static func art(index: Int, title: String) -> UIImage {
    let size = CGSize(width: 600, height: 600)
    let hue = CGFloat((index * 37) % 100) / 100
    let c1 = UIColor(hue: hue, saturation: 0.75, brightness: 0.95, alpha: 1)
    let c2 = UIColor(hue: (hue + 0.18).truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: 0.45, alpha: 1)
    return UIGraphicsImageRenderer(size: size).image { ctx in
      let cg = ctx.cgContext
      let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c1.cgColor, c2.cgColor] as CFArray, locations: [0, 1])!
      cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
      UIColor.white.withAlphaComponent(0.18).setFill()
      cg.fillEllipse(in: CGRect(x: 90 + CGFloat(index % 4) * 40, y: 70, width: 340, height: 340))
      UIColor.black.withAlphaComponent(0.22).setFill()
      cg.fillEllipse(in: CGRect(x: 250, y: 260 + CGFloat(index % 3) * 20, width: 300, height: 300))
      let para = NSMutableParagraphStyle(); para.alignment = .left
      (title as NSString).draw(in: CGRect(x: 40, y: 470, width: 520, height: 110), withAttributes: [
        .font: UIFont.systemFont(ofSize: 64, weight: .heavy), .foregroundColor: UIColor.white, .paragraphStyle: para,
      ])
    }
  }
}
