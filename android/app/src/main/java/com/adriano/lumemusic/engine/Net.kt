package com.adriano.lumemusic.engine

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

// ---------- Helpers para navegar em JSON "solto" (equivale a [String: Any] do Swift) ----------

val LumeJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    isLenient = true
    coerceInputValues = true
}

fun JsonElement?.obj(): JsonObject? = this as? JsonObject
fun JsonElement?.arr(): JsonArray? = this as? JsonArray
fun JsonElement?.objs(): List<JsonObject> = (this as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()
operator fun JsonElement?.get(key: String): JsonElement? = (this as? JsonObject)?.get(key)?.takeIf { it !is JsonNull }
fun JsonElement?.str(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
fun JsonElement?.strLoose(): String? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
fun JsonElement?.dbl(): Double? = (this as? JsonPrimitive)?.let { it.doubleOrNull ?: it.content.toDoubleOrNull() }
fun JsonElement?.lng(): Long? = (this as? JsonPrimitive)?.let { it.longOrNull ?: it.content.toDoubleOrNull()?.toLong() }
fun JsonElement?.int(): Int? = lng()?.toInt()
fun JsonElement?.bool(): Boolean? = (this as? JsonPrimitive)?.booleanOrNull

fun jsonObjectOf(vararg pairs: Pair<String, Any?>): JsonObject = JsonObject(pairs.mapNotNull { (k, v) -> toJson(v)?.let { k to it } }.toMap())

fun toJson(v: Any?): JsonElement? = when (v) {
    null -> null
    is JsonElement -> v
    is String -> JsonPrimitive(v)
    is Boolean -> JsonPrimitive(v)
    is Number -> JsonPrimitive(v)
    is Map<*, *> -> JsonObject(v.entries.mapNotNull { (k, x) -> toJson(x)?.let { k.toString() to it } }.toMap())
    is List<*> -> JsonArray(v.mapNotNull { toJson(it) })
    else -> JsonPrimitive(v.toString())
}

/** Percorre a árvore inteira (equivalente aos `walk` recursivos do Swift). */
fun JsonElement.walk(visit: (JsonObject) -> Boolean) {
    fun go(n: JsonElement): Boolean {
        when (n) {
            is JsonObject -> {
                if (visit(n)) return true
                for (v in n.values) if (go(v)) return true
            }
            is JsonArray -> for (v in n) if (go(v)) return true
            else -> {}
        }
        return false
    }
    go(this)
}

// ---------- Rede ----------

object DiscNet {
    const val BROWSER_UA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(7, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .callTimeout(16, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    /** Pasta de cache (definida pelo Application; em testes JVM cai para a pasta temporária). */
    @Volatile var cacheDir: File = File(System.getProperty("java.io.tmpdir"), "lume-cache").apply { mkdirs() }

    fun caches(name: String): File = File(cacheDir, name)

    fun enc(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    private fun build(url: String, timeout: Long, headers: Map<String, String>): Request.Builder {
        val b = Request.Builder().url(url)
        b.header("User-Agent", BROWSER_UA)
        b.header("Accept-Language", "pt-BR,pt;q=0.9,en;q=0.7")
        for ((k, v) in headers) b.header(k, v)
        return b
    }

    private fun clientFor(timeout: Long): OkHttpClient =
        if (timeout == 7L) client else client.newBuilder().callTimeout(timeout + 6, TimeUnit.SECONDS).readTimeout(timeout, TimeUnit.SECONDS).build()

    private suspend fun execute(req: Request, timeout: Long): String? = withContext(Dispatchers.IO) {
        try {
            clientFor(timeout).newCall(req).execute().use { r ->
                if (!r.isSuccessful) null else r.body?.string()
            }
        } catch (_: Exception) {
            null
        }
    }

    suspend fun json(url: String, timeout: Long = 7, headers: Map<String, String> = emptyMap(), retries: Int = 0): JsonElement? {
        val req = try { build(url, timeout, headers).get().build() } catch (_: Exception) { return null }
        var left = retries
        var body = execute(req, timeout)
        var parsed = body?.let { parse(it) }
        while (parsed == null && left > 0) {
            left--
            body = execute(req, timeout)
            parsed = body?.let { parse(it) }
        }
        return parsed
    }

    suspend fun postJson(url: String, body: JsonObject, timeout: Long = 8, headers: Map<String, String> = emptyMap()): JsonElement? {
        val req = try {
            build(url, timeout, headers)
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .header("Content-Type", "application/json")
                .build()
        } catch (_: Exception) { return null }
        return execute(req, timeout)?.let { parse(it) }
    }

    suspend fun text(url: String, timeout: Long = 7, headers: Map<String, String> = emptyMap()): String? {
        val req = try { build(url, timeout, headers).get().build() } catch (_: Exception) { return null }
        return execute(req, timeout)
    }

    fun parse(s: String): JsonElement? = try { LumeJson.parseToJsonElement(s) } catch (_: Exception) { null }
}
