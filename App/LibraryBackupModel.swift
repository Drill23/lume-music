import Foundation

// Contrato 5.2 (A): formato LibraryV1 (MESMO no iPhone e no Android) e mesclagem pura.
// Só usa Foundation: roda no autoteste (-LMSelfTest) e em um compilador de linha de comando, sem simulador.

struct BackupTrack: Codable, Equatable {
  var videoId: String
  var title: String
  var artist: String
  var album: String?
  var durationSec: Double?
  var artworkUrl: String?

  init(videoId: String, title: String, artist: String, album: String? = nil, durationSec: Double? = nil, artworkUrl: String? = nil) {
    self.videoId = videoId; self.title = title; self.artist = artist
    self.album = album; self.durationSec = durationSec; self.artworkUrl = artworkUrl
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    videoId = try c.decode(String.self, forKey: .videoId)
    title = (try? c.decode(String.self, forKey: .title)) ?? ""
    artist = (try? c.decode(String.self, forKey: .artist)) ?? ""
    album = try? c.decodeIfPresent(String.self, forKey: .album)
    durationSec = try? c.decodeIfPresent(Double.self, forKey: .durationSec)
    artworkUrl = try? c.decodeIfPresent(String.self, forKey: .artworkUrl)
  }
}

struct BackupPlaylist: Codable, Equatable {
  var id: String
  var name: String
  var created: Int64
  var updated: Int64
  var tracks: [BackupTrack]

  init(id: String, name: String, created: Int64, updated: Int64, tracks: [BackupTrack]) {
    self.id = id; self.name = name; self.created = created; self.updated = updated; self.tracks = tracks
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = (try? c.decode(String.self, forKey: .name)) ?? "Playlist"
    let created = BackupNumber.decode(c, .created) ?? 0
    self.created = created
    updated = BackupNumber.decode(c, .updated) ?? created
    tracks = BackupList.decode(c, .tracks)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(created, forKey: .created)
    try c.encode(updated, forKey: .updated)
    try c.encode(tracks, forKey: .tracks)
  }

  private enum CodingKeys: String, CodingKey { case id, name, created, updated, tracks }
}

struct BackupTombstone: Codable, Equatable {
  var id: String
  var at: Int64

  init(id: String, at: Int64) { self.id = id; self.at = at }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    at = BackupNumber.decode(c, .at) ?? 0
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(at, forKey: .at)
  }

  private enum CodingKeys: String, CodingKey { case id, at }
}

/// Números do JSON podem vir como inteiro ou decimal (Android/Node): aceita os dois.
enum BackupNumber {
  static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int64? {
    if let i = try? c.decodeIfPresent(Int64.self, forKey: key) { return i }
    if let d = try? c.decodeIfPresent(Double.self, forKey: key), d.isFinite { return Int64(d) }
    return nil
  }
}

/// Lista tolerante: um item quebrado não derruba o restante do backup.
enum BackupList {
  private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
  }
  static func decode<T: Decodable, K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [T] {
    ((try? c.decodeIfPresent([Lossy<T>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? []
  }
}

struct LibraryV1: Codable, Equatable {
  var v: Int = 1
  var exportedAt: Int64 = 0
  var platform: String = "ios"
  var app: String = ""
  var playlists: [BackupPlaylist] = []
  var liked: [BackupTrack] = []
  var followed: [String] = []
  var deletedPlaylists: [BackupTombstone] = []

  init(exportedAt: Int64 = 0, platform: String = "ios", app: String = "",
       playlists: [BackupPlaylist] = [], liked: [BackupTrack] = [], followed: [String] = [], deletedPlaylists: [BackupTombstone] = []) {
    self.exportedAt = exportedAt; self.platform = platform; self.app = app
    self.playlists = playlists; self.liked = liked; self.followed = followed; self.deletedPlaylists = deletedPlaylists
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    v = BackupNumber.decode(c, .v).map(Int.init) ?? 1
    exportedAt = BackupNumber.decode(c, .exportedAt) ?? 0
    platform = (try? c.decodeIfPresent(String.self, forKey: .platform)) ?? ""
    app = (try? c.decodeIfPresent(String.self, forKey: .app)) ?? ""
    playlists = BackupList.decode(c, .playlists)
    liked = BackupList.decode(c, .liked)
    followed = BackupList.decode(c, .followed)
    deletedPlaylists = BackupList.decode(c, .deletedPlaylists)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(v, forKey: .v)
    try c.encode(exportedAt, forKey: .exportedAt)
    try c.encode(platform, forKey: .platform)
    try c.encode(app, forKey: .app)
    try c.encode(playlists, forKey: .playlists)
    try c.encode(liked, forKey: .liked)
    try c.encode(followed, forKey: .followed)
    try c.encode(deletedPlaylists, forKey: .deletedPlaylists)
  }

  private enum CodingKeys: String, CodingKey { case v, exportedAt, platform, app, playlists, liked, followed, deletedPlaylists }

  static let maxBytes = 1_000_000

  /// Corpo JSON (objeto) pronto para o painel. Se passar de ~950 KB, tira capas e álbuns; se ainda assim passar, devolve nil.
  func fittedJSON() -> Data? {
    let enc = JSONEncoder()
    if let d = try? enc.encode(self), d.count <= Self.maxBytes - 50_000 { return d }
    var slim = self
    func strip(_ t: BackupTrack) -> BackupTrack { var x = t; x.artworkUrl = nil; x.album = nil; return x }
    slim.liked = slim.liked.map(strip)
    slim.playlists = slim.playlists.map { var p = $0; p.tracks = p.tracks.map(strip); return p }
    if let d = try? enc.encode(slim), d.count <= Self.maxBytes { return d }
    return nil
  }

  var isEmpty: Bool { playlists.isEmpty && liked.isEmpty && followed.isEmpty }
}

/// Mesclagem do contrato 5.2 (A). Nunca apaga nada local sem motivo; só uma tombstone mais nova que a última
/// alteração da playlist (apagada em outro aparelho depois da última edição daqui) tira a playlist.
enum LibraryMerge {
  /// Tombstones com mais de 120 dias saem do arquivo (evita crescer para sempre).
  static let tombstoneTTLms: Int64 = 120 * 86_400_000

  static func merge(local: LibraryV1, remote: LibraryV1, now: Int64 = 0) -> LibraryV1 {
    // 1. Tombstones: união por id, vale a mais recente.
    var tomb: [String: Int64] = [:]
    for t in local.deletedPlaylists + remote.deletedPlaylists { tomb[t.id] = max(tomb[t.id] ?? 0, t.at) }

    // 2. Playlists: união por id; no mesmo id fica a de `updated` maior (empate: a local).
    var byId: [String: BackupPlaylist] = [:]
    var order: [String] = []
    for p in local.playlists where byId[p.id] == nil { byId[p.id] = p; order.append(p.id) }
    for r in remote.playlists {
      if let l = byId[r.id] {
        if r.updated > l.updated { byId[r.id] = r }
      } else {
        byId[r.id] = r
        order.append(r.id)
      }
    }
    var playlists: [BackupPlaylist] = []
    for id in order {
      guard let p = byId[id] else { continue }
      if let at = tomb[id], at > p.updated { continue }   // apagada depois da última edição: não volta
      playlists.append(p)
    }
    // Tombstone que perdeu para uma edição mais nova deixa de valer.
    for p in playlists { if let at = tomb[p.id], at <= p.updated { tomb[p.id] = nil } }
    var tombs = tomb.map { BackupTombstone(id: $0.key, at: $0.value) }.sorted { $0.at != $1.at ? $0.at > $1.at : $0.id < $1.id }
    if now > 0 { tombs = tombs.filter { now - $0.at < tombstoneTTLms } }

    // 3. Curtidas: união por videoId, ordem local primeiro e as que faltam no fim.
    var liked: [BackupTrack] = []
    var seen = Set<String>()
    for t in local.liked + remote.liked where !t.videoId.isEmpty && seen.insert(t.videoId).inserted { liked.append(t) }

    // 4. Seguidos: união sem diferenciar maiúsculas (mantém a grafia da primeira ocorrência).
    var followed: [String] = []
    var seenArtists = Set<String>()
    for a in local.followed + remote.followed {
      let clean = a.trimmingCharacters(in: .whitespacesAndNewlines)
      if !clean.isEmpty, seenArtists.insert(clean.lowercased()).inserted { followed.append(clean) }
    }

    return LibraryV1(exportedAt: max(local.exportedAt, remote.exportedAt), platform: local.platform, app: local.app,
                     playlists: playlists, liked: liked, followed: followed, deletedPlaylists: tombs)
  }
}
