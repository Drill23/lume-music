import Foundation

struct CountryChartBundle: Codable, Hashable {
  let country: ChartCountry
  let topSongs: [Track]
  let topAlbums: [AlbumShowcase]
  let topArtists: [ArtistInfo]
  let trending: [Track]
  let updatedAt: Date
}

struct GenreHubBundle: Codable, Hashable {
  let genre: MusicGenre
  let topSongs: [Track]
  let topAlbums: [AlbumShowcase]
  let topArtists: [ArtistInfo]
  let playlists: [RemotePlaylist]
  let updatedAt: Date
}

/// Motor de exploração por país, gênero musical, playlists editoriais e mixes personalizados.
/// Usa Apple RSS v2, iTunes Genre RSS, YouTube Music Charts e Deezer Playlists (evitando /genre/{id}/artists do Deezer que ignora o gênero).
actor CatalogExplorerService {
  static let shared = CatalogExplorerService()

  private var countryCache: [String: CountryChartBundle] = [:]
  private var genreCache: [String: GenreHubBundle] = [:]
  private var playlistCache: [Int: (tracks: [Track], at: Date)] = [:]

  private let ttl: TimeInterval = 2 * 3600

  private static let ytContext: [String: Any] = [
    "client": ["clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "pt", "gl": "BR"]
  ]
  private static let ytHeaders = ["Origin": "https://music.youtube.com", "Referer": "https://music.youtube.com/"]

  // MARK: - Paradas por País

  /// Último pacote salvo (memória/disco), de qualquer idade. Serve para mostrar algo NA HORA e atualizar depois.
  func cachedCountryChart(for country: ChartCountry) -> CountryChartBundle? {
    if let hit = countryCache[country.code] { return hit }
    let disk = DiscNet.caches("lume_country_v2_\(country.code).json")
    guard let data = try? Data(contentsOf: disk),
          let saved = try? JSONDecoder().decode(CountryChartBundle.self, from: data),
          !saved.topSongs.isEmpty else { return nil }
    countryCache[country.code] = saved
    return saved
  }

  /// Etapa rápida: só músicas e álbuns (compartilha o cache com a Home). Preserva artistas/em alta já conhecidos.
  func countryChartFast(for country: ChartCountry, force: Bool = false) async -> CountryChartBundle? {
    guard let place = ChartPlace.place(id: country.code),
          let list = await ChartsService.shared.load(place, force: force) else { return cachedCountryChart(for: country) }
    let prev = cachedCountryChart(for: country)
    let bundle = CountryChartBundle(
      country: country, topSongs: list.songs, topAlbums: list.albums,
      topArtists: prev?.topArtists ?? [], trending: prev?.trending ?? [], updatedAt: list.updatedAt)
    countryCache[country.code] = bundle
    return bundle
  }

  /// Pacote completo: músicas, álbuns, artistas ranqueados e "em alta" do YouTube Music do país.
  func countryChart(for country: ChartCountry, force: Bool = false) async -> CountryChartBundle {
    if !force, let hit = countryCache[country.code], Date().timeIntervalSince(hit.updatedAt) < ttl,
       !hit.topArtists.isEmpty || !hit.trending.isEmpty { return hit }

    async let fastTask = countryChartFast(for: country, force: force)
    async let ytmTask = fetchYTMCountryCharts(ytmCode: country.ytmCode)
    let (fast, ytm) = await (fastTask, ytmTask)
    let songs = fast?.topSongs ?? []

    var artists: [ArtistInfo] = []
    if country.code == "world" {
      // Global: artistas da própria parada global do Deezer (a lista de artistas do YouTube Global é dominada pela Índia).
      if let dz = await ChartParsers.deezerPlaylistTracks(3155776842) { artists = Array(dz.artists.prefix(16)) }
    } else if !ytm.artistNames.isEmpty {
      artists = await resolveArtists(names: ytm.artistNames, limit: 16)
    }
    if artists.isEmpty {
      artists = await resolveArtists(names: songs.map { Self.primaryArtist($0.artist) }, limit: 16)
    }

    let bundle = CountryChartBundle(
      country: country, topSongs: songs, topAlbums: fast?.topAlbums ?? [],
      topArtists: artists, trending: ytm.tracks, updatedAt: Date())
    if !songs.isEmpty {
      countryCache[country.code] = bundle
      if let encoded = try? JSONEncoder().encode(bundle) {
        try? encoded.write(to: DiscNet.caches("lume_country_v2_\(country.code).json"), options: .atomic)
      }
    }
    return bundle
  }

  // MARK: - Hub de Gênero Musical

  /// Último hub salvo (qualquer idade) para mostrar na hora e atualizar em seguida.
  func cachedGenreHub(for genre: MusicGenre) -> GenreHubBundle? {
    if let hit = genreCache[genre.id] { return hit }
    guard let data = try? Data(contentsOf: DiscNet.caches("lume_genre_v2_\(genre.id).json")),
          let saved = try? JSONDecoder().decode(GenreHubBundle.self, from: data), !saved.topSongs.isEmpty else { return nil }
    genreCache[genre.id] = saved
    return saved
  }

  func isGenreHubFresh(_ genre: MusicGenre) -> Bool {
    guard let hit = genreCache[genre.id] else { return false }
    return Date().timeIntervalSince(hit.updatedAt) < ttl
  }

  func genreHub(for genre: MusicGenre, force: Bool = false) async -> GenreHubBundle {
    if !force, let hit = genreCache[genre.id], Date().timeIntervalSince(hit.updatedAt) < ttl {
      return hit
    }
    let disk = DiscNet.caches("lume_genre_v2_\(genre.id).json")
    if !force,
       let data = try? Data(contentsOf: disk),
       let saved = try? JSONDecoder().decode(GenreHubBundle.self, from: data),
       Date().timeIntervalSince(saved.updatedAt) < ttl,
       !saved.topSongs.isEmpty {
      genreCache[genre.id] = saved
      return saved
    }

    async let appleSongsTask = GenreSources.songs(for: genre, limit: 30)
    async let appleAlbumsTask = GenreSources.albums(for: genre, limit: 16)
    async let playlistsTask = SearchService.shared.playlists(genre.playlistQuery, limit: 10)

    let (appleSongs, appleAlbums, playlists) = await (appleSongsTask, appleAlbumsTask, playlistsTask)

    var songs = appleSongs
    if songs.count < 12 {
      let extra = await MusicEngine.shared.searchSongs(query: genre.searchQuery, limit: 25)
      var seen = Set(songs.map(\.id))
      for t in extra where seen.insert(t.id).inserted {
        songs.append(t)
      }
    }

    let candidateArtists = songs.map { Self.primaryArtist($0.artist) }
    let artists = await resolveArtists(names: candidateArtists, limit: 16)

    let bundle = GenreHubBundle(
      genre: genre,
      topSongs: Array(songs.prefix(35)),
      topAlbums: appleAlbums,
      topArtists: artists,
      playlists: playlists,
      updatedAt: Date()
    )
    if !bundle.topSongs.isEmpty {
      genreCache[genre.id] = bundle
      if let encoded = try? JSONEncoder().encode(bundle) {
        try? encoded.write(to: disk, options: .atomic)
      }
    }
    return bundle
  }

  // MARK: - Faixas de Playlist Editorial

  func playlistTracks(deezerId: Int) async -> [Track] {
    if let hit = playlistCache[deezerId], Date().timeIntervalSince(hit.at) < 3600 {
      return hit.tracks
    }
    guard let obj = await DiscNet.json("https://api.deezer.com/playlist/\(deezerId)/tracks?limit=100", timeout: 8, retries: 1) as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return [] }
    let tracks: [Track] = data.compactMap { d in
      guard let title = d["title"] as? String, !title.isEmpty else { return nil }
      let artist = ((d["artist"] as? [String: Any])?["name"] as? String) ?? "Artista"
      let albumObj = d["album"] as? [String: Any]
      let albumTitle = (albumObj?["title"] as? String) ?? ""
      var cover = (albumObj?["cover_xl"] as? String) ?? (albumObj?["cover_big"] as? String) ?? ""
      if cover.contains("/cover//") { cover = "" }
      let dur = Self.double(d["duration"]) ?? 0
      let exp = (d["explicit_lyrics"] as? Bool) ?? false
      return Track(title: title, artist: artist, album: albumTitle, duration: dur, artworkURL: cover, sourceService: "Playlist", isExplicit: exp)
    }
    if !tracks.isEmpty {
      playlistCache[deezerId] = (tracks, Date())
    }
    return tracks
  }

  // MARK: - Mixes Personalizados (estilo Spotify Daily Mix / No Repeat)

  nonisolated static func buildPersonalizedMixes(
    mostPlayed: [Track],
    favorites: [Track],
    recent: [Track],
    topArtists: [String],
    feed: DiscoverFeed?
  ) -> [PersonalizedMix] {
    var mixes: [PersonalizedMix] = []
    let br = feed?.topBrazil ?? []
    let brHits = feed?.brazilianHits ?? []
    let gl = feed?.topGlobal ?? []

    if !mostPlayed.isEmpty {
      mixes.append(PersonalizedMix(
        id: "mix_norepeat",
        title: "No Repeat",
        subtitle: "As que você não para de ouvir",
        tag: "SEU SOM",
        icon: "repeat",
        hexA: 0xFF7BA9,
        hexB: 0xAD8CFF,
        tracks: Array(mostPlayed.prefix(30))
      ))
    }

    let pool = dedupeTracks(Array(mostPlayed.prefix(60)) + Array(favorites.prefix(60)) + Array(recent.prefix(40)) + br + gl)

    if let firstArtist = topArtists.first {
      let matching = pool.filter {
        DiscText.artistMatches($0.artist, firstArtist)
      }
      let matchIds = Set(matching.map(\.id))
      let extra = br.filter { !matchIds.contains($0.id) }.prefix(10)
      let tracks = dedupeTracks(matching + extra)
      if !tracks.isEmpty {
        mixes.append(PersonalizedMix(
          id: "mix_daily1",
          title: "Mix Diário 1",
          subtitle: "\(firstArtist) e sons na mesma vibe",
          tag: "PARA VOCÊ",
          icon: "sparkles",
          hexA: 0x7CC8FF,
          hexB: 0x6366F1,
          tracks: Array(tracks.prefix(25))
        ))
      }
    }

    if topArtists.count >= 2 {
      let second = topArtists[1]
      let matching = pool.filter {
        DiscText.artistMatches($0.artist, second)
      }
      let matchIds = Set(matching.map(\.id))
      let extra = gl.filter { !matchIds.contains($0.id) }.prefix(10)
      let tracks = dedupeTracks(matching + extra)
      if !tracks.isEmpty {
        mixes.append(PersonalizedMix(
          id: "mix_daily2",
          title: "Mix Diário 2",
          subtitle: "Com \(second) e sucessos",
          tag: "DESCOBERTA",
          icon: "waveform.path.ecg",
          hexA: 0xFFB27A,
          hexB: 0xE0457B,
          tracks: Array(tracks.prefix(25))
        ))
      }
    }

    if !favorites.isEmpty {
      mixes.append(PersonalizedMix(
        id: "mix_favorites",
        title: "Radar de Curtidas",
        subtitle: "Suas favoritas em sequência",
        tag: "CURTIDAS",
        icon: "heart.fill",
        hexA: 0xF43F5E,
        hexB: 0x9F1239,
        tracks: Array(favorites.prefix(30))
      ))
    }

    if !brHits.isEmpty || !br.isEmpty {
      mixes.append(PersonalizedMix(
        id: "mix_br_radar",
        title: "Radar Brasil",
        subtitle: brHits.isEmpty ? "O que mais toca no Brasil hoje" : "Só música brasileira que está tocando",
        tag: "BRASIL",
        icon: "flame.fill",
        hexA: 0x10B981,
        hexB: 0x047857,
        tracks: Array((brHits.isEmpty ? br : brHits).prefix(30))
      ))
    }

    if !gl.isEmpty {
      let discovery = dedupeTracks(gl)
      mixes.append(PersonalizedMix(
        id: "mix_global_wave",
        title: "Onda Global",
        subtitle: "Os hits que o mundo está ouvindo",
        tag: "MUNDO",
        icon: "globe.americas.fill",
        hexA: 0x06B6D4,
        hexB: 0x3B82F6,
        tracks: Array(discovery.prefix(30))
      ))
    }

    return mixes
  }

  // MARK: - Private Fetchers

  private func fetchAppleCountrySongs(country: String) async -> [Track] {
    guard let obj = await DiscNet.json("https://rss.marketingtools.apple.com/api/v2/\(country)/music/most-played/50/songs.json", timeout: 6, retries: 2) as? [String: Any],
          let results = (obj["feed"] as? [String: Any])?["results"] as? [[String: Any]] else { return [] }
    return results.compactMap { r in
      guard let title = r["name"] as? String else { return nil }
      return Track(
        title: title,
        artist: (r["artistName"] as? String) ?? "",
        artworkURL: Self.upscaleApple((r["artworkUrl100"] as? String) ?? ""),
        sourceService: "Apple \(country.uppercased())",
        isExplicit: ((r["contentAdvisoryRating"] as? String) ?? "").lowercased().hasPrefix("explic")
      )
    }
  }

  private func fetchAppleCountryAlbums(country: String) async -> [AlbumShowcase] {
    guard let obj = await DiscNet.json("https://rss.marketingtools.apple.com/api/v2/\(country)/music/most-played/25/albums.json", timeout: 6, retries: 2) as? [String: Any],
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
        id: "alb_\(idStr)",
        title: title,
        artist: (r["artistName"] as? String) ?? "",
        artworkURL: Self.upscaleApple((r["artworkUrl100"] as? String) ?? ""),
        year: DiscText.year(from: date),
        genre: genre,
        tracks: [],
        releaseDate: date,
        kind: kind,
        deezerId: nil,
        itunesId: Int(idStr)
      )
    }
  }

  /// YouTube Music Charts do país: artistas em alta (ranqueados) + faixas da playlist "<País>: 20 vídeos em alta".
  private func fetchYTMCountryCharts(ytmCode: String) async -> (artistNames: [String], tracks: [Track]) {
    let body: [String: Any] = [
      "context": Self.ytContext,
      "browseId": "FEmusic_charts",
      "formData": ["selectedValues": [ytmCode]]
    ]
    guard let charts = await DiscNet.postJSON("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                                              body: body, headers: Self.ytHeaders) else {
      return ([], [])
    }
    var artistNames: [String] = []
    var trendingId: String?
    func walk(_ n: Any) {
      if let d = n as? [String: Any] {
        if let r = d["musicResponsiveListItemRenderer"] as? [String: Any] {
          let cols = r["flexColumns"] as? [[String: Any]] ?? []
          let hasVideo = ((r["playlistItemData"] as? [String: Any])?["videoId"] as? String) != nil
          if !hasVideo, let c0 = cols.first.map({ Self.ytmColText($0) }), !c0.isEmpty { artistNames.append(c0) }
          return
        }
        if trendingId == nil, let r = d["musicTwoRowItemRenderer"] as? [String: Any],
           let runs = (r["title"] as? [String: Any])?["runs"] as? [[String: Any]],
           let text = runs.first?["text"] as? String, text.lowercased().contains("vídeos em alta"),
           let bid = ((r["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String {
          trendingId = bid
        }
        for v in d.values { walk(v) }
      } else if let a = n as? [Any] {
        for v in a { walk(v) }
      }
    }
    walk(charts)

    var tracks: [Track] = []
    if let pid = trendingId,
       let obj = await DiscNet.postJSON("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                                        body: ["context": Self.ytContext, "browseId": pid], headers: Self.ytHeaders) {
      func walkTracks(_ n: Any) {
        if let d = n as? [String: Any] {
          if let r = d["musicResponsiveListItemRenderer"] as? [String: Any] {
            if let vid = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String,
               let cols = r["flexColumns"] as? [[String: Any]], cols.count >= 2 {
              let title = Self.ytmColText(cols[0]), artist = Self.ytmColText(cols[1])
              var thumb = ""
              if let th = (((r["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] {
                thumb = (th.last?["url"] as? String) ?? ""
              }
              if !title.isEmpty { tracks.append(Track(videoId: vid, title: title, artist: artist, artworkURL: thumb, sourceService: "YouTube Music")) }
            }
            return
          }
          for v in d.values { walkTracks(v) }
        } else if let a = n as? [Any] {
          for v in a { walkTracks(v) }
        }
      }
      walkTracks(obj)
    }
    var seen = Set<String>()
    return (artistNames, tracks.filter { seen.insert($0.id).inserted })
  }

  private func resolveArtists(names: [String], limit: Int) async -> [ArtistInfo] {
    var seen = Set<String>()
    var clean: [(Int, String)] = []
    for n in names {
      let base = DiscText.searchArtist(n)
      let key = DiscText.normalize(base)
      guard !key.isEmpty, seen.insert(key).inserted else { continue }
      clean.append((clean.count + 1, base))
      if clean.count >= limit { break }
    }
    let resolved: [(Int, ArtistInfo)] = await withTaskGroup(of: (Int, ArtistInfo)?.self) { group in
      for (rank, name) in clean {
        group.addTask {
          if let hit = await self.lookupDeezerArtist(name: name) {
            var a = hit
            a.rank = rank
            return (rank, a)
          }
          return (rank, ArtistInfo(id: "art_\(DiscText.normalize(name))", name: name, pictureURL: "", deezerId: nil, fans: nil, rank: rank))
        }
      }
      var out: [(Int, ArtistInfo)] = []
      for await item in group { if let item { out.append(item) } }
      return out
    }
    return resolved.sorted { $0.0 < $1.0 }.map(\.1)
  }

  private func lookupDeezerArtist(name: String) async -> ArtistInfo? {
    guard let obj = await DiscNet.json("https://api.deezer.com/search/artist?q=\(DiscNet.enc(name))&limit=4") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return nil }
    let target = DiscText.normalize(name)
    let hit = data.first { DiscText.normalize(($0["name"] as? String) ?? "") == target }
      ?? data.first { DiscText.artistMatches(($0["name"] as? String) ?? "", name) }
    guard let d = hit, let id = Self.int(d["id"]), let aname = d["name"] as? String else { return nil }
    var pic = (d["picture_xl"] as? String) ?? (d["picture_big"] as? String) ?? ""
    if pic.contains("/images/artist//") { pic = "" }
    return ArtistInfo(id: "dz_\(id)", name: aname, pictureURL: pic, deezerId: id, fans: Self.int(d["nb_fan"]), rank: nil)
  }

  private static func primaryArtist(_ s: String) -> String {
    let seps = [",", " feat", " ft.", " x ", " part.", " (", " com "]
    var out = s
    for sep in seps {
      if let r = out.range(of: sep, options: .caseInsensitive) { out = String(out[..<r.lowerBound]) }
    }
    return out.replacingOccurrences(of: " - Topic", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func dedupeTracks(_ tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { seen.insert($0.id).inserted }
  }

  private static func upscaleApple(_ url: String) -> String {
    var u = url
    if let r = u.range(of: #"\d{2,4}x\d{2,4}(bb|cc)"#, options: .regularExpression) {
      u.replaceSubrange(r, with: "1000x1000bb")
    }
    return u
  }

  private static func ytmColText(_ col: [String: Any]) -> String {
    let runs = ((col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
    return runs.compactMap { $0["text"] as? String }.joined()
  }

  private static func int(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let s = v as? String { return Int(s) }
    if let d = v as? Double { return Int(d) }
    return nil
  }

  private static func double(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let s = v as? String { return Double(s) }
    return nil
  }
}
