import Foundation
import SwiftUI

/// Persistent local store for user library, playlists, favorites, listening history,
/// resolved videoIds, and offline download metadata.
@MainActor
final class LibraryStore: ObservableObject {
  static let shared = LibraryStore()

  @Published var tracksById: [String: Track] = [:]
  @Published var favoriteIds: [String] = []
  @Published var recentIds: [String] = []
  @Published var playlists: [MusicPlaylist] = []
  @Published var downloadedIds: Set<String> = []
  @Published var searchHistory: [String] = []
  @Published var followedArtists: [String] = []
  @Published var playCounts: [String: Int] = [:]
  @Published var seenReleaseIds: Set<String> = []
  @Published var savedAlbums: [AlbumShowcase] = []

  // User preferences
  @Published var visualizerStyle: VisualizerStyle = .ares { didSet { save() } }
  @Published var soundProfile: SoundProfile = .natural { didSet { save() } }
  @Published var animatedArtEnabled: Bool = true { didSet { save() } }
  @Published var autoTranslateLyrics: Bool = false { didSet { save() } }
  @Published var customEQGains: [Float] = [0, 0, 0, 0, 0] { didSet { save() } }
  @Published var crossfadeSeconds: Double = 0 { didSet { save() } }
  @Published var offlineMode: Bool = false { didSet { save() } }
  @Published var autoDownloadFavorites: Bool = false { didSet { save() } }
  @Published var turntableFinish: TurntableFinish = .obsidian { didSet { save() } }
  @Published var vinylEdition: VinylEdition = .classicBlack { didSet { save() } }
  @Published var turntable3D: Bool = true { didSet { save() } }
  @Published var cassetteStyle: CassetteStyle = .smokedStudio { didSet { save() } }
  @Published var introEnabled: Bool = true { didSet { save() } }
  @Published var totalListeningSeconds: Double = 0

  struct ReplaySummary {
    let totalPlays: Int
    let totalMinutes: Int
    let uniqueTracks: Int
    let uniqueArtists: Int
    let topTracks: [(track: Track, count: Int)]
    let topArtists: [(name: String, count: Int)]
  }

  private struct Snapshot: Codable {
    var tracksById: [String: Track]
    var favoriteIds: [String]
    var recentIds: [String]
    var playlists: [MusicPlaylist]
    var downloadedIds: [String]
    var searchHistory: [String]
    var visualizerStyle: VisualizerStyle
    var soundProfile: SoundProfile
    var animatedArtEnabled: Bool
    var autoTranslateLyrics: Bool
    var followedArtists: [String]?
    var playCounts: [String: Int]?
    var seenReleaseIds: [String]?
    var savedAlbums: [AlbumShowcase]?
    var customEQGains: [Float]?
    var crossfadeSeconds: Double?
    var offlineMode: Bool?
    var autoDownloadFavorites: Bool?
    var totalListeningSeconds: Double?
    var turntableFinish: TurntableFinish?
    var vinylEdition: VinylEdition?
    var turntable3D: Bool?
    var cassetteStyle: CassetteStyle?
    var introEnabled: Bool?
  }

  private var storeURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LumeMusic", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("library_v1.json")
  }

  var offlineDir: URL {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("OfflineAudio", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private init() {
    load()
    reconcileOfflineFiles()
  }

  func localAudioURL(for trackId: String) -> URL {
    let mp4 = offlineDir.appendingPathComponent("\(safeName(trackId)).mp4")
    if FileManager.default.fileExists(atPath: mp4.path) { return mp4 }
    let m4a = offlineDir.appendingPathComponent("\(safeName(trackId)).m4a")
    if FileManager.default.fileExists(atPath: m4a.path) { return m4a }
    return mp4
  }

  func removeDownload(_ trackId: String) {
    let base = safeName(trackId)
    try? FileManager.default.removeItem(at: offlineDir.appendingPathComponent("\(base).mp4"))
    try? FileManager.default.removeItem(at: offlineDir.appendingPathComponent("\(base).m4a"))
    downloadedIds.remove(trackId)
    save()
  }

  func isDownloaded(_ trackId: String) -> Bool {
    downloadedIds.contains(trackId) && FileManager.default.fileExists(atPath: localAudioURL(for: trackId).path)
  }

  func register(_ track: Track) {
    if var existing = tracksById[track.id] {
      if existing.videoId == nil, let v = track.videoId { existing.videoId = v }
      if existing.artworkURL.isEmpty, !track.artworkURL.isEmpty { existing.artworkURL = track.artworkURL }
      if existing.animatedArtworkURL == nil, let a = track.animatedArtworkURL { existing.animatedArtworkURL = a }
      if existing.duration <= 0, track.duration > 0 { existing.duration = track.duration }
      if existing.album.isEmpty, !track.album.isEmpty { existing.album = track.album }
      tracksById[track.id] = existing
    } else {
      tracksById[track.id] = track
    }
  }

  func updateVideoId(_ videoId: String, for trackId: String) {
    guard var tr = tracksById[trackId] else { return }
    tr.videoId = videoId
    tracksById[trackId] = tr
    save()
  }

  func updateAnimatedArt(_ url: String, for trackId: String) {
    guard var tr = tracksById[trackId] else { return }
    tr.animatedArtworkURL = url
    tracksById[trackId] = tr
    save()
  }

  func isFavorite(_ trackId: String) -> Bool {
    favoriteIds.contains(trackId)
  }

  func toggleFavorite(_ track: Track) {
    register(track)
    if let idx = favoriteIds.firstIndex(of: track.id) {
      favoriteIds.remove(at: idx)
    } else {
      favoriteIds.insert(track.id, at: 0)
      Haptics.success()
      if autoDownloadFavorites && !isDownloaded(track.id) {
        DownloadManager.shared.download(track)
      }
    }
    save()
  }

  func recordPlay(_ track: Track) {
    register(track)
    recentIds.removeAll { $0 == track.id }
    recentIds.insert(track.id, at: 0)
    if recentIds.count > 120 { recentIds = Array(recentIds.prefix(120)) }
    playCounts[track.id, default: 0] += 1
    totalListeningSeconds += track.duration > 0 ? track.duration : 195
    save()
  }

  var effectiveEQGains: [Float] {
    soundProfile == .custom ? customEQGains : soundProfile.defaultGains
  }

  func isAlbumSaved(_ id: String) -> Bool {
    savedAlbums.contains { $0.id == id }
  }

  func toggleSaveAlbum(_ album: AlbumShowcase, tracks: [Track] = []) {
    if let idx = savedAlbums.firstIndex(where: { $0.id == album.id }) {
      savedAlbums.remove(at: idx)
    } else {
      var copy = album
      if copy.tracks.isEmpty && !tracks.isEmpty { copy.tracks = tracks }
      for t in copy.tracks { register(t) }
      savedAlbums.insert(copy, at: 0)
      Haptics.success()
    }
    save()
  }

  func reorderPlaylist(_ playlistId: String, from: IndexSet, to: Int) {
    guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
    playlists[idx].trackIds.move(fromOffsets: from, toOffset: to)
    save()
  }

  func fileSizeBytes(for trackId: String) -> Int64 {
    let url = localAudioURL(for: trackId)
    guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
    let sz = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    return Int64(sz)
  }

  func fileSizeFormatted(for trackId: String) -> String {
    let bytes = fileSizeBytes(for: trackId)
    guard bytes > 0 else { return "" }
    let mb = Double(bytes) / (1024.0 * 1024.0)
    return String(format: "%.1f MB", mb)
  }

  func removeAllDownloads() {
    for id in Array(downloadedIds) {
      let base = safeName(id)
      try? FileManager.default.removeItem(at: offlineDir.appendingPathComponent("\(base).mp4"))
      try? FileManager.default.removeItem(at: offlineDir.appendingPathComponent("\(base).m4a"))
    }
    downloadedIds.removeAll()
    save()
  }

  var replaySummary: ReplaySummary {
    let totalPlays = playCounts.values.reduce(0, +)
    let mins = max(Int((totalListeningSeconds / 60.0).rounded()), totalPlays * 3)
    let topTracks: [(track: Track, count: Int)] = playCounts
      .sorted { $0.value > $1.value }
      .compactMap { k, v in
        guard let t = tracksById[k] else { return nil }
        return (t, v)
      }
      .prefix(10)
      .map { $0 }

    var artistScore: [String: (name: String, count: Int)] = [:]
    for (id, n) in playCounts {
      guard let t = tracksById[id] else { continue }
      let main = Self.mainArtist(t.artist)
      guard !main.isEmpty, main != "Artista" else { continue }
      let key = main.lowercased()
      artistScore[key] = (main, (artistScore[key]?.count ?? 0) + n)
    }
    let topArtists = artistScore.values.sorted { $0.count > $1.count }.prefix(10).map { ($0.name, $0.count) }
    return ReplaySummary(
      totalPlays: totalPlays,
      totalMinutes: mins,
      uniqueTracks: playCounts.count,
      uniqueArtists: artistScore.count,
      topTracks: topTracks,
      topArtists: topArtists
    )
  }

  // MARK: - Artists (follow + listening stats)

  func isFollowing(_ artist: String) -> Bool {
    followedArtists.contains { $0.caseInsensitiveCompare(artist) == .orderedSame }
  }

  func toggleFollow(_ artist: String) {
    let clean = artist.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    if let idx = followedArtists.firstIndex(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
      followedArtists.remove(at: idx)
    } else {
      followedArtists.insert(clean, at: 0)
      Haptics.success()
    }
    save()
  }

  /// Tracks ranked by how many times they were played.
  var mostPlayedTracks: [Track] {
    playCounts.sorted { $0.value > $1.value }.compactMap { tracksById[$0.key] }
  }

  /// Artists ranked by plays (main artist only), followed artists first.
  var topListenedArtists: [String] {
    var score: [String: Int] = [:]
    var display: [String: String] = [:]
    for (id, n) in playCounts {
      guard let t = tracksById[id] else { continue }
      let main = Self.mainArtist(t.artist)
      guard !main.isEmpty, main != "Artista" else { continue }
      score[main.lowercased(), default: 0] += n
      display[main.lowercased()] = main
    }
    for id in favoriteIds {
      guard let t = tracksById[id] else { continue }
      let main = Self.mainArtist(t.artist)
      guard !main.isEmpty, main != "Artista" else { continue }
      score[main.lowercased(), default: 0] += 2
      display[main.lowercased()] = main
    }
    let ranked = score.sorted { $0.value > $1.value }.compactMap { display[$0.key] }
    var out = followedArtists
    for a in ranked where !out.contains(where: { $0.caseInsensitiveCompare(a) == .orderedSame }) { out.append(a) }
    return out
  }

  static func mainArtist(_ s: String) -> String {
    // Keep duo names intact ("Henrique e Juliano", "Jorge & Mateus"); only split real collaborations.
    let seps = [",", " feat", " ft.", " x ", " part.", " (", " com "]
    var out = s
    for sep in seps {
      if let r = out.range(of: sep, options: .caseInsensitive) { out = String(out[..<r.lowerBound]) }
    }
    return out.replacingOccurrences(of: " - Topic", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func updateArtwork(_ url: String, for trackId: String) {
    guard var tr = tracksById[trackId], tr.artworkURL != url else { return }
    tr.artworkURL = url
    tracksById[trackId] = tr
    save()
  }

  func addSearchTerm(_ q: String) {
    let clean = q.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    searchHistory.removeAll { $0.caseInsensitiveCompare(clean) == .orderedSame }
    searchHistory.insert(clean, at: 0)
    if searchHistory.count > 12 { searchHistory = Array(searchHistory.prefix(12)) }
    save()
  }

  @discardableResult
  func createPlaylist(name: String, subtitle: String = "", sourceBadge: String = "Lume", artworkURL: String = "", tracks: [Track] = []) -> MusicPlaylist {
    var ids: [String] = []
    for t in tracks {
      register(t)
      if !ids.contains(t.id) { ids.append(t.id) }
    }
    let cover = artworkURL.isEmpty ? (tracks.first(where: { !$0.artworkURL.isEmpty })?.artworkURL ?? "") : artworkURL
    let pl = MusicPlaylist(name: name, subtitle: subtitle, artworkURL: cover, trackIds: ids, sourceBadge: sourceBadge)
    playlists.insert(pl, at: 0)
    save()
    return pl
  }

  func addTrack(_ track: Track, toPlaylist playlistId: String) {
    register(track)
    guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
    if !playlists[idx].trackIds.contains(track.id) {
      playlists[idx].trackIds.append(track.id)
      if playlists[idx].artworkURL.isEmpty && !track.artworkURL.isEmpty {
        playlists[idx].artworkURL = track.artworkURL
      }
      save()
    }
  }

  func removeTrack(_ trackId: String, fromPlaylist playlistId: String) {
    guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
    playlists[idx].trackIds.removeAll { $0 == trackId }
    save()
  }

  func deletePlaylist(_ playlistId: String) {
    playlists.removeAll { $0.id == playlistId }
    save()
  }

  func markDownloaded(_ track: Track) {
    register(track)
    downloadedIds.insert(track.id)
    save()
  }

  var favoriteTracks: [Track] { favoriteIds.compactMap { tracksById[$0] } }
  var recentTracks: [Track] { recentIds.compactMap { tracksById[$0] } }
  var downloadedTracks: [Track] {
    downloadedIds.compactMap { isDownloaded($0) ? tracksById[$0] : nil }
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  func tracks(in playlist: MusicPlaylist) -> [Track] {
    playlist.trackIds.compactMap { tracksById[$0] }
  }

  var offlineStorageFormatted: String {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(at: offlineDir, includingPropertiesForKeys: [.fileSizeKey]) else { return "0 MB" }
    let total = files.reduce(Int64(0)) { acc, u in
      let sz = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      return acc + Int64(sz)
    }
    let mb = Double(total) / (1024.0 * 1024.0)
    return mb >= 1024 ? String(format: "%.2f GB", mb / 1024.0) : String(format: "%.1f MB", mb)
  }

  private func reconcileOfflineFiles() {
    let valid = downloadedIds.filter { FileManager.default.fileExists(atPath: localAudioURL(for: $0).path) }
    if valid.count != downloadedIds.count {
      downloadedIds = valid
      save()
    }
  }

  private func safeName(_ id: String) -> String {
    id.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
  }

  private func load() {
    guard let data = try? Data(contentsOf: storeURL),
          let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
    tracksById = snap.tracksById
    favoriteIds = snap.favoriteIds
    recentIds = snap.recentIds
    playlists = snap.playlists
    downloadedIds = Set(snap.downloadedIds)
    searchHistory = snap.searchHistory
    visualizerStyle = snap.visualizerStyle
    soundProfile = snap.soundProfile
    animatedArtEnabled = snap.animatedArtEnabled
    autoTranslateLyrics = snap.autoTranslateLyrics
    followedArtists = snap.followedArtists ?? []
    playCounts = snap.playCounts ?? [:]
    seenReleaseIds = Set(snap.seenReleaseIds ?? [])
    savedAlbums = snap.savedAlbums ?? []
    customEQGains = snap.customEQGains ?? [0, 0, 0, 0, 0]
    crossfadeSeconds = snap.crossfadeSeconds ?? 0
    offlineMode = snap.offlineMode ?? false
    autoDownloadFavorites = snap.autoDownloadFavorites ?? false
    totalListeningSeconds = snap.totalListeningSeconds ?? 0
    turntableFinish = snap.turntableFinish ?? .obsidian
    vinylEdition = snap.vinylEdition ?? .classicBlack
    turntable3D = snap.turntable3D ?? true
    cassetteStyle = snap.cassetteStyle ?? .smokedStudio
    introEnabled = snap.introEnabled ?? true
  }

  func save() {
    let snap = Snapshot(
      tracksById: tracksById,
      favoriteIds: favoriteIds,
      recentIds: recentIds,
      playlists: playlists,
      downloadedIds: Array(downloadedIds),
      searchHistory: searchHistory,
      visualizerStyle: visualizerStyle,
      soundProfile: soundProfile,
      animatedArtEnabled: animatedArtEnabled,
      autoTranslateLyrics: autoTranslateLyrics,
      followedArtists: followedArtists,
      playCounts: playCounts,
      seenReleaseIds: Array(seenReleaseIds),
      savedAlbums: savedAlbums,
      customEQGains: customEQGains,
      crossfadeSeconds: crossfadeSeconds,
      offlineMode: offlineMode,
      autoDownloadFavorites: autoDownloadFavorites,
      totalListeningSeconds: totalListeningSeconds,
      turntableFinish: turntableFinish,
      vinylEdition: vinylEdition,
      turntable3D: turntable3D,
      cassetteStyle: cassetteStyle,
      introEnabled: introEnabled
    )
    if let data = try? JSONEncoder().encode(snap) {
      try? data.write(to: storeURL, options: .atomic)
    }
  }
}
