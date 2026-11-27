import CoreImage
import ImageIO
import SwiftUI
import UIKit

// MARK: - Lume Music 3 · Design System "Prisma"
//
// Visual language: clean iOS 26/27 Liquid Glass surfaces over a neutral canvas,
// SF Pro typography, and an iridescent "prism" accent (peach → rose → lavender → sky).
// Every color adapts to Light/Dark. Album artwork drives the player ambience.

enum Theme {
  static let credit = "Desenvolvido por A.A · Demerzel Studio"

  // MARK: Adaptive neutrals

  static func dyn(_ light: UInt32, _ dark: UInt32, la: CGFloat = 1, da: CGFloat = 1) -> Color {
    Color(uiColor: UIColor { tc in
      tc.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: da) : UIColor(hex: light, alpha: la)
    })
  }

  static let canvas = dyn(0xF3F2F7, 0x09090B)
  static let canvasRaised = dyn(0xFFFFFF, 0x141418)
  static let text = dyn(0x101013, 0xF5F5F7)
  static let secondary = dyn(0x101013, 0xF5F5F7, la: 0.58, da: 0.62)
  static let tertiary = dyn(0x101013, 0xF5F5F7, la: 0.32, da: 0.34)
  static let hairline = dyn(0x000000, 0xFFFFFF, la: 0.08, da: 0.10)
  static let fill = dyn(0x000000, 0xFFFFFF, la: 0.05, da: 0.075)
  static let fillStrong = dyn(0x000000, 0xFFFFFF, la: 0.09, da: 0.13)
  static let shadow = dyn(0x2A2440, 0x000000, la: 0.16, da: 0.55)

  // MARK: Prism palette

  static let peach = Color(hex: 0xFFB27A)
  static let rose = Color(hex: 0xFF7BA9)
  static let lavender = Color(hex: 0xAD8CFF)
  static let sky = Color(hex: 0x7CC8FF)
  static let mint = Color(hex: 0x6FE3C1)
  static let accent = dyn(0xE0457B, 0xFF7BA9)
  static let ok = Color(hex: 0x30D158)
  static let danger = Color(hex: 0xFF453A)
  static let onPrism = Color(red: 0.07, green: 0.06, blue: 0.09)

  static let prismColors: [Color] = [peach, rose, lavender, sky]
  static let prism = LinearGradient(colors: prismColors, startPoint: .leading, endPoint: .trailing)
  static let prismDiagonal = LinearGradient(colors: prismColors, startPoint: .topLeading, endPoint: .bottomTrailing)
  static let prismAngular = AngularGradient(colors: prismColors + [peach], center: .center)

  static let glassStroke = LinearGradient(
    colors: [Color.white.opacity(0.42), Color.white.opacity(0.10), Color.white.opacity(0.22)],
    startPoint: .topLeading, endPoint: .bottomTrailing
  )

  // MARK: Legacy aliases (older call sites)

  static let bg = canvas
  static let surface = canvasRaised
  static let surface2 = fillStrong
  static let muted = secondary
  static let dim = tertiary
  static let ink = onPrism
  static let amber = peach
  static let coral = rose
  static let violet = lavender
  static let aurora = prism

  // MARK: Helpers

  static var motion: Bool { !UIAccessibility.isReduceMotionEnabled }

  static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight)
  }

  static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .rounded)
  }

  static func hex(_ v: UInt32) -> Color { Color(hex: v) }

  static func formatTime(_ sec: Double) -> String {
    guard sec.isFinite && sec >= 0 else { return "0:00" }
    let s = Int(sec)
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
  }

  private static let isoDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private static let brShortMonthFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "d MMM"
    return f
  }()

  static func shortDate(_ iso: String?) -> String {
    guard let iso, iso.count >= 10,
          let d = isoDayFormatter.date(from: String(iso.prefix(10))) else { return "" }
    let days = Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 99
    if days <= 0 { return "Hoje" }
    if days == 1 { return "Ontem" }
    if days < 7 { return "Há \(days) dias" }
    return brShortMonthFormatter.string(from: d).replacingOccurrences(of: ".", with: "")
  }
}

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }
}

extension UIColor {
  convenience init(hex: UInt32, alpha: CGFloat = 1) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: alpha
    )
  }
}

enum Haptics {
  static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
  static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
  static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
  static func rigid() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7) }
  static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
  static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// MARK: - Liquid Glass

/// Native iOS 26+ Liquid Glass (`glassEffect`) with a frosted-material fallback for iOS 18–25.
struct GlassSurface<S: Shape>: ViewModifier {
  let shape: S
  var tint: Color? = nil
  var interactive: Bool = false
  var clear: Bool = false

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(glass, in: shape)
    } else {
      content
        .background {
          ZStack {
            shape.fill(.ultraThinMaterial)
            if let tint { shape.fill(tint.opacity(0.18)) }
            shape.fill(LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
          }
        }
        .overlay(shape.stroke(Theme.glassStroke, lineWidth: 0.7))
    }
  }

  @available(iOS 26.0, *)
  private var glass: Glass {
    var g: Glass = clear ? .clear : .regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
  }
}

extension View {
  func glass(_ radius: CGFloat = 22, tint: Color? = nil, interactive: Bool = false, clear: Bool = false) -> some View {
    modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, interactive: interactive, clear: clear))
  }

  func glassCapsule(tint: Color? = nil, interactive: Bool = false, clear: Bool = false) -> some View {
    modifier(GlassSurface(shape: Capsule(), tint: tint, interactive: interactive, clear: clear))
  }

  func glassCircle(tint: Color? = nil, interactive: Bool = false, clear: Bool = false) -> some View {
    modifier(GlassSurface(shape: Circle(), tint: tint, interactive: interactive, clear: clear))
  }

  // Legacy names
  func liquidGlass(radius: CGFloat = 20, tint: Color = .clear, interactive: Bool = false) -> some View {
    glass(radius, tint: tint == .clear ? nil : tint.opacity(0.3), interactive: interactive)
  }
  func liquidGlassCapsule(tint: Color = .clear, interactive: Bool = false) -> some View {
    glassCapsule(tint: tint == .clear ? nil : tint.opacity(0.3), interactive: interactive)
  }
  func liquidGlassCircle(tint: Color = .clear, interactive: Bool = false) -> some View {
    glassCircle(tint: tint == .clear ? nil : tint.opacity(0.3), interactive: interactive)
  }

  /// Soft, layered elevation shadow used across cards.
  func lumeShadow(_ radius: CGFloat = 18, y: CGFloat = 10, opacity: Double = 1) -> some View {
    shadow(color: Theme.shadow.opacity(opacity), radius: radius, y: y)
  }

  @ViewBuilder
  func glassGroup(spacing: CGFloat = 12) -> some View {
    if #available(iOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) { self }
    } else {
      self
    }
  }
}

/// Pressable scale style used by cards (gentle, iOS-like).
struct PressableStyle: ButtonStyle {
  var scale: CGFloat = 0.965
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? scale : 1)
      .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
  }
}

// MARK: - Reusable components

struct GlassIconButton: View {
  let systemName: String
  var size: CGFloat = 40
  var iconSize: CGFloat? = nil
  var tint: Color? = nil
  var foreground: Color = Theme.text
  var badge: Bool = false
  let action: () -> Void

  var body: some View {
    Button {
      Haptics.light()
      action()
    } label: {
      Image(systemName: systemName)
        .font(.system(size: iconSize ?? size * 0.40, weight: .semibold))
        .foregroundStyle(foreground)
        .frame(width: size, height: size)
        .contentShape(Circle())
        .glassCircle(tint: tint, interactive: true)
        .overlay(alignment: .topTrailing) {
          if badge {
            Circle()
              .fill(Theme.rose)
              .frame(width: 9, height: 9)
              .overlay(Circle().stroke(Theme.canvas, lineWidth: 1.5))
              .offset(x: -1, y: 1)
          }
        }
    }
    .buttonStyle(PressableStyle(scale: 0.9))
  }
}

/// Serene-style chip: prism-filled when active, glass otherwise.
struct PrismChip: View {
  let title: String
  var systemImage: String? = nil
  let active: Bool
  let action: () -> Void

  var body: some View {
    Button {
      Haptics.selection()
      action()
    } label: {
      HStack(spacing: 6) {
        if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)) }
        Text(title).font(Theme.font(14, .semibold))
      }
      .foregroundStyle(active ? Theme.onPrism : Theme.text)
      .padding(.horizontal, 16)
      .frame(height: 38)
      .background {
        if active {
          Capsule().fill(Theme.prismDiagonal)
            .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 0.8))
            .shadow(color: Theme.rose.opacity(0.35), radius: 10, y: 4)
        }
      }
      .modifier(ConditionalGlassCapsule(enabled: !active))
    }
    .buttonStyle(PressableStyle(scale: 0.94))
  }
}

struct ConditionalGlassCapsule: ViewModifier {
  let enabled: Bool
  func body(content: Content) -> some View {
    if enabled { content.glassCapsule(interactive: true) } else { content }
  }
}

struct SectionHeader: View {
  let title: String
  var subtitle: String? = nil
  var actionLabel: String? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(Theme.font(21, .bold))
          .foregroundStyle(Theme.text)
        if let subtitle {
          Text(subtitle)
            .font(Theme.font(13, .regular))
            .foregroundStyle(Theme.secondary)
        }
      }
      Spacer()
      if let action {
        Button {
          Haptics.light()
          action()
        } label: {
          HStack(spacing: 3) {
            Text(actionLabel ?? "Ver tudo").font(Theme.font(14, .medium))
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
          }
          .foregroundStyle(Theme.secondary)
        }
      }
    }
    .padding(.horizontal, 20)
  }
}

/// Primary call-to-action with prism gradient.
struct PrismButton: View {
  let title: String
  var systemImage: String? = nil
  var height: CGFloat = 50
  let action: () -> Void

  var body: some View {
    Button {
      Haptics.medium()
      action()
    } label: {
      HStack(spacing: 8) {
        if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .bold)) }
        Text(title).font(Theme.font(16, .semibold))
      }
      .foregroundStyle(Theme.onPrism)
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .background(Capsule().fill(Theme.prismDiagonal))
      .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.8))
      .shadow(color: Theme.rose.opacity(0.32), radius: 14, y: 6)
    }
    .buttonStyle(PressableStyle())
  }
}

struct GlassButton: View {
  let title: String
  var systemImage: String? = nil
  var height: CGFloat = 50
  let action: () -> Void

  var body: some View {
    Button {
      Haptics.light()
      action()
    } label: {
      HStack(spacing: 8) {
        if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)) }
        Text(title).font(Theme.font(16, .semibold))
      }
      .foregroundStyle(Theme.text)
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .glassCapsule(interactive: true)
    }
    .buttonStyle(PressableStyle())
  }
}

/// O novo emblema do Lume: disco escultural em vidro líquido com microssulcos, anel prismático e brilho diagonal.
struct PrismMark: View {
  var size: CGFloat = 32

  /// 5.0: a mesma arte do ícone novo (disco de vidro claro com anel prisma), nítida em qualquer tamanho.
  var body: some View {
    Image("Mark")
      .resizable()
      .interpolation(.high)
      .antialiased(true)
      .frame(width: size, height: size)
      .shadow(color: Theme.lavender.opacity(0.30), radius: size * 0.12, y: size * 0.05)
  }
}

struct LumeWordmark: View {
  var size: CGFloat = 26
  var body: some View {
    HStack(spacing: size * 0.32) {
      PrismMark(size: size * 1.22)
      Text("Lume")
        .font(.system(size: size, weight: .bold, design: .rounded))
        .tracking(-0.4)
        .foregroundStyle(Theme.text)
    }
  }
}

struct EmptyStateView: View {
  let icon: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(Theme.prismDiagonal)
        .frame(width: 72, height: 72)
        .glassCircle()
      Text(title).font(Theme.font(17, .semibold)).foregroundStyle(Theme.text)
      Text(message)
        .font(Theme.font(14))
        .foregroundStyle(Theme.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 36)
  }
}

// MARK: - Image pipeline (memory + disk cache, downsampling)

actor ImagePipeline {
  static let shared = ImagePipeline()

  nonisolated(unsafe) let memory: NSCache<NSString, UIImage> = {
    let c = NSCache<NSString, UIImage>()
    c.totalCostLimit = 120 * 1024 * 1024
    return c
  }()

  private var inflight: [String: Task<UIImage?, Never>] = [:]

  private let session: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 12
    cfg.requestCachePolicy = .returnCacheDataElseLoad
    cfg.urlCache = URLCache(memoryCapacity: 24 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
    return URLSession(configuration: cfg)
  }()

  /// Agrupa tamanhos parecidos (160/200, 300/500, 700/800…) num só decode em cache:
  /// antes cada tela pedia um maxPixel diferente e a mesma capa era decodificada 4–6 vezes.
  nonisolated static func bucket(_ px: CGFloat) -> CGFloat {
    switch px {
    case ..<221: return 220
    case ..<521: return 520
    case ..<821: return 820
    default: return 1200
    }
  }

  nonisolated static func key(_ url: String, _ px: CGFloat) -> NSString {
    "\(url)#\(Int(bucket(px)))" as NSString
  }

  nonisolated func cached(_ url: String, maxPixel: CGFloat) -> UIImage? {
    memory.object(forKey: Self.key(url, maxPixel))
  }

  func image(_ url: String, maxPixel: CGFloat = 800) async -> UIImage? {
    guard !url.isEmpty, let u = URL(string: url) else { return nil }
    let key = Self.key(url, maxPixel)
    let maxPixel = Self.bucket(maxPixel)
    if let hit = memory.object(forKey: key) { return hit }
    let k = key as String
    if let running = inflight[k] { return await running.value }
    let session = self.session
    // Decodificação/downsampling em tarefa destacada: não serializa todas as capas no actor.
    let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
      guard let (data, _) = try? await session.data(from: u) else { return nil }
      return Self.downsample(data, maxPixel: maxPixel)
    }
    inflight[k] = task
    let img = await task.value
    inflight[k] = nil
    if let img {
      let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
      memory.setObject(img, forKey: key, cost: cost)
    }
    return img
  }

  nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
    let opts = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let src = CGImageSourceCreateWithData(data as CFData, opts) else { return UIImage(data: data) }
    let thumbOpts = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
    ] as CFDictionary
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { return UIImage(data: data) }
    return UIImage(cgImage: cg)
  }
}

/// Cached, downsampled artwork with a soft placeholder. Video thumbnails (16:9) are center-cropped.
struct ArtworkImage: View {
  let url: String
  var cornerRadius: CGFloat = 12
  var maxPixel: CGFloat = 700
  var placeholderIcon: String = "music.note"

  @State private var image: UIImage?

  init(url: String, cornerRadius: CGFloat = 12, maxPixel: CGFloat = 700, placeholderIcon: String = "music.note") {
    self.url = url
    self.cornerRadius = cornerRadius
    self.maxPixel = maxPixel
    self.placeholderIcon = placeholderIcon
    _image = State(initialValue: ImagePipeline.shared.cached(url, maxPixel: maxPixel))
  }

  var body: some View {
    Color.clear
      .overlay {
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .transition(.opacity)
        } else {
          placeholder
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .task(id: url) {
        if let hit = ImagePipeline.shared.cached(url, maxPixel: maxPixel) {
          image = hit
          return
        }
        image = nil
        let img = await ImagePipeline.shared.image(url, maxPixel: maxPixel)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { image = img }
      }
  }

  private var placeholder: some View {
    ZStack {
      LinearGradient(colors: [Theme.fillStrong, Theme.fill], startPoint: .topLeading, endPoint: .bottomTrailing)
      Image(systemName: placeholderIcon)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(Theme.tertiary)
    }
  }
}

/// Backwards-compatible name.
struct RemoteArtwork: View {
  let url: String
  var cornerRadius: CGFloat = 14
  var placeholderIcon: String = "music.note"
  var body: some View {
    ArtworkImage(url: url, cornerRadius: cornerRadius, placeholderIcon: placeholderIcon)
  }
}

// MARK: - Artwork palette (ambient colors for the player)

struct ArtworkPalette: Equatable {
  /// Quadrant colors (TL, TR, BL, BR) — used as mesh-gradient anchors.
  var quadrants: [Color]
  /// Most vibrant colors for accents.
  var vibrant: Color
  var vibrant2: Color

  static let fallback = ArtworkPalette(
    quadrants: [Theme.lavender, Theme.rose, Theme.sky, Theme.peach],
    vibrant: Theme.rose,
    vibrant2: Theme.lavender
  )
}

actor ArtworkColorExtractor {
  static let shared = ArtworkColorExtractor()
  private var cache: [String: ArtworkPalette] = [:]

  func palette(for urlString: String) async -> ArtworkPalette {
    if let hit = cache[urlString] { return hit }
    guard let img = await ImagePipeline.shared.image(urlString, maxPixel: 160),
          let pal = Self.extract(from: img) else { return .fallback }
    cache[urlString] = pal
    return pal
  }

  func colors(for urlString: String) async -> (Color, Color) {
    let p = await palette(for: urlString)
    return (p.vibrant, p.vibrant2)
  }

  private static func extract(from image: UIImage) -> ArtworkPalette? {
    guard let cg = image.cgImage else { return nil }
    let size = 24
    var px = [UInt8](repeating: 0, count: size * size * 4)
    guard let ctx = CGContext(
      data: &px, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

    func avg(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> (Double, Double, Double) {
      var r = 0.0, g = 0.0, b = 0.0, n = 0.0
      for y in y0..<y1 {
        for x in x0..<x1 {
          let i = (y * size + x) * 4
          r += Double(px[i]); g += Double(px[i + 1]); b += Double(px[i + 2]); n += 1
        }
      }
      return (r / n / 255, g / n / 255, b / n / 255)
    }
    let h = size / 2
    // CGContext origin is bottom-left: row 0 = bottom.
    let quads = [avg(0, h, h, size), avg(h, h, size, size), avg(0, 0, h, h), avg(h, 0, size, h)]

    var best1: (s: Double, c: (Double, Double, Double)) = (-1, (1, 0.48, 0.66))
    var best2: (s: Double, c: (Double, Double, Double)) = (-1, (0.68, 0.55, 1))
    for i in stride(from: 0, to: px.count, by: 4) {
      let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
      let mx = max(r, g, b), mn = min(r, g, b)
      let sat = mx > 0.05 ? (mx - mn) / mx : 0
      let luma = 0.299 * r + 0.587 * g + 0.114 * b
      if luma < 0.10 || luma > 0.94 { continue }
      let score = sat * 1.7 + (1 - abs(luma - 0.55)) * 0.5
      let dist = abs(r - best1.c.0) + abs(g - best1.c.1) + abs(b - best1.c.2)
      if score > best1.s {
        if dist > 0.35 { best2 = best1 }
        best1 = (score, (r, g, b))
      } else if score > best2.s && dist > 0.38 {
        best2 = (score, (r, g, b))
      }
    }

    func color(_ c: (Double, Double, Double), boost: Double = 1.18) -> Color {
      var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
      UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1).getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
      return Color(hue: hue, saturation: min(1, sat * boost), brightness: max(0.22, min(0.95, bri)))
    }
    return ArtworkPalette(
      quadrants: quads.map { color($0, boost: 1.3) },
      vibrant: color(best1.c, boost: 1.1),
      vibrant2: color(best2.c, boost: 1.1)
    )
  }
}

// MARK: - Capa pré-desfocada (cache)

/// Capa desfocada renderizada uma única vez com CoreImage (fora da main) e guardada em cache.
struct PreblurredArtwork: View {
  let url: String
  @State private var image: UIImage?

  init(url: String) {
    self.url = url
    _image = State(initialValue: BlurredArtworkCache.cached(url))
  }

  var body: some View {
    Color.clear
      .overlay {
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .transition(.opacity)
        }
      }
      .task(id: url) {
        if let hit = BlurredArtworkCache.cached(url) { image = hit; return }
        let img = await BlurredArtworkCache.load(url)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.5)) { image = img }
      }
      .allowsHitTesting(false)
  }
}

enum BlurredArtworkCache {
  nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
    let c = NSCache<NSString, UIImage>()
    c.countLimit = 12
    return c
  }()
  private static let ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

  static func cached(_ url: String) -> UIImage? { memory.object(forKey: url as NSString) }

  static func load(_ url: String) async -> UIImage? {
    if let hit = cached(url) { return hit }
    guard let src = await ImagePipeline.shared.image(url, maxPixel: 200) else { return nil }
    let out = await Task.detached(priority: .utility) { () -> UIImage? in
      guard let cg = src.cgImage else { return nil }
      let input = CIImage(cgImage: cg)
      // 200 px exibidos a ~1,8x da tela: raio 19 px aqui ≈ o antigo blur de 70 pt.
      let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 19).cropped(to: input.extent)
      guard let outCG = ciContext.createCGImage(blurred, from: input.extent) else { return nil }
      return UIImage(cgImage: outCG)
    }.value
    if let out { memory.setObject(out, forKey: url as NSString) }
    return out
  }
}

// MARK: - Ambient animated mesh background (Apple Music-like, driven by artwork)

struct AmbientMeshBackground: View {
  let palette: ArtworkPalette
  var artworkURL: String = ""
  var animate: Bool = true
  @Environment(\.colorScheme) private var scheme
  @ObservedObject private var gov = PerfGovernor.shared

  var body: some View {
    ZStack {
      Theme.canvas
      if !artworkURL.isEmpty {
        // 5.0: a capa chega JÁ desfocada (CoreImage, uma vez, fora da main). Antes era um
        // `.blur(radius: 70)` ao vivo em tela cheia, recomposto pela GPU a cada quadro do mesh.
        PreblurredArtwork(url: artworkURL)
          .scaleEffect(1.8)
          .opacity(scheme == .dark ? 0.55 : 0.45)
      }
      // O mesh se move muito devagar (períodos de 30–50 s): 12 fps são indistinguíveis de 20 e
      // custam 40% menos. Pausa com app inativo/tela bloqueada, Reduzir Movimento ou modo economia.
      TimelineView(.animation(minimumInterval: 1 / 12, paused: !animate || !Theme.motion || !gov.isActive || gov.reduced)) { tl in
        let t = tl.date.timeIntervalSinceReferenceDate
        mesh(t: t)
      }
      .opacity(scheme == .dark ? 0.78 : 0.62)
      // Legibility veil
      LinearGradient(
        colors: scheme == .dark
          ? [Color.black.opacity(0.10), Color.black.opacity(0.28), Color.black.opacity(0.62)]
          : [Color.white.opacity(0.18), Color.white.opacity(0.30), Color.white.opacity(0.55)],
        startPoint: .top, endPoint: .bottom
      )
    }
    .ignoresSafeArea()
  }

  @ViewBuilder
  private func mesh(t: Double) -> some View {
    let q = palette.quadrants.count == 4 ? palette.quadrants : ArtworkPalette.fallback.quadrants
    let a = Float(sin(t * 0.21) * 0.10), b = Float(cos(t * 0.17) * 0.10), c = Float(sin(t * 0.13 + 1.2) * 0.08)
    MeshGradient(
      width: 3, height: 3,
      points: [
        [0, 0], [0.5 + a, 0], [1, 0],
        [0, 0.5 + b], [0.5 + c, 0.5 - a], [1, 0.5 + c],
        [0, 1], [0.5 - b, 1], [1, 1],
      ],
      colors: [
        q[0], palette.vibrant, q[1],
        palette.vibrant2, q[0].mix(with: q[3], by: 0.5), q[1],
        q[2], palette.vibrant, q[3],
      ]
    )
  }
}
