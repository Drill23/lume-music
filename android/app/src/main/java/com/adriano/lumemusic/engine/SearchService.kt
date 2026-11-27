package com.adriano.lumemusic.engine

import com.adriano.lumemusic.data.AlbumShowcase
import com.adriano.lumemusic.data.ArtistInfo
import com.adriano.lumemusic.data.LyricSearchHit
import com.adriano.lumemusic.data.RemotePlaylist
import com.adriano.lumemusic.data.newTrack
import kotlinx.serialization.json.JsonArray

/** Busca de artistas, álbuns, playlists (Deezer), sugestões ao vivo e busca por letra (LRCLIB). */
object SearchService {
    suspend fun suggestions(q: String): List<String> {
        val query = q.trim()
        if (query.length < 2) return emptyList()
        val root = DiscNet.json("https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&hl=pt&q=${DiscNet.enc(query)}") as? JsonArray
            ?: return emptyList()
        if (root.size < 2) return emptyList()
        val list = (root[1] as? JsonArray)?.mapNotNull { it.str() } ?: return emptyList()
        val seen = HashSet<String>()
        return list.filter { it.isNotEmpty() && seen.add(it.lowercase()) }.take(8)
    }

    suspend fun artists(q: String): List<ArtistInfo> {
        val query = q.trim()
        if (query.isEmpty()) return emptyList()
        val obj = DiscNet.json("https://api.deezer.com/search/artist?q=${DiscNet.enc(query)}&limit=12") ?: return emptyList()
        return obj["data"].objs().mapNotNull { d ->
            val id = d["id"].lng() ?: return@mapNotNull null
            val name = d["name"].str()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            var pic = d["picture_xl"].str() ?: d["picture_big"].str() ?: ""
            if (pic.contains("/images/artist//")) pic = ""
            ArtistInfo(id = "dz_$id", name = name, pictureURL = pic, deezerId = id, fans = d["nb_fan"].lng())
        }
    }

    suspend fun albums(q: String): List<AlbumShowcase> {
        val query = q.trim()
        if (query.isEmpty()) return emptyList()
        val obj = DiscNet.json("https://api.deezer.com/search/album?q=${DiscNet.enc(query)}&limit=16") ?: return emptyList()
        return obj["data"].objs().mapNotNull { d ->
            val id = d["id"].lng() ?: return@mapNotNull null
            val title = d["title"].str()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            var cover = d["cover_xl"].str() ?: d["cover_big"].str() ?: ""
            if (cover.contains("/cover//")) cover = ""
            val artist = d["artist"]["name"].str() ?: "Artista"
            val kind = when ((d["record_type"].str() ?: "").lowercase()) { "single" -> "Single"; "ep" -> "EP"; else -> "Álbum" }
            val date = d["release_date"].str()
            AlbumShowcase(id = "dzalb_$id", title = title, artist = artist, artworkURL = cover,
                year = (date ?: "").take(4), genre = "", releaseDate = date, kind = kind, deezerId = id)
        }
    }

    suspend fun playlists(q: String, limit: Int = 12): List<RemotePlaylist> {
        val query = q.trim()
        if (query.isEmpty()) return emptyList()
        val obj = DiscNet.json("https://api.deezer.com/search/playlist?q=${DiscNet.enc(query)}&limit=$limit") ?: return emptyList()
        return obj["data"].objs().mapNotNull { d ->
            val id = d["id"].lng() ?: return@mapNotNull null
            val title = d["title"].str()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val count = d["nb_tracks"].int() ?: 0
            if (count <= 0) return@mapNotNull null
            var cover = d["picture_xl"].str() ?: d["picture_big"].str() ?: d["picture_medium"].str() ?: ""
            if (cover.contains("/cover//")) cover = ""
            val creator = d["user"]["name"].str() ?: "Curadoria"
            RemotePlaylist(id, title, "$count músicas · $creator", cover, count, creator)
        }
    }

    suspend fun searchByLyrics(q: String): List<LyricSearchHit> {
        val query = q.trim()
        if (query.length < 3) return emptyList()
        val arr = DiscNet.json("https://lrclib.net/api/search?q=${DiscNet.enc(query)}", 6, retries = 1) as? JsonArray
            ?: return emptyList()
        val seen = HashSet<String>()
        val hits = mutableListOf<LyricSearchHit>()
        for (item in arr.objs()) {
            val trackName = item["trackName"].str() ?: item["name"].str() ?: continue
            val artistName = item["artistName"].str() ?: continue
            if (trackName.isEmpty() || artistName.isEmpty()) continue
            val key = "${DiscText.normalize(trackName)}|${DiscText.normalize(artistName)}"
            if (!seen.add(key)) continue
            val snippet = extractSnippet(query, item["plainLyrics"].str() ?: "", item["syncedLyrics"].str() ?: "")
            val tr = newTrack(title = trackName, artist = artistName, album = item["albumName"].str() ?: "",
                duration = item["duration"].dbl() ?: 0.0, sourceService = "Letras")
            hits.add(LyricSearchHit(tr, snippet))
            if (hits.size >= 16) break
        }
        return hits
    }

    private val reTimestamp = Regex("""\[\d{1,2}:\d{2}(?:\.\d{1,3})?]""")

    fun extractSnippet(query: String, plain: String, synced: String): String {
        val rawText = if (plain.isNotEmpty()) plain else synced.replace(reTimestamp, "")
        val lines = rawText.lines().map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.isEmpty()) return ""
        val tokens = DiscText.normalize(query).split(" ").filter { it.length >= 2 }
        val idx = lines.indexOfFirst { line ->
            val nl = DiscText.normalize(line)
            tokens.any { nl.contains(it) }
        }
        if (idx >= 0) return lines.subList(idx, minOf(lines.size, idx + 2)).joinToString(" / ")
        return lines.take(2).joinToString(" / ")
    }
}
