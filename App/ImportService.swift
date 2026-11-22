import Foundation
import MediaPlayer

/// 1-click music & playlist importer supporting:
/// - Apple Music library directly on this iPhone (MediaPlayer)
/// - Spotify public playlists/albums via embed JSON (no login/API key)
/// - YouTube Music / YouTube playlists via InnerTube
/// - Apple Music & Amazon Music public links (metadata / serialized JSON)
/// - Plain text / M3U track lists ("Artista - Música")
actor ImportService {
  static let shared = ImportService()

  struct ImportResult: Sendable {
    let playlistName: String
    let sourceBadge: String
    let artworkURL: String
    let tracks: [Track]
  }

  // MARK: - 1. Local Apple Music Library on iPhone

  func importFromLocalAppleMusic() async throws -> [ImportResult] {
#if os(iOS)
    let status = await withCheckedContinuation { cont in
      MPMediaLibrary.requestAuthorization { st in cont.resume(returning: st) }
    }
    guard status == .authorized else {
      throw NSError(domain: "LumeMusic", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permita o acesso à Biblioteca de Mídia nos Ajustes do iPhone para importar do Apple Music."])
    }

    var results: [ImportResult] = []
    if let playlists = MPMediaQuery.playlists().collections {
      for pl in playlists {
        let name = (pl.value(forProperty: MPMediaPlaylistPropertyName) as? String) ?? "Playlist Apple Music"
        let tracks = pl.items.prefix(150).compactMap { item -> Track? in
          guard let title = item.title, !title.isEmpty else { return nil }
          return Track(
            title: title,
            artist: item.artist ?? item.albumArtist ?? "Artista",
            album: item.albumTitle ?? "",
            duration: item.playbackDuration,
            artworkURL: "",
            sourceService: "Apple Music"
          )
        }
        if !tracks.isEmpty {
          results.append(ImportResult(playlistName: name, sourceBadge: "Apple Music", artworkURL: "", tracks: tracks))
        }
      }
    }

    // Also include user's general Apple Music songs if no playlists or as a unified collection
    if let songs = MPMediaQuery.songs().items, !songs.isEmpty {
      let tracks = songs.prefix(200).compactMap { item -> Track? in
        guard let title = item.title, !title.isEmpty else { return nil }
        return Track(
          title: title,
          artist: item.artist ?? item.albumArtist ?? "Artista",
          album: item.albumTitle ?? "",
          duration: item.playbackDuration,
          artworkURL: "",
          sourceService: "Apple Music"
        )
      }
      if !tracks.isEmpty {
        results.insert(ImportResult(playlistName: "Minha Biblioteca Apple Music", sourceBadge: "Apple Music", artworkURL: "", tracks: tracks), at: 0)
      }
    }

    if results.isEmpty {
      throw NSError(domain: "LumeMusic", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nenhuma música encontrada na biblioteca local do Apple Music neste iPhone. Você também pode colar o link de uma playlist abaixo!"])
    }
    return results
#else
    return []
#endif
  }

  // MARK: - 2. Import by URL (Spotify, YouTube Music, Apple Music, Amazon Music)

  func importFromURL(_ rawURL: String) async throws -> ImportResult {
    let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
      throw NSError(domain: "LumeMusic", code: 3, userInfo: [NSLocalizedDescriptionKey: "Link inválido. Cole o link completo de uma playlist ou álbum."])
    }
    if host.contains("spotify.com") {
      return try await importSpotify(url: url)
    }
    if host.contains("youtube.com") || host.contains("youtu.be") {
      return try await importYouTube(url: url)
    }
    if host.contains("music.apple.com") {
      return try await importAppleMusicURL(url: url)
    }
    if host.contains("amazon.") {
      return try await importGenericMusicPage(url: url, badge: "Amazon Music")
    }
    return try await importGenericMusicPage(url: url, badge: "Importada")
  }

  // MARK: - 3. Import from Plain Text / M3U

  func importFromText(_ text: String, name: String) -> ImportResult {
    var tracks: [Track] = []
    for raw in text.components(separatedBy: .newlines) {
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix("#EXTM3U") { continue }
      var clean = line
      if clean.hasPrefix("#EXTINF:") {
        if let comma = clean.firstIndex(of: ",") {
          clean = String(clean[clean.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        } else { continue }
      } else if clean.hasPrefix("#") || clean.hasPrefix("http") {
        continue
      }
      // Split "Artist - Title" or "Title - Artist"
      if let sep = clean.range(of: " - ") ?? clean.range(of: " – ") ?? clean.range(of: " — ") {
        let a = String(clean[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
        let b = String(clean[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
        tracks.append(Track(title: b, artist: a, sourceService: "Lista"))
      } else {
        tracks.append(Track(title: clean, artist: "", sourceService: "Lista"))
      }
    }
    return ImportResult(playlistName: name.isEmpty ? "Playlist Importada" : name, sourceBadge: "Importada", artworkURL: "", tracks: tracks)
  }

  // MARK: - Spotify Embed Parser

  private func importSpotify(url: URL) async throws -> ImportResult {
    let comps = url.pathComponents.filter { $0 != "/" }
    guard comps.count >= 2 else {
      throw NSError(domain: "LumeMusic", code: 4, userInfo: [NSLocalizedDescriptionKey: "Use o link de uma playlist ou álbum público do Spotify."])
    }
    let kind: String
    let id: String
    if let idx = comps.firstIndex(where: { $0 == "playlist" || $0 == "album" || $0 == "track" }), idx + 1 < comps.count {
      kind = comps[idx]
      id = comps[idx + 1]
    } else {
      kind = "playlist"
      id = comps.last!
    }

    guard let embedURL = URL(string: "https://open.spotify.com/embed/\(kind)/\(id)") else {
      throw NSError(domain: "LumeMusic", code: 4, userInfo: [NSLocalizedDescriptionKey: "Não foi possível ler esse link do Spotify."])
    }
    var req = URLRequest(url: embedURL)
    req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
    let (data, _) = try await URLSession.shared.data(for: req)
    guard let html = String(data: data, encoding: .utf8),
          let r1 = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
          let r2 = html.range(of: "</script>", range: r1.upperBound..<html.endIndex) else {
      throw NSError(domain: "LumeMusic", code: 5, userInfo: [NSLocalizedDescriptionKey: "Playlist privada ou indisponível no Spotify. Deixe-a pública para importar."])
    }
    let jsonStr = String(html[r1.upperBound..<r2.lowerBound])
    guard let jdata = jsonStr.data(using: .utf8),
          let root = try JSONSerialization.jsonObject(with: jdata) as? [String: Any],
          let props = root["props"] as? [String: Any],
          let pageProps = props["pageProps"] as? [String: Any],
          let state = pageProps["state"] as? [String: Any],
          let sdata = state["data"] as? [String: Any],
          let entity = sdata["entity"] as? [String: Any] else {
      throw NSError(domain: "LumeMusic", code: 6, userInfo: [NSLocalizedDescriptionKey: "Não foi possível extrair as faixas do Spotify."])
    }
    let title = (entity["name"] as? String) ?? (entity["title"] as? String) ?? "Playlist Spotify"
    let cover = (((entity["visualIdentity"] as? [String: Any])?["image"] as? [[String: Any]])?.first?["url"] as? String)
      ?? ((entity["coverArt"] as? [String: Any])?["sources"] as? [[String: Any]])?.first?["url"] as? String ?? ""

    var tracks: [Track] = []
    if let list = entity["trackList"] as? [[String: Any]] {
      for item in list {
        guard let t = item["title"] as? String, !t.isEmpty else { continue }
        let artist = ((item["subtitle"] as? String) ?? "").replacingOccurrences(of: "\u{00A0}", with: " ")
        let ms = (item["duration"] as? Double) ?? 0
        tracks.append(Track(title: t, artist: artist, album: title, duration: ms / 1000.0, artworkURL: cover, sourceService: "Spotify"))
      }
    } else if kind == "track", let t = entity["name"] as? String {
      let artist = ((entity["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")) ?? ""
      tracks.append(Track(title: t, artist: artist, artworkURL: cover, sourceService: "Spotify"))
    }

    guard !tracks.isEmpty else {
      throw NSError(domain: "LumeMusic", code: 7, userInfo: [NSLocalizedDescriptionKey: "Nenhuma faixa encontrada nessa playlist do Spotify."])
    }
    return ImportResult(playlistName: title, sourceBadge: "Spotify", artworkURL: cover, tracks: tracks)
  }

  // MARK: - YouTube Music Playlist Parser

  private func importYouTube(url: URL) async throws -> ImportResult {
    let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    if let listId = comps?.queryItems?.first(where: { $0.name == "list" })?.value, !listId.isEmpty {
      let (name, tracks) = await MusicEngine.shared.fetchYTMPlaylist(listId: listId)
      guard !tracks.isEmpty else {
        throw NSError(domain: "LumeMusic", code: 8, userInfo: [NSLocalizedDescriptionKey: "Playlist do YouTube Music vazia ou privada."])
      }
      return ImportResult(playlistName: name, sourceBadge: "YouTube Music", artworkURL: tracks.first?.artworkURL ?? "", tracks: tracks)
    }
    throw NSError(domain: "LumeMusic", code: 8, userInfo: [NSLocalizedDescriptionKey: "Cole um link de playlist do YouTube Music contendo '?list=...'."])
  }

  // MARK: - Apple Music Public Link Parser

  private func importAppleMusicURL(url: URL) async throws -> ImportResult {
    // Check if it's an album with numeric ID we can fetch cleanly via iTunes Lookup API
    if let last = url.pathComponents.last, Int(last) != nil, url.path.contains("/album/") {
      if let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=\(last)&entity=song&country=br") {
        let (data, _) = try await URLSession.shared.data(from: lookupURL)
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let items = root["results"] as? [[String: Any]] {
          let albTitle = (items.first?["collectionName"] as? String) ?? "Álbum Apple Music"
          let albArt = ((items.first?["artworkUrl100"] as? String) ?? "").replacingOccurrences(of: "100x100bb", with: "1400x1400bb")
          let tracks = items.compactMap { it -> Track? in
            guard (it["wrapperType"] as? String) == "track", let n = it["trackName"] as? String else { return nil }
            let a = (it["artistName"] as? String) ?? ""
            let ms = (it["trackTimeMillis"] as? Double) ?? 0
            let art = ((it["artworkUrl100"] as? String) ?? albArt).replacingOccurrences(of: "100x100bb", with: "1400x1400bb")
            return Track(title: n, artist: a, album: albTitle, duration: ms / 1000.0, artworkURL: art, sourceService: "Apple Music")
          }
          if !tracks.isEmpty {
            return ImportResult(playlistName: albTitle, sourceBadge: "Apple Music", artworkURL: albArt, tracks: tracks)
          }
        }
      }
    }
    return try await importGenericMusicPage(url: url, badge: "Apple Music")
  }

  // MARK: - Generic JSON-LD / Meta Music Page Parser (Apple Music Playlists & Amazon Music)

  private func importGenericMusicPage(url: URL, badge: String) async throws -> ImportResult {
    var req = URLRequest(url: url)
    req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
    let (data, _) = try await URLSession.shared.data(for: req)
    guard let html = String(data: data, encoding: .utf8) else {
      throw NSError(domain: "LumeMusic", code: 9, userInfo: [NSLocalizedDescriptionKey: "Não foi possível abrir essa página."])
    }

    var tracks: [Track] = []
    var playlistTitle = "Playlist \(badge)"
    var cover = ""

    // Try og:title & og:image
    if let t = firstCapture(in: html, pattern: #"<meta[^>]+property="og:title"[^>]+content="([^"]+)""#) {
      playlistTitle = t.replacingOccurrences(of: " no Apple Music", with: "").replacingOccurrences(of: " on Apple Music", with: "")
    }
    if let img = firstCapture(in: html, pattern: #"<meta[^>]+property="og:image"[^>]+content="([^"]+)""#) {
      cover = img
    }

    // Parse application/ld+json MusicPlaylist / MusicAlbum
    let ldPattern = #"<script[^>]+type="application/ld\+json"[^>]*>(.*?)</script>"#
    if let regex = try? NSRegularExpression(pattern: ldPattern, options: [.dotMatchesLineSeparators]) {
      let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
      for m in matches {
        if let range = Range(m.range(at: 1), in: html),
           let jdata = String(html[range]).data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: jdata) as? [String: Any] {
          if let name = obj["name"] as? String, !name.isEmpty { playlistTitle = name }
          if let list = obj["track"] as? [[String: Any]] {
            for item in list {
              guard let name = item["name"] as? String, !name.isEmpty else { continue }
              var artist = ""
              if let by = item["byArtist"] as? [String: Any] { artist = (by["name"] as? String) ?? "" }
              else if let byArr = item["byArtist"] as? [[String: Any]] { artist = byArr.compactMap { $0["name"] as? String }.joined(separator: ", ") }
              tracks.append(Track(title: name, artist: artist, album: playlistTitle, artworkURL: cover, sourceService: badge))
            }
          }
        }
      }
    }

    guard !tracks.isEmpty else {
      throw NSError(domain: "LumeMusic", code: 10, userInfo: [NSLocalizedDescriptionKey: "Não foi possível ler automaticamente esse link do \(badge). Dica: copie os nomes das faixas e use a aba 'Lista de texto' ou importe direto da biblioteca do Apple Music!"])
    }
    return ImportResult(playlistName: playlistTitle, sourceBadge: badge, artworkURL: cover, tracks: tracks)
  }

  private func firstCapture(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let r = Range(m.range(at: 1), in: text) else { return nil }
    return String(text[r])
  }
}
