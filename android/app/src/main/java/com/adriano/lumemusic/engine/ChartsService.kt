package com.adriano.lumemusic.engine

import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.ChartCountry
import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.data.newTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

// ---------------- Lugares (países + Global) das paradas — porta de App/ChartsService.swift ----------------

/**
 * Um "lugar" de parada: um país (loja da Apple Music + playlist oficial "Deezer Charts" do país) ou o Global.
 * Fontes (auditadas em 26/11/2026, iguais às do iOS):
 *  - País: Apple Marketing Tools RSS (`most-played`, storefront do país) · reserva: playlist "Top <país>" do Deezer Charts.
 *  - Global: playlist "Top Worldwide" do Deezer Charts (a Apple não tem parada global).
 */
data class ChartPlace(
    val id: String,
    val name: String,
    val flag: String,
    val apple: String?,
    val deezerPlaylist: Long?,
    val ytm: String,
    val region: String,
    val hexA: Long,
    val hexB: Long,
) {
    val isGlobal: Boolean get() = id == "world"
    val title: String get() = if (isGlobal) "Top 10 Global" else "Top 10 $name"

    /** Nome curto para o chip. */
    val short: String get() = when (id) { "us" -> "EUA"; "kr" -> "Coreia"; else -> name }

    /** Versão compatível com a rota `Country(...)`. */
    val chartCountry: ChartCountry get() = ChartCountry(id, ytm, name, flag, region, hexA, hexB)

    companion object {
        val world = ChartPlace("world", "Global", "🌎", null, 3155776842, "ZZ", "Mundo", 0x06B6D4, 0x3B82F6)

        /** Ordem do seletor: Brasil, Global, depois os mais pedidos (20 chips). */
        val all: List<ChartPlace> = listOf(
            ChartPlace("br", "Brasil", "🇧🇷", "br", 1111141961, "BR", "América do Sul", 0x10B981, 0x047857),
            world,
            ChartPlace("us", "Estados Unidos", "🇺🇸", "us", 1313621735, "US", "América do Norte", 0x3B82F6, 0x1D4ED8),
            ChartPlace("gb", "Reino Unido", "🇬🇧", "gb", 1111142221, "GB", "Europa", 0x6366F1, 0xBE123C),
            ChartPlace("mx", "México", "🇲🇽", "mx", 1111142361, "MX", "América Latina", 0x16A34A, 0xDC2626),
            ChartPlace("pt", "Portugal", "🇵🇹", "pt", 1362519755, "PT", "Europa", 0xEF4444, 0x059669),
            ChartPlace("ar", "Argentina", "🇦🇷", "ar", 1279119721, "AR", "América do Sul", 0x38BDF8, 0x0284C7),
            ChartPlace("es", "Espanha", "🇪🇸", "es", 1116190041, "ES", "Europa", 0xEA580C, 0xB91C1C),
            ChartPlace("fr", "França", "🇫🇷", "fr", 1109890291, "FR", "Europa", 0x2563EB, 0xE11D48),
            ChartPlace("de", "Alemanha", "🇩🇪", "de", 1111143121, "DE", "Europa", 0xF59E0B, 0x374151),
            ChartPlace("it", "Itália", "🇮🇹", "it", 1116187241, "IT", "Europa", 0x10B981, 0xDC2626),
            ChartPlace("jp", "Japão", "🇯🇵", "jp", null, "JP", "Ásia", 0xF43F5E, 0x9F1239),
            ChartPlace("kr", "Coreia do Sul", "🇰🇷", "kr", 1362510315, "KR", "Ásia", 0xEC4899, 0x4F46E5),
            ChartPlace("ca", "Canadá", "🇨🇦", "ca", 1652248171, "CA", "América do Norte", 0xEF4444, 0x991B1B),
            ChartPlace("co", "Colômbia", "🇨🇴", "co", 1116188451, "CO", "América do Sul", 0xF59E0B, 0x1D4ED8),
            ChartPlace("cl", "Chile", "🇨🇱", "cl", 1279119121, "CL", "América do Sul", 0xDC2626, 0x1E40AF),
            ChartPlace("ng", "Nigéria", "🇳🇬", "ng", 1362516565, "NG", "África", 0x059669, 0x065F46),
            ChartPlace("in", "Índia", "🇮🇳", "in", null, "IN", "Ásia", 0xF97316, 0x0F766E),
            ChartPlace("au", "Austrália", "🇦🇺", "au", 1313616925, "AU", "Oceania", 0x06B6D4, 0x1E3A8A),
            ChartPlace("se", "Suécia", "🇸🇪", "se", 1313620305, "SE", "Europa", 0x0EA5E9, 0xCA8A04),
        )

        fun place(id: String?): ChartPlace? = if (id == null) null else all.firstOrNull { it.id == id }

        /** País do usuário pelo Locale (cai no Brasil se não houver parada para a região). */
        val userPlace: ChartPlace get() = place(Locale.getDefault().country.lowercase()) ?: all[0]
    }
}

/** Lista de parada (cacheável em disco). */
@Serializable
data class ChartList(
    val placeId: String,
    val songs: List<Track>,
    val albums: List<AlbumShowcase>,
    val source: String,            // "Apple Music" | "Deezer Charts"
    val updatedAt: Long,
) {
    val isFresh: Boolean get() = System.currentTimeMillis() - updatedAt < ChartsService.FRESH_FOR_MS

    /** "Apple Music · atualizado há 5 min" — para o usuário saber de onde vem cada ranking. */
    val caption: String get() = "$source · atualizado ${relativeAgo(updatedAt)}"

    companion object {
        fun relativeAgo(at: Long, now: Long = System.currentTimeMillis()): String {
            val secs = Math.abs(now - at) / 1000
            return when {
                secs < 60 -> "agora"
                secs < 3600 -> "há ${secs / 60} min"
                secs < 86400 -> "há ${secs / 3600} h"
                else -> "há ${secs / 86400} d"
            }
        }
    }
}

// ---------------- Parsers compartilhados ----------------

object ChartParsers {
    private val reApple = Regex("""\d{2,4}x\d{2,4}(bb|cc)""")

    fun upscaleApple(url: String, size: Int = 600): String = url.replace(reApple, "${size}x${size}bb")

    fun appleSongs(results: List<JsonObject>, label: String): List<Track> = results.mapNotNull { r ->
        val title = r["name"].str() ?: return@mapNotNull null
        newTrack(
            title = title, artist = r["artistName"].str() ?: "",
            artworkURL = upscaleApple(r["artworkUrl100"].str() ?: ""), sourceService = label,
            isExplicit = (r["contentAdvisoryRating"].str() ?: "").lowercase().startsWith("explic"),
        )
    }

    fun appleAlbums(results: List<JsonObject>, size: Int = 800): List<AlbumShowcase> = results.mapNotNull { r ->
        val idStr = r["id"].strLoose() ?: return@mapNotNull null
        var title = r["name"].str() ?: return@mapNotNull null
        var kind = "Álbum"
        for ((suffix, k) in listOf(" - Single" to "Single", " - EP" to "EP")) {
            if (title.endsWith(suffix)) { title = title.dropLast(suffix.length); kind = k }
        }
        val date = r["releaseDate"].str()
        val genre = r["genres"].objs().mapNotNull { it["name"].str() }.firstOrNull { it != "Música" && it != "Music" } ?: ""
        AlbumShowcase(
            id = "alb_$idStr", title = title, artist = r["artistName"].str() ?: "",
            artworkURL = upscaleApple(r["artworkUrl100"].str() ?: "", size), year = DiscText.year(date), genre = genre,
            releaseDate = date, kind = kind, itunesId = idStr.toLongOrNull(),
        )
    }

    data class DeezerPlaylistData(
        val tracks: List<Track> = emptyList(),
        val artists: List<ArtistInfo> = emptyList(),   // ranqueados por presença/posição na parada
        val albums: List<AlbumShowcase> = emptyList(), // álbuns únicos das faixas, na ordem da parada
    )

    /** Faixas + artistas (com foto) + álbuns (com id do Deezer) de uma playlist do Deezer, sem chamadas extras. */
    fun deezerPlaylist(data: List<JsonObject>, label: String = "Deezer"): DeezerPlaylistData {
        val tracks = mutableListOf<Track>()
        val albums = mutableListOf<AlbumShowcase>()
        class Score(val info: ArtistInfo, var score: Int, val first: Int)
        val scores = LinkedHashMap<Long, Score>()
        val seenAlbums = HashSet<Long>()
        val n = data.size
        for ((i, d) in data.withIndex()) {
            val title = d["title"].str()?.takeIf { it.isNotEmpty() } ?: continue
            val art = d["artist"]
            val album = d["album"]
            val artistName = art["name"].str() ?: ""
            var cover = album["cover_big"].str() ?: album["cover_xl"].str() ?: ""
            if (cover.contains("/cover//")) cover = ""
            tracks.add(newTrack(
                title = title, artist = artistName, album = album["title"].str() ?: "",
                duration = (d["duration"].int() ?: 0).toDouble(), artworkURL = cover, sourceService = label,
                isExplicit = d["explicit_lyrics"].bool() ?: false,
            ))
            val aid = art["id"].lng()
            if (aid != null && artistName.isNotEmpty()) {
                var pic = art["picture_xl"].str() ?: art["picture_big"].str() ?: ""
                if (pic.contains("/images/artist//")) pic = ""
                val pts = maxOf(1, n - i)
                val cur = scores[aid]
                if (cur != null) cur.score += pts
                else scores[aid] = Score(ArtistInfo("dz_$aid", artistName, pic, aid, null, null), pts, i)
            }
            val alid = album["id"].lng()
            val at = album["title"].str()
            if (alid != null && cover.isNotEmpty() && seenAlbums.add(alid) && at != null) {
                albums.add(AlbumShowcase(
                    id = "dzalb_$alid", title = at, artist = artistName, artworkURL = album["cover_xl"].str() ?: cover,
                    kind = "Álbum", deezerId = alid,
                ))
            }
        }
        val artists = scores.values
            .sortedWith(compareByDescending<Score> { it.score }.thenBy { it.first })
            .mapIndexed { idx, v -> v.info.copy(rank = idx + 1) }
        return DeezerPlaylistData(tracks, artists, albums)
    }

    suspend fun deezerPlaylistTracks(id: Long, limit: Int = 50, timeout: Long = 5): DeezerPlaylistData? {
        val obj = DiscNet.json("https://api.deezer.com/playlist/$id/tracks?limit=$limit", timeout, retries = 1) ?: return null
        val data = obj["data"].objs()
        if (data.isEmpty()) return null
        return deezerPlaylist(data)
    }

    suspend fun appleChart(cc: String, kind: String, limit: Int): List<JsonObject> {
        val obj = DiscNet.json("https://rss.marketingtools.apple.com/api/v2/$cc/music/most-played/$limit/$kind.json", 5, retries = 1)
        return obj["feed"]["results"].objs()
    }
}

// ---------------- Fontes por gênero (auditadas) ----------------

/**
 * O app antigo usava o id Apple 1122 ("Brasileira", pai de todos) para Sertanejo e Hip-Hop para o Funk BR,
 * o que misturava MPB/rock nacional no "Sertanejo" e rap no "Funk". Estes são os ids reais dos subgêneros.
 */
object GenreSources {
    data class Source(val country: String, val id: Int)

    fun sources(g: MusicGenre): List<Source> = when (g.id) {
        "sertanejo" -> listOf(Source("br", 1228))
        "funk_br" -> listOf(Source("br", 1229), Source("br", 18))      // Baile Funk + Hip-Hop/Rap nacional (trap)
        "pagode" -> listOf(Source("br", 1226), Source("br", 1227))     // Pagode + Samba
        "mpb" -> listOf(Source("br", 1225), Source("br", 1221))        // MPB + Bossa Nova
        "forro" -> listOf(Source("br", 1223))
        "kpop" -> listOf(Source("us", 51))                             // a loja kr não publica o gênero 51
        else -> g.appleGenreId?.let { listOf(Source(g.appleCountry, it)) } ?: emptyList()
    }

    suspend fun songs(g: MusicGenre, limit: Int = 30): List<Track> = coroutineScope {
        val lists = sources(g).map { s -> async { fetchSongs(s.country, s.id, limit, g.title) } }.awaitAll()
        interleave(lists, limit) { it.id }
    }

    suspend fun albums(g: MusicGenre, limit: Int = 16): List<AlbumShowcase> = coroutineScope {
        val lists = sources(g).map { s -> async { fetchAlbums(s.country, s.id, limit, g.title) } }.awaitAll()
        interleave(lists, limit) { it.id }
    }

    /** Intercala as listas (1º de cada, 2º de cada…) sem repetir ids. */
    fun <T> interleave(lists: List<List<T>>, limit: Int, id: (T) -> String): List<T> {
        val out = mutableListOf<T>()
        val seen = HashSet<String>()
        var idx = 0
        while (out.size < limit) {
            var added = false
            for (l in lists) {
                if (idx < l.size && seen.add(id(l[idx]))) { out.add(l[idx]); added = true }
                if (out.size >= limit) break
            }
            if (!added && lists.all { idx >= it.size }) break
            idx++
        }
        return out
    }

    private fun entries(obj: JsonElement?): List<JsonObject> {
        val e = obj["feed"]["entry"]
        return if (e is JsonObject) listOf(e) else e.objs()
    }

    private suspend fun fetchSongs(country: String, genreId: Int, limit: Int, label: String): List<Track> {
        val obj = DiscNet.json("https://itunes.apple.com/$country/rss/topsongs/limit=$limit/genre=$genreId/json", 6, retries = 1)
        return entries(obj).mapNotNull { e ->
            val title = e["im:name"]["label"].str() ?: return@mapNotNull null
            val artist = e["im:artist"]["label"].str() ?: return@mapNotNull null
            val art = ChartParsers.upscaleApple(e["im:image"].objs().lastOrNull()?.get("label").str() ?: "", 600)
            val album = e["im:collection"]["im:name"]["label"].str() ?: ""
            newTrack(title = title, artist = artist, album = album, artworkURL = art, sourceService = label)
        }
    }

    private suspend fun fetchAlbums(country: String, genreId: Int, limit: Int, genreTitle: String): List<AlbumShowcase> {
        val obj = DiscNet.json("https://itunes.apple.com/$country/rss/topalbums/limit=$limit/genre=$genreId/json", 6, retries = 1)
        return entries(obj).mapNotNull { e ->
            val title = e["im:name"]["label"].str() ?: return@mapNotNull null
            val artist = e["im:artist"]["label"].str() ?: return@mapNotNull null
            val idStr = e["id"]["attributes"]["im:id"].str() ?: Track.stableId(title, artist)
            val art = ChartParsers.upscaleApple(e["im:image"].objs().lastOrNull()?.get("label").str() ?: "", 800)
            val release = e["im:releaseDate"]["label"].str()
            AlbumShowcase(
                id = "alb_$idStr", title = title, artist = artist, artworkURL = art, year = DiscText.year(release),
                genre = genreTitle, releaseDate = release?.take(10), kind = "Álbum", itunesId = idStr.toLongOrNull(),
            )
        }
    }
}

// ---------------- Serviço (cache em disco + stale-while-revalidate) ----------------

/**
 * Paradas por país/global. [cached] devolve na hora (memória/disco, qualquer idade); [load] atualiza em segundo plano
 * com requisições coalescidas (várias telas pedindo o mesmo país = 1 só chamada de rede).
 */
object ChartsService {
    const val FRESH_FOR_MS = 20 * 60_000L
    private const val GENRE_FRESH_MS = 3 * 3600_000L

    private val memory = ConcurrentHashMap<String, ChartList>()
    private val inflight = HashMap<String, Deferred<ChartList?>>()
    private val lock = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val genreMemory = ConcurrentHashMap<String, Pair<List<Track>, Long>>()

    private fun diskFile(id: String) = DiscNet.caches("lume_chart_v2_$id.json")
    private fun genreFile(id: String) = DiscNet.caches("lume_genre_songs_v2_$id.json")

    // ---- Países / Global ----

    /** Último pacote salvo (memória/disco), de qualquer idade. */
    suspend fun cached(place: ChartPlace): ChartList? {
        memory[place.id]?.let { return it }
        return withContext(Dispatchers.IO) {
            try {
                val f = diskFile(place.id)
                if (!f.exists()) null
                else LumeJson.decodeFromString(ChartList.serializer(), f.readText()).takeIf { it.songs.isNotEmpty() }
                    ?.also { memory[place.id] = it }
            } catch (_: Exception) { null }
        }
    }

    /** Devolve a lista fresca (do cache se ainda válida) ou busca na rede. Em caso de falha, devolve o cache velho. */
    suspend fun load(place: ChartPlace, force: Boolean = false): ChartList? {
        if (!force) cached(place)?.let { if (it.isFresh) return it }
        val task: Deferred<ChartList?> = lock.withLock {
            inflight[place.id] ?: scope.async {
                val result = fetch(place)
                lock.withLock { inflight.remove(place.id) }
                if (result != null) {
                    memory[place.id] = result
                    try { diskFile(place.id).writeText(LumeJson.encodeToString(ChartList.serializer(), result)) } catch (_: Exception) {}
                }
                result
            }.also { inflight[place.id] = it }
        }
        return task.await() ?: cached(place)
    }

    /** Pré-carrega vários lugares em paralelo (no máximo 3 por vez) sem bloquear ninguém. */
    suspend fun prefetch(places: List<ChartPlace>) {
        for (slice in places.chunked(3)) coroutineScope { slice.map { p -> async { load(p) } }.awaitAll() }
    }

    private suspend fun fetch(p: ChartPlace): ChartList? = coroutineScope {
        // Rede em paralelo: Apple (músicas + álbuns) e a playlist oficial do Deezer, usada como reserva.
        val dzT = async { p.deezerPlaylist?.let { ChartParsers.deezerPlaylistTracks(it, 50) } }
        var appleSongs = emptyList<Track>()
        var appleAlbums = emptyList<AlbumShowcase>()
        if (p.apple != null) {
            val sT = async { ChartParsers.appleChart(p.apple, "songs", 50) }
            val aT = async { ChartParsers.appleChart(p.apple, "albums", 25) }
            appleSongs = ChartParsers.appleSongs(sT.await(), "Apple ${p.apple.uppercase()}")
            appleAlbums = ChartParsers.appleAlbums(aT.await())
        }
        val dz = dzT.await()
        val now = System.currentTimeMillis()
        if (p.isGlobal) {
            if (dz == null || dz.tracks.isEmpty()) return@coroutineScope null
            return@coroutineScope ChartList(p.id, dz.tracks.map { it.copy(sourceService = "Deezer Top Worldwide") },
                dz.albums.take(25), "Deezer Charts · Top Worldwide", now)
        }
        if (appleSongs.isNotEmpty()) {
            return@coroutineScope ChartList(p.id, appleSongs, appleAlbums.ifEmpty { dz?.albums?.take(25) ?: emptyList() }, "Apple Music", now)
        }
        if (dz != null && dz.tracks.isNotEmpty()) {
            return@coroutineScope ChartList(p.id, dz.tracks, appleAlbums.ifEmpty { dz.albums.take(25) }, "Deezer Charts", now)
        }
        null
    }

    // ---- Gêneros (para "Para você") ----

    suspend fun cachedGenreSongs(g: MusicGenre): List<Track>? {
        genreMemory[g.id]?.let { return it.first }
        return withContext(Dispatchers.IO) {
            try {
                val f = genreFile(g.id)
                if (!f.exists()) null
                else LumeJson.decodeFromString(ListSerializer(Track.serializer()), f.readText()).takeIf { it.isNotEmpty() }?.also {
                    genreMemory[g.id] = it to f.lastModified()
                }
            } catch (_: Exception) { null }
        }
    }

    suspend fun genreSongs(g: MusicGenre, force: Boolean = false): List<Track> {
        if (genreMemory[g.id] == null) cachedGenreSongs(g)
        genreMemory[g.id]?.let { if (!force && System.currentTimeMillis() - it.second < GENRE_FRESH_MS) return it.first }
        var songs = GenreSources.songs(g, 30)
        if (songs.size < 8) {
            val extra = MusicEngine.searchSongs(g.searchQuery, 25)
            val seen = songs.map { it.id }.toMutableSet()
            songs = songs + extra.filter { seen.add(it.id) }
        }
        if (songs.isEmpty()) return genreMemory[g.id]?.first ?: emptyList()
        genreMemory[g.id] = songs to System.currentTimeMillis()
        withContext(Dispatchers.IO) {
            try { genreFile(g.id).writeText(LumeJson.encodeToString(ListSerializer(Track.serializer()), songs)) } catch (_: Exception) {}
        }
        return songs
    }
}
