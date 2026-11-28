package com.adriano.lumemusic.audio

import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import androidx.compose.runtime.snapshotFlow
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionError
import com.adriano.lumemusic.MainActivity
import com.adriano.lumemusic.R
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.MusicEngine
import com.adriano.lumemusic.widget.LumeWidget
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

/**
 * Player exposto à sessão: previous/next controlam a fila do Lume (não a do ExoPlayer, que tem 1 item).
 * Quem põe música no ExoPlayer é sempre o AudioPlayer; pedidos de controladores externos (Android Auto, Bluetooth, assistente)
 * para trocar a lista de reprodução são tratados em [PlaybackService] chamando o AudioPlayer, então aqui viram "nada a fazer".
 */
class SessionPlayer(p: Player) : ForwardingPlayer(p) {
    private val extra = Player.Commands.Builder()
        .addAll(Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_PREVIOUS,
            Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM).build()

    override fun getAvailableCommands(): Player.Commands = super.getAvailableCommands().buildUpon().addAll(extra).build()
    override fun isCommandAvailable(command: Int): Boolean = availableCommands.contains(command)
    override fun hasNextMediaItem() = true
    override fun hasPreviousMediaItem() = true
    override fun seekToNext() = AudioPlayer.nextTrack()
    override fun seekToNextMediaItem() = AudioPlayer.nextTrack()
    override fun seekToPrevious() = AudioPlayer.previousTrack()
    override fun seekToPreviousMediaItem() = AudioPlayer.previousTrack()

    override fun setMediaItem(mediaItem: MediaItem) {}
    override fun setMediaItem(mediaItem: MediaItem, startPositionMs: Long) {}
    override fun setMediaItem(mediaItem: MediaItem, resetPosition: Boolean) {}
    override fun setMediaItems(mediaItems: MutableList<MediaItem>) {}
    override fun setMediaItems(mediaItems: MutableList<MediaItem>, resetPosition: Boolean) {}
    override fun setMediaItems(mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long) {}
    override fun addMediaItem(mediaItem: MediaItem) {}
    override fun addMediaItem(index: Int, mediaItem: MediaItem) {}
    override fun addMediaItems(mediaItems: MutableList<MediaItem>) {}
    override fun addMediaItems(index: Int, mediaItems: MutableList<MediaItem>) {}
}

/**
 * Notificação / tela de bloqueio com capa, título e controles (MediaSession) + biblioteca navegável para o Android Auto
 * (MediaLibrarySession). Também atualiza o widget da tela inicial quando a faixa ou o estado mudam.
 */
class PlaybackService : MediaLibraryService() {
    private var session: MediaLibrarySession? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val callback = object : MediaLibrarySession.Callback {
        override fun onGetLibraryRoot(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, params: LibraryParams?): ListenableFuture<LibraryResult<MediaItem>> =
            Futures.immediateFuture(LibraryResult.ofItem(LibraryBrowseTree.rootItem(), params))

        override fun onGetItem(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, mediaId: String): ListenableFuture<LibraryResult<MediaItem>> {
            val item = if (mediaId == LibraryBrowseTree.ROOT) LibraryBrowseTree.rootItem()
            else LibraryBrowseTree.lookup(mediaId)?.let { LibraryBrowseTree.trackItem(it) }
            return Futures.immediateFuture(if (item != null) LibraryResult.ofItem(item, null) else LibraryResult.ofError(SessionError.ERROR_BAD_VALUE))
        }

        override fun onGetChildren(
            session: MediaLibrarySession, browser: MediaSession.ControllerInfo, parentId: String, page: Int, pageSize: Int, params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            val all = LibraryBrowseTree.children(parentId)
                ?: return Futures.immediateFuture(LibraryResult.ofError(SessionError.ERROR_BAD_VALUE))
            return Futures.immediateFuture(LibraryResult.ofItemList(ImmutableList.copyOf(pageOf(all, page, pageSize)), params))
        }

        override fun onSearch(session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, params: LibraryParams?): ListenableFuture<LibraryResult<Void>> {
            scope.launch {
                val found = searchTracks(query)
                LibraryBrowseTree.setSearch(query, found)
                session.notifySearchResultChanged(browser, query, found.size, params)
            }
            return Futures.immediateFuture(LibraryResult.ofVoid())
        }

        override fun onGetSearchResult(
            session: MediaLibrarySession, browser: MediaSession.ControllerInfo, query: String, page: Int, pageSize: Int, params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            val f = SettableFuture.create<LibraryResult<ImmutableList<MediaItem>>>()
            scope.launch {
                val found = LibraryBrowseTree.search(query) ?: searchTracks(query).also { LibraryBrowseTree.setSearch(query, it) }
                f.set(LibraryResult.ofItemList(ImmutableList.copyOf(pageOf(LibraryBrowseTree.searchItems(query, found), page, pageSize)), params))
            }
            return f
        }

        /** Escolher uma música no carro / voz ("tocar X") / Bluetooth: toca pelo AudioPlayer, o mesmo caminho do app. */
        override fun onSetMediaItems(
            mediaSession: MediaSession, controller: MediaSession.ControllerInfo, mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            val f = SettableFuture.create<MediaSession.MediaItemsWithStartPosition>()
            scope.launch {
                try {
                    val played = playRequest(mediaItems, startIndex)
                    f.set(MediaSession.MediaItemsWithStartPosition(
                        played.map { LibraryBrowseTree.trackItem(it) }, if (played.isEmpty()) C.INDEX_UNSET else 0, C.TIME_UNSET))
                } catch (e: Exception) { f.setException(e) }
            }
            return f
        }

        /** "Adicionar à fila" de um controlador externo. */
        override fun onAddMediaItems(mediaSession: MediaSession, controller: MediaSession.ControllerInfo, mediaItems: MutableList<MediaItem>): ListenableFuture<MutableList<MediaItem>> {
            val f = SettableFuture.create<MutableList<MediaItem>>()
            scope.launch {
                try {
                    val tracks = resolve(mediaItems)
                    tracks.forEach { AudioPlayer.addToQueue(it) }
                    f.set(tracks.map { LibraryBrowseTree.trackItem(it) }.toMutableList())
                } catch (e: Exception) { f.setException(e) }
            }
            return f
        }
    }

    private fun pageOf(all: List<MediaItem>, page: Int, pageSize: Int): List<MediaItem> {
        if (pageSize <= 0 || pageSize == Int.MAX_VALUE) return all
        val from = (page.toLong() * pageSize).coerceAtMost(all.size.toLong()).toInt()
        return all.subList(from, minOf(all.size, from + pageSize))
    }

    private suspend fun searchTracks(query: String): List<Track> {
        val q = query.trim()
        if (q.isEmpty()) return LibraryStore.favoriteTracks.ifEmpty { LibraryStore.recentTracks }
        return try { MusicEngine.searchSongs(q, 25) } catch (_: Exception) { emptyList() }
    }

    /** mediaIds (música, pasta/playlist) ou consulta de voz → faixas. */
    private suspend fun resolve(items: List<MediaItem>): List<Track> {
        val out = ArrayList<Track>()
        for (it in items) {
            val id = it.mediaId
            val t = LibraryBrowseTree.lookup(id)
            when {
                t != null -> out += t
                LibraryBrowseTree.isFolder(id) -> LibraryBrowseTree.tracksOf(id)?.second?.let { l -> out += l }
                it.requestMetadata.searchQuery != null -> out += searchTracks(it.requestMetadata.searchQuery!!)
            }
        }
        return out
    }

    /** Toca o pedido. Uma música escolhida numa lista toca a lista inteira a partir dela. Devolve as faixas que passaram a tocar. */
    private suspend fun playRequest(items: List<MediaItem>, startIndex: Int): List<Track> {
        val first = items.firstOrNull() ?: return emptyList()
        val ctx = if (items.size == 1) LibraryBrowseTree.context(first.mediaId) else null
        val track = ctx?.list?.firstOrNull { it.id == first.mediaId }
        if (ctx != null && track != null) {
            if (ctx.parent == LibraryBrowseTree.NOW) {
                val i = AudioPlayer.queue.indexOfFirst { it.id == track.id }
                if (i >= 0) { AudioPlayer.jumpToQueueIndex(i); return listOf(track) }
            }
            AudioPlayer.play(track, ctx.list, ctx.title)
            return listOf(track)
        }
        val tracks = resolve(items)
        if (tracks.isEmpty()) return emptyList()
        val start = startIndex.takeIf { it in tracks.indices } ?: 0
        val label = items.firstNotNullOfOrNull { it.requestMetadata.searchQuery?.takeIf { q -> q.isNotBlank() } }?.let { "Busca: $it" }
        AudioPlayer.play(tracks[start], tracks, label)
        return tracks
    }

    override fun onCreate() {
        super.onCreate()
        PlayerHolder.init(this)
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaLibrarySession.Builder(this, SessionPlayer(PlayerHolder.player), callback).setSessionActivity(open).build()
        setMediaNotificationProvider(DefaultMediaNotificationProvider(this).also { it.setSmallIcon(R.drawable.ic_stat_lume) })
        observeForCar()
        observeForWidget()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    /** Avisa o carro quando a fila, as curtidas, as playlists, as baixadas ou os recentes mudam. */
    private fun observeForCar() {
        fun watch(parent: String, read: () -> Any?) = scope.launch {
            snapshotFlow(read).drop(1).collect {
                delay(500)
                try { session?.notifyChildrenChanged(parent, 0, null) } catch (_: Exception) {}
            }
        }
        watch(LibraryBrowseTree.NOW) { AudioPlayer.queue }
        watch(LibraryBrowseTree.LIKED) { LibraryStore.favoriteIds }
        watch(LibraryBrowseTree.PLAYLISTS) { LibraryStore.playlists }
        watch(LibraryBrowseTree.DOWNLOADED) { LibraryStore.downloadedIds }
        watch(LibraryBrowseTree.RECENT) { LibraryStore.recentIds }
    }

    /** Widget: atualiza quando muda a faixa, a capa ou tocar/pausar (leitura do estado do AudioPlayer, sem tocar no player). */
    private fun observeForWidget() {
        val app = applicationContext
        scope.launch {
            snapshotFlow { Triple(AudioPlayer.currentTrack?.id, AudioPlayer.isPlaying, AudioPlayer.currentArtwork) }.collect {
                delay(200)
                LumeWidget.requestUpdate(app)
            }
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = PlayerHolder.player
        if (!p.playWhenReady || p.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        scope.cancel()
        session?.release()
        session = null
        super.onDestroy()
    }
}
