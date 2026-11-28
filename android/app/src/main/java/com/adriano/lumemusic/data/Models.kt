package com.adriano.lumemusic.data

import kotlinx.serialization.Serializable
import java.util.UUID

/** Modelos de domínio do Lume Music (espelham App/Models.swift). */
@Serializable
data class Track(
    val id: String,
    val videoId: String? = null,
    val title: String,
    val artist: String,
    val album: String = "",
    val duration: Double = 0.0,
    val artworkURL: String = "",
    val animatedArtworkURL: String? = null,
    val sourceService: String = "Lume",
    val isExplicit: Boolean = false,
) {
    val searchQuery: String get() = if (artist.isEmpty()) title else "$title $artist"

    val formattedDuration: String
        get() {
            if (duration <= 0) return ""
            val s = Math.round(duration).toInt()
            return "%d:%02d".format(s / 60, s % 60)
        }

    companion object {
        /** FNV-1a de 64 bits, idêntico ao iOS: "tr_%016llx". */
        fun stableId(title: String, artist: String): String {
            val raw = "${artist.lowercase().trim()}::${title.lowercase().trim()}"
            var h = 14695981039346656037UL
            for (b in raw.toByteArray(Charsets.UTF_8)) {
                h = h xor b.toUByte().toULong()
                h *= 1099511628211UL
            }
            return "tr_" + h.toString(16).padStart(16, '0')
        }
    }
}

/** Equivalente ao init de Track do Swift (limpa espaços, id estável, duração >= 0). */
fun newTrack(
    id: String? = null,
    videoId: String? = null,
    title: String,
    artist: String,
    album: String = "",
    duration: Double = 0.0,
    artworkURL: String = "",
    animatedArtworkURL: String? = null,
    sourceService: String = "Lume",
    isExplicit: Boolean = false,
): Track = Track(
    id = id ?: videoId ?: Track.stableId(title, artist),
    videoId = videoId,
    title = title.trim(),
    artist = artist.trim(),
    album = album.trim(),
    duration = maxOf(0.0, duration),
    artworkURL = artworkURL,
    animatedArtworkURL = animatedArtworkURL,
    sourceService = sourceService,
    isExplicit = isExplicit,
)

@Serializable
data class AlbumShowcase(
    val id: String,
    val title: String,
    val artist: String,
    val artworkURL: String = "",
    val animatedArtworkURL: String? = null,
    val year: String = "",
    val genre: String = "",
    val tracks: List<Track> = emptyList(),
    val releaseDate: String? = null,
    val kind: String? = null,
    val deezerId: Long? = null,
    val itunesId: Long? = null,
)

@Serializable
data class MusicPlaylist(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val subtitle: String = "",
    val artworkURL: String = "",
    val trackIds: List<String> = emptyList(),
    val sourceBadge: String = "Lume",
    val createdAt: Long = System.currentTimeMillis(),
    /** Última alteração (ms). 0 = playlist antiga, vale [createdAt]. Usado na mesclagem do backup da biblioteca. */
    val updatedAt: Long = 0L,
) {
    val lastChange: Long get() = maxOf(updatedAt, createdAt)
}

/** Playlist apagada (lápide) para o backup não ressuscitá-la em outro aparelho. */
@Serializable
data class DeletedPlaylist(val id: String, val at: Long)

@Serializable
data class LyricLine(
    val id: Int,
    val time: Double,
    val text: String,
    val translated: String? = null,
)

@Serializable
data class LyricsBundle(
    val trackKey: String,
    val synced: Boolean,
    val lines: List<LyricLine>,
    val source: String,
    val translatedToPT: Boolean = false,
)

@Serializable
data class ArtistInfo(
    val id: String,
    val name: String,
    val pictureURL: String = "",
    val deezerId: Long? = null,
    val fans: Long? = null,
    val rank: Int? = null,
)

@Serializable
data class ArtistDetail(
    val artist: ArtistInfo,
    val topTracks: List<Track>,
    val albums: List<AlbumShowcase>,
    val related: List<ArtistInfo>,
)

@Serializable
data class DiscoverFeed(
    val updatedAt: Long,
    val newReleases: List<AlbumShowcase>,
    val brazilReleases: List<AlbumShowcase>,
    val topBrazil: List<Track>,
    val topGlobal: List<Track>,
    val topArtists: List<ArtistInfo>,
    val trending: List<Track>,
    val topAlbumsBrazil: List<AlbumShowcase>? = null,
    val topAlbumsGlobal: List<AlbumShowcase>? = null,
    val globalTopArtists: List<ArtistInfo>? = null,
    /** Playlist "Top Brasil" (Deezer Charts): música realmente brasileira, ao contrário da parada da Apple que traz hits gringos. */
    val brazilianHits: List<Track>? = null,
)

@Serializable
data class HomeFeed(
    val topBrazil: List<Track>,
    val newAlbums: List<AlbumShowcase>,
    val globalHits: List<Track>,
)

@Serializable
data class RemotePlaylist(
    val deezerId: Long,
    val title: String,
    val subtitle: String,
    val artworkURL: String,
    val trackCount: Int,
    val creator: String,
) {
    val id: String get() = "dzpl_$deezerId"
}

data class LyricSearchHit(val track: Track, val snippet: String) {
    val id: String get() = track.id
}

data class PersonalizedMix(
    val id: String,
    val title: String,
    val subtitle: String,
    val tag: String,
    val icon: String,
    val hexA: Long,
    val hexB: Long,
    val tracks: List<Track>,
)

// ---- Enums persistidos (raw values NUNCA mudam; só adicionar casos) ----

enum class VisualizerStyle(val raw: String, val title: String, val icon: String) {
    ARES("Ondas Ares", "Ondas 3D", "mountain.2.fill"),
    AURORA("Espectro", "Espectro", "chart.bar.fill"),
    ORB("Orbe", "Orbe", "circle.hexagongrid.fill"),
    SOLAR_RING("Anel Solar", "Anel Solar", "sun.max.circle.fill"),
    OSCILLOSCOPE("Osciloscópio", "Osciloscópio", "waveform.path.ecg"),
    NEBULA("Nebulosa", "Nebulosa", "sparkles"),
    OFF("Desligado", "Desligado", "eye.slash");

    companion object {
        val activeStyles = listOf(ARES, AURORA, ORB, SOLAR_RING, OSCILLOSCOPE, NEBULA)
        fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: ARES
    }
}

enum class TurntableFinish(val raw: String, val isDarkChassis: Boolean) {
    OBSIDIAN("Obsidian Pro", true),
    SILVER("Prata Estúdio", false),
    WALNUT("Nogueira Vintage", true),
    GOLD("Titânio Dourado", false);

    companion object { fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: OBSIDIAN }
}

enum class VinylEdition(val raw: String) {
    CLASSIC_BLACK("Preto 180g"),
    PRISM_CRYSTAL("Cristal Prisma"),
    LIMITED_GOLD("Ouro Limitado"),
    WHITE_MARBLE("Mármore Branco");

    companion object { fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: CLASSIC_BLACK }
}

enum class CassetteStyle(val raw: String) {
    SMOKED_STUDIO("Fumê Estúdio"),
    CRYSTAL_CLEAR("Cristal Transparente"),
    METALLIC_CHROME("Cromo Metálico"),
    VINTAGE_CREAM("Vintage Creme");

    companion object { fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: SMOKED_STUDIO }
}

/** Arte mostrada na tela de bloqueio / notificação de mídia. Raw values iguais aos do iOS. */
enum class LockArtStyle(val raw: String, val title: String) {
    AUTOMATIC("auto", "Automático"),
    COVER("capa", "Capa"),
    VINYL("vinil", "Vinil"),
    CASSETTE("k7", "Fita K7");

    companion object { fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: AUTOMATIC }
}

enum class RepeatMode(val raw: String) {
    OFF("off"), ALL("all"), ONE("one");

    val next: RepeatMode get() = when (this) { OFF -> ALL; ALL -> ONE; ONE -> OFF }

    companion object { fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: OFF }
}

enum class SoundProfile(val raw: String, val subtitle: String, val defaultGains: List<Float>) {
    NATURAL("Natural", "Equilíbrio fiel ao estúdio", listOf(0f, 0f, 0f, 0f, 0f)),
    BASS("Grave Intenso", "Sub-graves encorpados e pulsantes", listOf(6.5f, 4.0f, -0.5f, 1.0f, 2.5f)),
    VOCAL("Voz & Karaokê", "Voz em destaque para acompanhar letras", listOf(-2.5f, -0.5f, 4.0f, 4.5f, 1.5f)),
    CINEMA("Cinema 3D", "Palco amplo e espacial", listOf(4.5f, 1.5f, -1.0f, 3.0f, 4.5f)),
    NIGHT("Modo Noite", "Volume suave sem picos bruscos", listOf(-3.0f, 1.0f, 2.0f, 1.0f, -2.5f)),
    CUSTOM("Personalizado", "Ajuste fino nas 5 bandas do equalizador", listOf(0f, 0f, 0f, 0f, 0f));

    companion object { fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: NATURAL }
}

enum class SleepTimerOption(val minutes: Int, val label: String) {
    OFF(0, "Desligado"),
    M15(15, "15 minutos"),
    M30(30, "30 minutos"),
    M45(45, "45 minutos"),
    M60(60, "1 hora"),
    END_OF_TRACK(-1, "Fim desta faixa"),
}

/** Os "palcos" do Tocando agora. Capa e Letra estão completos; os demais são placeholders (fase 2). */
enum class PlayerSurfaceTab(val raw: String, val icon: String) {
    ARTWORK("Capa", "square.fill"),
    VINYL("Vinil", "record.circle"),
    CASSETTE("K7", "recordingtape"),
    WAVES("Ondas", "waveform"),
    LYRICS("Letra", "quote.bubble");

    companion object { fun fromRaw(raw: String?) = entries.firstOrNull { it.raw == raw } ?: ARTWORK }
}

enum class AppTab(val title: String, val icon: String) {
    HOME("Início", "house.fill"),
    EXPLORE("Explorar", "safari.fill"),
    LIBRARY("Biblioteca", "square.stack.fill"),
    SEARCH("Buscar", "magnifyingglass");

    companion object { val bar = listOf(HOME, EXPLORE, LIBRARY) }
}

data class MoodCategory(
    val id: String,
    val title: String,
    val query: String,
    val icon: String,
    val hexA: Long,
    val hexB: Long,
) {
    companion object {
        val presets = listOf(
            MoodCategory("sertanejo", "Sertanejo", "top sertanejo brasil sucessos 2026", "guitars.fill", 0xFFB547, 0xD9534F),
            MoodCategory("pop", "Pop Hits", "top pop hits 2026", "star.fill", 0xFF6B8B, 0x7C3AED),
            MoodCategory("rock", "Rock", "rock classics greatest hits", "bolt.fill", 0xF97316, 0x991B1B),
            MoodCategory("hiphop", "Hip-Hop & Trap", "hip hop trap hits 2026", "headphones", 0x6366F1, 0xEC4899),
            MoodCategory("mpb", "MPB & Brasil", "mpb pagode melhores musicas brasil", "sun.max.fill", 0x10B981, 0x059669),
            MoodCategory("eletronica", "Eletrônica", "electronic dance house hits 2026", "waveform", 0x06B6D4, 0x3B82F6),
            MoodCategory("lofi", "Foco & Lo-Fi", "lofi chill beats study focus", "moon.stars.fill", 0x8B5CF6, 0x1E3A8A),
            MoodCategory("treino", "Treino", "workout gym motivation music hits", "flame.fill", 0xEF4444, 0xF59E0B),
        )
        val activities = listOf(
            MoodCategory("act_treino", "Treino & Academia", "workout gym motivation music hits 2026", "flame.fill", 0xEF4444, 0xF97316),
            MoodCategory("act_foco", "Foco & Estudo", "lofi chill beats study focus instrumental", "brain.head.profile", 0x6366F1, 0x1E3A8A),
            MoodCategory("act_relax", "Relaxar & Chill", "acoustic chill vibes relax music", "leaf.fill", 0x10B981, 0x047857),
            MoodCategory("act_festa", "Festa & Balada", "party dance club hits remix 2026", "sparkles", 0xEC4899, 0x8B5CF6),
            MoodCategory("act_estrada", "Estrada & Viagem", "road trip feel good classics hits", "car.fill", 0xF59E0B, 0xD97706),
            MoodCategory("act_romance", "Romântico", "romantic love songs brasil internacional", "heart.fill", 0xF43F5E, 0xBE123C),
            MoodCategory("act_dormir", "Dormir & Paz", "ambient sleep calm piano rain", "moon.stars.fill", 0x3B82F6, 0x1E1B4B),
            MoodCategory("act_cafe", "Café da Manhã", "bossa nova morning coffee acoustic jazz", "cup.and.saucer.fill", 0xFB923C, 0x9A3412),
        )
        val decades = listOf(
            MoodCategory("dec_80s", "Anos 80", "80s greatest hits classics", "recordingtape", 0xEC4899, 0x4F46E5),
            MoodCategory("dec_90s", "Anos 90", "90s greatest hits rock pop brasil", "record.circle", 0xF97316, 0x7C2D12),
            MoodCategory("dec_00s", "Anos 2000", "2000s hits throwbacks pop rock", "compactdisc", 0x06B6D4, 0x1D4ED8),
            MoodCategory("dec_10s", "Anos 2010", "2010s biggest pop hits", "music.quarternote.3", 0x8B5CF6, 0xDB2777),
        )
    }
}

data class ChartCountry(
    val code: String,
    val ytmCode: String,
    val name: String,
    val flag: String,
    val region: String,
    val hexA: Long,
    val hexB: Long,
) {
    val id: String get() = code

    companion object {
        val all = listOf(
            ChartCountry("br", "BR", "Brasil", "🇧🇷", "América do Sul", 0x10B981, 0x047857),
            ChartCountry("us", "US", "Estados Unidos", "🇺🇸", "América do Norte", 0x3B82F6, 0x1D4ED8),
            ChartCountry("gb", "GB", "Reino Unido", "🇬🇧", "Europa", 0x6366F1, 0xBE123C),
            ChartCountry("pt", "PT", "Portugal", "🇵🇹", "Europa", 0xEF4444, 0x059669),
            ChartCountry("ar", "AR", "Argentina", "🇦🇷", "América do Sul", 0x38BDF8, 0x0284C7),
            ChartCountry("mx", "MX", "México", "🇲🇽", "América Latina", 0x16A34A, 0xDC2626),
            ChartCountry("co", "CO", "Colômbia", "🇨🇴", "América do Sul", 0xF59E0B, 0x1D4ED8),
            ChartCountry("es", "ES", "Espanha", "🇪🇸", "Europa", 0xEA580C, 0xB91C1C),
            ChartCountry("fr", "FR", "França", "🇫🇷", "Europa", 0x2563EB, 0xE11D48),
            ChartCountry("de", "DE", "Alemanha", "🇩🇪", "Europa", 0xF59E0B, 0x374151),
            ChartCountry("it", "IT", "Itália", "🇮🇹", "Europa", 0x10B981, 0xDC2626),
            ChartCountry("jp", "JP", "Japão", "🇯🇵", "Ásia", 0xF43F5E, 0x9F1239),
            ChartCountry("kr", "KR", "Coreia do Sul", "🇰🇷", "Ásia", 0xEC4899, 0x4F46E5),
            ChartCountry("ng", "NG", "Nigéria", "🇳🇬", "África", 0x059669, 0x065F46),
            ChartCountry("in", "IN", "Índia", "🇮🇳", "Ásia", 0xF97316, 0x0F766E),
            ChartCountry("ca", "CA", "Canadá", "🇨🇦", "América do Norte", 0xEF4444, 0x991B1B),
            ChartCountry("au", "AU", "Austrália", "🇦🇺", "Oceania", 0x06B6D4, 0x1E3A8A),
            ChartCountry("se", "SE", "Suécia", "🇸🇪", "Europa", 0x0EA5E9, 0xCA8A04),
        )
    }
}

data class MusicGenre(
    val id: String,
    val title: String,
    val subtitle: String,
    val group: Group,
    val appleGenreId: Int?,
    val appleCountry: String,
    val searchQuery: String,
    val playlistQuery: String,
    val icon: String,
    val hexA: Long,
    val hexB: Long,
) {
    enum class Group(val raw: String) { BRASIL("Brasil"), INTERNACIONAL("Internacional") }

    companion object {
        val all = listOf(
            // Brasil
            MusicGenre("sertanejo", "Sertanejo", "Modão, universitário e sucessos", Group.BRASIL, 1122, "br", "sertanejo mais tocadas brasil 2026", "top sertanejo brasil", "guitars.fill", 0xFFB547, 0xD9534F),
            MusicGenre("funk_br", "Funk & Trap BR", "Bailes, mandelão e trap nacional", Group.BRASIL, 18, "br", "funk brasil trap nacional hits 2026", "funk brasil hits", "speaker.wave.3.fill", 0xEC4899, 0x7C3AED),
            MusicGenre("pagode", "Pagode & Samba", "Rodas de samba e pagode 90/atual", Group.BRASIL, null, "br", "pagode samba mais tocadas brasil", "pagode samba brasil", "music.quarternote.3", 0xF59E0B, 0xB45309),
            MusicGenre("mpb", "MPB & Bossa", "Clássicos e nova MPB brasileira", Group.BRASIL, null, "br", "mpb bossa nova melhores musicas", "mpb classicos brasil", "sun.max.fill", 0x10B981, 0x059669),
            MusicGenre("forro", "Forró & Piseiro", "Nordeste, piseiro e vaquejada", Group.BRASIL, null, "br", "forro piseiro sucessos 2026", "forro piseiro brasil", "flame.fill", 0xFB7185, 0xE11D48),
            MusicGenre("gospel", "Gospel & Louvor", "Adoração e louvores em alta", Group.BRASIL, 22, "br", "gospel louvor adoracao mais tocadas", "gospel brasil louvor", "sparkles", 0x38BDF8, 0x4F46E5),
            // Internacional
            MusicGenre("pop", "Pop", "Hits globais das paradas", Group.INTERNACIONAL, 14, "us", "top pop hits 2026", "pop hits today", "star.fill", 0xFF6B8B, 0x7C3AED),
            MusicGenre("rock", "Rock", "Clássicos, alternativo e hard rock", Group.INTERNACIONAL, 21, "br", "rock greatest hits classics", "rock classics hits", "bolt.fill", 0xF97316, 0x991B1B),
            MusicGenre("hiphop", "Hip-Hop & Rap", "Rap mundial, trap e R&B", Group.INTERNACIONAL, 18, "us", "hip hop rap hits 2026", "hip hop rap hits", "headphones", 0x6366F1, 0x1E1B4B),
            MusicGenre("eletronica", "Eletrônica & Dance", "House, techno, EDM e festival", Group.INTERNACIONAL, 17, "gb", "electronic dance house hits 2026", "electronic dance hits", "waveform", 0x06B6D4, 0x1D4ED8),
            MusicGenre("rnb", "R&B & Soul", "Groove, neo-soul e vocais", Group.INTERNACIONAL, 15, "us", "rnb soul hits classics", "r&b soul hits", "heart.circle.fill", 0xA855F7, 0x6B21A8),
            MusicGenre("latina", "Latina & Reggaeton", "Reggaeton, salsa e pop latino", Group.INTERNACIONAL, 12, "us", "latin reggaeton hits 2026", "reggaeton latin hits", "sun.haze.fill", 0xF59E0B, 0xDC2626),
            MusicGenre("kpop", "K-Pop", "Grupos e solos da Coreia", Group.INTERNACIONAL, 51, "kr", "kpop hits 2026", "k-pop hits", "wand.and.stars", 0xEC4899, 0x0EA5E9),
            MusicGenre("metal", "Metal", "Heavy, thrash e metal moderno", Group.INTERNACIONAL, 1153, "us", "heavy metal rock hits", "heavy metal classics", "flame", 0x52525B, 0x18181B),
            MusicGenre("indie", "Indie & Alternativo", "Cenas independentes e alt-pop", Group.INTERNACIONAL, 20, "us", "indie alternative hits", "indie alternative", "leaf.fill", 0x14B8A6, 0x0F766E),
            MusicGenre("jazz", "Jazz", "Standards, sax e jazz contemporâneo", Group.INTERNACIONAL, 11, "us", "jazz classics saxophone", "jazz classics", "music.note", 0xD97706, 0x451A03),
            MusicGenre("classica", "Clássica", "Sinfonias, piano e concertos", Group.INTERNACIONAL, 5, "us", "classical piano orchestra masterpiece", "classical essentials", "pianokeys", 0x64748B, 0x1E293B),
            MusicGenre("reggae", "Reggae", "Roots, dub e vibrações positivas", Group.INTERNACIONAL, 24, "br", "reggae roots classics brasil", "reggae hits", "tropicalstorm", 0x22C55E, 0xCA8A04),
            MusicGenre("country", "Country", "Nashville e country contemporâneo", Group.INTERNACIONAL, 6, "us", "country hits 2026", "country hits", "music.mic", 0xB45309, 0x78350F),
            MusicGenre("soundtrack", "Trilhas & Games", "Cinema, séries e games", Group.INTERNACIONAL, 16, "us", "movie soundtrack epic score", "soundtrack movie hits", "film.fill", 0x4F46E5, 0x0F172A),
        )
    }
}
