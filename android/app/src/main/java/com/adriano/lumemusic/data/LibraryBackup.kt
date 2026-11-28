package com.adriano.lumemusic.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.access.AccessConfig
import com.adriano.lumemusic.access.AccessHttp
import com.adriano.lumemusic.access.AccessState
import com.adriano.lumemusic.access.OkHttpAccessHttp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

// ======================================================================================================
// Formato LibraryV1 (contrato 5.2, seção A): o MESMO JSON no iPhone e no Android.
// Lido e escrito "na mão" para tolerar variações do outro app (números como texto, campos faltando).
// ======================================================================================================

data class LbTrack(
    val videoId: String,
    val title: String = "",
    val artist: String = "",
    val album: String? = null,
    val durationSec: Int? = null,
    val artworkUrl: String? = null,
)

data class LbPlaylist(
    val id: String,
    val name: String = "",
    val created: Long = 0L,
    val updated: Long = 0L,
    val tracks: List<LbTrack> = emptyList(),
)

data class LbDeleted(val id: String, val at: Long = 0L)

data class LibraryV1(
    val exportedAt: Long = 0L,
    val platform: String = "android",
    val app: String = "",
    val playlists: List<LbPlaylist> = emptyList(),
    val liked: List<LbTrack> = emptyList(),
    val followed: List<String> = emptyList(),
    val deletedPlaylists: List<LbDeleted> = emptyList(),
) {
    val isEmpty: Boolean get() = playlists.isEmpty() && liked.isEmpty() && followed.isEmpty() && deletedPlaylists.isEmpty()

    fun toJsonObject(withArtwork: Boolean = true): JsonObject = buildJsonObject {
        put("v", 1)
        put("exportedAt", exportedAt)
        put("platform", platform)
        put("app", app)
        put("playlists", buildJsonArray {
            for (p in playlists) add(buildJsonObject {
                put("id", p.id); put("name", p.name); put("created", p.created); put("updated", p.updated)
                put("tracks", buildJsonArray { for (t in p.tracks) add(trackJson(t, withArtwork)) })
            })
        })
        put("liked", buildJsonArray { for (t in liked) add(trackJson(t, withArtwork)) })
        put("followed", buildJsonArray { for (f in followed) add(JsonPrimitive(f)) })
        put("deletedPlaylists", buildJsonArray { for (d in deletedPlaylists) add(buildJsonObject { put("id", d.id); put("at", d.at) }) })
    }

    private fun trackJson(t: LbTrack, withArtwork: Boolean) = buildJsonObject {
        put("videoId", t.videoId); put("title", t.title); put("artist", t.artist)
        t.album?.takeIf { it.isNotEmpty() && withArtwork }?.let { put("album", it) }
        t.durationSec?.takeIf { it > 0 }?.let { put("durationSec", it) }
        t.artworkUrl?.takeIf { it.isNotEmpty() && withArtwork }?.let { put("artworkUrl", it) }
    }

    companion object {
        private fun JsonObject.s(k: String): String? = (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
        private fun JsonObject.l(k: String): Long? = (this[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.let { it.longOrNull ?: it.doubleOrNull?.toLong() ?: it.content.toDoubleOrNull()?.toLong() }
        private fun JsonObject.arr(k: String): List<kotlinx.serialization.json.JsonElement> = (this[k] as? JsonArray) ?: emptyList()

        private fun track(o: JsonObject): LbTrack? {
            val vid = o.s("videoId")?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            return LbTrack(vid, o.s("title") ?: "", o.s("artist") ?: "", o.s("album"), o.l("durationSec")?.toInt(), o.s("artworkUrl"))
        }

        /** null se não for um objeto com v == 1. */
        fun fromJsonObject(o: JsonObject): LibraryV1? {
            if (o.l("v") != 1L) return null
            val playlists = o.arr("playlists").mapNotNull { e ->
                val p = e as? JsonObject ?: return@mapNotNull null
                val id = p.s("id")?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                LbPlaylist(id, p.s("name") ?: "", p.l("created") ?: 0L, p.l("updated") ?: p.l("created") ?: 0L,
                    p.arr("tracks").mapNotNull { (it as? JsonObject)?.let(::track) })
            }
            return LibraryV1(
                exportedAt = o.l("exportedAt") ?: 0L,
                platform = o.s("platform") ?: "",
                app = o.s("app") ?: "",
                playlists = playlists,
                liked = o.arr("liked").mapNotNull { (it as? JsonObject)?.let(::track) },
                followed = o.arr("followed").mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p !is JsonNull }?.content?.trim()?.takeIf { s -> s.isNotEmpty() } },
                deletedPlaylists = o.arr("deletedPlaylists").mapNotNull { e ->
                    val d = e as? JsonObject ?: return@mapNotNull null
                    LbDeleted(d.s("id")?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null, d.l("at") ?: 0L)
                },
            )
        }
    }
}

/** Mesclagem do contrato (pura, testada na JVM): nunca perde nada sem motivo. */
object LibraryMerge {
    fun merge(local: LibraryV1, remote: LibraryV1): LibraryV1 {
        // Lápides: união por id, vale a mais recente.
        val tomb = LinkedHashMap<String, Long>()
        for (d in local.deletedPlaylists + remote.deletedPlaylists) tomb[d.id] = maxOf(tomb[d.id] ?: Long.MIN_VALUE, d.at)

        // Playlists: união por id; no mesmo id fica a de `updated` maior (empate: a local). A ordem local é preservada.
        val byId = LinkedHashMap<String, LbPlaylist>()
        for (p in local.playlists) { val cur = byId[p.id]; if (cur == null || p.updated > cur.updated) byId[p.id] = p }
        for (p in remote.playlists) { val cur = byId[p.id]; if (cur == null || p.updated > cur.updated) byId[p.id] = p }
        // Apagada depois da última alteração (at > updated) → não volta.
        val playlists = byId.values.filter { p -> (tomb[p.id] ?: Long.MIN_VALUE) <= p.updated }
        val alive = playlists.associateBy { it.id }
        val deleted = tomb.entries
            .filter { (id, at) -> alive[id]?.let { at > it.updated } ?: true }
            .map { LbDeleted(it.key, it.value) }

        // Curtidas: união por videoId (ordem local primeiro, o que faltava vem no fim).
        val liked = LinkedHashMap<String, LbTrack>()
        for (t in local.liked + remote.liked) liked.putIfAbsent(t.videoId, t)

        // Seguidos: união sem diferenciar maiúsculas (fica a grafia que apareceu primeiro).
        val followed = LinkedHashMap<String, String>()
        for (f in local.followed + remote.followed) { val k = f.trim(); if (k.isNotEmpty()) followed.putIfAbsent(k.lowercase(), k) }

        return LibraryV1(
            exportedAt = maxOf(local.exportedAt, remote.exportedAt),
            platform = local.platform, app = local.app,
            playlists = playlists, liked = liked.values.toList(), followed = followed.values.toList(), deletedPlaylists = deleted,
        )
    }
}

/** "Último backup: hoje às 21:40" (puro e testável). */
object BackupText {
    fun last(savedAt: Long, now: Long = System.currentTimeMillis(), zone: TimeZone = TimeZone.getDefault()): String {
        if (savedAt <= 0) return "Nenhum backup ainda"
        fun dayStart(t: Long) = Calendar.getInstance(zone).apply { timeInMillis = t; set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0) }.timeInMillis
        val hour = SimpleDateFormat("HH:mm", Locale("pt", "BR")).apply { timeZone = zone }.format(Date(savedAt))
        val days = Math.round((dayStart(now) - dayStart(savedAt)) / 86_400_000.0).toInt()
        return when {
            days <= 0 -> "Último backup: hoje às $hour"
            days == 1 -> "Último backup: ontem às $hour"
            else -> "Último backup: " + SimpleDateFormat("dd/MM", Locale("pt", "BR")).apply { timeZone = zone }.format(Date(savedAt)) + " às $hour"
        }
    }
}

sealed class BackupOutcome {
    data class Done(val savedAt: Long, val changed: Boolean = false) : BackupOutcome()
    /** Sem sessão de acesso ativa ou painel indisponível: nada a fazer agora. */
    data object Skipped : BackupOutcome()
    data class Failed(val message: String) : BackupOutcome()
}

/**
 * Cliente do backup da biblioteca (contrato 5.2 A). Silencioso em rede/404: tenta de novo mais tarde.
 * Backup 20 s depois da última mudança e ao ir para o fundo; restauração (sempre mesclando) depois de ativar/transferir/restaurar o
 * vitalício e, no máximo uma vez por dia, enquanto este aparelho ainda não foi restaurado.
 */
object LibraryBackup {
    const val DEBOUNCE_MS = 20_000L
    private const val DAY_MS = 24 * 3600_000L
    private const val MAX_BYTES = 1_000_000

    private lateinit var prefs: SharedPreferences
    private var ready = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private var debounce: Job? = null
    private val http: AccessHttp by lazy { OkHttpAccessHttp() }
    private val lenient = Json { ignoreUnknownKeys = true; isLenient = true }

    /** Último backup bem-sucedido (ms, hora do painel); 0 = nunca. Observável pela tela de Ajustes. */
    var lastBackupAt by mutableStateOf(0L); private set
    var busy by mutableStateOf(false); private set

    fun init(context: Context) {
        if (ready) return
        prefs = context.applicationContext.getSharedPreferences("lume_backup", Context.MODE_PRIVATE)
        lastBackupAt = prefs.getLong("lastBackupAt", 0L)
        ready = true
        if (prefs.getBoolean("dirty", false)) schedule()   // mudou e o app fechou antes do backup
    }

    // ---------------- Gatilhos ----------------

    /** A biblioteca mudou (playlist, faixa, curtida, seguir): backup 20 s depois da última mudança. */
    fun markChanged() {
        if (!ready) return
        prefs.edit().putBoolean("dirty", true).apply()
        schedule()
    }

    private fun schedule() {
        debounce?.cancel()
        debounce = scope.launch { delay(DEBOUNCE_MS); backup() }
    }

    /** O app foi para o fundo (MainActivity.onStop): envia já, se houver mudança pendente. */
    fun onBackground() {
        if (!ready || !prefs.getBoolean("dirty", false)) return
        debounce?.cancel()
        scope.launch { backup() }
    }

    /** Abertura do app (a cada 6 h): restaura no máximo uma vez por dia enquanto não houver marca de "restaurado neste aparelho". */
    fun onAppOpen() {
        if (!ready || prefs.getLong("restoredAt", 0L) > 0L) return
        val now = System.currentTimeMillis()
        if (now - prefs.getLong("lastAutoTry", 0L) < DAY_MS) return
        if (session() == null) return
        prefs.edit().putLong("lastAutoTry", now).apply()
        scope.launch { restore() }
    }

    /** Vitalício ativado/transferido/restaurado neste aparelho: restaura agora (o painel migra o backup do teste grátis). */
    fun onLifetimeActivated() {
        if (!ready) return
        prefs.edit().remove("restoredAt").apply()
        scope.launch { restore() }
    }

    // ---------------- Operações ----------------

    private class Session(val base: String, val token: String, val device: String)

    private fun session(): Session? {
        val svc = try { Access.service } catch (_: Throwable) { return null }
        if (svc.state.value !is AccessState.Active) return null
        val token = svc.savedToken() ?: return null
        val base = svc.effectiveApiBase().takeIf { it.isNotEmpty() } ?: return null
        return Session(base, token, svc.deviceId())
    }

    private fun body(s: Session, library: JsonObject?): String = buildJsonObject {
        put("device", s.device); put("platform", AccessConfig.PLATFORM); put("app", AccessConfig.APP_VERSION)
        if (library != null) put("library", library)
    }.toString()

    /** Faz o backup. [manual] = botão dos Ajustes: devolve mensagens; no automático falha em silêncio. */
    suspend fun backup(manual: Boolean = false): BackupOutcome = mutex.withLock {
        val s = session() ?: return if (manual) BackupOutcome.Failed("Ative seu acesso para guardar a biblioteca.") else BackupOutcome.Skipped
        busy = true
        try {
            // Antes do primeiro backup deste aparelho, junta o que já está guardado: o backup SUBSTITUI o anterior.
            if (prefs.getLong("restoredAt", 0L) <= 0L) {
                val r = restoreLocked(s)
                if (r is BackupOutcome.Failed || r is BackupOutcome.Skipped) return if (manual) r else BackupOutcome.Skipped
            }
            var payload = withContext(Dispatchers.Main) { LibraryStore.exportLibrary() }
            var json = body(s, payload.toJsonObject())
            if (json.toByteArray().size > MAX_BYTES + 2_000) json = body(s, payload.toJsonObject(withArtwork = false))
            val r = try { http.post("${s.base}/api/library/backup", json, s.token, 20_000) }
            catch (_: IOException) { return if (manual) BackupOutcome.Failed("Sem conexão. Tente de novo mais tarde.") else BackupOutcome.Skipped }
            when {
                r.code == 200 -> {
                    val savedAt = (parse(r.body)?.get("savedAt") as? JsonPrimitive)?.longOrNull ?: System.currentTimeMillis()
                    lastBackupAt = savedAt
                    prefs.edit().putLong("lastBackupAt", savedAt).putBoolean("dirty", false).apply()
                    BackupOutcome.Done(savedAt)
                }
                r.code == 413 -> BackupOutcome.Failed(errorMessage(r.body) ?: "Sua biblioteca ficou grande demais para o backup.")
                r.code == 429 -> BackupOutcome.Failed("Muitos backups seguidos. Tente de novo em alguns minutos.")
                else -> if (manual) BackupOutcome.Failed(errorMessage(r.body) ?: "O painel ainda não está disponível. Tente mais tarde.") else BackupOutcome.Skipped
            }
        } finally { busy = false }
    }

    /** Restaura do painel e MESCLA com a biblioteca local (nunca apaga). */
    suspend fun restore(manual: Boolean = false): BackupOutcome = mutex.withLock {
        val s = session() ?: return if (manual) BackupOutcome.Failed("Ative seu acesso para restaurar a biblioteca.") else BackupOutcome.Skipped
        busy = true
        try {
            val r = restoreLocked(s)
            if (!manual && (r is BackupOutcome.Failed)) BackupOutcome.Skipped else r
        } finally { busy = false }
    }

    private suspend fun restoreLocked(s: Session): BackupOutcome {
        val r = try { http.post("${s.base}/api/library/restore", body(s, null), s.token, 20_000) }
        catch (_: IOException) { return BackupOutcome.Failed("Sem conexão. Tente de novo mais tarde.") }
        if (r.code != 200) return BackupOutcome.Failed(errorMessage(r.body) ?: "O painel ainda não está disponível. Tente mais tarde.")
        val o = parse(r.body)
        if (o == null || (o["ok"] as? JsonPrimitive)?.content != "true") return BackupOutcome.Failed("Resposta inesperada do painel.")
        val savedAt = (o["savedAt"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.longOrNull
        val remote = (o["library"] as? JsonObject)?.let { LibraryV1.fromJsonObject(it) }
        var changed = false
        if (remote != null) {
            changed = withContext(Dispatchers.Main) {
                val merged = LibraryMerge.merge(LibraryStore.exportLibrary(), remote)
                LibraryStore.applyMerged(merged)
            }
        }
        prefs.edit().putLong("restoredAt", System.currentTimeMillis()).apply()
        if (savedAt != null && savedAt > lastBackupAt) { lastBackupAt = savedAt; prefs.edit().putLong("lastBackupAt", savedAt).apply() }
        if (changed) markChanged()   // o que veio de lá ainda não está no backup deste aparelho
        return BackupOutcome.Done(savedAt ?: 0L, changed)
    }

    private fun parse(body: String?): JsonObject? = try { body?.let { lenient.parseToJsonElement(it) as? JsonObject } } catch (_: Exception) { null }
    private fun errorMessage(body: String?): String? = (parse(body)?.get("message") as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
}
