package com.adriano.lumemusic.engine

import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.HomeFeed
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.data.newTrack
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonObject
import java.util.concurrent.ConcurrentHashMap

/** Descoberta, busca, paradas, resolução de stream (InnerTube) e capas animadas. */
object MusicEngine {
    data class ResolvedStream(val url: String, val headers: Map<String, String>, val bitrate: Int, val expiresAt: Long, val itag: Int,
                              /** playerConfig.audioConfig.loudnessDb (dB relativo à referência do YouTube); null se não veio. */
                              val loudnessDb: Double? = null)

    private val streamCache = ConcurrentHashMap<String, ResolvedStream>()
    private val videoIdCache = ConcurrentHashMap<String, String>()
    private val animatedCache = ConcurrentHashMap<String, String>()
    @Volatile private var animatedLoaded = false

    private val animatedFile get() = DiscNet.caches("lume_music_animated_art.json")
    private val feedFile get() = DiscNet.caches("lume_music_home_feed.json")

    private fun loadAnimatedIfNeeded() {
        if (animatedLoaded) return
        animatedLoaded = true
        try {
            if (animatedFile.exists()) {
                val m = LumeJson.decodeFromString(MapSerializer(String.serializer(), String.serializer()), animatedFile.readText())
                animatedCache.putAll(m)
            }
        } catch (_: Exception) {}
    }

    private fun saveAnimated() {
        try {
            animatedFile.writeText(LumeJson.encodeToString(MapSerializer(String.serializer(), String.serializer()), animatedCache.toMap()))
        } catch (_: Exception) {}
    }

    // ---------------- Home feed (iTunes + Deezer) ----------------

    fun cachedHomeFeed(): HomeFeed? = try {
        if (feedFile.exists()) LumeJson.decodeFromString(HomeFeed.serializer(), feedFile.readText()).takeIf { it.topBrazil.isNotEmpty() } else null
    } catch (_: Exception) { null }

    suspend fun fetchHomeFeed(): HomeFeed = coroutineScope {
        val s = async { fetchITunesTopSongsBR() }
        val a = async { fetchITunesNewAlbumsBR() }
        val da = async { fetchDeezerTopAlbums() }
        val d = async { fetchDeezerTopTracks() }
        val songs = s.await(); val albums = a.await(); val dzAlbums = da.await(); val dz = d.await()
        val merged = albums.toMutableList()
        val seen = albums.map { it.title.lowercase() }.toMutableSet()
        for (item in dzAlbums) if (seen.add(item.title.lowercase())) merged.add(item)
        val feed = HomeFeed(
            topBrazil = songs.ifEmpty { dz },
            newAlbums = merged,
            globalHits = dz.ifEmpty { songs },
        )
        if (feed.topBrazil.isNotEmpty()) {
            try { feedFile.writeText(LumeJson.encodeToString(HomeFeed.serializer(), feed)) } catch (_: Exception) {}
        }
        feed
    }

    private suspend fun fetchITunesTopSongsBR(): List<Track> {
        val root = DiscNet.json("https://rss.marketingtools.apple.com/api/v2/br/music/most-played/25/songs.json") ?: return emptyList()
        return root["feed"]["results"].objs().mapNotNull { item ->
            val name = item["name"].str() ?: return@mapNotNull null
            val artist = item["artistName"].str() ?: return@mapNotNull null
            val art = (item["artworkUrl100"].str() ?: "").replace("100x100bb", "1400x1400bb")
            val explicit = item["contentAdvisoryRating"].str()?.lowercase()?.contains("expl") == true
            newTrack(title = name, artist = artist, artworkURL = art, sourceService = "Top Brasil", isExplicit = explicit)
        }
    }

    private suspend fun fetchITunesNewAlbumsBR(): List<AlbumShowcase> {
        val root = DiscNet.json("https://rss.marketingtools.apple.com/api/v2/br/music/most-played/15/albums.json") ?: return emptyList()
        return root["feed"]["results"].objs().mapNotNull { item ->
            val name = item["name"].str() ?: return@mapNotNull null
            val artist = item["artistName"].str() ?: return@mapNotNull null
            val idStr = item["id"].strLoose() ?: Track.stableId(name, artist)
            val art = (item["artworkUrl100"].str() ?: "").replace("100x100bb", "1400x1400bb")
            val release = (item["releaseDate"].str() ?: "").take(4)
            val genre = item["genres"].objs().firstOrNull()?.get("name").str() ?: "Lançamento"
            AlbumShowcase(id = "alb_$idStr", title = name, artist = artist, artworkURL = art, year = release, genre = genre)
        }
    }

    private suspend fun fetchDeezerTopAlbums(): List<AlbumShowcase> {
        val root = DiscNet.json("https://api.deezer.com/chart/0/albums?limit=14") ?: return emptyList()
        return root["data"].objs().mapNotNull { it ->
            val title = it["title"].str() ?: return@mapNotNull null
            val artist = it["artist"]["name"].str() ?: return@mapNotNull null
            val idStr = it["id"].lng()?.toString() ?: Track.stableId(title, artist)
            val art = it["cover_xl"].str() ?: it["cover_big"].str() ?: ""
            AlbumShowcase(id = "dzalb_$idStr", title = title, artist = artist, artworkURL = art, year = "2026", genre = "Em Alta")
        }
    }

    private suspend fun fetchDeezerTopTracks(): List<Track> {
        val root = DiscNet.json("https://api.deezer.com/chart/0/tracks?limit=25") ?: return emptyList()
        return root["data"].objs().mapNotNull { it ->
            val title = it["title"].str() ?: return@mapNotNull null
            val artist = it["artist"]["name"].str() ?: return@mapNotNull null
            val album = it["album"]
            newTrack(
                title = title, artist = artist, album = album["title"].str() ?: "",
                artworkURL = album["cover_xl"].str() ?: album["cover_big"].str() ?: "",
                duration = it["duration"].dbl() ?: 0.0, sourceService = "Chart",
                isExplicit = it["explicit_lyrics"].bool() ?: false,
            )
        }
    }

    suspend fun fetchAlbumTracks(albumTitle: String, artist: String, fallbackArtwork: String): List<Track> {
        val q = DiscNet.enc("$albumTitle $artist")
        val search = DiscNet.json("https://itunes.apple.com/search?term=$q&entity=album&country=br&limit=1")
        val cid = search["results"].objs().firstOrNull()?.get("collectionId").lng()
            ?: return searchSongs("$albumTitle $artist", 12)
        val lookup = DiscNet.json("https://itunes.apple.com/lookup?id=$cid&entity=song&country=br")
            ?: return searchSongs("$albumTitle $artist", 12)
        val songs = lookup["results"].objs().mapNotNull { it ->
            if (it["wrapperType"].str() != "track") return@mapNotNull null
            val name = it["trackName"].str() ?: return@mapNotNull null
            val artName = it["artistName"].str() ?: return@mapNotNull null
            val ms = it["trackTimeMillis"].dbl() ?: 0.0
            val art = (it["artworkUrl100"].str() ?: fallbackArtwork).replace("100x100bb", "1400x1400bb")
            newTrack(title = name, artist = artName, album = it["collectionName"].str() ?: albumTitle,
                duration = ms / 1000.0, artworkURL = art, sourceService = "Álbum")
        }
        return songs.ifEmpty { searchSongs("$albumTitle $artist", 12) }
    }

    // ---------------- YouTube Music (InnerTube) ----------------

    private fun ytBody(vararg extra: Pair<String, Any?>): JsonObject =
        jsonObjectOf("context" to InnerTube.webContext, *extra)

    private suspend fun ytPost(path: String, body: JsonObject): kotlinx.serialization.json.JsonElement? =
        DiscNet.postJson(
            "https://music.youtube.com/youtubei/v1/$path?prettyPrint=false", body, 8,
            mapOf("User-Agent" to InnerTube.WEB_UA, "Origin" to "https://music.youtube.com"),
        )

    suspend fun searchSongs(query: String, limit: Int = 20): List<Track> {
        val q = query.trim()
        if (q.isEmpty()) return emptyList()
        val json = ytPost("search", ytBody("query" to q, "params" to InnerTube.SONGS_FILTER))
        if (json != null) {
            val parsed = InnerTube.extractResponsiveListTracks(json, "YouTube Music")
            if (parsed.isNotEmpty()) return parsed.take(limit)
        }
        val broad = ytPost("search", ytBody("query" to q)) ?: return emptyList()
        return InnerTube.extractResponsiveListTracks(broad, "YouTube Music").take(limit)
    }

    suspend fun fetchRadioQueue(videoId: String, limit: Int = 20): List<Track> {
        val json = ytPost("next", ytBody("videoId" to videoId, "playlistId" to "RDAMVM$videoId", "isAudioOnly" to true)) ?: return emptyList()
        return InnerTube.extractPanelVideoTracks(json).filter { it.videoId != videoId }.take(limit)
    }

    suspend fun fetchYTMPlaylist(listId: String): Pair<String, List<Track>> {
        val browseId = if (listId.startsWith("VL")) listId else "VL$listId"
        val json = ytPost("browse", ytBody("browseId" to browseId)) ?: return "YouTube Music" to emptyList()
        val tracks = InnerTube.extractResponsiveListTracks(json, "YouTube Music")
        val title = InnerTube.extractFirstTitle(json) ?: "Playlist YouTube Music"
        return title to tracks
    }

    // ---------------- VideoId + stream ----------------

    suspend fun resolveVideoId(track: Track): String? {
        track.videoId?.takeIf { it.length == 11 }?.let { return it }
        videoIdCache[track.id]?.let { return it }
        val hits = searchSongs(track.searchQuery, 5)
        val best = hits.firstOrNull { it.videoId != null }?.videoId
        if (best != null) videoIdCache[track.id] = best
        return best
    }

    fun invalidateStream(videoId: String) { streamCache.remove(videoId) }

    suspend fun resolveStream(videoId: String): ResolvedStream? {
        streamCache[videoId]?.let { if (it.expiresAt > System.currentTimeMillis() + 60_000) return it }
        val androidClient = mapOf(
            "clientName" to "ANDROID", "clientVersion" to "20.10.38", "osName" to "Android", "osVersion" to "14",
            "androidSdkVersion" to 34, "hl" to "pt", "gl" to "BR",
        )
        requestPlayerStream(videoId, androidClient, InnerTube.ANDROID_UA)?.let { streamCache[videoId] = it; return it }
        val iosClient = mapOf(
            "clientName" to "IOS", "clientVersion" to "21.02.3", "deviceMake" to "Apple", "deviceModel" to "iPhone16,2",
            "osName" to "iPhone", "osVersion" to "18.3.2.22D82", "hl" to "pt", "gl" to "BR",
        )
        requestPlayerStream(videoId, iosClient, InnerTube.IOS_UA)?.let { streamCache[videoId] = it; return it }
        return null
    }

    /**
     * Política igual à do iOS (27/11/2026): MP4 progressivo (itag 18) é o PRIMÁRIO — toca a faixa inteira e aceita
     * seek/reconexão em qualquer Range. O áudio puro (itag 140) responde 403 a qualquer Range depois de ~1 MB sem
     * PO token (testado com curl), então só é usado quando não há progressivo.
     */
    fun pickProgressive(playerJson: kotlinx.serialization.json.JsonElement): Triple<String, Int, Int>? {
        val sd = playerJson["streamingData"] ?: return null
        val combined = sd["formats"].objs()
        val adaptive = sd["adaptiveFormats"].objs()
        fun url(f: JsonObject) = f["url"].str()
        val v18 = combined.firstOrNull { it["itag"].int() == 18 && url(it) != null }
            ?: combined.firstOrNull { (it["mimeType"].str() ?: "").contains("mp4") && url(it) != null }
        if (v18 != null) return Triple(url(v18)!!, maxOf(96000, v18["bitrate"].int() ?: 128000), v18["itag"].int() ?: 18)
        val audio140 = adaptive.firstOrNull { it["itag"].int() == 140 && url(it) != null }
        if (audio140 != null) return Triple(url(audio140)!!, maxOf(96000, audio140["bitrate"].int() ?: 128000), 140)
        val anyAudio = adaptive.firstOrNull {
            val m = it["mimeType"].str() ?: ""
            m.startsWith("audio/mp4") && m.contains("mp4a.40.2") && url(it) != null
        } ?: adaptive.firstOrNull { (it["mimeType"].str() ?: "").startsWith("audio/mp4") && url(it) != null }
        if (anyAudio != null) return Triple(url(anyAudio)!!, anyAudio["bitrate"].int() ?: 128000, anyAudio["itag"].int() ?: 0)
        return null
    }

    /** Sonoridade da faixa (`playerConfig.audioConfig.loudnessDb`). Valor ausente ou absurdo → null (ganho 0 dB). */
    fun parseLoudnessDb(playerJson: kotlinx.serialization.json.JsonElement): Double? {
        val v = playerJson["playerConfig"]["audioConfig"]["loudnessDb"].dbl() ?: return null
        return v.takeIf { it.isFinite() && it > -60.0 && it < 60.0 }
    }

    private suspend fun requestPlayerStream(videoId: String, client: Map<String, Any>, userAgent: String): ResolvedStream? {
        val body = jsonObjectOf(
            "videoId" to videoId, "context" to mapOf("client" to client),
            "contentCheckOk" to true, "racyCheckOk" to true,
        )
        val json = DiscNet.postJson(
            "https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false", body, 8,
            mapOf("User-Agent" to userAgent),
        ) ?: return null
        val picked = pickProgressive(json) ?: return null
        return ResolvedStream(picked.first, mapOf("User-Agent" to userAgent), picked.second,
            System.currentTimeMillis() + 40 * 60_000L, picked.third, parseLoudnessDb(json))
    }

    // ---------------- Capa animada (Apple Music .m3u8) ----------------

    suspend fun fetchAnimatedArtwork(title: String, artist: String, album: String): String? {
        withContext(Dispatchers.IO) { loadAnimatedIfNeeded() }
        val key = Track.stableId(album.ifEmpty { title }, artist)
        animatedCache[key]?.let { return it.ifEmpty { null } }
        val term = DiscNet.enc(if (album.isEmpty()) "$title $artist" else "$album $artist")
        val search = DiscNet.json("https://itunes.apple.com/search?term=$term&entity=album&country=br&limit=1")
        val page = search["results"].objs().firstOrNull()?.get("collectionViewUrl").str()
        if (page == null) {
            animatedCache[key] = ""
            withContext(Dispatchers.IO) { saveAnimated() }
            return null
        }
        val html = DiscNet.text(page, 7, mapOf("User-Agent" to InnerTube.WEB_UA)) ?: return null
        val matches = Regex("""https://mvod\.itunes\.apple\.com/[^"'\\<>]+\.m3u8""").findAll(html).map { it.value }.toList()
        val best = matches.firstOrNull { it.contains("default.m3u8") } ?: matches.firstOrNull()
        animatedCache[key] = best ?: ""
        withContext(Dispatchers.IO) { saveAnimated() }
        return best
    }
}
