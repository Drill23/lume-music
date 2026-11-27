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
import java.net.URI

class ImportException(message: String) : Exception(message)

/** Importador 1-clique: biblioteca local do aparelho, Spotify, YouTube Music, Apple Music, Amazon e texto/M3U. */
object ImportService {
    data class ImportResult(val playlistName: String, val sourceBadge: String, val artworkURL: String, val tracks: List<Track>)

    // 1. Músicas locais do aparelho (equivalente ao "Apple Music do iPhone")
    suspend fun importFromDevice(context: Context): List<ImportResult> = withContext(Dispatchers.IO) {
        val tracks = mutableListOf<Track>()
        val proj = arrayOf(MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION)
        try {
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, proj,
                "${MediaStore.Audio.Media.IS_MUSIC} != 0", null, "${MediaStore.Audio.Media.DATE_ADDED} DESC",
            )?.use { c ->
                while (c.moveToNext() && tracks.size < 200) {
                    val title = c.getString(0) ?: continue
                    if (title.isBlank()) continue
                    var artist = c.getString(1) ?: "Artista"
                    if (artist == "<unknown>") artist = "Artista"
                    tracks.add(newTrack(title = title, artist = artist, album = c.getString(2) ?: "",
                        duration = c.getLong(3) / 1000.0, sourceService = "Aparelho"))
                }
            }
        } catch (_: SecurityException) {
            throw ImportException("Permita o acesso às músicas do aparelho para importar.")
        }
        if (tracks.isEmpty()) throw ImportException("Nenhuma música encontrada neste aparelho. Você também pode colar o link de uma playlist abaixo!")
        listOf(ImportResult("Minha Biblioteca do Aparelho", "Aparelho", "", tracks))
    }

    // 2. Por link
    suspend fun importFromURL(rawURL: String): ImportResult {
        val trimmed = rawURL.trim()
        val uri = try { URI(trimmed) } catch (_: Exception) { null }
        val host = uri?.host?.lowercase() ?: throw ImportException("Link inválido. Cole o link completo de uma playlist ou álbum.")
        return when {
            host.contains("spotify.com") -> importSpotify(uri)
            host.contains("youtube.com") || host.contains("youtu.be") -> importYouTube(uri)
            host.contains("music.apple.com") -> importAppleMusicURL(uri)
            host.contains("amazon.") -> importGenericMusicPage(trimmed, "Amazon Music")
            else -> importGenericMusicPage(trimmed, "Importada")
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

    // ---- Spotify ----

    private suspend fun importSpotify(uri: URI): ImportResult {
        val comps = uri.path.split("/").filter { it.isNotEmpty() }
        if (comps.size < 2) throw ImportException("Use o link de uma playlist ou álbum público do Spotify.")
        val idx = comps.indexOfFirst { it == "playlist" || it == "album" || it == "track" }
        val kind: String
        val id: String
        if (idx >= 0 && idx + 1 < comps.size) { kind = comps[idx]; id = comps[idx + 1] } else { kind = "playlist"; id = comps.last() }
        val html = DiscNet.text("https://open.spotify.com/embed/$kind/$id", 10,
            mapOf("User-Agent" to "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"))
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
                val artist = (item["subtitle"].str() ?: "").replace(' ', ' ')
                tracks.add(newTrack(title = t, artist = artist, album = title,
                    duration = (item["duration"].dbl() ?: 0.0) / 1000.0, artworkURL = cover, sourceService = "Spotify"))
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
            if (tracks.isEmpty()) throw ImportException("Playlist do YouTube Music vazia ou privada.")
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
                    newTrack(title = n, artist = it["artistName"].str() ?: "", album = albTitle,
                        duration = (it["trackTimeMillis"].dbl() ?: 0.0) / 1000.0,
                        artworkURL = (it["artworkUrl100"].str() ?: albArt).replace("100x100bb", "1400x1400bb"),
                        sourceService = "Apple Music")
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
        val html = DiscNet.text(url, 10, mapOf("User-Agent" to InnerTube.WEB_UA))
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
            throw ImportException("Não foi possível ler automaticamente esse link do $badge. Dica: copie os nomes das faixas e use a aba 'Lista de texto'!")
        }
        return ImportResult(playlistTitle, badge, cover, tracks)
    }
}

private fun JsonElement?.asObj() = this as? JsonObject
