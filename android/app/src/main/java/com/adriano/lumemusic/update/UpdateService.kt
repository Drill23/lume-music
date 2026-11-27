package com.adriano.lumemusic.update

import com.adriano.lumemusic.access.AccessHttp
import com.adriano.lumemusic.access.SecureStore
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import java.io.IOException

data class UpdateInfo(
    val build: Int,
    val versionName: String,
    val url: String,
    val notes: String,
    val mandatory: Boolean,
    val publishedAt: Long = 0,
)

/** GET /api/app/update?platform=android&build=<versionCode>&app=<versionName> (ao abrir e a cada 6 h). */
class UpdateService(
    private val http: AccessHttp,
    private val store: SecureStore,
    private val apiBase: () -> String,
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    companion object {
        const val INTERVAL_MS = 6 * 3600_000L
        const val POSTPONE_MS = 24 * 3600_000L
        private const val K_LAST = "update.lastCheck"
        private fun kPost(build: Int) = "update.postponedUntil.$build"

        fun parse(body: String): UpdateInfo? = try {
            val o = Json.parseToJsonElement(body) as? JsonObject
            if (o == null || (o["ok"] as? JsonPrimitive)?.booleanOrNull != true || (o["available"] as? JsonPrimitive)?.booleanOrNull != true) null else {
                val build = (o["build"] as? JsonPrimitive)?.longOrNull?.toInt()
                val url = (o["url"] as? JsonPrimitive)?.contentOrNull
                if (build == null || url.isNullOrBlank() || !url.startsWith("https://")) null else UpdateInfo(
                    build = build,
                    versionName = (o["versionName"] as? JsonPrimitive)?.contentOrNull ?: build.toString(),
                    url = url,
                    notes = (o["notes"] as? JsonPrimitive)?.contentOrNull ?: "",
                    mandatory = (o["mandatory"] as? JsonPrimitive)?.booleanOrNull ?: false,
                    publishedAt = (o["publishedAt"] as? JsonPrimitive)?.longOrNull ?: 0,
                )
            }
        } catch (_: Exception) { null }
    }

    fun shouldCheck(): Boolean = now() - (store.get(K_LAST)?.toLongOrNull() ?: 0L) >= INTERVAL_MS

    /** Consulta o painel; null = sem atualização, painel desligado ou erro (nunca incomoda o usuário). */
    suspend fun fetch(currentBuild: Int, currentName: String): UpdateInfo? {
        val base = apiBase()
        if (base.isEmpty()) return null
        val url = "$base/api/app/update?platform=android&build=$currentBuild&app=${java.net.URLEncoder.encode(currentName, "UTF-8")}"
        val r = try { http.get(url, 8000) } catch (_: IOException) { return null }
        if (r.code != 200 || r.body == null) return null
        store.put(K_LAST, now().toString())
        val info = parse(r.body) ?: return null
        return if (info.build > currentBuild) info else null
    }

    /** Obrigatória sempre aparece; as outras ficam adiadas 24 h depois de "Depois" (para aquela versão). */
    fun isPostponed(info: UpdateInfo): Boolean = !info.mandatory && now() < (store.get(kPost(info.build))?.toLongOrNull() ?: 0L)
    fun postpone(info: UpdateInfo) = store.put(kPost(info.build), (now() + POSTPONE_MS).toString())
}
