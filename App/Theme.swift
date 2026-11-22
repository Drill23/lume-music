import SwiftUI
import UIKit

/// Lume Music 2.0 Design System — True iOS 26 Native Liquid Glass (.glassEffect) + Editorial Calm Spacing,
/// deep obsidian canvas, dynamic album-extracted color mesh, tactile haptics, zero clutter.
enum Theme {
  static let credit = "Desenvolvido por A.A · Demerzel Studio"

  static let bg = Color(red: 0.035, green: 0.039, blue: 0.055)       // #090A0E
  static let surface = Color(red: 0.075, green: 0.084, blue: 0.114)  // #13151D
  static let surface2 = Color(red: 0.114, green: 0.128, blue: 0.168) // #1D212B
  static let text = Color(red: 0.968, green: 0.962, blue: 0.950)     // #F7F5F2
  static let muted = Color(red: 0.620, green: 0.638, blue: 0.695)    // #9EA3B1
  static let dim = Color(red: 0.44, green: 0.46, blue: 0.52)

  static let amber = Color(red: 1.0, green: 0.710, blue: 0.278)      // #FFB547
  static let coral = Color(red: 1.0, green: 0.420, blue: 0.420)      // #FF6B6B
  static let violet = Color(red: 0.60, green: 0.46, blue: 0.98)
  static let ok = Color(red: 0.373, green: 0.878, blue: 0.659)       // #5FE0A8
  static let ink = Color(red: 0.086, green: 0.055, blue: 0.020)

  static let aurora = LinearGradient(
    colors: [amber, coral],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static let prism = LinearGradient(
    colors: [Color(red: 0.48, green: 0.82, blue: 0.98), amber, coral, Color(red: 0.78, green: 0.48, blue: 0.96)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static let glassStroke = LinearGradient(
    colors: [Color.white.opacity(0.34), Color.white.opacity(0.10), Color.white.opacity(0.04)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static var motion: Bool { !UIAccessibility.isReduceMotionEnabled }

  static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    if UIFont(name: "Manrope", size: size) != nil {
      return Font.custom("Manrope", size: size).weight(weight)
    }
    return .system(size: size, weight: weight, design: .rounded)
  }

  static func hex(_ v: UInt32) -> Color {
    Color(
      red: Double((v >> 16) & 0xFF) / 255.0,
      green: Double((v >> 8) & 0xFF) / 255.0,
      blue: Double(v & 0xFF) / 255.0
    )
  }

  static func formatTime(_ sec: Double) -> String {
    guard sec.isFinite && sec >= 0 else { return "0:00" }
    let s = Int(sec)
    return String(format: "%d:%02d", s / 60, s % 60)
  }
}

enum Haptics {
  static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
  static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
  static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
  static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// True iOS 26 Native Liquid Glass (.glassEffect) with automatic refined glass fallback for iOS 18.
struct LumeGlassModifier<S: Shape>: ViewModifier {
  let shape: S
  var tint: Color = .clear
  var interactive: Bool = false

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      let base: Glass = tint == .clear ? .regular : .regular.tint(tint.opacity(0.26))
      let style: Glass = interactive ? base.interactive() : base
      content.glassEffect(style, in: shape)
    } else {
      content
        .background(
          ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(
              LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.03), tint.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
          }
        )
        .overlay(shape.stroke(Theme.glassStroke, lineWidth: 0.9))
    }
  }
}

extension View {
  func liquidGlass(radius: CGFloat = 20, tint: Color = .clear, interactive: Bool = false) -> some View {
    modifier(LumeGlassModifier(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, interactive: interactive))
  }

  func liquidGlassCapsule(tint: Color = .clear, interactive: Bool = false) -> some View {
    modifier(LumeGlassModifier(shape: Capsule(), tint: tint, interactive: interactive))
  }

  func liquidGlassCircle(tint: Color = .clear, interactive: Bool = false) -> some View {
    modifier(LumeGlassModifier(shape: Circle(), tint: tint, interactive: interactive))
  }
}

/// Extracts primary & secondary vibrant colors from album artwork for the ambient Liquid Glass backdrop.
actor ArtworkColorExtractor {
  static let shared = ArtworkColorExtractor()
  private var cache: [String: (Color, Color)] = [:]

  func colors(for urlString: String) async -> (Color, Color) {
    if let hit = cache[urlString] { return hit }
    guard let url = URL(string: urlString) else { return (Theme.amber, Theme.coral) }
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      guard let img = UIImage(data: data), let pair = Self.extract(from: img) else {
        return (Theme.amber, Theme.coral)
      }
      cache[urlString] = pair
      return pair
    } catch {
      return (Theme.amber, Theme.coral)
    }
  }

  private static func extract(from image: UIImage) -> (Color, Color)? {
    guard let cg = image.cgImage else { return nil }
    let size = 24
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    guard let ctx = CGContext(
      data: &pixels, width: size, height: size, bitsPerComponent: 8,
      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .low
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

    var best1: (score: Double, r: Double, g: Double, b: Double) = (-1, 0.9, 0.65, 0.3)
    var best2: (score: Double, r: Double, g: Double, b: Double) = (-1, 0.9, 0.4, 0.45)

    for i in stride(from: 0, to: pixels.count, by: 4) {
      let r = Double(pixels[i]) / 255.0
      let g = Double(pixels[i + 1]) / 255.0
      let b = Double(pixels[i + 2]) / 255.0
      let mx = max(r, max(g, b)), mn = min(r, min(g, b))
      let sat = mx > 0.05 ? (mx - mn) / mx : 0
      let luma = 0.299 * r + 0.587 * g + 0.114 * b
      if luma < 0.12 || luma > 0.92 { continue }
      let score = sat * 1.6 + (1.0 - abs(luma - 0.52)) * 0.6
      if score > best1.score {
        let dist = abs(r - best1.r) + abs(g - best1.g) + abs(b - best1.b)
        if dist > 0.35 { best2 = best1 }
        best1 = (score, r, g, b)
      } else if score > best2.score {
        let dist = abs(r - best1.r) + abs(g - best1.g) + abs(b - best1.b)
        if dist > 0.38 { best2 = (score, r, g, b) }
      }
    }
    let c1 = Color(red: max(0.18, best1.r), green: max(0.16, best1.g), blue: max(0.20, best1.b))
    let c2 = Color(red: max(0.14, best2.r), green: max(0.12, best2.g), blue: max(0.18, best2.b))
    return (c1, c2)
  }
}

/// Cached asynchronous album artwork image view.
struct RemoteArtwork: View {
  let url: String
  var cornerRadius: CGFloat = 14
  var placeholderIcon: String = "music.note"

  var body: some View {
    Color.clear
      .overlay {
        Group {
          if let u = URL(string: url), !url.isEmpty {
            AsyncImage(url: u, transaction: Transaction(animation: .easeInOut(duration: 0.22))) { phase in
              switch phase {
              case .success(let img):
                img.resizable().scaledToFill()
              case .failure:
                placeholder
              case .empty:
                placeholder.overlay(
                  LinearGradient(colors: [.clear, .white.opacity(0.06), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
              @unknown default:
                placeholder
              }
            }
          } else {
            placeholder
          }
        }
      }
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  private var placeholder: some View {
    ZStack {
      LinearGradient(colors: [Theme.surface2, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
      Image(systemName: placeholderIcon)
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(Theme.amber.opacity(0.55))
    }
  }
}
