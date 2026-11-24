import UIKit
import SwiftUI

/// Gerador procedural de texturas de estúdio em CoreGraphics com cache único em memória (upload único GPU a 120Hz).
@MainActor
final class LumeTextures {
  static let shared = LumeTextures()

  private var surfaceCache: [String: UIImage] = [:]
  private var vinylCache: [String: UIImage] = [:]

  private init() {}

  func brushedSurface(styleId: Int, size: Int = 512) -> UIImage {
    let key = "surf_\(styleId)_\(size)"
    if let hit = surfaceCache[key] { return hit }
    let img = Self.renderBrushedSurface(styleId: styleId, size: size)
    surfaceCache[key] = img
    return img
  }

  func vinylDisc(edition: VinylEdition, size: Int = 640) -> UIImage {
    let key = "vinyl_\(edition.rawValue)_\(size)"
    if let hit = vinylCache[key] { return hit }
    let img = Self.renderVinylDisc(edition: edition, size: size)
    vinylCache[key] = img
    return img
  }

  // MARK: - Brushed Surfaces (Prata, Obsidian, Nogueira, Ouro)

  private static func renderBrushedSurface(styleId: Int, size: Int) -> UIImage {
    let w = size, h = size
    var px = [UInt8](repeating: 255, count: w * h * 4)
    let invW = 1.0 / Double(w)
    let invH = 1.0 / Double(h)

    // Pré-computa ruído anisotrópico por linha para velocidade
    var rowNoise = [Double](repeating: 0, count: h)
    for y in 0..<h {
      let s = sin(Double(y) * 1.4 * 12.9898 + 4.1414) * 43758.5453
      rowNoise[y] = s - floor(s)
    }

    for y in 0..<h {
      let v = Double(y) * invH
      let rn = rowNoise[y]
      for x in 0..<w {
        let u = Double(x) * invW
        let diag = u * 0.65 + v * 0.35
        let d1 = (diag - 0.38) * 4.5
        let d2 = (diag - 0.78) * 6.0
        let sheen = exp(-(d1 * d1)) * 0.15 + exp(-(d2 * d2)) * 0.08

        let fineSeed = sin(Double(x / 3) * 12.9898 + Double(y) * 78.233) * 43758.5453
        let fine = fineSeed - floor(fineSeed)
        let grain = rn * 0.75 + fine * 0.25

        var r: Double, g: Double, b: Double
        switch styleId {
        case 0: // Prata Estúdio
          r = 0.86 - 0.16 * v + (grain - 0.5) * 0.055 + sheen
          g = 0.88 - 0.15 * v + (grain - 0.5) * 0.055 + sheen
          b = 0.91 - 0.14 * v + (grain - 0.5) * 0.055 + sheen
        case 1: // Obsidian Pro
          r = 0.16 - 0.08 * v + (grain - 0.5) * 0.032 + sheen * 0.45
          g = 0.165 - 0.08 * v + (grain - 0.5) * 0.032 + sheen * 0.45
          b = 0.19 - 0.09 * v + (grain - 0.5) * 0.032 + sheen * 0.45
        case 2: // Nogueira Vintage
          let ring = sin(v * 42.0 + sin(u * 6.5) * 2.2 + u * 3.0) * 0.5 + 0.5
          let wFactor = ring * 0.78 + fine * 0.12
          r = 0.18 + (0.36 - 0.18) * wFactor + sheen * 0.30
          g = 0.10 + (0.20 - 0.10) * wFactor + sheen * 0.24
          b = 0.06 + (0.11 - 0.06) * wFactor + sheen * 0.18
        default: // Titânio Dourado
          r = 0.84 - 0.22 * v + (grain - 0.5) * 0.05 + sheen * 1.05
          g = 0.74 - 0.23 * v + (grain - 0.5) * 0.05 + sheen * 0.95
          b = 0.55 - 0.21 * v + (grain - 0.5) * 0.05 + sheen * 0.75
        }

        let edge = min(min(u, 1.0 - u), min(v, 1.0 - v))
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

  // MARK: - Vinyl Discs (Microssulcos, Pausas, Edições)

  private static func renderVinylDisc(edition: VinylEdition, size: Int) -> UIImage {
    let w = size, h = size
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let cx = Double(w) * 0.5
    let cy = Double(h) * 0.5
    let maxR = Double(min(w, h)) * 0.5

    for y in 0..<h {
      let dy = Double(y) - cy
      for x in 0..<w {
        let dx = Double(x) - cx
        let r = hypot(dx, dy)
        let rn = r / maxR
        guard rn <= 1.0 && rn >= 0.33 else { continue }

        let theta = atan2(dy, dx)
        let microGroove = sin(rn * 290.0 * 6.2831853 + sin(theta * 2.0) * 0.15) * 0.5 + 0.5
        let bandWave = sin(rn * 44.0) * 0.5 + 0.5

        let g1 = exp(-pow((rn - 0.53) * 140.0, 2.0))
        let g2 = exp(-pow((rn - 0.66) * 140.0, 2.0))
        let g3 = exp(-pow((rn - 0.79) * 140.0, 2.0))
        let g4 = exp(-pow((rn - 0.91) * 140.0, 2.0))
        let gaps = max(max(g1, g2), max(g3, g4))
        let deadWax = rn < 0.39 ? max(0.0, min(1.0, (0.39 - rn) / 0.03)) : 0.0
        let leadIn = rn > 0.965 ? max(0.0, min(1.0, (rn - 0.965) / 0.03)) : 0.0

        var red: Double, green: Double, blue: Double, alpha: Double = 1.0

        switch edition {
        case .classicBlack:
          var gVal = 0.055 + microGroove * 0.038 + bandWave * 0.015
          gVal = gVal * (1.0 - (gaps * 0.65 + deadWax * 0.35)) + 0.025 * (gaps * 0.65 + deadWax * 0.35)
          gVal += leadIn * 0.10
          red = gVal; green = gVal; blue = gVal * 1.04
        case .prismCrystal:
          let swirl = theta + rn * 3.2
          let ir = 0.56 + 0.34 * sin(swirl)
          let ig = 0.48 + 0.32 * sin(swirl + 1.9)
          let ib = 0.74 + 0.24 * cos(swirl)
          let m = 0.58 + microGroove * 0.24 - gaps * 0.18 + leadIn * 0.18
          red = ir * m; green = ig * m; blue = ib * m
          alpha = 0.88
        case .limitedGold:
          let m = 0.45 + microGroove * 0.32 + bandWave * 0.15 - gaps * 0.22 + leadIn * 0.18
          red = 0.44 + 0.38 * m
          green = 0.30 + 0.30 * m
          blue = 0.09 + 0.14 * m
        case .whiteMarble:
          let marble = sin(rn * 12.0 + sin(theta * 3.0) * 1.4) * 0.5 + 0.5
          let m = marble * 0.7 + microGroove * 0.25
          let base = 0.74 + 0.20 * m - gaps * 0.08 - leadIn * 0.08
          red = base; green = base * 0.99; blue = base * 1.02
        }

        // Suavização antialias na borda externa
        if rn > 0.992 {
          alpha *= max(0.0, (1.0 - rn) / 0.008)
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

  private static func imageFromRGBA(_ px: [UInt8], width: Int, height: Int) -> UIImage {
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
