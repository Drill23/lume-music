package com.adriano.lumemusic.engine

import android.content.Context
import android.provider.MediaStore
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.data.newTrack
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import okhttp3.Request
import java.net.URI

class ImportException(message: String) : Exception(message)

/**
 * Importador completo (paridade total com ImportService.swift do iOS):
 * - Músicas locais do aparelho (1 toque, até 1000 faixas)
 * - Spotify (playlists/álbuns/faixas públicos, links curtos spotify.link e URIs spotify:)
 * - Deezer (API pública com paginação até 2000 faixas, links curtos link.deezer.com / dzr.page.link)
 * - YouTube Music / YouTube (InnerTube)
 * - Apple Music, Amazon Music e Tidal por link público
 * - Múltiplos links de uma vez (um por linha)
 * - Arquivos CSV (Exportify, TuneMyMusic, Soundiiz…), M3U e TXT
 * - Lista de texto "Artista - Música"
 */
object ImportService {
    data class ImportResult(val playlistName: String, val sourceBadge: String, val artworkURL: String, val tracks: List<Track>)

    private const val MOBILE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    private val linkRegex = Regex("""https?://[^\s<>"']+""", RegexOption.IGNORE_CASE)
    private val shortHosts = listOf(
        "spotify.link", "spotify.app.link",
        "link.deezer.com", "deezer.page.link", "dzr.page.link",
        "amzn.to", "amzn.eu", "amzn.asia",
        "tidal.link", "apple.co", "youtu.be",
    )

    fun extractLinks(text: String): List<String> {
        val out = LinkedHashSet<String>()
        for (m in linkRegex.findAll(text)) {
            val clean = m.value.trimEnd('.', ',', ';', ')', ']', '"', '\'')
            if (clean.isNotEmpty()) out.add(clean)
        }
        // Também aceita URIs spotify:playlist:ID
        for (raw in text.lines()) {
            val t = raw.trim()
            if (t.lowercase().startsWith("spotify:")) {
                val parts = t.split(":")
                if (parts.size >= 3) out.add("https://open.spotify.com/${parts[parts.size - 2]}/${parts[parts.size - 1]}")
            }
        }
        return out.toList()
    }

    fun firstLink(text: String): String? = extractLinks(text).firstOrNull()

    fun serviceNameForLink(text: String): String? {
        val l = text.lowercase()
        return when {
            "spotify" in l -> "Spotify"
            "deezer" in l || "dzr.page" in l -> "Deezer"
            "music.youtube" in l || "youtube.com" in l || "youtu.be" in l -> "YouTube Music"
            "music.apple" in l || "apple.co" in l -> "Apple Music"
            "tidal" in l -> "Tidal"
            "amazon" in l || "amzn" in l -> "Amazon Music"
            else -> null
        }
    }

    // 1. Músicas locais do aparelho (equivalente 1-toque ao "Apple Music do iPhone")
    suspend fun importFromDevice(context: Context): List<ImportResult> = withContext(Dispatchers.IO) {
        val tracks = mutableListOf<Track>()
        val proj = arrayOf(MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION)
        try {
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, proj,
                "${MediaStore.Audio.Media.IS_MUSIC} != 0", null, "${MediaStore.Audio.Media.DATE_ADDED} DESC",
            )?.use { c ->
                while (c.moveToNext() && tracks.size < 1000) {
                    val title = c.getString(0) ?: continue
                    if (title.isBlank()) continue
                    var artist = c.getString(1) ?: "Artista"
                    if (artist == "<unknown>") artist = "Artista"
                    tracks.add(newTrack(
                        title = title, artist = artist, album = c.getString(2) ?: "",
                        duration = c.getLong(3) / 1000.0, sourceService = "Aparelho",
                    ))
                }
            }
        } catch (_: SecurityException) {
            throw ImportException("Permita o acesso às músicas do aparelho para importar.")
        }
        if (tracks.isEmpty()) {
            throw ImportException("Nenhuma música salva encontrada neste aparelho. Para trazer do Spotify, YouTube Music ou Deezer, escolha o serviço abaixo.")
        }
        listOf(ImportResult("Músicas do Aparelho", "Aparelho", "", tracks))
    }

    // 2. Um ou vários links de uma vez
    suspend fun importMultipleURLs(rawInput: String, onProgress: ((String) -> Unit)? = null): List<ImportResult> {
        val links = extractLinks(rawInput)
        if (links.isEmpty()) throw ImportException("Link inválido. Cole o link completo de uma playlist ou álbum.")
        if (links.size == 1) return listOf(importFromURL(links.first(), onProgress))
        val results = mutableListOf<ImportResult>()
        var lastErr: String? = null
        for ((i, u) in links.withIndex()) {
            onProgress?.invoke("Importando playlist ${i + 1} de ${links.size}…")
            try {
                results.add(importFromURL(u, onProgress))
            } catch (e: ImportException) {
                lastErr = e.message
            } catch (_: Exception) {
                lastErr = "Não foi possível ler um dos links."
            }
        }
        if (results.isEmpty()) throw ImportException(lastErr ?: "Não foi possível importar os links informados.")
        return results
    }

    suspend fun importFromURL(rawURL: String, onProgress: ((String) -> Unit)? = null): ImportResult {
        var trimmed = firstLink(rawURL) ?: rawURL.trim()
        if (trimmed.lowercase().startsWith("spotify:")) {
            val parts = trimmed.split(":")
            if (parts.size >= 3) trimmed = "https://open.spotify.com/${parts[parts.size - 2]}/${parts[parts.size - 1]}"
        }
        var uri = try { URI(trimmed) } catch (_: Exception) { null }
        var host = uri?.host?.lowercase() ?: throw ImportException("Link inválido. Cole o link completo de uma playlist ou álbum.")

        // Links curtos (spotify.link, link.deezer.com, amzn.to…): segue o redirecionamento real.
        if (shortHosts.any { host == it || host.endsWith(".$it") }) {
            onProgress?.invoke("Abrindo link…")
            val resolved = resolveRedirect(trimmed)
            if (resolved != null) {
                val rUri = try { URI(resolved) } catch (_: Exception) { null }
                if (rUri?.host != null) {
                    uri = rUri
                    host = rUri.host.lowercase()
                    trimmed = resolved
                }
            }
        }

        val finalUri = uri ?: throw ImportException("Link inválido. Cole o link completo de uma playlist ou álbum.")
        onProgress?.invoke("Lendo a playlist…")
        return when {
            host.contains("spotify.com") -> importSpotify(finalUri)
            host.contains("deezer.com") || host.contains("deezer.page.link") -> importDeezer(finalUri, onProgress)
            host.contains("youtube.com") || host.contains("youtu.be") -> importYouTube(finalUri)
            host.contains("music.apple.com") -> importAppleMusicURL(finalUri)
            host.contains("tidal.com") -> importGenericMusicPage(trimmed, "Tidal")
            host.contains("amazon.") -> importGenericMusicPage(trimmed, "Amazon Music")
            else -> importGenericMusicPage(trimmed, "Importada")
        }
    }

    private suspend fun resolveRedirect(url: String): String? = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder().url(url).header("User-Agent", DiscNet.BROWSER_UA).get().build()
            DiscNet.client.newCall(req).execute().use { resp -> resp.request.url.toString() }
        } catch (_: Exception) {
            null
        }
    }

    // 3. Texto / M3U
    fun importFromText(text: String, name: String): ImportResult {
        val tracks = mutableListOf<Track>()
        for (raw in text.lines()) {
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("#EXTM3U")) continue
            var clean = line
            if (clean.startsWith("#EXTINF:")) {
                val comma = clean.indexOf(',')
                if (comma < 0) continue
                clean = clean.substring(comma + 1).trim()
            } else if (clean.startsWith("#") || clean.startsWith("http")) continue
            val sep = listOf(" - ", " – ", " — ").map { clean.indexOf(it) to it }.firstOrNull { it.first >= 0 }
            if (sep != null) {
                val a = clean.substring(0, sep.first).trim()
                val b = clean.substring(sep.first + sep.second.length).trim()
                tracks.add(newTrack(title = b, artist = a, sourceService = "Lista"))
            } else tracks.add(newTrack(title = clean, artist = "", sourceService = "Lista"))
        }
        return ImportResult(name.ifEmpty { "Playlist Importada" }, "Importada", "", tracks)
    }

    // 4. Arquivo CSV (Exportify, TuneMyMusic, Soundiiz…), M3U ou TXT
    fun importFromFile(text: String, filename: String): ImportResult {
        if (text.isBlank()) throw ImportException("Não consegui ler esse arquivo. Use CSV, M3U ou TXT.")
        val base = filename.substringAfterLast('/').substringBeforeLast('.').ifBlank { "Playlist Importada" }
        val ext = filename.substringAfterLast('.', "").lowercase()
        val result = if (ext == "csv" || (ext != "m3u" && ext != "m3u8" && looksLikeCSV(text))) {
            importFromCSV(text, base)
        } else {
            importFromText(text, base)
        }
        if (result.tracks.isEmpty()) {
            throw ImportException("Não encontrei músicas nesse arquivo. Ele precisa ter uma música por linha (Artista - Música) ou um CSV com título e artista.")
        }
        return ImportResult(result.playlistName, "Arquivo", "", result.tracks)
    }

    private fun looksLikeCSV(text: String): Boolean {
        val first = text.lineSequence().firstOrNull()?.lowercase() ?: return false
        return (',' in first || ';' in first) && listOf("title", "track", "artist", "nome", "artista", "música", "musica", "song").any { it in first }
    }

    private fun importFromCSV(text: String, name: String): ImportResult {
        val firstLine = text.lineSequence().firstOrNull() ?: ""
        val delimiter = if (firstLine.count { it == ';' } > firstLine.count { it == ',' }) ';' else ','
        val rows = parseCSV(text, delimiter)
        val header = rows.firstOrNull() ?: return ImportResult(name, "Arquivo", "", emptyList())
        val h = header.map { it.lowercase().trim() }

        fun col(keys: List<String>, exclude: List<String> = emptyList()): Int? {
            for ((i, n) in h.withIndex()) if (keys.any { n == it }) return i
            for ((i, n) in h.withIndex()) if (keys.any { it in n } && exclude.none { it in n }) return i
            return null
        }
        val titleCol = col(listOf("track name", "title", "song", "track", "música", "musica", "nome da faixa", "name", "nome"), listOf("artist", "album", "uri", "id", "playlist"))
        val artistCol = col(listOf("artist name(s)", "artist name", "artist", "artista", "artistas"))
        val albumCol = col(listOf("album name", "album", "álbum"), listOf("artist", "date", "uri", "id", "image"))
        val durCol = col(listOf("duration (ms)", "duration_ms", "duration"))

        val tracks = mutableListOf<Track>()
        if (titleCol != null) {
            for (row in rows.drop(1)) {
                if (titleCol >= row.size) continue
                val title = row[titleCol].trim()
                if (title.isEmpty()) continue
                val artist = (artistCol?.takeIf { it < row.size }?.let { row[it] } ?: "").trim().replace(";", ", ")
                val album = (albumCol?.takeIf { it < row.size }?.let { row[it] } ?: "").trim()
                val rawDur = durCol?.takeIf { it < row.size }?.let { row[it].trim().toDoubleOrNull() } ?: 0.0
                val dur = if (rawDur > 10_000.0) rawDur / 1000.0 else rawDur
                tracks.add(newTrack(title = title, artist = artist, album = album, duration = dur, sourceService = "Arquivo"))
            }
        } else {
            for (row in rows) {
                val a = row.getOrNull(0)?.trim().orEmpty()
                if (a.isEmpty()) continue
                val b = row.getOrNull(1)?.trim().orEmpty()
                tracks.add(newTrack(title = a, artist = b, sourceService = "Arquivo"))
            }
        }
        return ImportResult(name, "Arquivo", "", tracks)
    }

    internal fun parseCSV(text: String, delimiter: Char = ','): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val field = StringBuilder()
        var inQuotes = false
        val norm = text.replace("\r\n", "\n").replace("\r", "\n").removePrefix("\uFEFF")
        var i = 0
        while (i < norm.length) {
            val c = norm[i]
            if (inQuotes) {
                if (c == '"') {
                    if (i + 1 < norm.length && norm[i + 1] == '"') { field.append('"'); i++ } else inQuotes = false
                } else field.append(c)
            } else when (c) {
                '"' -> inQuotes = true
                delimiter -> { row.add(field.toString()); field.clear() }
                '\n' -> {
                    row.add(field.toString()); field.clear()
                    if (!(row.size == 1 && row[0].isEmpty())) rows.add(row)
                    row = mutableListOf()
                }
                else -> field.append(c)
            }
            i++
        }
        if (field.isNotEmpty() || row.isNotEmpty()) { row.add(field.toString()); rows.add(row) }
        return rows
    }

    // ---- Deezer (API pública com paginação) ----

    private suspend fun importDeezer(uri: URI, onProgress: ((String) -> Unit)?): ImportResult {
        val comps = uri.path.split("/").filter { it.isNotEmpty() }
        val idx = comps.indexOfFirst { it == "playlist" || it == "album" || it == "track" }
        val id = if (idx >= 0 && idx + 1 < comps.size) comps[idx + 1].filter { it.isDigit() }.toLongOrNull() else null
        if (idx < 0 || id == null) {
            throw ImportException("Use o link de uma playlist, álbum ou faixa pública do Deezer (Compartilhar › Copiar link).")
        }
        val kind = comps[idx]

        fun mapTrack(d: JsonObject, fallbackArt: String = ""): Track? {
            val title = d["title"].str()?.takeIf { it.isNotEmpty() } ?: return null
            val artist = d["artist"]["name"].str() ?: ""
            val alb = d["album"]
            var art = alb["cover_xl"].str() ?: alb["cover_big"].str() ?: fallbackArt
            if ("/cover//" in art) art = fallbackArt
            val dur = d["duration"].dbl() ?: 0.0
            return newTrack(
                title = title, artist = artist, album = alb["title"].str() ?: "",
                duration = dur, artworkURL = art, sourceService = "Deezer",
                isExplicit = d["explicit_lyrics"].bool() ?: false,
            )
        }

        if (kind == "track") {
            val d = DiscNet.json("https://api.deezer.com/track/$id", 10, retries = 1).obj()
            if (d == null || d["error"] != null) throw ImportException("Não consegui abrir essa faixa do Deezer.")
            val t = mapTrack(d) ?: throw ImportException("Não consegui abrir essa faixa do Deezer.")
            return ImportResult(t.title, "Deezer", t.artworkURL, listOf(t))
        }

        val isAlbum = kind == "album"
        val meta = DiscNet.json("https://api.deezer.com/$kind/$id", 10, retries = 1).obj()
        if (meta == null || meta["error"] != null) {
            throw ImportException("Playlist privada ou indisponível no Deezer. Deixe-a pública para importar.")
        }
        val title = meta["title"].str() ?: if (isAlbum) "Álbum Deezer" else "Playlist Deezer"
        val cover = meta["cover_xl"].str() ?: meta["picture_xl"].str() ?: meta["cover_big"].str() ?: meta["picture_big"].str() ?: ""
        onProgress?.invoke("Lendo $title…")

        val tracks = mutableListOf<Track>()
        var index = 0
        val pageSize = 100
        while (index < 2000) {
            val page = DiscNet.json("https://api.deezer.com/$kind/$id/tracks?index=$index&limit=$pageSize", 10, retries = 1).obj() ?: break
            val data = page["data"].objs()
            if (data.isEmpty()) break
            for (d in data) mapTrack(d, if (isAlbum) cover else "")?.let { tracks.add(it) }
            index += data.size
            onProgress?.invoke("$title · ${tracks.size} músicas")
            if (page["next"] == null || data.size < pageSize) break
        }
        if (tracks.isEmpty()) throw ImportException("Nenhuma faixa encontrada nessa lista do Deezer.")
        return ImportResult(title, "Deezer", cover, tracks)
    }

    // ---- Spotify ----

    private suspend fun importSpotify(uri: URI): ImportResult {
        val comps = uri.path.split("/").filter { it.isNotEmpty() }
        if (comps.size < 2) throw ImportException("Use o link de uma playlist ou álbum público do Spotify.")
        val idx = comps.indexOfFirst { it == "playlist" || it == "album" || it == "track" }
        val kind: String
        val id: String
        if (idx >= 0 && idx + 1 < comps.size) { kind = comps[idx]; id = comps[idx + 1] } else { kind = "playlist"; id = comps.last() }
        val html = DiscNet.text("https://open.spotify.com/embed/$kind/$id", 12, mapOf("User-Agent" to MOBILE_UA))
        val open = "<script id=\"__NEXT_DATA__\" type=\"application/json\">"
        val s = html?.indexOf(open) ?: -1
        val e = if (s >= 0) html!!.indexOf("</script>", s + open.length) else -1
        if (html == null || s < 0 || e < 0) throw ImportException("Playlist privada ou indisponível no Spotify. Deixe-a pública para importar.")
        val root = DiscNet.parse(html.substring(s + open.length, e)) ?: throw ImportException("Não foi possível extrair as faixas do Spotify.")
        val entity = root["props"]["pageProps"]["state"]["data"]["entity"].obj()
            ?: throw ImportException("Não foi possível extrair as faixas do Spotify.")
        val title = entity["name"].str() ?: entity["title"].str() ?: "Playlist Spotify"
        val cover = entity["visualIdentity"]["image"].objs().firstOrNull()?.get("url").str()
            ?: entity["coverArt"]["sources"].objs().firstOrNull()?.get("url").str() ?: ""
        val tracks = mutableListOf<Track>()
        val list = entity["trackList"].objs()
        if (list.isNotEmpty()) {
            for (item in list) {
                val t = item["title"].str()?.takeIf { it.isNotEmpty() } ?: continue
                val artist = (item["subtitle"].str() ?: "").replace('\u00A0', ' ')
                tracks.add(newTrack(
                    title = t, artist = artist, album = title,
                    duration = (item["duration"].dbl() ?: 0.0) / 1000.0, artworkURL = cover, sourceService = "Spotify",
                ))
            }
        } else if (kind == "track") {
            val t = entity["name"].str()
            if (t != null) {
                val artist = entity["artists"].objs().mapNotNull { it["name"].str() }.joinToString(", ")
                tracks.add(newTrack(title = t, artist = artist, artworkURL = cover, sourceService = "Spotify"))
            }
        }
        if (tracks.isEmpty()) throw ImportException("Nenhuma faixa encontrada nessa playlist do Spotify.")
        return ImportResult(title, "Spotify", cover, tracks)
    }

    // ---- YouTube ----

    private suspend fun importYouTube(uri: URI): ImportResult {
        val listId = (uri.rawQuery ?: "").split("&").map { it.split("=", limit = 2) }
            .firstOrNull { it[0] == "list" && it.size == 2 }?.get(1)
        if (!listId.isNullOrEmpty()) {
            val (name, tracks) = MusicEngine.fetchYTMPlaylist(listId)
            if (tracks.isEmpty()) throw ImportException("Playlist do YouTube Music vazia ou privada. Deixe-a pública ou não listada.")
            return ImportResult(name, "YouTube Music", tracks.first().artworkURL, tracks)
        }
        throw ImportException("Cole um link de playlist do YouTube Music contendo '?list=...'.")
    }

    // ---- Apple Music ----

    private suspend fun importAppleMusicURL(uri: URI): ImportResult {
        val last = uri.path.split("/").lastOrNull { it.isNotEmpty() }
        if (last != null && last.toLongOrNull() != null && uri.path.contains("/album/")) {
            val obj = DiscNet.json("https://itunes.apple.com/lookup?id=$last&entity=song&country=br")
            val items = obj["results"].objs()
            if (items.isNotEmpty()) {
                val albTitle = items.first()["collectionName"].str() ?: "Álbum Apple Music"
                val albArt = (items.first()["artworkUrl100"].str() ?: "").replace("100x100bb", "1400x1400bb")
                val tracks = items.mapNotNull { it ->
                    if (it["wrapperType"].str() != "track") return@mapNotNull null
                    val n = it["trackName"].str() ?: return@mapNotNull null
                    newTrack(
                        title = n, artist = it["artistName"].str() ?: "", album = albTitle,
                        duration = (it["trackTimeMillis"].dbl() ?: 0.0) / 1000.0,
                        artworkURL = (it["artworkUrl100"].str() ?: albArt).replace("100x100bb", "1400x1400bb"),
                        sourceService = "Apple Music",
                    )
                }
                if (tracks.isNotEmpty()) return ImportResult(albTitle, "Apple Music", albArt, tracks)
            }
        }
        return importGenericMusicPage(uri.toString(), "Apple Music")
    }

    // ---- Página genérica (JSON-LD / og:) ----

    private val reOgTitle = Regex("""<meta[^>]+property="og:title"[^>]+content="([^"]+)"""")
    private val reOgImage = Regex("""<meta[^>]+property="og:image"[^>]+content="([^"]+)"""")
    private val reLd = Regex("""<script[^>]+type="application/ld\+json"[^>]*>(.*?)</script>""", RegexOption.DOT_MATCHES_ALL)

    private suspend fun importGenericMusicPage(url: String, badge: String): ImportResult {
        val html = DiscNet.text(url, 12, mapOf("User-Agent" to InnerTube.WEB_UA))
            ?: throw ImportException("Não foi possível abrir essa página.")
        var playlistTitle = "Playlist $badge"
        var cover = ""
        reOgTitle.find(html)?.let { playlistTitle = it.groupValues[1].replace(" no Apple Music", "").replace(" on Apple Music", "") }
        reOgImage.find(html)?.let { cover = it.groupValues[1] }
        val tracks = mutableListOf<Track>()
        for (m in reLd.findAll(html)) {
            val obj = DiscNet.parse(m.groupValues[1]).obj() ?: continue
            obj["name"].str()?.takeIf { it.isNotEmpty() }?.let { playlistTitle = it }
            for (item in obj["track"].objs()) {
                val name = item["name"].str()?.takeIf { it.isNotEmpty() } ?: continue
                val by = item["byArtist"]
                val artist = when (by) {
                    is JsonObject -> by["name"].str() ?: ""
                    is JsonArray -> by.objs().mapNotNull { it["name"].str() }.joinToString(", ")
                    else -> ""
                }
                tracks.add(newTrack(title = name, artist = artist, album = playlistTitle, artworkURL = cover, sourceService = badge))
            }
        }
        if (tracks.isEmpty()) {
            throw ImportException("O $badge não deixa o Lume ler esse link automaticamente. Sem problema: exporte em CSV (Exportify / TuneMyMusic) e escolha “Arquivo”, ou cole na lista de texto.")
        }
        return ImportResult(playlistTitle, badge, cover, tracks)
    }
}
