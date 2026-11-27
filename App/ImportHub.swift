import SwiftUI
import UniformTypeIdentifiers

// MARK: - Serviços

/// Serviços de onde a pessoa pode trazer a biblioteca.
enum ImportServiceKind: String, CaseIterable, Identifiable {
  case appleMusic, spotify, youtubeMusic, deezer, amazonMusic, tidal, file

  var id: String { rawValue }

  var title: String {
    switch self {
    case .appleMusic: return "Apple Music"
    case .spotify: return "Spotify"
    case .youtubeMusic: return "YouTube Music"
    case .deezer: return "Deezer"
    case .amazonMusic: return "Amazon Music"
    case .tidal: return "Tidal"
    case .file: return "Arquivo"
    }
  }

  var tagline: String {
    switch self {
    case .appleMusic: return "1 toque · biblioteca do iPhone"
    case .spotify: return "Colar link da playlist"
    case .youtubeMusic: return "Colar link da playlist"
    case .deezer: return "Colar link da playlist"
    case .amazonMusic: return "Colar link da playlist"
    case .tidal: return "Colar link da playlist"
    case .file: return "CSV, M3U ou TXT"
    }
  }

  var symbol: String {
    switch self {
    case .appleMusic: return "music.note"
    case .spotify: return "dot.radiowaves.left.and.right"
    case .youtubeMusic: return "play.fill"
    case .deezer: return "chart.bar.fill"
    case .amazonMusic: return "waveform"
    case .tidal: return "diamond.fill"
    case .file: return "doc.text.fill"
    }
  }

  var colors: [Color] {
    switch self {
    case .appleMusic: return [Color(hex: 0xFF5A74), Color(hex: 0xFA2D48)]
    case .spotify: return [Color(hex: 0x3DDC84), Color(hex: 0x14A44D)]
    case .youtubeMusic: return [Color(hex: 0xFF5E5E), Color(hex: 0xE00000)]
    case .deezer: return [Color(hex: 0xB86BFF), Color(hex: 0x7B2FF2)]
    case .amazonMusic: return [Color(hex: 0x4FE3F0), Color(hex: 0x1AA7D6)]
    case .tidal: return [Color(hex: 0x6B7280), Color(hex: 0x111827)]
    case .file: return [Theme.peach, Theme.rose]
    }
  }

  /// Site/app para abrir (universal link: abre o app instalado, senão o site).
  var openURL: URL? {
    switch self {
    case .spotify: return URL(string: "https://open.spotify.com")
    case .youtubeMusic: return URL(string: "https://music.youtube.com")
    case .deezer: return URL(string: "https://www.deezer.com")
    case .amazonMusic: return URL(string: "https://music.amazon.com.br")
    case .tidal: return URL(string: "https://listen.tidal.com")
    case .appleMusic: return URL(string: "https://music.apple.com")
    case .file: return nil
    }
  }

  var howTo: [String] {
    switch self {
    case .spotify:
      return ["Abra o Spotify e entre na playlist (ela precisa estar pública).", "Toque em ••• › Compartilhar › Copiar link.", "Volte aqui e toque em “Colar link e importar”."]
    case .youtubeMusic:
      return ["Abra o YouTube Music e entre na playlist (pública ou não listada).", "Toque em Compartilhar › Copiar link.", "Volte aqui e toque em “Colar link e importar”."]
    case .deezer:
      return ["Abra o Deezer e entre na playlist.", "Toque em ••• › Compartilhar › Copiar link.", "Volte aqui e toque em “Colar link e importar”. Funciona com playlists e álbuns."]
    case .amazonMusic:
      return ["Abra o Amazon Music e entre na playlist.", "Toque em Compartilhar › Copiar link.", "Volte aqui e cole. Se a Amazon não deixar o Lume ler, exporte em CSV e use “Arquivo”."]
    case .tidal:
      return ["Abra o Tidal e entre na playlist.", "Toque em ••• › Compartilhar › Copiar link.", "Volte aqui e cole. Se o Tidal não deixar o Lume ler, exporte em CSV e use “Arquivo”."]
    case .appleMusic, .file:
      return []
    }
  }
}

// MARK: - Coordenador

struct ImportSummary: Equatable {
  struct Item: Equatable, Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let artworkURL: String
  }
  let service: String
  let items: [Item]
  var totalTracks: Int { items.reduce(0) { $0 + $1.count } }
}

/// Faz a importação de verdade (ImportService → LibraryStore) e expõe o estado para a interface.
@MainActor
final class ImportCoordinator: ObservableObject {
  enum Phase: Equatable {
    case idle
    case running(service: String, progress: ImportProgress)
    case done(ImportSummary)
    case failed(String)
  }

  @Published private(set) var phase: Phase = .idle
  /// Soma de faixas importadas desde que o coordenador foi criado (para a tela final do onboarding).
  @Published private(set) var importedTracks = 0
  @Published private(set) var importedPlaylists = 0

  private var task: Task<Void, Never>?
  private let store = LibraryStore.shared

  var isRunning: Bool { if case .running = phase { return true }; return false }

  func reset() { task?.cancel(); phase = .idle }

  func cancel() { task?.cancel(); phase = .idle }

  private func handler(_ service: String) -> ImportProgressHandler {
    { [weak self] p in
      Task { @MainActor in
        guard let self, case .running = self.phase else { return }
        self.phase = .running(service: service, progress: p)
      }
    }
  }

  func runApple() {
    start(service: "Apple Music") { [weak self] progress in
      let packs = try await ImportService.shared.importFromLocalAppleMusic(progress: progress)
      return await self?.commit(packs, service: "Apple Music") ?? ImportSummary(service: "Apple Music", items: [])
    }
  }

  func runLink(_ text: String) {
    let service = ImportService.serviceName(forLink: text) ?? "link"
    start(service: service) { [weak self] progress in
      let res = try await ImportService.shared.importFromURL(text, progress: progress)
      return await self?.commit([res], service: res.sourceBadge) ?? ImportSummary(service: service, items: [])
    }
  }

  func runFile(url: URL) {
    start(service: "Arquivo") { [weak self] _ in
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: url)
      let res = try await ImportService.shared.importFromFile(data: data, filename: url.lastPathComponent)
      return await self?.commit([res], service: "Arquivo") ?? ImportSummary(service: "Arquivo", items: [])
    }
  }

  func runText(_ text: String, name: String) {
    start(service: "Lista") { [weak self] _ in
      let res = await ImportService.shared.importFromText(text, name: name)
      guard !res.tracks.isEmpty else {
        throw NSError(domain: "LumeMusic", code: 20, userInfo: [NSLocalizedDescriptionKey: "Cole pelo menos uma música na lista."])
      }
      return await self?.commit([res], service: "Lista") ?? ImportSummary(service: "Lista", items: [])
    }
  }

  private func start(service: String, _ work: @escaping (@escaping ImportProgressHandler) async throws -> ImportSummary) {
    guard !isRunning else { return }
    task?.cancel()
    phase = .running(service: service, progress: ImportProgress(phase: "Conectando", done: 0, total: 0))
    Haptics.medium()
    task = Task { [weak self] in
      guard let self else { return }
      do {
        let summary = try await work(self.handler(service))
        guard !Task.isCancelled else { return }
        // Mantém o progresso visível por um instante para a animação fechar bonita.
        if case .running(let s, let p) = self.phase { self.phase = .running(service: s, progress: ImportProgress(phase: p.phase, done: max(p.total, p.done), total: max(p.total, p.done))) }
        try? await Task.sleep(for: .milliseconds(450))
        self.importedTracks += summary.totalTracks
        self.importedPlaylists += summary.items.count
        SoundFX.shared.play(.success)
        Haptics.success()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { self.phase = .done(summary) }
      } catch {
        guard !Task.isCancelled else { return }
        SoundFX.shared.play(.error)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { self.phase = .failed(error.localizedDescription) }
      }
    }
  }

  private func commit(_ results: [ImportService.ImportResult], service: String) -> ImportSummary {
    var items: [ImportSummary.Item] = []
    for r in results {
      let pl = store.createPlaylist(name: r.playlistName, sourceBadge: r.sourceBadge, artworkURL: r.artworkURL, tracks: r.tracks)
      items.append(.init(name: r.playlistName, count: r.tracks.count, artworkURL: pl.artworkURL))
    }
    return ImportSummary(service: service, items: items)
  }
}

// MARK: - Painel (grade de serviços + progresso + resultado)

struct ImportHubPanel: View {
  @ObservedObject var coordinator: ImportCoordinator
  var compact = false
  /// Abre a folha do serviço automaticamente (depuração).
  var initialService: ImportServiceKind? = nil

  @State private var sheetService: ImportServiceKind?
  @State private var pickingFile = false
  @Namespace private var ns

  var body: some View {
    VStack(spacing: 14) {
      switch coordinator.phase {
      case .idle:
        grid.transition(.opacity.combined(with: .scale(scale: 0.97)))
      case .running(let service, let p):
        ImportProgressCard(service: service, progress: p) { coordinator.cancel() }
          .transition(.opacity.combined(with: .scale(scale: 0.97)))
      case .done(let summary):
        ImportDoneCard(summary: summary) { coordinator.reset() }
          .transition(.opacity.combined(with: .scale(scale: 0.97)))
      case .failed(let msg):
        ImportFailedCard(message: msg) { coordinator.reset() }
          .transition(.opacity.combined(with: .scale(scale: 0.97)))
      }
    }
    .animation(.spring(response: 0.45, dampingFraction: 0.86), value: coordinator.phase)
    .sheet(item: $sheetService) { kind in
      ServiceLinkSheet(kind: kind) { link in
        sheetService = nil
        coordinator.runLink(link)
      }
    }
    .fileImporter(isPresented: $pickingFile, allowedContentTypes: Self.fileTypes) { result in
      if case .success(let url) = result { coordinator.runFile(url: url) }
    }
    .onAppear {
      if let s = initialService, sheetService == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { sheetService = s } }
    }
  }

  private static var fileTypes: [UTType] {
    [UTType.commaSeparatedText, .plainText, .text, UTType(filenameExtension: "m3u"), UTType(filenameExtension: "m3u8"), UTType(filenameExtension: "csv")].compactMap { $0 }
  }

  private func tap(_ kind: ImportServiceKind) {
    Haptics.light()
    SoundFX.shared.play(.tap)
    switch kind {
    case .appleMusic: coordinator.runApple()
    case .file: pickingFile = true
    default: sheetService = kind
    }
  }

  private var grid: some View {
    VStack(spacing: 10) {
      // Apple Music em destaque: é o único 100% em 1 toque.
      Button { tap(.appleMusic) } label: { appleTile }
        .buttonStyle(PressableStyle(scale: 0.98))

      LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
        ForEach(ImportServiceKind.allCases.filter { $0 != .appleMusic }) { kind in
          Button { tap(kind) } label: { tile(kind) }
            .buttonStyle(PressableStyle(scale: 0.96))
        }
      }
    }
  }

  private func icon(_ kind: ImportServiceKind, size: CGFloat) -> some View {
    Image(systemName: kind.symbol)
      .font(.system(size: size * 0.44, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(Circle().fill(LinearGradient(colors: kind.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
      .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.8))
      .shadow(color: kind.colors.last!.opacity(0.35), radius: 8, y: 3)
  }

  private var appleTile: some View {
    HStack(spacing: 14) {
      icon(.appleMusic, size: 48)
      VStack(alignment: .leading, spacing: 3) {
        Text("Importar do Apple Music")
          .font(Theme.font(17, .semibold)).foregroundStyle(Theme.text)
        Text("Traz suas playlists e músicas deste iPhone com 1 toque")
          .font(Theme.font(13)).foregroundStyle(Theme.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.leading)
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.tertiary)
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 76)
    .glass(22, tint: Color(hex: 0xFA2D48).opacity(0.18), interactive: true)
    .contentShape(Rectangle())
  }

  private func tile(_ kind: ImportServiceKind) -> some View {
    HStack(spacing: 10) {
      icon(kind, size: 38)
      VStack(alignment: .leading, spacing: 2) {
        Text(kind.title).font(Theme.font(15, .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
        Text(kind.tagline).font(Theme.font(11.5)).foregroundStyle(Theme.secondary).lineLimit(2).multilineTextAlignment(.leading)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 64)
    .glass(20, interactive: true)
    .contentShape(Rectangle())
  }
}

// MARK: - Progresso

struct ImportProgressCard: View {
  let service: String
  let progress: ImportProgress
  let onCancel: () -> Void

  @State private var spin = false

  var body: some View {
    VStack(spacing: 18) {
      ZStack {
        Circle().stroke(Theme.fillStrong, lineWidth: 7)
        if let f = progress.fraction {
          Circle()
            .trim(from: 0, to: f)
            .stroke(Theme.prismAngular, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.easeOut(duration: 0.35), value: f)
        } else {
          Circle()
            .trim(from: 0, to: 0.28)
            .stroke(Theme.prismAngular, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(Theme.motion ? .linear(duration: 1.1).repeatForever(autoreverses: false) : nil, value: spin)
        }
        PrismMark(size: 54)
          .rotationEffect(.degrees(spin ? 360 : 0))
          .animation(Theme.motion ? .linear(duration: 6).repeatForever(autoreverses: false) : nil, value: spin)
      }
      .frame(width: 112, height: 112)

      VStack(spacing: 5) {
        Text(headline)
          .font(Theme.font(18, .semibold)).foregroundStyle(Theme.text)
          .contentTransition(.numericText())
          .animation(.snappy, value: progress.done)
        Text(progress.phase)
          .font(Theme.font(13.5)).foregroundStyle(Theme.secondary)
          .lineLimit(1)
      }

      Button(action: onCancel) {
        Text("Cancelar").font(Theme.font(14, .medium)).foregroundStyle(Theme.secondary)
          .frame(minWidth: 88, minHeight: 44)
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity)
    .glass(28)
    .onAppear { spin = true }
  }

  private var headline: String {
    if progress.total > 0 { return "Importando \(progress.done) de \(progress.total)…" }
    return "Importando de \(service)…"
  }
}

// MARK: - Resultado

struct ImportDoneCard: View {
  let summary: ImportSummary
  let onMore: () -> Void
  @State private var appear = false

  var body: some View {
    VStack(spacing: 16) {
      ZStack {
        Circle().fill(Color.clear).frame(width: 72, height: 72).glassCircle(tint: Theme.mint.opacity(0.4))
        Image(systemName: "checkmark")
          .font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
          .scaleEffect(appear ? 1 : 0.3)
      }
      VStack(spacing: 4) {
        Text("Pronto! \(summary.totalTracks) música\(summary.totalTracks == 1 ? "" : "s") importada\(summary.totalTracks == 1 ? "" : "s")")
          .font(Theme.font(18, .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
        Text("\(summary.items.count) playlist\(summary.items.count == 1 ? "" : "s") do \(summary.service) já estão na sua biblioteca")
          .font(Theme.font(13.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
      }
      VStack(spacing: 8) {
        ForEach(summary.items.prefix(4)) { item in
          HStack(spacing: 12) {
            ArtworkImage(url: item.artworkURL, cornerRadius: 8, maxPixel: 120, placeholderIcon: "music.note.list")
              .frame(width: 40, height: 40)
            Text(item.name).font(Theme.font(14.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer(minLength: 0)
            Text("\(item.count)").font(Theme.font(13.5, .semibold)).foregroundStyle(Theme.secondary)
          }
        }
        if summary.items.count > 4 {
          Text("+ \(summary.items.count - 4) playlists").font(Theme.font(12.5)).foregroundStyle(Theme.tertiary)
        }
      }
      GlassButton(title: "Importar de outro lugar", systemImage: "plus", height: 46, action: onMore)
    }
    .padding(20)
    .frame(maxWidth: .infinity)
    .glass(28)
    .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appear = true } }
  }
}

struct ImportFailedCard: View {
  let message: String
  let onRetry: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.peach)
      Text(message)
        .font(Theme.font(14.5, .medium)).foregroundStyle(Theme.text)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      GlassButton(title: "Tentar de outro jeito", systemImage: "arrow.counterclockwise", height: 46, action: onRetry)
    }
    .padding(20)
    .frame(maxWidth: .infinity)
    .glass(28, tint: Theme.danger.opacity(0.25))
  }
}

// MARK: - Folha de um serviço (abrir app + colar link)

struct ServiceLinkSheet: View {
  let kind: ImportServiceKind
  let onLink: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var manual = ""
  @State private var clipboardHasURL = false
  @State private var opened = false

  var body: some View {
    ZStack {
      Theme.canvas.ignoresSafeArea()
      ScrollView(showsIndicators: false) {
        VStack(spacing: 20) {
          VStack(spacing: 10) {
            Image(systemName: kind.symbol)
              .font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
              .frame(width: 72, height: 72)
              .background(Circle().fill(LinearGradient(colors: kind.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
              .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
              .shadow(color: kind.colors.last!.opacity(0.4), radius: 14, y: 6)
            Text("Importar do \(kind.title)")
              .font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
          }
          .padding(.top, 28)

          VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(kind.howTo.enumerated()), id: \.offset) { i, line in
              HStack(alignment: .top, spacing: 12) {
                Text("\(i + 1)")
                  .font(Theme.font(13, .bold)).foregroundStyle(Theme.onPrism)
                  .frame(width: 24, height: 24)
                  .background(Circle().fill(Theme.prismDiagonal))
                Text(line).font(Theme.font(14.5)).foregroundStyle(Theme.text)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          .padding(18)
          .frame(maxWidth: .infinity, alignment: .leading)
          .glass(22)

          if let url = kind.openURL {
            GlassButton(title: "Abrir \(kind.title)", systemImage: "arrow.up.right.square", height: 50) {
              opened = true
              openURL(url)
            }
          }

          if clipboardHasURL {
            VStack(spacing: 10) {
              Label("Você copiou um link. É o da playlist?", systemImage: "link.badge.plus")
                .font(Theme.font(14, .medium)).foregroundStyle(Theme.text)
              pasteButton
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .glass(22, tint: Theme.lavender.opacity(0.3))
            .transition(.scale(scale: 0.96).combined(with: .opacity))
          } else {
            pasteButton
          }

          VStack(spacing: 10) {
            HStack(spacing: 8) {
              Image(systemName: "link").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondary)
              TextField("…ou escreva/cole o link aqui", text: $manual)
                .font(Theme.font(15)).foregroundStyle(Theme.text)
                .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit { send(manual) }
            }
            .padding(.horizontal, 16).frame(height: 48).glassCapsule()
            if !manual.trimmingCharacters(in: .whitespaces).isEmpty {
              PrismButton(title: "Importar do link", systemImage: "arrow.down.circle", height: 48) { send(manual) }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
          }
          .animation(.spring(response: 0.35, dampingFraction: 0.85), value: manual.isEmpty)

          Text("Seus dados não saem do iPhone. O Lume só lê a playlist pública.")
            .font(Theme.font(12)).foregroundStyle(Theme.tertiary).padding(.bottom, 24)
        }
        .padding(.horizontal, 22)
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .onAppear(perform: detectClipboard)
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in detectClipboard() }
  }

  /// Botão de colar do sistema: não dispara o aviso de "colou de outro app".
  private var pasteButton: some View {
    PasteButton(payloadType: String.self) { strings in
      guard let s = strings.first else { return }
      Task { @MainActor in send(s) }
    }
    .labelStyle(.titleAndIcon)
    .buttonBorderShape(.capsule)
    .tint(Theme.rose)
    .frame(maxWidth: .infinity, minHeight: 50)
  }

  private func send(_ text: String) {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    onLink(t)
  }

  /// `detectPatterns` não lê o conteúdo (e não mostra o aviso de colagem): só diz se parece um link.
  private func detectClipboard() {
    UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
      let found: Bool
      if case .success(let patterns) = result { found = patterns.contains(.probableWebURL) } else { found = false }
      DispatchQueue.main.async {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { clipboardHasURL = found }
      }
    }
  }
}
