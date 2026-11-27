import Foundation
import MediaPlayer

/// Progresso de uma importação, para a interface mostrar "importando 132 de 240…".
struct ImportProgress: Sendable, Equatable {
  /// Texto curto da etapa atual ("Lendo a biblioteca", nome da playlist…).
  var phase: String
  var done: Int
  /// 0 = indeterminado.
  var total: Int
  var fraction: Double? { total > 0 ? min(1, Double(done) / Double(total)) : nil }
}

typealias ImportProgressHandler = @Sendable (ImportProgress) -> Void

/// Importador de músicas e playlists com suporte a:
/// - Apple Music da biblioteca deste iPhone (MediaPlayer)
/// - Spotify (playlists/álbuns públicos via embed, sem login nem chave de API; links curtos spotify.link e URIs spotify:)
/// - Deezer (API pública: playlists, álbuns e faixas, com paginação; links curtos link.deezer.com)
/// - YouTube Music / YouTube (InnerTube)
/// - Apple Music e Amazon Music por link público (JSON-LD / metadados)
/// - Tidal (página pública, quando legível)
/// - Arquivos CSV (Exportify, TuneMyMusic, Soundiiz…), M3U e TXT
/// - Lista de texto "Artista - Música"
actor ImportService {
  static let shared = ImportService()

  struct ImportResult: Sendable {
    let playlistName: String
    let sourceBadge: String
    let artworkURL: String
    let tracks: [Track]
  }

  private static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
  private static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

  private func fail(_ code: Int, _ msg: String) -> NSError {
    NSError(domain: "LumeMusic", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
  }

  // MARK: - 1. Local Apple Music Library on iPhone

  func importFromLocalAppleMusic(progress: ImportProgressHandler? = nil) async throws -> [ImportResult] {
#if os(iOS)
    let status = await withCheckedContinuation { cont in
      MPMediaLibrary.requestAuthorization { st in cont.resume(returning: st) }
    }
    guard status == .authorized else {
      throw fail(1, "Permita o acesso à Biblioteca de Mídia nos Ajustes do iPhone para importar do Apple Music.")
    }

    let collections = MPMediaQuery.playlists().collections ?? []
    let songItems = MPMediaQuery.songs().items ?? []
    let grandTotal = collections.reduce(0) { $0 + min($1.count, 150) } + min(songItems.count, 200)
    var processed = 0
    progress?(ImportProgress(phase: "Lendo a biblioteca do Apple Music", done: 0, total: grandTotal))

    var results: [ImportResult] = []
    for pl in collections {
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
      processed += min(pl.count, 150)
      progress?(ImportProgress(phase: name, done: processed, total: grandTotal))
      if !tracks.isEmpty {
        results.append(ImportResult(playlistName: name, sourceBadge: "Apple Music", artworkURL: "", tracks: tracks))
      }
      await Task.yield()
    }

    // Todas as músicas da biblioteca, como uma coleção unificada.
    let songTracks = songItems.prefix(200).compactMap { item -> Track? in
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
    if !songTracks.isEmpty {
      results.insert(ImportResult(playlistName: "Minha Biblioteca Apple Music", sourceBadge: "Apple Music", artworkURL: "", tracks: songTracks), at: 0)
    }
    progress?(ImportProgress(phase: "Biblioteca lida", done: grandTotal, total: grandTotal))

    if results.isEmpty {
      throw fail(2, "Nenhuma música encontrada na biblioteca local do Apple Music neste iPhone. Você também pode colar o link de uma playlist pública do Apple Music, Spotify ou Deezer.")
    }
    return results
#else
    return []
#endif
  }

  // MARK: - 2. Import by URL (Spotify, Deezer, YouTube Music, Apple Music, Amazon Music, Tidal)

  func importFromURL(_ rawURL: String, progress: ImportProgressHandler? = nil) async throws -> ImportResult {
    var trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
    // Texto de compartilhamento costuma vir com frase + link: pega só o primeiro link.
    if let found = Self.firstLink(in: trimmed) { trimmed = found }

    // URI do Spotify: spotify:playlist:ID
    if trimmed.lowercased().hasPrefix("spotify:") {
      let parts = trimmed.split(separator: ":").map(String.init)
      if parts.count >= 3 { trimmed = "https://open.spotify.com/\(parts[parts.count - 2])/\(parts[parts.count - 1])" }
    }

    guard var url = URL(string: trimmed), var host = url.host?.lowercased() else {
      throw fail(3, "Link inválido. Cole o link completo de uma playlist ou álbum.")
    }

    // Links curtos (spotify.link, link.deezer.com, amzn.to…): segue o redirecionamento.
    let shortHosts = ["spotify.link", "spotify.app.link", "link.deezer.com", "deezer.page.link", "dzr.page.link", "amzn.to", "amzn.eu", "amzn.asia", "music.youtube.com/s", "tidal.link", "apple.co"]
    if shortHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
      progress?(ImportProgress(phase: "Abrindo o link", done: 0, total: 0))
      if let resolved = await resolveRedirect(url) {
        url = resolved
        host = resolved.host?.lowercased() ?? host
      }
    }

    progress?(ImportProgress(phase: "Lendo a playlist", done: 0, total: 0))
    if host.contains("spotify.com") { return try await importSpotify(url: url, progress: progress) }
    if host.contains("deezer.com") || host.contains("deezer.page.link") { return try await importDeezer(url: url, progress: progress) }
    if host.contains("youtube.com") || host.contains("youtu.be") { return try await importYouTube(url: url) }
    if host.contains("music.apple.com") { return try await importAppleMusicURL(url: url) }
    if host.contains("tidal.com") { return try await importGenericMusicPage(url: url, badge: "Tidal") }
    if host.contains("amazon.") { return try await importGenericMusicPage(url: url, badge: "Amazon Music") }
    return try await importGenericMusicPage(url: url, badge: "Importada")
  }

  /// Primeiro `http(s)://…` encontrado em um texto (ou nil).
  nonisolated static func firstLink(in text: String) -> String? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    for m in detector.matches(in: text, range: range) {
      if let u = m.url, let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" { return u.absoluteString }
    }
    return nil
  }

  /// Qual serviço parece ser o link (para mostrar o selo certo antes de importar).
  nonisolated static func serviceName(forLink text: String) -> String? {
    let l = text.lowercased()
    if l.contains("spotify") { return "Spotify" }
    if l.contains("deezer") || l.contains("dzr.page") { return "Deezer" }
    if l.contains("music.youtube") || l.contains("youtube.com") || l.contains("youtu.be") { return "YouTube Music" }
    if l.contains("music.apple") { return "Apple Music" }
    if l.contains("tidal") { return "Tidal" }
    if l.contains("amazon") || l.contains("amzn") { return "Amazon Music" }
    return nil
  }

  private func resolveRedirect(_ url: URL) async -> URL? {
    var req = URLRequest(url: url)
    req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
    req.timeoutInterval = 10
    guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return nil }
    return resp.url
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

  // MARK: - 4. Arquivo (CSV / M3U / TXT)

  /// Lê um arquivo exportado (CSV do Exportify/TuneMyMusic/Soundiiz, M3U ou TXT) e devolve a playlist.
  func importFromFile(data: Data, filename: String) throws -> ImportResult {
    let text = String(data: data, encoding: .utf8)
      ?? String(data: data, encoding: .utf16)
      ?? String(data: data, encoding: .isoLatin1)
      ?? ""
    guard !text.isEmpty else { throw fail(11, "Não consegui ler esse arquivo. Use CSV, M3U ou TXT.") }

    let base = (filename as NSString).deletingPathExtension
    let name = base.isEmpty ? "Playlist Importada" : base
    let ext = (filename as NSString).pathExtension.lowercased()

    var result: ImportResult
    if ext == "csv" || (ext != "m3u" && ext != "m3u8" && Self.looksLikeCSV(text)) {
      result = importFromCSV(text, name: name)
    } else {
      result = importFromText(text, name: name)
    }
    guard !result.tracks.isEmpty else {
      throw fail(12, "Não encontrei músicas nesse arquivo. Ele precisa ter uma música por linha (Artista - Música) ou um CSV com colunas de título e artista.")
    }
    result = ImportResult(playlistName: result.playlistName, sourceBadge: "Arquivo", artworkURL: "", tracks: result.tracks)
    return result
  }

  private nonisolated static func looksLikeCSV(_ text: String) -> Bool {
    guard let first = text.split(whereSeparator: \.isNewline).first else { return false }
    let l = first.lowercased()
    return (l.contains(",") || l.contains(";")) && (l.contains("title") || l.contains("track") || l.contains("artist") || l.contains("nome") || l.contains("artista") || l.contains("música") || l.contains("musica") || l.contains("song"))
  }

  private func importFromCSV(_ text: String, name: String) -> ImportResult {
    let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    let delimiter: Character = (firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count) ? ";" : ","
    let rows = Self.parseCSV(text, delimiter: delimiter)
    guard let header = rows.first else { return ImportResult(playlistName: name, sourceBadge: "Arquivo", artworkURL: "", tracks: []) }
    let h = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

    func col(_ keys: [String], exclude: [String] = []) -> Int? {
      for (i, name) in h.enumerated() where keys.contains(where: { name == $0 }) { return i }
      for (i, name) in h.enumerated() where keys.contains(where: { name.contains($0) }) && !exclude.contains(where: { name.contains($0) }) { return i }
      return nil
    }
    let titleCol = col(["track name", "title", "song", "track", "música", "musica", "nome da faixa", "name", "nome"], exclude: ["artist", "album", "uri", "id", "playlist"])
    let artistCol = col(["artist name(s)", "artist name", "artist", "artista", "artistas"])
    let albumCol = col(["album name", "album", "álbum"], exclude: ["artist", "date", "uri", "id", "image"])
    let durCol = col(["duration (ms)", "duration_ms", "duration"])

    var tracks: [Track] = []
    if let titleCol {
      for row in rows.dropFirst() {
        guard titleCol < row.count else { continue }
        let title = row[titleCol].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { continue }
        var artist = (artistCol.flatMap { $0 < row.count ? row[$0] : nil } ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Exportify separa vários artistas por ";" — usa todos, separados por vírgula.
        artist = artist.replacingOccurrences(of: ";", with: ", ")
        let album = (albumCol.flatMap { $0 < row.count ? row[$0] : nil } ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var dur = 0.0
        if let durCol, durCol < row.count, let ms = Double(row[durCol].trimmingCharacters(in: .whitespaces)) { dur = ms > 10_000 ? ms / 1000 : ms }
        tracks.append(Track(title: title, artist: artist, album: album, duration: dur, sourceService: "Arquivo"))
      }
    } else {
      // Sem cabeçalho reconhecível: assume colunas Música, Artista.
      for row in rows where row.count >= 1 {
        let a = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { continue }
        let b = row.count > 1 ? row[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        tracks.append(Track(title: a, artist: b, sourceService: "Arquivo"))
      }
    }
    return ImportResult(playlistName: name, sourceBadge: "Arquivo", artworkURL: "", tracks: tracks)
  }

  /// Parser CSV com aspas ("a, b", "" escapado) e quebras de linha dentro de campos.
  nonisolated static func parseCSV(_ text: String, delimiter: Character = ",") -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
    if chars.first == "\u{FEFF}" { chars.removeFirst() }
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if inQuotes {
        if c == "\"" {
          if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
        } else { field.append(c) }
      } else if c == "\"" {
        inQuotes = true
      } else if c == delimiter {
        row.append(field); field = ""
      } else if c == "\n" {
        row.append(field); field = ""
        if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
        row = []
      } else {
        field.append(c)
      }
      i += 1
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
    return rows
  }

  // MARK: - Deezer (API pública)

  private func importDeezer(url: URL, progress: ImportProgressHandler?) async throws -> ImportResult {
    let comps = url.pathComponents.filter { $0 != "/" }
    guard let idx = comps.firstIndex(where: { ["playlist", "album", "track"].contains($0) }), idx + 1 < comps.count,
          let id = Int(comps[idx + 1].filter(\.isNumber)) ?? Int(comps[idx + 1]) else {
      throw fail(13, "Use o link de uma playlist, álbum ou faixa pública do Deezer (Compartilhar > Copiar link).")
    }
    let kind = comps[idx]

    func get(_ path: String) async -> [String: Any]? {
      await DiscNet.json("https://api.deezer.com/\(path)", timeout: 10, retries: 1) as? [String: Any]
    }
    func map(_ d: [String: Any], fallbackArt: String = "") -> Track? {
      guard let title = d["title"] as? String, !title.isEmpty else { return nil }
      let artist = ((d["artist"] as? [String: Any])?["name"] as? String) ?? ""
      let album = d["album"] as? [String: Any]
      var art = (album?["cover_xl"] as? String) ?? (album?["cover_big"] as? String) ?? fallbackArt
      if art.contains("/cover//") { art = fallbackArt }
      let dur = (d["duration"] as? Double) ?? Double((d["duration"] as? Int) ?? 0)
      return Track(title: title, artist: artist, album: (album?["title"] as? String) ?? "", duration: dur,
                   artworkURL: art, sourceService: "Deezer", isExplicit: (d["explicit_lyrics"] as? Bool) ?? false)
    }

    if kind == "track" {
      guard let d = await get("track/\(id)"), d["error"] == nil, let t = map(d) else {
        throw fail(14, "Não consegui abrir essa faixa do Deezer. Ela pode ser privada ou ter sido removida.")
      }
      return ImportResult(playlistName: t.title, sourceBadge: "Deezer", artworkURL: t.artworkURL, tracks: [t])
    }

    let isAlbum = kind == "album"
    guard let meta = await get("\(kind)/\(id)"), meta["error"] == nil else {
      throw fail(14, "Playlist privada ou indisponível no Deezer. Deixe-a pública para importar.")
    }
    let title = (meta["title"] as? String) ?? (isAlbum ? "Álbum Deezer" : "Playlist Deezer")
    let cover = (meta["cover_xl"] as? String) ?? (meta["picture_xl"] as? String) ?? (meta["cover_big"] as? String) ?? (meta["picture_big"] as? String) ?? ""
    let declared = (meta["nb_tracks"] as? Int) ?? 0
    progress?(ImportProgress(phase: title, done: 0, total: declared))

    var tracks: [Track] = []
    var index = 0
    let pageSize = 100
    while index < 2000, !Task.isCancelled {
      guard let page = await get("\(kind)/\(id)/tracks?index=\(index)&limit=\(pageSize)"),
            let data = page["data"] as? [[String: Any]], !data.isEmpty else { break }
      for d in data { if let t = map(d, fallbackArt: isAlbum ? cover : "") { tracks.append(t) } }
      index += data.count
      progress?(ImportProgress(phase: title, done: tracks.count, total: max(declared, tracks.count)))
      if page["next"] == nil || data.count < pageSize { break }
    }
    guard !tracks.isEmpty else { throw fail(15, "Nenhuma faixa encontrada nessa lista do Deezer.") }
    return ImportResult(playlistName: title, sourceBadge: "Deezer", artworkURL: cover, tracks: tracks)
  }

  // MARK: - Spotify Embed Parser

  private func importSpotify(url: URL, progress: ImportProgressHandler?) async throws -> ImportResult {
    let comps = url.pathComponents.filter { $0 != "/" }
    guard comps.count >= 2 else {
      throw fail(4, "Use o link de uma playlist ou álbum público do Spotify.")
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
      throw fail(4, "Não foi possível ler esse link do Spotify.")
    }
    var req = URLRequest(url: embedURL)
    req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
    req.timeoutInterval = 15
    let (data, _) = try await URLSession.shared.data(for: req)
    guard let html = String(data: data, encoding: .utf8),
          let r1 = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
          let r2 = html.range(of: "</script>", range: r1.upperBound..<html.endIndex) else {
      throw fail(5, "Playlist privada ou indisponível no Spotify. Deixe-a pública para importar.")
    }
    let jsonStr = String(html[r1.upperBound..<r2.lowerBound])
    guard let jdata = jsonStr.data(using: .utf8),
          let root = try JSONSerialization.jsonObject(with: jdata) as? [String: Any],
          let props = root["props"] as? [String: Any],
          let pageProps = props["pageProps"] as? [String: Any],
          let state = pageProps["state"] as? [String: Any],
          let sdata = state["data"] as? [String: Any],
          let entity = sdata["entity"] as? [String: Any] else {
      throw fail(6, "Não foi possível extrair as faixas do Spotify.")
    }
    let title = (entity["name"] as? String) ?? (entity["title"] as? String) ?? "Playlist Spotify"
    let cover = (((entity["visualIdentity"] as? [String: Any])?["image"] as? [[String: Any]])?.first?["url"] as? String)
      ?? ((entity["coverArt"] as? [String: Any])?["sources"] as? [[String: Any]])?.first?["url"] as? String ?? ""

    var tracks: [Track] = []
    if let list = entity["trackList"] as? [[String: Any]] {
      for (n, item) in list.enumerated() {
        guard let t = item["title"] as? String, !t.isEmpty else { continue }
        let artist = ((item["subtitle"] as? String) ?? "").replacingOccurrences(of: "\u{00A0}", with: " ")
        let ms = (item["duration"] as? Double) ?? 0
        tracks.append(Track(title: t, artist: artist, album: title, duration: ms / 1000.0, artworkURL: cover, sourceService: "Spotify"))
        if n % 20 == 0 { progress?(ImportProgress(phase: title, done: tracks.count, total: list.count)) }
      }
      progress?(ImportProgress(phase: title, done: tracks.count, total: list.count))
    } else if kind == "track", let t = entity["name"] as? String {
      let artist = ((entity["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ")) ?? ""
      tracks.append(Track(title: t, artist: artist, artworkURL: cover, sourceService: "Spotify"))
    }

    guard !tracks.isEmpty else {
      throw fail(7, "Nenhuma faixa encontrada nessa playlist do Spotify.")
    }
    return ImportResult(playlistName: title, sourceBadge: "Spotify", artworkURL: cover, tracks: tracks)
  }

  // MARK: - YouTube Music Playlist Parser

  private func importYouTube(url: URL) async throws -> ImportResult {
    let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    if let listId = comps?.queryItems?.first(where: { $0.name == "list" })?.value, !listId.isEmpty {
      let (name, tracks) = await MusicEngine.shared.fetchYTMPlaylist(listId: listId)
      guard !tracks.isEmpty else {
        throw fail(8, "Playlist do YouTube Music vazia ou privada. Deixe-a pública ou não listada para importar.")
      }
      return ImportResult(playlistName: name, sourceBadge: "YouTube Music", artworkURL: tracks.first?.artworkURL ?? "", tracks: tracks)
    }
    throw fail(8, "Cole um link de playlist do YouTube Music contendo '?list=...'.")
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

  // MARK: - Generic JSON-LD / Meta Music Page Parser (Apple Music Playlists, Amazon Music, Tidal)

  private func importGenericMusicPage(url: URL, badge: String) async throws -> ImportResult {
    var req = URLRequest(url: url)
    req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
    req.timeoutInterval = 15
    let (data, _) = try await URLSession.shared.data(for: req)
    guard let html = String(data: data, encoding: .utf8) else {
      throw fail(9, "Não foi possível abrir essa página.")
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
      throw fail(10, "O \(badge) não deixa o Lume ler esse link automaticamente. Sem problema: exporte a playlist em CSV (o site gratuito TuneMyMusic ou Soundiiz faz isso em 1 minuto) e escolha “Arquivo”, ou cole os nomes na lista de texto.")
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
