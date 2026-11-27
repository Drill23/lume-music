import Foundation
import SwiftUI

// MARK: - Destinos extras (navegação dentro das abas, sem mexer em LumeRoute)

/// Telas de "hub" criadas pela Home/Explorar. Empilhadas direto no `NavigationPath` da aba.
enum LumeHub: Hashable {
  case genres
}

// MARK: - Gêneros do onboarding

enum OnboardingGenres {
  static let defaultsKey = "lume.onboarding.genres"

  /// Gêneros escolhidos no onboarding (leitura tolerante: [String], String separada por vírgula, nomes soltos).
  static func selected() -> [MusicGenre] {
    let d = UserDefaults.standard
    var names = d.stringArray(forKey: defaultsKey) ?? []
    if names.isEmpty, let s = d.string(forKey: defaultsKey) {
      names = s.components(separatedBy: CharacterSet(charactersIn: ",;|"))
    }
    var out: [MusicGenre] = []
    for n in names {
      if let g = match(n), !out.contains(where: { $0.id == g.id }) { out.append(g) }
    }
    return out
  }

  private static let aliases: [String: String] = [
    "funk": "funk_br", "trap": "funk_br", "baile funk": "funk_br", "funk carioca": "funk_br",
    "pagode": "pagode", "samba": "pagode", "mpb": "mpb", "bossa": "mpb", "bossa nova": "mpb",
    "forro": "forro", "piseiro": "forro", "arrocha": "forro",
    "gospel": "gospel", "louvor": "gospel", "religioso": "gospel", "crista": "gospel",
    "rap": "hiphop", "hip hop": "hiphop", "hiphop": "hiphop",
    "eletronica": "eletronica", "dance": "eletronica", "edm": "eletronica", "house": "eletronica",
    "r e b": "rnb", "rnb": "rnb", "soul": "rnb",
    "latina": "latina", "latino": "latina", "reggaeton": "latina", "musica latina": "latina",
    "k pop": "kpop", "kpop": "kpop", "classica": "classica", "erudita": "classica",
    "trilhas": "soundtrack", "trilha sonora": "soundtrack", "games": "soundtrack",
    "alternativo": "indie", "indie": "indie", "pop": "pop", "rock": "rock", "metal": "metal",
    "jazz": "jazz", "reggae": "reggae", "country": "country", "sertanejo": "sertanejo", "sertaneja": "sertanejo",
  ]

  static func match(_ name: String) -> MusicGenre? {
    let key = DiscText.normalize(name)
    guard !key.isEmpty else { return nil }
    if let id = aliases[key], let g = MusicGenre.all.first(where: { $0.id == id }) { return g }
    if let g = MusicGenre.all.first(where: { $0.id == key || DiscText.normalize($0.title) == key }) { return g }
    return MusicGenre.all.first { g in
      let t = DiscText.normalize(g.title)
      return t.contains(key) || (key.count > 3 && key.contains(t))
    }
  }
}

// MARK: - Estado da Home

/// Dono dos dados da Home. Mostra o cache em disco NA HORA e atualiza em segundo plano (stale-while-revalidate);
/// tudo em paralelo, sem bloquear a main thread (as leituras de disco/rede acontecem nos atores).
@MainActor
final class HomeStore: ObservableObject {
  static let shared = HomeStore()

  @Published private(set) var feed: DiscoverFeed?
  @Published private(set) var lists: [String: ChartList] = [:]
  @Published private(set) var loadingPlaces: Set<String> = []
  @Published private(set) var genreMixes: [PersonalizedMix] = []
  @Published private(set) var settled = false          // primeira rodada de carga terminou (com ou sem dados)
  @Published var place: ChartPlace

  /// País do usuário (Locale) — usado na vitrine e como padrão do Top 10.
  let homePlace: ChartPlace
  private static let placeKey = "lume.home.chartPlace"
  private var started = false
  private var observer: NSObjectProtocol?

  private init() {
    let home = ChartPlace.userPlace
    homePlace = home
    place = ChartPlace.place(id: UserDefaults.standard.string(forKey: Self.placeKey)) ?? home
    observer = NotificationCenter.default.addObserver(forName: DiscoveryService.feedUpdated, object: nil, queue: .main) { [weak self] note in
      guard let f = note.userInfo?["feed"] as? DiscoverFeed else { return }
      MainActor.assumeIsolated {
        self?.feed = f
        AppModel.shared.feed = f
      }
    }
  }

  var current: ChartList? { lists[place.id] }
  var homeList: ChartList? { lists[homePlace.id] }
  var isLoadingCurrent: Bool { loadingPlaces.contains(place.id) }

  // MARK: Início

  func start() {
    guard !started else { return }
    started = true
    Task { await bootstrap() }
  }

  private func bootstrap() async {
    // 1) Cache instantâneo (disco → memória), tudo em paralelo.
    async let cachedFeed = DiscoveryService.shared.cachedFeed()
    async let cachedPlace = ChartsService.shared.cached(place)
    async let cachedHome = ChartsService.shared.cached(homePlace)
    let (f, p, h) = await (cachedFeed, cachedPlace, cachedHome)
    if feed == nil, let f { feed = f }
    if let p { lists[place.id] = p }
    if let h { lists[homePlace.id] = h }
    reloadGenreMixesFromCache()

    // 2) Revalidação em segundo plano: paradas do país do usuário + selecionado + feed + mixes.
    async let a: Void = revalidate(homePlace)
    async let b: Void = place.id == homePlace.id ? () : revalidate(place)
    async let c: Void = refreshFeedIfNeeded()
    async let d: Void = refreshGenreMixes()
    _ = await (a, b, c, d)
    settled = true

    // 3) Pré-carrega as paradas mais prováveis do seletor, sem pressa.
    let next = ChartPlace.all.filter { $0.id != place.id && $0.id != homePlace.id }.prefix(5)
    await ChartsService.shared.prefetch(Array(next))
  }

  func refresh() async {
    async let a: Void = revalidate(homePlace, force: true)
    async let b: Void = place.id == homePlace.id ? () : revalidate(place, force: true)
    async let c: DiscoverFeed = DiscoveryService.shared.refresh()
    async let d: Void = refreshGenreMixes(force: true)
    let (_, _, nf, _) = await (a, b, c, d)
    feed = nf
    AppModel.shared.feed = nf
  }

  // MARK: Paradas

  func select(_ p: ChartPlace) {
    guard p.id != place.id else { return }
    place = p
    UserDefaults.standard.set(p.id, forKey: Self.placeKey)
    Task {
      if lists[p.id] == nil, let c = await ChartsService.shared.cached(p) { lists[p.id] = c }
      await revalidate(p)
      // Vizinhos no seletor ficam prontos para a próxima troca.
      if let i = ChartPlace.all.firstIndex(of: p) {
        let near = [i - 1, i + 1, i + 2].filter { ChartPlace.all.indices.contains($0) }.map { ChartPlace.all[$0] }
        await ChartsService.shared.prefetch(near)
        for n in near { if lists[n.id] == nil, let c = await ChartsService.shared.cached(n) { lists[n.id] = c } }
      }
    }
  }

  private func revalidate(_ p: ChartPlace, force: Bool = false) async {
    loadingPlaces.insert(p.id)
    let fresh = await ChartsService.shared.load(p, force: force)
    if let fresh { lists[p.id] = fresh }
    loadingPlaces.remove(p.id)
  }

  private func refreshFeedIfNeeded() async {
    if let f = feed, Date().timeIntervalSince(f.updatedAt) < 20 * 60 { return }
    feed = await DiscoveryService.shared.refresh()
  }

  // MARK: "Para você" por gênero

  nonisolated static func mix(for g: MusicGenre, tracks: [Track]) -> PersonalizedMix {
    PersonalizedMix(
      id: "genre_\(g.id)", title: g.title, subtitle: g.subtitle, tag: "PARA VOCÊ", icon: g.icon,
      hexA: g.hexA, hexB: g.hexB, tracks: Array(tracks.prefix(30)))
  }

  /// Gêneros do onboarding; se não houver, os dois estilos mais populares da região do usuário.
  private func preferredGenres() -> [MusicGenre] {
    let chosen = OnboardingGenres.selected()
    if !chosen.isEmpty { return Array(chosen.prefix(4)) }
    // Sem escolha e sem histórico: sugere estilos populares da região para a Home nunca ficar vazia.
    guard LibraryStore.shared.recentTracks.isEmpty else { return [] }
    let ids = homePlace.id == "br" ? ["sertanejo", "pop", "funk_br"] : ["pop", "hiphop", "rock"]
    return ids.compactMap { id in MusicGenre.all.first { $0.id == id } }
  }

  private func reloadGenreMixesFromCache() {
    let genres = preferredGenres()
    guard !genres.isEmpty else { return }
    Task {
      var out: [PersonalizedMix] = []
      for g in genres {
        if let t = await ChartsService.shared.cachedGenreSongs(g) { out.append(Self.mix(for: g, tracks: t)) }
      }
      if genreMixes.isEmpty, !out.isEmpty { genreMixes = out }
    }
  }

  func refreshGenreMixes(force: Bool = false) async {
    let genres = preferredGenres()
    guard !genres.isEmpty else { genreMixes = []; return }
    let results: [(Int, PersonalizedMix?)] = await withTaskGroup(of: (Int, PersonalizedMix?).self) { group in
      for (i, g) in genres.enumerated() {
        group.addTask {
          let t = await ChartsService.shared.genreSongs(g, force: force)
          return (i, t.isEmpty ? nil : HomeStore.mix(for: g, tracks: t))
        }
      }
      var out: [(Int, PersonalizedMix?)] = []
      for await r in group { out.append(r) }
      return out
    }
    let mixes = results.sorted { $0.0 < $1.0 }.compactMap(\.1)
    if !mixes.isEmpty { genreMixes = mixes }
  }
}
