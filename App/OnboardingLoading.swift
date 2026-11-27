import SwiftUI

// MARK: - Pré-carregamento real

/// Pré-carrega de verdade o que a Home usa (feed de descoberta + vitrines dos gêneros escolhidos + capas) enquanto a animação roda.
@MainActor
final class LoadingMusicModel: ObservableObject {
  @Published private(set) var covers: [String] = []
  @Published private(set) var doneTasks = 0
  private(set) var totalTasks = 1

  var taskFraction: Double { totalTasks > 0 ? Double(doneTasks) / Double(totalTasks) : 1 }
  private var started = false

  func start(genres: [MusicGenre]) {
    guard !started else { return }
    started = true
    let hubGenres = Array(genres.prefix(3))
    // feed + 1 vitrine por gênero (até 3) + decodificação das capas
    totalTasks = 2 + hubGenres.count

    var genreAlbums: [[String]] = Array(repeating: [], count: hubGenres.count)

    Task {
      await AppModel.shared.loadFeed()
      doneTasks += 1
    }

    Task {
      await withTaskGroup(of: (Int, [String]).self) { group in
        for (i, g) in hubGenres.enumerated() {
          group.addTask {
            let bundle = await CatalogExplorerService.shared.genreHub(for: g)
            return (i, bundle.topAlbums.map(\.artworkURL).filter { !$0.isEmpty })
          }
        }
        for await (i, urls) in group {
          genreAlbums[i] = urls
          mergeCovers(genre: genreAlbums)
          doneTasks += 1
        }
      }
      // Sem gêneros escolhidos (ou falha): usa as capas do feed.
      await fillFromFeed()
      await decode()
      doneTasks += 1
    }
  }

  private func mergeCovers(genre lists: [[String]]) {
    var out: [String] = []
    var round = 0
    while out.count < 12, round < 12 {
      for l in lists where round < l.count && !out.contains(l[round]) && out.count < 12 { out.append(l[round]) }
      round += 1
    }
    if !out.isEmpty { covers = out }
  }

  private func fillFromFeed() async {
    guard covers.count < 12 else { return }
    // Espera o feed (até ~2 s) para completar a estante.
    for _ in 0..<10 {
      if AppModel.shared.feed != nil { break }
      try? await Task.sleep(for: .milliseconds(200))
    }
    guard let feed = AppModel.shared.feed else { return }
    var pool = feed.newReleases + feed.brazilReleases + (feed.topAlbumsBrazil ?? []) + (feed.topAlbumsGlobal ?? [])
    pool.shuffle()
    var out = covers
    for a in pool where !a.artworkURL.isEmpty && !out.contains(a.artworkURL) && out.count < 12 { out.append(a.artworkURL) }
    covers = out
  }

  private func decode() async {
    let urls = covers
    await withTaskGroup(of: Void.self) { group in
      for u in urls { group.addTask { _ = await ImagePipeline.shared.image(u, maxPixel: 300) } }
    }
  }
}

// MARK: - Tela

/// "Carregando suas músicas": disco de vidro girando, capas voando para a estante, anel de progresso prisma e frases.
/// Dura de 3,5 s (tudo carregado) até 6 s (conexão lenta).
struct LoadingMusicView: View {
  let genres: [MusicGenre]
  let onFinish: () -> Void

  @StateObject private var model = LoadingMusicModel()
  @Environment(\.scenePhase) private var scenePhase
  @State private var start = Date()
  @State private var landed: [Bool] = Array(repeating: false, count: 12)
  @State private var finished = false
  @State private var spin = false

  private let minSeconds = 3.5
  private let maxSeconds = 6.0
  private let phrases = ["Afinando seus gêneros…", "Buscando lançamentos…", "Montando sua biblioteca…", "Quase lá…"]

  private var tints: [MusicGenre] { genres.isEmpty ? [MusicGenre.all[0], MusicGenre.all[6], MusicGenre.all[1]] : genres }

  var body: some View {
    GeometryReader { geo in
      let cols = 4
      let spacing: CGFloat = 10
      let tile = min(86, (geo.size.width - 48 - spacing * CGFloat(cols - 1)) / CGFloat(cols))

      VStack(spacing: 0) {
        Spacer(minLength: 24)

        // Disco + anel de progresso
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: finished || scenePhase != .active)) { tl in
          let p = progress(at: tl.date)
          ZStack {
            Circle().stroke(Theme.fillStrong, lineWidth: 6).frame(width: 148, height: 148)
            Circle()
              .trim(from: 0, to: p)
              .stroke(Theme.prismAngular, style: StrokeStyle(lineWidth: 6, lineCap: .round))
              .rotationEffect(.degrees(-90))
              .frame(width: 148, height: 148)
            Circle().fill(Color.clear).frame(width: 128, height: 128).glassCircle(tint: Theme.lavender.opacity(0.15))
            PrismMark(size: 104)
              .drawingGroup()
              .rotationEffect(.degrees(spin ? 360 : 0))
              .animation(Theme.motion ? .linear(duration: 3.2).repeatForever(autoreverses: false) : nil, value: spin)
          }
          .onChange(of: p >= 1) { _, done in if done { complete() } }
          .onChange(of: tl.date) { _, d in checkDeadline(d) }
        }

        Text("Carregando suas músicas")
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.text)
          .padding(.top, 22)

        TimelineView(.periodic(from: start, by: 0.5)) { tl in
          let i = min(phrases.count - 1, Int(tl.date.timeIntervalSince(start) / 1.25))
          Text(phrases[max(0, i)])
            .font(Theme.font(15, .medium))
            .foregroundStyle(Theme.secondary)
            .id(i)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: i)
        }
        .frame(height: 28)
        .padding(.top, 6)
        .clipped()

        Spacer(minLength: 20)

        // Estante: capas voam e se encaixam.
        VStack(spacing: 12) {
          ForEach(0..<3, id: \.self) { row in
            VStack(spacing: 6) {
              HStack(spacing: spacing) {
                ForEach(0..<cols, id: \.self) { col in
                  let i = row * cols + col
                  CoverTile(url: i < model.covers.count ? model.covers[i] : nil, genre: tints[i % tints.count], size: tile)
                    .modifier(FlyIn(landed: landed[i], index: i, width: geo.size.width))
                }
              }
              Capsule()
                .fill(Color.clear)
                .frame(width: geo.size.width - 40, height: 5)
                .glassCapsule()
                .opacity(0.8)
            }
          }
        }
        .padding(.horizontal, 24)

        Spacer(minLength: 36)
      }
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .onAppear {
      start = Date()
      spin = true
      model.start(genres: genres)
      for i in 0..<12 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(i) * 0.17) {
          withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { landed[i] = true }
          if i % 3 == 0 { SoundFX.shared.play(.tap) }
        }
      }
    }
  }

  private func progress(at date: Date) -> Double {
    let elapsed = date.timeIntervalSince(start)
    let timeFrac = min(1, elapsed / minSeconds)
    // Não passa de 92% até as tarefas reais terminarem; no limite máximo conclui.
    let cap = model.taskFraction >= 1 ? 1.0 : 0.92
    let p = min(timeFrac, cap)
    return elapsed >= maxSeconds ? 1 : p
  }

  private func checkDeadline(_ d: Date) {
    if d.timeIntervalSince(start) >= maxSeconds { complete() }
  }

  private func complete() {
    guard !finished else { return }
    finished = true
    onFinish()
  }
}

private struct CoverTile: View {
  let url: String?
  let genre: MusicGenre
  let size: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(LinearGradient(colors: [Color(hex: genre.hexA).opacity(0.85), Color(hex: genre.hexB).opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(Image(systemName: genre.icon).font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(.white.opacity(0.7)))
      if let url {
        ArtworkImage(url: url, cornerRadius: 14, maxPixel: 300)
          .transition(.opacity)
      }
    }
    .frame(width: size, height: size)
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 0.8))
    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    .animation(.easeOut(duration: 0.4), value: url)
  }
}

/// Cada capa chega voando de um ponto diferente, girando, e se encaixa na estante.
private struct FlyIn: ViewModifier {
  let landed: Bool
  let index: Int
  let width: CGFloat

  private var start: CGSize {
    let a = Double(index) * 2.399 // ângulo áureo: espalha as origens
    return CGSize(width: CGFloat(cos(a)) * width * 0.9, height: CGFloat(sin(a)) * 420 - 120)
  }
  private var tilt: Double { Double((index * 37) % 9) - 4 }

  func body(content: Content) -> some View {
    content
      .offset(landed ? .zero : start)
      .rotationEffect(.degrees(landed ? 0 : tilt * 14))
      .scaleEffect(landed ? 1 : 0.3)
      .opacity(landed ? 1 : 0)
  }
}
