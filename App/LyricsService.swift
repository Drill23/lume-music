import Foundation

/// Synchronized karaoke lyrics (LRCLIB) + 1-click line-by-line PT-BR translation with disk caching.
actor LyricsService {
  static let shared = LyricsService()

  private var memCache: [String: LyricsBundle] = [:]

  private var cacheDir: URL {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("LumeMusicLyrics", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func diskURL(for key: String) -> URL {
    cacheDir.appendingPathComponent("\(key).json")
  }

  func fetchLyrics(for track: Track) async -> LyricsBundle? {
    let key = Track.stableId(title: track.title, artist: track.artist)
    if let mem = memCache[key] { return mem }
    if let data = try? Data(contentsOf: diskURL(for: key)),
       let saved = try? JSONDecoder().decode(LyricsBundle.self, from: data) {
      memCache[key] = saved
      return saved
    }

    // 1. Exact LRCLIB match
    let cleanTitle = Self.cleanTitle(track.title)
    let cleanArtist = Self.cleanArtist(track.artist)
    var comps = URLComponents(string: "https://lrclib.net/api/get")
    comps?.queryItems = [
      URLQueryItem(name: "track_name", value: cleanTitle),
      URLQueryItem(name: "artist_name", value: cleanArtist),
    ]
    if track.duration > 10 {
      comps?.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
    }
    if let url = comps?.url, let bundle = await loadLRCLIBObject(url: url, key: key) {
      save(bundle)
      return bundle
    }

    // 2. Search LRCLIB fallback
    var scomps = URLComponents(string: "https://lrclib.net/api/search")
    scomps?.queryItems = [URLQueryItem(name: "q", value: "\(cleanTitle) \(cleanArtist)")]
    if let url = scomps?.url, let bundle = await loadLRCLIBSearch(url: url, key: key, targetDuration: track.duration) {
      save(bundle)
      return bundle
    }
    return nil
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

  private func loadLRCLIBObject(url: URL, key: String) async -> LyricsBundle? {
    var req = URLRequest(url: url)
    req.setValue("LumeMusic/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard (resp as? HTTPURLResponse)?.statusCode == 200,
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
      return parseLRCLIBEntry(obj, key: key)
    } catch { return nil }
  }

  private func loadLRCLIBSearch(url: URL, key: String, targetDuration: Double) async -> LyricsBundle? {
    var req = URLRequest(url: url)
    req.setValue("LumeMusic/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard (resp as? HTTPURLResponse)?.statusCode == 200,
            let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], !list.isEmpty else { return nil }
      // Prefer synced lyrics closest to duration
      let sorted = list.sorted { a, b in
        let sa = (a["syncedLyrics"] as? String)?.isEmpty == false
        let sb = (b["syncedLyrics"] as? String)?.isEmpty == false
        if sa != sb { return sa }
        if targetDuration > 10 {
          let da = abs(((a["duration"] as? Double) ?? 0) - targetDuration)
          let db = abs(((b["duration"] as? Double) ?? 0) - targetDuration)
          return da < db
        }
        return false
      }
      for entry in sorted {
        if let parsed = parseLRCLIBEntry(entry, key: key) { return parsed }
      }
    } catch {}
    return nil
  }

  private func parseLRCLIBEntry(_ obj: [String: Any], key: String) -> LyricsBundle? {
    if let synced = obj["syncedLyrics"] as? String, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let lines = Self.parseLRC(synced)
      if !lines.isEmpty {
        return LyricsBundle(trackKey: key, synced: true, lines: lines, source: "LRCLIB · Sincronizada", translatedToPT: false)
      }
    }
    if let plain = obj["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let raw = plain.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      let lines = raw.enumerated().map { LyricLine(id: $0.offset, time: Double($0.offset) * 3.5, text: $0.element, translated: nil) }
      if !lines.isEmpty {
        return LyricsBundle(trackKey: key, synced: false, lines: lines, source: "LRCLIB · Letra", translatedToPT: false)
      }
    }
    return nil
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

  static func cleanTitle(_ s: String) -> String {
    var out = s
    let patterns = [#"\s*\((Official|Audio|Video|Lyrics|Clipe|Ao Vivo|Remaster)[^)]*\)"#, #"\s*\[[^\]]*\]"#, #"\s*-\s*Topic$"#]
    for p in patterns {
      out = out.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func cleanArtist(_ s: String) -> String {
    s.replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
      .components(separatedBy: CharacterSet(charactersIn: ",&")).first?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? s
  }
}
