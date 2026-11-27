package com.adriano.lumemusic.engine

import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.ChartCountry
import com.adriano.lumemusic.data.DiscoverFeed
import com.adriano.lumemusic.data.MusicGenre
import com.adriano.lumemusic.data.PersonalizedMix
import com.adriano.lumemusic.data.RemotePlaylist
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.data.newTrack
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.util.concurrent.ConcurrentHashMap

data class CountryChartBundle(
    val country: ChartCountry,
    val topSongs: List<Track>,
    val topAlbums: List<AlbumShowcase>,
    val topArtists: List<ArtistInfo>,
    val trending: List<Track>,
    val updatedAt: Long,
)

data class GenreHubBundle(
    val genre: MusicGenre,
    val topSongs: List<Track>,
    val topAlbums: List<AlbumShowcase>,
    val topArtists: List<ArtistInfo>,
    val playlists: List<RemotePlaylist>,
    val updatedAt: Long,
)

@Serializable
private data class CountryDisk(
    val topSongs: List<Track>, val topAlbums: List<AlbumShowcase>, val topArtists: List<ArtistInfo>,
    val trending: List<Track>, val updatedAt: Long,
)

@Serializable
private data class GenreDisk(
    val topSongs: List<Track>, val topAlbums: List<AlbumShowcase>, val topArtists: List<ArtistInfo>,
    val playlists: List<RemotePlaylist>, val updatedAt: Long,
)

/** Exploração por país, gênero, playlists editoriais e mixes personalizados (porta de CatalogExplorerService.swift). */
object CatalogExplorerService {
    private val countryCache = ConcurrentHashMap<String, CountryChartBundle>()
    private val genreCache = ConcurrentHashMap<String, GenreHubBundle>()
    private val playlistCache = ConcurrentHashMap<Long, Pair<List<Track>, Long>>()
    private const val TTL = 2 * 3600_000L
    private const val DEEZER_TOP_WORLDWIDE = 3155776842L

    // ---------------- Paradas por País ----------------

    /** Último pacote salvo (memória/disco), de qualquer idade. Serve para mostrar algo NA HORA e atualizar depois. */
    suspend fun cachedCountryChart(country: ChartCountry): CountryChartBundle? {
        countryCache[country.code]?.let { return it }
        return withContext(Dispatchers.IO) {
            try {
                val f = DiscNet.caches("lume_country_v2_${country.code}.json")
                if (!f.exists()) return@withContext null
                val d = LumeJson.decodeFromString(CountryDisk.serializer(), f.readText())
                if (d.topSongs.isEmpty()) return@withContext null
                CountryChartBundle(country, d.topSongs, d.topAlbums, d.topArtists, d.trending, d.updatedAt).also { countryCache[country.code] = it }
            } catch (_: Exception) { null }
        }
    }

    /** Etapa rápida: só músicas e álbuns (compartilha o cache com a Home). Preserva artistas/em alta já conhecidos. */
    suspend fun countryChartFast(country: ChartCountry, force: Boolean = false): CountryChartBundle? {
        val place = ChartPlace.place(country.code) ?: return cachedCountryChart(country)
        val list = ChartsService.load(place, force) ?: return cachedCountryChart(country)
        val prev = cachedCountryChart(country)
        val bundle = CountryChartBundle(country, list.songs, list.albums, prev?.topArtists ?: emptyList(), prev?.trending ?: emptyList(), list.updatedAt)
        countryCache[country.code] = bundle
        return bundle
    }

    /** Pacote completo: músicas, álbuns, artistas ranqueados e "em alta" do YouTube Music do país. */
    suspend fun countryChart(country: ChartCountry, force: Boolean = false): CountryChartBundle = coroutineScope {
        if (!force) countryCache[country.code]?.let {
            if (System.currentTimeMillis() - it.updatedAt < TTL && (it.topArtists.isNotEmpty() || it.trending.isNotEmpty())) return@coroutineScope it
        }
        val fastT = async { countryChartFast(country, force) }
        val ytmT = async { fetchYTMCountryCharts(country.ytmCode) }
        val fast = fastT.await(); val ytm = ytmT.await()
        val songs = fast?.topSongs ?: emptyList()

        var artists = emptyList<ArtistInfo>()
        if (country.code == "world") {
            // Global: artistas da própria parada global do Deezer (a lista de artistas do YouTube Global é dominada pela Índia).
            ChartParsers.deezerPlaylistTracks(DEEZER_TOP_WORLDWIDE)?.let { artists = it.artists.take(16) }
        } else if (ytm.first.isNotEmpty()) {
            artists = resolveArtists(ytm.first, 16)
        }
        if (artists.isEmpty()) artists = resolveArtists(songs.map { primaryArtist(it.artist) }, 16)

        val bundle = CountryChartBundle(country, songs, fast?.topAlbums ?: emptyList(), artists, ytm.second, System.currentTimeMillis())
        if (songs.isNotEmpty()) {
            countryCache[country.code] = bundle
            withContext(Dispatchers.IO) {
                try {
                    DiscNet.caches("lume_country_v2_${country.code}.json").writeText(
                        LumeJson.encodeToString(CountryDisk.serializer(), CountryDisk(songs, bundle.topAlbums, artists, ytm.second, bundle.updatedAt)))
                } catch (_: Exception) {}
            }
        }
        bundle
    }

    // ---------------- Hub de Gênero Musical ----------------

    /** Último hub salvo (qualquer idade) para mostrar na hora e atualizar em seguida. */
    suspend fun cachedGenreHub(genre: MusicGenre): GenreHubBundle? {
        genreCache[genre.id]?.let { return it }
        return withContext(Dispatchers.IO) {
            try {
                val f = DiscNet.caches("lume_genre_v2_${genre.id}.json")
                if (!f.exists()) return@withContext null
                val d = LumeJson.decodeFromString(GenreDisk.serializer(), f.readText())
                if (d.topSongs.isEmpty()) return@withContext null
                GenreHubBundle(genre, d.topSongs, d.topAlbums, d.topArtists, d.playlists, d.updatedAt).also { genreCache[genre.id] = it }
            } catch (_: Exception) { null }
        }
    }

    suspend fun genreHub(genre: MusicGenre, force: Boolean = false): GenreHubBundle = coroutineScope {
        val now = System.currentTimeMillis()
        if (!force) genreCache[genre.id]?.let { if (now - it.updatedAt < TTL) return@coroutineScope it }
        if (!force) cachedGenreHub(genre)?.let { if (now - it.updatedAt < TTL) return@coroutineScope it }
        val sT = async { GenreSources.songs(genre, 30) }
        val aT = async { GenreSources.albums(genre, 16) }
        val pT = async { SearchService.playlists(genre.playlistQuery, 10) }
        val appleSongs = sT.await(); val appleAlbums = aT.await(); val playlists = pT.await()
        val songs = appleSongs.toMutableList()
        if (songs.size < 12) {
            val extra = MusicEngine.searchSongs(genre.searchQuery, 25)
            val seen = songs.map { it.id }.toMutableSet()
            for (t in extra) if (seen.add(t.id)) songs.add(t)
        }
        val artists = resolveArtists(songs.map { primaryArtist(it.artist) }, 16)
        val bundle = GenreHubBundle(genre, songs.take(35), appleAlbums, artists, playlists, System.currentTimeMillis())
        if (bundle.topSongs.isNotEmpty()) {
            genreCache[genre.id] = bundle
            withContext(Dispatchers.IO) {
                try {
                    DiscNet.caches("lume_genre_v2_${genre.id}.json").writeText(
                        LumeJson.encodeToString(GenreDisk.serializer(), GenreDisk(bundle.topSongs, appleAlbums, artists, playlists, bundle.updatedAt)))
                } catch (_: Exception) {}
            }
        }
        bundle
    }

    // ---------------- Faixas de Playlist Editorial ----------------

    suspend fun playlistTracks(deezerId: Long): List<Track> {
        playlistCache[deezerId]?.let { if (System.currentTimeMillis() - it.second < 3600_000L) return it.first }
        val obj = DiscNet.json("https://api.deezer.com/playlist/$deezerId/tracks?limit=100", 8, retries = 1) ?: return emptyList()
        val tracks = obj["data"].objs().mapNotNull { d ->
            val title = d["title"].str()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val artist = d["artist"]["name"].str() ?: "Artista"
            val alb = d["album"]
            var cover = alb["cover_xl"].str() ?: alb["cover_big"].str() ?: ""
            if (cover.contains("/cover//")) cover = ""
            newTrack(
                title = title, artist = artist, album = alb["title"].str() ?: "", duration = d["duration"].dbl() ?: 0.0,
                artworkURL = cover, sourceService = "Playlist", isExplicit = d["explicit_lyrics"].bool() ?: false,
            )
        }
        if (tracks.isNotEmpty()) playlistCache[deezerId] = tracks to System.currentTimeMillis()
        return tracks
    }

    // ---------------- Mixes personalizados ----------------

    fun buildPersonalizedMixes(
        mostPlayed: List<Track>, favorites: List<Track>, recent: List<Track>, topArtists: List<String>, feed: DiscoverFeed?,
    ): List<PersonalizedMix> {
        val mixes = mutableListOf<PersonalizedMix>()
        val br = feed?.topBrazil ?: emptyList()
        val brHits = feed?.brazilianHits ?: emptyList()
        val gl = feed?.topGlobal ?: emptyList()
        if (mostPlayed.isNotEmpty()) mixes.add(
            PersonalizedMix("mix_norepeat", "No Repeat", "As que você não para de ouvir", "SEU SOM", "repeat", 0xFF7BA9, 0xAD8CFF, mostPlayed.take(30)),
        )
        topArtists.firstOrNull()?.let { first ->
            val matching = (mostPlayed + favorites + recent + br + gl).filter { DiscText.artistMatches(it.artist, first) }
            val extra = br.filter { it !in matching }.take(10)
            val tracks = dedupeTracks(matching + extra)
            if (tracks.isNotEmpty()) mixes.add(
                PersonalizedMix("mix_daily1", "Mix Diário 1", "$first e sons na mesma vibe", "PARA VOCÊ", "sparkles", 0x7CC8FF, 0x6366F1, tracks.take(25)),
            )
        }
        if (topArtists.size >= 2) {
            val second = topArtists[1]
            val matching = (mostPlayed + favorites + recent + br + gl).filter { DiscText.artistMatches(it.artist, second) }
            val extra = gl.filter { it !in matching }.take(10)
            val tracks = dedupeTracks(matching + extra)
            if (tracks.isNotEmpty()) mixes.add(
                PersonalizedMix("mix_daily2", "Mix Diário 2", "Com $second e sucessos", "DESCOBERTA", "waveform.path.ecg", 0xFFB27A, 0xE0457B, tracks.take(25)),
            )
        }
        if (favorites.isNotEmpty()) mixes.add(
            PersonalizedMix("mix_favorites", "Radar de Curtidas", "Suas favoritas em sequência", "CURTIDAS", "heart.fill", 0xF43F5E, 0x9F1239, favorites.take(30)),
        )
        if (brHits.isNotEmpty() || br.isNotEmpty()) mixes.add(
            PersonalizedMix("mix_br_radar", "Radar Brasil",
                if (brHits.isEmpty()) "O que mais toca no Brasil hoje" else "Só música brasileira que está tocando",
                "BRASIL", "flame.fill", 0x10B981, 0x047857, (if (brHits.isEmpty()) br else brHits).take(30)),
        )
        if (gl.isNotEmpty()) mixes.add(
            PersonalizedMix("mix_global_wave", "Onda Global", "Os hits que o mundo está ouvindo", "MUNDO", "globe.americas.fill", 0x06B6D4, 0x3B82F6, dedupeTracks(gl).take(30)),
        )
        return mixes
    }

    // ---------------- Fetchers ----------------

    /** YouTube Music Charts do país: artistas em alta (ranqueados) + faixas da playlist "<País>: 20 vídeos em alta". */
    private suspend fun fetchYTMCountryCharts(ytmCode: String): Pair<List<String>, List<Track>> {
        val body = jsonObjectOf(
            "context" to InnerTube.webContext, "browseId" to "FEmusic_charts",
            "formData" to mapOf("selectedValues" to listOf(ytmCode)),
        )
        val charts = DiscNet.postJson("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false", body, headers = InnerTube.ytHeaders)
            ?: return emptyList<String>() to emptyList()
        val artistNames = mutableListOf<String>()
        var trendingId: String? = null
        charts.walk { d ->
            val r = d["musicResponsiveListItemRenderer"].obj()
            if (r != null) {
                val cols = r["flexColumns"].objs()
                val hasVideo = r["playlistItemData"]["videoId"].str() != null
                val c0 = cols.firstOrNull()?.let { InnerTube.textOfColumn(it) } ?: ""
                if (!hasVideo && c0.isNotEmpty()) artistNames.add(c0)
            }
            val two = d["musicTwoRowItemRenderer"].obj()
            if (trendingId == null && two != null) {
                val text = InnerTube.runsArray(two["title"]).firstOrNull()
                val bid = two["navigationEndpoint"]["browseEndpoint"]["browseId"].str()
                if (text != null && text.lowercase().contains("vídeos em alta") && bid != null) trendingId = bid
            }
            false
        }
        val tracks = mutableListOf<Track>()
        trendingId?.let { pid ->
            val obj = DiscNet.postJson("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
                jsonObjectOf("context" to InnerTube.webContext, "browseId" to pid), headers = InnerTube.ytHeaders)
            obj?.walk { d ->
                val r = d["musicResponsiveListItemRenderer"].obj()
                if (r != null) InnerTube.ytmChartTrack(r)?.let { tracks.add(it) }
                false
            }
        }
        val seen = HashSet<String>()
        return artistNames to tracks.filter { seen.add(it.id) }
    }

    private suspend fun resolveArtists(names: List<String>, limit: Int): List<ArtistInfo> = coroutineScope {
        val seen = HashSet<String>()
        val clean = mutableListOf<Pair<Int, String>>()
        for (n in names) {
            val base = DiscText.searchArtist(n)
            val key = DiscText.normalize(base)
            if (key.isEmpty() || !seen.add(key)) continue
            clean.add((clean.size + 1) to base)
            if (clean.size >= limit) break
        }
        clean.map { (rank, name) ->
            async {
                lookupDeezerArtist(name)?.copy(rank = rank) ?: ArtistInfo("art_${DiscText.normalize(name)}", name, "", null, null, rank)
            }
        }.awaitAll().sortedBy { it.rank ?: 0 }
    }

    private suspend fun lookupDeezerArtist(name: String): ArtistInfo? {
        val obj = DiscNet.json("https://api.deezer.com/search/artist?q=${DiscNet.enc(name)}&limit=4") ?: return null
        val target = DiscText.normalize(name)
        val data = obj["data"].objs()
        val hit = data.firstOrNull { DiscText.normalize(it["name"].str() ?: "") == target }
            ?: data.firstOrNull { DiscText.artistMatches(it["name"].str() ?: "", name) }
        return hit?.let { DiscoveryService.artistInfo(it) }
    }

    private val primarySeps = listOf(",", " feat", " ft.", " x ", " part.", " (", " com ")

    fun primaryArtist(s: String): String {
        var out = s
        for (sep in primarySeps) { val i = out.indexOf(sep, ignoreCase = true); if (i >= 0) out = out.substring(0, i) }
        return out.replace(" - Topic", "").trim()
    }

    private fun dedupeTracks(tracks: List<Track>): List<Track> { val seen = HashSet<String>(); return tracks.filter { seen.add(it.id) } }
}
