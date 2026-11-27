import Foundation

// MARK: - Lugares (países + Global) das paradas

/// Um "lugar" de parada: um país (loja da Apple Music + playlist oficial "Deezer Charts" do país) ou o Global.
/// Fontes auditadas em 26/11/2026:
///  - País: Apple Marketing Tools RSS (`most-played`, storefront do país) · reserva: playlist "Top <país>" do Deezer Charts.
///  - Global: playlist "Top Worldwide" do Deezer Charts (a Apple não tem parada global).
struct ChartPlace: Identifiable, Hashable {
  let id: String            // "br", "us", … ou "world"
  let name: String
  let flag: String
  let apple: String?        // storefront da Apple Music
  let deezerPlaylist: Int?  // playlist oficial "Deezer Charts" do país
  let ytm: String           // código do YouTube Music Charts
  let region: String
  let hexA: UInt32
  let hexB: UInt32

  var isGlobal: Bool { id == "world" }
  var title: String { isGlobal ? "Top 10 Global" : "Top 10 \(name)" }

  /// Versão compatível com a rota `.country(...)`.
  var chartCountry: ChartCountry {
    ChartCountry(code: id, ytmCode: ytm, name: name, flag: flag, region: region, hexA: hexA, hexB: hexB)
  }

  static let world = ChartPlace(id: "world", name: "Global", flag: "🌎", apple: nil, deezerPlaylist: 3155776842,
                                ytm: "ZZ", region: "Mundo", hexA: 0x06B6D4, hexB: 0x3B82F6)

  /// Ordem do seletor: Brasil, Global, depois os mais pedidos.
  static let all: [ChartPlace] = [
    ChartPlace(id: "br", name: "Brasil", flag: "🇧🇷", apple: "br", deezerPlaylist: 1111141961, ytm: "BR", region: "América do Sul", hexA: 0x10B981, hexB: 0x047857),
    .world,
    ChartPlace(id: "us", name: "Estados Unidos", flag: "🇺🇸", apple: "us", deezerPlaylist: 1313621735, ytm: "US", region: "América do Norte", hexA: 0x3B82F6, hexB: 0x1D4ED8),
    ChartPlace(id: "gb", name: "Reino Unido", flag: "🇬🇧", apple: "gb", deezerPlaylist: 1111142221, ytm: "GB", region: "Europa", hexA: 0x6366F1, hexB: 0xBE123C),
    ChartPlace(id: "mx", name: "México", flag: "🇲🇽", apple: "mx", deezerPlaylist: 1111142361, ytm: "MX", region: "América Latina", hexA: 0x16A34A, hexB: 0xDC2626),
    ChartPlace(id: "pt", name: "Portugal", flag: "🇵🇹", apple: "pt", deezerPlaylist: 1362519755, ytm: "PT", region: "Europa", hexA: 0xEF4444, hexB: 0x059669),
    ChartPlace(id: "ar", name: "Argentina", flag: "🇦🇷", apple: "ar", deezerPlaylist: 1279119721, ytm: "AR", region: "América do Sul", hexA: 0x38BDF8, hexB: 0x0284C7),
    ChartPlace(id: "es", name: "Espanha", flag: "🇪🇸", apple: "es", deezerPlaylist: 1116190041, ytm: "ES", region: "Europa", hexA: 0xEA580C, hexB: 0xB91C1C),
    ChartPlace(id: "fr", name: "França", flag: "🇫🇷", apple: "fr", deezerPlaylist: 1109890291, ytm: "FR", region: "Europa", hexA: 0x2563EB, hexB: 0xE11D48),
    ChartPlace(id: "de", name: "Alemanha", flag: "🇩🇪", apple: "de", deezerPlaylist: 1111143121, ytm: "DE", region: "Europa", hexA: 0xF59E0B, hexB: 0x374151),
    ChartPlace(id: "it", name: "Itália", flag: "🇮🇹", apple: "it", deezerPlaylist: 1116187241, ytm: "IT", region: "Europa", hexA: 0x10B981, hexB: 0xDC2626),
    ChartPlace(id: "jp", name: "Japão", flag: "🇯🇵", apple: "jp", deezerPlaylist: nil, ytm: "JP", region: "Ásia", hexA: 0xF43F5E, hexB: 0x9F1239),
    ChartPlace(id: "kr", name: "Coreia do Sul", flag: "🇰🇷", apple: "kr", deezerPlaylist: 1362510315, ytm: "KR", region: "Ásia", hexA: 0xEC4899, hexB: 0x4F46E5),
    ChartPlace(id: "ca", name: "Canadá", flag: "🇨🇦", apple: "ca", deezerPlaylist: 1652248171, ytm: "CA", region: "América do Norte", hexA: 0xEF4444, hexB: 0x991B1B),
    ChartPlace(id: "co", name: "Colômbia", flag: "🇨🇴", apple: "co", deezerPlaylist: 1116188451, ytm: "CO", region: "América do Sul", hexA: 0xF59E0B, hexB: 0x1D4ED8),
    ChartPlace(id: "cl", name: "Chile", flag: "🇨🇱", apple: "cl", deezerPlaylist: 1279119121, ytm: "CL", region: "América do Sul", hexA: 0xDC2626, hexB: 0x1E40AF),
    ChartPlace(id: "ng", name: "Nigéria", flag: "🇳🇬", apple: "ng", deezerPlaylist: 1362516565, ytm: "NG", region: "África", hexA: 0x059669, hexB: 0x065F46),
    ChartPlace(id: "in", name: "Índia", flag: "🇮🇳", apple: "in", deezerPlaylist: nil, ytm: "IN", region: "Ásia", hexA: 0xF97316, hexB: 0x0F766E),
    ChartPlace(id: "au", name: "Austrália", flag: "🇦🇺", apple: "au", deezerPlaylist: 1313616925, ytm: "AU", region: "Oceania", hexA: 0x06B6D4, hexB: 0x1E3A8A),
    ChartPlace(id: "se", name: "Suécia", flag: "🇸🇪", apple: "se", deezerPlaylist: 1313620305, ytm: "SE", region: "Europa", hexA: 0x0EA5E9, hexB: 0xCA8A04),
  ]

  static func place(id: String?) -> ChartPlace? {
    guard let id else { return nil }
    return all.first { $0.id == id }
  }

  /// País do usuário pelo Locale (cai no Brasil se não houver parada para a região).
  static var userPlace: ChartPlace {
    let region = Locale.current.region?.identifier.lowercased()
    return place(id: region) ?? all[0]
  }
}

// MARK: - Lista de parada (cacheável)

struct ChartList: Codable {
  var placeId: String
  var songs: [Track]
  var albums: [AlbumShowcase]
  var source: String          // "Apple Music" | "Deezer Charts"
  var updatedAt: Date

  var isFresh: Bool { Date().timeIntervalSince(updatedAt) < ChartsService.freshFor }
}

// MARK: - Parsers compartilhados

enum ChartParsers {
  static func int(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let s = v as? String { return Int(s) }
    if let d = v as? Double { return Int(d) }
    return nil
  }

  static func upscaleApple(_ url: String, size: Int = 600) -> String {
    var u = url
    if let r = u.range(of: #"\d{2,4}x\d{2,4}(bb|cc)"#, options: .regularExpression) {
      u.replaceSubrange(r, with: "\(size)x\(size)bb")
    }
    return u
  }

  static func appleSongs(_ results: [[String: Any]], label: String) -> [Track] {
    results.compactMap { r in
      guard let title = r["name"] as? String else { return nil }
      return Track(
        title: title, artist: (r["artistName"] as? String) ?? "",
        artworkURL: upscaleApple((r["artworkUrl100"] as? String) ?? ""),
        sourceService: label,
        isExplicit: ((r["contentAdvisoryRating"] as? String) ?? "").lowercased().hasPrefix("explic"))
    }
  }

  static func appleAlbums(_ results: [[String: Any]], size: Int = 800) -> [AlbumShowcase] {
    results.compactMap { r in
      guard let idStr = r["id"] as? String, var title = r["name"] as? String else { return nil }
      var kind = "Álbum"
      for (suffix, k) in [(" - Single", "Single"), (" - EP", "EP")] where title.hasSuffix(suffix) {
        title = String(title.dropLast(suffix.count))
        kind = k
      }
      let date = r["releaseDate"] as? String
      let genre = ((r["genres"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        .first { $0 != "Música" && $0 != "Music" } ?? ""
      return AlbumShowcase(
        id: "alb_\(idStr)", title: title, artist: (r["artistName"] as? String) ?? "",
        artworkURL: upscaleApple((r["artworkUrl100"] as? String) ?? "", size: size),
        year: DiscText.year(from: date), genre: genre, tracks: [],
        releaseDate: date, kind: kind, deezerId: nil, itunesId: Int(idStr))
    }
  }

  struct DeezerPlaylistData {
    var tracks: [Track] = []
    var artists: [ArtistInfo] = []     // ranqueados por presença/posição na parada
    var albums: [AlbumShowcase] = []   // álbuns únicos das faixas, na ordem da parada
  }

  /// Faixas + artistas (com foto) + álbuns (com id do Deezer) de uma playlist do Deezer, sem chamadas extras.
  static func deezerPlaylist(_ data: [[String: Any]], label: String = "Deezer") -> DeezerPlaylistData {
    var out = DeezerPlaylistData()
    var score: [Int: (info: ArtistInfo, score: Int, first: Int)] = [:]
    var seenAlbums = Set<Int>()
    let n = data.count
    for (i, d) in data.enumerated() {
      guard let title = d["title"] as? String, !title.isEmpty else { continue }
      let art = d["artist"] as? [String: Any]
      let album = d["album"] as? [String: Any]
      let artistName = (art?["name"] as? String) ?? ""
      var cover = (album?["cover_big"] as? String) ?? (album?["cover_xl"] as? String) ?? ""
      if cover.contains("/cover//") { cover = "" }
      out.tracks.append(Track(
        title: title, artist: artistName, album: (album?["title"] as? String) ?? "",
        duration: Double(int(d["duration"]) ?? 0), artworkURL: cover, sourceService: label,
        isExplicit: (d["explicit_lyrics"] as? Bool) ?? false))

      if let aid = int(art?["id"]), !artistName.isEmpty {
        var pic = (art?["picture_xl"] as? String) ?? (art?["picture_big"] as? String) ?? ""
        if pic.contains("/images/artist//") { pic = "" }
        let pts = max(1, n - i)
        if var cur = score[aid] { cur.score += pts; score[aid] = cur } else {
          score[aid] = (ArtistInfo(id: "dz_\(aid)", name: artistName, pictureURL: pic, deezerId: aid, fans: nil, rank: nil), pts, i)
        }
      }
      if let alid = int(album?["id"]), !cover.isEmpty, seenAlbums.insert(alid).inserted,
         let at = album?["title"] as? String {
        out.albums.append(AlbumShowcase(
          id: "dzalb_\(alid)", title: at, artist: artistName, artworkURL: (album?["cover_xl"] as? String) ?? cover,
          year: "", genre: "", tracks: [], releaseDate: nil, kind: "Álbum", deezerId: alid, itunesId: nil))
      }
    }
    out.artists = score.values
      .sorted { $0.score != $1.score ? $0.score > $1.score : $0.first < $1.first }
      .enumerated().map { idx, v in
        var a = v.info
        a.rank = idx + 1
        return a
      }
    return out
  }

  static func deezerPlaylistTracks(_ id: Int, limit: Int = 50, timeout: TimeInterval = 5) async -> DeezerPlaylistData? {
    guard let obj = await DiscNet.json("https://api.deezer.com/playlist/\(id)/tracks?limit=\(limit)", timeout: timeout, retries: 1) as? [String: Any],
          let data = obj["data"] as? [[String: Any]], !data.isEmpty else { return nil }
    return deezerPlaylist(data)
  }

  static func appleChart(_ cc: String, kind: String, limit: Int) async -> [[String: Any]] {
    guard let obj = await DiscNet.json("https://rss.marketingtools.apple.com/api/v2/\(cc)/music/most-played/\(limit)/\(kind).json",
                                       timeout: 4.5, retries: 1) as? [String: Any],
          let results = (obj["feed"] as? [String: Any])?["results"] as? [[String: Any]] else { return [] }
    return results
  }
}

// MARK: - Fontes por gênero (auditadas)

/// O app antigo usava o id Apple 1122 ("Brasileira", pai de todos) para Sertanejo e Hip-Hop para o Funk BR,
/// o que misturava MPB/rock nacional no "Sertanejo" e rap no "Funk". Estes são os ids reais dos subgêneros.
enum GenreSources {
  static func sources(for g: MusicGenre) -> [(country: String, id: Int)] {
    switch g.id {
    case "sertanejo": return [("br", 1228)]
    case "funk_br": return [("br", 1229), ("br", 18)]       // Baile Funk + Hip-Hop/Rap nacional (trap)
    case "pagode": return [("br", 1226), ("br", 1227)]      // Pagode + Samba
    case "mpb": return [("br", 1225), ("br", 1221)]         // MPB + Bossa Nova
    case "forro": return [("br", 1223)]
    case "kpop": return [("us", 51)]                        // a loja kr não publica o gênero 51
    default:
      if let id = g.appleGenreId { return [(g.appleCountry, id)] }
      return []
    }
  }

  static func songs(for g: MusicGenre, limit: Int = 30) async -> [Track] {
    let src = sources(for: g)
    let lists: [[Track]] = await withTaskGroup(of: (Int, [Track]).self) { group in
      for (i, s) in src.enumerated() {
        group.addTask { (i, await fetchSongs(country: s.country, genreId: s.id, limit: limit, label: g.title)) }
      }
      var out: [(Int, [Track])] = []
      for await r in group { out.append(r) }
      return out.sorted { $0.0 < $1.0 }.map(\.1)
    }
    return interleave(lists, limit: limit)
  }

  static func albums(for g: MusicGenre, limit: Int = 16) async -> [AlbumShowcase] {
    let src = sources(for: g)
    let lists: [[AlbumShowcase]] = await withTaskGroup(of: (Int, [AlbumShowcase]).self) { group in
      for (i, s) in src.enumerated() {
        group.addTask { (i, await fetchAlbums(country: s.country, genreId: s.id, limit: limit, genreTitle: g.title)) }
      }
      var out: [(Int, [AlbumShowcase])] = []
      for await r in group { out.append(r) }
      return out.sorted { $0.0 < $1.0 }.map(\.1)
    }
    return interleave(lists, limit: limit)
  }

  private static func interleave<T: Identifiable>(_ lists: [[T]], limit: Int) -> [T] {
    var out: [T] = []
    var seen = Set<T.ID>()
    var idx = 0
    while out.count < limit {
      var added = false
      for l in lists where idx < l.count {
        if seen.insert(l[idx].id).inserted { out.append(l[idx]); added = true }
        if out.count >= limit { break }
      }
      if !added && lists.allSatisfy({ idx >= $0.count }) { break }
      idx += 1
    }
    return out
  }

  private static func fetchSongs(country: String, genreId: Int, limit: Int, label: String) async -> [Track] {
    guard let obj = await DiscNet.json("https://itunes.apple.com/\(country)/rss/topsongs/limit=\(limit)/genre=\(genreId)/json", timeout: 6, retries: 1) as? [String: Any],
          let entries = (obj["feed"] as? [String: Any])?["entry"] as? [[String: Any]] else { return [] }
    return entries.compactMap { e in
      guard let title = (e["im:name"] as? [String: Any])?["label"] as? String,
            let artist = (e["im:artist"] as? [String: Any])?["label"] as? String else { return nil }
      let imgs = (e["im:image"] as? [[String: Any]]) ?? []
      let art = ChartParsers.upscaleApple((imgs.last?["label"] as? String) ?? "", size: 600)
      let album = ((e["im:collection"] as? [String: Any])?["im:name"] as? [String: Any])?["label"] as? String ?? ""
      return Track(title: title, artist: artist, album: album, artworkURL: art, sourceService: label)
    }
  }

  private static func fetchAlbums(country: String, genreId: Int, limit: Int, genreTitle: String) async -> [AlbumShowcase] {
    guard let obj = await DiscNet.json("https://itunes.apple.com/\(country)/rss/topalbums/limit=\(limit)/genre=\(genreId)/json", timeout: 6, retries: 1) as? [String: Any],
          let entries = (obj["feed"] as? [String: Any])?["entry"] as? [[String: Any]] else { return [] }
    return entries.compactMap { e in
      guard let title = (e["im:name"] as? [String: Any])?["label"] as? String,
            let artist = (e["im:artist"] as? [String: Any])?["label"] as? String else { return nil }
      let idAttrs = (e["id"] as? [String: Any])?["attributes"] as? [String: Any]
      let idStr = (idAttrs?["im:id"] as? String) ?? Track.stableId(title: title, artist: artist)
      let imgs = (e["im:image"] as? [[String: Any]]) ?? []
      let art = ChartParsers.upscaleApple((imgs.last?["label"] as? String) ?? "", size: 800)
      let release = ((e["im:releaseDate"] as? [String: Any])?["label"] as? String)
      return AlbumShowcase(
        id: "alb_\(idStr)", title: title, artist: artist, artworkURL: art,
        year: DiscText.year(from: release), genre: genreTitle, tracks: [],
        releaseDate: release.map { String($0.prefix(10)) }, kind: "Álbum", deezerId: nil, itunesId: Int(idStr))
    }
  }
}

// MARK: - Serviço (cache em disco + stale-while-revalidate)

/// Paradas por país/global. `cached` devolve na hora (memória/disco, qualquer idade); `load` atualiza em segundo plano
/// com requisições coalescidas (várias telas pedindo o mesmo país = 1 só chamada de rede).
actor ChartsService {
  static let shared = ChartsService()
  static let freshFor: TimeInterval = 20 * 60

  private var memory: [String: ChartList] = [:]
  private var inflight: [String: Task<ChartList?, Never>] = [:]
  private var genreMemory: [String: (tracks: [Track], at: Date)] = [:]

  private static func diskURL(_ id: String) -> URL { DiscNet.caches("lume_chart_v2_\(id).json") }
  private static func genreURL(_ id: String) -> URL { DiscNet.caches("lume_genre_songs_v2_\(id).json") }

  // MARK: Países / Global

  func cached(_ place: ChartPlace) -> ChartList? {
    if let m = memory[place.id] { return m }
    guard let data = try? Data(contentsOf: Self.diskURL(place.id)),
          let l = try? JSONDecoder().decode(ChartList.self, from: data), !l.songs.isEmpty else { return nil }
    memory[place.id] = l
    return l
  }

  /// Devolve a lista fresca (do cache se ainda válida) ou busca na rede. Em caso de falha, devolve o cache velho.
  func load(_ place: ChartPlace, force: Bool = false) async -> ChartList? {
    if !force, let c = cached(place), c.isFresh { return c }
    if let t = inflight[place.id] { return await t.value }
    let t = Task<ChartList?, Never> { await Self.fetch(place) }
    inflight[place.id] = t
    let result = await t.value
    inflight[place.id] = nil
    guard let result else { return cached(place) }
    memory[place.id] = result
    if let data = try? JSONEncoder().encode(result) { try? data.write(to: Self.diskURL(place.id), options: .atomic) }
    return result
  }

  /// Pré-carrega vários lugares em paralelo (no máximo 3 por vez) sem bloquear ninguém.
  func prefetch(_ places: [ChartPlace]) async {
    var i = 0
    while i < places.count {
      let slice = Array(places[i..<min(i + 3, places.count)])
      await withTaskGroup(of: Void.self) { group in
        for p in slice { group.addTask { _ = await self.load(p) } }
      }
      i += 3
    }
  }

  private static func fetch(_ p: ChartPlace) async -> ChartList? {
    // Rede em paralelo: Apple (músicas + álbuns) e a playlist oficial do Deezer, usada como reserva.
    async let dzTask: ChartParsers.DeezerPlaylistData? = {
      guard let id = p.deezerPlaylist else { return nil }
      return await ChartParsers.deezerPlaylistTracks(id, limit: 50)
    }()
    var appleSongs: [Track] = []
    var appleAlbums: [AlbumShowcase] = []
    if let cc = p.apple {
      async let s = ChartParsers.appleChart(cc, kind: "songs", limit: 50)
      async let a = ChartParsers.appleChart(cc, kind: "albums", limit: 25)
      let (sr, ar) = await (s, a)
      appleSongs = ChartParsers.appleSongs(sr, label: "Apple \(cc.uppercased())")
      appleAlbums = ChartParsers.appleAlbums(ar)
    }
    let dz = await dzTask

    if p.isGlobal {
      guard let dz, !dz.tracks.isEmpty else { return nil }
      return ChartList(placeId: p.id, songs: dz.tracks.map { var t = $0; t.sourceService = "Deezer Top Worldwide"; return t },
                       albums: Array(dz.albums.prefix(25)), source: "Deezer Charts · Top Worldwide", updatedAt: Date())
    }
    if !appleSongs.isEmpty {
      return ChartList(placeId: p.id, songs: appleSongs, albums: appleAlbums.isEmpty ? Array((dz?.albums ?? []).prefix(25)) : appleAlbums,
                       source: "Apple Music", updatedAt: Date())
    }
    if let dz, !dz.tracks.isEmpty {
      return ChartList(placeId: p.id, songs: dz.tracks, albums: appleAlbums.isEmpty ? Array(dz.albums.prefix(25)) : appleAlbums,
                       source: "Deezer Charts", updatedAt: Date())
    }
    return nil
  }

  // MARK: Gêneros (para "Para você")

  func cachedGenreSongs(_ g: MusicGenre) -> [Track]? {
    if let m = genreMemory[g.id] { return m.tracks }
    guard let data = try? Data(contentsOf: Self.genreURL(g.id)),
          let t = try? JSONDecoder().decode([Track].self, from: data), !t.isEmpty else { return nil }
    let at = (try? FileManager.default.attributesOfItem(atPath: Self.genreURL(g.id).path)[.modificationDate] as? Date) ?? Date.distantPast
    genreMemory[g.id] = (t, at)
    return t
  }

  func genreSongs(_ g: MusicGenre, force: Bool = false) async -> [Track] {
    if genreMemory[g.id] == nil { _ = cachedGenreSongs(g) }
    if !force, let m = genreMemory[g.id], Date().timeIntervalSince(m.at) < 3 * 3600 { return m.tracks }
    var songs = await GenreSources.songs(for: g, limit: 30)
    if songs.count < 8 {
      let extra = await MusicEngine.shared.searchSongs(query: g.searchQuery, limit: 25)
      var seen = Set(songs.map(\.id))
      for t in extra where seen.insert(t.id).inserted { songs.append(t) }
    }
    guard !songs.isEmpty else { return genreMemory[g.id]?.tracks ?? [] }
    genreMemory[g.id] = (songs, Date())
    if let data = try? JSONEncoder().encode(songs) { try? data.write(to: Self.genreURL(g.id), options: .atomic) }
    return songs
  }
}
