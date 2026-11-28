import AppIntents
import Foundation

// Compilado no app E na extensão do widget (contrato 5.2 D).
// O app grava um JSON pequeno + a capa reduzida no container do App Group; o widget só lê.

/// App Group `group.com.adriano.lumemusic`. O SideStore renomeia o grupo (acrescenta o Team ID) e anota o nome novo em
/// `ALTAppGroups` no Info.plist; testamos cada candidato e ficamos com o primeiro que o iOS libera.
/// SEM App Group (ex.: dentro do LiveContainer) tudo aqui devolve nil e o app funciona normal, só não grava nada.
enum LumeGroup {
  static let baseIdentifier = "group.com.adriano.lumemusic"

  static let identifier: String? = {
    var candidates: [String] = []
    if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
      candidates += alt.filter { $0.hasPrefix(baseIdentifier) } + alt
    }
    if let team = teamSuffix { candidates.append("\(baseIdentifier).\(team)") }
    candidates.append(baseIdentifier)
    var seen = Set<String>()
    for c in candidates where seen.insert(c).inserted {
      if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: c) != nil { return c }
    }
    return nil
  }()

  /// Team ID que o SideStore acrescenta ao bundle (com.adriano.lumemusic.ios.ABCDE12345).
  private static var teamSuffix: String? {
    let parts = (Bundle.main.bundleIdentifier ?? "").split(separator: ".").map(String.init)
    return parts.first { p in
      p.count == 10 && p.allSatisfy { $0.isNumber || ($0.isLetter && $0.isUppercase) }
    }
  }

  static let containerURL: URL? = {
    guard let id = identifier else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
  }()

  static func fileURL(_ name: String) -> URL? { containerURL?.appendingPathComponent(name) }
}

/// O que o widget mostra.
struct WidgetNowPlaying: Codable, Equatable {
  var title: String
  var artist: String
  var isPlaying: Bool
  var videoId: String?
  var trackId: String?
  var artworkURL: String?
  /// Identifica a capa gravada (muda quando a faixa muda).
  var coverKey: String?
}

enum WidgetStore {
  static let kind = "LumeNowPlaying"
  private static let jsonName = "nowplaying.json"
  private static let coverName = "cover.jpg"

  static func read() -> WidgetNowPlaying? {
    guard let url = LumeGroup.fileURL(jsonName), let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(WidgetNowPlaying.self, from: data)
  }

  static func write(_ value: WidgetNowPlaying) {
    guard let url = LumeGroup.fileURL(jsonName), let data = try? JSONEncoder().encode(value) else { return }
    try? data.write(to: url, options: .atomic)
  }

  static func writeCover(_ jpeg: Data?) {
    guard let url = LumeGroup.fileURL(coverName) else { return }
    if let jpeg { try? jpeg.write(to: url, options: .atomic) } else { try? FileManager.default.removeItem(at: url) }
  }

  static func coverPath() -> String? {
    guard let url = LumeGroup.fileURL(coverName), FileManager.default.fileExists(atPath: url.path) else { return nil }
    return url.path
  }
}

// MARK: - Botões do widget (executam no processo do app)

/// `AudioPlaybackIntent` roda dentro do app (mesmo em segundo plano), então pode usar o AudioPlayer direto.
/// Na extensão o corpo fica vazio: o sistema nunca executa o `perform` lá.
struct LumeTogglePlayIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Tocar ou pausar"
  static let description = IntentDescription("Toca ou pausa a música do Lume Music.")
  static let isDiscoverable = false
  func perform() async throws -> some IntentResult {
    #if LUME_APP
    await LumeRemoteControl.run(.toggle)
    #endif
    return .result()
  }
}

struct LumeNextIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Próxima música"
  static let description = IntentDescription("Pula para a próxima música do Lume Music.")
  static let isDiscoverable = false
  func perform() async throws -> some IntentResult {
    #if LUME_APP
    await LumeRemoteControl.run(.next)
    #endif
    return .result()
  }
}

struct LumePreviousIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Música anterior"
  static let description = IntentDescription("Volta para a música anterior do Lume Music.")
  static let isDiscoverable = false
  func perform() async throws -> some IntentResult {
    #if LUME_APP
    await LumeRemoteControl.run(.previous)
    #endif
    return .result()
  }
}
