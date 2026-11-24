import Foundation

/// Busca de artistas, álbuns, playlists (Deezer), sugestões ao vivo (YouTube/Google) e busca por letra (LRCLIB).
actor SearchService {
  static let shared = SearchService()

  func suggestions(_ q: String) async -> [String] {
    let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 2 else { return [] }
    guard let url = URL(string: "https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&hl=pt&q=\(DiscNet.enc(query))") else {
      return []
    }
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      guard let arr = try JSONSerialization.jsonObject(with: data) as? [Any],
            arr.count >= 2,
            let list = arr[1] as? [String] else { return [] }
      var seen = Set<String>()
      return list.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(8).map { $0 }
    } catch { return [] }
  }

  func artists(_ q: String) async -> [ArtistInfo] {
    let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty,
          let obj = await DiscNet.json("https://api.deezer.com/search/artist?q=\(DiscNet.enc(query))&limit=12") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return [] }
    return data.compactMap { d in
      guard let id = Self.int(d["id"]), let name = d["name"] as? String, !name.isEmpty else { return nil }
      var pic = (d["picture_xl"] as? String) ?? (d["picture_big"] as? String) ?? ""
      if pic.contains("/images/artist//") { pic = "" }
      return ArtistInfo(id: "dz_\(id)", name: name, pictureURL: pic, deezerId: id, fans: Self.int(d["nb_fan"]), rank: nil)
    }
  }

  func albums(_ q: String) async -> [AlbumShowcase] {
    let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty,
          let obj = await DiscNet.json("https://api.deezer.com/search/album?q=\(DiscNet.enc(query))&limit=16") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return [] }
    return data.compactMap { d in
      guard let id = Self.int(d["id"]), let title = d["title"] as? String, !title.isEmpty else { return nil }
      var cover = (d["cover_xl"] as? String) ?? (d["cover_big"] as? String) ?? ""
      if cover.contains("/cover//") { cover = "" }
      let artist = ((d["artist"] as? [String: Any])?["name"] as? String) ?? "Artista"
      let kind: String
      switch ((d["record_type"] as? String) ?? "").lowercased() {
      case "single": kind = "Single"
      case "ep": kind = "EP"
      default: kind = "Álbum"
      }
      let date = d["release_date"] as? String
      return AlbumShowcase(
        id: "dzalb_\(id)", title: title, artist: artist, artworkURL: cover,
        animatedArtworkURL: nil, year: String((date ?? "").prefix(4)), genre: "", tracks: [],
        releaseDate: date, kind: kind, deezerId: id, itunesId: nil
      )
    }
  }

  func playlists(_ q: String, limit: Int = 12) async -> [RemotePlaylist] {
    let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty,
          let obj = await DiscNet.json("https://api.deezer.com/search/playlist?q=\(DiscNet.enc(query))&limit=\(limit)") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return [] }
    return data.compactMap { d in
      guard let id = Self.int(d["id"]), let title = d["title"] as? String, !title.isEmpty else { return nil }
      let count = Self.int(d["nb_tracks"]) ?? 0
      guard count > 0 else { return nil }
      var cover = (d["picture_xl"] as? String) ?? (d["picture_big"] as? String) ?? (d["picture_medium"] as? String) ?? ""
      if cover.contains("/cover//") { cover = "" }
      let creator = ((d["user"] as? [String: Any])?["name"] as? String) ?? "Curadoria"
      return RemotePlaylist(
        deezerId: id,
        title: title,
        subtitle: "\(count) músicas · \(creator)",
        artworkURL: cover,
        trackCount: count,
        creator: creator
      )
    }
  }

  func searchByLyrics(_ q: String) async -> [LyricSearchHit] {
    let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 3,
          let arr = await DiscNet.json("https://lrclib.net/api/search?q=\(DiscNet.enc(query))", timeout: 6, retries: 1) as? [[String: Any]] else {
      return []
    }
    var seen = Set<String>()
    var hits: [LyricSearchHit] = []
    for item in arr {
      guard let trackName = item["trackName"] as? String ?? item["name"] as? String,
            let artistName = item["artistName"] as? String,
            !trackName.isEmpty, !artistName.isEmpty else { continue }
      let key = "\(DiscText.normalize(trackName))|\(DiscText.normalize(artistName))"
      guard seen.insert(key).inserted else { continue }
      let plain = (item["plainLyrics"] as? String) ?? ""
      let synced = (item["syncedLyrics"] as? String) ?? ""
      let snippet = Self.extractSnippet(query: query, plain: plain, synced: synced)
      let dur = (item["duration"] as? Double) ?? 0
      let alb = (item["albumName"] as? String) ?? ""
      let tr = Track(title: trackName, artist: artistName, album: alb, duration: dur, artworkURL: "", sourceService: "Letras")
      hits.append(LyricSearchHit(track: tr, snippet: snippet))
      if hits.count >= 16 { break }
    }
    return hits
  }

  nonisolated static func extractSnippet(query: String, plain: String, synced: String) -> String {
    let rawText = !plain.isEmpty ? plain : synced.replacingOccurrences(of: #"\[\d{1,2}:\d{2}(?:\.\d{1,3})?\]"#, with: "", options: .regularExpression)
    let lines = rawText
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !lines.isEmpty else { return "" }
    let tokens = DiscText.normalize(query).split(separator: " ").map(String.init).filter { $0.count >= 2 }
    if let matchIdx = lines.firstIndex(where: { line in
      let nl = DiscText.normalize(line)
      return tokens.contains { nl.contains($0) }
    }) {
      let start = max(0, matchIdx)
      let end = min(lines.count, start + 2)
      return lines[start..<end].joined(separator: " / ")
    }
    return lines.prefix(2).joined(separator: " / ")
  }

  private static func int(_ any: Any?) -> Int? {
    if let i = any as? Int { return i }
    if let d = any as? Double { return Int(d) }
    if let s = any as? String { return Int(s) }
    return nil
  }
}
