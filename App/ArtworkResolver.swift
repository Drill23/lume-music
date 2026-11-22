import Foundation

// MARK: - Helpers de rede/texto compartilhados pelo motor de descoberta

enum DiscNet {
  static let browserUA =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

  static let session: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 7
    cfg.timeoutIntervalForResource = 14
    cfg.httpAdditionalHeaders = ["User-Agent": browserUA, "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7"]
    return URLSession(configuration: cfg)
  }()

  /// GET e decodifica JSON (qualquer formato). nil em qualquer falha.
  static func json(_ urlString: String, timeout: TimeInterval = 7, headers: [String: String] = [:],
                   retries: Int = 0) async -> Any? {
    guard let url = URL(string: urlString) else { return nil }
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    var result = await send(req)
    var left = retries
    while result == nil, left > 0, !Task.isCancelled {
      left -= 1
      result = await send(req)
    }
    return result
  }

  static func postJSON(_ urlString: String, body: [String: Any], timeout: TimeInterval = 8,
                       headers: [String: String] = [:]) async -> Any? {
    guard let url = URL(string: urlString),
          let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.httpBody = data
    req.timeoutInterval = timeout
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    return await send(req)
  }

  static func send(_ req: URLRequest) async -> Any? {
    do {
      let (data, resp) = try await session.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
      return try? JSONSerialization.jsonObject(with: data)
    } catch { return nil }
  }

  static func text(_ urlString: String, timeout: TimeInterval = 7, headers: [String: String] = [:]) async -> String? {
    guard let url = URL(string: urlString) else { return nil }
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    do {
      let (data, resp) = try await session.data(for: req)
      guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
      return String(data: data, encoding: .utf8)
    } catch { return nil }
  }

  static func enc(_ s: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=+?#/:\"")
    return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
  }

  static func caches(_ name: String) -> URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
  }
}

enum DiscText {
  /// minúsculas, sem acentos, sem (feat ...), "- Ao Vivo", parênteses/colchetes e pontuação.
  static func normalize(_ s: String) -> String {
    var out = s
    out = out.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
    out = out.replacingOccurrences(
      of: #"\s[-–—]\s*(ao vivo|live|remaster(ed)?|acoustic|ac[uú]stico|versão|version|radio edit|single version|topic).*$"#,
      with: "", options: [.regularExpression, .caseInsensitive])
    out = out.replacingOccurrences(
      of: #"\s(feat\.?|ft\.?|featuring|part\.?|com)\s.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
    out = out.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
    out = out.lowercased()
    out = out.replacingOccurrences(of: "&", with: " e ")
    out = out.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
    return out.trimmingCharacters(in: .whitespaces)
  }

  /// Verdadeiro se os nomes de artista batem (igual, um contém o outro, ou algum artista de uma lista "A, B & C" bate).
  static func artistMatches(_ a: String, _ b: String) -> Bool {
    let na = normalize(a), nb = normalize(b)
    if na.isEmpty || nb.isEmpty { return false }
    if na == nb || na.contains(nb) || nb.contains(na) { return true }
    let partsA = splitArtists(a), partsB = splitArtists(b)
    for x in partsA { for y in partsB where x == y { return true } }
    return false
  }

  static func splitArtists(_ s: String) -> [String] {
    s.replacingOccurrences(of: #"\s(feat\.?|ft\.?|x|e|and|com|part\.?)\s"#, with: ",", options: [.regularExpression, .caseInsensitive])
      .components(separatedBy: CharacterSet(charactersIn: ",&;/"))
      .map { normalize($0) }
      .filter { !$0.isEmpty }
  }

  static func titleMatches(_ a: String, _ b: String) -> Bool {
    let na = normalize(a), nb = normalize(b)
    if na.isEmpty || nb.isEmpty { return false }
    return na == nb
  }

  static func titleLooselyMatches(_ a: String, _ b: String) -> Bool {
    let na = normalize(a), nb = normalize(b)
    if na.isEmpty || nb.isEmpty { return false }
    if na == nb { return true }
    let short = na.count <= nb.count ? na : nb
    let long = na.count <= nb.count ? nb : na
    return short.count >= 5 && long.hasPrefix(short + " ")
  }

  /// "Artista - Topic" → "Artista"; mantém colaborações (para busca).
  static func searchArtist(_ s: String) -> String {
    var out = s.replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
    out = out.replacingOccurrences(of: "VEVO", with: "", options: [.caseInsensitive])
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func searchTitle(_ s: String) -> String {
    var out = s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
    out = out.replacingOccurrences(of: #"\s[-–—|]\s.*$"#, with: "", options: .regularExpression)
    out = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return out.isEmpty ? s : out
  }

  static func year(from date: String?) -> String {
    guard let d = date, d.count >= 4 else { return "" }
    return String(d.prefix(4))
  }
}

// MARK: - ArtworkResolver

/// Resolve capas de álbum em alta e fotos de artistas (iTunes + Deezer), com cache em disco.
actor ArtworkResolver {
  static let shared = ArtworkResolver()

  private struct Entry: Codable { var url: String?; var ts: Double }
  private var store: [String: Entry] = [:]
  private var loaded = false
  private var inflight: [String: Task<String?, Never>] = [:]
  private let negativeTTL: Double = 3 * 24 * 3600
  private let positiveTTL: Double = 60 * 24 * 3600

  private var fileURL: URL { DiscNet.caches("lume_artwork_cache.json") }

  /// true se url vazia, thumbnail de vídeo (ytimg) ou imagem pequena (<500px detectável pela URL).
  nonisolated static func needsUpgrade(_ url: String) -> Bool {
    let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
    if u.isEmpty { return true }
    let lower = u.lowercased()
    if lower.contains("ytimg.com") || lower.contains("img.youtube.com") { return true }
    // 100x100bb, 250x250-000000..., 60x60
    if let r = lower.range(of: #"/(\d{2,4})x(\d{2,4})(bb|cc|-|\.)"#, options: .regularExpression) {
      let nums = lower[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
      if let m = nums.min(), m < 500 { return true }
      return false
    }
    // Google: =w120-h120..., =s120, -w120
    if let r = lower.range(of: #"[=\-]([ws])(\d{2,4})"#, options: .regularExpression) {
      let nums = lower[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
      if let m = nums.first, m < 500 { return true }
      return false
    }
    return false
  }

  // MARK: API

  func albumCover(title: String, artist: String, album: String) async -> String? {
    let t = DiscText.searchTitle(title)
    let a = DiscText.searchArtist(artist)
    guard !t.isEmpty else { return nil }
    let key = "cover|\(DiscText.normalize(t))|\(DiscText.normalize(a))"
    return await cached(key) { [album] in
      await Self.lookupCover(title: t, artist: a, album: album)
    }
  }

  func artistPicture(name: String) async -> String? {
    let n = DiscText.searchArtist(name)
    guard !n.isEmpty else { return nil }
    let key = "artist|\(DiscText.normalize(n))"
    return await cached(key) { await Self.lookupArtist(name: n) }
  }

  // MARK: Cache

  private func loadIfNeeded() {
    guard !loaded else { return }
    loaded = true
    if let data = try? Data(contentsOf: fileURL),
       let dict = try? JSONDecoder().decode([String: Entry].self, from: data) {
      store = dict
    }
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(store) {
      try? data.write(to: fileURL, options: .atomic)
    }
  }

  private func cached(_ key: String, _ work: @escaping @Sendable () async -> String?) async -> String? {
    loadIfNeeded()
    let now = Date().timeIntervalSince1970
    if let e = store[key] {
      if e.url != nil, now - e.ts < positiveTTL { return e.url }
      if e.url == nil, now - e.ts < negativeTTL { return nil }
    }
    if let t = inflight[key] { return await t.value }
    let task = Task<String?, Never> { await work() }
    inflight[key] = task
    let result = await task.value
    inflight[key] = nil
    store[key] = Entry(url: result, ts: now)
    persist()
    return result
  }

  // MARK: Lookups

  private static func upscaleApple(_ url: String) -> String {
    var u = url
    if let r = u.range(of: #"\d{2,4}x\d{2,4}(bb|cc)"#, options: .regularExpression) {
      u.replaceSubrange(r, with: "1200x1200bb")
    }
    return u
  }

  private static func lookupCover(title: String, artist: String, album: String) async -> String? {
    // 1. iTunes
    let term = DiscNet.enc("\(title) \(artist)")
    if let obj = await DiscNet.json("https://itunes.apple.com/search?term=\(term)&entity=song&country=br&limit=8") as? [String: Any],
       let results = obj["results"] as? [[String: Any]] {
      let candidates = results.filter { r in
        guard let tn = r["trackName"] as? String, let an = r["artistName"] as? String else { return false }
        return DiscText.artistMatches(an, artist) && DiscText.titleLooselyMatches(tn, title)
      }
      let best = candidates.first(where: { r in
        !album.isEmpty && DiscText.normalize((r["collectionName"] as? String) ?? "") == DiscText.normalize(album)
      }) ?? candidates.first(where: { DiscText.titleMatches(($0["trackName"] as? String) ?? "", title) }) ?? candidates.first
      if let art = best?["artworkUrl100"] as? String { return upscaleApple(art) }
    }
    // 2. Deezer: busca estruturada, depois livre
    let queries = [
      "artist:\"\(artist)\" track:\"\(title)\"",
      "\(title) \(artist)",
    ]
    for q in queries {
      if let obj = await DiscNet.json("https://api.deezer.com/search?q=\(DiscNet.enc(q))&limit=5") as? [String: Any],
         let data = obj["data"] as? [[String: Any]] {
        for r in data {
          guard let tn = r["title"] as? String,
                let art = r["artist"] as? [String: Any], let an = art["name"] as? String,
                DiscText.artistMatches(an, artist), DiscText.titleLooselyMatches(tn, title),
                let alb = r["album"] as? [String: Any] else { continue }
          if let xl = alb["cover_xl"] as? String, !xl.isEmpty, !xl.contains("/cover//") { return xl }
        }
      }
    }
    return nil
  }

  private static func lookupArtist(name: String) async -> String? {
    guard let obj = await DiscNet.json("https://api.deezer.com/search/artist?q=\(DiscNet.enc(name))&limit=5") as? [String: Any],
          let data = obj["data"] as? [[String: Any]] else { return nil }
    let target = DiscText.normalize(name)
    for r in data {
      guard let n = r["name"] as? String, DiscText.normalize(n) == target,
            let pic = r["picture_xl"] as? String, !pic.isEmpty, !pic.contains("/images/artist//") else { continue }
      return pic
    }
    return nil
  }
}
