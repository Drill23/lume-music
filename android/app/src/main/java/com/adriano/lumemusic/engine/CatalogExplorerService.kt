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
import kotlinx.coroutines.coroutineScope
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

/** Exploração por país, gênero, playlists editoriais e mixes personalizados. */
object CatalogExplorerService {
    private val countryCache = ConcurrentHashMap<String, CountryChartBundle>()
    private val genreCache = ConcurrentHashMap<String, GenreHubBundle>()
    private val playlistCache = ConcurrentHashMap<Long, Pair<List<Track>, Long>>()
    private const val TTL = 2 * 3600_000L

    suspend fun countryChart(country: ChartCountry, force: Boolean = false): CountryChartBundle = coroutineScope {
        val now = System.currentTimeMillis()
        if (!force) countryCache[country.code]?.let { if (now - it.updatedAt < TTL) return@coroutineScope it }
        val disk = DiscNet.caches("lume_country_${country.code}.json")
        if (!force) {
            try {
                if (disk.exists()) {
                    val d = LumeJson.decodeFromString(CountryDisk.serializer(), disk.readText())
                    if (now - d.updatedAt < TTL && d.topSongs.isNotEmpty()) {
                        val b = CountryChartBundle(country, d.topSongs, d.topAlbums, d.topArtists, d.trending, d.updatedAt)
                        countryCache[country.code] = b
                        return@coroutineScope b
                    }
                }
            } catch (_: Exception) {}
        }
        val songsT = async { fetchAppleCountrySongs(country.code) }
        val albumsT = async { fetchAppleCountryAlbums(country.code) }
        val ytmT = async { fetchYTMCountryCharts(country.ytmCode) }
        val songs = songsT.await(); val albums = albumsT.await(); val ytm = ytmT.await()
        var artists = emptyList<ArtistInfo>()
        if (ytm.first.isNotEmpty()) artists = resolveArtists(ytm.first, 16)
        if (artists.isEmpty()) artists = resolveArtists(songs.map { primaryArtist(it.artist) }, 16)
        val bundle = CountryChartBundle(country, songs, albums, artists, ytm.second, System.currentTimeMillis())
        if (songs.isNotEmpty()) {
            countryCache[country.code] = bundle
            try {
                disk.writeText(LumeJson.encodeToString(CountryDisk.serializer(), CountryDisk(songs, albums, artists, ytm.second, bundle.updatedAt)))
            } catch (_: Exception) {}
        }
        bundle
    }

    suspend fun genreHub(genre: MusicGenre, force: Boolean = false): GenreHubBundle = coroutineScope {
        val now = System.currentTimeMillis()
        if (!force) genreCache[genre.id]?.let { if (now - it.updatedAt < TTL) return@coroutineScope it }
        val disk = DiscNet.caches("lume_genre_${genre.id}.json")
        if (!force) {
            try {
                if (disk.exists()) {
                    val d = LumeJson.decodeFromString(GenreDisk.serializer(), disk.readText())
                    if (now - d.updatedAt < TTL && d.topSongs.isNotEmpty()) {
                        val b = GenreHubBundle(genre, d.topSongs, d.topAlbums, d.topArtists, d.playlists, d.updatedAt)
                        genreCache[genre.id] = b
                        return@coroutineScope b
                    }
                }
            } catch (_: Exception) {}
        }
        val sT = async { fetchAppleGenreSongs(genre) }
        val aT = async { fetchAppleGenreAlbums(genre) }
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
            try {
                disk.writeText(LumeJson.encodeToString(GenreDisk.serializer(), GenreDisk(bundle.topSongs, appleAlbums, artists, playlists, bundle.updatedAt)))
            } catch (_: Exception) {}
        }
        bundle
    }

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
        val gl = feed?.topGlobal ?: emptyList()
        val tr = feed?.trending ?: emptyList()
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
        if (br.isNotEmpty()) mixes.add(
            PersonalizedMix("mix_br_radar", "Radar Brasil", "O que domina o país hoje", "BRASIL", "flame.fill", 0x10B981, 0x047857, br.take(30)),
        )
        if (tr.isNotEmpty() || gl.isNotEmpty()) mixes.add(
            PersonalizedMix("mix_global_wave", "Onda Global", "Hits subindo no mundo inteiro", "MUNDO", "globe.americas.fill", 0x06B6D4, 0x3B82F6, dedupeTracks(tr + gl).take(30)),
        )
        return mixes
    }

    // ---------------- Fetchers ----------------

    private val reApple = Regex("""\d{2,4}x\d{2,4}(bb|cc)""")
    private fun upscale1000(url: String) = url.replace(reApple, "1000x1000bb")

    private suspend fun fetchAppleCountrySongs(country: String): List<Track> {
        val obj = DiscNet.json("https://rss.marketingtools.apple.com/api/v2/$country/music/most-played/50/songs.json", 6, retries = 2)
        return obj["feed"]["results"].objs().mapNotNull { r ->
            val title = r["name"].str() ?: return@mapNotNull null
            newTrack(
                title = title, artist = r["artistName"].str() ?: "", artworkURL = upscale1000(r["artworkUrl100"].str() ?: ""),
                sourceService = "Apple ${country.uppercase()}",
                isExplicit = (r["contentAdvisoryRating"].str() ?: "").lowercase().startsWith("explic"),
            )
        }
    }

    private suspend fun fetchAppleCountryAlbums(country: String): List<AlbumShowcase> {
        val obj = DiscNet.json("https://rss.marketingtools.apple.com/api/v2/$country/music/most-played/25/albums.json", 6, retries = 2)
        return obj["feed"]["results"].objs().mapNotNull { r ->
            val idStr = r["id"].strLoose() ?: return@mapNotNull null
            var title = r["name"].str() ?: return@mapNotNull null
            var kind = "Álbum"
            for ((suffix, k) in listOf(" - Single" to "Single", " - EP" to "EP")) {
                if (title.endsWith(suffix)) { title = title.dropLast(suffix.length); kind = k }
            }
            val date = r["releaseDate"].str()
            val genre = r["genres"].objs().mapNotNull { it["name"].str() }.firstOrNull { it != "Música" && it != "Music" } ?: ""
            AlbumShowcase(
                "alb_$idStr", title, r["artistName"].str() ?: "", upscale1000(r["artworkUrl100"].str() ?: ""),
                year = DiscText.year(date), genre = genre, releaseDate = date, kind = kind, itunesId = idStr.toLongOrNull(),
            )
        }
    }

    private suspend fun fetchYTMCountryCharts(ytmCode: String): Pair<List<String>, List<Track>> {
        val body = jsonObjectOf(
            "context" to InnerTube.webContext, "browseId" to "FEmusic_charts",
            "formData" to mapOf("selectedValues" to listOf(ytmCode)),
        )
        val charts = DiscNet.postJson("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false", body, headers = InnerTube.ytHeaders)
            ?: return emptyList<String>() to emptyList()
        val names = mutableListOf<String>()
        val tracks = mutableListOf<Track>()
        charts.walk { d ->
            val r = d["musicResponsiveListItemRenderer"].obj()
            if (r != null) {
                val vid = r["playlistItemData"]["videoId"].str()
                val cols = r["flexColumns"].objs()
                val c0 = cols.getOrNull(0)?.let { InnerTube.textOfColumn(it) } ?: ""
                val c1 = cols.getOrNull(1)?.let { InnerTube.textOfColumn(it) } ?: ""
                if (!vid.isNullOrEmpty() && c0.isNotEmpty()) {
                    val th = r["thumbnail"]["musicThumbnailRenderer"]["thumbnail"]["thumbnails"].objs()
                    val thumb = th.lastOrNull()?.get("url").str() ?: ""
                    tracks.add(newTrack(videoId = vid, title = c0, artist = c1, artworkURL = thumb, sourceService = "YouTube Music"))
                } else if (c0.isNotEmpty()) names.add(c0)
            }
            false
        }
        return names to tracks
    }

    private suspend fun fetchAppleGenreSongs(genre: MusicGenre): List<Track> {
        val gid = genre.appleGenreId ?: return emptyList()
        val obj = DiscNet.json("https://itunes.apple.com/${genre.appleCountry}/rss/topsongs/limit=30/genre=$gid/json", 6, retries = 1)
        return obj["feed"]["entry"].objs().mapNotNull { e ->
            val title = e["im:name"]["label"].str() ?: return@mapNotNull null
            val artist = e["im:artist"]["label"].str() ?: return@mapNotNull null
            val art = upscale1000(e["im:image"].objs().lastOrNull()?.get("label").str() ?: "")
            val album = e["im:collection"]["im:name"]["label"].str() ?: ""
            newTrack(title = title, artist = artist, album = album, artworkURL = art, sourceService = genre.title)
        }
    }

    private suspend fun fetchAppleGenreAlbums(genre: MusicGenre): List<AlbumShowcase> {
        val gid = genre.appleGenreId ?: return emptyList()
        val obj = DiscNet.json("https://itunes.apple.com/${genre.appleCountry}/rss/topalbums/limit=16/genre=$gid/json", 6, retries = 1)
        return obj["feed"]["entry"].objs().mapNotNull { e ->
            val title = e["im:name"]["label"].str() ?: return@mapNotNull null
            val artist = e["im:artist"]["label"].str() ?: return@mapNotNull null
            val idStr = e["id"]["attributes"]["im:id"].str() ?: Track.stableId(title, artist)
            val art = upscale1000(e["im:image"].objs().lastOrNull()?.get("label").str() ?: "")
            val release = e["im:releaseDate"]["label"].str()
            AlbumShowcase(
                "alb_$idStr", title, artist, art, year = DiscText.year(release), genre = genre.title,
                releaseDate = release?.take(10), kind = "Álbum", itunesId = idStr.toLongOrNull(),
            )
        }
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
