import Foundation

/// Core domain models for Lume Music (Codable, Hashable, lightweight).
struct Track: Identifiable, Codable, Hashable {
  var id: String
  var videoId: String?
  var title: String
  var artist: String
  var album: String
  var duration: Double
  var artworkURL: String
  var animatedArtworkURL: String?
  var sourceService: String
  var isExplicit: Bool

  init(
    id: String? = nil,
    videoId: String? = nil,
    title: String,
    artist: String,
    album: String = "",
    duration: Double = 0,
    artworkURL: String = "",
    animatedArtworkURL: String? = nil,
    sourceService: String = "Lume",
    isExplicit: Bool = false
  ) {
    let cleanId = id ?? videoId ?? Self.stableId(title: title, artist: artist)
    self.id = cleanId
    self.videoId = videoId
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
    self.album = album.trimmingCharacters(in: .whitespacesAndNewlines)
    self.duration = max(0, duration)
    self.artworkURL = artworkURL
    self.animatedArtworkURL = animatedArtworkURL
    self.sourceService = sourceService
    self.isExplicit = isExplicit
  }

  static func stableId(title: String, artist: String) -> String {
    let raw = "\(artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))::\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    var h: UInt64 = 14695981039346656037
    for b in raw.utf8 { h ^= UInt64(b); h &*= 1099511628211 }
    return String(format: "tr_%016llx", h)
  }

  var searchQuery: String {
    artist.isEmpty ? title : "\(title) \(artist)"
  }

  var formattedDuration: String {
    guard duration > 0 else { return "" }
    let s = Int(duration.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
  }
}

struct AlbumShowcase: Identifiable, Codable, Hashable {
  var id: String
  var title: String
  var artist: String
  var artworkURL: String
  var animatedArtworkURL: String?
  var year: String
  var genre: String
  var tracks: [Track]
  var releaseDate: String? = nil   // "2026-11-20"
  var kind: String? = nil          // "Álbum", "Single", "EP"
  var deezerId: Int? = nil
  var itunesId: Int? = nil
}

struct MusicPlaylist: Identifiable, Codable, Hashable {
  var id: String
  var name: String
  var subtitle: String
  var artworkURL: String
  var trackIds: [String]
  var sourceBadge: String
  var createdAt: Date

  init(
    id: String = UUID().uuidString,
    name: String,
    subtitle: String = "",
    artworkURL: String = "",
    trackIds: [String] = [],
    sourceBadge: String = "Lume",
    createdAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.subtitle = subtitle
    self.artworkURL = artworkURL
    self.trackIds = trackIds
    self.sourceBadge = sourceBadge
    self.createdAt = createdAt
  }
}

struct LyricLine: Identifiable, Codable, Hashable {
  var id: Int
  var time: Double
  var text: String
  var translated: String?
}

struct LyricsBundle: Codable, Hashable {
  var trackKey: String
  var synced: Bool
  var lines: [LyricLine]
  var source: String
  var translatedToPT: Bool
}

enum VisualizerStyle: String, CaseIterable, Codable, Identifiable {
  // Raw values are persisted in the library snapshot — never rename them.
  case ares = "Ondas Ares"
  case aurora = "Espectro"
  case orb = "Orbe"
  case off = "Desligado"

  var id: String { rawValue }
  var title: String {
    switch self {
    case .ares: return "Ondas 3D"
    case .aurora: return "Espectro"
    case .orb: return "Orbe"
    case .off: return "Desligado"
    }
  }
  var icon: String {
    switch self {
    case .ares: return "mountain.2.fill"
    case .aurora: return "chart.bar.fill"
    case .orb: return "circle.hexagongrid.fill"
    case .off: return "eye.slash"
    }
  }
}

enum RepeatMode: String, Codable {
  case off, all, one
  var next: RepeatMode {
    switch self {
    case .off: return .all
    case .all: return .one
    case .one: return .off
    }
  }
  var icon: String {
    switch self {
    case .off: return "repeat"
    case .all: return "repeat"
    case .one: return "repeat.1"
    }
  }
}

enum SoundProfile: String, CaseIterable, Codable, Identifiable {
  case natural = "Natural"
  case bass = "Grave Intenso"
  case vocal = "Voz & Karaokê"
  case cinema = "Cinema 3D"
  case night = "Modo Noite"

  var id: String { rawValue }
  var subtitle: String {
    switch self {
    case .natural: return "Equilíbrio fiel ao estúdio"
    case .bass: return "Sub-graves encorpados e pulsantes"
    case .vocal: return "Voz em destaque para acompanhar letras"
    case .cinema: return "Palco amplo e espacial"
    case .night: return "Volume suave sem picos bruscos"
    }
  }
}

enum SleepTimerOption: Int, CaseIterable, Identifiable {
  case off = 0
  case m15 = 15
  case m30 = 30
  case m45 = 45
  case m60 = 60
  case endOfTrack = -1

  var id: Int { rawValue }
  var label: String {
    switch self {
    case .off: return "Desligado"
    case .m15: return "15 minutos"
    case .m30: return "30 minutos"
    case .m45: return "45 minutos"
    case .m60: return "1 hora"
    case .endOfTrack: return "Fim desta faixa"
    }
  }
}

enum PlayerSurfaceTab: String, CaseIterable, Identifiable {
  case artwork = "Capa"
  case vinyl = "Vinil"
  case cassette = "K7"
  case waves = "Ondas"
  case lyrics = "Letra"

  var id: String { rawValue }
  var icon: String {
    switch self {
    case .artwork: return "square.fill"
    case .vinyl: return "record.circle"
    case .cassette: return "recordingtape"
    case .waves: return "waveform"
    case .lyrics: return "quote.bubble"
    }
  }
}

enum AppTab: String, CaseIterable, Identifiable {
  case home = "Início"
  case explore = "Novidades"
  case library = "Biblioteca"
  case search = "Buscar"

  var id: String { rawValue }
  var icon: String {
    switch self {
    case .home: return "house.fill"
    case .explore: return "square.grid.2x2.fill"
    case .library: return "square.stack.fill"
    case .search: return "magnifyingglass"
    }
  }
  static var bar: [AppTab] { [.home, .explore, .library] }
}

struct MoodCategory: Identifiable, Hashable {
  let id: String
  let title: String
  let query: String
  let icon: String
  let hexA: UInt32
  let hexB: UInt32

  static let presets: [MoodCategory] = [
    MoodCategory(id: "sertanejo", title: "Sertanejo", query: "top sertanejo brasil sucessos 2026", icon: "guitars.fill", hexA: 0xFFB547, hexB: 0xD9534F),
    MoodCategory(id: "pop", title: "Pop Hits", query: "top pop hits 2026", icon: "star.fill", hexA: 0xFF6B8B, hexB: 0x7C3AED),
    MoodCategory(id: "rock", title: "Rock", query: "rock classics greatest hits", icon: "bolt.fill", hexA: 0xF97316, hexB: 0x991B1B),
    MoodCategory(id: "hiphop", title: "Hip-Hop & Trap", query: "hip hop trap hits 2026", icon: "headphones", hexA: 0x6366F1, hexB: 0xEC4899),
    MoodCategory(id: "mpb", title: "MPB & Brasil", query: "mpb pagode melhores musicas brasil", icon: "sun.max.fill", hexA: 0x10B981, hexB: 0x059669),
    MoodCategory(id: "eletronica", title: "Eletrônica", query: "electronic dance house hits 2026", icon: "waveform", hexA: 0x06B6D4, hexB: 0x3B82F6),
    MoodCategory(id: "lofi", title: "Foco & Lo-Fi", query: "lofi chill beats study focus", icon: "moon.stars.fill", hexA: 0x8B5CF6, hexB: 0x1E3A8A),
    MoodCategory(id: "treino", title: "Treino", query: "workout gym motivation music hits", icon: "flame.fill", hexA: 0xEF4444, hexB: 0xF59E0B),
  ]
}
