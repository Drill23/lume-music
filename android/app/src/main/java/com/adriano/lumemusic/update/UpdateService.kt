package com.adriano.lumemusic.update

import com.adriano.lumemusic.access.AccessHttp
import com.adriano.lumemusic.access.SecureStore
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
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

sealed interface UpdateFetchResult {
    data class Available(val info: UpdateInfo) : UpdateFetchResult
    data object UpToDate : UpdateFetchResult
    data object Error : UpdateFetchResult
}

/**
 * Atualizações automáticas (ao abrir, a cada 6 h e sob demanda em Ajustes):
 * 1) Painel (/api/app/update) — prioridade máxima (permite atualização obrigatória e avisos do admin)
 * 2) Manifesto do site (https://lume-music-enq.pages.dev/version.json) — CDN sem limite de taxa
 * 3) GitHub Releases (api.github.com/repos/Drill23/lume-music/releases/latest) — fallback automático
 */
class UpdateService(
    private val http: AccessHttp,
    private val store: SecureStore,
    private val apiBase: () -> String,
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    companion object {
        const val INTERVAL_MS = 6 * 3600_000L
        const val POSTPONE_MS = 24 * 3600_000L
        const val SITE_MANIFEST_URL = "https://lume-music-enq.pages.dev/version.json"
        const val GITHUB_LATEST_URL = "https://api.github.com/repos/Drill23/lume-music/releases/latest"
        private const val K_LAST = "update.lastCheck"
        private fun kPost(info: UpdateInfo) =
            if (info.build > 0) "update.postponedUntil.${info.build}" else "update.postponedUntil.v.${info.versionName}"

        fun compareVersions(a: String, b: String): Int {
            fun parts(v: String): List<Int> = v.trim()
                .removePrefix("v").removePrefix("V")
                .substringBefore('-').substringBefore('+')
                .split('.')
                .map { it.filter(Char::isDigit).toIntOrNull() ?: 0 }
            val pa = parts(a)
            val pb = parts(b)
            val n = maxOf(pa.size, pb.size)
            for (i in 0 until n) {
                val da = pa.getOrElse(i) { 0 }
                val db = pb.getOrElse(i) { 0 }
                if (da != db) return da.compareTo(db)
            }
            return 0
        }

        fun isNewer(info: UpdateInfo, currentBuild: Int, currentName: String): Boolean {
            if (info.build > 0 && currentBuild > 0 && info.build > currentBuild) return true
            return compareVersions(info.versionName, currentName) > 0
        }

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

        fun parseSiteManifest(body: String, platform: String = "android"): UpdateInfo? {
            return try {
                val root = Json.parseToJsonElement(body) as? JsonObject ?: return null
                val plat = root[platform] as? JsonObject
                fun str(k: String) = (plat?.get(k) as? JsonPrimitive)?.contentOrNull ?: (root[k] as? JsonPrimitive)?.contentOrNull
                fun num(k: String) = (plat?.get(k) as? JsonPrimitive)?.longOrNull ?: (root[k] as? JsonPrimitive)?.longOrNull
                fun bool(k: String) = (plat?.get(k) as? JsonPrimitive)?.booleanOrNull ?: (root[k] as? JsonPrimitive)?.booleanOrNull
                val url = str("url")
                val build = num("build")?.toInt() ?: 0
                val versionName = str("versionName")?.trim()?.takeIf { it.isNotEmpty() } ?: build.takeIf { it > 0 }?.toString()
                if (url.isNullOrBlank() || !url.startsWith("https://") || versionName.isNullOrBlank()) null else UpdateInfo(
                    build = build,
                    versionName = versionName,
                    url = url,
                    notes = (str("notes") ?: "").trim(),
                    mandatory = bool("mandatory") ?: false,
                )
            } catch (_: Exception) { null }
        }

        fun parseGitHubRelease(body: String, assetName: String = "Lume-Music-Android.apk"): UpdateInfo? {
            return try {
                val root = Json.parseToJsonElement(body) as? JsonObject ?: return null
                if ((root["draft"] as? JsonPrimitive)?.booleanOrNull == true) return null
                if ((root["prerelease"] as? JsonPrimitive)?.booleanOrNull == true) return null
                val tag = (root["tag_name"] as? JsonPrimitive)?.contentOrNull?.trim()
                    ?.removePrefix("v")?.removePrefix("V")?.takeIf { it.isNotEmpty() } ?: return null
                val assets = (root["assets"] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()
                val match = assets.firstOrNull { ((it["name"] as? JsonPrimitive)?.contentOrNull ?: "").equals(assetName, ignoreCase = true) }
                    ?: assets.firstOrNull { ((it["name"] as? JsonPrimitive)?.contentOrNull ?: "").endsWith(".apk", ignoreCase = true) }
                val url = (match?.get("browser_download_url") as? JsonPrimitive)?.contentOrNull
                if (url.isNullOrBlank() || !url.startsWith("https://")) return null
                val rawNotes = ((root["body"] as? JsonPrimitive)?.contentOrNull ?: "")
                    .replace(Regex("(?m)^#{1,6}\\s*"), "")
                    .replace("**", "")
                    .trim()
                    .take(700)
                UpdateInfo(build = 0, versionName = tag, url = url, notes = rawNotes, mandatory = false)
            } catch (_: Exception) { null }
        }
    }

    fun shouldCheck(): Boolean = now() - (store.get(K_LAST)?.toLongOrNull() ?: 0L) >= INTERVAL_MS

    /** Consulta Painel → Manifesto do site → GitHub Releases, distinguindo atualização disponível, atualizado e offline. */
    suspend fun fetchStatus(currentBuild: Int, currentName: String): UpdateFetchResult {
        var anySuccess = false

        // 1. Painel administrativo (tem prioridade para atualizações obrigatórias / avisos customizados)
        val base = apiBase()
        if (base.isNotEmpty()) {
            val url = "$base/api/app/update?platform=android&build=$currentBuild&app=${java.net.URLEncoder.encode(currentName, "UTF-8")}"
            val r = try { http.get(url, 8000) } catch (_: IOException) { null }
            if (r != null && r.code == 200 && r.body != null) {
                anySuccess = true
                store.put(K_LAST, now().toString())
                val info = parse(r.body)
                if (info != null && isNewer(info, currentBuild, currentName)) return UpdateFetchResult.Available(info)
            }
        }

        // 2. Manifesto público do site (Cloudflare Pages, por plataforma — autoritativo quando responde 200 com seção "android")
        val siteUrl = "$SITE_MANIFEST_URL?t=${now()}"
        val sr = try { http.get(siteUrl, 8000) } catch (_: IOException) { null }
        if (sr != null && sr.code == 200 && sr.body != null) {
            anySuccess = true
            store.put(K_LAST, now().toString())
            val info = parseSiteManifest(sr.body, "android")
            if (info != null) {
                return if (isNewer(info, currentBuild, currentName)) UpdateFetchResult.Available(info)
                else UpdateFetchResult.UpToDate
            }
        }

        // 3. Fallback direto no GitHub Releases (apenas se o manifesto do site estiver indisponível)
        val gr = try { http.get(GITHUB_LATEST_URL, 8000) } catch (_: IOException) { null }
        if (gr != null && gr.code == 200 && gr.body != null) {
            anySuccess = true
            store.put(K_LAST, now().toString())
            val info = parseGitHubRelease(gr.body, "Lume-Music-Android.apk")
            if (info != null && isNewer(info, currentBuild, currentName)) return UpdateFetchResult.Available(info)
        }

        return if (anySuccess) UpdateFetchResult.UpToDate else UpdateFetchResult.Error
    }

    /** Consulta atualização; null = sem atualização ou erro (nunca incomoda o usuário). */
    suspend fun fetch(currentBuild: Int, currentName: String): UpdateInfo? =
        (fetchStatus(currentBuild, currentName) as? UpdateFetchResult.Available)?.info

    /** Obrigatória sempre aparece; as outras ficam adiadas 24 h depois de "Depois" (para aquela versão). */
    fun isPostponed(info: UpdateInfo): Boolean = !info.mandatory && now() < (store.get(kPost(info))?.toLongOrNull() ?: 0L)
    fun postpone(info: UpdateInfo) = store.put(kPost(info), (now() + POSTPONE_MS).toString())
}
