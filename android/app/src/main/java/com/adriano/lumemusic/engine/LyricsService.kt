package com.adriano.lumemusic.engine

import com.adriano.lumemusic.data.LyricLine
import com.adriano.lumemusic.data.LyricsBundle
import com.adriano.lumemusic.data.Track
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/** Letras de várias fontes (LRCLIB, NetEase, YouTube Music, Letras.mus.br, Lyrics.ovh) com tradução PT-BR e cache. */
object LyricsService {
    private val memCache = ConcurrentHashMap<String, LyricsBundle>()
    private val negCache = ConcurrentHashMap<String, Long>()
    private val inflight = HashMap<String, CompletableDeferred<LyricsBundle?>>()
    private val lock = Mutex()

    private val cacheDir: File
        get() = File(DiscNet.cacheDir, "LumeMusicLyrics").also { it.mkdirs() }

    private fun diskFile(key: String) = File(cacheDir, "$key.json")

    fun forgetMiss(track: Track) { negCache.remove(Track.stableId(track.title, track.artist)) }

    suspend fun fetchLyrics(track: Track): LyricsBundle? {
        val key = Track.stableId(track.title, track.artist)
        memCache[key]?.let { return it }
        val fromDisk = withContext(Dispatchers.IO) {
            try {
                val f = diskFile(key)
                if (f.exists()) LumeJson.decodeFromString(LyricsBundle.serializer(), f.readText()) else null
            } catch (_: Exception) { null }
        }
        if (fromDisk != null) { memCache[key] = fromDisk; return fromDisk }
        negCache[key]?.let { if (System.currentTimeMillis() - it < 24 * 3600_000L) return null }

        var mine: CompletableDeferred<LyricsBundle?>? = null
        var wait: CompletableDeferred<LyricsBundle?>? = null
        lock.withLock {
            val running = inflight[key]
            if (running != null) wait = running else { mine = CompletableDeferred(); inflight[key] = mine!! }
        }
        wait?.let { return it.await() }
        val result = try { search(track, key) } catch (_: Exception) { null }
        lock.withLock { inflight.remove(key) }
        if (result != null) save(result) else negCache[key] = System.currentTimeMillis()
        mine?.complete(result)
        return result
    }

    private suspend fun save(bundle: LyricsBundle) {
        memCache[bundle.trackKey] = bundle
        withContext(Dispatchers.IO) {
            try { diskFile(bundle.trackKey).writeText(LumeJson.encodeToString(LyricsBundle.serializer(), bundle)) } catch (_: Exception) {}
        }
    }

    // ---------------- Tradução ----------------

    suspend fun translateToPortuguese(bundle: LyricsBundle): LyricsBundle {
        if (bundle.translatedToPT) return bundle
        val lines = bundle.lines.toMutableList()
        val nonEmpty = lines.indices.filter { lines[it].text.isNotBlank() }
        if (nonEmpty.isEmpty()) return bundle
        var i = 0
        while (i < nonEmpty.size) {
            val batchIdx = mutableListOf<Int>()
            val batchText = mutableListOf<String>()
            var chars = 0
            while (i < nonEmpty.size) {
                val idx = nonEmpty[i]
                val t = lines[idx].text.replace("\n", " ")
                if (batchIdx.isNotEmpty() && chars + t.length + 2 > 1400) break
                batchIdx.add(idx); batchText.add(t); chars += t.length + 2; i++
            }
            val translated = translateChunk(batchText.joinToString("\n"))
            if (translated != null) {
                val out = translated.split("\n")
                for ((pos, lineIdx) in batchIdx.withIndex()) {
                    if (pos >= out.size) break
                    val tr = out[pos].trim()
                    if (tr.isNotEmpty() && tr.lowercase() != lines[lineIdx].text.lowercase()) {
                        lines[lineIdx] = lines[lineIdx].copy(translated = tr)
                    }
                }
            }
        }
        val updated = bundle.copy(lines = lines, translatedToPT = true)
        save(updated)
        return updated
    }

    private suspend fun translateChunk(text: String): String? {
        val url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=pt&dt=t&q=${DiscNet.enc(text)}"
        val arr = DiscNet.json(url, headers = mapOf("User-Agent" to "Mozilla/5.0")) as? JsonArray ?: return null
        val segments = arr.firstOrNull() as? JsonArray ?: return null
        val sb = StringBuilder()
        for (seg in segments) (seg as? JsonArray)?.firstOrNull().str()?.let { sb.append(it) }
        return sb.toString().ifEmpty { null }
    }

    // ---------------- Busca ----------------

    private data class Cand(val bundle: LyricsBundle, val duration: Double?, val score: Double)

    private suspend fun search(track: Track, key: String): LyricsBundle? = coroutineScope {
        val jobs = mutableListOf<kotlinx.coroutines.Deferred<List<Cand>>>()
        for (url in lrclibGetURLs(track)) jobs.add(async { lrclibGet(url, key, track) })
        for (url in lrclibSearchURLs(track)) jobs.add(async { lrclibSearch(url, key, track) })
        jobs.add(async { neteaseLyrics(track, key) })
        val stage1 = jobs.awaitAll().flatten()
        stage1.filter { it.bundle.synced }.maxByOrNull { it.score }?.let { return@coroutineScope it.bundle }
        val lrclibPlain = stage1.filter { !it.bundle.synced }.maxByOrNull { it.score }

        val s2 = listOf(
            async { youtubeMusicLyrics(track, key) },
            async { letrasMusBr(track, key) },
            async { lyricsOvh(track, key) },
        ).awaitAll()
        s2.firstOrNull { it != null }?.bundle ?: lrclibPlain?.bundle
    }

    // ---------------- LRCLIB ----------------

    private fun enc(q: List<Pair<String, String>>) = q.joinToString("&") { "${DiscNet.enc(it.first)}=${DiscNet.enc(it.second)}" }

    fun lrclibGetURLs(track: Track): List<String> {
        val title = cleanTitle(track.title)
        val fullArtist = stripTopic(track.artist)
        val firstArtist = cleanArtist(track.artist)
        val dur = if (track.duration > 10) Math.round(track.duration).toString() else null
        val variants = mutableListOf<List<Pair<String, String>>>()
        fun v(t: String, a: String, album: Boolean, duration: Boolean) {
            val q = mutableListOf("track_name" to t, "artist_name" to a)
            if (album && track.album.isNotEmpty()) q.add("album_name" to track.album)
            if (duration && dur != null) q.add("duration" to dur)
            variants.add(q)
        }
        v(title, fullArtist, album = true, duration = true)
        v(title, firstArtist, album = false, duration = true)
        v(title, fullArtist, album = false, duration = false)
        v(title, firstArtist, album = false, duration = false)
        return variants.map { "https://lrclib.net/api/get?${enc(it)}" }.distinct()
    }

    fun lrclibSearchURLs(track: Track): List<String> {
        val title = cleanTitle(track.title)
        val firstArtist = cleanArtist(track.artist)
        return listOf(
            "https://lrclib.net/api/search?${enc(listOf("track_name" to title, "artist_name" to firstArtist))}",
            "https://lrclib.net/api/search?${enc(listOf("q" to "$title $firstArtist"))}",
        )
    }

    private suspend fun lrclibRequest(url: String): JsonElement? =
        DiscNet.json(url, 6, mapOf("User-Agent" to "LumeMusic/2.0 (https://lume.app)"))

    private suspend fun lrclibGet(url: String, key: String, track: Track): List<Cand> {
        val obj = lrclibRequest(url) as? JsonObject ?: return emptyList()
        return lrclibCands(obj, key, track, verify = false, bonus = 10.0)
    }

    private suspend fun lrclibSearch(url: String, key: String, track: Track): List<Cand> {
        val list = lrclibRequest(url) as? JsonArray ?: return emptyList()
        return list.objs().take(15).flatMap { lrclibCands(it, key, track, verify = true, bonus = 0.0) }
    }

    private fun durationOK(track: Track, candidate: Double?): Boolean {
        if (track.duration <= 10 || candidate == null || candidate <= 10) return true
        return Math.abs(track.duration - candidate) <= 15
    }

    private fun durationPenalty(track: Track, candidate: Double?): Double {
        if (track.duration <= 10 || candidate == null || candidate <= 10) return 0.0
        return minOf(Math.abs(track.duration - candidate), 30.0)
    }

    private fun lrclibCands(obj: JsonObject, key: String, track: Track, verify: Boolean, bonus: Double): List<Cand> {
        if (obj["instrumental"].bool() == true) return emptyList()
        val duration = obj["duration"].dbl()
        if (!durationOK(track, duration)) return emptyList()
        if (verify) {
            val name = obj["trackName"].str() ?: obj["name"].str() ?: ""
            val artist = obj["artistName"].str() ?: ""
            if (!DiscText.titleLooselyMatches(name, track.title) && !DiscText.titleLooselyMatches(name, cleanTitle(track.title))) return emptyList()
            if (track.artist.isNotEmpty() && !DiscText.artistMatches(artist, stripTopic(track.artist))) return emptyList()
        }
        val pen = durationPenalty(track, duration)
        val out = mutableListOf<Cand>()
        val synced = obj["syncedLyrics"].str()
        if (synced != null && synced.isNotBlank()) {
            val lines = parseLRC(synced)
            if (usable(lines.map { it.text })) {
                out.add(Cand(LyricsBundle(key, true, lines, "LRCLIB · Sincronizada", false), duration, 100 + bonus - pen))
            }
        }
        val plain = obj["plainLyrics"].str()
        if (plain != null) plainLines(plain)?.let { lines ->
            out.add(Cand(LyricsBundle(key, false, lines, "LRCLIB", false), duration, 50 + bonus - pen))
        }
        return out
    }

    // ---------------- NetEase ----------------

    private val reCredit = Regex(
        """^(作词|作曲|编曲|制作人?|混音|母带|录音|和声|吉他|贝斯|鼓|监制|企划|Lyrics?|Music|Composer|Producer|Arranged?|Written|Mix(ed)?|Master(ed)?)\b.{0,12}[:：]""",
        RegexOption.IGNORE_CASE,
    )

    private suspend fun neteaseLyrics(track: Track, key: String): List<Cand> {
        val title = cleanTitle(track.title)
        val artist = cleanArtist(track.artist)
        val q = DiscText.fold("$title $artist")
        val headers = mapOf("Referer" to "https://music.163.com/", "Cookie" to "appver=2.0.2")
        val obj = DiscNet.json("https://music.163.com/api/search/get?s=${DiscNet.enc(q)}&type=1&limit=6", 6, headers)
        val songs = obj["result"]["songs"].objs()
        var chosenId: Long? = null
        var chosenDur: Double? = null
        for (s in songs) {
            val id = s["id"].lng() ?: continue
            val name = s["name"].str() ?: continue
            val artists = s["artists"].objs().mapNotNull { it["name"].str() }
            val dur = s["duration"].dbl()?.div(1000)
            if (!DiscText.titleLooselyMatches(name, title) && !DiscText.titleLooselyMatches(name, track.title)) continue
            if (track.artist.isNotEmpty() && artists.none { DiscText.artistMatches(it, stripTopic(track.artist)) }) continue
            if (!durationOK(track, dur)) continue
            chosenId = id; chosenDur = dur
            break
        }
        val id = chosenId ?: return emptyList()
        val lobj = DiscNet.json("https://music.163.com/api/song/lyric?id=$id&lv=1&kv=1&tv=-1", 6, headers) ?: return emptyList()
        val lrc = lobj["lrc"]["lyric"].str() ?: return emptyList()
        var lines = parseLRC(lrc).filter { !reCredit.containsMatchIn(it.text) }
        lines = lines.mapIndexed { i, l -> LyricLine(i, l.time, l.text, null) }
        if (!usable(lines.map { it.text })) return emptyList()
        return listOf(Cand(LyricsBundle(key, true, lines, "NetEase · Sincronizada", false), chosenDur,
            80 - durationPenalty(track, chosenDur)))
    }

    // ---------------- YouTube Music ----------------

    private suspend fun youtubeMusicLyrics(track: Track, key: String): Cand? {
        var vid = track.videoId
        if (vid.isNullOrEmpty()) vid = ytmFindVideoId(track)
        val videoId = vid ?: return null
        val next = DiscNet.postJson("https://music.youtube.com/youtubei/v1/next?prettyPrint=false",
            jsonObjectOf("context" to InnerTube.webContext, "videoId" to videoId), 6, InnerTube.ytHeaders) ?: return null
        var browseId: String? = null
        next.walk { d ->
            val b = d["browseId"].str()
            if (b != null && b.startsWith("MPLY")) { browseId = b; true } else false
        }
        val bid = browseId ?: return null
        val page = DiscNet.postJson("https://music.youtube.com/youtubei/v1/browse?prettyPrint=false",
            jsonObjectOf("context" to InnerTube.webContext, "browseId" to bid), 6, InnerTube.ytHeaders) ?: return null
        var text: String? = null
        page.walk { d ->
            val shelf = d["musicDescriptionShelfRenderer"].obj()
            if (shelf != null) {
                text = InnerTube.runsText(shelf["description"]); true
            } else false
        }
        val lines = plainLines(text ?: return null) ?: return null
        return Cand(LyricsBundle(key, false, lines, "YouTube Music", false), null, 40.0)
    }

    private suspend fun ytmFindVideoId(track: Track): String? {
        val body = jsonObjectOf(
            "context" to InnerTube.webContext,
            "query" to "${cleanTitle(track.title)} ${cleanArtist(track.artist)}",
            "params" to "EgWKAQIIAWoKEAkQBRAKEAMQBA==",
        )
        val obj = DiscNet.postJson("https://music.youtube.com/youtubei/v1/search?prettyPrint=false", body, 6, InnerTube.ytHeaders) ?: return null
        var found: String? = null
        obj.walk { d ->
            val r = d["musicResponsiveListItemRenderer"].obj()
            if (r != null) {
                val cols = r["flexColumns"].objs()
                val c0 = cols.firstOrNull()?.let { InnerTube.runsText(it["musicResponsiveListItemFlexColumnRenderer"]["text"]) } ?: ""
                val vid = r["playlistItemData"]["videoId"].str()
                if (vid != null && (DiscText.titleLooselyMatches(c0, track.title) || DiscText.titleLooselyMatches(c0, cleanTitle(track.title)))) found = vid
                true
            } else false
        }
        return found
    }

    // ---------------- Letras.mus.br ----------------

    private suspend fun letrasMusBr(track: Track, key: String): Cand? {
        val title = cleanTitle(track.title)
        val artist = cleanArtist(track.artist)
        val q = DiscText.fold("$title $artist")
        val raw = DiscNet.text("https://solr.sscdn.co/letras/m1/?q=${DiscNet.enc(q)}&wt=json&rows=6", 5) ?: return null
        val open = raw.indexOf('(')
        val close = raw.lastIndexOf(')')
        if (open < 0 || close <= open) return null
        val obj = DiscNet.parse(raw.substring(open + 1, close)) ?: return null
        val docs = obj["response"]["docs"].objs()
        val doc = docs.firstOrNull { d ->
            val t = d["txt"].str(); val a = d["art"].str()
            t != null && a != null && d["url"].str() != null && d["dns"].str() != null &&
                DiscText.titleLooselyMatches(t, title) && DiscText.artistMatches(a, stripTopic(track.artist))
        } ?: return null
        val dns = doc["dns"].str() ?: return null
        val slug = doc["url"].str() ?: return null
        val html = DiscNet.text("https://www.letras.mus.br/$dns/$slug/", 6,
            mapOf("Accept" to "text/html", "Accept-Language" to "pt-BR,pt;q=0.9")) ?: return null
        var m = html.indexOf("lyric-original")
        if (m < 0) m = html.indexOf("cnt-letra")
        if (m < 0) return null
        val rest = html.substring(m)
        val start = rest.indexOf('>')
        if (start < 0) return null
        val body = rest.substring(start + 1)
        val end = body.indexOf("</div>").let { if (it < 0) body.length else it }
        var chunk = body.substring(0, end)
        chunk = chunk.replace(Regex("""<br\s*/?>"""), "\n").replace(Regex("""</p>"""), "\n\n").replace(Regex("""<[^>]+>"""), "")
        for ((k, v) in listOf("&amp;" to "&", "&quot;" to "\"", "&#39;" to "'", "&lt;" to "<", "&gt;" to ">", "&nbsp;" to " ")) chunk = chunk.replace(k, v)
        val lines = plainLines(chunk) ?: return null
        return Cand(LyricsBundle(key, false, lines, "Letras.mus.br", false), null, 45.0)
    }

    // ---------------- Lyrics.ovh ----------------

    private suspend fun lyricsOvh(track: Track, key: String): Cand? {
        val title = cleanTitle(track.title)
        val artists = mutableListOf(cleanArtist(track.artist))
        val full = stripTopic(track.artist)
        if (full != artists[0]) artists.add(full)
        for (a in artists) {
            val obj = DiscNet.json("https://api.lyrics.ovh/v1/${DiscNet.enc(a)}/${DiscNet.enc(title)}", 6) ?: continue
            var text = obj["lyrics"].str() ?: continue
            if (text.lowercase().startsWith("paroles de la chanson")) {
                val nl = text.indexOf('\n')
                if (nl >= 0) text = text.substring(nl + 1)
            }
            text = text.replace("\r\n", "\n")
            plainLines(text)?.let { return Cand(LyricsBundle(key, false, it, "Lyrics.ovh", false), null, 30.0) }
        }
        return null
    }

    // ---------------- Validação / parsing ----------------

    fun usable(texts: List<String>): Boolean {
        val real = texts.map { it.trim() }.filter { it.isNotEmpty() && it != "♪" }
        if (real.size < 3) return false
        if (real.size <= 6) {
            val joined = real.joinToString(" ").lowercase()
            if (joined.contains("instrumental") || joined.contains("纯音乐") || joined.contains("no lyrics")) return false
        }
        return true
    }

    fun plainLines(text: String): List<LyricLine>? {
        val raw = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
            .filter { !(it.startsWith("[") && it.endsWith("]")) }
        if (!usable(raw)) return null
        return raw.mapIndexed { i, s -> LyricLine(i, i * 3.5, s, null) }
    }

    private val reLrcStamp = Regex("""\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?]""")

    fun parseLRC(lrc: String): List<LyricLine> {
        val temp = mutableListOf<Pair<Double, String>>()
        for (rawLine in lrc.lines()) {
            val matches = reLrcStamp.findAll(rawLine).toList()
            if (matches.isEmpty()) continue
            val text = rawLine.substring(matches.last().range.last + 1).trim()
            for (m in matches) {
                val min = m.groupValues[1].toDoubleOrNull() ?: 0.0
                val sec = m.groupValues[2].toDoubleOrNull() ?: 0.0
                var frac = 0.0
                val f = m.groups[3]?.value
                if (f != null) frac = (f.toDoubleOrNull() ?: 0.0) / Math.pow(10.0, f.length.toDouble())
                temp.add((min * 60.0 + sec + frac) to text.ifEmpty { "♪" })
            }
        }
        temp.sortBy { it.first }
        return temp.mapIndexed { i, p -> LyricLine(i, p.first, p.second, null) }
    }

    private fun stripTopic(s: String) = s.replace(" - Topic", "", ignoreCase = true).trim()

    private val titlePatterns: List<Regex> by lazy {
        val kw = """(official|oficial|audio|áudio|video|vídeo|lyrics?|letra|clipe|clip|ao vivo|live|remaster(ed)?|visuali[sz]er|feat\.?|ft\.?|featuring|part\.?|hd|4k|explicit)"""
        val o = RegexOption.IGNORE_CASE
        listOf(
            Regex("""\s*\([^)]*\b$kw\b[^)]*\)""", o),
            Regex("""\s*\[[^\]]*]""", o),
            Regex("""\s+[-–—]\s*(ao vivo|live|remaster(ed)?|official|oficial|topic|\d{4} remaster)\b.*$""", o),
            Regex("""\s*\|.*$""", o),
            Regex("""\s+(feat\.?|ft\.?|featuring)\s+.*$""", o),
            Regex("""\s+Official\s+(Music\s+)?(Video|Audio|Lyric Video|Clipe)\s*$""", o),
            Regex("""\s+Remaster(ed)?(\s+\d{4})?\s*$""", o),
            Regex("""\s*-\s*Topic$""", o),
        )
    }

    fun cleanTitle(s: String): String {
        var out = s
        for (p in titlePatterns) out = out.replace(p, "")
        out = out.trim()
        return out.ifEmpty { s.trim() }
    }

    private val reFeatTail = Regex("""\s+(feat\.?|ft\.?|featuring)\s+.*$""", RegexOption.IGNORE_CASE)

    fun cleanArtist(s: String): String {
        val base = s.replace(" - Topic", "", ignoreCase = true).replace(reFeatTail, "")
        return base.split(',', '&').firstOrNull()?.trim() ?: s
    }
}
