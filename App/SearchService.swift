import Foundation

/// Busca de artistas e álbuns (Deezer, sem chave de API). As músicas vêm do MusicEngine.
actor SearchService {
  static let shared = SearchService()

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

  private static func int(_ any: Any?) -> Int? {
    if let i = any as? Int { return i }
    if let d = any as? Double { return Int(d) }
    if let s = any as? String { return Int(s) }
    return nil
  }
}
