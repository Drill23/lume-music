import Combine
import SwiftUI

// MARK: - Regras e formato (puros; testados no -LMSelfTest)

/// Uma audição pronta para enviar ao ListenBrainz (também é o formato da fila offline).
struct ScrobbleItem: Codable, Equatable {
  var listenedAt: Int?          // segundos desde 1970 (nil no playing_now)
  var artist: String
  var track: String
  var release: String?
  var videoId: String?
  var durationMs: Int?
}

enum ListenBrainzRules {
  static let api = "https://api.listenbrainz.org/1"
  static let maxQueue = 500
  static let batchSize = 100

  /// Contrato 5.2 (B): a faixa precisa ter pelo menos 30 s e ter sido ouvida pela METADE ou por 4 minutos, o que vier antes.
  /// Sem duração conhecida (0), vale só a regra dos 4 minutos.
  static func shouldScrobble(listened: Double, duration: Double) -> Bool {
    if duration > 0 {
      guard duration >= 30 else { return false }
      return listened >= min(duration / 2, 240)
    }
    return listened >= 240
  }

  static func metadata(_ i: ScrobbleItem, version: String) -> [String: Any] {
    var info: [String: Any] = ["media_player": "Lume Music", "submission_client": "Lume Music", "submission_client_version": version]
    if let v = i.videoId, !v.isEmpty {
      info["music_service"] = "youtube.com"
      info["origin_url"] = "https://music.youtube.com/watch?v=\(v)"
    }
    if let d = i.durationMs, d > 0 { info["duration_ms"] = d }
    var meta: [String: Any] = ["artist_name": i.artist, "track_name": i.track, "additional_info": info]
    if let r = i.release, !r.isEmpty { meta["release_name"] = r }
    return meta
  }

  /// Corpo de `submit-listens`. `type`: playing_now | single | import.
  static func body(type: String, items: [ScrobbleItem], version: String) -> [String: Any] {
    let payload: [[String: Any]] = items.map { i in
      var e: [String: Any] = ["track_metadata": metadata(i, version: version)]
      if type != "playing_now", let t = i.listenedAt { e["listened_at"] = t }
      return e
    }
    return ["listen_type": type, "payload": payload]
  }

  /// Acrescenta à fila respeitando o limite (descarta as mais antigas).
  static func enqueue(_ item: ScrobbleItem, to queue: [ScrobbleItem]) -> [ScrobbleItem] {
    var q = queue + [item]
    if q.count > maxQueue { q.removeFirst(q.count - maxQueue) }
    return q
  }
}

// MARK: - Serviço

/// ListenBrainz: token no Keychain, `playing_now` ao começar, `single` ao ouvir metade (ou 4 min), fila offline em arquivo.
/// Observa o AudioPlayer sem alterá-lo. Desligado por padrão.
@MainActor
final class ListenBrainzService: ObservableObject {
  static let shared = ListenBrainzService()

  @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled); refreshTimer() } }
  @Published private(set) var userName: String?
  @Published private(set) var busy = false
  @Published var message: String?
  @Published private(set) var pending = 0

  private enum Key {
    static let enabled = "lume.lb.enabled"
    static let user = "lume.lb.user"
    static let token = "lume.listenbrainz.token"
  }

  private let defaults = UserDefaults.standard
  private let secrets: SecretStore = KeychainSecretStore()
  private var cancellables = Set<AnyCancellable>()
  private var timer: Timer?
  private var started = false
  private var flushing = false
  private var ticks = 0
  private var playingFlag = false
  private var queue: [ScrobbleItem] = []
  private var session: Session?

  private struct Session {
    var trackId: String
    var item: ScrobbleItem
    var duration: Double
    var listened: Double = 0
    var startedAt: Int?
    var nowPlayingSent = false
    var scrobbled = false
    var lastClock: Double = 0
  }

  private init() {
    enabled = UserDefaults.standard.bool(forKey: Key.enabled)
    userName = UserDefaults.standard.string(forKey: Key.user)
    queue = Self.loadQueue()
    pending = queue.count
  }

  var token: String? {
    guard let t = secrets.get(Key.token), !t.isEmpty else { return nil }
    return t
  }
  var connected: Bool { token != nil && userName != nil }
  private var active: Bool { enabled && token != nil }

  // MARK: Ligação

  func start() {
    guard !started else { return }
    started = true
    let player = AudioPlayer.shared
    player.$currentTrack
      .sink { [weak self] t in MainActor.assumeIsolated { self?.trackChanged(t) } }
      .store(in: &cancellables)
    player.$isPlaying
      .sink { [weak self] p in MainActor.assumeIsolated { self?.playingFlag = p } }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in MainActor.assumeIsolated { self?.kickFlush() } }
      .store(in: &cancellables)
    refreshTimer()
    kickFlush()
  }

  private func refreshTimer() {
    timer?.invalidate()
    timer = nil
    guard started, active else { return }
    let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  /// Valida o token colado (GET validate-token) e, se servir, guarda no Keychain e liga o envio.
  func connect(token raw: String) async {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    busy = true; message = nil
    defer { busy = false }
    guard let url = URL(string: ListenBrainzRules.api + "/validate-token") else { return }
    var req = URLRequest(url: url)
    req.timeoutInterval = 12
    req.setValue("Token \(t)", forHTTPHeaderField: "Authorization")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
      let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
      if status == 200, (obj["valid"] as? Bool) == true, let name = obj["user_name"] as? String, !name.isEmpty {
        secrets.set(t, for: Key.token)
        userName = name
        defaults.set(name, forKey: Key.user)
        enabled = true
        Haptics.success()
        kickFlush()
      } else if status == 429 || status >= 500 {
        message = "O ListenBrainz está fora do ar agora. Tente de novo em instantes."
      } else {
        message = "Esse token não é válido. Confira e tente de novo."
      }
    } catch {
      message = "Sem conexão com o ListenBrainz. Verifique a internet e tente de novo."
    }
  }

  func disconnect() {
    secrets.remove(Key.token)
    userName = nil
    defaults.removeObject(forKey: Key.user)
    enabled = false
    queue = []
    persistQueue()
    session = nil
    message = nil
  }

  // MARK: Acompanhando a reprodução

  private func trackChanged(_ t: Track?) {
    guard let t else { session = nil; return }
    if session?.trackId == t.id { return }
    session = makeSession(for: t)
  }

  private func makeSession(for t: Track) -> Session {
    let clock = PlaybackClock.shared
    let dur = max(t.duration, clock.duration)
    let item = ScrobbleItem(
      listenedAt: nil, artist: t.artist, track: t.title,
      release: t.album.isEmpty ? nil : t.album, videoId: t.videoId,
      durationMs: dur > 0 ? Int(dur * 1000) : nil)
    return Session(trackId: t.id, item: item, duration: dur, lastClock: clock.currentTime)
  }

  private func tick() {
    guard active, var s = session, playingFlag else { return }
    let clock = PlaybackClock.shared
    // Mesma faixa tocando de novo (repetir uma): o tempo volta ao começo depois de já ter passado do início.
    if s.scrobbled, clock.currentTime < 3, s.lastClock > 20, let t = AudioPlayer.shared.currentTrack {
      s = makeSession(for: t)
    }
    s.lastClock = clock.currentTime
    if s.startedAt == nil { s.startedAt = Int(Date().timeIntervalSince1970) }
    s.listened += 1
    if clock.duration > s.duration {
      s.duration = clock.duration
      s.item.durationMs = Int(clock.duration * 1000)
    }
    var sendNow = false
    var sendSingle: ScrobbleItem?
    if !s.nowPlayingSent { s.nowPlayingSent = true; sendNow = true }
    if !s.scrobbled, ListenBrainzRules.shouldScrobble(listened: s.listened, duration: s.duration) {
      s.scrobbled = true
      var item = s.item
      item.listenedAt = s.startedAt
      sendSingle = item
    }
    session = s
    ticks += 1
    if ticks % 300 == 0 { kickFlush() }
    if sendNow { let i = s.item; Task { _ = await self.post(type: "playing_now", items: [i]) } }
    if let item = sendSingle { Task { await self.submitSingle(item) } }
  }

  // MARK: Envio

  private enum PostResult { case ok, retry, drop, unauthorized }

  private func submitSingle(_ item: ScrobbleItem) async {
    switch await post(type: "single", items: [item]) {
    case .ok: kickFlush()
    case .retry: queue = ListenBrainzRules.enqueue(item, to: queue); persistQueue()
    case .drop: break
    case .unauthorized: queue = ListenBrainzRules.enqueue(item, to: queue); persistQueue()
    }
  }

  private func post(type: String, items: [ScrobbleItem]) async -> PostResult {
    guard let token, let url = URL(string: ListenBrainzRules.api + "/submit-listens") else { return .drop }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = 15
    req.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body = ListenBrainzRules.body(type: type, items: items, version: AccessConfig.appVersion)
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return .drop }
    req.httpBody = data
    do {
      let (_, resp) = try await URLSession.shared.data(for: req)
      let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
      switch status {
      case 200...299: return .ok
      case 401: return .unauthorized
      case 400...499 where status != 429 && status != 408: return .drop
      default: return .retry
      }
    } catch {
      return .retry
    }
  }

  private func kickFlush() {
    guard active, !queue.isEmpty, !flushing else { return }
    Task { await flushQueue() }
  }

  /// Envia a fila offline em lotes de até 100 (`import`).
  private func flushQueue() async {
    guard !flushing else { return }
    flushing = true
    defer { flushing = false }
    while active, !queue.isEmpty {
      let batch = Array(queue.prefix(ListenBrainzRules.batchSize))
      let r = await post(type: "import", items: batch)
      switch r {
      case .ok, .drop:
        queue.removeFirst(min(batch.count, queue.count))
        persistQueue()
      case .retry, .unauthorized:
        return
      }
    }
  }

  // MARK: Fila em arquivo

  private static var queueURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LumeMusic", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("listenbrainz_queue.json")
  }

  private static func loadQueue() -> [ScrobbleItem] {
    guard let d = try? Data(contentsOf: queueURL), let q = try? JSONDecoder().decode([ScrobbleItem].self, from: d) else { return [] }
    return Array(q.suffix(ListenBrainzRules.maxQueue))
  }

  private func persistQueue() {
    pending = queue.count
    if queue.isEmpty { try? FileManager.default.removeItem(at: Self.queueURL); return }
    if let d = try? JSONEncoder().encode(queue) { try? d.write(to: Self.queueURL, options: .atomic) }
  }
}
