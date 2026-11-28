package com.adriano.lumemusic.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.adriano.lumemusic.platform.Haptics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import java.io.File

/** Resumo do Lume Replay. */
data class ReplaySummary(
    val totalPlays: Int,
    val totalMinutes: Int,
    val uniqueTracks: Int,
    val uniqueArtists: Int,
    val topTracks: List<Pair<Track, Int>>,
    val topArtists: List<Pair<String, Int>>,
)

@Serializable
private data class Snapshot(
    val tracksById: Map<String, Track> = emptyMap(),
    val favoriteIds: List<String> = emptyList(),
    val recentIds: List<String> = emptyList(),
    val playlists: List<MusicPlaylist> = emptyList(),
    val downloadedIds: List<String> = emptyList(),
    val searchHistory: List<String> = emptyList(),
    val visualizerStyle: String = VisualizerStyle.ARES.raw,
    val soundProfile: String = SoundProfile.NATURAL.raw,
    val animatedArtEnabled: Boolean = true,
    val autoTranslateLyrics: Boolean = false,
    val followedArtists: List<String> = emptyList(),
    val playCounts: Map<String, Int> = emptyMap(),
    val seenReleaseIds: List<String> = emptyList(),
    val savedAlbums: List<AlbumShowcase> = emptyList(),
    val customEQGains: List<Float> = listOf(0f, 0f, 0f, 0f, 0f),
    val crossfadeSeconds: Double = 0.0,
    val offlineMode: Boolean = false,
    val autoDownloadFavorites: Boolean = false,
    val totalListeningSeconds: Double = 0.0,
    val turntableFinish: String = TurntableFinish.OBSIDIAN.raw,
    val vinylEdition: String = VinylEdition.CLASSIC_BLACK.raw,
    val turntable3D: Boolean = true,
    val cassetteStyle: String = CassetteStyle.SMOKED_STUDIO.raw,
    val introEnabled: Boolean = true,
    val playerSurface: String = PlayerSurfaceTab.ARTWORK.raw,
    val lyricsFontScale: Float = 1f,
    val lockArtStyle: String = LockArtStyle.AUTOMATIC.raw,
    val deletedPlaylists: List<DeletedPlaylist> = emptyList(),
)

/**
 * Biblioteca local persistente: curtidas, playlists, histórico, Replay, preferências e metadados de downloads.
 * Estado exposto via Compose snapshot state.
 */
private class Saved<T>(initial: T) : kotlin.properties.ReadWriteProperty<Any?, T> {
    private val st = mutableStateOf(initial)
    override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): T = st.value
    override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: T) {
        if (st.value != value) { st.value = value; LibraryStore.save() }
    }
}

object LibraryStore {
    private lateinit var appContext: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var saveJob: Job? = null
    private var ready = false

    var tracksById by mutableStateOf<Map<String, Track>>(emptyMap()); private set
    var favoriteIds by mutableStateOf<List<String>>(emptyList()); private set
    var recentIds by mutableStateOf<List<String>>(emptyList()); private set
    var playlists by mutableStateOf<List<MusicPlaylist>>(emptyList()); private set
    var downloadedIds by mutableStateOf<Set<String>>(emptySet()); private set
    var searchHistory by mutableStateOf<List<String>>(emptyList()); private set
    var followedArtists by mutableStateOf<List<String>>(emptyList()); private set
    var playCounts by mutableStateOf<Map<String, Int>>(emptyMap()); private set
    var seenReleaseIds by mutableStateOf<Set<String>>(emptySet()); private set
    var savedAlbums by mutableStateOf<List<AlbumShowcase>>(emptyList()); private set
    var totalListeningSeconds by mutableStateOf(0.0); private set
    /** Lápides de playlists apagadas (backup da biblioteca). */
    var deletedPlaylists by mutableStateOf<List<DeletedPlaylist>>(emptyList()); private set

    // Preferências
    var visualizerStyle by Saved(VisualizerStyle.ARES)
    var soundProfile by Saved(SoundProfile.NATURAL)
    var animatedArtEnabled by Saved(true)
    var autoTranslateLyrics by Saved(false)
    var customEQGains by Saved(listOf(0f, 0f, 0f, 0f, 0f))
    var crossfadeSeconds by Saved(0.0)
    var offlineMode by Saved(false)
    var autoDownloadFavorites by Saved(false)
    var turntableFinish by Saved(TurntableFinish.OBSIDIAN)
    var vinylEdition by Saved(VinylEdition.CLASSIC_BLACK)
    var turntable3D by Saved(true)
    var cassetteStyle by Saved(CassetteStyle.SMOKED_STUDIO)
    var introEnabled by Saved(true)
    var playerSurface by Saved(PlayerSurfaceTab.ARTWORK)
    var lyricsFontScale by Saved(1f)
    /** Arte da tela de bloqueio: Automático (segue o palco), Capa, Vinil ou Fita K7. */
    var lockArtStyle by Saved(LockArtStyle.AUTOMATIC)

    /** Estilo efetivo: no Automático, K7 se o palco preferido for a fita; senão vinil (igual ao iOS). */
    val resolvedLockArtStyle: LockArtStyle
        get() = if (lockArtStyle != LockArtStyle.AUTOMATIC) lockArtStyle
        else if (playerSurface == PlayerSurfaceTab.CASSETTE) LockArtStyle.CASSETTE else LockArtStyle.VINYL

    private val storeFile get() = File(File(appContext.filesDir, "LumeMusic").also { it.mkdirs() }, "library_v1.json")
    val offlineDir: File get() = File(appContext.filesDir, "OfflineAudio").also { it.mkdirs() }

    fun init(context: Context) {
        if (ready) return
        appContext = context.applicationContext
        load()
        reconcileOfflineFiles()
        ready = true
    }

    // ---------- Arquivos offline ----------

    private fun safeName(id: String) = id.replace(Regex("[^A-Za-z0-9_-]"), "_")

    fun localAudioFile(trackId: String): File {
        val mp4 = File(offlineDir, "${safeName(trackId)}.mp4")
        if (mp4.exists()) return mp4
        val m4a = File(offlineDir, "${safeName(trackId)}.m4a")
        if (m4a.exists()) return m4a
        return mp4
    }

    fun removeDownload(trackId: String) {
        val base = safeName(trackId)
        File(offlineDir, "$base.mp4").delete()
        File(offlineDir, "$base.m4a").delete()
        downloadedIds = downloadedIds - trackId
        save()
    }

    fun isDownloaded(trackId: String): Boolean = trackId in downloadedIds && localAudioFile(trackId).exists()

    fun removeAllDownloads() {
        for (id in downloadedIds) {
            val base = safeName(id)
            File(offlineDir, "$base.mp4").delete()
            File(offlineDir, "$base.m4a").delete()
        }
        downloadedIds = emptySet()
        save()
    }

    fun fileSizeBytes(trackId: String): Long = localAudioFile(trackId).takeIf { it.exists() }?.length() ?: 0L

    fun fileSizeFormatted(trackId: String): String {
        val bytes = fileSizeBytes(trackId)
        if (bytes <= 0) return ""
        return "%.1f MB".format(bytes / (1024.0 * 1024.0))
    }

    val offlineStorageFormatted: String
        get() {
            val total = offlineDir.listFiles()?.sumOf { it.length() } ?: 0L
            val mb = total / (1024.0 * 1024.0)
            return if (mb >= 1024) "%.2f GB".format(mb / 1024.0) else "%.1f MB".format(mb)
        }

    private fun reconcileOfflineFiles() {
        val valid = downloadedIds.filter { localAudioFile(it).exists() }.toSet()
        if (valid.size != downloadedIds.size) { downloadedIds = valid; save() }
    }

    // ---------- Faixas ----------

    fun register(track: Track) {
        val existing = tracksById[track.id]
        if (existing == null) {
            tracksById = tracksById + (track.id to track)
            return
        }
        var e = existing
        if (e.videoId == null && track.videoId != null) e = e.copy(videoId = track.videoId)
        if (e.artworkURL.isEmpty() && track.artworkURL.isNotEmpty()) e = e.copy(artworkURL = track.artworkURL)
        if (e.animatedArtworkURL == null && track.animatedArtworkURL != null) e = e.copy(animatedArtworkURL = track.animatedArtworkURL)
        if (e.duration <= 0 && track.duration > 0) e = e.copy(duration = track.duration)
        if (e.album.isEmpty() && track.album.isNotEmpty()) e = e.copy(album = track.album)
        if (e != existing) tracksById = tracksById + (track.id to e)
    }

    fun registerAll(tracks: List<Track>) {
        if (tracks.isEmpty()) return
        val m = tracksById.toMutableMap()
        for (t in tracks) {
            val ex = m[t.id]
            if (ex == null) m[t.id] = t
            else {
                var e = ex
                if (e.videoId == null && t.videoId != null) e = e.copy(videoId = t.videoId)
                if (e.artworkURL.isEmpty() && t.artworkURL.isNotEmpty()) e = e.copy(artworkURL = t.artworkURL)
                if (e.duration <= 0 && t.duration > 0) e = e.copy(duration = t.duration)
                if (e.album.isEmpty() && t.album.isNotEmpty()) e = e.copy(album = t.album)
                m[t.id] = e
            }
        }
        tracksById = m
    }

    fun updateVideoId(videoId: String, trackId: String) {
        val tr = tracksById[trackId] ?: return
        tracksById = tracksById + (trackId to tr.copy(videoId = videoId)); save()
    }

    fun updateAnimatedArt(url: String, trackId: String) {
        val tr = tracksById[trackId] ?: return
        tracksById = tracksById + (trackId to tr.copy(animatedArtworkURL = url)); save()
    }

    fun updateArtwork(url: String, trackId: String) {
        val tr = tracksById[trackId] ?: return
        if (tr.artworkURL == url) return
        tracksById = tracksById + (trackId to tr.copy(artworkURL = url)); save()
    }

    fun isFavorite(trackId: String) = trackId in favoriteIds

    fun toggleFavorite(track: Track) {
        register(track)
        if (track.id in favoriteIds) {
            favoriteIds = favoriteIds - track.id
        } else {
            favoriteIds = listOf(track.id) + favoriteIds
            Haptics.success()
            if (autoDownloadFavorites && !isDownloaded(track.id)) DownloadManager.download(track)
        }
        save(); LibraryBackup.markChanged()
    }

    fun recordPlay(track: Track) {
        register(track)
        recentIds = (listOf(track.id) + recentIds.filter { it != track.id }).take(120)
        playCounts = playCounts + (track.id to ((playCounts[track.id] ?: 0) + 1))
        totalListeningSeconds += if (track.duration > 0) track.duration else 195.0
        save()
    }

    val effectiveEQGains: List<Float> get() = if (soundProfile == SoundProfile.CUSTOM) customEQGains else soundProfile.defaultGains

    // ---------- Álbuns salvos ----------

    fun isAlbumSaved(id: String) = savedAlbums.any { it.id == id }

    fun toggleSaveAlbum(album: AlbumShowcase, tracks: List<Track> = emptyList()) {
        if (isAlbumSaved(album.id)) {
            savedAlbums = savedAlbums.filter { it.id != album.id }
        } else {
            var copy = album
            if (copy.tracks.isEmpty() && tracks.isNotEmpty()) copy = copy.copy(tracks = tracks)
            registerAll(copy.tracks)
            savedAlbums = listOf(copy) + savedAlbums
            Haptics.success()
        }
        save()
    }

    // ---------- Playlists ----------

    fun createPlaylist(
        name: String, subtitle: String = "", sourceBadge: String = "Lume", artworkURL: String = "", tracks: List<Track> = emptyList(),
    ): MusicPlaylist {
        registerAll(tracks)
        val ids = tracks.map { it.id }.distinct()
        val cover = artworkURL.ifEmpty { tracks.firstOrNull { it.artworkURL.isNotEmpty() }?.artworkURL ?: "" }
        val now = System.currentTimeMillis()
        val pl = MusicPlaylist(name = name, subtitle = subtitle, artworkURL = cover, trackIds = ids, sourceBadge = sourceBadge, createdAt = now, updatedAt = now)
        playlists = listOf(pl) + playlists
        deletedPlaylists = deletedPlaylists.filter { it.id != pl.id }
        save(); LibraryBackup.markChanged()
        return pl
    }

    fun addTrack(track: Track, playlistId: String) {
        register(track)
        val idx = playlists.indexOfFirst { it.id == playlistId }
        if (idx < 0) return
        val pl = playlists[idx]
        if (track.id in pl.trackIds) return
        val updated = pl.copy(
            trackIds = pl.trackIds + track.id,
            artworkURL = if (pl.artworkURL.isEmpty() && track.artworkURL.isNotEmpty()) track.artworkURL else pl.artworkURL,
            updatedAt = System.currentTimeMillis(),
        )
        playlists = playlists.toMutableList().also { it[idx] = updated }
        save(); LibraryBackup.markChanged()
    }

    fun removeTrack(trackId: String, playlistId: String) {
        playlists = playlists.map { if (it.id == playlistId) it.copy(trackIds = it.trackIds.filter { t -> t != trackId }, updatedAt = System.currentTimeMillis()) else it }
        save(); LibraryBackup.markChanged()
    }

    fun deletePlaylist(playlistId: String) {
        if (playlists.none { it.id == playlistId }) return
        playlists = playlists.filter { it.id != playlistId }
        deletedPlaylists = (deletedPlaylists.filter { it.id != playlistId } + DeletedPlaylist(playlistId, System.currentTimeMillis())).takeLast(500)
        save(); LibraryBackup.markChanged()
    }

    fun renamePlaylist(playlistId: String, name: String) {
        playlists = playlists.map { if (it.id == playlistId) it.copy(name = name, updatedAt = System.currentTimeMillis()) else it }
        save(); LibraryBackup.markChanged()
    }

    fun reorderPlaylist(playlistId: String, from: Int, to: Int) {
        playlists = playlists.map {
            if (it.id != playlistId) it else {
                val ids = it.trackIds.toMutableList()
                if (from !in ids.indices) return@map it
                val item = ids.removeAt(from)
                ids.add(to.coerceIn(0, ids.size), item)
                it.copy(trackIds = ids, updatedAt = System.currentTimeMillis())
            }
        }
        save(); LibraryBackup.markChanged()
    }

    fun markDownloaded(track: Track) {
        register(track)
        downloadedIds = downloadedIds + track.id
        save()
    }

    // ---------- Backup da biblioteca (contrato 5.2 A) ----------

    private fun videoIdOf(t: Track): String? = t.videoId?.takeIf { it.isNotBlank() }

    private fun lbTrack(t: Track, vid: String) = LbTrack(
        videoId = vid, title = t.title, artist = t.artist, album = t.album.ifEmpty { null },
        durationSec = if (t.duration > 0) Math.round(t.duration).toInt() else null, artworkUrl = t.artworkURL.ifEmpty { null },
    )

    /** Biblioteca no formato LibraryV1. Faixas sem videoId (arquivos do aparelho) não entram. */
    fun exportLibrary(): LibraryV1 {
        fun tracksOf(ids: List<String>): List<LbTrack> {
            val seen = HashSet<String>()
            return ids.mapNotNull { id -> tracksById[id]?.let { t -> videoIdOf(t)?.takeIf { seen.add(it) }?.let { vid -> lbTrack(t, vid) } } }
        }
        return LibraryV1(
            exportedAt = System.currentTimeMillis(), platform = "android", app = com.adriano.lumemusic.access.AccessConfig.APP_VERSION,
            playlists = playlists.map { LbPlaylist(it.id, it.name, it.createdAt, it.lastChange, tracksOf(it.trackIds)) },
            liked = tracksOf(favoriteIds),
            followed = followedArtists,
            deletedPlaylists = deletedPlaylists.map { LbDeleted(it.id, it.at) },
        )
    }

    /**
     * Aplica uma biblioteca JÁ MESCLADA (LibraryMerge) sem apagar nada local: faixas sem videoId continuam nas playlists,
     * a ordem local é mantida e o que vem de fora entra no fim. Devolve true se algo mudou.
     */
    fun applyMerged(m: LibraryV1): Boolean {
        val before = listOf(playlists, favoriteIds, followedArtists, deletedPlaylists)
        val byVid = HashMap<String, String>()
        for (t in tracksById.values) videoIdOf(t)?.let { byVid.putIfAbsent(it, t.id) }
        fun localId(lt: LbTrack): String {
            byVid[lt.videoId]?.let { return it }
            if (tracksById.containsKey(lt.videoId)) { byVid[lt.videoId] = lt.videoId; return lt.videoId }
            val t = newTrack(
                videoId = lt.videoId, title = lt.title, artist = lt.artist, album = lt.album ?: "",
                duration = (lt.durationSec ?: 0).toDouble(), artworkURL = lt.artworkUrl ?: "",
            )
            register(t); byVid[lt.videoId] = t.id
            return t.id
        }
        fun cover(ids: List<String>) = ids.firstNotNullOfOrNull { tracksById[it]?.artworkURL?.takeIf { u -> u.isNotEmpty() } } ?: ""

        val mergedById = m.playlists.associateBy { it.id }
        val localIds = playlists.map { it.id }.toSet()
        val out = ArrayList<MusicPlaylist>()
        for (lp in playlists) {
            val mp = mergedById[lp.id] ?: continue   // apagada por lápide mais nova
            if (mp.updated > lp.lastChange) {
                val keepLocal = lp.trackIds.filter { id -> tracksById[id]?.let { videoIdOf(it) == null } ?: false }
                val ids = (mp.tracks.map(::localId) + keepLocal).distinct()
                out += lp.copy(name = mp.name.ifEmpty { lp.name }, trackIds = ids, createdAt = mp.created.takeIf { it > 0 } ?: lp.createdAt,
                    updatedAt = mp.updated, artworkURL = lp.artworkURL.ifEmpty { cover(ids) })
            } else out += lp
        }
        for (mp in m.playlists) if (mp.id !in localIds) {
            val ids = mp.tracks.map(::localId).distinct()
            out += MusicPlaylist(id = mp.id, name = mp.name.ifEmpty { "Playlist" }, artworkURL = cover(ids), trackIds = ids,
                createdAt = mp.created.takeIf { it > 0 } ?: mp.updated, updatedAt = mp.updated)
        }
        playlists = out
        deletedPlaylists = m.deletedPlaylists.map { DeletedPlaylist(it.id, it.at) }.takeLast(500)

        val fav = favoriteIds.toMutableList(); val favSet = fav.toHashSet()
        for (lt in m.liked) { val id = localId(lt); if (favSet.add(id)) fav.add(id) }
        favoriteIds = fav

        val fol = followedArtists.toMutableList()
        for (f in m.followed) if (fol.none { it.equals(f, ignoreCase = true) }) fol.add(f)
        followedArtists = fol

        val changed = before != listOf(playlists, favoriteIds, followedArtists, deletedPlaylists)
        if (changed) save()
        return changed
    }

    // ---------- Artistas ----------

    fun isFollowing(artist: String) = followedArtists.any { it.equals(artist, ignoreCase = true) }

    fun toggleFollow(artist: String) {
        val clean = artist.trim()
        if (clean.isEmpty()) return
        if (isFollowing(clean)) followedArtists = followedArtists.filter { !it.equals(clean, ignoreCase = true) }
        else { followedArtists = listOf(clean) + followedArtists; Haptics.success() }
        save(); LibraryBackup.markChanged()
    }

    fun markReleasesSeen(ids: Collection<String>) { seenReleaseIds = seenReleaseIds + ids; save() }

    fun addSearchTerm(q: String) {
        val clean = q.trim()
        if (clean.isEmpty()) return
        searchHistory = (listOf(clean) + searchHistory.filter { !it.equals(clean, ignoreCase = true) }).take(12)
        save()
    }

    fun clearSearchHistory() { searchHistory = emptyList(); save() }

    fun clearListeningHistory() { recentIds = emptyList(); playCounts = emptyMap(); totalListeningSeconds = 0.0; save() }

    // ---------- Derivados ----------

    val favoriteTracks: List<Track> get() = favoriteIds.mapNotNull { tracksById[it] }
    val recentTracks: List<Track> get() = recentIds.mapNotNull { tracksById[it] }
    val downloadedTracks: List<Track>
        get() = downloadedIds.mapNotNull { if (isDownloaded(it)) tracksById[it] else null }
            .sortedBy { it.title.lowercase() }

    fun tracks(playlist: MusicPlaylist): List<Track> = playlist.trackIds.mapNotNull { tracksById[it] }

    val mostPlayedTracks: List<Track>
        get() = playCounts.entries.sortedByDescending { it.value }.mapNotNull { tracksById[it.key] }

    val replaySummary: ReplaySummary
        get() {
            val totalPlays = playCounts.values.sum()
            val mins = maxOf(Math.round(totalListeningSeconds / 60.0).toInt(), totalPlays * 3)
            val topTracks = playCounts.entries.sortedByDescending { it.value }
                .mapNotNull { e -> tracksById[e.key]?.let { it to e.value } }.take(10)
            val score = HashMap<String, Pair<String, Int>>()
            for ((id, n) in playCounts) {
                val t = tracksById[id] ?: continue
                val main = mainArtist(t.artist)
                if (main.isEmpty() || main == "Artista") continue
                val key = main.lowercase()
                score[key] = main to ((score[key]?.second ?: 0) + n)
            }
            val topArtists = score.values.sortedByDescending { it.second }.take(10)
            return ReplaySummary(totalPlays, mins, playCounts.size, score.size, topTracks, topArtists)
        }

    val topListenedArtists: List<String>
        get() {
            val score = HashMap<String, Int>()
            val display = HashMap<String, String>()
            for ((id, n) in playCounts) {
                val t = tracksById[id] ?: continue
                val main = mainArtist(t.artist)
                if (main.isEmpty() || main == "Artista") continue
                score[main.lowercase()] = (score[main.lowercase()] ?: 0) + n
                display[main.lowercase()] = main
            }
            for (id in favoriteIds) {
                val t = tracksById[id] ?: continue
                val main = mainArtist(t.artist)
                if (main.isEmpty() || main == "Artista") continue
                score[main.lowercase()] = (score[main.lowercase()] ?: 0) + 2
                display[main.lowercase()] = main
            }
            val ranked = score.entries.sortedByDescending { it.value }.mapNotNull { display[it.key] }
            val out = followedArtists.toMutableList()
            for (a in ranked) if (out.none { it.equals(a, ignoreCase = true) }) out.add(a)
            return out
        }

    private val mainArtistSeps = listOf(",", " feat", " ft.", " x ", " part.", " (", " com ")

    fun mainArtist(s: String): String {
        var out = s
        for (sep in mainArtistSeps) {
            val i = out.indexOf(sep, ignoreCase = true)
            if (i >= 0) out = out.substring(0, i)
        }
        return out.replace(" - Topic", "").trim()
    }

    // ---------- Persistência ----------

    private fun load() {
        try {
            if (!storeFile.exists()) return
            val snap = LumeJsonLib.decode(storeFile.readText())
            tracksById = snap.tracksById
            favoriteIds = snap.favoriteIds
            recentIds = snap.recentIds
            playlists = snap.playlists
            downloadedIds = snap.downloadedIds.toSet()
            searchHistory = snap.searchHistory
            visualizerStyle = VisualizerStyle.fromRaw(snap.visualizerStyle)
            soundProfile = SoundProfile.fromRaw(snap.soundProfile)
            animatedArtEnabled = snap.animatedArtEnabled
            autoTranslateLyrics = snap.autoTranslateLyrics
            followedArtists = snap.followedArtists
            playCounts = snap.playCounts
            seenReleaseIds = snap.seenReleaseIds.toSet()
            savedAlbums = snap.savedAlbums
            customEQGains = snap.customEQGains.let { if (it.size == 5) it else listOf(0f, 0f, 0f, 0f, 0f) }
            crossfadeSeconds = snap.crossfadeSeconds
            offlineMode = snap.offlineMode
            autoDownloadFavorites = snap.autoDownloadFavorites
            totalListeningSeconds = snap.totalListeningSeconds
            turntableFinish = TurntableFinish.fromRaw(snap.turntableFinish)
            vinylEdition = VinylEdition.fromRaw(snap.vinylEdition)
            turntable3D = snap.turntable3D
            cassetteStyle = CassetteStyle.fromRaw(snap.cassetteStyle)
            introEnabled = snap.introEnabled
            playerSurface = PlayerSurfaceTab.fromRaw(snap.playerSurface)
            lyricsFontScale = snap.lyricsFontScale
            lockArtStyle = LockArtStyle.fromRaw(snap.lockArtStyle)
            deletedPlaylists = snap.deletedPlaylists
        } catch (_: Exception) {}
    }

    /** Salva com debounce de 160 ms (como no iOS). Preferências chamam save() direto das telas. */
    fun save() {
        if (!ready) return
        val snap = Snapshot(
            tracksById, favoriteIds, recentIds, playlists, downloadedIds.toList(), searchHistory,
            visualizerStyle.raw, soundProfile.raw, animatedArtEnabled, autoTranslateLyrics, followedArtists, playCounts,
            seenReleaseIds.toList(), savedAlbums, customEQGains, crossfadeSeconds, offlineMode, autoDownloadFavorites,
            totalListeningSeconds, turntableFinish.raw, vinylEdition.raw, turntable3D, cassetteStyle.raw, introEnabled,
            playerSurface.raw, lyricsFontScale, lockArtStyle.raw, deletedPlaylists,
        )
        saveJob?.cancel()
        saveJob = scope.launch {
            delay(160)
            try {
                val tmp = File(storeFile.parentFile, "library_v1.json.tmp")
                tmp.writeText(LumeJsonLib.encode(snap))
                tmp.renameTo(storeFile)
            } catch (_: Exception) {}
        }
    }

    private object LumeJsonLib {
        fun decode(s: String): Snapshot = com.adriano.lumemusic.engine.LumeJson.decodeFromString(Snapshot.serializer(), s)
        fun encode(s: Snapshot): String = com.adriano.lumemusic.engine.LumeJson.encodeToString(Snapshot.serializer(), s)
    }
}
