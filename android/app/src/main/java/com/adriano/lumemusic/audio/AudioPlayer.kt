package com.adriano.lumemusic.audio

import android.app.Application
import android.content.ComponentName
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import androidx.core.net.toUri
import com.adriano.lumemusic.data.ArtworkStore
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.LyricsBundle
import com.adriano.lumemusic.data.RepeatMode
import com.adriano.lumemusic.data.SleepTimerOption
import com.adriano.lumemusic.data.SoundProfile
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.LyricsService
import com.adriano.lumemusic.engine.MusicEngine
import com.adriano.lumemusic.platform.Haptics
import com.adriano.lumemusic.ui.AppModel
import com.adriano.lumemusic.ui.theme.ArtworkColors
import com.adriano.lumemusic.ui.theme.ArtworkPalette
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import kotlin.math.abs
import kotlin.random.Random

/** Relógio isolado de reprodução: só as telas que mostram o tempo recompõem. */
object PlaybackClock {
    var currentTime by mutableDoubleStateOf(0.0)
    var duration by mutableDoubleStateOf(0.0)
}

/**
 * Controlador principal de reprodução (porta de AudioPlayer.swift): fila, aleatório, repetir, crossfade,
 * EQ, velocidade, timer de dormir, rádio automático, letras sincronizadas e tela de bloqueio (MediaSession).
 * A fila é do Lume; o ExoPlayer toca um item por vez.
 */
object AudioPlayer {
    private lateinit var app: Application
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val player get() = PlayerHolder.player

    var currentTrack by mutableStateOf<Track?>(null); private set
    var queue by mutableStateOf<List<Track>>(emptyList()); private set
    var currentIndex by mutableIntStateOf(0); private set
    var isPlaying by mutableStateOf(false); private set
    var isLoading by mutableStateOf(false); private set
    var shuffleEnabled by mutableStateOf(false)
    var repeatMode by mutableStateOf(RepeatMode.OFF)
    var autoplayRadio by mutableStateOf(true)
    var playbackRate by mutableFloatStateOf(1f); private set
    var errorToast by mutableStateOf<String?>(null)

    var palette by mutableStateOf(ArtworkPalette.Fallback); private set
    var currentAnimatedArtURL by mutableStateOf<String?>(null); private set
    var lyrics by mutableStateOf<LyricsBundle?>(null); private set
    var isLoadingLyrics by mutableStateOf(false); private set
    var isTranslatingLyrics by mutableStateOf(false); private set
    var showTranslation by mutableStateOf(false)
    var currentBitrateLabel by mutableStateOf("AAC"); private set
    var currentArtwork by mutableStateOf(""); private set
    var contextTitle by mutableStateOf(""); private set

    var sleepTimerOption by mutableStateOf(SleepTimerOption.OFF); private set
    var sleepRemainingSeconds by mutableIntStateOf(0); private set
    var sessionHistory by mutableStateOf<List<Track>>(emptyList()); private set

    private var varispeed = 1f
    private var pollJob: Job? = null
    private var sleepJob: Job? = null
    private var lyricsJob: Job? = null
    private var artJob: Job? = null
    private var prefetchJob: Job? = null
    private var radioFetching = false
    private var crossfadeTriggered = false
    private var shouldFadeInNext = false
    private var retriedTrackIds = HashSet<String>()
    private var started = false

    fun init(application: Application) {
        if (started) return
        started = true
        app = application
        PlayerHolder.init(application)
        StreamResolver.onResolved = { trackId, vid, bitrate, itag ->
            scope.launch {
                LibraryStore.updateVideoId(vid, trackId)
                if (currentTrack?.id == trackId) {
                    currentTrack = currentTrack?.copy(videoId = vid)
                    val idx = queue.indexOfFirst { it.id == trackId }
                    if (idx >= 0) queue = queue.toMutableList().also { it[idx] = it[idx].copy(videoId = vid) }
                    currentBitrateLabel = if (itag == 140) "AAC · Áudio puro" else "AAC · Estéreo"
                }
            }
        }
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) { syncState(); if (state == Player.STATE_ENDED) onEnded() }
            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) { syncState() }
            override fun onIsPlayingChanged(isPlaying: Boolean) { syncState() }
            override fun onPlayerError(error: PlaybackException) { handleError(error) }
        })
        // Liga o serviço de mídia (notificação e tela de bloqueio) ao processo.
        try {
            val token = SessionToken(app, ComponentName(app, PlaybackService::class.java))
            MediaController.Builder(app, token).buildAsync()
        } catch (_: Exception) {}
        applyVolume()
    }

    // ---------------- Estado ----------------

    private fun syncState() {
        val p = player
        val playing = p.playWhenReady && (p.playbackState == Player.STATE_READY || p.playbackState == Player.STATE_BUFFERING)
        if (isPlaying != playing) isPlaying = playing
        val loading = p.playbackState == Player.STATE_BUFFERING && p.playWhenReady
        if (isLoading != loading && currentTrack != null) isLoading = loading
        if (p.isPlaying) startPolling() else if (!playing) stopPolling()
        else startPolling()
        val d = p.duration
        if (d > 1000) PlaybackClock.duration = d / 1000.0
    }

    private fun startPolling() {
        if (pollJob?.isActive == true) return
        pollJob = scope.launch {
            while (isActive) {
                tick()
                delay(150)
            }
        }
    }

    private fun stopPolling() { pollJob?.cancel(); pollJob = null; tick() }

    private fun baseVolume(): Float = if (LibraryStore.soundProfile == SoundProfile.NIGHT) 0.72f else 1f
    private fun applyVolume() { try { player.volume = baseVolume() } catch (_: Exception) {} }

    private fun tick() {
        val p = player
        if (p.mediaItemCount == 0) return
        val sec = p.currentPosition / 1000.0
        if (sec.isFinite() && sec >= 0) PlaybackClock.currentTime = sec
        val d = p.duration
        if (d > 1000) PlaybackClock.duration = d / 1000.0
        if (sleepTimerOption == SleepTimerOption.END_OF_TRACK) {
            sleepRemainingSeconds = maxOf(0, (PlaybackClock.duration - PlaybackClock.currentTime).toInt())
        }
        val xf = LibraryStore.crossfadeSeconds
        val dur = PlaybackClock.duration
        if (xf > 0 && repeatMode != RepeatMode.ONE && sleepTimerOption != SleepTimerOption.END_OF_TRACK && dur > xf + 2 && isPlaying) {
            val rem = dur - PlaybackClock.currentTime
            val base = baseVolume()
            if (rem <= xf && rem > 0) {
                p.volume = base * (rem / xf).toFloat().coerceIn(0.05f, 1f)
                if (rem <= 0.65 && !crossfadeTriggered && (currentIndex + 1 < queue.size || repeatMode == RepeatMode.ALL || autoplayRadio)) {
                    crossfadeTriggered = true
                    shouldFadeInNext = true
                    nextTrack()
                }
            } else if (!crossfadeTriggered && sleepRemainingSeconds == 0) p.volume = base
        }
    }

    // ---------------- Comandos ----------------

    fun displayArtwork(t: Track): String = ArtworkStore.url(t)

    fun play(track: Track, list: List<Track>? = null, context: String? = null) {
        if (context != null) contextTitle = context else if (list == null || list.size == 1) contextTitle = ""
        LibraryStore.register(track)
        if (!list.isNullOrEmpty()) {
            LibraryStore.registerAll(list)
            queue = list
            currentIndex = list.indexOfFirst { it.id == track.id }.coerceAtLeast(0)
        } else {
            val idx = queue.indexOfFirst { it.id == track.id }
            if (idx >= 0) currentIndex = idx else { queue = listOf(track); currentIndex = 0 }
        }
        startCurrentTrack()
    }

    fun playNextInQueue(track: Track) {
        LibraryStore.register(track)
        if (queue.isEmpty()) { play(track); return }
        val cur = currentTrack?.id
        val q = queue.toMutableList()
        q.removeAll { it.id == track.id && it.id != cur }
        val ci = q.indexOfFirst { it.id == cur }.let { if (it < 0) currentIndex else it }
        q.add(minOf(q.size, ci + 1), track)
        queue = q
        currentIndex = q.indexOfFirst { it.id == cur }.coerceAtLeast(0)
        Haptics.light()
    }

    fun addToQueue(track: Track) {
        LibraryStore.register(track)
        if (queue.isEmpty()) { play(track); return }
        if (queue.none { it.id == track.id }) queue = queue + track
        Haptics.light()
    }

    fun togglePlayPause() {
        if (player.mediaItemCount == 0) { currentTrack?.let { play(it, queue) }; return }
        Haptics.light()
        if (player.playWhenReady && player.playbackState != Player.STATE_ENDED) player.pause()
        else {
            if (player.playbackState == Player.STATE_ENDED) player.seekTo(0)
            if (player.playbackState == Player.STATE_IDLE) player.prepare()
            player.play()
        }
        syncState()
    }

    fun seek(seconds: Double) {
        val max = if (PlaybackClock.duration > 0) PlaybackClock.duration else seconds
        val c = seconds.coerceIn(0.0, max)
        PlaybackClock.currentTime = c
        player.seekTo((c * 1000).toLong())
    }

    fun nextTrack() {
        if (queue.isEmpty()) return
        Haptics.light()
        if (shuffleEnabled && queue.size > 1) {
            var n = Random.nextInt(queue.size)
            if (n == currentIndex) n = (currentIndex + 1) % queue.size
            currentIndex = n; startCurrentTrack(); return
        }
        if (currentIndex + 1 < queue.size) { currentIndex += 1; startCurrentTrack() }
        else if (repeatMode == RepeatMode.ALL) { currentIndex = 0; startCurrentTrack() }
        else if (autoplayRadio && currentTrack != null) {
            val cur = currentTrack!!
            scope.launch {
                appendRadio(cur)
                if (currentIndex + 1 < queue.size) { currentIndex += 1; startCurrentTrack() }
                else { player.pause(); syncState() }
            }
        } else { player.pause(); syncState() }
    }

    fun previousTrack() {
        Haptics.light()
        if (PlaybackClock.currentTime > 3.5) { seek(0.0); return }
        if (queue.isEmpty()) return
        if (currentIndex > 0) { currentIndex -= 1; startCurrentTrack() }
        else if (repeatMode == RepeatMode.ALL) { currentIndex = queue.size - 1; startCurrentTrack() }
        else seek(0.0)
    }

    fun startRadio(track: Track) {
        autoplayRadio = true
        play(track, listOf(track), "Rádio · ${LibraryStore.mainArtist(track.artist)}")
        AppModel.showToast("Rádio de ${track.title} ligada")
    }

    fun moveQueue(from: Int, to: Int) {
        if (from !in queue.indices) return
        val curId = currentTrack?.id
        val q = queue.toMutableList()
        val item = q.removeAt(from)
        q.add(to.coerceIn(0, q.size), item)
        queue = q
        curId?.let { id -> q.indexOfFirst { it.id == id }.takeIf { it >= 0 }?.let { currentIndex = it } }
    }

    fun removeFromQueue(index: Int) {
        if (index !in queue.indices || index == currentIndex) return
        val curId = currentTrack?.id
        queue = queue.toMutableList().also { it.removeAt(index) }
        curId?.let { id -> queue.indexOfFirst { it.id == id }.takeIf { it >= 0 }?.let { currentIndex = it } }
    }

    fun clearUpcoming() {
        val cur = currentTrack ?: return
        queue = listOf(cur); currentIndex = 0
    }

    /** Fader de pitch do toca-discos: varispeed (tempo e tom mudam juntos). */
    fun setVarispeed(rate: Float) {
        varispeed = rate
        playbackRate = rate
        player.playbackParameters = PlaybackParameters(rate, rate)
    }

    fun setRate(rate: Float) {
        varispeed = 1f
        playbackRate = rate
        player.playbackParameters = PlaybackParameters(rate, 1f)
    }

    fun reloadLyrics() {
        val track = currentTrack ?: return
        lyricsJob?.cancel()
        lyricsJob = scope.launch {
            isLoadingLyrics = true
            LyricsService.forgetMiss(track)
            val fetched = LyricsService.fetchLyrics(track)
            if (currentTrack?.id != track.id) return@launch
            lyrics = fetched; isLoadingLyrics = false
        }
    }

    fun jumpToQueueIndex(i: Int) { if (i in queue.indices) { currentIndex = i; startCurrentTrack() } }

    fun applySoundProfile(profile: SoundProfile) {
        LibraryStore.soundProfile = profile
        AudioSpectrum.setEQGains(LibraryStore.effectiveEQGains)
        applyVolume()
        Haptics.selection()
    }

    fun applyCustomEQ(gains: List<Float>) {
        LibraryStore.customEQGains = gains
        LibraryStore.soundProfile = SoundProfile.CUSTOM
        AudioSpectrum.setEQGains(gains)
    }

    // ---------------- Timer de dormir ----------------

    fun setSleepTimer(option: SleepTimerOption) {
        sleepJob?.cancel(); sleepJob = null
        sleepTimerOption = option
        when (option) {
            SleepTimerOption.OFF -> { sleepRemainingSeconds = 0; applyVolume() }
            SleepTimerOption.END_OF_TRACK -> sleepRemainingSeconds = maxOf(1, (PlaybackClock.duration - PlaybackClock.currentTime).toInt())
            else -> {
                sleepRemainingSeconds = option.minutes * 60
                sleepJob = scope.launch {
                    while (isActive) {
                        delay(1000)
                        if (sleepRemainingSeconds <= 1) {
                            sleepTimerOption = SleepTimerOption.OFF; sleepRemainingSeconds = 0
                            player.pause(); applyVolume(); syncState()
                            break
                        } else {
                            sleepRemainingSeconds -= 1
                            if (sleepRemainingSeconds <= 5) player.volume = baseVolume() * (sleepRemainingSeconds / 5f)
                        }
                    }
                }
            }
        }
        Haptics.selection()
    }

    // ---------------- Pipeline de início de faixa ----------------

    private fun buildItem(track: Track, art: String): MediaItem {
        val local = LibraryStore.isDownloaded(track.id)
        val uri = if (local) File(LibraryStore.localAudioFile(track.id).path).toUri() else StreamResolver.uriFor(track)
        val md = MediaMetadata.Builder().setTitle(track.title).setArtist(track.artist).setAlbumTitle(track.album.ifEmpty { null })
            .setArtworkUri(if (art.isNotEmpty()) art.toUri() else null).build()
        return MediaItem.Builder().setMediaId(track.id).setUri(uri).setMediaMetadata(md).build()
    }

    private fun startCurrentTrack() {
        if (currentIndex !in queue.indices) return
        val track = queue[currentIndex]
        currentTrack = track
        isLoading = true
        isPlaying = false
        PlaybackClock.currentTime = 0.0
        PlaybackClock.duration = track.duration
        errorToast = null
        lyrics = null
        showTranslation = LibraryStore.autoTranslateLyrics
        currentAnimatedArtURL = track.animatedArtworkURL
        crossfadeTriggered = false
        LibraryStore.recordPlay(track)
        sessionHistory = (listOf(track) + sessionHistory.filter { it.id != track.id }).take(40)
        lyricsJob?.cancel(); artJob?.cancel(); prefetchJob?.cancel()
        retriedTrackIds.remove(track.id)
        currentArtwork = ArtworkStore.url(track)

        // 1. Capa real + paleta ambiente + capa animada
        artJob = scope.launch {
            ArtworkStore.ensure(track)
            if (currentTrack?.id != track.id) return@launch
            val art = ArtworkStore.url(track)
            if (art != currentArtwork) currentArtwork = art
            if (art.isNotEmpty()) {
                val pal = ArtworkColors.palette(app, art)
                if (currentTrack?.id != track.id) return@launch
                palette = pal
                // atualiza capa na tela de bloqueio (troca só de metadados; não reinicia o áudio)
                try {
                    if (player.mediaItemCount > 0 && player.currentMediaItem?.mediaId == track.id) {
                        player.replaceMediaItem(0, buildItem(track, art).let { it })
                    }
                } catch (_: Exception) {}
            }
            if (LibraryStore.animatedArtEnabled && track.animatedArtworkURL == null) {
                val anim = MusicEngine.fetchAnimatedArtwork(track.title, track.artist, track.album)
                if (anim != null) {
                    LibraryStore.updateAnimatedArt(anim, track.id)
                    if (currentTrack?.id == track.id) currentAnimatedArtURL = anim
                }
            }
        }

        // 2. Letras sincronizadas
        lyricsJob = scope.launch {
            isLoadingLyrics = true
            var fetched = LyricsService.fetchLyrics(track)
            if (fetched == null && track.videoId == null) {
                for (i in 0 until 16) {
                    if (currentTrack?.id != track.id) return@launch
                    val vid = currentTrack?.videoId
                    if (vid != null) {
                        val withVid = track.copy(videoId = vid)
                        LyricsService.forgetMiss(withVid)
                        fetched = LyricsService.fetchLyrics(withVid)
                        break
                    }
                    delay(500)
                }
            }
            if (currentTrack?.id != track.id) return@launch
            lyrics = fetched
            isLoadingLyrics = false
            if (LibraryStore.autoTranslateLyrics && fetched != null) translateCurrentLyrics(fetched)
        }

        // 3. Áudio: arquivo offline ou stream (resolvido pela fonte de dados do ExoPlayer)
        if (LibraryStore.isDownloaded(track.id)) {
            currentBitrateLabel = "Offline · AAC"
        } else {
            if (LibraryStore.offlineMode) {
                isLoading = false; isPlaying = false
                errorToast = "Modo offline ativo. Baixe “${track.title}” para ouvir sem internet."
                player.pause()
                return
            }
            currentBitrateLabel = "AAC"
        }
        beginPlayback(track, 0L)
        if (autoplayRadio && queue.size - currentIndex <= 2) scope.launch { appendRadio(track) }
        scheduleNextTrackPrefetch()
    }

    private fun beginPlayback(track: Track, positionMs: Long) {
        player.setMediaItem(buildItem(track, currentArtwork), positionMs)
        player.playbackParameters = PlaybackParameters(playbackRate, if (abs(varispeed - 1f) < 0.001f) 1f else varispeed)
        val base = baseVolume()
        if (shouldFadeInNext) {
            shouldFadeInNext = false
            player.volume = base * 0.08f
            scope.launch {
                for (step in 1..10) {
                    delay(90)
                    if (currentTrack?.id != track.id) return@launch
                    player.volume = base * (step / 10f)
                }
            }
        } else player.volume = base
        player.prepare()
        player.playWhenReady = true
        syncState()
    }

    private fun handleError(error: PlaybackException) {
        val track = currentTrack ?: return
        if (!LibraryStore.isDownloaded(track.id) && track.id !in retriedTrackIds) {
            retriedTrackIds.add(track.id)
            track.videoId?.let { MusicEngine.invalidateStream(it) }
            val pos = player.currentPosition
            beginPlayback(track, pos)
            return
        }
        isLoading = false; isPlaying = false
        val msg = StreamResolver.lastError ?: (error.cause?.message ?: error.message ?: "Falha ao reproduzir esta faixa.")
        errorToast = "Erro no áudio: $msg"
    }

    private fun onEnded() {
        if (sleepTimerOption == SleepTimerOption.END_OF_TRACK) {
            sleepTimerOption = SleepTimerOption.OFF; sleepRemainingSeconds = 0; isPlaying = false; return
        }
        if (repeatMode == RepeatMode.ONE) { player.seekTo(0); player.play() } else nextTrack()
    }

    private fun scheduleNextTrackPrefetch() {
        prefetchJob?.cancel()
        val nextIdx = currentIndex + 1
        if (nextIdx >= queue.size || LibraryStore.offlineMode) return
        val next = queue[nextIdx]
        prefetchJob = scope.launch(Dispatchers.IO) {
            delay(1500)
            ArtworkStore.ensure(next)
            if (!LibraryStore.isDownloaded(next.id)) {
                MusicEngine.resolveVideoId(next)?.let { vid ->
                    launch(Dispatchers.Main) { LibraryStore.updateVideoId(vid, next.id) }
                    MusicEngine.resolveStream(vid)
                }
            }
            LyricsService.fetchLyrics(next)
        }
    }

    // ---------------- Tradução ----------------

    fun toggleTranslation() {
        Haptics.selection()
        if (showTranslation) { showTranslation = false; return }
        showTranslation = true
        val cur = lyrics ?: return
        if (cur.translatedToPT) return
        scope.launch { translateCurrentLyrics(cur) }
    }

    private suspend fun translateCurrentLyrics(bundle: LyricsBundle) {
        if (isTranslatingLyrics) return
        isTranslatingLyrics = true
        val translated = LyricsService.translateToPortuguese(bundle)
        if (lyrics?.trackKey == translated.trackKey) lyrics = translated
        isTranslatingLyrics = false
    }

    // ---------------- Rádio ----------------

    private suspend fun appendRadio(track: Track) {
        val vid = track.videoId ?: return
        if (radioFetching) return
        radioFetching = true
        try {
            val more = MusicEngine.fetchRadioQueue(vid, 18)
            val existing = queue.map { it.id }.toSet()
            val fresh = more.filter { it.id !in existing }
            if (fresh.isNotEmpty()) { LibraryStore.registerAll(fresh); queue = queue + fresh }
        } finally { radioFetching = false }
    }
}
