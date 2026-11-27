package com.adriano.lumemusic.engine

import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.data.newTrack
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Parsers puros do InnerTube (YouTube Music). Testáveis na JVM. */
object InnerTube {
    const val WEB_UA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    const val ANDROID_UA = "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"
    const val IOS_UA = "com.google.ios.youtube/21.02.3 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
    const val SONGS_FILTER = "EgWKAQIIAWoMEAMQBBAJEAoQBRAV"

    val webContext: JsonObject = jsonObjectOf(
        "client" to mapOf(
            "clientName" to "WEB_REMIX", "clientVersion" to "1.20250101.01.00", "hl" to "pt", "gl" to "BR",
        ),
    )
    val ytHeaders = mapOf("Origin" to "https://music.youtube.com", "Referer" to "https://music.youtube.com/")

    // ---- texto em "runs" ----

    fun runsArray(any: JsonElement?): List<String> {
        val d = any as? JsonObject ?: return emptyList()
        val runs = d["runs"]
        if (runs is JsonArray) return runs.mapNotNull { (it as? JsonObject)?.get("text").str() }
        d["simpleText"].str()?.let { return listOf(it) }
        return emptyList()
    }

    fun runsText(any: JsonElement?): String = runsArray(any).joinToString("")

    private fun columnInner(col: JsonElement?): JsonObject? =
        (col["musicResponsiveListItemFlexColumnRenderer"] ?: col["musicResponsiveListItemFixedColumnRenderer"]).obj()

    fun textOfColumn(col: JsonElement?): String = runsText(columnInner(col)["text"])
    fun runsOfColumn(col: JsonElement?): List<String> =
        runsArray((col["musicResponsiveListItemFlexColumnRenderer"].obj())["text"])

    fun parseClock(s: String): Double? {
        val parts = s.trim().split(":").map { it.trim().toIntOrNull() ?: return null }
        return when (parts.size) {
            2 -> (parts[0] * 60 + parts[1]).toDouble()
            3 -> (parts[0] * 3600 + parts[1] * 60 + parts[2]).toDouble()
            else -> null
        }
    }

    private fun findStringKey(key: String, node: JsonElement): String? {
        when (node) {
            is JsonObject -> {
                (node[key] as? JsonPrimitive)?.takeIf { it.isString && it.content.isNotEmpty() }?.let { return it.content }
                for (v in node.values) findStringKey(key, v)?.let { return it }
            }
            is JsonArray -> for (v in node) findStringKey(key, v)?.let { return it }
            else -> {}
        }
        return null
    }

    fun bestThumbnail(node: JsonElement): String {
        var bestUrl = ""
        var bestW = -1
        fun go(n: JsonElement) {
            when (n) {
                is JsonObject -> {
                    val thumbs = n["thumbnails"]
                    if (thumbs is JsonArray) for (t in thumbs) {
                        val u = t["url"].str() ?: continue
                        val w = t["width"].int() ?: 0
                        if (w >= bestW) { bestW = w; bestUrl = u }
                    }
                    for (v in n.values) go(v)
                }
                is JsonArray -> for (v in n) go(v)
                else -> {}
            }
        }
        go(node)
        return bestUrl
    }

    private val reGoogleWH = Regex("""=w\d+-h\d+[^&]*""")
    private val reGoogleS = Regex("""=s\d+[^&]*""")

    fun upscaleGoogleThumb(url: String): String {
        reGoogleWH.find(url)?.let { return url.replaceRange(it.range, "=w1200-h1200-l95-rj") }
        reGoogleS.find(url)?.let { return url.replaceRange(it.range, "=s1200") }
        return url
    }

    // ---- listas ----

    fun extractResponsiveListTracks(root: JsonElement, source: String): List<Track> {
        val out = mutableListOf<Track>()
        val seen = HashSet<String>()
        fun go(n: JsonElement) {
            when (n) {
                is JsonObject -> {
                    val r = n["musicResponsiveListItemRenderer"].obj()
                    if (r != null) {
                        val tr = parseResponsiveItem(r, source)
                        val vid = tr?.videoId
                        if (tr != null && vid != null && seen.add(vid)) {
                            out.add(tr)
                            return
                        }
                    }
                    for (v in n.values) go(v)
                }
                is JsonArray -> for (v in n) go(v)
                else -> {}
            }
        }
        go(root)
        return out
    }

    private val noiseWords = listOf("música", "song", "vídeo", "video")

    fun parseResponsiveItem(r: JsonObject, source: String): Track? {
        var vid = r["playlistItemData"]["videoId"].str()
        if (vid == null) vid = findStringKey("videoId", r)
        val videoId = vid?.takeIf { it.length == 11 } ?: return null

        val cols = r["flexColumns"].objs()
        val title = textOfColumn(cols.firstOrNull())
        if (title.isEmpty()) return null

        val subRuns = runsOfColumn(cols.getOrNull(1))
        val clean = subRuns.map { it.trim() }.filter { p ->
            p.isNotEmpty() && p != "•" && p != "·" && noiseWords.none { p.lowercase().startsWith(it) }
        }
        var artist = ""
        var album = ""
        var duration = 0.0
        for (part in clean) {
            val d = parseClock(part)
            val low = part.lowercase()
            if (d != null) duration = d
            else if (low.contains("reproduç") || low.contains("plays") || low.contains("visualizaç")) continue
            else if (artist.isEmpty()) artist = part
            else if (album.isEmpty()) album = part
        }
        if (duration == 0.0) {
            for (fc in r["fixedColumns"].objs()) {
                parseClock(textOfColumn(fc))?.let { duration = it; break }
            }
        }
        var thumb = bestThumbnail(r)
        if (thumb.contains("googleusercontent.com")) thumb = upscaleGoogleThumb(thumb)
        if (thumb.isEmpty()) thumb = "https://i.ytimg.com/vi/$videoId/maxresdefault.jpg"

        return newTrack(
            id = videoId, videoId = videoId, title = title,
            artist = artist.ifEmpty { "Artista" }, album = album, duration = duration,
            artworkURL = thumb, sourceService = source,
        )
    }

    fun extractPanelVideoTracks(root: JsonElement): List<Track> {
        val out = mutableListOf<Track>()
        val seen = HashSet<String>()
        fun go(n: JsonElement) {
            when (n) {
                is JsonObject -> {
                    val p = n["playlistPanelVideoRenderer"].obj()
                    val vid = p["videoId"].str()
                    if (p != null && vid != null && vid.length == 11 && seen.add(vid)) {
                        val title = runsText(p["title"])
                        val byRuns = runsArray(p["longBylineText"] ?: p["shortBylineText"])
                            .map { it.trim() }.filter { it != "•" && it != "·" && it.isNotEmpty() }
                        val artist = byRuns.firstOrNull() ?: "Artista"
                        val album = byRuns.getOrNull(1) ?: ""
                        val dur = parseClock(runsText(p["lengthText"])) ?: 0.0
                        var thumb = bestThumbnail(p)
                        if (thumb.contains("googleusercontent.com")) thumb = upscaleGoogleThumb(thumb)
                        if (title.isNotEmpty()) {
                            out.add(newTrack(id = vid, videoId = vid, title = title, artist = artist, album = album,
                                duration = dur, artworkURL = thumb, sourceService = "Rádio"))
                        }
                        return
                    }
                    for (v in n.values) go(v)
                }
                is JsonArray -> for (v in n) go(v)
                else -> {}
            }
        }
        go(root)
        return out
    }

    fun extractFirstTitle(node: JsonElement): String? {
        when (node) {
            is JsonObject -> {
                val hdr = node["musicEditablePlaylistDetailHeaderRenderer"] ?: node["musicDetailHeaderRenderer"]
                    ?: node["musicResponsiveHeaderRenderer"]
                if (hdr is JsonObject) {
                    // musicEditablePlaylistDetailHeaderRenderer aninha o header real
                    val t = runsText(hdr["title"])
                    if (t.isNotEmpty()) return t
                    val inner = hdr["header"].obj()
                    inner?.values?.forEach { v ->
                        val tt = runsText(v["title"])
                        if (tt.isNotEmpty()) return tt
                    }
                }
                for (v in node.values) extractFirstTitle(v)?.let { return it }
            }
            is JsonArray -> for (v in node) extractFirstTitle(v)?.let { return it }
            else -> {}
        }
        return null
    }

    /** Faixa de uma lista de reprodução/charts do YTM (título, artista na 2ª coluna). */
    fun ytmChartTrack(r: JsonObject): Track? {
        val videoId = r["playlistItemData"]["videoId"].str() ?: return null
        val cols = r["flexColumns"].objs()
        if (cols.size < 2) return null
        val title = textOfColumn(cols[0])
        val artist = textOfColumn(cols[1])
        if (title.isEmpty()) return null
        var thumb = ""
        val th = r["thumbnail"]["musicThumbnailRenderer"]["thumbnail"]["thumbnails"].objs()
        if (th.isNotEmpty()) thumb = th.last()["url"].str() ?: ""
        return newTrack(videoId = videoId, title = title, artist = artist, artworkURL = thumb, sourceService = "YouTube Music")
    }
}
