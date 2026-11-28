import AppIntents
import SwiftUI
import WidgetKit

// Widget "Tocando agora" (contrato 5.2 D): pequeno, médio e retangular da tela de bloqueio.

@main
struct LumeWidgetBundle: WidgetBundle {
  var body: some Widget {
    LumeNowPlayingWidget()
  }
}

struct LumeEntry: TimelineEntry {
  let date: Date
  let data: WidgetNowPlaying?
  let cover: UIImage?
}

struct LumeProvider: TimelineProvider {
  func placeholder(in context: Context) -> LumeEntry {
    LumeEntry(date: Date(), data: WidgetNowPlaying(title: "Nome da música", artist: "Artista", isPlaying: true), cover: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (LumeEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : current())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<LumeEntry>) -> Void) {
    // O app pede a atualização (reloadAllTimelines) a cada troca de faixa ou de estado.
    completion(Timeline(entries: [current()], policy: .never))
  }

  private func current() -> LumeEntry {
    let cover = WidgetStore.coverPath().flatMap { UIImage(contentsOfFile: $0) }
    return LumeEntry(date: Date(), data: WidgetStore.read(), cover: cover)
  }
}

struct LumeNowPlayingWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetStore.kind, provider: LumeProvider()) { entry in
      LumeWidgetView(entry: entry)
    }
    .configurationDisplayName("Tocando agora")
    .description("A música atual do Lume Music, com os controles.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    .contentMarginsDisabled()
  }
}

// MARK: - Visual

private enum Palette {
  static let rose = Color(red: 0.96, green: 0.36, blue: 0.55)
  static let lavender = Color(red: 0.55, green: 0.45, blue: 0.95)
}

struct LumeWidgetView: View {
  let entry: LumeEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var scheme

  private var ink: Color { scheme == .dark ? .white : Color(red: 0.08, green: 0.08, blue: 0.12) }
  private var inkSoft: Color { ink.opacity(0.68) }

  var body: some View {
    Group {
      switch family {
      case .systemMedium: medium
      case .accessoryRectangular: accessory
      default: small
      }
    }
    .widgetURL(URL(string: "lumemusic://tocando"))
    .containerBackground(for: .widget) { background }
  }

  // MARK: Fundo de vidro (capa desfocada + véu claro/escuro)

  @ViewBuilder private var background: some View {
    if family == .accessoryRectangular {
      Color.clear
    } else {
      ZStack {
        if let cover = entry.cover {
          Image(uiImage: cover)
            .resizable()
            .scaledToFill()
            .scaleEffect(1.5)
            .blur(radius: 34)
        } else {
          LinearGradient(colors: [Palette.rose.opacity(0.85), Palette.lavender.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        Rectangle().fill(scheme == .dark ? Color.black.opacity(0.46) : Color.white.opacity(0.58))
      }
    }
  }

  // MARK: Peças

  private func coverView(_ side: CGFloat, radius: CGFloat) -> some View {
    ZStack {
      if let cover = entry.cover {
        Image(uiImage: cover).resizable().scaledToFill()
      } else {
        LinearGradient(colors: [Palette.rose, Palette.lavender], startPoint: .topLeading, endPoint: .bottomTrailing)
          .overlay(Image(systemName: "music.note").font(.system(size: side * 0.4, weight: .semibold)).foregroundStyle(.white.opacity(0.9)))
      }
    }
    .frame(width: side, height: side)
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.28), lineWidth: 0.8))
    .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
  }

  private func glassButton<I: AppIntent>(_ symbol: String, intent: I, size: CGFloat, big: Bool = false) -> some View {
    Button(intent: intent) {
      Image(systemName: symbol)
        .font(.system(size: size * (big ? 0.46 : 0.40), weight: .bold))
        .foregroundStyle(big ? Color.white : ink)
        .frame(width: size, height: size)
        .background {
          if big {
            Circle().fill(LinearGradient(colors: [Palette.rose, Palette.lavender], startPoint: .topLeading, endPoint: .bottomTrailing))
          } else {
            Circle().fill(.ultraThinMaterial)
          }
        }
        .overlay(Circle().strokeBorder(.white.opacity(scheme == .dark ? 0.22 : 0.5), lineWidth: 0.8))
    }
    .buttonStyle(.plain)
  }

  private var controls: some View {
    let playing = entry.data?.isPlaying == true
    return HStack(spacing: 0) {
      glassButton("backward.fill", intent: LumePreviousIntent(), size: 34)
      Spacer(minLength: 4)
      glassButton(playing ? "pause.fill" : "play.fill", intent: LumeTogglePlayIntent(), size: 40, big: true)
      Spacer(minLength: 4)
      glassButton("forward.fill", intent: LumeNextIntent(), size: 34)
    }
  }

  private var emptyText: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("Nada tocando")
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundStyle(ink)
      Text("Abra o Lume Music e escolha uma música.")
        .font(.system(size: 11.5, weight: .medium, design: .rounded))
        .foregroundStyle(inkSoft)
        .lineLimit(2)
    }
  }

  private func titleBlock(titleSize: CGFloat, artistSize: CGFloat, titleLines: Int) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(entry.data?.title ?? "")
        .font(.system(size: titleSize, weight: .bold, design: .rounded))
        .foregroundStyle(ink)
        .lineLimit(titleLines)
        .minimumScaleFactor(0.85)
      Text(entry.data?.artist ?? "")
        .font(.system(size: artistSize, weight: .medium, design: .rounded))
        .foregroundStyle(inkSoft)
        .lineLimit(1)
    }
  }

  // MARK: Pequeno

  private var small: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 9) {
        coverView(46, radius: 12)
        if entry.data == nil { emptyText } else { titleBlock(titleSize: 13, artistSize: 11.5, titleLines: 2) }
      }
      Spacer(minLength: 0)
      if entry.data != nil { controls }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: Médio

  private var medium: some View {
    HStack(spacing: 14) {
      coverView(112, radius: 20)
      VStack(alignment: .leading, spacing: 6) {
        if entry.data == nil {
          Spacer(minLength: 0)
          emptyText
          Spacer(minLength: 0)
        } else {
          titleBlock(titleSize: 17, artistSize: 13.5, titleLines: 2)
          Spacer(minLength: 0)
          controls
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
  }

  // MARK: Tela de bloqueio

  private var accessory: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        if let d = entry.data {
          Text(d.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
          Text(d.artist).font(.system(size: 12)).opacity(0.75).lineLimit(1)
        } else {
          Text("Nada tocando").font(.system(size: 14, weight: .semibold))
          Text("Abra o Lume Music").font(.system(size: 12)).opacity(0.75)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if entry.data != nil {
        Button(intent: LumeTogglePlayIntent()) {
          Image(systemName: entry.data?.isPlaying == true ? "pause.fill" : "play.fill")
            .font(.system(size: 15, weight: .bold))
            .frame(width: 32, height: 32)
            .background(Circle().fill(.white.opacity(0.22)))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 4)
  }
}
