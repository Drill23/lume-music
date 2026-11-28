package com.adriano.lumemusic.data

import android.content.Context
import android.content.SharedPreferences
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.adriano.lumemusic.BuildConfig
import com.adriano.lumemusic.audio.AudioPlayer
import com.adriano.lumemusic.audio.PlaybackClock
import com.adriano.lumemusic.audio.PlayerHolder
import com.adriano.lumemusic.engine.DiscNet
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

/** Regra do contrato 5.2 (B): uma "ouvida" conta com metade da faixa OU 4 minutos (o que vier antes), faixa com 30 s ou mais. */
object ListenRule {
    const val MIN_TRACK_SEC = 30.0
    const val CAP_SEC = 240.0

    /** [durationSec] <= 0 = duração ainda desconhecida: só vale o teto de 4 minutos. */
    fun shouldSubmit(durationSec: Double, listenedSec: Double): Boolean {
        if (durationSec > 0) {
            if (durationSec < MIN_TRACK_SEC) return false
            return listenedSec >= minOf(durationSec / 2.0, CAP_SEC)
        }
        return listenedSec >= CAP_SEC
    }
}

/** Uma ouvida pronta para enviar (e para a fila offline). */
data class PendingListen(
    val listenedAt: Long,
    val artist: String,
    val title: String,
    val album: String? = null,
    val videoId: String? = null,
    val durationMs: Long? = null,
)

/** Monta os corpos do ListenBrainz (puro e testável). */
object ListenPayload {
    fun trackMetadata(l: PendingListen, clientVersion: String): JsonObject = buildJsonObject {
        put("artist_name", l.artist)
        put("track_name", l.title)
        l.album?.takeIf { it.isNotBlank() }?.let { put("release_name", it) }
        put("additional_info", buildJsonObject {
            put("media_player", "Lume Music")
            put("submission_client", "Lume Music")
            put("submission_client_version", clientVersion)
            if (!l.videoId.isNullOrBlank()) {
                put("music_service", "youtube.com")
                put("origin_url", "https://music.youtube.com/watch?v=${l.videoId}")
            }
            l.durationMs?.takeIf { it > 0 }?.let { put("duration_ms", it) }
        })
    }

    /** [type]: "playing_now" (sem listened_at), "single" ou "import". */
    fun body(type: String, listens: List<PendingListen>, clientVersion: String): String = buildJsonObject {
        put("listen_type", type)
        put("payload", buildJsonArray {
            for (l in listens) add(buildJsonObject {
                if (type != "playing_now") put("listened_at", l.listenedAt)
                put("track_metadata", trackMetadata(l, clientVersion))
            })
        })
    }.toString()
}

sealed class LbConnect {
    data class Ok(val user: String) : LbConnect()
    data class Failed(val message: String) : LbConnect()
}

/**
 * ListenBrainz (contrato 5.2 B). Desligado por padrão: só roda com um token válido colado nos Ajustes.
 * O token fica em SharedPreferences privadas (fora do Auto Backup) e nunca vai para log.
 * Sem mexer no player: observa AudioPlayer/ExoPlayer de fora, uma vez por segundo, só enquanto conectado.
 */
object ListenBrainz {
    private const val API = "https://api.listenbrainz.org/1"
    private const val QUEUE_MAX = 500
    private const val BATCH = 100
    const val TOKEN_URL = "https://listenbrainz.org/settings/"

    private lateinit var appContext: Context
    private lateinit var prefs: SharedPreferences
    private var ready = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var loop: Job? = null
    private val flushMutex = Mutex()
    private val queueLock = Any()
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val http get() = DiscNet.client.newBuilder().callTimeout(15, TimeUnit.SECONDS).readTimeout(12, TimeUnit.SECONDS).build()
    private val queueFile get() = File(File(appContext.filesDir, "LumeMusic").also { it.mkdirs() }, "listenbrainz_queue.json")

    /** Nome do usuário quando conectado (para "Conectado como …"); null = desligado. */
    var connectedUser by mutableStateOf<String?>(null); private set
    var queuedCount by mutableStateOf(0); private set

    private fun token(): String? = prefs.getString("token", null)?.takeIf { it.isNotBlank() }

    fun init(context: Context) {
        if (ready) return
        appContext = context.applicationContext
        prefs = appContext.getSharedPreferences("lume_scrobble", Context.MODE_PRIVATE)
        ready = true
        queuedCount = readQueue().size
        if (token() != null) { connectedUser = prefs.getString("user", null) ?: ""; startLoop() }
    }

    // ---------------- Conectar / desconectar ----------------

    /** Valida o token em GET /validate-token; se valer, guarda e liga o registro. */
    suspend fun connect(raw: String): LbConnect {
        val t = raw.trim().removePrefix("Token ").trim()
        if (t.isEmpty()) return LbConnect.Failed("Cole o seu token do ListenBrainz.")
        val req = Request.Builder().url("$API/validate-token").header("Authorization", "Token $t").build()
        val r = try {
            withContext(Dispatchers.IO) { http.newCall(req).execute().use { it.code to it.body?.string() } }
        } catch (_: Exception) { return LbConnect.Failed("Sem conexão. Verifique a internet e tente de novo.") }
        val o = try { r.second?.let { json.parseToJsonElement(it) as? JsonObject } } catch (_: Exception) { null }
        val valid = (o?.get("valid") as? JsonPrimitive)?.booleanOrNull == true
        val user = (o?.get("user_name") as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
        if (r.first == 200 && valid && !user.isNullOrBlank()) {
            prefs.edit().putString("token", t).putString("user", user).apply()
            connectedUser = user
            startLoop()
            return LbConnect.Ok(user)
        }
        if (r.first >= 500) return LbConnect.Failed("O ListenBrainz está fora do ar agora. Tente de novo em instantes.")
        return LbConnect.Failed("Token inválido. Confira se copiou o token inteiro.")
    }

    fun disconnect() {
        prefs.edit().remove("token").remove("user").apply()
        connectedUser = null
        loop?.cancel(); loop = null
        resetTrack()
        synchronized(queueLock) { queueFile.delete() }
        queuedCount = 0
    }

    // ---------------- Acompanhamento da reprodução ----------------

    private var curId: String? = null
    private var startedAt = 0L
    private var listened = 0.0
    private var submitted = false
    private var nowSent = false
    private var lastPos = 0.0
    private var lastTickMs = 0L

    private fun resetTrack() { curId = null; listened = 0.0; submitted = false; nowSent = false; lastPos = 0.0; lastTickMs = 0L }

    private fun startLoop() {
        if (loop?.isActive == true) return
        loop = scope.launch(Dispatchers.Main.immediate) {
            launch(Dispatchers.IO) { delay(4_000); flushQueue() }
            while (isActive) { try { tick() } catch (_: Exception) {}; delay(1000) }
        }
    }

    private fun begin(t: Track) {
        curId = t.id; startedAt = System.currentTimeMillis() / 1000; listened = 0.0; submitted = false; nowSent = false
    }

    private fun listenOf(t: Track): PendingListen {
        val dur = if (PlaybackClock.duration > 0) PlaybackClock.duration else t.duration
        return PendingListen(startedAt, t.artist, t.title, t.album.ifEmpty { null },
            t.videoId, if (dur > 0) (dur * 1000).toLong() else null)
    }

    private fun tick() {
        val t = AudioPlayer.currentTrack ?: return
        val nowMs = SystemClock.elapsedRealtime()
        val dt = if (lastTickMs == 0L) 0.0 else ((nowMs - lastTickMs) / 1000.0).coerceIn(0.0, 3.0)
        lastTickMs = nowMs
        val pos = PlaybackClock.currentTime
        // Nova reprodução: outra faixa, ou a mesma voltando do fim para o começo (repetir).
        if (t.id != curId || (lastPos > 20 && pos < 3.0 && lastPos - pos > 15)) begin(t)
        lastPos = pos
        if (!PlayerHolder.player.isPlaying) return
        if (!nowSent) { nowSent = true; val l = listenOf(t); scope.launch { post("playing_now", listOf(l)) } }
        listened += dt
        val dur = if (PlaybackClock.duration > 0) PlaybackClock.duration else t.duration
        if (!submitted && ListenRule.shouldSubmit(dur, listened)) {
            submitted = true
            val l = listenOf(t)
            scope.launch { sendListen(l) }
        }
    }

    // ---------------- Envio e fila offline ----------------

    private enum class Out { OK, RETRY, DROP }

    private suspend fun post(type: String, listens: List<PendingListen>): Out {
        val tk = token() ?: return Out.DROP
        val body = ListenPayload.body(type, listens, BuildConfig.VERSION_NAME)
        val req = Request.Builder().url("$API/submit-listens").header("Authorization", "Token $tk")
            .post(body.toRequestBody("application/json".toMediaType())).build()
        return try {
            val code = withContext(Dispatchers.IO) { http.newCall(req).execute().use { it.code } }
            when { code in 200..299 -> Out.OK; code >= 500 || code == 429 || code == 408 || code == 401 -> Out.RETRY; else -> Out.DROP }
        } catch (_: IOException) { Out.RETRY } catch (_: Exception) { Out.RETRY }
    }

    private suspend fun sendListen(l: PendingListen) {
        when (post("single", listOf(l))) {
            Out.OK -> flushQueue()
            Out.RETRY -> enqueue(l)
            Out.DROP -> {}
        }
    }

    private fun readQueue(): List<PendingListen> = synchronized(queueLock) {
        try {
            if (!queueFile.exists()) return emptyList()
            (json.parseToJsonElement(queueFile.readText()) as? JsonArray)?.mapNotNull { e ->
                val o = e as? JsonObject ?: return@mapNotNull null
                fun s(k: String) = (o[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
                PendingListen(s("at")?.toLongOrNull() ?: return@mapNotNull null, s("artist") ?: return@mapNotNull null, s("title") ?: return@mapNotNull null,
                    s("album"), s("vid"), s("ms")?.toLongOrNull())
            } ?: emptyList()
        } catch (_: Exception) { emptyList() }
    }

    private fun writeQueue(list: List<PendingListen>) = synchronized(queueLock) {
        try {
            if (list.isEmpty()) { queueFile.delete() } else {
                val arr = buildJsonArray {
                    for (l in list) add(buildJsonObject {
                        put("at", l.listenedAt); put("artist", l.artist); put("title", l.title)
                        l.album?.let { put("album", it) }; l.videoId?.let { put("vid", it) }; l.durationMs?.let { put("ms", it) }
                    })
                }
                val tmp = File(queueFile.parentFile, "listenbrainz_queue.json.tmp")
                tmp.writeText(arr.toString()); tmp.renameTo(queueFile)
            }
        } catch (_: Exception) {}
        queuedCount = list.size
    }

    private fun enqueue(l: PendingListen) {
        val q = readQueue() + l
        writeQueue(if (q.size > QUEUE_MAX) q.takeLast(QUEUE_MAX) else q)
    }

    /** Envia a fila em lotes de até 100 (listen_type "import"). Para no primeiro erro de rede. */
    suspend fun flushQueue() = flushMutex.withLock {
        while (token() != null) {
            val q = readQueue()
            if (q.isEmpty()) break
            val batch = q.take(BATCH)
            when (post("import", batch)) {
                Out.OK, Out.DROP -> writeQueue(readQueue().drop(batch.size))
                Out.RETRY -> break
            }
        }
    }
}
