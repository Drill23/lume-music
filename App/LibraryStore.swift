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

  // Preferências 5.0 (UserDefaults: não mexem no formato do snapshot da biblioteca)
  /// Modo economia: menos quadros por segundo e efeitos mais leves em todo o app.
  @Published var economyMode: Bool = UserDefaults.standard.bool(forKey: "lume.economyMode") {
    didSet { UserDefaults.standard.set(economyMode, forKey: "lume.economyMode") }
  }
  /// Arte da tela de bloqueio: Automático (segue o palco), Capa, Vinil ou Fita K7.
  @Published var lockArtStyle: LockArtStyle = LockArtStyle(rawValue: UserDefaults.standard.string(forKey: "lume.lockArtStyle") ?? "") ?? .automatic {
    didSet { UserDefaults.standard.set(lockArtStyle.rawValue, forKey: "lume.lockArtStyle") }
  }

  /// Estilo efetivo: no Automático, K7 se o palco preferido for a fita; senão vinil.
  var resolvedLockArtStyle: LockArtStyle {
    guard lockArtStyle == .automatic else { return lockArtStyle }
    let stage = UserDefaults.standard.string(forKey: "lume.playerStyle") ?? ""
    return stage == PlayerSurfaceTab.cassette.rawValue ? .cassette : .vinyl
  }

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
    /// 5.2: playlists apagadas (para o backup não trazê-las de volta).
    var deletedPlaylists: [BackupTombstone]?
  }

  /// 5.2: playlists apagadas deste aparelho (lápide com data), usadas na mesclagem do backup.
  private(set) var deletedPlaylists: [BackupTombstone] = []
  private var playlistHashes: [String: Int] = [:]
  private var librarySignature = 0
  private var bookkeepingReady = false

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
    refreshBookkeeping()
    bookkeepingReady = true
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
    return Self.formatMB(mb)
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
    return Self.formatMB(mb)
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
    visualizerStyle = snap.visualizerStyle.resolved
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
    deletedPlaylists = snap.deletedPlaylists ?? []
  }

  private var saveTask: Task<Void, Never>?

  func save() {
    trackLibraryChanges()
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
      introEnabled: introEnabled,
      deletedPlaylists: deletedPlaylists
    )
    let url = storeURL
    saveTask?.cancel()
    saveTask = Task.detached(priority: .utility) {
      try? await Task.sleep(for: .milliseconds(160))
      if Task.isCancelled { return }
      if let data = try? JSONEncoder().encode(snap) {
        try? data.write(to: url, options: .atomic)
      }
    }
  }
}

extension LibraryStore {
  /// "0 MB", "12,4 MB", "1,25 GB" (vírgula decimal pt-BR).
  static func formatMB(_ mb: Double) -> String {
    if mb < 0.05 { return "0 MB" }
    let f = NumberFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.numberStyle = .decimal
    if mb >= 1024 {
      f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
      return (f.string(from: NSNumber(value: mb / 1024)) ?? "0") + " GB"
    }
    f.minimumFractionDigits = 0; f.maximumFractionDigits = 1
    return (f.string(from: NSNumber(value: mb)) ?? "0") + " MB"
  }
}

// MARK: - Backup da biblioteca (contrato 5.2 A)

extension LibraryStore {
  static func ms(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }
  static func date(ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

  private static func playlistHash(_ p: MusicPlaylist) -> Int {
    var h = Hasher()
    h.combine(p.name)
    h.combine(p.trackIds)
    return h.finalize()
  }

  /// Guarda o "retrato" atual das playlists/curtidas/seguidos como referência para detectar mudanças.
  fileprivate func refreshBookkeeping() {
    var hashes: [String: Int] = [:]
    var sig = Hasher()
    for p in playlists {
      let h = Self.playlistHash(p)
      hashes[p.id] = h
      sig.combine(p.id); sig.combine(h)
    }
    sig.combine(favoriteIds)
    sig.combine(followedArtists.map { $0.lowercased() })
    playlistHashes = hashes
    librarySignature = sig.finalize()
  }

  /// Chamado em todo `save()`: carimba `updatedAt` nas playlists que mudaram, registra as apagadas e, se algo do
  /// que vai no backup mudou, avisa o serviço de backup (que espera 20 s antes de enviar).
  fileprivate func trackLibraryChanges() {
    guard bookkeepingReady else { return }
    let now = Date()
    var copy = playlists
    var stamped = false
    var seen = Set<String>()
    for i in copy.indices {
      let p = copy[i]
      seen.insert(p.id)
      let h = Self.playlistHash(p)
      if playlistHashes[p.id] != h {
        copy[i].updatedAt = now
        stamped = true
      } else if p.updatedAt == nil {
        copy[i].updatedAt = p.createdAt
        stamped = true
      }
    }
    let nowMs = Self.ms(now)
    var tombs = deletedPlaylists
    for id in playlistHashes.keys where !seen.contains(id) {
      tombs.removeAll { $0.id == id }
      tombs.append(BackupTombstone(id: id, at: nowMs))
    }
    tombs = tombs.filter { nowMs - $0.at < LibraryMerge.tombstoneTTLms }
    if tombs != deletedPlaylists { deletedPlaylists = tombs }
    if stamped { playlists = copy }

    let before = librarySignature
    refreshBookkeeping()
    if before != librarySignature {
      NotificationCenter.default.post(name: .lumeLibraryChanged, object: nil)
    }
  }

  /// Foto da biblioteca no formato do backup. Faixas sem videoId (arquivos locais) não entram.
  func exportBackup() -> LibraryV1 {
    func bt(_ t: Track) -> BackupTrack? {
      guard let v = t.videoId, !v.isEmpty else { return nil }
      return BackupTrack(
        videoId: v, title: t.title, artist: t.artist,
        album: t.album.isEmpty ? nil : t.album,
        durationSec: t.duration > 0 ? t.duration.rounded() : nil,
        artworkUrl: t.artworkURL.hasPrefix("http") ? t.artworkURL : nil)
    }
    func unique(_ list: [BackupTrack]) -> [BackupTrack] {
      var seen = Set<String>()
      return list.filter { seen.insert($0.videoId).inserted }
    }
    let lists = playlists.map { p -> BackupPlaylist in
      BackupPlaylist(
        id: p.id, name: p.name, created: Self.ms(p.createdAt), updated: Self.ms(p.updatedAt ?? p.createdAt),
        tracks: unique(p.trackIds.compactMap { tracksById[$0] }.compactMap(bt)))
    }
    return LibraryV1(
      exportedAt: Self.ms(Date()), platform: AccessConfig.platform, app: AccessConfig.appVersion,
      playlists: lists,
      liked: unique(favoriteIds.compactMap { tracksById[$0] }.compactMap(bt)),
      followed: followedArtists,
      deletedPlaylists: deletedPlaylists)
  }

  struct BackupApplySummary: Equatable {
    var addedPlaylists = 0
    var updatedPlaylists = 0
    var removedPlaylists = 0
    var addedLiked = 0
    var addedFollowed = 0
    var changed: Bool { addedPlaylists + updatedPlaylists + removedPlaylists + addedLiked + addedFollowed > 0 }
  }

  /// Mescla o backup do painel com a biblioteca local (nunca apaga nada sem motivo; ver `LibraryMerge`).
  @discardableResult
  func applyBackupMerge(_ remote: LibraryV1) -> BackupApplySummary {
    var summary = BackupApplySummary()
    let local = exportBackup()
    let merged = LibraryMerge.merge(local: local, remote: remote, now: Self.ms(Date()))
    let localEntries = Dictionary(local.playlists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    var idByVideo: [String: String] = [:]
    for (id, t) in tracksById {
      guard let v = t.videoId, !v.isEmpty else { continue }
      if id == v || idByVideo[v] == nil { idByVideo[v] = id }
    }
    func localId(_ b: BackupTrack) -> String {
      if let id = idByVideo[b.videoId] { return id }
      let t = Track(id: b.videoId, videoId: b.videoId, title: b.title, artist: b.artist, album: b.album ?? "",
                    duration: b.durationSec ?? 0, artworkURL: b.artworkUrl ?? "")
      register(t)
      idByVideo[b.videoId] = t.id
      return t.id
    }

    // Playlists
    let mergedIds = Set(merged.playlists.map(\.id))
    var result: [MusicPlaylist] = []
    for lp in playlists {
      guard mergedIds.contains(lp.id) else { summary.removedPlaylists += 1; continue }
      guard let mp = merged.playlists.first(where: { $0.id == lp.id }), mp != localEntries[lp.id] else { result.append(lp); continue }
      // A versão do backup é mais nova: nome e faixas dela, mas faixas locais sem videoId ficam no fim.
      var upd = lp
      var ids = mp.tracks.map(localId)
      for id in lp.trackIds where !ids.contains(id) {
        let hasVideo = (tracksById[id]?.videoId).map { !$0.isEmpty } ?? false
        if !hasVideo { ids.append(id) }
      }
      upd.name = mp.name
      upd.trackIds = ids
      upd.updatedAt = Self.date(ms: mp.updated)
      if upd.artworkURL.isEmpty { upd.artworkURL = mp.tracks.compactMap(\.artworkUrl).first ?? "" }
      result.append(upd)
      summary.updatedPlaylists += 1
    }
    let have = Set(playlists.map(\.id))
    for mp in merged.playlists where !have.contains(mp.id) {
      result.append(MusicPlaylist(
        id: mp.id, name: mp.name, artworkURL: mp.tracks.compactMap(\.artworkUrl).first ?? "",
        trackIds: mp.tracks.map(localId), sourceBadge: "Lume",
        createdAt: Self.date(ms: mp.created), updatedAt: Self.date(ms: mp.updated)))
      summary.addedPlaylists += 1
    }
    if summary.addedPlaylists + summary.updatedPlaylists + summary.removedPlaylists > 0 { playlists = result }
    deletedPlaylists = merged.deletedPlaylists

    // Curtidas: mantém a ordem local e acrescenta as que faltam no fim.
    var haveVideos = Set(favoriteIds.compactMap { tracksById[$0]?.videoId })
    let haveIds = Set(favoriteIds)
    for b in merged.liked where !haveVideos.contains(b.videoId) {
      let id = localId(b)
      if !haveIds.contains(id) { favoriteIds.append(id); summary.addedLiked += 1 }
      haveVideos.insert(b.videoId)
    }

    // Seguidos
    for a in merged.followed where !isFollowing(a) {
      followedArtists.append(a)
      summary.addedFollowed += 1
    }

    refreshBookkeeping()
    if summary.changed || deletedPlaylists != local.deletedPlaylists { save() }
    return summary
  }
}

extension Notification.Name {
  /// Playlists, curtidas ou artistas seguidos mudaram (o backup dispara 20 s depois).
  static let lumeLibraryChanged = Notification.Name("lume.library.changed")
  /// Um acesso vitalício foi ativado, transferido ou restaurado neste aparelho.
  static let lumeLifetimeAdopted = Notification.Name("lume.access.lifetimeAdopted")
}
