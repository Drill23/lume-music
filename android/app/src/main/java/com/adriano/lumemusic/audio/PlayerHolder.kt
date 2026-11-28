package com.adriano.lumemusic.audio

import android.content.Context
import android.net.Uri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import com.adriano.lumemusic.data.LibraryStore
import com.adriano.lumemusic.data.Track
import com.adriano.lumemusic.engine.DiscNet
import com.adriano.lumemusic.engine.InnerTube
import com.adriano.lumemusic.engine.MusicEngine
import kotlinx.coroutines.runBlocking
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap

/** Resolve "lume://stream/<trackId>" para a URL real do áudio no momento em que o ExoPlayer abre a fonte. */
object StreamResolver {
    const val SCHEME = "lume"
    val tracks = ConcurrentHashMap<String, Track>()
    @Volatile var lastError: String? = null
    var onResolved: ((trackId: String, videoId: String, bitrate: Int, itag: Int, loudnessDb: Double?) -> Unit)? = null

    fun uriFor(track: Track): Uri { tracks[track.id] = track; return Uri.parse("$SCHEME://stream/${Uri.encode(track.id)}") }

    @Throws(IOException::class)
    fun resolve(trackId: String): String {
        val t = tracks[trackId] ?: throw IOException("Faixa desconhecida")
        lastError = null
        return runBlocking {
            val vid = MusicEngine.resolveVideoId(t) ?: run { lastError = "Áudio não encontrado para ${t.title}."; throw IOException(lastError) }
            val rs = MusicEngine.resolveStream(vid) ?: run { lastError = "Não foi possível conectar ao stream de áudio."; throw IOException(lastError) }
            onResolved?.invoke(trackId, vid, rs.bitrate, rs.itag, rs.loudnessDb)
            rs.url
        }
    }
}

/** Dono do ExoPlayer único (processo todo) + processador de áudio (EQ/FFT). */
object PlayerHolder {
    lateinit var player: ExoPlayer; private set
    val processor = LumeAudioProcessor()
    private var ready = false

    fun init(context: Context) {
        if (ready) return
        val app = context.applicationContext
        val renderers = object : DefaultRenderersFactory(app) {
            override fun buildAudioSink(context: Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean): AudioSink =
                DefaultAudioSink.Builder(context)
                    .setEnableFloatOutput(false)
                    .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                    .setAudioProcessors(arrayOf(processor))
                    .build()
        }.setEnableDecoderFallback(true)

        // callTimeout(0): o áudio é lido em streaming por minutos; só o timeout de leitura vale.
        val streamClient = DiscNet.client.newBuilder().callTimeout(0, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(25, java.util.concurrent.TimeUnit.SECONDS).build()
        val http = OkHttpDataSource.Factory(streamClient).setUserAgent(InnerTube.ANDROID_UA)
        val base: DataSource.Factory = DefaultDataSource.Factory(app, http)
        val resolving = ResolvingDataSource.Factory(base) { spec: DataSpec ->
            var out = spec
            if (spec.uri.scheme == StreamResolver.SCHEME) {
                val id = Uri.decode(spec.uri.lastPathSegment ?: "")
                out = spec.withUri(Uri.parse(StreamResolver.resolve(id)))
                // Sem cabeçalho Range o YouTube estrangula o áudio puro; "bytes=0-" libera a velocidade total.
                if (spec.position == 0L && spec.length == C.LENGTH_UNSET.toLong()) {
                    out = out.withAdditionalHeaders(mapOf("Range" to "bytes=0-"))
                }
            }
            out
        }

        player = ExoPlayer.Builder(app, renderers)
            .setMediaSourceFactory(DefaultMediaSourceFactory(resolving))
            .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(), true)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, true).build()
        player.repeatMode = Player.REPEAT_MODE_OFF
        AudioSpectrum.attach(processor)
        AudioSpectrum.setEQGains(LibraryStore.effectiveEQGains)
        ready = true
    }
}
