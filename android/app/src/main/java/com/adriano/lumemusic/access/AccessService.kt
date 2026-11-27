package com.adriano.lumemusic.access

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/** Contrato "Código de Acesso" v1 (app ⇄ painel). A tela fica para a fase 2; aqui está todo o serviço. */
object AccessConfig {
    /** Vazio = portão desligado até a config remota informar a URL do painel. */
    const val DEFAULT_API_BASE = ""
    const val CONFIG_URL = "https://raw.githubusercontent.com/Drill23/lume-music/main/config/painel.json"
    const val APP_VERSION = "5.0.0"
    const val PLATFORM = "android"
    const val CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    const val CHECK_INTERVAL_MS = 6 * 3600_000L
}

data class HttpResult(val code: Int, val body: String?)

interface AccessHttp {
    /** Lança IOException em erro de rede/timeout. */
    suspend fun get(url: String, timeoutMs: Long): HttpResult
    suspend fun post(url: String, json: String, bearer: String?, timeoutMs: Long): HttpResult
}

/** Armazenamento seguro de pares chave/valor (Keystore no Android; fake nos testes). */
interface SecureStore {
    fun get(key: String): String?
    fun put(key: String, value: String?)
}

@Serializable
data class RemoteConfig(val apiBase: String = "", val required: Boolean = true)

@Serializable
data class AccessInfo(
    val code: String,
    val token: String,
    val lifetime: Boolean,
    val expires: Long? = null,
    val planKind: String = "",
    val planValue: Int = 0,
    val activatedAt: Long = 0,
    val message: String = "",
    val note: String? = null,
) {
    val maskedCode: String get() = if (code.length == 6) code.take(2) + "••" + code.takeLast(2) else code
    fun isValidAt(now: Long) = lifetime || (expires != null && expires > now)

    /** Texto da tela de sucesso (regra do contrato). */
    fun successMessage(): String {
        if (lifetime) return "Acesso vitalício ✨ Obrigado por comprar!"
        val until = expires?.let { SimpleDateFormat("dd 'de' MMMM 'de' yyyy", Locale("pt", "BR")).format(Date(it)) } ?: ""
        val period = when (planKind) {
            "months" -> if (planValue == 1) "1 mês" else "$planValue meses"
            "days" -> if (planValue == 1) "1 dia" else "$planValue dias"
            else -> ""
        }
        return if (period.isNotEmpty()) "Código válido por $period — até $until" else "Código válido até $until"
    }
}

sealed class AccessState {
    /** Modo pré-painel / interruptor de emergência: o app é livre. */
    data object Open : AccessState()
    data class Locked(val message: String? = null) : AccessState()
    data class Active(val info: AccessInfo) : AccessState()
}

sealed class ActivateResult {
    data class Success(val info: AccessInfo) : ActivateResult()
    data class Failure(val error: String, val message: String) : ActivateResult()
}

class AccessService(
    private val store: SecureStore,
    private val http: AccessHttp,
    private val now: () -> Long = { System.currentTimeMillis() },
    private val deviceSeed: () -> String = { "" },
) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val _state = MutableStateFlow<AccessState>(AccessState.Open)
    val state: StateFlow<AccessState> = _state

    companion object {
        private const val K_CONFIG = "lume.access.config"
        private const val K_INFO = "lume.access.info"
        private const val K_DEVICE = "lume.access.device"
        private const val K_LAST_CHECK = "lume.access.lastCheck"
        private val CODE_RE = Regex("^[A-Z0-9]{6}$")

        /** Maiúsculas, sem espaços/hífens. */
        fun normalizeCode(raw: String): String = raw.uppercase().filter { !it.isWhitespace() && it != '-' }
        fun isValidCodeFormat(code: String) = CODE_RE.matches(code)

        fun parseConfig(body: String): RemoteConfig? = try {
            val o = Json.parseToJsonElement(body) as? JsonObject
            if (o == null) null else RemoteConfig(
                apiBase = (o["apiBase"] as? JsonPrimitive)?.contentOrNull?.trim()?.trimEnd('/') ?: "",
                required = (o["required"] as? JsonPrimitive)?.booleanOrNull ?: true,
            )
        } catch (_: Exception) { null }

        /** Interpreta resposta 200 do activate/check. */
        fun parseInfo(body: String, fallbackToken: String?, fallbackCode: String?): AccessInfo? {
            return try {
            val o = Json.parseToJsonElement(body) as? JsonObject ?: return null
            if ((o["ok"] as? JsonPrimitive)?.booleanOrNull != true) return null
            val plan = o["plan"] as? JsonObject
            AccessInfo(
                code = (o["code"] as? JsonPrimitive)?.contentOrNull ?: fallbackCode ?: "",
                token = (o["token"] as? JsonPrimitive)?.contentOrNull ?: fallbackToken ?: "",
                lifetime = (o["lifetime"] as? JsonPrimitive)?.booleanOrNull ?: false,
                expires = (o["expires"] as? JsonPrimitive)?.longOrNull,
                planKind = (plan?.get("kind") as? JsonPrimitive)?.contentOrNull ?: "",
                planValue = (plan?.get("value") as? JsonPrimitive)?.longOrNull?.toInt() ?: 0,
                activatedAt = (o["activatedAt"] as? JsonPrimitive)?.longOrNull ?: 0,
                message = (o["message"] as? JsonPrimitive)?.contentOrNull ?: "",
                note = (o["note"] as? JsonPrimitive)?.contentOrNull,
            )
            } catch (_: Exception) { null }
        }

        fun parseError(code: Int, body: String?): Pair<String, String> {
            val o = try { body?.let { Json.parseToJsonElement(it) as? JsonObject } } catch (_: Exception) { null }
            val err = (o?.get("error") as? JsonPrimitive)?.contentOrNull ?: "http_$code"
            val msg = (o?.get("message") as? JsonPrimitive)?.contentOrNull ?: when (err) {
                "invalid_code" -> "Código inválido. Confira e tente de novo."
                "revoked" -> "Este código foi desativado."
                "limit_reached" -> "Este código já atingiu o limite de pessoas."
                "rate_limited" -> "Muitas tentativas. Tente de novo em alguns minutos."
                "bad_request" -> "Formato de código inválido."
                else -> "Não foi possível validar o código agora."
            }
            return err to msg
        }
    }

    // ---------------- Identidade ----------------

    /** UUID gerado uma vez; mistura o hash do Android ID (seed) apenas como reforço de identidade. */
    fun deviceId(): String {
        store.get(K_DEVICE)?.let { if (it.length in 8..128) return it }
        val seed = deviceSeed()
        val id = (UUID.randomUUID().toString() + if (seed.isNotEmpty()) "-" + seed.take(12) else "")
            .filter { it.isLetterOrDigit() || it == '-' }.take(128)
        store.put(K_DEVICE, id)
        return id
    }

    // ---------------- Config ----------------

    fun cachedConfig(): RemoteConfig? = store.get(K_CONFIG)?.let { parseConfig(it) }

    /** Busca a config remota (timeout 6 s) e guarda a última resposta válida. */
    suspend fun refreshConfig(): RemoteConfig? {
        try {
            val r = http.get(AccessConfig.CONFIG_URL, 6000)
            if (r.code in 200..299 && r.body != null) {
                val cfg = parseConfig(r.body)
                if (cfg != null) { store.put(K_CONFIG, r.body); return cfg }
            }
        } catch (_: IOException) {}
        return cachedConfig()
    }

    /** Base efetiva da API: config remota (se não vazia) > constante compilada. Vazia = portão desligado. */
    fun effectiveApiBase(cfg: RemoteConfig? = cachedConfig()): String =
        cfg?.apiBase?.takeIf { it.isNotEmpty() } ?: AccessConfig.DEFAULT_API_BASE

    fun gateEnabled(cfg: RemoteConfig? = cachedConfig()): Boolean =
        effectiveApiBase(cfg).isNotEmpty() && (cfg?.required ?: true)

    // ---------------- Estado salvo ----------------

    fun savedInfo(): AccessInfo? = store.get(K_INFO)?.let { try { json.decodeFromString(AccessInfo.serializer(), it) } catch (_: Exception) { null } }

    private fun saveInfo(i: AccessInfo?) {
        store.put(K_INFO, i?.let { json.encodeToString(AccessInfo.serializer(), it) })
    }

    /** Estado inicial sem rede (para abrir o app na hora). */
    fun loadInitialState(): AccessState {
        val st = decide(cachedConfig(), savedInfo())
        _state.value = st
        return st
    }

    private fun decide(cfg: RemoteConfig?, info: AccessInfo?): AccessState {
        if (!gateEnabled(cfg)) return AccessState.Open
        if (info != null && info.isValidAt(now())) return AccessState.Active(info)
        return AccessState.Locked(if (info != null) "Seu acesso terminou. Fale com quem te enviou o código." else null)
    }

    fun lastCheckAt(): Long = store.get(K_LAST_CHECK)?.toLongOrNull() ?: 0L
    fun shouldCheck(): Boolean = now() - lastCheckAt() >= AccessConfig.CHECK_INTERVAL_MS

    // ---------------- Ativação ----------------

    suspend fun activate(rawCode: String, deviceName: String? = null): ActivateResult {
        val code = normalizeCode(rawCode)
        if (!isValidCodeFormat(code)) return ActivateResult.Failure("bad_request", "O código tem 6 letras e números.")
        val base = effectiveApiBase()
        if (base.isEmpty()) return ActivateResult.Failure("no_panel", "O painel ainda não está disponível.")
        val body = buildString {
            append("{\"code\":\"").append(code).append("\",\"device\":\"").append(deviceId())
            append("\",\"platform\":\"").append(AccessConfig.PLATFORM).append("\",\"app\":\"").append(AccessConfig.APP_VERSION).append('"')
            if (!deviceName.isNullOrBlank()) append(",\"name\":").append(JsonPrimitive(deviceName).toString())
            append('}')
        }
        val r = try { http.post("$base/api/access/activate", body, null, 10_000) }
        catch (_: IOException) { return ActivateResult.Failure("network", "Sem conexão. Verifique a internet e tente de novo.") }
        if (r.code == 200 && r.body != null) {
            val info = parseInfo(r.body, null, code)
            if (info != null && info.token.isNotEmpty()) {
                saveInfo(info)
                store.put(K_LAST_CHECK, now().toString())
                _state.value = AccessState.Active(info)
                return ActivateResult.Success(info)
            }
        }
        if (r.code >= 500) return ActivateResult.Failure("server", "O servidor está indisponível. Tente de novo em instantes.")
        val (err, msg) = parseError(r.code, r.body)
        return ActivateResult.Failure(err, msg)
    }

    // ---------------- Verificação ----------------

    /**
     * Checa o acesso no servidor. Rede/5xx/timeout mantém liberado se ainda válido; só 401/403 bloqueia.
     * Retorna o estado resultante.
     */
    suspend fun check(): AccessState {
        val cfg = refreshConfig()
        if (!gateEnabled(cfg)) { _state.value = AccessState.Open; return AccessState.Open }
        val info = savedInfo()
        if (info == null) { _state.value = AccessState.Locked(); return _state.value }
        val base = effectiveApiBase(cfg)
        val body = "{\"device\":\"${deviceId()}\",\"app\":\"${AccessConfig.APP_VERSION}\",\"platform\":\"${AccessConfig.PLATFORM}\"}"
        val r = try { http.post("$base/api/access/check", body, info.token, 8000) } catch (_: IOException) { null }
        val st: AccessState = when {
            r == null || r.code >= 500 || r.code == 408 || r.code == 429 -> decide(cfg, info)
            r.code == 200 && r.body != null -> {
                val fresh = parseInfo(r.body, info.token, info.code)
                if (fresh != null) {
                    saveInfo(fresh); store.put(K_LAST_CHECK, now().toString())
                    if (fresh.isValidAt(now())) AccessState.Active(fresh) else AccessState.Locked(fresh.message.ifEmpty { null })
                } else decide(cfg, info)
            }
            r.code == 401 || r.code == 403 -> {
                val (_, msg) = parseError(r.code, r.body)
                saveInfo(null)
                AccessState.Locked(msg)
            }
            else -> decide(cfg, info)
        }
        _state.value = st
        return st
    }

    /** "Trocar código": apaga o acesso salvo e volta para a tela de código. */
    fun signOut() {
        saveInfo(null)
        _state.value = if (gateEnabled()) AccessState.Locked() else AccessState.Open
    }
}
