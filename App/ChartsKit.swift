import SwiftUI

// MARK: - Shimmer leve (só anima quando visível, com o app ativo e sem "Reduzir Movimento")

struct LightShimmer: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase
  @State private var phase: CGFloat = -1
  @State private var visible = false

  private var active: Bool { visible && scenePhase == .active && Theme.motion }

  func body(content: Content) -> some View {
    content
      .overlay {
        if active {
          GeometryReader { g in
            LinearGradient(colors: [.clear, .white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
              .frame(width: g.size.width * 0.55)
              .offset(x: phase * g.size.width * 1.5)
          }
          .mask(content)
          .allowsHitTesting(false)
        }
      }
      .onAppear { visible = true }
      .onDisappear { visible = false }
      .task(id: active) {
        if active {
          phase = -1
          withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
        } else {
          withAnimation(.linear(duration: 0)) { phase = -1 }
        }
      }
  }
}

struct SoftBlock: View {
  var width: CGFloat? = nil
  var height: CGFloat
  var radius: CGFloat = 14
  var body: some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(Theme.fillStrong)
      .frame(width: width, height: height)
      .modifier(LightShimmer())
  }
}

struct SkeletonTrackRows: View {
  var count = 10
  var body: some View {
    VStack(spacing: 0) {
      ForEach(0..<count, id: \.self) { _ in
        HStack(spacing: 12) {
          SoftBlock(width: 26, height: 14, radius: 5)
          SoftBlock(width: 50, height: 50, radius: 8)
          VStack(alignment: .leading, spacing: 7) {
            SoftBlock(width: 168, height: 14, radius: 6)
            SoftBlock(width: 104, height: 12, radius: 6)
          }
          Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .frame(height: 60)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityHidden(true)
  }
}

// MARK: - Seletor de país / Global (chips de vidro com bandeira)

extension ChartPlace {
  /// Nome curto para o chip.
  var short: String {
    switch id {
    case "us": return "EUA"
    case "kr": return "Coreia"
    default: return name
    }
  }
}

struct PlaceChipsBar: View {
  let selected: String
  var places: [ChartPlace] = ChartPlace.all
  let onSelect: (ChartPlace) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(places) { p in
            PlaceChip(place: p, active: p.id == selected) { onSelect(p) }
              .id(p.id)
          }
        }
        .glassGroup(spacing: 8)
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
      }
      .scrollClipDisabled()
      .onChange(of: selected) { _, new in
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { proxy.scrollTo(new, anchor: .center) }
      }
      .onAppear { proxy.scrollTo(selected, anchor: .center) }
    }
  }
}

private struct PlaceChip: View {
  let place: ChartPlace
  let active: Bool
  let action: () -> Void

  var body: some View {
    Button {
      Haptics.selection()
      action()
    } label: {
      HStack(spacing: 6) {
        Text(place.flag).font(.system(size: 17))
        Text(place.short).font(Theme.font(14, .semibold))
      }
      .foregroundStyle(active ? Theme.onPrism : Theme.text)
      .padding(.horizontal, 14)
      .frame(height: 40)
      .background {
        if active {
          Capsule().fill(Theme.prismDiagonal)
            .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 0.8))
            .shadow(color: Theme.rose.opacity(0.30), radius: 8, y: 3)
        }
      }
      .modifier(ConditionalGlassCapsule(enabled: !active))
      .frame(height: 44)
      .contentShape(Capsule())
    }
    .buttonStyle(PressableStyle(scale: 0.94))
    .accessibilityLabel(place.name)
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}

// MARK: - Lista Top N (carregando / vazio / pronta)

struct ChartTrackList: View {
  let list: ChartList?
  let loading: Bool
  var limit: Int = 10
  let retry: () -> Void

  var body: some View {
    Group {
      if let list, !list.songs.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(list.songs.prefix(limit).enumerated()), id: \.element.id) { idx, tr in
            TrackRow(track: tr, rank: idx + 1, queue: list.songs)
          }
        }
        .padding(.horizontal, 20)
      } else if loading {
        SkeletonTrackRows(count: min(limit, 10)).padding(.horizontal, 20)
      } else {
        VStack(spacing: 12) {
          Image(systemName: "wifi.exclamationmark").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.tertiary)
          Text("Parada indisponível agora").font(Theme.font(15, .semibold)).foregroundStyle(Theme.text)
          Button {
            Haptics.light()
            retry()
          } label: {
            Text("Tentar de novo")
              .font(Theme.font(14, .semibold))
              .foregroundStyle(Theme.text)
              .padding(.horizontal, 18)
              .frame(height: 44)
              .glassCapsule(interactive: true)
          }
          .buttonStyle(PressableStyle(scale: 0.95))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
      }
    }
  }
}

extension ChartList {
  /// "Apple Music · atualizado há 5 min" — para o usuário saber de onde vem cada ranking.
  var caption: String {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.unitsStyle = .short
    let when = abs(updatedAt.timeIntervalSinceNow) < 60 ? "agora" : f.localizedString(for: updatedAt, relativeTo: Date())
    return "\(source) · atualizado \(when)"
  }
}
