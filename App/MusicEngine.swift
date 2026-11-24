import Foundation

/// Core music discovery, search, live charts, stream resolution, autoplay radio,
/// and official Apple Music animated artwork (.m3u8) fetcher.
actor MusicEngine {
  static let shared = MusicEngine()

  static let androidUserAgent = "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
  static let iosUserAgent = "com.google.ios.youtube/21.02.3 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
  private static let webUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

  struct ResolvedStream: Sendable {
    let url: URL
    let headers: [String: String]
    let bitrate: Int
    let expiresAt: Date
  }

  private var streamCache: [String: ResolvedStream] = [:]
  private var animatedCache: [String: String] = [:] // key -> m3u8 URL or "" for none
  private var animatedLoaded = false

  private let session: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 7
    cfg.timeoutIntervalForResource = 16
    cfg.urlCache = URLCache(memoryCapacity: 40 * 1024 * 1024, diskCapacity: 150 * 1024 * 1024)
    return URLSession(configuration: cfg)
  }()

  // MARK: - Persistent animated artwork cache

  private var animatedCacheURL: URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("lume_music_animated_art.json")
  }

  private func loadAnimatedCacheIfNeeded() {
    guard !animatedLoaded else { return }
    animatedLoaded = true
    if let data = try? Data(contentsOf: animatedCacheURL),
       let map = try? JSONDecoder().decode([String: String].self, from: data) {
      animatedCache = map
    }
  }

  private func saveAnimatedCache() {
    if let data = try? JSONEncoder().encode(animatedCache) {
      try? data.write(to: animatedCacheURL, options: .atomic)
    }
  }

  // MARK: - Live Charts & New Releases (Auto-updated daily)

  struct HomeFeed: Codable, Sendable {
    let topBrazil: [Track]
    let newAlbums: [AlbumShowcase]
    let globalHits: [Track]
  }

  private var feedCacheURL: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("lume_music_home_feed.json")
  }

  func cachedHomeFeed() -> HomeFeed? {
    guard let data = try? Data(contentsOf: feedCacheURL),
          let saved = try? JSONDecoder().decode(HomeFeed.self, from: data),
          !saved.topBrazil.isEmpty else { return nil }
    return saved
  }

  func fetchHomeFeed() async -> HomeFeed {
    async let brSongs = fetchITunesTopSongsBR()
    async let brAlbums = fetchITunesNewAlbumsBR()
    async let dzAlbums = fetchDeezerTopAlbums()
    async let deezer = fetchDeezerTopTracks()
    let (s, a, da, d) = await (brSongs, brAlbums, dzAlbums, deezer)

    var mergedAlbums = a
    var seenKeys = Set(a.map { $0.title.lowercased() })
    for item in da where !seenKeys.contains(item.title.lowercased()) {
      seenKeys.insert(item.title.lowercased())
      mergedAlbums.append(item)
    }

    let feed = HomeFeed(
      topBrazil: s.isEmpty ? d : s,
      newAlbums: mergedAlbums,
      globalHits: d.isEmpty ? s : d
    )
    if !feed.topBrazil.isEmpty, let data = try? JSONEncoder().encode(feed) {
      try? data.write(to: feedCacheURL, options: .atomic)
    }
    return feed
  }

  private func fetchITunesTopSongsBR() async -> [Track] {
    guard let url = URL(string: "https://rss.marketingtools.apple.com/api/v2/br/music/most-played/25/songs.json") else { return [] }
    do {
      let (data, _) = try await session.data(from: url)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let feed = root["feed"] as? [String: Any],
            let results = feed["results"] as? [[String: Any]] else { return [] }
      return results.compactMap { item -> Track? in
        guard let name = item["name"] as? String, let artist = item["artistName"] as? String else { return nil }
        let rawArt = (item["artworkUrl100"] as? String) ?? ""
        let art = rawArt.replacingOccurrences(of: "100x100bb", with: "1400x1400bb")
        let explicit = (item["contentAdvisoryRating"] as? String)?.lowercased().contains("expl") == true
        return Track(title: name, artist: artist, album: "", duration: 0, artworkURL: art, sourceService: "Top Brasil", isExplicit: explicit)
      }
    } catch { return [] }
  }

  private func fetchITunesNewAlbumsBR() async -> [AlbumShowcase] {
    guard let url = URL(string: "https://rss.marketingtools.apple.com/api/v2/br/music/most-played/15/albums.json") else { return [] }
    do {
      let (data, _) = try await session.data(from: url)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let feed = root["feed"] as? [String: Any],
            let results = feed["results"] as? [[String: Any]] else { return [] }
      return results.compactMap { item -> AlbumShowcase? in
        guard let name = item["name"] as? String,
              let artist = item["artistName"] as? String else { return nil }
        let idStr = (item["id"] as? String) ?? (item["id"] as? Int).map(String.init) ?? Track.stableId(title: name, artist: artist)
        let rawArt = (item["artworkUrl100"] as? String) ?? ""
        let art = rawArt.replacingOccurrences(of: "100x100bb", with: "1400x1400bb")
        let release = String(((item["releaseDate"] as? String) ?? "").prefix(4))
        let genre = ((item["genres"] as? [[String: Any]])?.first?["name"] as? String) ?? "Lançamento"
        return AlbumShowcase(id: "alb_\(idStr)", title: name, artist: artist, artworkURL: art, animatedArtworkURL: nil, year: release, genre: genre, tracks: [])
      }
    } catch { return [] }
  }

  private func fetchDeezerTopAlbums() async -> [AlbumShowcase] {
    guard let url = URL(string: "https://api.deezer.com/chart/0/albums?limit=14") else { return [] }
    do {
      let (data, _) = try await session.data(from: url)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["data"] as? [[String: Any]] else { return [] }
      return items.compactMap { it -> AlbumShowcase? in
        guard let title = it["title"] as? String,
              let artistObj = it["artist"] as? [String: Any],
              let artist = artistObj["name"] as? String else { return nil }
        let idStr = (it["id"] as? Int).map(String.init) ?? Track.stableId(title: title, artist: artist)
        let art = (it["cover_xl"] as? String) ?? (it["cover_big"] as? String) ?? ""
        return AlbumShowcase(id: "dzalb_\(idStr)", title: title, artist: artist, artworkURL: art, animatedArtworkURL: nil, year: "2026", genre: "Em Alta", tracks: [])
      }
    } catch { return [] }
  }

  func fetchAlbumTracks(albumTitle: String, artist: String, fallbackArtwork: String) async -> [Track] {
    let q = "\(albumTitle) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    guard let url = URL(string: "https://itunes.apple.com/search?term=\(q)&entity=album&country=br&limit=1") else { return [] }
    do {
      let (data, _) = try await session.data(from: url)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = root["results"] as? [[String: Any]],
            let cid = results.first?["collectionId"] as? Int,
            let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=\(cid)&entity=song&country=br") else {
        return await searchSongs(query: "\(albumTitle) \(artist)", limit: 12)
      }
      let (ldata, _) = try await session.data(from: lookupURL)
      guard let lroot = try JSONSerialization.jsonObject(with: ldata) as? [String: Any],
            let items = lroot["results"] as? [[String: Any]] else { return [] }
      let songs = items.compactMap { it -> Track? in
        guard (it["wrapperType"] as? String) == "track",
              let name = it["trackName"] as? String,
              let artName = it["artistName"] as? String else { return nil }
        let ms = (it["trackTimeMillis"] as? Double) ?? 0
        let rawArt = (it["artworkUrl100"] as? String) ?? fallbackArtwork
        let art = rawArt.replacingOccurrences(of: "100x100bb", with: "1400x1400bb")
        let alb = (it["collectionName"] as? String) ?? albumTitle
        return Track(title: name, artist: artName, album: alb, duration: ms / 1000.0, artworkURL: art, sourceService: "Álbum")
      }
      if !songs.isEmpty { return songs }
      return await searchSongs(query: "\(albumTitle) \(artist)", limit: 12)
    } catch {
      return await searchSongs(query: "\(albumTitle) \(artist)", limit: 12)
    }
  }

  private func fetchDeezerTopTracks() async -> [Track] {
    guard let url = URL(string: "https://api.deezer.com/chart/0/tracks?limit=25") else { return [] }
    do {
      let (data, _) = try await session.data(from: url)
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["data"] as? [[String: Any]] else { return [] }
      return items.compactMap { it -> Track? in
        guard let title = it["title"] as? String,
              let artistObj = it["artist"] as? [String: Any],
              let artist = artistObj["name"] as? String else { return nil }
        let albumObj = it["album"] as? [String: Any]
        let album = (albumObj?["title"] as? String) ?? ""
        let art = (albumObj?["cover_xl"] as? String) ?? (albumObj?["cover_big"] as? String) ?? ""
        let dur = (it["duration"] as? Double) ?? 0
        let exp = (it["explicit_lyrics"] as? Bool) ?? false
        return Track(title: title, artist: artist, album: album, duration: dur, artworkURL: art, sourceService: "Chart", isExplicit: exp)
      }
    } catch { return [] }
  }

  // MARK: - YouTube Music InnerTube Search & Radio

  func searchSongs(query: String, limit: Int = 20) async -> [Track] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let url = URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false") else { return [] }
    let payload: [String: Any] = [
      "context": [
        "client": [
          "clientName": "WEB_REMIX",
          "clientVersion": "1.20250101.01.00",
          "hl": "pt",
          "gl": "BR"
        ]
      ],
      "query": trimmed,
      "params": "EgWKAQIIAWoMEAMQBBAJEAoQBRAV" // Songs filter
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
    req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

    do {
      let (data, _) = try await session.data(for: req)
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
      let parsed = Self.extractResponsiveListTracks(from: json, source: "YouTube Music")
      if !parsed.isEmpty { return Array(parsed.prefix(limit)) }
    } catch {}
    // Fallback without strict songs filter
    return await searchSongsBroad(query: trimmed, limit: limit)
  }

  private func searchSongsBroad(query: String, limit: Int) async -> [Track] {
    guard let url = URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false") else { return [] }
    let payload: [String: Any] = [
      "context": ["client": ["clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "pt", "gl": "BR"]],
      "query": query
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
    req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
    do {
      let (data, _) = try await session.data(for: req)
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
      return Array(Self.extractResponsiveListTracks(from: json, source: "YouTube Music").prefix(limit))
    } catch { return [] }
  }

  func fetchRadioQueue(for videoId: String, limit: Int = 20) async -> [Track] {
    guard let url = URL(string: "https://music.youtube.com/youtubei/v1/next?prettyPrint=false") else { return [] }
    let payload: [String: Any] = [
      "videoId": videoId,
      "playlistId": "RDAMVM\(videoId)",
      "isAudioOnly": true,
      "context": ["client": ["clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "pt", "gl": "BR"]]
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
    req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
    do {
      let (data, _) = try await session.data(for: req)
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
      let tracks = Self.extractPanelVideoTracks(from: json).filter { $0.videoId != videoId }
      return Array(tracks.prefix(limit))
    } catch { return [] }
  }

  func fetchYTMPlaylist(listId: String) async -> (name: String, tracks: [Track]) {
    let browseId = listId.hasPrefix("VL") ? listId : "VL\(listId)"
    guard let url = URL(string: "https://music.youtube.com/youtubei/v1/browse?prettyPrint=false") else { return ("Playlist", []) }
    let payload: [String: Any] = [
      "browseId": browseId,
      "context": ["client": ["clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "pt", "gl": "BR"]]
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
    req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
    do {
      let (data, _) = try await session.data(for: req)
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ("YouTube Music", []) }
      let tracks = Self.extractResponsiveListTracks(from: json, source: "YouTube Music")
      let title = Self.extractFirstTitle(from: json) ?? "Playlist YouTube Music"
      return (title, tracks)
    } catch { return ("YouTube Music", []) }
  }

  // MARK: - VideoId + Direct Playable Audio Stream Resolver (IOS Client)

  func resolveVideoId(for track: Track) async -> String? {
    if let vid = track.videoId, vid.count == 11 { return vid }
    let hits = await searchSongs(query: track.searchQuery, limit: 5)
    if let best = hits.first(where: { $0.videoId != nil }) {
      return best.videoId
    }
    return nil
  }

  func invalidateStream(videoId: String) {
    streamCache.removeValue(forKey: videoId)
  }

  func resolveStream(videoId: String) async -> ResolvedStream? {
    if let cached = streamCache[videoId], cached.expiresAt > Date().addingTimeInterval(60) {
      return cached
    }
    // Primary: ANDROID client progressive MP4 (itag 18) — verified HTTP 200/206 past 1MB directly in native iOS AVPlayer!
    if let resolved = await requestPlayerStream(
      videoId: videoId,
      client: [
        "clientName": "ANDROID",
        "clientVersion": "20.10.38",
        "osName": "Android",
        "osVersion": "14",
        "androidSdkVersion": 34,
        "hl": "pt",
        "gl": "BR"
      ],
      userAgent: Self.androidUserAgent
    ) {
      streamCache[videoId] = resolved
      return resolved
    }
    // Fallback: IOS client progressive formats / HLS
    if let resolved = await requestPlayerStream(
      videoId: videoId,
      client: [
        "clientName": "IOS",
        "clientVersion": "21.02.3",
        "deviceMake": "Apple",
        "deviceModel": "iPhone16,2",
        "osName": "iPhone",
        "osVersion": "18.3.2.22D82",
        "hl": "pt",
        "gl": "BR"
      ],
      userAgent: Self.iosUserAgent
    ) {
      streamCache[videoId] = resolved
      return resolved
    }
    return nil
  }

  private func requestPlayerStream(videoId: String, client: [String: Any], userAgent: String) async -> ResolvedStream? {
    guard let url = URL(string: "https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false") else { return nil }
    let payload: [String: Any] = [
      "videoId": videoId,
      "context": ["client": client],
      "contentCheckOk": true,
      "racyCheckOk": true
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

    do {
      let (data, _) = try await session.data(for: req)
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sd = json["streamingData"] as? [String: Any] else { return nil }

      // 1. Progressive formats (itag 18 MP4/AAC-LC) — 100% playable natively in AVPlayer with zero PO-token 403!
      let combined = (sd["formats"] as? [[String: Any]]) ?? []
      let preferredProgressive = combined.first(where: { ($0["itag"] as? Int) == 18 && ($0["url"] as? String) != nil })
        ?? combined.first(where: { (($0["mimeType"] as? String) ?? "").contains("mp4") && ($0["url"] as? String) != nil })
      if let fmt = preferredProgressive, let urlStr = fmt["url"] as? String, let streamURL = URL(string: urlStr) {
        let br = max(96000, (fmt["bitrate"] as? Int) ?? 128000)
        return ResolvedStream(url: streamURL, headers: [:], bitrate: br, expiresAt: Date().addingTimeInterval(40 * 60))
      }

      // 2. HLS manifest if provided
      if let hls = sd["hlsManifestUrl"] as? String, let hlsURL = URL(string: hls) {
        return ResolvedStream(url: hlsURL, headers: [:], bitrate: 128000, expiresAt: Date().addingTimeInterval(25 * 60))
      }
    } catch {}
    return nil
  }

  // MARK: - Official Apple Music Animated Artwork (.m3u8)

  func fetchAnimatedArtwork(title: String, artist: String, album: String) async -> String? {
    loadAnimatedCacheIfNeeded()
    let key = Track.stableId(title: album.isEmpty ? title : album, artist: artist)
    if let hit = animatedCache[key] {
      return hit.isEmpty ? nil : hit
    }
    let term = (album.isEmpty ? "\(title) \(artist)" : "\(album) \(artist)")
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    guard let searchURL = URL(string: "https://itunes.apple.com/search?term=\(term)&entity=album&country=br&limit=1") else { return nil }
    do {
      let (sdata, _) = try await session.data(from: searchURL)
      guard let sroot = try JSONSerialization.jsonObject(with: sdata) as? [String: Any],
            let results = sroot["results"] as? [[String: Any]],
            let pageStr = results.first?["collectionViewUrl"] as? String,
            let pageURL = URL(string: pageStr) else {
        animatedCache[key] = ""
        saveAnimatedCache()
        return nil
      }
      var req = URLRequest(url: pageURL)
      req.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
      let (pdata, _) = try await session.data(for: req)
      guard let html = String(data: pdata, encoding: .utf8) else { return nil }
      let pattern = #"https://mvod\.itunes\.apple\.com/[^"'\\<>]+\.m3u8"#
      if let regex = try? NSRegularExpression(pattern: pattern) {
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range).compactMap { m -> String? in
          Range(m.range, in: html).map { String(html[$0]) }
        }
        // Prefer standard looping artwork stream
        if let best = matches.first(where: { $0.contains("default.m3u8") }) ?? matches.first {
          animatedCache[key] = best
          saveAnimatedCache()
          return best
        }
      }
      animatedCache[key] = ""
      saveAnimatedCache()
    } catch {}
    return nil
  }

  // MARK: - InnerTube JSON Parsers (Pure, resilient traversal)

  private static func extractResponsiveListTracks(from obj: Any, source: String) -> [Track] {
    var out: [Track] = []
    var seen = Set<String>()
    func walk(_ node: Any) {
      if let dict = node as? [String: Any] {
        if let r = dict["musicResponsiveListItemRenderer"] as? [String: Any],
           let tr = parseResponsiveItem(r, source: source),
           let vid = tr.videoId, !seen.contains(vid) {
          seen.insert(vid)
          out.append(tr)
          return
        }
        for (_, v) in dict { walk(v) }
      } else if let arr = node as? [Any] {
        for item in arr { walk(item) }
      }
    }
    walk(obj)
    return out
  }

  private static func parseResponsiveItem(_ r: [String: Any], source: String) -> Track? {
    // Video ID from playlistItemData or overlay playNavigationEndpoint
    var vid = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String
    if vid == nil {
      vid = findStringKey("videoId", in: r)
    }
    guard let videoId = vid, videoId.count == 11 else { return nil }

    let cols = (r["flexColumns"] as? [[String: Any]]) ?? []
    let title = textOfColumn(cols.first)
    guard !title.isEmpty else { return nil }

    let subRuns = runsOfColumn(cols.count > 1 ? cols[1] : nil)
    let cleanParts = subRuns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && $0 != "•" && $0 != "·" && !$0.lowercased().hasPrefix("música") && !$0.lowercased().hasPrefix("song") && !$0.lowercased().hasPrefix("vídeo") && !$0.lowercased().hasPrefix("video") }

    var artist = ""
    var album = ""
    var duration: Double = 0
    for part in cleanParts {
      if let d = parseClock(part) {
        duration = d
      } else if part.lowercased().contains("reproduç") || part.lowercased().contains("plays") || part.lowercased().contains("visualizaç") {
        continue
      } else if artist.isEmpty {
        artist = part
      } else if album.isEmpty {
        album = part
      }
    }
    if duration == 0, let fixedCols = r["fixedColumns"] as? [[String: Any]] {
      for fc in fixedCols {
        if let d = parseClock(textOfColumn(fc)) { duration = d; break }
      }
    }

    var thumb = bestThumbnail(in: r)
    if thumb.contains("googleusercontent.com") {
      thumb = upscaleGoogleThumb(thumb)
    }
    if thumb.isEmpty {
      thumb = "https://i.ytimg.com/vi/\(videoId)/maxresdefault.jpg"
    }

    return Track(
      id: videoId,
      videoId: videoId,
      title: title,
      artist: artist.isEmpty ? "Artista" : artist,
      album: album,
      duration: duration,
      artworkURL: thumb,
      sourceService: source
    )
  }

  private static func extractPanelVideoTracks(from obj: Any) -> [Track] {
    var out: [Track] = []
    var seen = Set<String>()
    func walk(_ node: Any) {
      if let dict = node as? [String: Any] {
        if let p = dict["playlistPanelVideoRenderer"] as? [String: Any],
           let vid = p["videoId"] as? String, vid.count == 11, !seen.contains(vid) {
          seen.insert(vid)
          let title = runsText(p["title"])
          let byRuns = runsArray(p["longBylineText"] ?? p["shortBylineText"])
            .filter { $0 != "•" && $0 != "·" && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
          let artist = byRuns.first ?? "Artista"
          let album = byRuns.count > 1 ? byRuns[1] : ""
          let dur = parseClock(runsText(p["lengthText"])) ?? 0
          var thumb = bestThumbnail(in: p)
          if thumb.contains("googleusercontent.com") { thumb = upscaleGoogleThumb(thumb) }
          if !title.isEmpty {
            out.append(Track(id: vid, videoId: vid, title: title, artist: artist, album: album, duration: dur, artworkURL: thumb, sourceService: "Rádio"))
          }
          return
        }
        for (_, v) in dict { walk(v) }
      } else if let arr = node as? [Any] {
        for item in arr { walk(item) }
      }
    }
    walk(obj)
    return out
  }

  private static func extractFirstTitle(from obj: Any) -> String? {
    if let dict = obj as? [String: Any] {
      if let hdr = dict["musicEditablePlaylistDetailHeaderRenderer"] ?? dict["musicDetailHeaderRenderer"] ?? dict["musicResponsiveHeaderRenderer"] {
        if let hdict = hdr as? [String: Any] {
          let t = runsText(hdict["title"])
          if !t.isEmpty { return t }
        }
      }
      for (_, v) in dict { if let found = extractFirstTitle(from: v) { return found } }
    } else if let arr = obj as? [Any] {
      for item in arr { if let found = extractFirstTitle(from: item) { return found } }
    }
    return nil
  }

  private static func textOfColumn(_ col: [String: Any]?) -> String {
    guard let col else { return "" }
    let inner = (col["musicResponsiveListItemFlexColumnRenderer"] ?? col["musicResponsiveListItemFixedColumnRenderer"]) as? [String: Any]
    return runsText(inner?["text"])
  }

  private static func runsOfColumn(_ col: [String: Any]?) -> [String] {
    guard let col else { return [] }
    let inner = col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
    return runsArray(inner?["text"])
  }

  private static func runsText(_ any: Any?) -> String {
    runsArray(any).joined()
  }

  private static func runsArray(_ any: Any?) -> [String] {
    guard let d = any as? [String: Any] else { return [] }
    if let runs = d["runs"] as? [[String: Any]] {
      return runs.compactMap { $0["text"] as? String }
    }
    if let simple = d["simpleText"] as? String { return [simple] }
    return []
  }

  private static func findStringKey(_ key: String, in obj: Any) -> String? {
    if let dict = obj as? [String: Any] {
      if let v = dict[key] as? String, !v.isEmpty { return v }
      for (_, v) in dict { if let f = findStringKey(key, in: v) { return f } }
    } else if let arr = obj as? [Any] {
      for item in arr { if let f = findStringKey(key, in: item) { return f } }
    }
    return nil
  }

  private static func bestThumbnail(in obj: Any) -> String {
    var bestURL = ""
    var bestW = -1
    func walk(_ node: Any) {
      if let dict = node as? [String: Any] {
        if let thumbs = dict["thumbnails"] as? [[String: Any]] {
          for t in thumbs {
            if let u = t["url"] as? String {
              let w = (t["width"] as? Int) ?? 0
              if w >= bestW { bestW = w; bestURL = u }
            }
          }
        }
        for (_, v) in dict { walk(v) }
      } else if let arr = node as? [Any] {
        for item in arr { walk(item) }
      }
    }
    walk(obj)
    return bestURL
  }

  private static func upscaleGoogleThumb(_ url: String) -> String {
    if let range = url.range(of: #"=w\d+-h\d+[^&]*"#, options: .regularExpression) {
      return url.replacingCharacters(in: range, with: "=w1200-h1200-l95-rj")
    }
    if let range = url.range(of: #"=s\d+[^&]*"#, options: .regularExpression) {
      return url.replacingCharacters(in: range, with: "=s1200")
    }
    return url
  }

  static func parseClock(_ s: String) -> Double? {
    let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = clean.split(separator: ":").compactMap { Int($0) }
    if parts.count == 2 { return Double(parts[0] * 60 + parts[1]) }
    if parts.count == 3 { return Double(parts[0] * 3600 + parts[1] * 60 + parts[2]) }
    return nil
  }
}
