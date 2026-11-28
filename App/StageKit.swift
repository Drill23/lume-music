import SwiftUI
import UIKit

// MARK: - Depuração visual dos palcos (só com argumentos de lançamento)

/// `-LMStage Vinil|K7|Capa|Ondas|Letra` abre o Tocando agora direto no palco, com uma faixa de teste.
/// Extras: `-LMPlaying 1|0`, `-LMProgress 0.4`, `-LMEdition Cristal Prisma`, `-LMFinish Nogueira Vintage`,
/// `-LMCassette Cristal Transparente`, `-LMOpenOrb 1`.
enum StageDebug {
  static func value(_ key: String) -> String? {
    let a = ProcessInfo.processInfo.arguments
    guard let i = a.firstIndex(of: key), i + 1 < a.count else { return nil }
    return a[i + 1]
  }

  static var openOrb: Bool { value("-LMOpenOrb") == "1" }

  @MainActor
  static func bootstrapIfNeeded() {
    guard let stage = value("-LMStage"), let tab = PlayerSurfaceTab(rawValue: stage) else { return }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(4.5))
      let app = AppModel.shared
      let player = AudioPlayer.shared
      let store = LibraryStore.shared
      if let v = value("-LMEdition"), let e = VinylEdition(rawValue: v) { store.vinylEdition = e }
      if let v = value("-LMFinish"), let f = TurntableFinish(rawValue: v) { store.turntableFinish = f }
      if let v = value("-LMCassette"), let c = CassetteStyle(rawValue: v) { store.cassetteStyle = c }
      if let v = value("-LM3D") { store.turntable3D = v == "1" }
      let url = "https://picsum.photos/id/1039/700/700"
      let track = Track(title: "Noite Estrelada", artist: "Lume Quartet", album: "Prisma", duration: 215, artworkURL: url)
      player.currentTrack = track
      player.currentArtwork = url
      PlaybackClock.shared.duration = 215
      PlaybackClock.shared.currentTime = (Double(value("-LMProgress") ?? "0.3") ?? 0.3) * 215
      player.isPlaying = (value("-LMPlaying") ?? "1") == "1"
      // Letra de demonstração (texto original, só para prints do palco "Letra"; a faixa de teste é fictícia).
      if value("-LMLyricsDemo") != nil {
        let demo = ["Acendo a luz do quarto escuro", "e o som desenha o seu lugar", "cada batida, um passo seguro",
                    "cada silêncio, um jeito de voltar", "Noite estrelada, fica mais um pouco", "deixa o refrão girar",
                    "no vidro frio da madrugada", "a gente aprende a brilhar"]
        let lines = demo.enumerated().map { LyricLine(id: $0.offset, time: 52 + Double($0.offset) * 4.5, text: $0.element, translated: nil) }
        player.lyrics = LyricsBundle(trackKey: track.id, synced: true, lines: lines, source: "Lume", translatedToPT: false)
      }
      app.playerStyle = tab == .lyrics ? .artwork : tab
      app.playerTab = tab
      app.showPlayer = true
      // sem AVPlayer real: avança o relógio para o carretel/braço andarem
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(150))
        if player.isPlaying { PlaybackClock.shared.currentTime = min(214, PlaybackClock.shared.currentTime + 0.15) }
      }
    }
  }
}

// MARK: - Transição entre palcos

/// Troca de palco: o que entra sobe de 92% com mola; o que sai some sem aceitar toques (acabou o "toque que não pega").
struct StageTransition: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .opacity(phase.isIdentity ? 1 : 0)
      .scaleEffect(phase.isIdentity ? 1 : (phase == .willAppear ? 0.92 : 1.04))
      .allowsHitTesting(phase.isIdentity)
  }
}

// MARK: - Seletor de palco

private struct StageTabStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
  }
}

/// Pílula de vidro com 5 alvos de 44 pt (ícone + rótulo) e um indicador que desliza entre eles.
/// Larguras fixas: nada muda de lugar sob o dedo quando você troca de palco.
struct StageSwitcher: View {
  let selection: PlayerSurfaceTab
  let onSelect: (PlayerSurfaceTab) -> Void
  @Namespace private var ns

  var body: some View {
    HStack(spacing: 2) {
      ForEach(PlayerSurfaceTab.allCases) { t in
        let active = selection == t
        Button {
          guard !active else { return }
          Haptics.selection()
          onSelect(t)
        } label: {
          HStack(spacing: 5) {
            Image(systemName: t.icon)
              .font(.system(size: 16, weight: .semibold))
            Text(t.rawValue)
              .font(Theme.font(12.5, .semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          .foregroundStyle(active ? Theme.onPrism : Theme.secondary)
          .frame(maxWidth: .infinity)
          .frame(height: 44)
          .background {
            if active {
              Capsule()
                .fill(Theme.prismDiagonal)
                .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.8))
                .matchedGeometryEffect(id: "indicator", in: ns)
            }
          }
          .contentShape(Capsule())
        }
        .buttonStyle(StageTabStyle())
        .accessibilityLabel(t.rawValue)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
      }
    }
    .padding(4)
    .glassCapsule()
    .padding(.horizontal, 16)
  }
}

// MARK: - Peças reutilizáveis dos painéis de estilo (todas com alvo ≥ 44 pt)

struct StageSectionHeader: View {
  let title: String
  var trailing: String? = nil
  var body: some View {
    HStack {
      Text(title)
        .font(Theme.font(11, .heavy))
        .tracking(0.9)
        .foregroundStyle(Theme.secondary)
      Spacer(minLength: 8)
      if let trailing {
        Text(trailing)
          .font(Theme.font(12, .semibold))
          .foregroundStyle(Theme.text)
          .lineLimit(1)
          .contentTransition(.opacity)
      }
    }
    .padding(.horizontal, 4)
  }
}

/// Segmentado de 44 pt com indicador que desliza.
struct StageSegmented<T: Hashable>: View {
  let items: [(value: T, title: String)]
  let selection: T
  let onSelect: (T) -> Void
  @Namespace private var ns

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, it in
        let active = it.value == selection
        Button {
          guard !active else { return }
          Haptics.selection()
          onSelect(it.value)
        } label: {
          Text(it.title)
            .font(Theme.font(13, .semibold))
            .foregroundStyle(active ? Theme.onPrism : Theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
              if active {
                Capsule().fill(Theme.prismDiagonal).matchedGeometryEffect(id: "seg", in: ns)
              }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(StageTabStyle())
      }
    }
    .padding(3)
    .background(Capsule().fill(Color.white.opacity(0.07)))
    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
  }
}

/// Bolinha de amostra (44 pt) com anel que marca a opção ativa.
struct StageSwatch<Fill: View>: View {
  let selected: Bool
  let label: String
  @ViewBuilder let fill: () -> Fill
  let action: () -> Void

  var body: some View {
    Button {
      guard !selected else { return }
      Haptics.selection()
      action()
    } label: {
      ZStack {
        fill()
          .frame(width: 34, height: 34)
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.8))
        Circle()
          .stroke(selected ? AnyShapeStyle(Theme.prismDiagonal) : AnyShapeStyle(Color.clear), lineWidth: 2.5)
          .frame(width: 44, height: 44)
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 2)
        }
      }
      .frame(width: 48, height: 48)
      .contentShape(Circle())
    }
    .buttonStyle(StageTabStyle())
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
  }
}

/// Linha de opção de 48 pt (ícone/amostra + título + check).
struct StageOptionRow<Leading: View>: View {
  let title: String
  var subtitle: String? = nil
  let selected: Bool
  @ViewBuilder let leading: () -> Leading
  let action: () -> Void

  var body: some View {
    Button {
      guard !selected else { return }
      Haptics.selection()
      action()
    } label: {
      HStack(spacing: 10) {
        leading().frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(Theme.font(14, selected ? .bold : .semibold)).lineLimit(1)
          if let subtitle {
            Text(subtitle).font(Theme.font(11)).lineLimit(1).opacity(0.7)
          }
        }
        Spacer(minLength: 6)
        if selected {
          Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
        }
      }
      .foregroundStyle(selected ? Theme.onPrism : Theme.text)
      .padding(.horizontal, 12)
      .frame(height: 48)
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(selected ? AnyShapeStyle(Theme.prismDiagonal) : AnyShapeStyle(Color.white.opacity(0.07)))
      }
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(StageTabStyle())
    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
  }
}

/// Botão de vidro de 44 pt para as docas dos palcos.
struct StageDockButton: View {
  let icon: String
  var title: String? = nil
  var tint: Color? = nil
  var minWidth: CGFloat = 44
  var accessibilityText: String
  let action: () -> Void

  var body: some View {
    Button {
      Haptics.light()
      action()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 17, weight: .semibold))
        if let title { Text(title).font(Theme.font(13, .semibold)).lineLimit(1) }
      }
      .foregroundStyle(Theme.text)
      .padding(.horizontal, title == nil ? 0 : 14)
      .frame(minWidth: minWidth, minHeight: 44)
      .contentShape(Capsule())
      .glassCapsule(tint: tint, interactive: true)
    }
    .buttonStyle(StageTabStyle())
    .accessibilityLabel(accessibilityText)
  }
}

// MARK: - Botão de estilos que se expande em painel de vidro

/// Botão (44 pt) que abre um painel de acabamentos. No iOS 26+ o vidro "derrete" do botão para o painel
/// (glassEffectID); antes disso o painel cresce a partir do canto do botão. O toque fora do painel fecha,
/// e o painel nunca é cortado: ele ocupa só a área do palco e rola quando não cabe.
struct StageStyleOrb<Content: View>: View {
  var icon: String = "paintpalette.fill"
  var accessibilityLabel: String = "Estilos visuais"
  var title: String? = nil
  var placement: Alignment = .topTrailing
  @ViewBuilder let content: (_ dismiss: @escaping () -> Void) -> Content

  @State private var expanded = false
  @State private var contentH: CGFloat = 0
  @Namespace private var ns
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var anchor: UnitPoint { placement == .bottomTrailing ? .bottomTrailing : .topTrailing }
  private var spring: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82) }

  private func toggle() {
    Haptics.selection()
    withAnimation(spring) { expanded.toggle() }
  }

  private func close() {
    withAnimation(spring) { expanded = false }
  }

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: placement) {
        if expanded {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { close() }
            .accessibilityHidden(true)
        }
        morph(maxH: geo.size.height - 16)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
      }
      .frame(width: geo.size.width, height: geo.size.height, alignment: placement)
    }
    .task {
      if StageDebug.openOrb {
        try? await Task.sleep(for: .seconds(1.2))
        withAnimation(spring) { expanded = true }
      }
    }
  }

  // MARK: botão e painel

  private var button: some View {
    Button(action: toggle) {
      HStack(spacing: 7) {
        Image(systemName: icon).font(.system(size: 17, weight: .semibold))
        if let title { Text(title).font(Theme.font(13, .semibold)).lineLimit(1) }
      }
      .foregroundStyle(Theme.text)
      .padding(.horizontal, title == nil ? 0 : 14)
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Capsule())
    }
    .buttonStyle(StageTabStyle())
    .accessibilityLabel(accessibilityLabel)
  }

  private func panel(maxH: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(title ?? "Estilos", systemImage: icon)
          .font(Theme.font(14, .bold))
          .foregroundStyle(Theme.text)
          .labelStyle(.titleAndIcon)
        Spacer()
        Button(action: close) {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.text)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.white.opacity(0.10)))
            .contentShape(Circle())
        }
        .buttonStyle(StageTabStyle())
        .accessibilityLabel("Fechar")
      }
      .padding(.leading, 6)

      ScrollView(.vertical, showsIndicators: false) {
        content(close)
          .frame(maxWidth: .infinity, alignment: .leading)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentH = $0 }
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(height: min(max(contentH, 60), max(120, maxH - 70)))
    }
    .padding(10)
    .frame(width: 304)
  }

  @ViewBuilder
  private func morph(maxH: CGFloat) -> some View {
    if #available(iOS 26.0, *) {
      GlassEffectContainer(spacing: 30) {
        if expanded {
          panel(maxH: maxH)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .glassEffectID("orb", in: ns)
        } else {
          button
            .glassEffect(.regular.interactive(), in: Capsule())
            .glassEffectID("orb", in: ns)
        }
      }
    } else {
      ZStack(alignment: placement) {
        if expanded {
          panel(maxH: maxH)
            .glass(30)
            .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
            .transition(.scale(scale: 0.3, anchor: anchor).combined(with: .opacity))
        } else {
          button
            .glassCapsule(interactive: true)
            .transition(.scale(scale: 0.6, anchor: anchor).combined(with: .opacity))
        }
      }
    }
  }
}
