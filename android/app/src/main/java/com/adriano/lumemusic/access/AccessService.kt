package com.adriano.lumemusic.access

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.sync.withLock
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
    val APP_VERSION: String = com.adriano.lumemusic.BuildConfig.VERSION_NAME.removeSuffix("-debug")
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
    /** Número do pedido ("LM-XXXXXX") quando o código veio de uma compra. */
    val purchase: String? = null,
    /** Teste grátis automático (v2.3). Só vem no /api/trial/start; o app carrega a marca nos checks seguintes. */
    val trial: Boolean = false,
    /** O painel conferiu o PIN enviado no /api/purchase/restore ("Ver meu código"). */
    val pinVerified: Boolean = false,
) {
    /** Dias que faltam (arredondado para cima); null se vitalício/sem prazo. */
    fun daysLeft(now: Long): Int? = if (lifetime) null else expires?.let { Math.ceil((it - now) / 86_400_000.0).toInt().coerceAtLeast(0) }
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
    /** [prefillCode]: código vitalício salvo, para o portão já vir preenchido com "Restaurar compra". */
    data class Locked(val message: String? = null, val prefillCode: String? = null) : AccessState()
    data class Active(val info: AccessInfo) : AccessState()
}

sealed class TrialResult {
    data class Started(val info: AccessInfo) : TrialResult()
    /** Painel com o teste desligado: usa o passo de código antigo. */
    data object Disabled : TrialResult()
    /** Painel ainda sem URL / portão desligado: nada a fazer. */
    data object NoPanel : TrialResult()
    /** 403 trial_used: o teste deste aparelho já terminou. */
    data class Used(val message: String) : TrialResult()
    /** [network]: rede/5xx (tolerância de 24 h na primeira abertura); senão recusa (ex.: trial_rate_limited). */
    data class Failed(val error: String, val message: String, val network: Boolean) : TrialResult()
}

sealed class ActivateResult {
    data class Success(val info: AccessInfo) : ActivateResult()
    /** [explicit]: negativa explícita do servidor (401/403), diferente de rede/5xx. */
    data class Failure(val error: String, val message: String, val explicit: Boolean = false) : ActivateResult()
}

class AccessService(
    private val store: SecureStore,
    private val http: AccessHttp,
    private val now: () -> Long = { System.currentTimeMillis() },
    private val deviceSeed: () -> String = { "" },
    /** Código vitalício + nº do pedido: arquivo próprio que entra no Auto Backup (sem token). Padrão: o mesmo [store]. */
    private val lifetimeStore: SecureStore = store,
    /** Hash do hardware (Android: SHA-256 de ANDROID_ID + package); sobrevive à reinstalação com a mesma assinatura. */
    private val hw: () -> String = { "" },
) {
    private val trialMutex = kotlinx.coroutines.sync.Mutex()
    /** Chamado depois que um vitalício é ativado, transferido ou restaurado neste aparelho (dispara a restauração da biblioteca). */
    @Volatile var onLifetimeAdopted: ((AccessInfo) -> Unit)? = null
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val _state = MutableStateFlow<AccessState>(AccessState.Open)
    val state: StateFlow<AccessState> = _state

    companion object {
        private const val K_CONFIG = "lume.access.config"
        private const val K_INFO = "lume.access.info"
        private const val K_DEVICE = "lume.access.device"
        private const val K_LAST_CHECK = "lume.access.lastCheck"
        private const val K_DENIED = "lume.access.lifetimeDenied"
        private const val K_FIRST_OPEN = "lume.trial.firstOpen"
        private const val K_TRIAL_USED = "lume.trial.used"
        const val TRIAL_GRACE_MS = 24 * 3600_000L
        const val K_LT_CODE = "lume.lifetime.code"
        const val K_LT_ORDER = "lume.lifetime.order"
        private val ORDER_RE = Regex("^LM-?[A-Z0-9]{6}$")
        private val DENY_ERRORS = setOf("transferred", "revoked")
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
                purchase = ((o["purchase"] as? JsonPrimitive)?.contentOrNull ?: (o["order"] as? JsonPrimitive)?.contentOrNull)?.takeIf { it.isNotBlank() },
                pinVerified = (o["pinVerified"] as? JsonPrimitive)?.contentOrNull == "true",
                trial = (o["trial"] as? JsonPrimitive)?.booleanOrNull ?: false,
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
                "transferred" -> "Sua conta Lume Vitalício foi transferida para outro aparelho. Se não foi você, fale com o suporte."
                "transfer_required" -> "Este código vitalício já está em uso em outro aparelho. Para trazer sua conta, use Transferir no aparelho antigo ou o seu PIN de recuperação."
                "trial_used" -> "Seu teste grátis já terminou neste aparelho. Garanta a Lume para sempre com o Vitalício."
                "trial_rate_limited" -> "Muitos testes a partir desta conexão hoje. Tente de novo mais tarde ou use um código."
                "transfer_limit" -> "Você já transferiu sua conta 3 vezes neste mês. Fale com o suporte."
                else -> "Não foi possível validar o código agora."
            }
            return err to msg
        }

        /** "lm-7k3q9x", "LM7K3Q9X" ou só "7k3q9x" -> "LM-7K3Q9X"; null se não for um pedido. */
        fun normalizeOrder(raw: String): String? {
            var up = raw.uppercase().filter { !it.isWhitespace() && it != '-' }
            if (up.startsWith("LM") && up.length == 8) up = up.removePrefix("LM")
            return if (up.length == 6 && up.all { it.isLetterOrDigit() }) "LM-$up" else null
        }

        /** Entrada do "Restaurar compra": 6 caracteres = código; "LM-XXXXXX" = nº do pedido. Retorna (código, pedido). */
        fun parseRestoreInput(raw: String): Pair<String?, String?>? {
            val up = raw.uppercase().filter { !it.isWhitespace() }
            if (ORDER_RE.matches(up)) return null to ("LM-" + up.removePrefix("LM").removePrefix("-"))
            val code = normalizeCode(raw)
            return if (isValidCodeFormat(code)) code to null else null
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

    // ---------------- Vitalício pegajoso ----------------

    fun lifetimeCode(): String? = lifetimeStore.get(K_LT_CODE)?.takeIf { isValidCodeFormat(it) }
    fun lifetimeOrder(): String? = lifetimeStore.get(K_LT_ORDER)?.takeIf { it.isNotBlank() }
    fun savedToken(): String? = savedInfo()?.token?.takeIf { it.isNotEmpty() }
    private fun denied() = store.get(K_DENIED) == "1"

    /** Guarda o código vitalício (e o pedido) para sobreviver a atualizações, reinstalações e Auto Backup. */
    fun rememberLifetime(code: String, order: String? = null) {
        if (!isValidCodeFormat(code)) return
        lifetimeStore.put(K_LT_CODE, code)
        if (!order.isNullOrBlank()) lifetimeStore.put(K_LT_ORDER, order)
        store.put(K_DENIED, null)
    }

    private fun rememberLifetime(info: AccessInfo) { if (info.lifetime) rememberLifetime(info.code, info.purchase) }

    private fun stickyInfo(code: String) = AccessInfo(code = code, token = "", lifetime = true, message = "Acesso vitalício", purchase = lifetimeOrder())

    /** Recusa explícita (transferred/revoked/…): tira o acesso local e impede o vitalício pegajoso de reabrir sozinho. */
    private fun markDenied(clearCode: Boolean) {
        saveInfo(null)
        store.put(K_DENIED, "1")
        if (clearCode) { lifetimeStore.put(K_LT_CODE, null); lifetimeStore.put(K_LT_ORDER, null) }
    }

    private fun decide(cfg: RemoteConfig?, info: AccessInfo?): AccessState {
        val lcode = lifetimeCode()
        // Vitalício é pegajoso: rede, servidor, timeout, painel sem apiBase ou resposta estranha nunca bloqueiam.
        if (info?.lifetime == true) return AccessState.Active(info)
        if (info == null && lcode != null && !denied()) return AccessState.Active(stickyInfo(lcode))
        if (!gateEnabled(cfg)) return AccessState.Open
        if (info != null && info.isValidAt(now())) return AccessState.Active(info)
        if (info == null && inTrialGrace()) return AccessState.Open
        return AccessState.Locked(if (info != null) "Seu acesso terminou. Fale com quem te enviou o código." else store.get(K_TRIAL_USED), lcode)
    }

    // ---------------- Teste grátis automático (v2.3) ----------------

    /** Tolerância de rede só na PRIMEIRA abertura: até 24 h sem acesso confirmado, o app deixa entrar. */
    private fun inTrialGrace(): Boolean {
        val first = store.get(K_FIRST_OPEN)?.toLongOrNull() ?: return false
        return store.get(K_TRIAL_USED) == null && now() - first < TRIAL_GRACE_MS
    }
    fun trialUsedMessage(): String? = store.get(K_TRIAL_USED)

    /**
     * POST /api/trial/start. [firstOpen]: chamada das boas-vindas do onboarding (marca a primeira abertura para a tolerância de 24 h).
     * Mesmo aparelho/hw nunca renova: o painel devolve a mesma ativação ou 403 trial_used.
     */
    suspend fun startTrial(firstOpen: Boolean = false): TrialResult = trialMutex.withLock { startTrialLocked(firstOpen) }

    private suspend fun startTrialLocked(firstOpen: Boolean): TrialResult {
        val cfg = cachedConfig() ?: refreshConfig()
        if (!gateEnabled(cfg)) return TrialResult.NoPanel
        if (firstOpen && store.get(K_FIRST_OPEN) == null) store.put(K_FIRST_OPEN, now().toString())
        savedInfo()?.takeIf { it.token.isNotEmpty() && it.isValidAt(now()) }?.let { return TrialResult.Started(it) }
        store.get(K_TRIAL_USED)?.let { return TrialResult.Used(it) }
        val base = effectiveApiBase(cfg)
        val r = try { http.post("$base/api/trial/start", baseBody("hw" to hw()), null, 8_000) }
        catch (_: IOException) { return TrialResult.Failed("network", "Sem conexão. Verifique a internet e tente de novo.", true) }
        if (r.code == 200 && r.body != null) {
            val o = try { Json.parseToJsonElement(r.body) as? JsonObject } catch (_: Exception) { null }
            if ((o?.get("enabled") as? JsonPrimitive)?.booleanOrNull == false) { store.put(K_FIRST_OPEN, null); return TrialResult.Disabled }
            val info = parseInfo(r.body, null, null)?.copy(trial = true)
            if (info != null && info.token.isNotEmpty()) {
                val cur = savedInfo()
                // Se a pessoa já ativou um código de prazo maior (ou vitalício) enquanto o teste carregava, o painel não rebaixa: o app também não.
                if (cur != null && cur.token.isNotEmpty() && (cur.lifetime || (cur.expires ?: 0L) >= (info.expires ?: 0L)) && cur.isValidAt(now())) return TrialResult.Started(cur)
                adopt(info)
                return TrialResult.Started(info)
            }
        }
        if (r.code >= 500) return TrialResult.Failed("server", "O servidor está indisponível. Tente de novo em instantes.", true)
        val (err, msg) = parseError(r.code, r.body)
        if (err == "trial_used") {
            store.put(K_TRIAL_USED, msg)
            _state.value = AccessState.Locked(msg, lifetimeCode())
            return TrialResult.Used(msg)
        }
        return TrialResult.Failed(err, msg, false)
    }

    fun lastCheckAt(): Long = store.get(K_LAST_CHECK)?.toLongOrNull() ?: 0L
    fun shouldCheck(): Boolean = now() - lastCheckAt() >= AccessConfig.CHECK_INTERVAL_MS

    // ---------------- Ativação ----------------

    private fun baseBody(vararg extra: Pair<String, String?>): String = buildString {
        append("{\"device\":\"").append(deviceId()).append("\",\"platform\":\"").append(AccessConfig.PLATFORM)
        append("\",\"app\":\"").append(AccessConfig.APP_VERSION).append('"')
        for ((k, v) in extra) if (!v.isNullOrBlank()) append(",\"").append(k).append("\":").append(JsonPrimitive(v).toString())
        append('}')
    }

    private fun adopt(info: AccessInfo) {
        saveInfo(info)
        rememberLifetime(info)
        store.put(K_LAST_CHECK, now().toString())
        _state.value = AccessState.Active(info)
        if (info.lifetime) try { onLifetimeAdopted?.invoke(info) } catch (_: Exception) {}
    }

    /** POST que devolve o fluxo do activate (activate, restore, transfer): adota o token e o estado. */
    private suspend fun postActivation(path: String, body: String, fallbackCode: String?): ActivateResult {
        val base = effectiveApiBase()
        if (base.isEmpty()) return ActivateResult.Failure("no_panel", "O painel ainda não está disponível.")
        val r = try { http.post("$base$path", body, null, 10_000) }
        catch (_: IOException) { return ActivateResult.Failure("network", "Sem conexão. Verifique a internet e tente de novo.") }
        if (r.code == 200 && r.body != null) {
            val info = parseInfo(r.body, null, fallbackCode)
            if (info != null && info.token.isNotEmpty()) { adopt(info); return ActivateResult.Success(info) }
        }
        if (r.code >= 500) return ActivateResult.Failure("server", "O servidor está indisponível. Tente de novo em instantes.")
        val (err, msg) = parseError(r.code, r.body)
        return ActivateResult.Failure(err, msg, explicit = r.code in 401..403 || r.code == 429)
    }

    suspend fun activate(rawCode: String, deviceName: String? = null): ActivateResult {
        val code = normalizeCode(rawCode)
        if (!isValidCodeFormat(code)) return ActivateResult.Failure("bad_request", "O código tem 6 letras e números.")
        return postActivation("/api/access/activate", baseBody("code" to code, "name" to deviceName), code)
    }

    /** "Restaurar compra" / restore automático (SÓ no mesmo aparelho; outro aparelho recebe transfer_required). */
    suspend fun restorePurchase(code: String?, order: String?, pin: String? = null): ActivateResult {
        if (code == null && order == null && pin == null) return ActivateResult.Failure("bad_request", "Digite o código vitalício ou o número do pedido.")
        val r = postActivation("/api/purchase/restore", baseBody("code" to code, "order" to order, "pin" to pin), code)
        if (r is ActivateResult.Failure && r.error in setOf("http_404", "http_405") && code != null) return activate(code)
        return r
    }

    /** Aparelho novo: código de transferência de 8 caracteres gerado no aparelho antigo. */
    suspend fun transferWithCode(raw: String): ActivateResult {
        val tc = normalizeCode(raw)
        if (tc.length != 8) return ActivateResult.Failure("bad_request", "O código de transferência tem 8 caracteres.")
        return postActivation("/api/purchase/transfer", baseBody("transferCode" to tc), null)
    }

    /** Aparelho antigo perdido: código vitalício + PIN de recuperação. */
    suspend fun transferWithPin(rawCode: String, pin: String): ActivateResult {
        val code = normalizeCode(rawCode)
        if (!isValidCodeFormat(code)) return ActivateResult.Failure("bad_request", "O código vitalício tem 6 letras e números.")
        if (!isValidPin(pin)) return ActivateResult.Failure("bad_request", "O PIN tem 6 números.")
        return postActivation("/api/purchase/transfer", baseBody("code" to code, "pin" to pin), code)
    }

    /** "Esqueci meu código": número do pedido + PIN (a resposta traz o código, que fica salvo). */
    suspend fun transferWithOrder(rawOrder: String, pin: String): ActivateResult {
        val order = normalizeOrder(rawOrder) ?: return ActivateResult.Failure("bad_request", "O número do pedido é LM- e mais 6 caracteres.")
        if (!isValidPin(pin)) return ActivateResult.Failure("bad_request", "O PIN tem 6 números.")
        return postActivation("/api/purchase/transfer", baseBody("order" to order, "pin" to pin), null)
    }

    // ---------------- Verificação ----------------

    /**
     * Checa o acesso no servidor. Rede/5xx/timeout mantém liberado se ainda válido (e sempre se vitalício);
     * só 401/403 explícito bloqueia — e, havendo código vitalício salvo, tenta antes o restore automático (mesmo aparelho).
     * 403 transferred/revoked é respeitado (a pegajosa não o ignora). Retorna o estado resultante.
     */
    suspend fun check(): AccessState {
        val cfg = refreshConfig()
        val info = savedInfo()
        val lcode = lifetimeCode()
        if (!gateEnabled(cfg)) { _state.value = decide(cfg, info); return _state.value }
        if (info == null || info.token.isEmpty()) {
            if (lcode != null && !denied()) return autoRestore(lcode, cfg, info)
            // Primeira abertura que não conseguiu o teste (rede): tenta de novo em segundo plano.
            if (info == null && store.get(K_FIRST_OPEN) != null && store.get(K_TRIAL_USED) == null) {
                when (val t = startTrial()) {
                    is TrialResult.Started -> return _state.value
                    is TrialResult.Used -> return AccessState.Locked(t.message, lcode).also { _state.value = it }
                    else -> {}
                }
            }
            _state.value = decide(cfg, info)
            
            return _state.value
        }
        val base = effectiveApiBase(cfg)
        val r = try { http.post("$base/api/access/check", baseBody(), info.token, 8000) } catch (_: IOException) { null }
        val st: AccessState = when {
            r == null || r.code >= 500 || r.code == 408 || r.code == 429 -> decide(cfg, info)
            r.code == 200 && r.body != null -> {
                val fresh = parseInfo(r.body, info.token, info.code)
                if (fresh == null) decide(cfg, info)
                else if (info.lifetime && !fresh.lifetime) decide(cfg, info)   // nunca rebaixa um vitalício
                else {
                    val keep = fresh.copy(trial = info.trial || fresh.trial)
                    saveInfo(keep); rememberLifetime(keep); store.put(K_LAST_CHECK, now().toString())
                    if (keep.isValidAt(now())) AccessState.Active(keep) else AccessState.Locked(fresh.message.ifEmpty { null }, lifetimeCode())
                }
            }
            r.code == 401 || r.code == 403 -> {
                val (err, msg) = parseError(r.code, r.body)
                when {
                    err in DENY_ERRORS -> { markDenied(clearCode = err == "transferred"); AccessState.Locked(msg, lifetimeCode()) }
                    lcode != null -> return autoRestore(lcode, cfg, info)
                    else -> { saveInfo(null); AccessState.Locked(msg) }
                }
            }
            else -> decide(cfg, info)
        }
        _state.value = st
        return st
    }

    private suspend fun autoRestore(code: String, cfg: RemoteConfig?, current: AccessInfo?): AccessState {
        val r = restorePurchase(code, lifetimeOrder())
        val st = when {
            r is ActivateResult.Success -> AccessState.Active(r.info)
            r is ActivateResult.Failure && r.explicit && r.error != "rate_limited" -> {
                markDenied(clearCode = r.error == "transferred")
                AccessState.Locked(r.message, lifetimeCode())
            }
            else -> decide(cfg, current)   // rede/servidor: segue liberado (pegajoso)
        }
        _state.value = st
        return st
    }

    /** "Trocar código" (só para quem não é vitalício): apaga o acesso salvo e volta para a tela de código. */
    fun signOut() {
        saveInfo(null)
        lifetimeStore.put(K_LT_CODE, null); lifetimeStore.put(K_LT_ORDER, null); store.put(K_DENIED, null)
        _state.value = if (gateEnabled()) AccessState.Locked() else AccessState.Open
    }
}

fun isValidPin(pin: String) = pin.length == 6 && pin.all { it in '0'..'9' }
