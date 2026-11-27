package com.adriano.lumemusic.engine

import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.ArtistDetail
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.DiscoverFeed
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.data.newTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/** Motor de descoberta: lançamentos, paradas, artistas (Deezer + Apple + YouTube Music), com cache em disco. */
object DiscoveryService {
    // Playlists oficiais "Deezer Charts" (auditadas): Top Brasil e Top Worldwide.
    private const val DEEZER_TOP_BRASIL = 1111141961L
    private const val DEEZER_TOP_WORLDWIDE = 3155776842L

    private val albumsMemo = ConcurrentHashMap<Long, List<AlbumShowcase>>()
    @Volatile private var memoryFeed: DiscoverFeed? = null
    private val feedFile get() = DiscNet.caches("lume_discover_feed_v2.json")

    fun cachedFeed(): DiscoverFeed? {
        memoryFeed?.let { return it }
        return try {
            if (!feedFile.exists()) null
            else LumeJson.decodeFromString(DiscoverFeed.serializer(), feedFile.readText()).also { memoryFeed = it }
        } catch (_: Exception) { null }
    }

    suspend fun feed(maxAgeMs: Long = 3 * 3600_000L): DiscoverFeed {
        cachedFeed()?.let { if (System.currentTimeMillis() - it.updatedAt < maxAgeMs) return it }
        return refresh()
    }

    /** Chamado a cada etapa da atualização (Home/Explorar reagem sem esperar tudo terminar). */
    @Volatile var onPublish: ((DiscoverFeed) -> Unit)? = null

    private val refreshLock = Mutex()
    private var refreshTask: Deferred<DiscoverFeed>? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Atualização coalescida: chamadas simultâneas (Home, Explorar, RootScreen) compartilham a mesma busca. */
    suspend fun refresh(): DiscoverFeed {
        val task = refreshLock.withLock {
            refreshTask ?: scope.async {
                try { runRefresh() } finally { refreshLock.withLock { refreshTask = null } }
            }.also { refreshTask = it }
        }
        return task.await()
    }

    private fun publish(feed: DiscoverFeed) {
        val anyData = !(feed.newReleases.isEmpty() && feed.brazilReleases.isEmpty() && feed.topBrazil.isEmpty() &&
            feed.topGlobal.isEmpty() && feed.topArtists.isEmpty() && feed.trending.isEmpty())
        if (!anyData) return
        memoryFeed = feed
        try { feedFile.writeText(LumeJson.encodeToString(DiscoverFeed.serializer(), feed)) } catch (_: Exception) {}
        onPublish?.invoke(feed)
    }

    private suspend fun runRefresh(): DiscoverFeed = coroutineScope {
        albumsMemo.clear()
        val old = cachedFeed()

        // ETAPA 1 (rápida, tudo em paralelo): paradas, artistas e álbuns mais ouvidos.
        val brPL = async { ChartParsers.deezerPlaylistTracks(DEEZER_TOP_BRASIL) }
        val wwPL = async { ChartParsers.deezerPlaylistTracks(DEEZER_TOP_WORLDWIDE) }
        val tbApple = async { appleTracks("br") }
        val abr = async { appleAlbums("br") }
        val aus = async { appleAlbums("us") }
        val agb = async { appleAlbums("gb") }
        val br = brPL.await(); val ww = wwPL.await(); val topBRApple = tbApple.await()
        val albBR = abr.await(); val albUS = aus.await(); val albGB = agb.await()

        // "Top Brasil" = parada da Apple Music do Brasil (o que os brasileiros mais ouvem, inclui hits internacionais);
        // reserva = playlist "Top Brasil" do Deezer. "Top Global" = playlist Deezer "Top Worldwide".
        val topBR = topBRApple.ifEmpty { br?.tracks ?: emptyList() }
        val topG = ww?.tracks ?: emptyList()
        // Artistas: calculados a partir dessas paradas (e não do /chart/0 do Deezer, que muda conforme o país do IP).
        var brArtists = (br?.artists ?: emptyList()).take(30)
        if (brArtists.isEmpty()) brArtists = fetchTopArtistsFallback()
        val worldArtists = (ww?.artists ?: emptyList()).take(30)

        var feed = DiscoverFeed(
            updatedAt = System.currentTimeMillis(),
            newReleases = old?.newReleases ?: emptyList(),
            brazilReleases = old?.brazilReleases ?: emptyList(),
            topBrazil = topBR.ifEmpty { old?.topBrazil ?: emptyList() },
            topGlobal = topG.ifEmpty { old?.topGlobal ?: emptyList() },
            topArtists = brArtists.ifEmpty { old?.topArtists ?: emptyList() },
            trending = old?.trending ?: emptyList(),
            topAlbumsBrazil = if (albBR.isEmpty()) old?.topAlbumsBrazil else albBR.take(25),
            topAlbumsGlobal = if (albUS.isEmpty()) old?.topAlbumsGlobal else albUS.take(25),
            globalTopArtists = worldArtists.ifEmpty { old?.globalTopArtists },
            brazilianHits = if (br?.tracks.isNullOrEmpty()) old?.brazilianHits else br?.tracks,
        )
        publish(feed)

        // ETAPA 2 (mais lenta: dezenas de consultas ao Deezer): lançamentos do mundo e do Brasil + "em alta".
        val nr = async { buildNewReleases(worldArtists, albUS + albGB) }
        val brr = async { buildBrazilReleases(brArtists, albBR) }
        val tr = async { fetchTrending() }
        val newR = nr.await(); val brR = brr.await(); val trend = tr.await()
        feed = feed.copy(
            trending = trend.ifEmpty { feed.trending },
            newReleases = newR.ifEmpty { feed.newReleases },
            brazilReleases = brR.ifEmpty { feed.brazilReleases },
            updatedAt = System.currentTimeMillis(),
        )
        publish(feed)
        feed
    }

    // ---------------- Artista ----------------

    suspend fun artistDetail(name: String, deezerId: Long?): ArtistDetail? = coroutineScope {
        var info: ArtistInfo? = null
        if (deezerId != null) {
            DiscNet.json("https://api.deezer.com/artist/$deezerId")?.obj()?.let { info = artistInfo(it) }
        }
        if (info == null) info = resolveArtist(name)
        val artist = info ?: return@coroutineScope null
        val id = artist.deezerId ?: return@coroutineScope null
        val top = async { DiscNet.json("https://api.deezer.com/artist/$id/top?limit=20") }
        val alb = async { artistAlbums(id, artist.name, 50) }
        val rel = async { DiscNet.json("https://api.deezer.com/artist/$id/related?limit=12") }
        val topTracks = top.await()["data"].objs().mapNotNull { deezerTrack(it, artist.name) }
        val albums = alb.await()
        val related = rel.await()["data"].objs().mapNotNull { artistInfo(it) }
        val today = dayString(0)
        val sorted = albums.filter { (it.releaseDate ?: "") <= today }.sortedByDescending { it.releaseDate ?: "" }
        ArtistDetail(artist, topTracks, sorted, related)
    }

    suspend fun newReleases(forArtists: List<String>, withinDays: Int = 45): List<AlbumShowcase> = coroutineScope {
        val seen = HashSet<String>()
        val unique = mutableListOf<String>()
        for (n in forArtists) {
            val k = DiscText.normalize(n)
            if (k.isEmpty() || !seen.add(k)) continue
            unique.add(n)
            if (unique.size >= 12) break
        }
        val cutoff = dayString(withinDays)
        val today = dayString(0)
        val lists = unique.map { n ->
            async {
                val a = resolveArtist(n) ?: return@async emptyList()
                val id = a.deezerId ?: return@async emptyList()
                recentAlbums(id, a.name).filter { (it.releaseDate ?: "") >= cutoff && (it.releaseDate ?: "") <= today }
            }
        }.awaitAll()
        dedupe(lists.flatten()).sortedByDescending { it.releaseDate ?: "" }
    }

    // ---------------- Faixas de álbum ----------------

    suspend fun albumTracks(album: AlbumShowcase): List<Track> {
        fun finish(tracks: List<Track>) = tracks.map { t ->
            t.copy(artworkURL = if (album.artworkURL.isEmpty()) t.artworkURL else album.artworkURL, album = album.title)
        }
        if (album.deezerId != null) {
            val tracks = deezerAlbumTracks(album.deezerId, album)
            if (tracks.isNotEmpty()) return finish(tracks)
        }
        var itunesId = album.itunesId
        if (itunesId == null && album.id.startsWith("alb_")) itunesId = album.id.drop(4).toLongOrNull()
        if (itunesId == null) {
            val term = DiscNet.enc("${album.title} ${album.artist}")
            val obj = DiscNet.json("https://itunes.apple.com/search?term=$term&entity=album&country=br&limit=8")
            val hit = obj["results"].objs().firstOrNull {
                DiscText.artistMatches(it["artistName"].str() ?: "", album.artist) &&
                    DiscText.titleLooselyMatches(it["collectionName"].str() ?: "", album.title)
            }
            itunesId = hit?.get("collectionId").lng()
        }
        if (itunesId != null) {
            for (country in listOf("br", "us")) {
                val obj = DiscNet.json("https://itunes.apple.com/lookup?id=$itunesId&entity=song&country=$country&limit=200") ?: continue
                val tracks = obj["results"].objs().mapNotNull { r ->
                    if (r["wrapperType"].str() != "track") return@mapNotNull null
                    val title = r["trackName"].str() ?: return@mapNotNull null
                    newTrack(title = title, artist = r["artistName"].str() ?: album.artist, album = album.title,
                        duration = (r["trackTimeMillis"].dbl() ?: 0.0) / 1000, artworkURL = album.artworkURL,
                        sourceService = "Apple", isExplicit = r["trackExplicitness"].str() == "explicit")
                }
                if (tracks.isNotEmpty()) return finish(tracks)
            }
        }
        if (album.deezerId == null) {
            val q = DiscNet.enc("${album.title} ${album.artist}")
            val obj = DiscNet.json("https://api.deezer.com/search/album?q=$q&limit=5")
            val hit = obj["data"].objs().firstOrNull {
                DiscText.titleLooselyMatches(it["title"].str() ?: "", album.title) &&
                    DiscText.artistMatches(it["artist"]["name"].str() ?: "", album.artist)
            }
            val id = hit?.get("id").lng()
            if (id != null) return finish(deezerAlbumTracks(id, album))
        }
        return emptyList()
    }

    private suspend fun deezerAlbumTracks(id: Long, album: AlbumShowcase): List<Track> {
        val obj = DiscNet.json("https://api.deezer.com/album/$id/tracks?limit=200") ?: return emptyList()
        return obj["data"].objs().mapNotNull { d ->
            deezerTrack(d, album.artist)?.copy(album = album.title, artworkURL = album.artworkURL)
        }
    }

    // ---------------- Listas ----------------

    private suspend fun appleTracks(country: String): List<Track> =
        ChartParsers.appleSongs(ChartParsers.appleChart(country, "songs", 50), "Apple")

    /** Reserva: ranking de artistas do Deezer (varia com o país do IP; só usado se a playlist Top Brasil falhar). */
    private suspend fun fetchTopArtistsFallback(): List<ArtistInfo> {
        val obj = DiscNet.json("https://api.deezer.com/chart/0/artists?limit=30") ?: return emptyList()
        return obj["data"].objs().mapIndexedNotNull { i, d -> artistInfo(d)?.copy(rank = i + 1) }
    }

    private suspend fun fetchTrending(): List<Track> = coroutineScope {
        // Sem reserva de outro país, para o rótulo "Brasil" ser verdadeiro.
        val tracks = fetchYTMTrending()
        if (tracks.isEmpty()) return@coroutineScope emptyList()
        val upgrades = tracks.mapIndexedNotNull { i, t ->
            if (ArtworkResolver.needsUpgrade(t.artworkURL)) async { i to ArtworkResolver.albumCover(t.title, t.artist, t.album) } else null
        }.awaitAll()
        val mutable = tracks.toMutableList()
        for ((i, url) in upgrades) if (url != null) mutable[i] = mutable[i].copy(artworkURL = url)
        mutable
    }

    private suspend fun fetchYTMTrending(): List<Track> {
        var playlistId = "VLOLAK5uy_nxSJNrV0WQ9XbKv_4R9Y98EYwJnZBgkfg"
        val chartBody = jsonObjectOf(
            "context" to InnerTube.webContext, "browseId" to "FEmusic_charts",
            "formData" to mapOf("selectedValues" to listOf("BR")),
        )
        DiscNet.postJson("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false", chartBody, headers = InnerTube.ytHeaders)?.let { charts ->
            var found: String? = null
            charts.walk { d ->
                val r = d["musicTwoRowItemRenderer"].obj()
                if (r != null) {
                    val text = InnerTube.runsArray(r["title"]).firstOrNull()
                    val bid = r["navigationEndpoint"]["browseEndpoint"]["browseId"].str()
                    if (text != null && text.lowercase().contains("em alta") && bid != null) { found = bid; return@walk true }
                }
                false
            }
            found?.let { playlistId = it }
        }
        val body = jsonObjectOf("context" to InnerTube.webContext, "browseId" to playlistId)
        val obj = DiscNet.postJson("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false", body, headers = InnerTube.ytHeaders)
            ?: return emptyList()
        val tracks = mutableListOf<Track>()
        obj.walk { d ->
            val r = d["musicResponsiveListItemRenderer"].obj()
            if (r != null) {
                val t = InnerTube.ytmChartTrack(r)
                if (t != null) tracks.add(t)
            }
            false
        }
        val seen = HashSet<String>()
        return tracks.filter { seen.add(it.id) }
    }

    /** Lançamentos do mundo: álbuns recentes dos maiores artistas da parada global + álbuns novos mais ouvidos nos EUA/Reino Unido. */
    private suspend fun buildNewReleases(worldArtists: List<ArtistInfo>, apple: List<AlbumShowcase>): List<AlbumShowcase> {
        val cutoff = dayString(120)
        val today = dayString(0)
        val pairs = worldArtists.take(14).mapNotNull { a -> a.deezerId?.let { it to a.name } }
        val deezer = recentForArtists(pairs)
        val recent = (deezer + apple).filter { (it.releaseDate ?: "") >= cutoff && (it.releaseDate ?: "") <= today }
        return dedupe(recent).sortedByDescending { it.releaseDate ?: "" }.take(40)
    }

    /** Lançamentos do Brasil: só entra o que for de artista da parada brasileira ou de gênero tipicamente brasileiro. */
    private suspend fun buildBrazilReleases(brazilArtists: List<ArtistInfo>, apple: List<AlbumShowcase>): List<AlbumShowcase> {
        val pairs = brazilArtists.take(16).mapNotNull { a -> a.deezerId?.let { it to a.name } }
        val deezer = recentForArtists(pairs)
        val cutoffDz = dayString(150)
        val cutoffAp = dayString(90)
        val today = dayString(0)
        val dzRecent = deezer.filter { (it.releaseDate ?: "") >= cutoffDz && (it.releaseDate ?: "") <= today }
        val brNames = brazilArtists.map { DiscText.normalize(it.name) }.toSet()
        val brGenres = listOf("sertanej", "mpb", "pagode", "samba", "funk", "forro", "axe", "brasil", "piseiro", "arrocha",
            "bossa", "tropicalia", "choro", "frevo")
        fun isBrazilian(a: AlbumShowcase): Boolean {
            val g = DiscText.normalize(a.genre)
            if (brGenres.any { g.contains(it) }) return true
            return DiscText.splitArtists(a.artist).any { it in brNames }
        }
        val apRecent = apple.filter { (it.releaseDate ?: "") >= cutoffAp && (it.releaseDate ?: "") <= today && isBrazilian(it) }
        return dedupe(dzRecent + apRecent).sortedByDescending { it.releaseDate ?: "" }.take(40)
    }

    private suspend fun appleAlbums(country: String): List<AlbumShowcase> =
        ChartParsers.appleAlbums(ChartParsers.appleChart(country, "albums", 50), 1000)

    private suspend fun recentForArtists(artists: List<Pair<Long, String>>): List<AlbumShowcase> = coroutineScope {
        val result = mutableListOf<AlbumShowcase>()
        for (slice in artists.chunked(8)) {
            result += slice.map { (id, name) -> async { recentAlbums(id, name) } }.awaitAll().flatten()
        }
        result
    }

    private suspend fun recentAlbums(artistId: Long, artistName: String): List<AlbumShowcase> {
        albumsMemo[artistId]?.let { return it }
        val r = artistAlbums(artistId, artistName, 40)
        albumsMemo[artistId] = r
        return r
    }

    private suspend fun artistAlbums(id: Long, artistName: String, limit: Int): List<AlbumShowcase> {
        val obj = DiscNet.json("https://api.deezer.com/artist/$id/albums?limit=$limit") ?: return emptyList()
        return obj["data"].objs().mapNotNull { deezerAlbum(it, artistName) }
    }

    suspend fun resolveArtist(name: String): ArtistInfo? {
        val clean = DiscText.searchArtist(name)
        val obj = DiscNet.json("https://api.deezer.com/search/artist?q=${DiscNet.enc(clean)}&limit=5") ?: return null
        val target = DiscText.normalize(clean)
        val data = obj["data"].objs()
        val hit = data.firstOrNull { DiscText.normalize(it["name"].str() ?: "") == target }
            ?: data.firstOrNull { DiscText.artistMatches(it["name"].str() ?: "", clean) }
        return hit?.let { artistInfo(it) }
    }

    // ---------------- Parsers ----------------

    fun artistInfo(d: JsonObject): ArtistInfo? {
        val id = d["id"].lng() ?: return null
        val name = d["name"].str() ?: return null
        var pic = d["picture_xl"].str() ?: d["picture_big"].str() ?: ""
        if (pic.contains("/images/artist//")) pic = ""
        return ArtistInfo("dz_$id", name, pic, id, d["nb_fan"].lng(), null)
    }

    fun deezerTrack(d: JsonElement, fallbackArtist: String): Track? {
        val title = d["title"].str()?.takeIf { it.isNotEmpty() } ?: return null
        val artistName = d["artist"]["name"].str() ?: fallbackArtist
        val album = d["album"]
        var cover = album["cover_xl"].str() ?: album["cover_big"].str() ?: ""
        if (cover.contains("/cover//")) cover = ""
        return newTrack(title = title, artist = artistName, album = album["title"].str() ?: "",
            duration = (d["duration"].int() ?: 0).toDouble(), artworkURL = cover, sourceService = "Deezer",
            isExplicit = d["explicit_lyrics"].bool() ?: false)
    }

    fun deezerAlbum(d: JsonElement, artist: String): AlbumShowcase? {
        val id = d["id"].lng() ?: return null
        val title = d["title"].str() ?: return null
        val date = d["release_date"].str()
        val kind = when (d["record_type"].str()?.lowercase()) { "single" -> "Single"; "ep" -> "EP"; else -> "Álbum" }
        val cover = d["cover_xl"].str() ?: d["cover_big"].str() ?: ""
        return AlbumShowcase(id = "dzalb_$id", title = title, artist = artist, artworkURL = cover,
            year = DiscText.year(date), genre = "", releaseDate = date, kind = kind, deezerId = id)
    }

    fun appleSongs(results: List<JsonObject>): List<Track> = results.mapNotNull { r ->
        val title = r["name"].str() ?: return@mapNotNull null
        newTrack(title = title, artist = r["artistName"].str() ?: "",
            artworkURL = DiscText.upscaleApple(r["artworkUrl100"].str() ?: ""), sourceService = "Apple",
            isExplicit = (r["contentAdvisoryRating"].str() ?: "").lowercase().startsWith("explic"))
    }

    fun dedupe(albums: List<AlbumShowcase>): List<AlbumShowcase> {
        val index = HashMap<String, Int>()
        val out = mutableListOf<AlbumShowcase>()
        for (a in albums) {
            val key = DiscText.normalize(a.title) + "|" + DiscText.normalize(DiscText.splitArtists(a.artist).firstOrNull() ?: a.artist)
            val i = index[key]
            if (i != null) {
                var cur = out[i]
                if (cur.deezerId == null) cur = cur.copy(deezerId = a.deezerId)
                if (cur.itunesId == null) cur = cur.copy(itunesId = a.itunesId)
                if (cur.genre.isEmpty()) cur = cur.copy(genre = a.genre)
                if (a.deezerId != null && cur.deezerId == a.deezerId && a.id.startsWith("dzalb_")) cur = cur.copy(id = a.id)
                out[i] = cur
            } else {
                index[key] = out.size
                out.add(a)
            }
        }
        return out
    }

    fun dayString(daysAgo: Int): String {
        val f = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        return f.format(Date(System.currentTimeMillis() - daysAgo * 86_400_000L))
    }
}
