import Foundation

// MARK: - Modelos

struct ArtistInfo: Identifiable, Codable, Hashable {
  var id: String          // ex. "dz_27"
  var name: String
  var pictureURL: String
  var deezerId: Int?
  var fans: Int?
  var rank: Int?
}

struct ArtistDetail: Codable, Hashable {
  var artist: ArtistInfo
  var topTracks: [Track]
  var albums: [AlbumShowcase]      // mais recente primeiro
  var related: [ArtistInfo]
}

struct DiscoverFeed: Codable {
  var updatedAt: Date
  var newReleases: [AlbumShowcase]     // lançamentos mundiais recentes (mais novo primeiro)
  var brazilReleases: [AlbumShowcase]  // lançamentos/álbuns brasileiros recentes
  var topBrazil: [Track]               // mais tocadas no Brasil
  var topGlobal: [Track]               // mais tocadas no mundo
  var topArtists: [ArtistInfo]         // cantores mais ouvidos (Brasil)
  var trending: [Track]                // em alta (YouTube Music BR; fallback Apple US)
  var topAlbumsBrazil: [AlbumShowcase]? = nil
  var topAlbumsGlobal: [AlbumShowcase]? = nil
  var globalTopArtists: [ArtistInfo]? = nil
  /// Playlist "Top Brasil" (Deezer Charts): música realmente brasileira, ao contrário da parada da Apple que traz muitos hits gringos.
  var brazilianHits: [Track]? = nil
}

// MARK: - Serviço

/// Motor de descoberta: lançamentos, paradas, artistas (Deezer + Apple + YouTube Music), com cache em disco.
actor DiscoveryService {
  static let shared = DiscoveryService()

  private var albumsMemo: [Int: Task<[AlbumShowcase], Never>] = [:]
  private var memoryFeed: DiscoverFeed?

  private var feedURL: URL { DiscNet.caches("lume_discover_feed_v2.json") }
  private var refreshTask: Task<DiscoverFeed, Never>?

  /// Publicada a cada etapa da atualização (Home/Explorar podem reagir sem esperar tudo terminar).
  static let feedUpdated = Notification.Name("lume.discover.feedUpdated")

  private static let ytContext: [String: Any] = [
    "client": ["clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "pt", "gl": "BR"]
  ]
  private static let ytHeaders = ["Origin": "https://music.youtube.com", "Referer": "https://music.youtube.com/"]

  // Playlists oficiais "Deezer Charts" (auditadas): Top Brasil e Top Worldwide.
  private static let deezerTopBrasil = 1111141961
  private static let deezerTopWorldwide = 3155776842

  // MARK: Feed

  func cachedFeed() -> DiscoverFeed? {
    if let m = memoryFeed { return m }
    guard let data = try? Data(contentsOf: feedURL),
          let feed = try? JSONDecoder().decode(DiscoverFeed.self, from: data) else { return nil }
    memoryFeed = feed
    return feed
  }

  func feed(maxAge: TimeInterval = 3 * 3600) async -> DiscoverFeed {
    if let c = cachedFeed(), Date().timeIntervalSince(c.updatedAt) < maxAge { return c }
    return await refresh()
  }

  /// Atualização coalescida: chamadas simultâneas (Home, Explorar, RootView) compartilham a mesma busca.
  func refresh() async -> DiscoverFeed {
    if let t = refreshTask { return await t.value }
    let t = Task<DiscoverFeed, Never> { await self.runRefresh() }
    refreshTask = t
    let f = await t.value
    refreshTask = nil
    return f
  }

  private func publish(_ feed: DiscoverFeed) {
    let anyData = !(feed.newReleases.isEmpty && feed.brazilReleases.isEmpty && feed.topBrazil.isEmpty
      && feed.topGlobal.isEmpty && feed.topArtists.isEmpty && feed.trending.isEmpty)
    guard anyData else { return }
    memoryFeed = feed
    if let data = try? JSONEncoder().encode(feed) { try? data.write(to: feedURL, options: .atomic) }
    NotificationCenter.default.post(name: Self.feedUpdated, object: nil, userInfo: ["feed": feed])
  }

  private func runRefresh() async -> DiscoverFeed {
    albumsMemo.removeAll()
    let old = cachedFeed()

    // ETAPA 1 (rápida, tudo em paralelo): paradas, artistas e álbuns mais ouvidos.
    async let brPL = ChartParsers.deezerPlaylistTracks(Self.deezerTopBrasil)
    async let wwPL = ChartParsers.deezerPlaylistTracks(Self.deezerTopWorldwide)
    async let tbApple = fetchAppleTracks(country: "br")
    async let abr = appleAlbums(country: "br")
    async let aus = appleAlbums(country: "us")
    async let agb = appleAlbums(country: "gb")
    let (br, ww, topBRApple, albBR, albUS, albGB) = await (brPL, wwPL, tbApple, abr, aus, agb)

    // "Top Brasil" = parada da Apple Music do Brasil (o que os brasileiros mais ouvem, inclui hits internacionais);
    // reserva = playlist "Top Brasil" do Deezer. "Top Global" = playlist Deezer "Top Worldwide".
    let topBR = topBRApple.isEmpty ? (br?.tracks ?? []) : topBRApple
    let topG = ww?.tracks ?? []
    // Artistas: calculados a partir dessas paradas (e não do /chart/0 do Deezer, que muda conforme o país do IP).
    var brArtists = Array((br?.artists ?? []).prefix(30))
    if brArtists.isEmpty { brArtists = await fetchTopArtistsFallback() }
    let worldArtists = Array((ww?.artists ?? []).prefix(30))

    var feed = DiscoverFeed(
      updatedAt: Date(),
      newReleases: old?.newReleases ?? [],
      brazilReleases: old?.brazilReleases ?? [],
      topBrazil: topBR.isEmpty ? (old?.topBrazil ?? []) : topBR,
      topGlobal: topG.isEmpty ? (old?.topGlobal ?? []) : topG,
      topArtists: brArtists.isEmpty ? (old?.topArtists ?? []) : brArtists,
      trending: old?.trending ?? [],
      topAlbumsBrazil: albBR.isEmpty ? old?.topAlbumsBrazil : Array(albBR.prefix(25)),
      topAlbumsGlobal: albUS.isEmpty ? old?.topAlbumsGlobal : Array(albUS.prefix(25)),
      globalTopArtists: worldArtists.isEmpty ? old?.globalTopArtists : worldArtists,
      brazilianHits: (br?.tracks.isEmpty ?? true) ? old?.brazilianHits : br?.tracks
    )
    publish(feed)

    // ETAPA 2 (mais lenta: dezenas de consultas ao Deezer): lançamentos do mundo e do Brasil.
    async let nr = buildNewReleases(worldArtists: worldArtists, apple: albUS + albGB)
    async let brr = buildBrazilReleases(brazilArtists: brArtists, apple: albBR)
    async let tr = fetchTrending()
    let (newR, brR, trend) = await (nr, brr, tr)
    if !trend.isEmpty { feed.trending = trend }
    feed.newReleases = newR.isEmpty ? feed.newReleases : newR
    feed.brazilReleases = brR.isEmpty ? feed.brazilReleases : brR
    feed.updatedAt = Date()
    publish(feed)
    return feed
  }

  // MARK: Artista

  func artistDetail(name: String, deezerId: Int?) async -> ArtistDetail? {
    var info: ArtistInfo?
    if let id = deezerId, let obj = await DiscNet.json("https://api.deezer.com/artist/\(id)") as? [String: Any] {
      info = Self.artistInfo(obj)
    }
    if info == nil { info = await resolveArtist(name: name) }
    guard let artist = info, let id = artist.deezerId else { return nil }

    async let top = DiscNet.json("https://api.deezer.com/artist/\(id)/top?limit=20")
    async let alb = artistAlbums(id: id, artistName: artist.name, limit: 50)
    async let rel = DiscNet.json("https://api.deezer.com/artist/\(id)/related?limit=12")
    let (topObj, albums, relObj) = await (top, alb, rel)

    let topTracks = ((topObj as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap {
      Self.deezerTrack($0, fallbackArtist: artist.name)
    }
    let related = ((relObj as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap { Self.artistInfo($0) }
    let today = Self.dayString(daysAgo: 0)
    let sorted = albums
      .filter { ($0.releaseDate ?? "") <= today }
      .sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    return ArtistDetail(artist: artist, topTracks: topTracks, albums: sorted, related: related)
  }

  func newReleases(forArtists names: [String], withinDays: Int = 45) async -> [AlbumShowcase] {
    var seen = Set<String>()
    var unique: [String] = []
    for n in names {
      let k = DiscText.normalize(n)
      if k.isEmpty || seen.contains(k) { continue }
      seen.insert(k)
      unique.append(n)
      if unique.count >= 12 { break }
    }
    let cutoff = Self.dayString(daysAgo: withinDays)
    let today = Self.dayString(daysAgo: 0)
    let lists: [[AlbumShowcase]] = await withTaskGroup(of: [AlbumShowcase].self) { group in
      for n in unique {
        group.addTask { [self] in
          guard let a = await resolveArtist(name: n), let id = a.deezerId else { return [] }
          return await recentAlbums(artistId: id, artistName: a.name)
            .filter { ($0.releaseDate ?? "") >= cutoff && ($0.releaseDate ?? "") <= today }
        }
      }
      var all: [[AlbumShowcase]] = []
      for await l in group { all.append(l) }
      return all
    }
    return Self.dedupe(lists.flatMap { $0 }).sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
  }

  // MARK: Faixas de álbum

  func albumTracks(_ album: AlbumShowcase) async -> [Track] {
    func finish(_ tracks: [Track]) -> [Track] {
      tracks.map { t in
        var t = t
        t.artworkURL = album.artworkURL.isEmpty ? t.artworkURL : album.artworkURL
        t.album = album.title
        return t
      }
    }
    if let dz = album.deezerId {
      let tracks = await deezerAlbumTracks(id: dz, album: album)
      if !tracks.isEmpty { return finish(tracks) }
    }
    // Apple
    var itunesId = album.itunesId
    if itunesId == nil, album.id.hasPrefix("alb_") { itunesId = Int(album.id.dropFirst(4)) }
    if itunesId == nil {
      let term = DiscNet.enc("\(album.title) \(album.artist)")
      if let obj = await DiscNet.json("https://itunes.apple.com/search?term=\(term)&entity=album&country=br&limit=8") as? [String: Any],
         let results = obj["results"] as? [[String: Any]] {
        let hit = results.first {
          DiscText.artistMatches(($0["artistName"] as? String) ?? "", album.artist)
            && DiscText.titleLooselyMatches(($0["collectionName"] as? String) ?? "", album.title)
        }
        itunesId = Self.int(hit?["collectionId"])
      }
    }
    if let id = itunesId {
      for country in ["br", "us"] {
        if let obj = await DiscNet.json("https://itunes.apple.com/lookup?id=\(id)&entity=song&country=\(country)&limit=200") as? [String: Any],
           let results = obj["results"] as? [[String: Any]] {
          let tracks: [Track] = results.compactMap { r in
            guard (r["wrapperType"] as? String) == "track", let title = r["trackName"] as? String else { return nil }
            return Track(
              title: title,
              artist: (r["artistName"] as? String) ?? album.artist,
              album: album.title,
              duration: ((r["trackTimeMillis"] as? Double) ?? 0) / 1000,
              artworkURL: album.artworkURL,
              sourceService: "Apple",
              isExplicit: (r["trackExplicitness"] as? String) == "explicit")
          }
          if !tracks.isEmpty { return finish(tracks) }
        }
      }
    }
    // Último recurso: achar o álbum no Deezer
    if album.deezerId == nil {
      let q = DiscNet.enc("\(album.title) \(album.artist)")
      if let obj = await DiscNet.json("https://api.deezer.com/search/album?q=\(q)&limit=5") as? [String: Any],
         let data = obj["data"] as? [[String: Any]],
         let hit = data.first(where: {
           DiscText.titleLooselyMatches(($0["title"] as? String) ?? "", album.title)
             && DiscText.artistMatches((($0["artist"] as? [String: Any])?["name"] as? String) ?? "", album.artist)
         }),
         let id = Self.int(hit["id"]) {
        return finish(await deezerAlbumTracks(id: id, album: album))
      }
    }
    return []
  }

  private func deezerAlbumTracks(id: Int, album: AlbumShowcase) async -> [Track] {
    guard let obj = await DiscNet.json("https://api.deezer.com/album/\(id)/tracks?limit=200") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return [] }
    return data.compactMap { d in
      guard var t = Self.deezerTrack(d, fallbackArtist: album.artist) else { return nil }
      t.album = album.title
      t.artworkURL = album.artworkURL
      return t
    }
  }

  // MARK: Construção das listas

  private func fetchAppleTracks(country: String) async -> [Track] {
    ChartParsers.appleSongs(await ChartParsers.appleChart(country, kind: "songs", limit: 50), label: "Apple")
  }

  /// Reserva: ranking de artistas do Deezer (varia com o país do IP; só usado se a playlist Top Brasil falhar).
  private func fetchTopArtistsFallback() async -> [ArtistInfo] {
    guard let obj = await DiscNet.json("https://api.deezer.com/chart/0/artists?limit=30") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return [] }
    return data.enumerated().compactMap { i, d in
      guard var a = Self.artistInfo(d) else { return nil }
      a.rank = i + 1
      return a
    }
  }

  /// "Em alta": vídeos de música em alta no YouTube Music Brasil (sem reserva de outro país, para o rótulo ser verdadeiro).
  private func fetchTrending() async -> [Track] {
    var tracks = await fetchYTMTrending()
    if tracks.isEmpty { return [] }
    // thumbnails de vídeo → capas reais
    let upgraded: [Int: String] = await withTaskGroup(of: (Int, String?).self) { group in
      for (i, t) in tracks.enumerated() where ArtworkResolver.needsUpgrade(t.artworkURL) {
        group.addTask {
          (i, await ArtworkResolver.shared.albumCover(title: t.title, artist: t.artist, album: t.album))
        }
      }
      var out: [Int: String] = [:]
      for await (i, url) in group { if let url { out[i] = url } }
      return out
    }
    for (i, url) in upgraded { tracks[i].artworkURL = url }
    return tracks
  }

  /// YouTube Music: charts BR → playlist "vídeos em alta" → faixas.
  private func fetchYTMTrending() async -> [Track] {
    var playlistId = "VLOLAK5uy_nxSJNrV0WQ9XbKv_4R9Y98EYwJnZBgkfg"   // "Brasil: 20 vídeos em alta"
    let chartBody: [String: Any] = [
      "context": Self.ytContext, "browseId": "FEmusic_charts", "formData": ["selectedValues": ["BR"]],
    ]
    if let charts = await DiscNet.postJSON("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                                           body: chartBody, headers: Self.ytHeaders) {
      var found: String?
      func walk(_ n: Any) {
        if found != nil { return }
        if let d = n as? [String: Any] {
          if let r = d["musicTwoRowItemRenderer"] as? [String: Any],
             let runs = (r["title"] as? [String: Any])?["runs"] as? [[String: Any]],
             let text = runs.first?["text"] as? String,
             text.lowercased().contains("em alta"),
             let bid = ((r["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String {
            found = bid
            return
          }
          for v in d.values { walk(v) }
        } else if let a = n as? [Any] { for v in a { walk(v) } }
      }
      walk(charts)
      if let f = found { playlistId = f }
    }
    let body: [String: Any] = ["context": Self.ytContext, "browseId": playlistId]
    guard let obj = await DiscNet.postJSON("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                                           body: body, headers: Self.ytHeaders) else { return [] }
    var tracks: [Track] = []
    func walk(_ n: Any) {
      if let d = n as? [String: Any] {
        if let r = d["musicResponsiveListItemRenderer"] as? [String: Any], let t = Self.ytmTrack(r) {
          tracks.append(t)
          return
        }
        for v in d.values { walk(v) }
      } else if let a = n as? [Any] { for v in a { walk(v) } }
    }
    walk(obj)
    var seen = Set<String>()
    return tracks.filter { seen.insert($0.id).inserted }
  }

  private static func ytmTrack(_ r: [String: Any]) -> Track? {
    guard let videoId = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String,
          let cols = r["flexColumns"] as? [[String: Any]], cols.count >= 2 else { return nil }
    func text(_ i: Int) -> String {
      let runs = ((cols[i]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
      return runs.compactMap { $0["text"] as? String }.joined()
    }
    let title = text(0), artist = text(1)
    guard !title.isEmpty else { return nil }
    var thumb = ""
    if let th = (((r["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] {
      thumb = (th.last?["url"] as? String) ?? ""
    }
    return Track(videoId: videoId, title: title, artist: artist, artworkURL: thumb, sourceService: "YouTube Music")
  }

  /// Lançamentos do mundo: álbuns recentes dos maiores artistas da parada global + álbuns novos mais ouvidos nos EUA/Reino Unido.
  private func buildNewReleases(worldArtists: [ArtistInfo], apple: [AlbumShowcase]) async -> [AlbumShowcase] {
    let cutoff = Self.dayString(daysAgo: 120)
    let today = Self.dayString(daysAgo: 0)
    let pairs = worldArtists.prefix(14).compactMap { a -> (Int, String)? in
      guard let id = a.deezerId else { return nil }
      return (id, a.name)
    }
    let deezer = await recentForArtists(Array(pairs))
    let recent = (deezer + apple).filter { ($0.releaseDate ?? "") >= cutoff && ($0.releaseDate ?? "") <= today }
    return Array(Self.dedupe(recent).sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }.prefix(40))
  }

  /// Lançamentos do Brasil: só entra o que for de artista da parada brasileira ou de gênero tipicamente brasileiro.
  private func buildBrazilReleases(brazilArtists: [ArtistInfo], apple: [AlbumShowcase]) async -> [AlbumShowcase] {
    let pairs = brazilArtists.prefix(16).compactMap { a -> (Int, String)? in
      guard let id = a.deezerId else { return nil }
      return (id, a.name)
    }
    let deezer = await recentForArtists(Array(pairs))
    let cutoffDz = Self.dayString(daysAgo: 150)
    let cutoffAp = Self.dayString(daysAgo: 90)
    let today = Self.dayString(daysAgo: 0)
    let dzRecent = deezer.filter { ($0.releaseDate ?? "") >= cutoffDz && ($0.releaseDate ?? "") <= today }
    let brNames = Set(brazilArtists.map { DiscText.normalize($0.name) })
    let brGenres = ["sertanej", "mpb", "pagode", "samba", "funk", "forro", "axe", "brasil", "piseiro", "arrocha",
                    "bossa", "tropicalia", "choro", "frevo"]
    func isBrazilian(_ a: AlbumShowcase) -> Bool {
      let g = DiscText.normalize(a.genre)
      if brGenres.contains(where: { g.contains($0) }) { return true }
      return DiscText.splitArtists(a.artist).contains { brNames.contains($0) }
    }
    let apRecent = apple.filter { ($0.releaseDate ?? "") >= cutoffAp && ($0.releaseDate ?? "") <= today && isBrazilian($0) }
    return Array(Self.dedupe(dzRecent + apRecent).sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }.prefix(40))
  }

  private func appleAlbums(country: String) async -> [AlbumShowcase] {
    ChartParsers.appleAlbums(await ChartParsers.appleChart(country, kind: "albums", limit: 50), size: 1000)
  }

  /// Álbuns recentes de vários artistas, com concorrência limitada (Deezer limita ~50 req/5s).
  private func recentForArtists(_ artists: [(Int, String)]) async -> [AlbumShowcase] {
    var result: [AlbumShowcase] = []
    var i = 0
    let batch = 8
    while i < artists.count {
      let slice = Array(artists[i..<min(i + batch, artists.count)])
      let parts: [[AlbumShowcase]] = await withTaskGroup(of: [AlbumShowcase].self) { group in
        for (id, name) in slice {
          group.addTask { [self] in await recentAlbums(artistId: id, artistName: name) }
        }
        var out: [[AlbumShowcase]] = []
        for await p in group { out.append(p) }
        return out
      }
      result += parts.flatMap { $0 }
      i += batch
    }
    return result
  }

  private func recentAlbums(artistId: Int, artistName: String) async -> [AlbumShowcase] {
    if let t = albumsMemo[artistId] { return await t.value }
    let task = Task<[AlbumShowcase], Never> { [self] in
      await artistAlbums(id: artistId, artistName: artistName, limit: 40)
    }
    albumsMemo[artistId] = task
    return await task.value
  }

  private func artistAlbums(id: Int, artistName: String, limit: Int) async -> [AlbumShowcase] {
    guard let obj = await DiscNet.json("https://api.deezer.com/artist/\(id)/albums?limit=\(limit)") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return [] }
    return data.compactMap { Self.deezerAlbum($0, artist: artistName) }
  }

  private func resolveArtist(name: String) async -> ArtistInfo? {
    let clean = DiscText.searchArtist(name)
    guard let obj = await DiscNet.json("https://api.deezer.com/search/artist?q=\(DiscNet.enc(clean))&limit=5") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return nil }
    let target = DiscText.normalize(clean)
    let hit = data.first { DiscText.normalize(($0["name"] as? String) ?? "") == target }
      ?? data.first { DiscText.artistMatches(($0["name"] as? String) ?? "", clean) }
    return hit.flatMap { Self.artistInfo($0) }
  }

  // MARK: Parsers

  fileprivate static func int(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let s = v as? String { return Int(s) }
    if let d = v as? Double { return Int(d) }
    return nil
  }

  private static func upscaleApple(_ url: String) -> String {
    var u = url
    if let r = u.range(of: #"\d{2,4}x\d{2,4}(bb|cc)"#, options: .regularExpression) {
      u.replaceSubrange(r, with: "1200x1200bb")
    }
    return u
  }

  private static func artistInfo(_ d: [String: Any]) -> ArtistInfo? {
    guard let id = int(d["id"]), let name = d["name"] as? String else { return nil }
    var pic = (d["picture_xl"] as? String) ?? (d["picture_big"] as? String) ?? ""
    if pic.contains("/images/artist//") { pic = "" }
    return ArtistInfo(id: "dz_\(id)", name: name, pictureURL: pic, deezerId: id,
                      fans: int(d["nb_fan"]), rank: nil)
  }

  private static func deezerTrack(_ d: [String: Any], fallbackArtist: String) -> Track? {
    guard let title = d["title"] as? String, !title.isEmpty else { return nil }
    let artistName = ((d["artist"] as? [String: Any])?["name"] as? String) ?? fallbackArtist
    let album = d["album"] as? [String: Any]
    var cover = (album?["cover_xl"] as? String) ?? (album?["cover_big"] as? String) ?? ""
    if cover.contains("/cover//") { cover = "" }
    return Track(
      title: title, artist: artistName, album: (album?["title"] as? String) ?? "",
      duration: Double(int(d["duration"]) ?? 0), artworkURL: cover, sourceService: "Deezer",
      isExplicit: (d["explicit_lyrics"] as? Bool) ?? false)
  }

  private static func deezerAlbum(_ d: [String: Any], artist: String) -> AlbumShowcase? {
    guard let id = int(d["id"]), let title = d["title"] as? String else { return nil }
    let date = d["release_date"] as? String
    let kind: String
    switch (d["record_type"] as? String)?.lowercased() {
    case "single": kind = "Single"
    case "ep": kind = "EP"
    default: kind = "Álbum"
    }
    let cover = (d["cover_xl"] as? String) ?? (d["cover_big"] as? String) ?? ""
    return AlbumShowcase(
      id: "dzalb_\(id)", title: title, artist: artist, artworkURL: cover,
      year: DiscText.year(from: date), genre: "", tracks: [],
      releaseDate: date, kind: kind, deezerId: id, itunesId: nil)
  }

  private static func appleSongs(_ results: [[String: Any]]) -> [Track] {
    results.compactMap { r in
      guard let title = r["name"] as? String else { return nil }
      return Track(
        title: title, artist: (r["artistName"] as? String) ?? "",
        artworkURL: upscaleApple((r["artworkUrl100"] as? String) ?? ""),
        sourceService: "Apple",
        isExplicit: ((r["contentAdvisoryRating"] as? String) ?? "").lowercased().hasPrefix("explic"))
    }
  }

  /// Remove duplicatas (título+artista normalizados), preenchendo ids que faltem.
  private static func dedupe(_ albums: [AlbumShowcase]) -> [AlbumShowcase] {
    var index: [String: Int] = [:]
    var out: [AlbumShowcase] = []
    for a in albums {
      let key = DiscText.normalize(a.title) + "|" + DiscText.normalize(DiscText.splitArtists(a.artist).first ?? a.artist)
      if let i = index[key] {
        if out[i].deezerId == nil { out[i].deezerId = a.deezerId }
        if out[i].itunesId == nil { out[i].itunesId = a.itunesId }
        if out[i].genre.isEmpty { out[i].genre = a.genre }
        if a.deezerId != nil, out[i].deezerId == a.deezerId, a.id.hasPrefix("dzalb_") { out[i].id = a.id }
      } else {
        index[key] = out.count
        out.append(a)
      }
    }
    return out
  }

  private static let isoDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private static func dayString(daysAgo: Int) -> String {
    let date = Date().addingTimeInterval(-Double(daysAgo) * 86400)
    return isoDayFormatter.string(from: date)
  }
}
