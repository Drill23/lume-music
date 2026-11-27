import SwiftUI

struct UpdateOffer: Equatable {
  var build: Int
  var versionName: String
  var url: String
  var notes: String
  var mandatory: Bool
}

enum UpdateCheckOutcome {
  case found(UpdateOffer)
  case upToDate
  case offline
}

/// Atualizações automáticas (ao abrir, a cada 6 h e sob demanda em Ajustes):
/// 1) Painel (/api/app/update) — prioridade máxima (atualizações obrigatórias / notas do admin)
/// 2) Manifesto do site (https://lume-music-enq.pages.dev/version.json) — CDN sem limite de taxa
/// 3) GitHub Releases (api.github.com/repos/Drill23/lume-music/releases/latest) — fallback automático
@MainActor
final class UpdateService: ObservableObject {
  static let shared = UpdateService()

  private static let siteManifestURL = "https://lume-music-enq.pages.dev/version.json"
  private static let githubLatestURL = "https://api.github.com/repos/Drill23/lume-music/releases/latest"

  @Published private(set) var offer: UpdateOffer?
  @Published private(set) var checking = false

  private var loop: Task<Void, Never>?
  private let defaults = UserDefaults.standard
  private let debug = ProcessInfo.processInfo.arguments.contains("-LMDebugUpdate")

  /// Inicia a verificação (chamar uma vez ao abrir o app).
  func start() {
    guard loop == nil else { return }
    loop = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      while !Task.isCancelled {
        _ = await self?.check(manual: false)
        try? await Task.sleep(for: .seconds(6 * 3600))
      }
    }
  }

  static func compareVersions(_ a: String, _ b: String) -> Int {
    func parts(_ v: String) -> [Int] {
      let clean = v.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
        .split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
      return clean.split(separator: ".").map { seg in
        Int(seg.filter(\.isNumber)) ?? 0
      }
    }
    let pa = parts(a)
    let pb = parts(b)
    let count = max(pa.count, pb.count)
    for i in 0..<count {
      let da = i < pa.count ? pa[i] : 0
      let db = i < pb.count ? pb[i] : 0
      if da != db { return da < db ? -1 : 1 }
    }
    return 0
  }

  private func isNewer(_ o: UpdateOffer) -> Bool {
    let curBuild = Int(AccessConfig.buildNumber) ?? 0
    if o.build > 0 && curBuild > 0 && o.build > curBuild { return true }
    return Self.compareVersions(o.versionName, AccessConfig.appVersion) > 0
  }

  @discardableResult
  func check(manual: Bool = false) async -> UpdateCheckOutcome {
    if debug {
      let o = UpdateOffer(build: 999, versionName: "5.2.0", url: "https://example.com/Lume-Music-5.2.0.ipa",
                          notes: "• Player mais rápido\n• Correções de estabilidade\n• Novos temas de vidro", mandatory: false)
      offer = o
      return .found(o)
    }
    if manual { checking = true }
    defer { if manual { checking = false } }

    var anySuccess = false

    // 1. Painel administrativo
    let access = AccessService.shared
    await access.ensureConfig()
    if access.panelAvailable {
      do {
        let (status, json) = try await access.send("GET", "/api/app/update",
                                                   query: ["platform": AccessConfig.platform, "build": AccessConfig.buildNumber, "app": AccessConfig.appVersion], timeout: 10)
        if status == 200 {
          anySuccess = true
          if let o = parsePanel(json), isNewer(o) {
            return presentOrDefer(o, manual: manual)
          }
        }
      } catch {
        // segue para o manifesto público do site
      }
    }

    // 2. Manifesto público do site (Cloudflare Pages, sem limite de taxa)
    if let (ok, o) = await fetchSiteManifest() {
      if ok { anySuccess = true }
      if let o, isNewer(o) {
        return presentOrDefer(o, manual: manual)
      }
    }

    // 3. Fallback direto no GitHub Releases
    if let (ok, o) = await fetchGitHubLatest() {
      if ok { anySuccess = true }
      if let o, isNewer(o) {
        return presentOrDefer(o, manual: manual)
      }
    }

    if anySuccess {
      offer = nil
      return .upToDate
    }
    return .offline
  }

  private func presentOrDefer(_ o: UpdateOffer, manual: Bool) -> UpdateCheckOutcome {
    if !manual && !o.mandatory, let until = defaults.object(forKey: deferKey(o)) as? Date, until > Date() {
      return .upToDate
    }
    offer = o
    return .found(o)
  }

  private func num(_ v: Any?) -> Int {
    Int((v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue ?? 0)
  }

  private func parsePanel(_ json: [String: Any]) -> UpdateOffer? {
    guard (json["ok"] as? Bool) == true, (json["available"] as? Bool) == true,
          let url = json["url"] as? String, url.hasPrefix("https://") else { return nil }
    let build = num(json["build"])
    let version = (json["versionName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let versionName = (version?.isEmpty == false) ? version! : (build > 0 ? "\(build)" : "nova")
    let notes = ((json["notes"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return UpdateOffer(build: build, versionName: versionName, url: url, notes: notes, mandatory: (json["mandatory"] as? Bool) ?? false)
  }

  private func fetchJSON(_ urlString: String) async -> (Bool, [String: Any]?) {
    guard let url = URL(string: urlString) else { return (false, nil) }
    var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
    req.setValue("LumeMusic/\(AccessConfig.appVersion)", forHTTPHeaderField: "User-Agent")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return (false, nil) }
      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      return (obj != nil, obj)
    } catch {
      return (false, nil)
    }
  }

  private func fetchSiteManifest() async -> (Bool, UpdateOffer?)? {
    let ts = Int(Date().timeIntervalSince1970)
    let (ok, root) = await fetchJSON("\(Self.siteManifestURL)?t=\(ts)")
    guard ok, let root else { return (false, nil) }
    let plat = root["ios"] as? [String: Any]
    func str(_ k: String) -> String? { (plat?[k] as? String) ?? (root[k] as? String) }
    func bool(_ k: String) -> Bool { (plat?[k] as? Bool) ?? (root[k] as? Bool) ?? false }
    let build = num(plat?["build"] ?? root["build"])
    guard let url = str("url"), url.hasPrefix("https://") else { return (true, nil) }
    let ver = str("versionName")?.trimmingCharacters(in: .whitespacesAndNewlines)
    let versionName = (ver?.isEmpty == false) ? ver! : (build > 0 ? "\(build)" : "")
    guard !versionName.isEmpty else { return (true, nil) }
    let notes = (str("notes") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return (true, UpdateOffer(build: build, versionName: versionName, url: url, notes: notes, mandatory: bool("mandatory")))
  }

  private func fetchGitHubLatest() async -> (Bool, UpdateOffer?)? {
    let (ok, root) = await fetchJSON(Self.githubLatestURL)
    guard ok, let root else { return (false, nil) }
    if (root["draft"] as? Bool) == true || (root["prerelease"] as? Bool) == true { return (true, nil) }
    guard let rawTag = root["tag_name"] as? String else { return (true, nil) }
    let versionName = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
    guard !versionName.isEmpty else { return (true, nil) }
    let assets = (root["assets"] as? [[String: Any]]) ?? []
    let match = assets.first { (($0["name"] as? String) ?? "").caseInsensitiveCompare("Lume-Music-iPhone.ipa") == .orderedSame }
      ?? assets.first { (($0["name"] as? String) ?? "").lowercased().hasSuffix(".ipa") }
    guard let url = match?["browser_download_url"] as? String, url.hasPrefix("https://") else { return (true, nil) }
    let rawNotes = ((root["body"] as? String) ?? "")
      .replacingOccurrences(of: "(?m)^#{1,6}\\s*", with: "", options: .regularExpression)
      .replacingOccurrences(of: "**", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let notes = String(rawNotes.prefix(700))
    return (true, UpdateOffer(build: 0, versionName: versionName, url: url, notes: notes, mandatory: false))
  }

  private func deferKey(_ offer: UpdateOffer) -> String {
    offer.build > 0 ? "lume.update.deferred.\(offer.build)" : "lume.update.deferred.v.\(offer.versionName)"
  }

  /// "Depois": adia 24 h para aquela versão.
  func postpone() {
    guard let o = offer, !o.mandatory else { return }
    defaults.set(Date().addingTimeInterval(24 * 3600), forKey: deferKey(o))
    offer = nil
  }

  func openDownload() {
    guard let o = offer, let url = URL(string: o.url) else { return }
    UIApplication.shared.open(url)
    if !o.mandatory { offer = nil }
  }
}

struct UpdatePopupCard: View {
  let offer: UpdateOffer
  @ObservedObject private var update = UpdateService.shared

  var body: some View {
    GlassPopup {
      ZStack {
        Circle().fill(Color.clear).frame(width: 72, height: 72).glassCircle(tint: Theme.sky.opacity(0.35))
        Image(systemName: "arrow.down.circle.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.prismDiagonal)
      }
      VStack(spacing: 8) {
        Text("Nova versão \(offer.versionName) disponível")
          .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
        if !offer.notes.isEmpty {
          ScrollView {
            Text(offer.notes)
              .font(Theme.font(14)).foregroundStyle(Theme.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 140)
          .padding(12)
          .glass(16)
        }
        Text("Depois de baixar, instale pelo LiveContainer sem perder suas playlists.")
          .font(Theme.font(12.5)).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
      }
      VStack(spacing: 10) {
        PrismButton(title: "Atualizar agora", systemImage: "arrow.down.to.line", height: 50) { update.openDownload() }
        if !offer.mandatory {
          GlassButton(title: "Depois", height: 48) { update.postpone() }
        }
      }
    }
  }
}
