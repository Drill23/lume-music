package com.adriano.lumemusic.audio

import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import com.adriano.lumemusic.data.ArtworkStore
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.Track
import java.util.concurrent.ConcurrentHashMap

/**
 * Árvore de navegação do Android Auto (e de qualquer MediaBrowser): Tocando agora, Curtidas, Playlists, Baixadas, Recentes.
 * O mediaId de uma música é o id da faixa no Lume; quem resolve e toca é o AudioPlayer (mesmo caminho do app).
 */
object LibraryBrowseTree {
    const val ROOT = "lume_root"
    const val NOW = "lume_now"
    const val LIKED = "lume_liked"
    const val PLAYLISTS = "lume_playlists"
    const val DOWNLOADED = "lume_downloaded"
    const val RECENT = "lume_recent"
    private const val PL_PREFIX = "lume_pl:"
    private const val MAX_ITEMS = 200

    /** Em qual lista cada faixa foi servida por último (para tocar a lista inteira ao escolher uma música). */
    class Served(val parent: String, val title: String, val list: List<Track>)

    private val served = ConcurrentHashMap<String, Served>()
    private val searches = ConcurrentHashMap<String, List<Track>>()

    private fun art(t: Track): String? = ArtworkStore.url(t).takeIf { it.isNotEmpty() }

    private fun folder(id: String, title: String, subtitle: String? = null, artwork: String? = null, type: Int = MediaMetadata.MEDIA_TYPE_FOLDER_MIXED): MediaItem =
        MediaItem.Builder().setMediaId(id).setMediaMetadata(
            MediaMetadata.Builder().setTitle(title).setSubtitle(subtitle).setArtworkUri(artwork?.toUri())
                .setIsBrowsable(true).setIsPlayable(false).setMediaType(type).build(),
        ).build()

    fun trackItem(t: Track): MediaItem =
        MediaItem.Builder().setMediaId(t.id).setMediaMetadata(
            MediaMetadata.Builder().setTitle(t.title).setArtist(t.artist).setAlbumTitle(t.album.ifEmpty { null })
                .setArtworkUri(art(t)?.toUri()).setIsBrowsable(false).setIsPlayable(true).setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC).build(),
        ).build()

    fun rootItem(): MediaItem = folder(ROOT, "Lume Music")

    fun isFolder(id: String) = id == ROOT || id == NOW || id == LIKED || id == PLAYLISTS || id == DOWNLOADED || id == RECENT || id.startsWith(PL_PREFIX)

    /** Faixas de uma pasta que é uma lista (não o root nem "Playlists"); null se não for. */
    fun tracksOf(parentId: String): Pair<String, List<Track>>? = when {
        parentId == NOW -> "Tocando agora" to AudioPlayer.queue
        parentId == LIKED -> "Curtidas" to LibraryStore.favoriteTracks
        parentId == DOWNLOADED -> "Baixadas" to LibraryStore.downloadedTracks
        parentId == RECENT -> "Recentes" to LibraryStore.recentTracks
        parentId.startsWith(PL_PREFIX) -> LibraryStore.playlists.firstOrNull { it.id == parentId.removePrefix(PL_PREFIX) }?.let { it.name to LibraryStore.tracks(it) }
        else -> null
    }?.let { (title, list) -> title to list.take(MAX_ITEMS) }

    /** Filhos de uma pasta; null se a pasta não existe. */
    fun children(parentId: String): List<MediaItem>? {
        when (parentId) {
            ROOT -> return listOf(
                folder(NOW, "Tocando agora", AudioPlayer.currentTrack?.title, null),
                folder(LIKED, "Curtidas"),
                folder(PLAYLISTS, "Playlists"),
                folder(DOWNLOADED, "Baixadas"),
                folder(RECENT, "Recentes"),
            )
            PLAYLISTS -> return LibraryStore.playlists.take(MAX_ITEMS).map { pl ->
                val n = pl.trackIds.size
                folder(PL_PREFIX + pl.id, pl.name, if (n == 1) "1 música" else "$n músicas",
                    pl.artworkURL.ifEmpty { LibraryStore.tracks(pl).firstOrNull()?.let { art(it) } ?: "" }.takeIf { it.isNotEmpty() },
                    MediaMetadata.MEDIA_TYPE_PLAYLIST)
            }
        }
        val (title, list) = tracksOf(parentId) ?: return null
        for (t in list) served[t.id] = Served(parentId, title, list)
        if (served.size > 3000) served.keys.take(1000).forEach { served.remove(it) }
        return list.map(::trackItem)
    }

    fun context(mediaId: String): Served? = served[mediaId]

    /** Acha a faixa de um mediaId: última lista servida, busca por voz, biblioteca ou fila. */
    fun lookup(mediaId: String): Track? =
        served[mediaId]?.list?.firstOrNull { it.id == mediaId }
            ?: searches.values.firstNotNullOfOrNull { l -> l.firstOrNull { it.id == mediaId } }
            ?: LibraryStore.tracksById[mediaId]
            ?: AudioPlayer.queue.firstOrNull { it.id == mediaId }

    fun setSearch(query: String, tracks: List<Track>) {
        if (searches.size > 6) searches.clear()
        searches[query.trim().lowercase()] = tracks
        LibraryStore.registerAll(tracks)
    }

    fun search(query: String): List<Track>? = searches[query.trim().lowercase()]

    /** Itens do resultado de busca; tocar um deles toca a lista inteira da busca. */
    fun searchItems(query: String, list: List<Track>): List<MediaItem> {
        for (t in list) served[t.id] = Served("lume_search", "Busca: $query", list)
        return list.map(::trackItem)
    }
}
