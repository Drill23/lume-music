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
}

// MARK: - Serviço

/// Motor de descoberta: lançamentos, paradas, artistas (Deezer + Apple + YouTube Music), com cache em disco.
actor DiscoveryService {
  static let shared = DiscoveryService()

  private var albumsMemo: [Int: Task<[AlbumShowcase], Never>] = [:]
  private var memoryFeed: DiscoverFeed?

  private var feedURL: URL { DiscNet.caches("lume_discover_feed.json") }

  private static let ytContext: [String: Any] = [
    "client": ["clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "pt", "gl": "BR"]
  ]
  private static let ytHeaders = ["Origin": "https://music.youtube.com", "Referer": "https://music.youtube.com/"]

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

  func refresh() async -> DiscoverFeed {
    albumsMemo.removeAll()
    async let nr = buildNewReleases()
    async let br = buildBrazilReleases()
    async let tb = fetchTopBrazil()
    async let tg = fetchTopGlobal()
    async let ta = fetchTopArtists()
    async let gta = fetchGlobalTopArtists()
    async let tr = fetchTrending()
    async let abr = appleAlbums(country: "br")
    async let aus = appleAlbums(country: "us")
    let (newR, brR, topBR, topG, topA, gTopA, trend, albBR, albUS) = await (nr, br, tb, tg, ta, gta, tr, abr, aus)

    let old = cachedFeed()
    let feed = DiscoverFeed(
      updatedAt: Date(),
      newReleases: newR.isEmpty ? (old?.newReleases ?? []) : newR,
      brazilReleases: brR.isEmpty ? (old?.brazilReleases ?? []) : brR,
      topBrazil: topBR.isEmpty ? (old?.topBrazil ?? []) : topBR,
      topGlobal: topG.isEmpty ? (old?.topGlobal ?? []) : topG,
      topArtists: topA.isEmpty ? (old?.topArtists ?? []) : topA,
      trending: trend.isEmpty ? (old?.trending ?? []) : trend,
      topAlbumsBrazil: albBR.isEmpty ? old?.topAlbumsBrazil : Array(albBR.prefix(25)),
      topAlbumsGlobal: albUS.isEmpty ? old?.topAlbumsGlobal : Array(albUS.prefix(25)),
      globalTopArtists: gTopA.isEmpty ? old?.globalTopArtists : gTopA
    )
    let anyData = !(feed.newReleases.isEmpty && feed.brazilReleases.isEmpty && feed.topBrazil.isEmpty
      && feed.topGlobal.isEmpty && feed.topArtists.isEmpty && feed.trending.isEmpty)
    if anyData {
      memoryFeed = feed
      if let data = try? JSONEncoder().encode(feed) { try? data.write(to: feedURL, options: .atomic) }
    }
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

  private func fetchTopBrazil() async -> [Track] {
    if let obj = await DiscNet.json("https://rss.marketingtools.apple.com/api/v2/br/music/most-played/50/songs.json", timeout: 5, retries: 2) as? [String: Any],
       let results = (obj["feed"] as? [String: Any])?["results"] as? [[String: Any]] {
      let tracks = Self.appleSongs(results)
      if !tracks.isEmpty { return tracks }
    }
    // Fallback: playlist editorial "Top Brasil" do Deezer
    guard let obj = await DiscNet.json("https://api.deezer.com/playlist/1111141961/tracks?limit=50", retries: 1) as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return [] }
    return data.compactMap { Self.deezerTrack($0, fallbackArtist: "") }
  }

  private func fetchTopGlobal() async -> [Track] {
    // Deezer's chart/0 follows the caller's country (Brazil on the user's phone), so use the
    // editorial "Top Worldwide" playlist for the real global chart; chart/0 only as fallback.
    if let obj = await DiscNet.json("https://api.deezer.com/playlist/3155776842/tracks?limit=50", retries: 1) as? [String: Any],
       let data = obj["data"] as? [[String: Any]] {
      let tracks = data.compactMap { Self.deezerTrack($0, fallbackArtist: "") }
      if !tracks.isEmpty { return tracks }
    }
    guard let obj = await DiscNet.json("https://api.deezer.com/chart/0/tracks?limit=50") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return [] }
    return data.compactMap { Self.deezerTrack($0, fallbackArtist: "") }
  }

  private func fetchTopArtists() async -> [ArtistInfo] {
    guard let obj = await DiscNet.json("https://api.deezer.com/chart/0/artists?limit=30") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return [] }
    return data.enumerated().compactMap { i, d in
      guard var a = Self.artistInfo(d) else { return nil }
      a.rank = Self.int(d["position"]) ?? (i + 1)
      return a
    }
  }

  /// Cantores mais ouvidos no mundo (YouTube Music Global `ZZ` + fotos em alta via ArtworkResolver).
  private func fetchGlobalTopArtists() async -> [ArtistInfo] {
    let body: [String: Any] = [
      "context": Self.ytContext, "browseId": "FEmusic_charts", "formData": ["selectedValues": ["ZZ"]],
    ]
    var names: [String] = []
    if let obj = await DiscNet.postJSON("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                                        body: body, headers: Self.ytHeaders) {
      func walk(_ n: Any) {
        if let d = n as? [String: Any] {
          if let r = d["musicResponsiveListItemRenderer"] as? [String: Any],
             let cols = r["flexColumns"] as? [[String: Any]], let first = cols.first {
            let runs = ((first["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
            let name = runs.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names.append(name) }
            return
          }
          for v in d.values { walk(v) }
        } else if let a = n as? [Any] { for v in a { walk(v) } }
      }
      walk(obj)
    }
    var seen = Set<String>()
    let unique = names.filter { seen.insert(DiscText.normalize($0)).inserted }.prefix(24)
    if unique.isEmpty {
      // Fallback: extrair artistas do Top Global do Apple Music US
      if let obj = await DiscNet.json("https://rss.marketingtools.apple.com/api/v2/us/music/most-played/40/songs.json", timeout: 5, retries: 1) as? [String: Any],
         let results = (obj["feed"] as? [String: Any])?["results"] as? [[String: Any]] {
        let fallbackNames = results.compactMap { $0["artistName"] as? String }
        return await resolveRankedArtists(Array(fallbackNames.prefix(20)))
      }
      return []
    }
    return await resolveRankedArtists(Array(unique))
  }

  private func resolveRankedArtists(_ names: [String]) async -> [ArtistInfo] {
    var seen = Set<String>()
    var clean: [(Int, String)] = []
    for n in names {
      let main = DiscText.searchArtist(n)
      let key = DiscText.normalize(main)
      guard !key.isEmpty, seen.insert(key).inserted else { continue }
      clean.append((clean.count + 1, main))
      if clean.count >= 24 { break }
    }
    let resolved: [(Int, ArtistInfo)] = await withTaskGroup(of: (Int, ArtistInfo)?.self) { group in
      for (rank, name) in clean {
        group.addTask {
          if let info = await self.resolveArtist(name: name) {
            var a = info
            a.rank = rank
            return (rank, a)
          }
          return (rank, ArtistInfo(id: "g_\(DiscText.normalize(name))", name: name, pictureURL: "", deezerId: nil, fans: nil, rank: rank))
        }
      }
      var out: [(Int, ArtistInfo)] = []
      for await item in group { if let item { out.append(item) } }
      return out
    }
    return resolved.sorted { $0.0 < $1.0 }.map(\.1)
  }

  private func fetchTrending() async -> [Track] {
    var tracks = await fetchYTMTrending()
    if tracks.isEmpty {
      if let obj = await DiscNet.json("https://rss.marketingtools.apple.com/api/v2/us/music/most-played/50/songs.json", timeout: 5, retries: 2) as? [String: Any],
         let results = (obj["feed"] as? [String: Any])?["results"] as? [[String: Any]] {
        tracks = Self.appleSongs(results)
      }
      return tracks
    }
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

  private func buildNewReleases() async -> [AlbumShowcase] {
    async let apBR = appleAlbums(country: "br")
    async let apUS = appleAlbums(country: "us")
    async let chart = DiscNet.json("https://api.deezer.com/chart/0/artists?limit=20")
    let (br, us, chartObj) = await (apBR, apUS, chart)
    let cutoff = Self.dayString(daysAgo: 120)
    let today = Self.dayString(daysAgo: 0)

    let artists = ((chartObj as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap { Self.artistInfo($0) }
    let deezer = await recentForArtists(artists.map { ($0.deezerId ?? 0, $0.name) }.filter { $0.0 != 0 })
    let all = deezer + br + us
    let recent = all.filter { ($0.releaseDate ?? "") >= cutoff && ($0.releaseDate ?? "") <= today }
    return Array(Self.dedupe(recent).sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }.prefix(40))
  }

  private func buildBrazilReleases() async -> [AlbumShowcase] {
    async let apBR = appleAlbums(country: "br")
    async let topBRArtists = fetchTopArtists()
    let (apple, chartArtists) = await (apBR, topBRArtists)
    let pairs = chartArtists.prefix(16).compactMap { a -> (Int, String)? in
      guard let id = a.deezerId else { return nil }
      return (id, a.name)
    }
    let deezer = await recentForArtists(pairs)
    let cutoffDz = Self.dayString(daysAgo: 150)
    let cutoffAp = Self.dayString(daysAgo: 90)
    let today = Self.dayString(daysAgo: 0)
    let dzRecent = deezer.filter { ($0.releaseDate ?? "") >= cutoffDz && ($0.releaseDate ?? "") <= today }
    let brNames = Set(chartArtists.map { DiscText.normalize($0.name) })
    let brGenres = ["sertanej", "mpb", "pagode", "samba", "funk", "forro", "axe", "brasil", "gospel", "piseiro", "arrocha", "bossa", "tropicalia"]
    func isBrazilian(_ a: AlbumShowcase) -> Bool {
      let g = DiscText.normalize(a.genre)
      if brGenres.contains(where: { g.contains($0) }) { return true }
      return DiscText.splitArtists(a.artist).contains { brNames.contains($0) }
    }
    let apRecent = apple.filter { ($0.releaseDate ?? "") >= cutoffAp && ($0.releaseDate ?? "") <= today && isBrazilian($0) }
    let combined = Self.dedupe(dzRecent + apRecent).sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    if combined.isEmpty {
      return Array(apple.prefix(24))
    }
    return Array(combined.prefix(40))
  }

  private func appleAlbums(country: String) async -> [AlbumShowcase] {
    guard let obj = await DiscNet.json("https://rss.marketingtools.apple.com/api/v2/\(country)/music/most-played/50/albums.json", timeout: 5, retries: 2) as? [String: Any],
          let results = (obj["feed"] as? [String: Any])?["results"] as? [[String: Any]] else { return [] }
    return results.compactMap { r in
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
        artworkURL: Self.upscaleApple((r["artworkUrl100"] as? String) ?? ""),
        year: DiscText.year(from: date), genre: genre, tracks: [],
        releaseDate: date, kind: kind, deezerId: nil, itunesId: Int(idStr))
    }
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

  private static func dayString(daysAgo: Int) -> String {
    let date = Date().addingTimeInterval(-Double(daysAgo) * 86400)
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }
}
