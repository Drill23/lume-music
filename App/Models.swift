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
  case solarRing = "Anel Solar"
  case oscilloscope = "Osciloscópio"
  case nebula = "Nebulosa"
  case off = "Desligado"

  var id: String { rawValue }
  var title: String {
    switch self {
    case .ares: return "Ondas Líquidas"
    case .aurora: return "Espectro"
    case .orb: return "Orbe"
    case .solarRing: return "Anel Solar"
    case .oscilloscope: return "Osciloscópio"
    case .nebula: return "Nebulosa"
    case .off: return "Desligado"
    }
  }
  var icon: String {
    switch self {
    case .ares: return "water.waves"
    case .aurora: return "chart.bar.fill"
    case .orb: return "circle.hexagongrid.fill"
    case .solarRing: return "sun.max.circle.fill"
    case .oscilloscope: return "waveform.path.ecg"
    case .nebula: return "sparkles"
    case .off: return "eye.slash"
    }
  }
  /// 5.0: "Anel Solar" duplicava o Orbe (e era o mais pesado) — saiu do menu. O raw value continua
  /// válido no disco e é mapeado para o Orbe; "Desligado" vira as Ondas Líquidas no palco.
  static var activeStyles: [VisualizerStyle] { [.ares, .aurora, .orb, .oscilloscope, .nebula] }
  var resolved: VisualizerStyle {
    switch self {
    case .solarRing: return .orb
    case .off: return .ares
    default: return self
    }
  }
}

/// Arte mostrada na tela de bloqueio / Central de Controle (MPNowPlayingInfo).
enum LockArtStyle: String, CaseIterable, Identifiable {
  // Raw values persistidos em UserDefaults ("lume.lockArtStyle") — não renomear.
  case automatic = "auto"
  case cover = "capa"
  case vinyl = "vinil"
  case cassette = "k7"

  var id: String { rawValue }
  var title: String {
    switch self {
    case .automatic: return "Automático"
    case .cover: return "Capa"
    case .vinyl: return "Vinil"
    case .cassette: return "Fita K7"
    }
  }
}

enum TurntableFinish: String, CaseIterable, Codable, Identifiable {
  case obsidian = "Obsidian Pro"
  case silver = "Prata Estúdio"
  case walnut = "Nogueira Vintage"
  case gold = "Titânio Dourado"

  var id: String { rawValue }
  var shaderIndex: Float {
    switch self {
    case .silver: return 0
    case .obsidian: return 1
    case .walnut: return 2
    case .gold: return 3
    }
  }
  var isDarkChassis: Bool {
    switch self {
    case .obsidian, .walnut: return true
    case .silver, .gold: return false
    }
  }
}

enum VinylEdition: String, CaseIterable, Codable, Identifiable {
  case classicBlack = "Preto 180g"
  case prismCrystal = "Cristal Prisma"
  case limitedGold = "Ouro Limitado"
  case whiteMarble = "Mármore Branco"

  var id: String { rawValue }
  var shaderIndex: Float {
    switch self {
    case .classicBlack: return 0
    case .prismCrystal: return 1
    case .limitedGold: return 2
    case .whiteMarble: return 3
    }
  }
}

enum CassetteStyle: String, CaseIterable, Codable, Identifiable {
  case smokedStudio = "Fumê Estúdio"
  case crystalClear = "Cristal Transparente"
  case metallicChrome = "Cromo Metálico"
  case vintageCream = "Vintage Creme"

  var id: String { rawValue }
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
  case custom = "Personalizado"

  var id: String { rawValue }
  var subtitle: String {
    switch self {
    case .natural: return "Equilíbrio fiel ao estúdio"
    case .bass: return "Sub-graves encorpados e pulsantes"
    case .vocal: return "Voz em destaque para acompanhar letras"
    case .cinema: return "Palco amplo e espacial"
    case .night: return "Volume suave sem picos bruscos"
    case .custom: return "Ajuste fino nas 5 bandas do equalizador"
    }
  }

  /// Ganho em dB para [60 Hz, 230 Hz, 910 Hz, 3.6 kHz, 14 kHz].
  var defaultGains: [Float] {
    switch self {
    case .natural: return [0, 0, 0, 0, 0]
    case .bass: return [6.5, 4.0, -0.5, 1.0, 2.5]
    case .vocal: return [-2.5, -0.5, 4.0, 4.5, 1.5]
    case .cinema: return [4.5, 1.5, -1.0, 3.0, 4.5]
    case .night: return [-3.0, 1.0, 2.0, 1.0, -2.5]
    case .custom: return [0, 0, 0, 0, 0]
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
  case explore = "Explorar"
  case library = "Biblioteca"
  case search = "Buscar"

  var id: String { rawValue }
  var icon: String {
    switch self {
    case .home: return "house.fill"
    case .explore: return "safari.fill"
    case .library: return "square.stack.fill"
    case .search: return "magnifyingglass"
    }
  }
  static var bar: [AppTab] { [.home, .explore, .library] }
}

struct MoodCategory: Identifiable, Hashable, Codable {
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

  static let activities: [MoodCategory] = [
    MoodCategory(id: "act_treino", title: "Treino & Academia", query: "workout gym motivation music hits 2026", icon: "flame.fill", hexA: 0xEF4444, hexB: 0xF97316),
    MoodCategory(id: "act_foco", title: "Foco & Estudo", query: "lofi chill beats study focus instrumental", icon: "brain.head.profile", hexA: 0x6366F1, hexB: 0x1E3A8A),
    MoodCategory(id: "act_relax", title: "Relaxar & Chill", query: "acoustic chill vibes relax music", icon: "leaf.fill", hexA: 0x10B981, hexB: 0x047857),
    MoodCategory(id: "act_festa", title: "Festa & Balada", query: "party dance club hits remix 2026", icon: "sparkles", hexA: 0xEC4899, hexB: 0x8B5CF6),
    MoodCategory(id: "act_estrada", title: "Estrada & Viagem", query: "road trip feel good classics hits", icon: "car.fill", hexA: 0xF59E0B, hexB: 0xD97706),
    MoodCategory(id: "act_romance", title: "Romântico", query: "romantic love songs brasil internacional", icon: "heart.fill", hexA: 0xF43F5E, hexB: 0xBE123C),
    MoodCategory(id: "act_dormir", title: "Dormir & Paz", query: "ambient sleep calm piano rain", icon: "moon.stars.fill", hexA: 0x3B82F6, hexB: 0x1E1B4B),
    MoodCategory(id: "act_cafe", title: "Café da Manhã", query: "bossa nova morning coffee acoustic jazz", icon: "cup.and.saucer.fill", hexA: 0xFB923C, hexB: 0x9A3412),
  ]

  static let decades: [MoodCategory] = [
    MoodCategory(id: "dec_80s", title: "Anos 80", query: "80s greatest hits classics", icon: "recordingtape", hexA: 0xEC4899, hexB: 0x4F46E5),
    MoodCategory(id: "dec_90s", title: "Anos 90", query: "90s greatest hits rock pop brasil", icon: "record.circle", hexA: 0xF97316, hexB: 0x7C2D12),
    MoodCategory(id: "dec_00s", title: "Anos 2000", query: "2000s hits throwbacks pop rock", icon: "compactdisc", hexA: 0x06B6D4, hexB: 0x1D4ED8),
    MoodCategory(id: "dec_10s", title: "Anos 2010", query: "2010s biggest pop hits", icon: "music.quarternote.3", hexA: 0x8B5CF6, hexB: 0xDB2777),
  ]
}

// MARK: - Paradas por País & Gêneros (estilo Apple Music / Spotify / Amazon Music)

struct ChartCountry: Identifiable, Hashable, Codable {
  var id: String { code }
  let code: String          // Apple RSS storefront (ex. "br", "us", "jp")
  let ytmCode: String       // YouTube Music FEmusic_charts code
  let name: String
  let flag: String
  let region: String
  let hexA: UInt32
  let hexB: UInt32

  static let all: [ChartCountry] = [
    ChartCountry(code: "br", ytmCode: "BR", name: "Brasil", flag: "🇧🇷", region: "América do Sul", hexA: 0x10B981, hexB: 0x047857),
    ChartCountry(code: "us", ytmCode: "US", name: "Estados Unidos", flag: "🇺🇸", region: "América do Norte", hexA: 0x3B82F6, hexB: 0x1D4ED8),
    ChartCountry(code: "gb", ytmCode: "GB", name: "Reino Unido", flag: "🇬🇧", region: "Europa", hexA: 0x6366F1, hexB: 0xBE123C),
    ChartCountry(code: "pt", ytmCode: "PT", name: "Portugal", flag: "🇵🇹", region: "Europa", hexA: 0xEF4444, hexB: 0x059669),
    ChartCountry(code: "ar", ytmCode: "AR", name: "Argentina", flag: "🇦🇷", region: "América do Sul", hexA: 0x38BDF8, hexB: 0x0284C7),
    ChartCountry(code: "mx", ytmCode: "MX", name: "México", flag: "🇲🇽", region: "América Latina", hexA: 0x16A34A, hexB: 0xDC2626),
    ChartCountry(code: "co", ytmCode: "CO", name: "Colômbia", flag: "🇨🇴", region: "América do Sul", hexA: 0xF59E0B, hexB: 0x1D4ED8),
    ChartCountry(code: "es", ytmCode: "ES", name: "Espanha", flag: "🇪🇸", region: "Europa", hexA: 0xEA580C, hexB: 0xB91C1C),
    ChartCountry(code: "fr", ytmCode: "FR", name: "França", flag: "🇫🇷", region: "Europa", hexA: 0x2563EB, hexB: 0xE11D48),
    ChartCountry(code: "de", ytmCode: "DE", name: "Alemanha", flag: "🇩🇪", region: "Europa", hexA: 0xF59E0B, hexB: 0x374151),
    ChartCountry(code: "it", ytmCode: "IT", name: "Itália", flag: "🇮🇹", region: "Europa", hexA: 0x10B981, hexB: 0xDC2626),
    ChartCountry(code: "jp", ytmCode: "JP", name: "Japão", flag: "🇯🇵", region: "Ásia", hexA: 0xF43F5E, hexB: 0x9F1239),
    ChartCountry(code: "kr", ytmCode: "KR", name: "Coreia do Sul", flag: "🇰🇷", region: "Ásia", hexA: 0xEC4899, hexB: 0x4F46E5),
    ChartCountry(code: "ng", ytmCode: "NG", name: "Nigéria", flag: "🇳🇬", region: "África", hexA: 0x059669, hexB: 0x065F46),
    ChartCountry(code: "in", ytmCode: "IN", name: "Índia", flag: "🇮🇳", region: "Ásia", hexA: 0xF97316, hexB: 0x0F766E),
    ChartCountry(code: "ca", ytmCode: "CA", name: "Canadá", flag: "🇨🇦", region: "América do Norte", hexA: 0xEF4444, hexB: 0x991B1B),
    ChartCountry(code: "au", ytmCode: "AU", name: "Austrália", flag: "🇦🇺", region: "Oceania", hexA: 0x06B6D4, hexB: 0x1E3A8A),
    ChartCountry(code: "se", ytmCode: "SE", name: "Suécia", flag: "🇸🇪", region: "Europa", hexA: 0x0EA5E9, hexB: 0xCA8A04),
  ]
}

struct MusicGenre: Identifiable, Hashable, Codable {
  enum Group: String, Codable, Hashable, CaseIterable {
    case brasil = "Brasil"
    case internacional = "Internacional"
  }

  let id: String
  let title: String
  let subtitle: String
  let group: Group
  let appleGenreId: Int?
  let appleCountry: String
  let searchQuery: String
  let playlistQuery: String
  let icon: String
  let hexA: UInt32
  let hexB: UInt32

  static let all: [MusicGenre] = [
    // Brasil
    MusicGenre(id: "sertanejo", title: "Sertanejo", subtitle: "Modão, universitário e sucessos", group: .brasil, appleGenreId: 1122, appleCountry: "br", searchQuery: "sertanejo mais tocadas brasil 2026", playlistQuery: "top sertanejo brasil", icon: "guitars.fill", hexA: 0xFFB547, hexB: 0xD9534F),
    MusicGenre(id: "funk_br", title: "Funk & Trap BR", subtitle: "Bailes, mandelão e trap nacional", group: .brasil, appleGenreId: 18, appleCountry: "br", searchQuery: "funk brasil trap nacional hits 2026", playlistQuery: "funk brasil hits", icon: "speaker.wave.3.fill", hexA: 0xEC4899, hexB: 0x7C3AED),
    MusicGenre(id: "pagode", title: "Pagode & Samba", subtitle: "Rodas de samba e pagode 90/atual", group: .brasil, appleGenreId: nil, appleCountry: "br", searchQuery: "pagode samba mais tocadas brasil", playlistQuery: "pagode samba brasil", icon: "music.quarternote.3", hexA: 0xF59E0B, hexB: 0xB45309),
    MusicGenre(id: "mpb", title: "MPB & Bossa", subtitle: "Clássicos e nova MPB brasileira", group: .brasil, appleGenreId: nil, appleCountry: "br", searchQuery: "mpb bossa nova melhores musicas", playlistQuery: "mpb classicos brasil", icon: "sun.max.fill", hexA: 0x10B981, hexB: 0x059669),
    MusicGenre(id: "forro", title: "Forró & Piseiro", subtitle: "Nordeste, piseiro e vaquejada", group: .brasil, appleGenreId: nil, appleCountry: "br", searchQuery: "forro piseiro sucessos 2026", playlistQuery: "forro piseiro brasil", icon: "flame.fill", hexA: 0xFB7185, hexB: 0xE11D48),
    MusicGenre(id: "gospel", title: "Gospel & Louvor", subtitle: "Adoração e louvores em alta", group: .brasil, appleGenreId: 22, appleCountry: "br", searchQuery: "gospel louvor adoracao mais tocadas", playlistQuery: "gospel brasil louvor", icon: "sparkles", hexA: 0x38BDF8, hexB: 0x4F46E5),

    // Internacional
    MusicGenre(id: "pop", title: "Pop", subtitle: "Hits globais das paradas", group: .internacional, appleGenreId: 14, appleCountry: "us", searchQuery: "top pop hits 2026", playlistQuery: "pop hits today", icon: "star.fill", hexA: 0xFF6B8B, hexB: 0x7C3AED),
    MusicGenre(id: "rock", title: "Rock", subtitle: "Clássicos, alternativo e hard rock", group: .internacional, appleGenreId: 21, appleCountry: "br", searchQuery: "rock greatest hits classics", playlistQuery: "rock classics hits", icon: "bolt.fill", hexA: 0xF97316, hexB: 0x991B1B),
    MusicGenre(id: "hiphop", title: "Hip-Hop & Rap", subtitle: "Rap mundial, trap e R&B", group: .internacional, appleGenreId: 18, appleCountry: "us", searchQuery: "hip hop rap hits 2026", playlistQuery: "hip hop rap hits", icon: "headphones", hexA: 0x6366F1, hexB: 0x1E1B4B),
    MusicGenre(id: "eletronica", title: "Eletrônica & Dance", subtitle: "House, techno, EDM e festival", group: .internacional, appleGenreId: 17, appleCountry: "gb", searchQuery: "electronic dance house hits 2026", playlistQuery: "electronic dance hits", icon: "waveform", hexA: 0x06B6D4, hexB: 0x1D4ED8),
    MusicGenre(id: "rnb", title: "R&B & Soul", subtitle: "Groove, neo-soul e vocais", group: .internacional, appleGenreId: 15, appleCountry: "us", searchQuery: "rnb soul hits classics", playlistQuery: "r&b soul hits", icon: "heart.circle.fill", hexA: 0xA855F7, hexB: 0x6B21A8),
    MusicGenre(id: "latina", title: "Latina & Reggaeton", subtitle: "Reggaeton, salsa e pop latino", group: .internacional, appleGenreId: 12, appleCountry: "us", searchQuery: "latin reggaeton hits 2026", playlistQuery: "reggaeton latin hits", icon: "sun.haze.fill", hexA: 0xF59E0B, hexB: 0xDC2626),
    MusicGenre(id: "kpop", title: "K-Pop", subtitle: "Grupos e solos da Coreia", group: .internacional, appleGenreId: 51, appleCountry: "kr", searchQuery: "kpop hits 2026", playlistQuery: "k-pop hits", icon: "wand.and.stars", hexA: 0xEC4899, hexB: 0x0EA5E9),
    MusicGenre(id: "metal", title: "Metal", subtitle: "Heavy, thrash e metal moderno", group: .internacional, appleGenreId: 1153, appleCountry: "us", searchQuery: "heavy metal rock hits", playlistQuery: "heavy metal classics", icon: "flame", hexA: 0x52525B, hexB: 0x18181B),
    MusicGenre(id: "indie", title: "Indie & Alternativo", subtitle: "Cenas independentes e alt-pop", group: .internacional, appleGenreId: 20, appleCountry: "us", searchQuery: "indie alternative hits", playlistQuery: "indie alternative", icon: "leaf.fill", hexA: 0x14B8A6, hexB: 0x0F766E),
    MusicGenre(id: "jazz", title: "Jazz", subtitle: "Standards, sax e jazz contemporâneo", group: .internacional, appleGenreId: 11, appleCountry: "us", searchQuery: "jazz classics saxophone", playlistQuery: "jazz classics", icon: "music.note", hexA: 0xD97706, hexB: 0x451A03),
    MusicGenre(id: "classica", title: "Clássica", subtitle: "Sinfonias, piano e concertos", group: .internacional, appleGenreId: 5, appleCountry: "us", searchQuery: "classical piano orchestra masterpiece", playlistQuery: "classical essentials", icon: "pianokeys", hexA: 0x64748B, hexB: 0x1E293B),
    MusicGenre(id: "reggae", title: "Reggae", subtitle: "Roots, dub e vibrações positivas", group: .internacional, appleGenreId: 24, appleCountry: "br", searchQuery: "reggae roots classics brasil", playlistQuery: "reggae hits", icon: "tropicalstorm", hexA: 0x22C55E, hexB: 0xCA8A04),
    MusicGenre(id: "country", title: "Country", subtitle: "Nashville e country contemporâneo", group: .internacional, appleGenreId: 6, appleCountry: "us", searchQuery: "country hits 2026", playlistQuery: "country hits", icon: "music.mic", hexA: 0xB45309, hexB: 0x78350F),
    MusicGenre(id: "soundtrack", title: "Trilhas & Games", subtitle: "Cinema, séries e games", group: .internacional, appleGenreId: 16, appleCountry: "us", searchQuery: "movie soundtrack epic score", playlistQuery: "soundtrack movie hits", icon: "film.fill", hexA: 0x4F46E5, hexB: 0x0F172A),
  ]
}

struct RemotePlaylist: Identifiable, Hashable, Codable {
  var id: String { "dzpl_\(deezerId)" }
  let deezerId: Int
  let title: String
  let subtitle: String
  let artworkURL: String
  let trackCount: Int
  let creator: String
}

struct LyricSearchHit: Identifiable, Hashable {
  var id: String { track.id }
  let track: Track
  let snippet: String
}

struct PersonalizedMix: Identifiable, Hashable {
  let id: String
  let title: String
  let subtitle: String
  let tag: String
  let icon: String
  let hexA: UInt32
  let hexB: UInt32
  let tracks: [Track]
}
