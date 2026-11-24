import UIKit
import SwiftUI

/// Gerador procedural de texturas de estúdio em CoreGraphics com cache em memória + disco (upload único GPU a 120Hz).
@MainActor
final class LumeTextures {
  static let shared = LumeTextures()

  private var surfaceCache: [String: UIImage] = [:]
  private var vinylCache: [String: UIImage] = [:]
  private var didPrewarm = false

  nonisolated private static let cacheDir: URL? = {
    guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    let dir = base.appendingPathComponent("LumeTextures", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()

  private init() {}

  func brushedSurface(styleId: Int, size: Int = 512) -> UIImage {
    let key = "surf_v42_\(styleId)_\(size)"
    if let hit = surfaceCache[key] { return hit }
    if let disk = Self.loadFromDisk(key: key) {
      surfaceCache[key] = disk
      return disk
    }
    let img = Self.renderBrushedSurface(styleId: styleId, size: size)
    surfaceCache[key] = img
    Self.saveToDiskAsync(img, key: key)
    return img
  }

  func vinylDisc(edition: VinylEdition, size: Int = 768) -> UIImage {
    let key = "vinyl_v42_\(edition.rawValue)_\(size)"
    if let hit = vinylCache[key] { return hit }
    if let disk = Self.loadFromDisk(key: key) {
      vinylCache[key] = disk
      return disk
    }
    let img = Self.renderVinylDisc(edition: edition, size: size)
    vinylCache[key] = img
    Self.saveToDiskAsync(img, key: key)
    return img
  }

  /// Pré-carrega / gera em background sem bloquear o fluxo principal na abertura do app.
  func prewarmInBackground() {
    guard !didPrewarm else { return }
    didPrewarm = true
    let editions = VinylEdition.allCases
    Task.detached(priority: .utility) {
      var loadedSurfaces: [String: UIImage] = [:]
      var loadedVinyls: [String: UIImage] = [:]
      for styleId in 0..<4 {
        let key = "surf_v42_\(styleId)_512"
        if let disk = Self.loadFromDisk(key: key) {
          loadedSurfaces[key] = disk
        } else {
          let img = Self.renderBrushedSurface(styleId: styleId, size: 512)
          Self.saveToDiskSync(img, key: key)
          loadedSurfaces[key] = img
        }
      }
      for ed in editions {
        let key = "vinyl_v42_\(ed.rawValue)_768"
        if let disk = Self.loadFromDisk(key: key) {
          loadedVinyls[key] = disk
        } else {
          let img = Self.renderVinylDisc(edition: ed, size: 768)
          Self.saveToDiskSync(img, key: key)
          loadedVinyls[key] = img
        }
      }
      let surfacesSnapshot = loadedSurfaces
      let vinylsSnapshot = loadedVinyls
      await MainActor.run {
        for (k, v) in surfacesSnapshot where self.surfaceCache[k] == nil { self.surfaceCache[k] = v }
        for (k, v) in vinylsSnapshot where self.vinylCache[k] == nil { self.vinylCache[k] = v }
      }
    }
  }

  nonisolated private static func diskURL(key: String) -> URL? {
    let safe = key.replacingOccurrences(of: "[^A-Za-z0-9_.-]", with: "_", options: .regularExpression)
    return cacheDir?.appendingPathComponent("\(safe).png")
  }

  nonisolated private static func loadFromDisk(key: String) -> UIImage? {
    guard let url = diskURL(key: key) else { return nil }
    return UIImage(contentsOfFile: url.path)
  }

  nonisolated private static func saveToDiskSync(_ image: UIImage, key: String) {
    guard let url = diskURL(key: key), let data = image.pngData() else { return }
    try? data.write(to: url, options: .atomic)
  }

  nonisolated private static func saveToDiskAsync(_ image: UIImage, key: String) {
    Task.detached(priority: .background) {
      saveToDiskSync(image, key: key)
    }
  }

  // MARK: - Brushed Surfaces (Prata, Obsidian, Nogueira, Ouro)

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
        case 0: // Prata Estúdio
          r = 0.86 - 0.16 * v + (grain - 0.5) * 0.052 + sheen
          g = 0.88 - 0.15 * v + (grain - 0.5) * 0.052 + sheen
          b = 0.91 - 0.14 * v + (grain - 0.5) * 0.052 + sheen
        case 1: // Obsidian Pro
          r = 0.16 - 0.08 * v + (grain - 0.5) * 0.030 + sheen * 0.45
          g = 0.165 - 0.08 * v + (grain - 0.5) * 0.030 + sheen * 0.45
          b = 0.19 - 0.09 * v + (grain - 0.5) * 0.030 + sheen * 0.45
        case 2: // Nogueira Vintage
          let ring = (woodBase * cos(sin(u * 6.5) * 2.2 + u * 3.0)) * 0.5 + 0.5
          let wFactor = ring * 0.78 + fine * 0.12
          r = 0.18 + (0.36 - 0.18) * wFactor + sheen * 0.30
          g = 0.10 + (0.20 - 0.10) * wFactor + sheen * 0.24
          b = 0.06 + (0.11 - 0.06) * wFactor + sheen * 0.18
        default: // Titânio Dourado
          r = 0.84 - 0.22 * v + (grain - 0.5) * 0.048 + sheen * 1.05
          g = 0.74 - 0.23 * v + (grain - 0.5) * 0.048 + sheen * 0.95
          b = 0.55 - 0.21 * v + (grain - 0.5) * 0.048 + sheen * 0.75
        }

        let edge = min(min(u, 1.0 - u), edgeV)
        let vig = edge < 0.05 ? (0.88 + 0.12 * (edge / 0.05)) : 1.0
        let i = (y * w + x) * 4
        px[i]     = UInt8(min(255, max(0, r * vig * 255.0)))
        px[i + 1] = UInt8(min(255, max(0, g * vig * 255.0)))
        px[i + 2] = UInt8(min(255, max(0, b * vig * 255.0)))
        px[i + 3] = 255
      }
    }
    return imageFromRGBA(px, width: w, height: h)
  }

  // MARK: - Vinyl Discs (Microssulcos fotorrealistas sem moiré)

  nonisolated static func renderVinylDisc(edition: VinylEdition, size: Int) -> UIImage {
    let w = size, h = size
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let cx = Double(w) * 0.5
    let cy = Double(h) * 0.5
    let invMaxR = 1.0 / (Double(min(w, h)) * 0.5)

    for y in 0..<h {
      let dy = Double(y) - cy
      let dy2 = dy * dy
      for x in 0..<w {
        let dx = Double(x) - cx
        let rn = sqrt(dx * dx + dy2) * invMaxR
        guard rn <= 1.0 && rn >= 0.33 else { continue }

        let theta = atan2(dy, dx)
        // 118 sulcos concêntricos abaixo da frequência de Nyquist para zero moiré
        let microGroove = sin(rn * 118.0 * 6.2831853 + sin(theta * 2.0) * 0.08) * 0.5 + 0.5
        // Dinâmica natural de compressão entre faixas do álbum
        let dynamics = (sin(rn * 19.0) * 0.5 + cos(rn * 41.0) * 0.3 + 0.8) * 0.5

        // Espaços entre faixas (lead-in gaps) com multiplicação direta (sem pow())
        let d1 = (rn - 0.51) * 185.0
        let d2 = (rn - 0.64) * 185.0
        let d3 = (rn - 0.77) * 185.0
        let d4 = (rn - 0.89) * 185.0
        let gaps = max(max(exp(-(d1 * d1)), exp(-(d2 * d2))), max(exp(-(d3 * d3)), exp(-(d4 * d4))))

        let deadWax = rn < 0.39 ? max(0.0, min(1.0, (0.39 - rn) / 0.028)) : 0.0
        let leadIn = rn > 0.968 ? max(0.0, min(1.0, (rn - 0.968) / 0.028)) : 0.0
        let rimHighlight = rn > 0.985 ? max(0.0, 1.0 - abs(rn - 0.991) / 0.006) * 0.11 : 0.0

        var red: Double, green: Double, blue: Double, alpha: Double = 1.0

        switch edition {
        case .classicBlack:
          // Vinil 180g preto profundo com sulcos sutis de grafite e borda chanfrada
          var gVal = 0.038 + microGroove * (0.022 + 0.016 * dynamics) + dynamics * 0.012
          let smoothZone = gaps * 0.72 + deadWax * 0.45
          gVal = gVal * (1.0 - smoothZone) + 0.020 * smoothZone
          gVal += leadIn * 0.055 + rimHighlight
          red = gVal; green = gVal * 1.01; blue = gVal * 1.03
        case .prismCrystal:
          let swirl = theta + rn * 3.0
          let ir = 0.54 + 0.32 * sin(swirl)
          let ig = 0.46 + 0.30 * sin(swirl + 1.9)
          let ib = 0.72 + 0.22 * cos(swirl)
          let m = 0.56 + microGroove * 0.22 - gaps * 0.16 + leadIn * 0.15 + rimHighlight
          red = ir * m; green = ig * m; blue = ib * m
          alpha = 0.88
        case .limitedGold:
          let m = 0.44 + microGroove * 0.26 + dynamics * 0.14 - gaps * 0.20 + leadIn * 0.15 + rimHighlight
          red = 0.44 + 0.38 * m
          green = 0.30 + 0.30 * m
          blue = 0.09 + 0.14 * m
        case .whiteMarble:
          let marble = sin(rn * 12.0 + sin(theta * 3.0) * 1.4) * 0.5 + 0.5
          let m = marble * 0.68 + microGroove * 0.22
          let base = 0.74 + 0.19 * m - gaps * 0.08 - leadIn * 0.07 + rimHighlight * 0.4
          red = base; green = base * 0.99; blue = base * 1.02
        }

        if rn > 0.993 {
          alpha *= max(0.0, (1.0 - rn) / 0.007)
        } else if rn < 0.336 {
          alpha *= max(0.0, (rn - 0.33) / 0.006)
        }

        let i = (y * w + x) * 4
        px[i]     = UInt8(min(255, max(0, red * 255.0)))
        px[i + 1] = UInt8(min(255, max(0, green * 255.0)))
        px[i + 2] = UInt8(min(255, max(0, blue * 255.0)))
        px[i + 3] = UInt8(min(255, max(0, alpha * 255.0)))
      }
    }
    return imageFromRGBA(px, width: w, height: h)
  }

  nonisolated private static func imageFromRGBA(_ px: [UInt8], width: Int, height: Int) -> UIImage {
    let data = Data(px)
    guard let provider = CGDataProvider(data: data as CFData),
          let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          ) else { return UIImage() }
    return UIImage(cgImage: cg)
  }
}
