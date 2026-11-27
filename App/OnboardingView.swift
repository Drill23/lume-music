import SwiftUI

// MARK: - Preferências do onboarding (para a Home e Ajustes)

/// Chaves e atalhos do onboarding.
///
/// UserDefaults:
/// - `lume.onboarding.done`   (Bool)     — já passou pela primeira abertura
/// - `lume.onboarding.genres` ([String]) — ids de `MusicGenre` escolhidos (ex.: "sertanejo", "pop")
/// - `lume.onboarding.artists`([String]) — nomes de artistas escolhidos (também seguidos via `LibraryStore.toggleFollow`)
enum Onboarding {
  static let doneKey = "lume.onboarding.done"
  static let genresKey = "lume.onboarding.genres"
  static let artistsKey = "lume.onboarding.artists"
  static let reopenNotification = Notification.Name("lume.onboarding.reopen")

  static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

  /// Ids de gênero escolhidos na primeira abertura (vazio se pulou).
  static var genreIds: [String] { UserDefaults.standard.stringArray(forKey: genresKey) ?? [] }

  /// Gêneros escolhidos, na ordem em que a pessoa tocou.
  static var genres: [MusicGenre] {
    genreIds.compactMap { id in MusicGenre.all.first { $0.id == id } }
  }

  static var artistNames: [String] { UserDefaults.standard.stringArray(forKey: artistsKey) ?? [] }

  /// Reabre o onboarding agora (botão em Ajustes). As escolhas anteriores são mantidas até a pessoa escolher de novo.
  @MainActor static func reset() {
    UserDefaults.standard.set(false, forKey: doneKey)
    NotificationCenter.default.post(name: reopenNotification, object: nil)
  }

  static var debugForced: Bool { ProcessInfo.processInfo.arguments.contains("-LMDebugOnboarding") }

  static func debugValue(_ flag: String) -> String? {
    let args = ProcessInfo.processInfo.arguments
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
  }
}

enum OnboardingStep: String, CaseIterable {
  case welcome, access, genres, artists, importLib, done

  /// Índice de paleta do fundo.
  var palette: Double {
    switch self {
    case .welcome: return 0
    case .access: return 1
    case .genres: return 2
    case .artists: return 3
    case .importLib: return 4
    case .done: return 5
    }
  }
}

extension OnboardingView {
  /// Reabre a abertura interativa (use em Ajustes: "Rever apresentação").
  @MainActor static func reset() { Onboarding.reset() }
}

// MARK: - Fundo animado

/// Manchas de cor suaves que se movem devagar e mudam de paleta a cada passo. ≤ 30 fps e pausa fora de cena.
struct OnboardingBackdrop: View, Animatable {
  var phase: Double
  var running: Bool

  var animatableData: Double {
    get { phase }
    set { phase = newValue }
  }

  @Environment(\.colorScheme) private var scheme

  private static let palettes: [[UInt32]] = [
    [0xFFB27A, 0xFF7BA9, 0xAD8CFF],
    [0xAD8CFF, 0x7CC8FF, 0xFF7BA9],
    [0xFF7BA9, 0xFFB27A, 0xAD8CFF],
    [0x7CC8FF, 0xAD8CFF, 0x6FE3C1],
    [0x6FE3C1, 0x7CC8FF, 0xFFB27A],
    [0xFFB27A, 0xFF7BA9, 0xAD8CFF],
    [0xAD8CFF, 0x7CC8FF, 0xFF7BA9],
  ]

  private func color(_ blob: Int) -> Color {
    let p = max(0, min(Double(Self.palettes.count - 1), phase))
    let lo = Int(p.rounded(.down)), hi = min(Self.palettes.count - 1, lo + 1)
    let f = p - Double(lo)
    func comps(_ v: UInt32) -> (Double, Double, Double) {
      (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
    let a = comps(Self.palettes[lo][blob]), b = comps(Self.palettes[hi][blob])
    return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
  }

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running || !Theme.motion)) { tl in
      let t = tl.date.timeIntervalSinceReferenceDate
      Canvas { ctx, size in
        let alpha = scheme == .dark ? 0.50 : 0.42
        let r = max(size.width, size.height) * 0.62
        for i in 0..<3 {
          let fi = Double(i)
          let x = size.width * (0.5 + 0.34 * sin(t * 0.17 + fi * 2.1))
          let y = size.height * (0.5 + 0.36 * cos(t * 0.13 + fi * 1.7))
          let c = color(i)
          let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
          ctx.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(Gradient(colors: [c.opacity(alpha), c.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r)
          )
        }
      }
    }
    .allowsHitTesting(false)
  }
}

// MARK: - Layout de bolhas

struct FlowLayout: Layout {
  var spacing: CGFloat = 10
  var lineSpacing: CGFloat = 10

  private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [[Int]] {
    var rows: [[Int]] = [[]]
    var x: CGFloat = 0
    for (i, s) in subviews.enumerated() {
      let w = s.sizeThatFits(.unspecified).width
      if x + w > maxWidth, !rows[rows.count - 1].isEmpty {
        rows.append([]); x = 0
      }
      rows[rows.count - 1].append(i)
      x += w + spacing
    }
    return rows
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let maxW = proposal.width ?? 340
    let rs = rows(subviews, maxWidth: maxW)
    var h: CGFloat = 0
    for r in rs { h += (r.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0) }
    h += CGFloat(max(0, rs.count - 1)) * lineSpacing
    return CGSize(width: maxW, height: h)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let rs = rows(subviews, maxWidth: bounds.width)
    var y = bounds.minY
    for r in rs {
      let sizes = r.map { subviews[$0].sizeThatFits(.unspecified) }
      let total = sizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, r.count - 1)) * spacing
      var x = bounds.minX + (bounds.width - total) / 2
      let rowH = sizes.map(\.height).max() ?? 0
      for (k, idx) in r.enumerated() {
        subviews[idx].place(at: CGPoint(x: x, y: y + (rowH - sizes[k].height) / 2), proposal: .unspecified)
        x += sizes[k].width + spacing
      }
      y += rowH + lineSpacing
    }
  }
}

// MARK: - Onboarding

/// Primeira abertura interativa: boas-vindas → (código de acesso) → estilos → artistas → importar → pronto → carregando.
struct OnboardingView: View {
  /// Chamado quando a abertura termina e o app deve aparecer.
  let onFinish: () -> Void

  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject private var access = AccessService.shared
  @StateObject private var importer = ImportCoordinator()
  @Namespace private var ns

  @State private var steps: [OnboardingStep] = [.welcome, .genres, .artists, .importLib, .done]
  @State private var index = 0
  @State private var forward = true
  @State private var selectedGenres: [String] = []
  @State private var selectedArtists: [String] = []
  @State private var checkingConfig = false
  @State private var ripple = 0
  @State private var loading = false
  @State private var revealRadius: CGFloat?
  @State private var accessInfo: AccessInfo?

  private var step: OnboardingStep { steps[min(index, steps.count - 1)] }
  private var chosenGenres: [MusicGenre] { selectedGenres.compactMap { id in MusicGenre.all.first { $0.id == id } } }
  private var debugImportService: ImportServiceKind? { Onboarding.debugValue("-LMDebugService").flatMap { ImportServiceKind(rawValue: $0) } }

  var body: some View {
    GeometryReader { geo in
      let markCY = geo.size.height * 0.30
      ZStack {
        Theme.canvas.ignoresSafeArea()
        OnboardingBackdrop(phase: loading ? 6 : step.palette, running: scenePhase == .active)
          .animation(.easeInOut(duration: 0.9), value: step)
          .animation(.easeInOut(duration: 0.9), value: loading)
          .ignoresSafeArea()

        if loading {
          LoadingMusicView(genres: chosenGenres.isEmpty ? Onboarding.genres : chosenGenres, onFinish: reveal)
            .transition(.opacity)
        } else {
          content(width: geo.size.width, markCY: markCY, safeTop: geo.safeAreaInsets.top)
            .transition(.opacity)

          // Onda de vidro que se expande a cada passo.
          RippleBurst(trigger: ripple)
            .position(x: geo.size.width / 2, y: geo.size.height - 70)
            .allowsHitTesting(false)
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .compositingGroup()
      .mask(revealMask(size: geo.size))
    }
    .ignoresSafeArea(.container, edges: .bottom)
    .onAppear {
      SoundFX.shared.begin()
      SoundFX.shared.holdOpen = true
      applyDebugState()
    }
  }

  // MARK: Conteúdo dos passos

  @ViewBuilder
  private func content(width: CGFloat, markCY: CGFloat, safeTop: CGFloat) -> some View {
    ZStack {
      // Marca única que viaja entre as telas (centro ↔ cabeçalho).
      let big = step == .welcome || step == .done
      PrismMark(size: 150)
        .scaleEffect(big ? 1 : 0.2)
        .position(x: width / 2, y: big ? markCY : 30)   // pequeno: no centro da linha dos botões do cabeçalho
        .animation(.spring(response: 0.7, dampingFraction: 0.82), value: step)
        .allowsHitTesting(false)

      VStack(spacing: 0) {
        header
        ZStack {
          stepView(width: width, markCY: markCY)
            .id(step)
            .transition(
              .asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.96))
              )
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  @ViewBuilder
  private func stepView(width: CGFloat, markCY: CGFloat) -> some View {
    switch step {
    case .welcome:
      WelcomeStep(centerY: markCY, loading: checkingConfig) { Task { await startFromWelcome() } }
    case .access:
      AccessStep(info: $accessInfo) { go(1) }
    case .genres:
      GenresStep(selected: $selectedGenres) {
        UserDefaults.standard.set(selectedGenres, forKey: Onboarding.genresKey)
        go(1)
      }
    case .artists:
      ArtistsStep(genres: chosenGenres, selected: $selectedArtists) {
        UserDefaults.standard.set(selectedArtists, forKey: Onboarding.artistsKey)
        go(1)
      }
    case .importLib:
      ImportStep(importer: importer, initialService: debugImportService) { go(1) }
    case .done:
      DoneStep(centerY: markCY, genres: chosenGenres, artists: selectedArtists.count, imported: importer.importedTracks) {
        enterApp()
      }
    }
  }

  // MARK: Cabeçalho

  private var header: some View {
    ZStack {
      HStack {
        if canGoBack {
          Button { go(-1) } label: {
            Image(systemName: "chevron.left")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(Theme.text)
              .frame(width: 44, height: 44)
              .glassCircle(interactive: true)
          }
          .accessibilityLabel("Voltar")
          .transition(.scale.combined(with: .opacity))
        }
        Spacer()
        if canSkip {
          Button { skip() } label: {
            Text("Pular")
              .font(Theme.font(15, .semibold))
              .foregroundStyle(Theme.secondary)
              .padding(.horizontal, 16)
              .frame(minWidth: 44, minHeight: 44)
              .glassCapsule(interactive: true)
          }
          .transition(.scale.combined(with: .opacity))
        }
      }
      if step != .welcome && step != .done {
        VStack(spacing: 0) {
          Spacer().frame(height: 52)
          dots
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .frame(height: step == .welcome || step == .done ? 60 : 96, alignment: .top)
    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
  }

  private var dots: some View {
    HStack(spacing: 6) {
      ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
        if s != .welcome && s != .done {
          Capsule()
            .fill(i == index ? AnyShapeStyle(Theme.prism) : AnyShapeStyle(Theme.fillStrong))
            .frame(width: i == index ? 24 : 7, height: 7)
        }
      }
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
  }

  private var canGoBack: Bool {
    guard index > 0 else { return false }
    if step == .access || step == .done { return false }
    return steps[index - 1] != .access && steps[index - 1] != .welcome
  }

  private var canSkip: Bool { step == .genres || step == .artists || step == .importLib }

  // MARK: Navegação

  private func go(_ delta: Int) {
    let target = max(0, min(steps.count - 1, index + delta))
    guard target != index else { return }
    forward = delta > 0
    SoundFX.shared.play(.whoosh)
    SoundFX.shared.resetScale()
    Haptics.soft()
    ripple += 1
    withAnimation(.spring(response: 0.62, dampingFraction: 0.86)) { index = target }
  }

  private func skip() {
    // Sem estilos escolhidos não há o que sugerir de artistas: vai direto para o fim.
    if step == .genres && selectedGenres.isEmpty {
      go(steps.count - 1 - index)
    } else {
      go(1)
    }
  }

  private func startFromWelcome() async {
    checkingConfig = true
    // Descobre se o portão de código está ligado (config remota, timeout de 6 s).
    await access.ensureConfig()
    checkingConfig = false
    if access.needsCode, !steps.contains(.access) {
      steps.insert(.access, at: 1)
    }
    SoundFX.shared.play(.tap)
    go(1)
  }

  private func enterApp() {
    UserDefaults.standard.set(true, forKey: Onboarding.doneKey)
    UserDefaults.standard.set(selectedGenres, forKey: Onboarding.genresKey)
    UserDefaults.standard.set(selectedArtists, forKey: Onboarding.artistsKey)
    // Artistas escolhidos passam a ser seguidos (a Home usa "seguidos" para lançamentos).
    for name in selectedArtists where !LibraryStore.shared.isFollowing(name) {
      LibraryStore.shared.toggleFollow(name)
    }
    SoundFX.shared.play(.chord)
    Haptics.success()
    withAnimation(.easeInOut(duration: 0.55)) { loading = true }
  }

  // MARK: Saída com vidro expandindo

  private func reveal() {
    SoundFX.shared.play(.whoosh)
    guard Theme.motion else { finishNow(); return }
    withAnimation(.easeInOut(duration: 0.75)) { revealRadius = 1400 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { finishNow() }
  }

  private func finishNow() {
    SoundFX.shared.end()
    onFinish()
  }

  @ViewBuilder
  private func revealMask(size: CGSize) -> some View {
    if let r = revealRadius {
      Rectangle()
        .fill(.black)
        .overlay {
          Circle().frame(width: r * 2, height: r * 2).blendMode(.destinationOut)
        }
        .compositingGroup()
    } else {
      Rectangle().fill(.black)
    }
  }

  // MARK: Depuração

  private func applyDebugState() {
    if let g = Onboarding.debugValue("-LMDebugGenres") {
      selectedGenres = g.split(separator: ",").map(String.init)
    }
    if let a = Onboarding.debugValue("-LMDebugArtists") {
      selectedArtists = a.split(separator: ",").map { $0.replacingOccurrences(of: "_", with: " ") }
    }
    guard let raw = Onboarding.debugValue("-LMDebugOnboardingStep") else { return }
    if raw == "loading" { withAnimation { loading = true }; return }
    guard let want = OnboardingStep(rawValue: raw) else { return }
    if want == .access, !steps.contains(.access) { steps.insert(.access, at: 1) }
    if let i = steps.firstIndex(of: want) { index = i }
  }
}

/// Anel de vidro que se expande e some (transição entre passos).
struct RippleBurst: View {
  let trigger: Int
  @State private var value = 0

  var body: some View {
    Circle()
      .stroke(Theme.prismAngular, lineWidth: 3)
      .frame(width: 120, height: 120)
      .keyframeAnimator(initialValue: RippleValues(), trigger: trigger) { content, v in
        content.scaleEffect(v.scale).opacity(v.opacity)
      } keyframes: { _ in
        KeyframeTrack(\.scale) { LinearKeyframe(0.2, duration: 0); CubicKeyframe(9, duration: 0.85) }
        KeyframeTrack(\.opacity) { LinearKeyframe(trigger == 0 ? 0 : 0.55, duration: 0); CubicKeyframe(0, duration: 0.85) }
      }
  }

  struct RippleValues {
    var scale: CGFloat = 0.2
    var opacity: Double = 0
  }
}

// MARK: - 1. Boas-vindas

private struct WelcomeStep: View {
  let centerY: CGFloat
  let loading: Bool
  let onStart: () -> Void

  @State private var appear = false
  @State private var spin = false
  @State private var pulse = false

  private let words1 = ["Sua", "música,"]
  private let words2 = ["em", "outra", "luz."]

  var body: some View {
    ZStack {
      // Disco de vidro girando + ondas suaves (centrado onde a marca está).
      GeometryReader { geo in
        ZStack {
          ForEach(0..<3, id: \.self) { i in
            Circle()
              .stroke(Theme.prismAngular.opacity(0.6), lineWidth: 1.6)
              .frame(width: 170, height: 170)
              .scaleEffect(pulse ? 2.3 : 0.9)
              .opacity(pulse ? 0 : 0.7)
              .animation(
                Theme.motion ? .easeOut(duration: 3.6).repeatForever(autoreverses: false).delay(Double(i) * 1.2) : nil,
                value: pulse
              )
          }
          Circle()
            .fill(Color.clear)
            .frame(width: 214, height: 214)
            .background(Circle().fill(Color.white.opacity(0.07)))   // sem vidro desfocando a marca por baixo
          Circle()
            .stroke(Theme.prismAngular, lineWidth: 3)
            .frame(width: 214, height: 214)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(Theme.motion ? .linear(duration: 16).repeatForever(autoreverses: false) : nil, value: spin)
            .opacity(0.8)
        }
        .scaleEffect(appear ? 1 : 0.5)
        .opacity(appear ? 1 : 0)
        .position(x: geo.size.width / 2, y: centerY - 60)
      }

      VStack(spacing: 0) {
        Spacer()
        VStack(spacing: 6) {
          wordLine(words1, offset: 0)
          wordLine(words2, offset: words1.count, prism: true)
        }
        Text("Vamos deixar a Lume com a sua cara em menos de um minuto.")
          .font(Theme.font(15.5))
          .foregroundStyle(Theme.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 36)
          .padding(.top, 14)
          .opacity(appear ? 1 : 0)
          .animation(.easeOut(duration: 0.6).delay(0.9), value: appear)
        PrismButton(title: loading ? "Preparando…" : "Começar", systemImage: loading ? nil : "arrow.right", height: 54, action: onStart)
          .disabled(loading)
          .padding(.horizontal, 28)
          .padding(.top, 28)
          .scaleEffect(appear ? 1 : 0.9)
          .opacity(appear ? 1 : 0)
          .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.1), value: appear)
        Text(Theme.credit)
          .font(Theme.font(11.5))
          .foregroundStyle(Theme.tertiary)
          .padding(.top, 18)
          .padding(.bottom, 26)
      }
    }
    .onAppear {
      appear = true; spin = true; pulse = true
      Haptics.soft()
    }
  }

  private func wordLine(_ words: [String], offset: Int, prism: Bool = false) -> some View {
    HStack(spacing: 10) {
      ForEach(Array(words.enumerated()), id: \.offset) { i, w in
        Text(w)
          .font(.system(size: 38, weight: .bold, design: .rounded))
          .foregroundStyle(prism ? AnyShapeStyle(Theme.prism) : AnyShapeStyle(Theme.text))
          .opacity(appear ? 1 : 0)
          .offset(y: appear ? 0 : 16)
          .animation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.35 + Double(offset + i) * 0.14), value: appear)
      }
    }
  }
}

// MARK: - 2. Código de acesso

private struct AccessStep: View {
  @Binding var info: AccessInfo?
  let onDone: () -> Void

  var body: some View {
    VStack {
      Spacer(minLength: 20)
      if let info {
        AccessSuccessView(info: info, buttonTitle: "Continuar", onContinue: onDone)
          .transition(.scale(scale: 0.94).combined(with: .opacity))
      } else {
        AccessCodeView { i in
          withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { info = i }
        }
        .transition(.opacity)
      }
      Spacer(minLength: 20)
    }
    .padding(.horizontal, 24)
    .padding(.top, 60)
  }
}

// MARK: - 3. Estilos

private enum GenreLabel {
  static func short(_ g: MusicGenre) -> String {
    switch g.id {
    case "funk_br": return "Funk"
    case "pagode": return "Pagode"
    case "mpb": return "MPB"
    case "forro": return "Forró / Piseiro"
    case "gospel": return "Gospel"
    case "hiphop": return "Hip-Hop / Rap"
    case "eletronica": return "Eletrônica"
    case "rnb": return "R&B"
    case "latina": return "Latina"
    case "indie": return "Indie"
    case "classica": return "Clássica"
    case "soundtrack": return "Trilhas & Games"
    default: return g.title
    }
  }
}

private struct GenresStep: View {
  @Binding var selected: [String]
  let onNext: () -> Void

  @State private var shown = false

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        Text("Qual estilo você mais curte?")
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.text)
          .multilineTextAlignment(.center)
        Text("Toque nos que combinam com você. Pode escolher vários.")
          .font(Theme.font(14.5))
          .foregroundStyle(Theme.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 28)
      .padding(.top, 4)

      ScrollView(showsIndicators: false) {
        FlowLayout(spacing: 10, lineSpacing: 12) {
          ForEach(Array(MusicGenre.all.enumerated()), id: \.element.id) { i, g in
            GenreBubble(genre: g, selected: selected.contains(g.id)) { toggle(g) }
              .scaleEffect(shown ? 1 : 0.5)
              .opacity(shown ? 1 : 0)
              .animation(.spring(response: 0.5, dampingFraction: 0.72).delay(Double(i) * 0.03), value: shown)
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
      }

      bottomBar
    }
    .onAppear { shown = true }
  }

  private var bottomBar: some View {
    VStack(spacing: 10) {
      Text(selected.isEmpty ? "Escolha pelo menos um" : "\(selected.count) escolhido\(selected.count == 1 ? "" : "s")")
        .font(Theme.font(13.5, .medium))
        .foregroundStyle(Theme.secondary)
        .contentTransition(.numericText())
        .animation(.snappy, value: selected.count)
      PrismButton(title: "Continuar", systemImage: "arrow.right", height: 54, action: onNext)
        .disabled(selected.isEmpty)
        .opacity(selected.isEmpty ? 0.4 : 1)
        .animation(.easeOut(duration: 0.25), value: selected.isEmpty)
    }
    .padding(.horizontal, 28)
    .padding(.bottom, 26)
    .padding(.top, 10)
  }

  private func toggle(_ g: MusicGenre) {
    if let i = selected.firstIndex(of: g.id) {
      selected.remove(at: i)
      SoundFX.shared.play(.deselect)
      Haptics.light()
    } else {
      selected.append(g.id)
      SoundFX.shared.play(.select)
      Haptics.medium()
    }
  }
}

private struct GenreBubble: View {
  let genre: MusicGenre
  let selected: Bool
  let action: () -> Void

  @State private var burst = 0

  var body: some View {
    Button {
      burst += 1
      action()
    } label: {
      HStack(spacing: 8) {
        Image(systemName: genre.icon)
          .font(.system(size: 15, weight: .bold))
        Text(GenreLabel.short(genre))
          .font(Theme.font(15.5, .semibold))
          .lineLimit(1)
      }
      .foregroundStyle(selected ? Color.white : Theme.text)
      .padding(.horizontal, 16)
      .frame(minHeight: 48)
      .background {
        if selected {
          Capsule().fill(LinearGradient(colors: [Color(hex: genre.hexA), Color(hex: genre.hexB)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .shadow(color: Color(hex: genre.hexA).opacity(0.5), radius: 10, y: 4)
        } else {
          Capsule().fill(Color.clear).glassCapsule(interactive: true)
        }
      }
      .overlay(Capsule().stroke(selected ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .keyframeAnimator(initialValue: BubblePulse(), trigger: burst) { content, v in
      content
        .scaleEffect(v.scale)
        .overlay {
          Capsule()
            .stroke(Color(hex: genre.hexA), lineWidth: 2)
            .scaleEffect(v.ring)
            .opacity(v.ringOpacity)
            .allowsHitTesting(false)
        }
    } keyframes: { _ in
      KeyframeTrack(\.scale) {
        SpringKeyframe(0.88, duration: 0.09)
        SpringKeyframe(1.1, duration: 0.2, spring: .bouncy)
        SpringKeyframe(1, duration: 0.25)
      }
      KeyframeTrack(\.ring) { LinearKeyframe(1, duration: 0.05); CubicKeyframe(1.5, duration: 0.5) }
      KeyframeTrack(\.ringOpacity) { LinearKeyframe(burst == 0 ? 0 : 0.7, duration: 0.05); CubicKeyframe(0, duration: 0.5) }
    }
    .accessibilityLabel(GenreLabel.short(genre))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  struct BubblePulse {
    var scale: CGFloat = 1
    var ring: CGFloat = 1
    var ringOpacity: Double = 0
  }
}

// MARK: - 4. Artistas

private enum ArtistSuggestions {
  static let byGenre: [String: [String]] = [
    "sertanejo": ["Gusttavo Lima", "Jorge & Mateus", "Henrique & Juliano", "Marília Mendonça", "Ana Castela", "Luan Santana"],
    "funk_br": ["MC Ryan SP", "MC Cabelinho", "Anitta", "MC Hariel", "Kevinho", "MC Livinho"],
    "pagode": ["Thiaguinho", "Menos É Mais", "Ferrugem", "Grupo Revelação", "Péricles", "Dilsinho"],
    "mpb": ["Caetano Veloso", "Gilberto Gil", "Djavan", "Milton Nascimento", "Marisa Monte", "Jorge Ben Jor"],
    "forro": ["Zé Vaqueiro", "Natanzinho Lima", "Mari Fernandez", "Xand Avião", "Wesley Safadão", "Luiz Gonzaga"],
    "gospel": ["Aline Barros", "Fernandinho", "Gabriela Rocha", "Isadora Pompeo", "Thalles Roberto", "Hillsong United"],
    "pop": ["Taylor Swift", "Dua Lipa", "Ariana Grande", "Billie Eilish", "The Weeknd", "Sabrina Carpenter"],
    "rock": ["Queen", "Foo Fighters", "Legião Urbana", "Nirvana", "Imagine Dragons", "Capital Inicial"],
    "hiphop": ["Kendrick Lamar", "Drake", "Travis Scott", "Emicida", "Djonga", "Eminem"],
    "eletronica": ["Alok", "Calvin Harris", "David Guetta", "Martin Garrix", "Vintage Culture", "Avicii"],
    "rnb": ["SZA", "Beyoncé", "Bruno Mars", "Frank Ocean", "Rihanna", "Usher"],
    "latina": ["Bad Bunny", "Shakira", "J Balvin", "Karol G", "Rosalía", "Daddy Yankee"],
    "kpop": ["BTS", "BLACKPINK", "NewJeans", "Stray Kids", "TWICE", "LE SSERAFIM"],
    "metal": ["Metallica", "Iron Maiden", "Sepultura", "Black Sabbath", "Slipknot", "Angra"],
    "indie": ["Arctic Monkeys", "Tame Impala", "Lana Del Rey", "Mac DeMarco", "Radiohead", "Terno Rei"],
    "jazz": ["Miles Davis", "Norah Jones", "Louis Armstrong", "John Coltrane", "Ella Fitzgerald", "Diana Krall"],
    "classica": ["Mozart", "Beethoven", "Chopin", "Ludovico Einaudi", "Vivaldi", "Johann Sebastian Bach"],
    "reggae": ["Bob Marley", "Natiruts", "Jimmy Cliff", "Ponto de Equilíbrio", "Peter Tosh", "Gregory Isaacs"],
    "country": ["Luke Combs", "Morgan Wallen", "Johnny Cash", "Dolly Parton", "Zach Bryan", "Chris Stapleton"],
    "soundtrack": ["Hans Zimmer", "John Williams", "Ramin Djawadi", "Ennio Morricone", "Joe Hisaishi", "Howard Shore"],
  ]

  /// Intercala os estilos escolhidos para variar (até 15 nomes).
  static func list(for genres: [MusicGenre]) -> [String] {
    let ids = genres.isEmpty ? ["pop", "sertanejo", "funk_br"] : genres.map(\.id)
    var out: [String] = []
    var round = 0
    while out.count < 15, round < 6 {
      for id in ids {
        if let arr = byGenre[id], round < arr.count, !out.contains(arr[round]), out.count < 15 { out.append(arr[round]) }
      }
      round += 1
    }
    return out
  }
}

@MainActor
private final class ArtistPicsModel: ObservableObject {
  @Published var pics: [String: String] = [:]
  @Published var results: [ArtistInfo] = []
  @Published var searching = false
  private var searchTask: Task<Void, Never>?

  func load(_ names: [String]) {
    for name in names where pics[name] == nil {
      Task {
        let hits = await SearchService.shared.artists(name)
        let best = hits.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? hits.first
        if let url = best?.pictureURL, !url.isEmpty { pics[name] = url }
      }
    }
  }

  func search(_ q: String) {
    searchTask?.cancel()
    let query = q.trimmingCharacters(in: .whitespaces)
    guard query.count >= 2 else { results = []; searching = false; return }
    searching = true
    searchTask = Task {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      let r = await SearchService.shared.artists(query)
      guard !Task.isCancelled else { return }
      results = Array(r.prefix(9))
      for a in results where !a.pictureURL.isEmpty { pics[a.name] = a.pictureURL }
      searching = false
    }
  }
}

private struct ArtistsStep: View {
  let genres: [MusicGenre]
  @Binding var selected: [String]
  let onNext: () -> Void

  @StateObject private var model = ArtistPicsModel()
  @State private var query = ""
  @State private var shown = false

  private var suggestions: [String] { ArtistSuggestions.list(for: genres) }
  private var searchNames: [String] { model.results.map(\.name).filter { n in !suggestions.contains(n) } }

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        Text("Artistas que você ama")
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.text)
        Text("Opcional. Eles aparecem primeiro nos seus lançamentos.")
          .font(Theme.font(14.5))
          .foregroundStyle(Theme.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 28)

      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.secondary)
        TextField("Buscar outro artista", text: $query)
          .font(Theme.font(15.5))
          .foregroundStyle(Theme.text)
          .autocorrectionDisabled()
          .submitLabel(.search)
        if model.searching { ProgressView().scaleEffect(0.8) }
        else if !query.isEmpty {
          Button { query = "" } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary).frame(width: 44, height: 44)
          }
        }
      }
      .padding(.leading, 16)
      .frame(height: 48)
      .glassCapsule()
      .padding(.horizontal, 24)
      .padding(.top, 16)

      ScrollView(showsIndicators: false) {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 16) {
          ForEach(Array((searchNames + suggestions).enumerated()), id: \.element) { i, name in
            OBArtistBubble(name: name, picture: model.pics[name], selected: selected.contains(name)) { toggle(name) }
              .scaleEffect(shown ? 1 : 0.6)
              .opacity(shown ? 1 : 0)
              .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(min(i, 12)) * 0.04), value: shown)
          }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
      }
      .scrollDismissesKeyboard(.interactively)

      VStack(spacing: 8) {
        PrismButton(title: selected.isEmpty ? "Continuar sem escolher" : "Continuar · \(selected.count)", systemImage: "arrow.right", height: 54, action: onNext)
          .contentTransition(.numericText())
          .animation(.snappy, value: selected.count)
      }
      .padding(.horizontal, 28)
      .padding(.bottom, 26)
      .padding(.top, 8)
    }
    .onAppear {
      shown = true
      model.load(suggestions)
    }
    .onChange(of: query) { _, q in model.search(q) }
  }

  private func toggle(_ name: String) {
    if let i = selected.firstIndex(of: name) {
      selected.remove(at: i); SoundFX.shared.play(.deselect); Haptics.light()
    } else {
      selected.append(name); SoundFX.shared.play(.select); Haptics.medium()
    }
  }
}

private struct OBArtistBubble: View {
  let name: String
  let picture: String?
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        ZStack(alignment: .bottomTrailing) {
          ZStack {
            if let picture, !picture.isEmpty {
              ArtworkImage(url: picture, cornerRadius: 46, maxPixel: 240, placeholderIcon: "person.fill")
            } else {
              Circle().fill(Theme.fillStrong)
                .overlay(Image(systemName: "person.fill").font(.system(size: 28)).foregroundStyle(Theme.tertiary))
            }
          }
          .frame(width: 92, height: 92)
          .clipShape(Circle())
          .overlay(Circle().stroke(selected ? AnyShapeStyle(Theme.prismAngular) : AnyShapeStyle(Theme.hairline), lineWidth: selected ? 4 : 1))
          .shadow(color: selected ? Theme.rose.opacity(0.45) : .clear, radius: 10, y: 4)
          .scaleEffect(selected ? 1.06 : 1)

          if selected {
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Theme.onPrism)
              .frame(width: 26, height: 26)
              .background(Circle().fill(Theme.prismDiagonal))
              .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
              .transition(.scale.combined(with: .opacity))
          }
        }
        Text(name)
          .font(Theme.font(12.5, selected ? .semibold : .medium))
          .foregroundStyle(selected ? Theme.text : Theme.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .frame(height: 32, alignment: .top)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle(scale: 0.94))
    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selected)
    .accessibilityLabel(name)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

// MARK: - 5. Importar

private struct ImportStep: View {
  @ObservedObject var importer: ImportCoordinator
  var initialService: ImportServiceKind?
  let onNext: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 8) {
        Text("Traga sua música")
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.text)
        Text("Já tem playlists em outro serviço? Traga tudo para cá com um toque.")
          .font(Theme.font(14.5))
          .foregroundStyle(Theme.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 28)

      ScrollView(showsIndicators: false) {
        ImportHubPanel(coordinator: importer, compact: true, initialService: initialService)
          .padding(.horizontal, 22)
          .padding(.vertical, 20)
      }

      VStack(spacing: 8) {
        if importer.importedTracks > 0 {
          PrismButton(title: "Continuar", systemImage: "arrow.right", height: 54, action: onNext)
        } else {
          GlassButton(title: "Agora não, importo depois", height: 54, action: onNext)
        }
        if importer.importedTracks == 0 {
          Text("Você pode importar a qualquer hora em Biblioteca.")
            .font(Theme.font(12)).foregroundStyle(Theme.tertiary)
        }
      }
      .padding(.horizontal, 28)
      .padding(.bottom, 26)
      .padding(.top, 8)
      .animation(.spring(response: 0.4, dampingFraction: 0.85), value: importer.importedTracks)
    }
  }
}

// MARK: - 6. Tudo pronto

private struct DoneStep: View {
  let centerY: CGFloat
  let genres: [MusicGenre]
  let artists: Int
  let imported: Int
  let onEnter: () -> Void

  @State private var appear = false

  var body: some View {
    ZStack {
      GeometryReader { geo in
        ZStack {
          ForEach(0..<12, id: \.self) { i in
            let a = Double(i) / 12 * 2 * .pi
            Image(systemName: i % 3 == 0 ? "sparkle" : "circle.fill")
              .font(.system(size: i % 3 == 0 ? 15 : 6, weight: .bold))
              .foregroundStyle(Theme.prismColors[i % 4])
              .offset(x: appear ? CGFloat(cos(a)) * 128 : 0, y: appear ? CGFloat(sin(a)) * 128 : 0)
              .scaleEffect(appear ? 1 : 0.2)
              .opacity(appear ? 0.0 : 1)
              .animation(.easeOut(duration: 1.1).delay(0.25), value: appear)
          }
          Circle().fill(Color.white.opacity(0.07)).frame(width: 200, height: 200)
            .scaleEffect(appear ? 1 : 0.4)
            .animation(.spring(response: 0.7, dampingFraction: 0.7), value: appear)
        }
        .position(x: geo.size.width / 2, y: centerY - 40)
      }

      VStack(spacing: 0) {
        Spacer()
        Text("Tudo pronto!")
          .font(.system(size: 36, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.text)
        Text(summary)
          .font(Theme.font(15.5))
          .foregroundStyle(Theme.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 36)
          .padding(.top, 10)
        PrismButton(title: "Entrar na Lume", systemImage: "sparkles", height: 56, action: onEnter)
          .padding(.horizontal, 28)
          .padding(.top, 28)
          .padding(.bottom, 40)
      }
      .opacity(appear ? 1 : 0)
      .offset(y: appear ? 0 : 20)
      .animation(.spring(response: 0.7, dampingFraction: 0.82).delay(0.2), value: appear)
    }
    .onAppear {
      appear = true
      SoundFX.shared.play(.success)
      Haptics.success()
    }
  }

  private var summary: String {
    var parts: [String] = []
    if !genres.isEmpty {
      let names = genres.prefix(3).map { GenreLabel.short($0) }
      parts.append("Montamos a sua Lume com \(names.joined(separator: ", "))" + (genres.count > 3 ? " e mais \(genres.count - 3)" : "") + ".")
    } else {
      parts.append("A sua Lume está pronta. Você pode afinar os estilos depois.")
    }
    if artists > 0 { parts.append("\(artists) artista\(artists == 1 ? "" : "s") para acompanhar.") }
    if imported > 0 { parts.append("\(imported) músicas importadas.") }
    return parts.joined(separator: " ")
  }
}
