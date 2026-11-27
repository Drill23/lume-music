package com.adriano.lumemusic.engine

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer

/** Resolve capas de álbum em alta e fotos de artistas (iTunes + Deezer), com cache em disco. */
object ArtworkResolver {
    @Serializable
    private data class Entry(val url: String? = null, val ts: Long)

    private val mapSer = MapSerializer(String.serializer(), Entry.serializer())
    private val store = HashMap<String, Entry>()
    private var loaded = false
    private val lock = Mutex()
    private val inflight = HashMap<String, CompletableDeferred<String?>>()
    private const val NEGATIVE_TTL = 3L * 24 * 3600 * 1000
    private const val POSITIVE_TTL = 60L * 24 * 3600 * 1000

    private val file get() = DiscNet.caches("lume_artwork_cache.json")

    private val reDims = Regex("""/(\d{2,4})x(\d{2,4})(bb|cc|-|\.)""")
    private val reGoogle = Regex("""[=\-]([ws])(\d{2,4})""")

    /** true se url vazia, thumbnail de vídeo (ytimg) ou imagem pequena (<500px detectável pela URL). */
    fun needsUpgrade(url: String): Boolean {
        val u = url.trim()
        if (u.isEmpty()) return true
        val lower = u.lowercase()
        if (lower.contains("ytimg.com") || lower.contains("img.youtube.com")) return true
        reDims.find(lower)?.let { m ->
            val nums = Regex("""\d+""").findAll(m.value).map { it.value.toInt() }.toList()
            return (nums.minOrNull() ?: 9999) < 500
        }
        reGoogle.find(lower)?.let { m ->
            val n = Regex("""\d+""").find(m.value)?.value?.toIntOrNull() ?: 9999
            return n < 500
        }
        return false
    }

    suspend fun albumCover(title: String, artist: String, album: String): String? {
        val t = DiscText.searchTitle(title)
        val a = DiscText.searchArtist(artist)
        if (t.isEmpty()) return null
        val key = "cover|${DiscText.normalize(t)}|${DiscText.normalize(a)}"
        return cached(key) { lookupCover(t, a, album) }
    }

    suspend fun artistPicture(name: String): String? {
        val n = DiscText.searchArtist(name)
        if (n.isEmpty()) return null
        return cached("artist|${DiscText.normalize(n)}") { lookupArtist(n) }
    }

    private fun loadIfNeeded() {
        if (loaded) return
        loaded = true
        try {
            if (file.exists()) store.putAll(LumeJson.decodeFromString(mapSer, file.readText()))
        } catch (_: Exception) {}
    }

    private fun persist() {
        try { file.writeText(LumeJson.encodeToString(mapSer, HashMap(store))) } catch (_: Exception) {}
    }

    private suspend fun cached(key: String, work: suspend () -> String?): String? {
        val now = System.currentTimeMillis()
        var mine: CompletableDeferred<String?>? = null
        var wait: CompletableDeferred<String?>? = null
        lock.withLock {
            loadIfNeeded()
            store[key]?.let { e ->
                if (e.url != null && now - e.ts < POSITIVE_TTL) return e.url
                if (e.url == null && now - e.ts < NEGATIVE_TTL) return null
            }
            val running = inflight[key]
            if (running != null) wait = running else { mine = CompletableDeferred(); inflight[key] = mine!! }
        }
        wait?.let { return it.await() }
        val result = try { work() } catch (_: Exception) { null }
        lock.withLock {
            inflight.remove(key)
            store[key] = Entry(result, now)
        }
        withContext(Dispatchers.IO) { lock.withLock { persist() } }
        mine?.complete(result)
        return result
    }

    private suspend fun lookupCover(title: String, artist: String, album: String): String? {
        // 1. iTunes
        val term = DiscNet.enc("$title $artist")
        val it = DiscNet.json("https://itunes.apple.com/search?term=$term&entity=song&country=br&limit=8")
        val candidates = it["results"].objs().filter { r ->
            val tn = r["trackName"].str() ?: return@filter false
            val an = r["artistName"].str() ?: return@filter false
            DiscText.artistMatches(an, artist) && DiscText.titleLooselyMatches(tn, title)
        }
        val best = candidates.firstOrNull { r ->
            album.isNotEmpty() && DiscText.normalize(r["collectionName"].str() ?: "") == DiscText.normalize(album)
        } ?: candidates.firstOrNull { DiscText.titleMatches(it["trackName"].str() ?: "", title) } ?: candidates.firstOrNull()
        best?.get("artworkUrl100").str()?.let { return DiscText.upscaleApple(it) }
        // 2. Deezer
        val queries = listOf("artist:\"$artist\" track:\"$title\"", "$title $artist")
        for (q in queries) {
            val obj = DiscNet.json("https://api.deezer.com/search?q=${DiscNet.enc(q)}&limit=5")
            for (r in obj["data"].objs()) {
                val tn = r["title"].str() ?: continue
                val an = r["artist"]["name"].str() ?: continue
                if (!DiscText.artistMatches(an, artist) || !DiscText.titleLooselyMatches(tn, title)) continue
                val xl = r["album"]["cover_xl"].str() ?: continue
                if (xl.isNotEmpty() && !xl.contains("/cover//")) return xl
            }
        }
        return null
    }

    private suspend fun lookupArtist(name: String): String? {
        val obj = DiscNet.json("https://api.deezer.com/search/artist?q=${DiscNet.enc(name)}&limit=5") ?: return null
        val target = DiscText.normalize(name)
        for (r in obj["data"].objs()) {
            val n = r["name"].str() ?: continue
            if (DiscText.normalize(n) != target) continue
            val pic = r["picture_xl"].str() ?: continue
            if (pic.isNotEmpty() && !pic.contains("/images/artist//")) return pic
        }
        return null
    }
}
