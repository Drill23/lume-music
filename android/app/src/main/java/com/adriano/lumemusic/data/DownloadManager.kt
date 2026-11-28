package com.adriano.lumemusic.data

import android.content.Context
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.adriano.lumemusic.engine.DiscNet
import com.adriano.lumemusic.engine.LyricsService
import com.adriano.lumemusic.engine.MusicEngine
import com.adriano.lumemusic.platform.DownloadService
import com.adriano.lumemusic.platform.Haptics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.io.File
import kotlin.coroutines.coroutineContext

sealed class DownloadState {
    data object Queued : DownloadState()
    data object Resolving : DownloadState()
    data class Downloading(val progress: Double) : DownloadState()
    data class Failed(val reason: String) : DownloadState()

    val fraction: Double
        get() = when (this) { Queued -> 0.02; Resolving -> 0.14; is Downloading -> progress; is Failed -> 0.0 }
    val isActive: Boolean get() = this !is Failed
}

/** Downloads offline: fila de até 2 simultâneos, pausa/retomada, prefetch de capa e letra. */
object DownloadManager {
    private lateinit var appContext: Context
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private const val MAX_CONCURRENT = 2

    val progressById = mutableStateMapOf<String, Double>()
    val statesById = mutableStateMapOf<String, DownloadState>()
    var activeCount by mutableStateOf(0); private set
    var paused by mutableStateOf(false); private set
    var lastMessage by mutableStateOf<String?>(null)

    private val queued = ArrayList<Track>()
    private val active = HashMap<String, Job>()
    private val failed = LinkedHashMap<String, Track>()

    fun init(context: Context) {
        appContext = context.applicationContext
        com.adriano.lumemusic.audio.LoudnessStore.init(appContext)
    }

    val pendingCount: Int get() = active.size + queued.size

    val failedItems: List<Pair<Track, String>>
        get() = failed.values.mapNotNull { tr ->
            (statesById[tr.id] as? DownloadState.Failed)?.let { tr to it.reason }
        }.sortedBy { it.first.title.lowercase() }

    val overallProgress: Double
        get() {
            val act = statesById.values.filter { it.isActive }
            if (act.isEmpty()) return 0.0
            return act.sumOf { it.fraction } / act.size
        }

    fun isDownloading(trackId: String) = statesById[trackId]?.isActive == true

    fun download(track: Track) {
        if (LibraryStore.isDownloaded(track.id) || statesById[track.id]?.isActive == true) return
        enqueue(track)
        refreshCounts(); pumpQueue()
    }

    fun downloadBatch(tracks: List<Track>) {
        tracks.filter { !LibraryStore.isDownloaded(it.id) && statesById[it.id]?.isActive != true }.forEach { enqueue(it) }
        refreshCounts(); pumpQueue()
    }

    fun downloadPlaylist(playlist: MusicPlaylist) = downloadBatch(LibraryStore.tracks(playlist))

    private fun enqueue(t: Track) {
        LibraryStore.register(t)
        failed.remove(t.id)
        statesById[t.id] = DownloadState.Queued
        progressById[t.id] = 0.02
        if (queued.none { it.id == t.id }) queued.add(t)
    }

    fun retry(trackId: String) {
        val tr = failed[trackId] ?: LibraryStore.tracksById[trackId] ?: return
        failed.remove(trackId)
        statesById.remove(trackId)
        download(tr)
    }

    fun retryAllFailed() { for (t in failed.values.toList()) retry(t.id) }

    fun togglePauseAll() {
        paused = !paused
        if (paused) {
            for ((id, job) in active.toMap()) {
                job.cancel()
                LibraryStore.tracksById[id]?.let {
                    queued.add(0, it)
                    statesById[id] = DownloadState.Queued
                    progressById[id] = 0.02
                }
            }
            active.clear()
            refreshCounts()
        } else pumpQueue()
    }

    fun cancel(trackId: String) {
        active.remove(trackId)?.cancel()
        queued.removeAll { it.id == trackId }
        failed.remove(trackId)
        statesById.remove(trackId)
        progressById.remove(trackId)
        refreshCounts(); pumpQueue()
    }

    fun cancelAll() {
        active.values.forEach { it.cancel() }
        active.clear(); queued.clear(); failed.clear()
        statesById.clear(); progressById.clear()
        paused = false
        refreshCounts()
    }

    private fun refreshCounts() {
        activeCount = active.size + queued.size
        if (::appContext.isInitialized) DownloadService.sync(appContext, activeCount > 0 && !paused)
    }

    private fun pumpQueue() {
        if (paused) return
        while (active.size < MAX_CONCURRENT && queued.isNotEmpty()) {
            val next = queued.removeAt(0)
            if (LibraryStore.isDownloaded(next.id)) {
                statesById.remove(next.id); progressById.remove(next.id); continue
            }
            startTask(next)
        }
        refreshCounts()
    }

    private fun startTask(track: Track) {
        statesById[track.id] = DownloadState.Resolving
        progressById[track.id] = 0.08
        val job = scope.launch {
            try {
                val vid = MusicEngine.resolveVideoId(track)
                if (vid == null) { markFailed(track, "Áudio não localizado"); return@launch }
                ensureActive()
                val working = track.copy(videoId = vid)
                LibraryStore.updateVideoId(vid, track.id)
                statesById[track.id] = DownloadState.Resolving; progressById[track.id] = 0.16
                val resolved = MusicEngine.resolveStream(vid)
                if (resolved == null) { markFailed(working, "Stream indisponível"); return@launch }
                ensureActive()
                // Guarda a sonoridade para o "Volume igual" valer também offline.
                resolved.loudnessDb?.let { com.adriano.lumemusic.audio.LoudnessStore.put(track.id, it) }
                statesById[track.id] = DownloadState.Downloading(0.20); progressById[track.id] = 0.20

                val dest = LibraryStore.localAudioFile(track.id)
                val part = File(dest.parentFile, dest.nameWithoutExtension + ".part")
                val bytes = try {
                    withContext(Dispatchers.IO) { fetchToFile(resolved.url, resolved.headers, part) { f ->
                        val p = minOf(0.96, 0.20 + 0.76 * f)
                        scope.launch { if (statesById[track.id]?.isActive == true) { statesById[track.id] = DownloadState.Downloading(p); progressById[track.id] = p } }
                    } }
                } catch (e: kotlinx.coroutines.CancellationException) {
                    withContext(Dispatchers.IO) { part.delete() }
                    throw e
                } catch (_: Exception) {
                    withContext(Dispatchers.IO) { part.delete() }
                    markFailed(working, "Falha de rede"); return@launch
                }
                if (bytes <= 32768) {
                    withContext(Dispatchers.IO) { part.delete() }
                    markFailed(working, "Arquivo incompleto"); return@launch
                }

                if (statesById[track.id]?.isActive == true) {
                    statesById[track.id] = DownloadState.Downloading(0.98)
                    progressById[track.id] = 0.98
                }

                // Só áudio: tira a faixa de vídeo do MP4 (remux sem recodificar; se não houver vídeo, move para .m4a)
                val finalFile = withContext(Dispatchers.IO) {
                    val m4a = File(dest.parentFile, dest.nameWithoutExtension + ".m4a")
                    val mp4 = File(dest.parentFile, dest.nameWithoutExtension + ".mp4")
                    val stripped = AudioRemux.stripVideoTrack(part)
                    if (stripped != part && stripped.exists() && stripped.length() > 32768) {
                        part.delete()
                        if (stripped != mp4) mp4.delete()
                        stripped
                    } else {
                        m4a.delete()
                        mp4.delete()
                        if (part.renameTo(m4a)) m4a else part
                    }
                }
                val finalSize = withContext(Dispatchers.IO) { finalFile.length() }

                LibraryStore.markDownloaded(working, finalSize)
                statesById.remove(track.id); progressById.remove(track.id); failed.remove(track.id)
                Haptics.success()
                lastMessage = "Baixada offline: ${track.title}"

                // Prefetch de letra em segundo plano (nunca trava o progresso em 95–99%)
                scope.launch(Dispatchers.IO) {
                    try { LyricsService.fetchLyrics(working) } catch (_: Exception) {}
                }
            } finally {
                active.remove(track.id)
                refreshCounts(); pumpQueue()
            }
        }
        active[track.id] = job
        refreshCounts()
    }

    private suspend fun fetchToFile(url: String, headers: Map<String, String>, part: File, onProgress: (Double) -> Unit): Long {
        val rb = Request.Builder().url(url)
        for ((k, v) in headers) rb.header(k, v)
        // Sem cabeçalho Range o YouTube estrangula o áudio puro (itag 140); com "bytes=0-" vem em velocidade total.
        rb.header("Range", "bytes=0-")
        val client = DiscNet.client.newBuilder()
            .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS).callTimeout(0, java.util.concurrent.TimeUnit.SECONDS).build()
        val call = client.newCall(rb.build())
        val cancelHandle = coroutineContext[Job]?.invokeOnCompletion { if (it != null) call.cancel() }
        try {
            call.execute().use { resp ->
                if (!resp.isSuccessful) throw java.io.IOException("HTTP ${resp.code}")
                val body = resp.body ?: throw java.io.IOException("sem corpo")
                val total = body.contentLength()
                var written = 0L
                var lastReport = 0L
                part.outputStream().use { out ->
                    body.byteStream().use { input ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            coroutineContext.ensureActive()
                            val n = input.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            written += n
                            val now = System.nanoTime()
                            if (total > 0 && now - lastReport > 150_000_000L) { lastReport = now; onProgress(written.toDouble() / total) }
                        }
                    }
                }
                if (total > 0 && written < total) { part.delete(); throw java.io.IOException("incompleto") }
                return written
            }
        } finally {
            cancelHandle?.dispose()
        }
    }

    private fun markFailed(track: Track, reason: String) {
        progressById.remove(track.id)
        statesById[track.id] = DownloadState.Failed(reason)
        failed[track.id] = track
        lastMessage = "Erro ao baixar ${track.title}: $reason"
    }
}
