import Foundation

/// Letras de várias fontes (LRCLIB, NetEase, YouTube Music, Letras.mus.br, Lyrics.ovh) com tradução PT-BR e cache.
/// Positivo: disco. Negativo: só memória por 24h.
actor LyricsService {
  static let shared = LyricsService()

  private var memCache: [String: LyricsBundle] = [:]
  private var negCache: [String: Date] = [:]
  private var inflight: [String: Task<LyricsBundle?, Never>] = [:]

  private var cacheDir: URL {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LumeMusicLyrics", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func diskURL(for key: String) -> URL {
    cacheDir.appendingPathComponent("\(key).json")
  }

  /// Clears a remembered miss so the next fetch searches again (e.g. after the videoId is known).
  func forgetMiss(for track: Track) {
    negCache[Track.stableId(title: track.title, artist: track.artist)] = nil
  }

  func fetchLyrics(for track: Track) async -> LyricsBundle? {
    let key = Track.stableId(title: track.title, artist: track.artist)
    if let mem = memCache[key] { return mem }
    if let data = try? Data(contentsOf: diskURL(for: key)),
       let saved = try? JSONDecoder().decode(LyricsBundle.self, from: data) {
      memCache[key] = saved
      return saved
    }
    if let t = negCache[key], Date().timeIntervalSince(t) < 24 * 3600 { return nil }
    if let running = inflight[key] { return await running.value }

    let task = Task<LyricsBundle?, Never> { await Self.search(track: track, key: key) }
    inflight[key] = task
    let result = await task.value
    inflight[key] = nil
    if let result {
      save(result)
    } else {
      negCache[key] = Date()
    }
    return result
  }

  func translateToPortuguese(_ bundle: LyricsBundle) async -> LyricsBundle {
    if bundle.translatedToPT { return bundle }
    let nonEmptyIndices = bundle.lines.indices.filter { !bundle.lines[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard !nonEmptyIndices.isEmpty else { return bundle }

    var updated = bundle
    // Batch lines into ~1400-char chunks preserving exact 1-to-1 line alignment
    var i = 0
    while i < nonEmptyIndices.count {
      var batchIdx: [Int] = []
      var batchText: [String] = []
      var chars = 0
      while i < nonEmptyIndices.count {
        let idx = nonEmptyIndices[i]
        let t = updated.lines[idx].text.replacingOccurrences(of: "\n", with: " ")
        if !batchIdx.isEmpty && chars + t.count + 2 > 1400 { break }
        batchIdx.append(idx)
        batchText.append(t)
        chars += t.count + 2
        i += 1
      }
      let joined = batchText.joined(separator: "\n")
      if let translated = await translateChunk(joined) {
        let outLines = translated.components(separatedBy: "\n")
        for (pos, lineIdx) in batchIdx.enumerated() where pos < outLines.count {
          let tr = outLines[pos].trimmingCharacters(in: .whitespacesAndNewlines)
          if !tr.isEmpty && tr.lowercased() != updated.lines[lineIdx].text.lowercased() {
            updated.lines[lineIdx].translated = tr
          }
        }
      }
    }
    updated.translatedToPT = true
    save(updated)
    return updated
  }

  private func translateChunk(_ text: String) async -> String? {
    var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
    comps?.queryItems = [
      URLQueryItem(name: "client", value: "gtx"),
      URLQueryItem(name: "sl", value: "auto"),
      URLQueryItem(name: "tl", value: "pt"),
      URLQueryItem(name: "dt", value: "t"),
      URLQueryItem(name: "q", value: text),
    ]
    guard let url = comps?.url else { return nil }
    var req = URLRequest(url: url)
    req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    do {
      let (data, _) = try await URLSession.shared.data(for: req)
      guard let arr = try JSONSerialization.jsonObject(with: data) as? [Any],
            let segments = arr.first as? [Any] else { return nil }
      var result = ""
      for seg in segments {
        if let pair = seg as? [Any], let part = pair.first as? String {
          result += part
        }
      }
      return result.isEmpty ? nil : result
    } catch { return nil }
  }

  // MARK: - Busca

  private struct Cand {
    var bundle: LyricsBundle
    var duration: Double?
    var score: Double
  }

  /// Etapa 1: sincronizadas em paralelo. Etapa 2 (se nada sincronizado): letras simples em paralelo.
  private static func search(track: Track, key: String) async -> LyricsBundle? {
    let stage1 = await withTaskGroup(of: [Cand].self) { group -> [Cand] in
      for url in lrclibGetURLs(track) {
        group.addTask { await lrclibGet(url: url, key: key, track: track) }
      }
      for url in lrclibSearchURLs(track) {
        group.addTask { await lrclibSearch(url: url, key: key, track: track) }
      }
      group.addTask { await neteaseLyrics(track: track, key: key) }
      var all: [Cand] = []
      for await part in group { all += part }
      return all
    }
    if let best = stage1.filter({ $0.bundle.synced }).max(by: { $0.score < $1.score }) {
      return best.bundle
    }
    let lrclibPlain = stage1.filter { !$0.bundle.synced }.max(by: { $0.score < $1.score })

    let stage2 = await withTaskGroup(of: (Int, Cand?).self) { group -> [(Int, Cand?)] in
      group.addTask { (0, await youtubeMusicLyrics(track: track, key: key)) }
      group.addTask { (1, await letrasMusBr(track: track, key: key)) }
      group.addTask { (2, await lyricsOvh(track: track, key: key)) }
      var all: [(Int, Cand?)] = []
      for await r in group { all.append(r) }
      return all
    }
    // ordem de preferência das letras simples
    let ordered = stage2.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
    if let first = ordered.first { return first.bundle }
    return lrclibPlain?.bundle
  }

  // MARK: LRCLIB

  private static func lrclibGetURLs(_ track: Track) -> [URL] {
    let title = cleanTitle(track.title)
    let fullArtist = stripTopic(track.artist)
    let firstArtist = cleanArtist(track.artist)
    let dur = track.duration > 10 ? String(Int(track.duration.rounded())) : nil
    var variants: [[(String, String)]] = []
    func v(_ t: String, _ a: String, album: Bool, duration: Bool) {
      var q: [(String, String)] = [("track_name", t), ("artist_name", a)]
      if album, !track.album.isEmpty { q.append(("album_name", track.album)) }
      if duration, let d = dur { q.append(("duration", d)) }
      variants.append(q)
    }
    v(title, fullArtist, album: true, duration: true)
    v(title, firstArtist, album: false, duration: true)
    v(title, fullArtist, album: false, duration: false)
    v(title, firstArtist, album: false, duration: false)
    var seen = Set<String>()
    var urls: [URL] = []
    for q in variants {
      var comps = URLComponents(string: "https://lrclib.net/api/get")
      comps?.queryItems = q.map { URLQueryItem(name: $0.0, value: $0.1) }
      if let u = comps?.url, seen.insert(u.absoluteString).inserted { urls.append(u) }
    }
    return urls
  }

  private static func lrclibSearchURLs(_ track: Track) -> [URL] {
    let title = cleanTitle(track.title)
    let firstArtist = cleanArtist(track.artist)
    var out: [URL] = []
    var a = URLComponents(string: "https://lrclib.net/api/search")
    a?.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: firstArtist)]
    if let u = a?.url { out.append(u) }
    var b = URLComponents(string: "https://lrclib.net/api/search")
    b?.queryItems = [URLQueryItem(name: "q", value: "\(title) \(firstArtist)")]
    if let u = b?.url { out.append(u) }
    return out
  }

  private static func lrclibRequest(_ url: URL) async -> Any? {
    await DiscNet.json(url.absoluteString, timeout: 6, headers: ["User-Agent": "LumeMusic/2.0 (https://lume.app)"])
  }

  private static func lrclibGet(url: URL, key: String, track: Track) async -> [Cand] {
    guard let obj = await lrclibRequest(url) as? [String: Any] else { return [] }
    return lrclibCands(obj, key: key, track: track, verify: false, bonus: 10)
  }

  private static func lrclibSearch(url: URL, key: String, track: Track) async -> [Cand] {
    guard let list = await lrclibRequest(url) as? [[String: Any]] else { return [] }
    var out: [Cand] = []
    for entry in list.prefix(15) { out += lrclibCands(entry, key: key, track: track, verify: true, bonus: 0) }
    return out
  }

  private static func durationOK(track: Track, candidate: Double?) -> Bool {
    guard track.duration > 10, let c = candidate, c > 10 else { return true }
    return abs(track.duration - c) <= 15
  }

  private static func durationPenalty(track: Track, candidate: Double?) -> Double {
    guard track.duration > 10, let c = candidate, c > 10 else { return 0 }
    return min(abs(track.duration - c), 30)
  }

  private static func lrclibCands(_ obj: [String: Any], key: String, track: Track, verify: Bool, bonus: Double) -> [Cand] {
    if (obj["instrumental"] as? Bool) == true { return [] }
    let duration = obj["duration"] as? Double
    guard durationOK(track: track, candidate: duration) else { return [] }
    if verify {
      let name = (obj["trackName"] as? String) ?? (obj["name"] as? String) ?? ""
      let artist = (obj["artistName"] as? String) ?? ""
      if !DiscText.titleLooselyMatches(name, track.title) && !DiscText.titleLooselyMatches(name, cleanTitle(track.title)) { return [] }
      if !track.artist.isEmpty && !DiscText.artistMatches(artist, stripTopic(track.artist)) { return [] }
    }
    let pen = durationPenalty(track: track, candidate: duration)
    var out: [Cand] = []
    if let synced = obj["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let lines = parseLRC(synced)
      if usable(lines.map { $0.text }) {
        out.append(Cand(
          bundle: LyricsBundle(trackKey: key, synced: true, lines: lines, source: "LRCLIB · Sincronizada", translatedToPT: false),
          duration: duration, score: 100 + bonus - pen))
      }
    }
    if let plain = obj["plainLyrics"] as? String, let lines = plainLines(plain) {
      out.append(Cand(
        bundle: LyricsBundle(trackKey: key, synced: false, lines: lines, source: "LRCLIB", translatedToPT: false),
        duration: duration, score: 50 + bonus - pen))
    }
    return out
  }

  // MARK: NetEase

  private static func neteaseLyrics(track: Track, key: String) async -> [Cand] {
    let title = cleanTitle(track.title)
    let artist = cleanArtist(track.artist)
    let q = "\(title) \(artist)".folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
    let headers = ["Referer": "https://music.163.com/", "Cookie": "appver=2.0.2"]
    guard let obj = await DiscNet.json("https://music.163.com/api/search/get?s=\(DiscNet.enc(q))&type=1&limit=6",
                                       timeout: 6, headers: headers) as? [String: Any],
          let songs = (obj["result"] as? [String: Any])?["songs"] as? [[String: Any]] else { return [] }
    var chosen: (id: Int, dur: Double?)?
    for s in songs {
      guard let id = s["id"] as? Int, let name = s["name"] as? String else { continue }
      let artists = ((s["artists"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
      let dur = (s["duration"] as? Double).map { $0 / 1000 }
      guard DiscText.titleLooselyMatches(name, title) || DiscText.titleLooselyMatches(name, track.title) else { continue }
      if !track.artist.isEmpty && !artists.contains(where: { DiscText.artistMatches($0, stripTopic(track.artist)) }) { continue }
      guard durationOK(track: track, candidate: dur) else { continue }
      chosen = (id, dur)
      break
    }
    guard let pick = chosen,
          let lobj = await DiscNet.json("https://music.163.com/api/song/lyric?id=\(pick.id)&lv=1&kv=1&tv=-1",
                                        timeout: 6, headers: headers) as? [String: Any],
          let lrc = (lobj["lrc"] as? [String: Any])?["lyric"] as? String else { return [] }
    var lines = parseLRC(lrc)
    // créditos do tipo "作词 : fulano"
    let credit = try? NSRegularExpression(pattern: #"^(作词|作曲|编曲|制作人?|混音|母带|录音|和声|吉他|贝斯|鼓|监制|企划|Lyrics?|Music|Composer|Producer|Arranged?|Written|Mix(ed)?|Master(ed)?)\b.{0,12}[:：]"#, options: .caseInsensitive)
    lines = lines.filter { l in
      guard let credit else { return true }
      return credit.firstMatch(in: l.text, range: NSRange(location: 0, length: (l.text as NSString).length)) == nil
    }
    lines = lines.enumerated().map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text, translated: nil) }
    guard usable(lines.map { $0.text }) else { return [] }
    return [Cand(bundle: LyricsBundle(trackKey: key, synced: true, lines: lines, source: "NetEase · Sincronizada", translatedToPT: false),
                 duration: pick.dur, score: 80 - durationPenalty(track: track, candidate: pick.dur))]
  }

  // MARK: YouTube Music

  private static let ytContext: [String: Any] = [
    "client": ["clientName": "WEB_REMIX", "clientVersion": "1.20250101.01.00", "hl": "pt", "gl": "BR"]
  ]
  private static let ytHeaders = ["Origin": "https://music.youtube.com", "Referer": "https://music.youtube.com/"]

  private static func youtubeMusicLyrics(track: Track, key: String) async -> Cand? {
    var vid = track.videoId
    if vid == nil || vid!.isEmpty { vid = await ytmFindVideoId(track: track) }
    guard let videoId = vid else { return nil }
    guard let next = await DiscNet.postJSON("https://music.youtube.com/youtubei/v1/next?prettyPrint=false",
                                            body: ["context": ytContext, "videoId": videoId],
                                            timeout: 6, headers: ytHeaders) else { return nil }
    var browseId: String?
    func walk(_ n: Any) {
      if browseId != nil { return }
      if let d = n as? [String: Any] {
        if let b = d["browseId"] as? String, b.hasPrefix("MPLY") { browseId = b; return }
        for v in d.values { walk(v) }
      } else if let a = n as? [Any] { for v in a { walk(v) } }
    }
    walk(next)
    guard let bid = browseId,
          let page = await DiscNet.postJSON("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                                            body: ["context": ytContext, "browseId": bid],
                                            timeout: 6, headers: ytHeaders) else { return nil }
    var text: String?
    func walk2(_ n: Any) {
      if text != nil { return }
      if let d = n as? [String: Any] {
        if let shelf = d["musicDescriptionShelfRenderer"] as? [String: Any],
           let runs = (shelf["description"] as? [String: Any])?["runs"] as? [[String: Any]] {
          text = runs.compactMap { $0["text"] as? String }.joined()
          return
        }
        for v in d.values { walk2(v) }
      } else if let a = n as? [Any] { for v in a { walk2(v) } }
    }
    walk2(page)
    guard let t = text, let lines = plainLines(t) else { return nil }
    return Cand(bundle: LyricsBundle(trackKey: key, synced: false, lines: lines, source: "YouTube Music", translatedToPT: false),
                duration: nil, score: 40)
  }

  private static func ytmFindVideoId(track: Track) async -> String? {
    let body: [String: Any] = [
      "context": ytContext,
      "query": "\(cleanTitle(track.title)) \(cleanArtist(track.artist))",
      "params": "EgWKAQIIAWoKEAkQBRAKEAMQBA==",
    ]
    guard let obj = await DiscNet.postJSON("https://music.youtube.com/youtubei/v1/search?prettyPrint=false",
                                           body: body, timeout: 6, headers: ytHeaders) else { return nil }
    var found: String?
    func walk(_ n: Any) {
      if found != nil { return }
      if let d = n as? [String: Any] {
        if let r = d["musicResponsiveListItemRenderer"] as? [String: Any] {
          let cols = (r["flexColumns"] as? [[String: Any]]) ?? []
          func col(_ i: Int) -> String {
            guard i < cols.count else { return "" }
            let runs = (((cols[i]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
            return runs.compactMap { $0["text"] as? String }.joined(separator: " ")
          }
          if DiscText.titleLooselyMatches(col(0), track.title) || DiscText.titleLooselyMatches(col(0), cleanTitle(track.title)),
             let vid = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String {
            found = vid
          }
          return
        }
        for v in d.values { walk(v) }
      } else if let a = n as? [Any] { for v in a { walk(v) } }
    }
    walk(obj)
    return found
  }

  // MARK: Letras.mus.br

  private static func letrasMusBr(track: Track, key: String) async -> Cand? {
    let title = cleanTitle(track.title)
    let artist = cleanArtist(track.artist)
    let q = "\(title) \(artist)".folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
    guard let raw = await DiscNet.text("https://solr.sscdn.co/letras/m1/?q=\(DiscNet.enc(q))&wt=json&rows=6", timeout: 5),
          let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")"), open < close,
          let data = String(raw[raw.index(after: open)..<close]).data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let docs = (obj["response"] as? [String: Any])?["docs"] as? [[String: Any]] else { return nil }
    guard let doc = docs.first(where: { d in
      guard let t = d["txt"] as? String, let a = d["art"] as? String, d["url"] is String, d["dns"] is String else { return false }
      return DiscText.titleLooselyMatches(t, title) && DiscText.artistMatches(a, stripTopic(track.artist))
    }), let dns = doc["dns"] as? String, let slug = doc["url"] as? String else { return nil }
    guard let html = await DiscNet.text("https://www.letras.mus.br/\(dns)/\(slug)/", timeout: 6,
                                        headers: ["Accept": "text/html", "Accept-Language": "pt-BR,pt;q=0.9"]),
          let marker = html.range(of: "lyric-original") ?? html.range(of: "cnt-letra") else { return nil }
    let rest = html[marker.upperBound...]
    guard let start = rest.firstIndex(of: ">") else { return nil }
    let body = rest[rest.index(after: start)...]
    let end = body.range(of: "</div>")?.lowerBound ?? body.endIndex
    var chunk = String(body[..<end])
    chunk = chunk.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
    chunk = chunk.replacingOccurrences(of: #"</p>"#, with: "\n\n", options: .regularExpression)
    chunk = chunk.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    for (k, v) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
      chunk = chunk.replacingOccurrences(of: k, with: v)
    }
    guard let lines = plainLines(chunk) else { return nil }
    return Cand(bundle: LyricsBundle(trackKey: key, synced: false, lines: lines, source: "Letras.mus.br", translatedToPT: false),
                duration: nil, score: 45)
  }

  // MARK: Lyrics.ovh

  private static func lyricsOvh(track: Track, key: String) async -> Cand? {
    let title = cleanTitle(track.title)
    var artists = [cleanArtist(track.artist)]
    let full = stripTopic(track.artist)
    if full != artists[0] { artists.append(full) }
    for a in artists {
      guard let obj = await DiscNet.json("https://api.lyrics.ovh/v1/\(DiscNet.enc(a))/\(DiscNet.enc(title))", timeout: 6) as? [String: Any],
            var text = obj["lyrics"] as? String else { continue }
      if text.lowercased().hasPrefix("paroles de la chanson"), let nl = text.firstIndex(of: "\n") {
        text = String(text[text.index(after: nl)...])
      }
      text = text.replacingOccurrences(of: "\r\n", with: "\n")
      if let lines = plainLines(text) {
        return Cand(bundle: LyricsBundle(trackKey: key, synced: false, lines: lines, source: "Lyrics.ovh", translatedToPT: false),
                    duration: nil, score: 30)
      }
    }
    return nil
  }

  // MARK: Validação

  /// Descarta letras vazias/instrumentais/curtas demais.
  private static func usable(_ texts: [String]) -> Bool {
    let real = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != "♪" }
    guard real.count >= 3 else { return false }
    if real.count <= 6 {
      let joined = real.joined(separator: " ").lowercased()
      if joined.contains("instrumental") || joined.contains("纯音乐") || joined.contains("no lyrics") { return false }
    }
    return true
  }

  private static func plainLines(_ text: String) -> [LyricLine]? {
    let raw = text.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .filter { !($0.hasPrefix("[") && $0.hasSuffix("]")) }
    guard usable(raw) else { return nil }
    return raw.enumerated().map { LyricLine(id: $0.offset, time: Double($0.offset) * 3.5, text: $0.element, translated: nil) }
  }

  private func save(_ bundle: LyricsBundle) {
    memCache[bundle.trackKey] = bundle
    if let data = try? JSONEncoder().encode(bundle) {
      try? data.write(to: diskURL(for: bundle.trackKey), options: .atomic)
    }
  }

  static func parseLRC(_ lrc: String) -> [LyricLine] {
    let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    var temp: [(Double, String)] = []
    for rawLine in lrc.components(separatedBy: .newlines) {
      let ns = rawLine as NSString
      let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: ns.length))
      guard !matches.isEmpty else { continue }
      let textStart = matches.last!.range.location + matches.last!.range.length
      let text = ns.substring(from: textStart).trimmingCharacters(in: .whitespacesAndNewlines)
      for m in matches {
        let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
        let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
        var frac: Double = 0
        if m.range(at: 3).location != NSNotFound {
          let fStr = ns.substring(with: m.range(at: 3))
          frac = (Double(fStr) ?? 0) / pow(10.0, Double(fStr.count))
        }
        let t = min * 60.0 + sec + frac
        temp.append((t, text.isEmpty ? "♪" : text))
      }
    }
    temp.sort { $0.0 < $1.0 }
    return temp.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1, translated: nil) }
  }

  private static func stripTopic(_ s: String) -> String {
    s.replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func cleanTitle(_ s: String) -> String {
    var out = s
    let kw = #"(official|oficial|audio|áudio|video|vídeo|lyrics?|letra|clipe|clip|ao vivo|live|remaster(ed)?|visuali[sz]er|feat\.?|ft\.?|featuring|part\.?|hd|4k|explicit)"#
    let patterns = [
      // (…) com palavra-chave de "ruído"
      #"\s*\([^)]*\b"# + kw + #"\b[^)]*\)"#,
      #"\s*\[[^\]]*\]"#,
      // " - Ao Vivo ...", " - Remastered 2011", " - Topic", " - Official Video"
      #"\s+[-–—]\s*(ao vivo|live|remaster(ed)?|official|oficial|topic|\d{4} remaster)\b.*$"#,
      #"\s*\|.*$"#,
      #"\s+(feat\.?|ft\.?|featuring)\s+.*$"#,
      #"\s+Official\s+(Music\s+)?(Video|Audio|Lyric Video|Clipe)\s*$"#,
      #"\s+Remaster(ed)?(\s+\d{4})?\s*$"#,
      #"\s*-\s*Topic$"#,
    ]
    for p in patterns {
      out = out.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
    }
    out = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return out.isEmpty ? s.trimmingCharacters(in: .whitespacesAndNewlines) : out
  }

  static func cleanArtist(_ s: String) -> String {
    let base = s.replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: #"\s+(feat\.?|ft\.?|featuring)\s+.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
    return base.components(separatedBy: CharacterSet(charactersIn: ",&")).first?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? s
  }
}
