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

  func countryChart(for country: ChartCountry, force: Bool = false) async -> CountryChartBundle {
    if !force, let hit = countryCache[country.code], Date().timeIntervalSince(hit.updatedAt) < ttl {
      return hit
    }
    let disk = DiscNet.caches("lume_country_\(country.code).json")
    if !force,
       let data = try? Data(contentsOf: disk),
       let saved = try? JSONDecoder().decode(CountryChartBundle.self, from: data),
       Date().timeIntervalSince(saved.updatedAt) < ttl,
       !saved.topSongs.isEmpty {
      countryCache[country.code] = saved
      return saved
    }

    async let songsTask = fetchAppleCountrySongs(country: country.code)
    async let albumsTask = fetchAppleCountryAlbums(country: country.code)
    async let ytmTask = fetchYTMCountryCharts(ytmCode: country.ytmCode)

    let (songs, albums, ytm) = await (songsTask, albumsTask, ytmTask)

    var artists: [ArtistInfo] = []
    if !ytm.artistNames.isEmpty {
      artists = await resolveArtists(names: ytm.artistNames, limit: 16)
    }
    if artists.isEmpty {
      let fromSongs = songs.map { Self.primaryArtist($0.artist) }
      artists = await resolveArtists(names: fromSongs, limit: 16)
    }

    let bundle = CountryChartBundle(
      country: country,
      topSongs: songs,
      topAlbums: albums,
      topArtists: artists,
      trending: ytm.tracks,
      updatedAt: Date()
    )
    if !songs.isEmpty {
      countryCache[country.code] = bundle
      if let encoded = try? JSONEncoder().encode(bundle) {
        try? encoded.write(to: disk, options: .atomic)
      }
    }
    return bundle
  }

  // MARK: - Hub de Gênero Musical

  func genreHub(for genre: MusicGenre, force: Bool = false) async -> GenreHubBundle {
    if !force, let hit = genreCache[genre.id], Date().timeIntervalSince(hit.updatedAt) < ttl {
      return hit
    }
    let disk = DiscNet.caches("lume_genre_\(genre.id).json")
    if !force,
       let data = try? Data(contentsOf: disk),
       let saved = try? JSONDecoder().decode(GenreHubBundle.self, from: data),
       Date().timeIntervalSince(saved.updatedAt) < ttl,
       !saved.topSongs.isEmpty {
      genreCache[genre.id] = saved
      return saved
    }

    async let appleSongsTask = fetchAppleGenreSongs(genre: genre)
    async let appleAlbumsTask = fetchAppleGenreAlbums(genre: genre)
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
    let gl = feed?.topGlobal ?? []
    let tr = feed?.trending ?? []

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

    if let firstArtist = topArtists.first {
      let matching = (mostPlayed + favorites + recent + br + gl).filter {
        DiscText.artistMatches($0.artist, firstArtist)
      }
      let extra = br.filter { !matching.contains($0) }.prefix(10)
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
      let matching = (mostPlayed + favorites + recent + br + gl).filter {
        DiscText.artistMatches($0.artist, second)
      }
      let extra = gl.filter { !matching.contains($0) }.prefix(10)
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

    if !br.isEmpty {
      mixes.append(PersonalizedMix(
        id: "mix_br_radar",
        title: "Radar Brasil",
        subtitle: "O que domina o país hoje",
        tag: "BRASIL",
        icon: "flame.fill",
        hexA: 0x10B981,
        hexB: 0x047857,
        tracks: Array(br.prefix(30))
      ))
    }

    if !tr.isEmpty || !gl.isEmpty {
      let discovery = dedupeTracks(tr + gl)
      mixes.append(PersonalizedMix(
        id: "mix_global_wave",
        title: "Onda Global",
        subtitle: "Hits subindo no mundo inteiro",
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
    var tracks: [Track] = []
    func walk(_ n: Any) {
      if let d = n as? [String: Any] {
        if let r = d["musicResponsiveListItemRenderer"] as? [String: Any] {
          let vid = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String
          let cols = r["flexColumns"] as? [[String: Any]] ?? []
          let c0 = cols.indices.contains(0) ? Self.ytmColText(cols[0]) : ""
          let c1 = cols.indices.contains(1) ? Self.ytmColText(cols[1]) : ""
          if let vid, !vid.isEmpty, !c0.isEmpty {
            var thumb = ""
            if let th = (((r["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] {
              thumb = (th.last?["url"] as? String) ?? ""
            }
            tracks.append(Track(videoId: vid, title: c0, artist: c1, artworkURL: thumb, sourceService: "YouTube Music"))
          } else if !c0.isEmpty {
            artistNames.append(c0)
          }
          return
        }
        for v in d.values { walk(v) }
      } else if let a = n as? [Any] {
        for v in a { walk(v) }
      }
    }
    walk(charts)
    return (artistNames, tracks)
  }

  private func fetchAppleGenreSongs(genre: MusicGenre) async -> [Track] {
    guard let gid = genre.appleGenreId else { return [] }
    guard let obj = await DiscNet.json("https://itunes.apple.com/\(genre.appleCountry)/rss/topsongs/limit=30/genre=\(gid)/json", timeout: 6, retries: 1) as? [String: Any],
          let feed = obj["feed"] as? [String: Any],
          let entries = feed["entry"] as? [[String: Any]] else { return [] }
    return entries.compactMap { e in
      guard let title = (e["im:name"] as? [String: Any])?["label"] as? String,
            let artist = (e["im:artist"] as? [String: Any])?["label"] as? String else { return nil }
      let imgs = (e["im:image"] as? [[String: Any]]) ?? []
      let rawImg = (imgs.last?["label"] as? String) ?? ""
      let art = Self.upscaleApple(rawImg)
      let album = ((e["im:collection"] as? [String: Any])?["im:name"] as? [String: Any])?["label"] as? String ?? ""
      return Track(title: title, artist: artist, album: album, artworkURL: art, sourceService: genre.title)
    }
  }

  private func fetchAppleGenreAlbums(genre: MusicGenre) async -> [AlbumShowcase] {
    guard let gid = genre.appleGenreId else { return [] }
    guard let obj = await DiscNet.json("https://itunes.apple.com/\(genre.appleCountry)/rss/topalbums/limit=16/genre=\(gid)/json", timeout: 6, retries: 1) as? [String: Any],
          let feed = obj["feed"] as? [String: Any],
          let entries = feed["entry"] as? [[String: Any]] else { return [] }
    return entries.compactMap { e in
      guard let title = (e["im:name"] as? [String: Any])?["label"] as? String,
            let artist = (e["im:artist"] as? [String: Any])?["label"] as? String else { return nil }
      let idAttrs = (e["id"] as? [String: Any])?["attributes"] as? [String: Any]
      let idStr = (idAttrs?["im:id"] as? String) ?? Track.stableId(title: title, artist: artist)
      let imgs = (e["im:image"] as? [[String: Any]]) ?? []
      let art = Self.upscaleApple((imgs.last?["label"] as? String) ?? "")
      let release = ((e["im:releaseDate"] as? [String: Any])?["label"] as? String)
      return AlbumShowcase(
        id: "alb_\(idStr)",
        title: title,
        artist: artist,
        artworkURL: art,
        year: DiscText.year(from: release),
        genre: genre.title,
        tracks: [],
        releaseDate: release.map { String($0.prefix(10)) },
        kind: "Álbum",
        deezerId: nil,
        itunesId: Int(idStr)
      )
    }
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
