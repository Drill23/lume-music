package com.adriano.lumemusic.access

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import java.io.IOException

/** Contrato v2/v2.1/v2.2: compra do vitalício por Pix (Mercado Pago automático ou chave manual) + PIN + transferência. */
@Serializable
data class PixData(
    val key: String? = null,
    val name: String = "",
    val copiaECola: String = "",
    val automatic: Boolean = false,
)

@Serializable
data class PurchaseOrder(
    val orderId: String,
    val status: String = "pending",
    val amount: Int = 0,
    val amountText: String = "",
    val plan: String = "",
    val checkoutUrl: String? = null,
    val pix: PixData? = null,
    val pollSeconds: Int = 5,
    val expiresAt: Long = 0,
)

data class PurchaseStatus(val orderId: String, val status: String, val code: String?, val message: String)
data class TransferCode(val code: String, val expiresAt: Long)

sealed class PurchaseResult<out T> {
    data class Ok<T>(val value: T) : PurchaseResult<T>()
    data class Err(val error: String, val message: String) : PurchaseResult<Nothing>()
}

class PurchaseService(
    private val http: AccessHttp,
    private val store: SecureStore,
    private val access: AccessService,
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    companion object {
        const val K_PENDING = "purchase.pending.json"
        const val K_PAID_CODE = "purchase.paid.code"
        const val K_PAID_ORDER = "purchase.paid.order"
        const val K_PIN_HASH = "purchase.pin.hash"
        const val K_PRICE = "purchase.price"
        const val K_PIN_PENDING = "purchase.pin.pending"
        private val json = Json { ignoreUnknownKeys = true; isLenient = true }

        private fun JsonObject.s(k: String) = (this[k] as? JsonPrimitive)?.contentOrNull
        private fun JsonObject.l(k: String) = (this[k] as? JsonPrimitive)?.longOrNull
        private fun JsonObject.b(k: String) = (this[k] as? JsonPrimitive)?.booleanOrNull

        fun parseOrder(body: String): PurchaseOrder? = try {
            val o = Json.parseToJsonElement(body) as? JsonObject
            if (o == null || o.b("ok") != true) null else {
                val px = o["pix"] as? JsonObject
                val orderId = o.s("orderId")
                if (orderId.isNullOrEmpty()) null else PurchaseOrder(
                    orderId = orderId,
                    status = o.s("status") ?: "pending",
                    amount = o.l("amount")?.toInt() ?: 0,
                    amountText = o.s("amountText") ?: "",
                    plan = o.s("plan") ?: "",
                    checkoutUrl = o.s("checkoutUrl")?.takeIf { it.isNotBlank() && it != "null" },
                    pix = px?.let { PixData(it.s("key")?.takeIf { k -> k.isNotBlank() }, it.s("name") ?: "", it.s("copiaECola") ?: "", it.b("automatic") ?: false) },
                    pollSeconds = (o.l("pollSeconds")?.toInt() ?: 5).coerceIn(2, 60),
                    expiresAt = o.l("expiresAt") ?: (px?.l("expiresAt") ?: 0L),
                )
            }
        } catch (_: Exception) { null }

        fun parseStatus(body: String): PurchaseStatus? = try {
            val o = Json.parseToJsonElement(body) as? JsonObject
            if (o == null || o.b("ok") != true) null else PurchaseStatus(
                orderId = o.s("orderId") ?: "", status = o.s("status") ?: "pending",
                code = o.s("code")?.takeIf { it.isNotBlank() }?.let { AccessService.normalizeCode(it) }, message = o.s("message") ?: "",
            )
        } catch (_: Exception) { null }

        fun parseTransferCode(body: String, now: Long): TransferCode? = try {
            val o = Json.parseToJsonElement(body) as? JsonObject
            val c = o?.s("transferCode") ?: o?.s("code")
            if (o == null || o.b("ok") != true || c.isNullOrBlank()) null
            else TransferCode(AccessService.normalizeCode(c), o.l("expiresAt") ?: o.l("expires") ?: (now + 15 * 60_000L))
        } catch (_: Exception) { null }

        /** "R$ 5,00" -> "R$ 5" (rótulos curtos dos botões). */
        fun shortPrice(text: String): String = text.replace(Regex(",00$"), "").ifBlank { "R$ 5" }
    }

    private fun err(code: Int, body: String?, fallback: String): PurchaseResult.Err {
        val (e, m) = AccessService.parseError(code, body)
        val msg = when (e) {
            "rate_limited" -> if (code == 429 && body?.contains("message") != true) "Muitas tentativas. Tente de novo mais tarde." else m
            "purchase_disabled" -> if (body?.contains("message") != true) "A compra ainda não está disponível. Tente mais tarde." else m
            else -> if (m.startsWith("Não foi possível validar")) fallback else m
        }
        return PurchaseResult.Err(e, msg)
    }

    private val noNet = PurchaseResult.Err("network", "Sem conexão. Verifique a internet e tente de novo.")
    private val noPanel = PurchaseResult.Err("no_panel", "O painel ainda não está disponível.")
    private fun base() = access.effectiveApiBase()

    // ---------------- pedido pendente / preço / flags ----------------

    fun pendingOrder(): PurchaseOrder? {
        val o = store.get(K_PENDING)?.let { try { json.decodeFromString(PurchaseOrder.serializer(), it) } catch (_: Exception) { null } } ?: return null
        if (o.expiresAt in 1 until now()) { clearPending(); return null }
        return o
    }
    fun clearPending() = store.put(K_PENDING, null)
    fun priceText(): String = store.get(K_PRICE) ?: "R$ 5,00"
    fun paidCode(): String? = store.get(K_PAID_CODE)
    fun paidOrder(): String? = store.get(K_PAID_ORDER)
    fun setPaidCode(c: String?, order: String? = null) { store.put(K_PAID_CODE, c); store.put(K_PAID_ORDER, if (c == null) null else order) }

    // PIN: o painel guarda só o hash; aqui fica um hash local com sal só para travar o "Ver meu código" neste aparelho.
    private fun pinHash(pin: String, salt: String): String =
        java.security.MessageDigest.getInstance("SHA-256").digest("$salt:$pin".toByteArray()).joinToString("") { "%02x".format(it) }
    private fun savePinLocally(pin: String) {
        val salt = java.util.UUID.randomUUID().toString().take(12)
        store.put(K_PIN_HASH, "$salt:${pinHash(pin, salt)}")
    }
    /** true/false = conferido localmente; null = este aparelho não conhece o PIN (criado em outro). */
    fun verifyLocalPin(pin: String): Boolean? {
        val v = store.get(K_PIN_HASH) ?: return null
        val (salt, h) = v.split(":", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
        return pinHash(pin, salt) == h
    }

    /**
     * "Ver meu código": exige o PIN. Com PIN conhecido localmente e código salvo, mostra direto; senão pergunta ao painel
     * (/api/purchase/restore, mesmo aparelho; a resposta traz code e order) e salva.
     */
    suspend fun revealCode(pin: String): PurchaseResult<Pair<String, String?>> {
        if (!isValidPin(pin)) return PurchaseResult.Err("bad_request", "O PIN tem 6 números.")
        val local = verifyLocalPin(pin)
        if (local == false) return PurchaseResult.Err("bad_pin", "PIN incorreto.")
        val saved = access.lifetimeCode()
        if (local == true && saved != null) return PurchaseResult.Ok(saved to access.lifetimeOrder())
        return when (val r = access.restorePurchase(saved, access.lifetimeOrder(), pin)) {
            is ActivateResult.Success -> {
                // Sem PIN conhecido neste aparelho, só mostra o código se o PAINEL confirmou o PIN.
                if (local != true && !r.info.pinVerified) {
                    PurchaseResult.Err("pin_unverified", "Não foi possível confirmar o seu PIN agora. Tente de novo em instantes.")
                } else {
                    savePinLocally(pin)
                    PurchaseResult.Ok(r.info.code to (r.info.purchase ?: access.lifetimeOrder()))
                }
            }
            is ActivateResult.Failure -> PurchaseResult.Err(r.error, r.message)
        }
    }
    fun pinPending(): Boolean = store.get(K_PIN_PENDING) == "1"
    fun setPinPending(v: Boolean) = store.put(K_PIN_PENDING, if (v) "1" else null)

    // ---------------- API ----------------

    suspend fun create(method: String = "pix"): PurchaseResult<PurchaseOrder> {
        val b = base(); if (b.isEmpty()) return noPanel
        val body = "{\"device\":\"${access.deviceId()}\",\"platform\":\"${AccessConfig.PLATFORM}\",\"app\":\"${AccessConfig.APP_VERSION}\",\"method\":\"$method\"}"
        val r = try { http.post("$b/api/purchase/create", body, null, 12_000) } catch (_: IOException) { return noNet }
        if (r.code == 200 && r.body != null) {
            val o = parseOrder(r.body) ?: return PurchaseResult.Err("bad_response", "Resposta inesperada do servidor.")
            store.put(K_PENDING, json.encodeToString(PurchaseOrder.serializer(), o))
            if (o.amountText.isNotBlank()) store.put(K_PRICE, o.amountText)
            return PurchaseResult.Ok(o)
        }
        if (r.code >= 500 && r.code != 503) return PurchaseResult.Err("server", "O servidor está indisponível. Tente de novo em instantes.")
        return err(r.code, r.body, "Não foi possível criar o pedido agora.")
    }

    /** Consulta o pedido. Se vier `paid` com código: guarda o código (vitalício pegajoso) e limpa o pedido pendente. */
    suspend fun status(orderId: String): PurchaseResult<PurchaseStatus> {
        val b = base(); if (b.isEmpty()) return noPanel
        val url = "$b/api/purchase/status?order=${java.net.URLEncoder.encode(orderId, "UTF-8")}&device=${java.net.URLEncoder.encode(access.deviceId(), "UTF-8")}"
        val r = try { http.get(url, 8000) } catch (_: IOException) { return noNet }
        if (r.code == 200 && r.body != null) {
            val st = parseStatus(r.body) ?: return PurchaseResult.Err("bad_response", "Resposta inesperada do servidor.")
            when (st.status) {
                "paid" -> if (st.code != null) { access.rememberLifetime(st.code, orderId); setPaidCode(st.code, orderId); clearPending() }
                "canceled" -> clearPending()
            }
            return PurchaseResult.Ok(st)
        }
        if (r.code >= 500) return PurchaseResult.Err("server", "O servidor está indisponível.")
        return err(r.code, r.body, "Não foi possível consultar o pedido agora.")
    }

    suspend fun claim(orderId: String): PurchaseResult<Unit> {
        val b = base(); if (b.isEmpty()) return noPanel
        val body = "{\"order\":\"$orderId\",\"device\":\"${access.deviceId()}\"}"
        val r = try { http.post("$b/api/purchase/claim", body, null, 10_000) } catch (_: IOException) { return noNet }
        if (r.code == 200) return PurchaseResult.Ok(Unit)
        if (r.code >= 500) return PurchaseResult.Err("server", "O servidor está indisponível. Tente de novo em instantes.")
        return err(r.code, r.body, "Não foi possível avisar o pagamento agora.")
    }

    /** "Restaurar compra" (mesmo aparelho): código vitalício ou número do pedido. */
    suspend fun restore(raw: String): ActivateResult {
        val parsed = AccessService.parseRestoreInput(raw)
            ?: return ActivateResult.Failure("bad_request", "Digite o código vitalício (6 caracteres) ou o número do pedido (LM-XXXXXX).")
        return access.restorePurchase(parsed.first, parsed.second)
    }

    /** Ativa o código vitalício recebido pelo pagamento (o painel já ativou este aparelho: activate devolve o token). */
    suspend fun activatePaid(code: String): ActivateResult {
        val r = access.activate(code, null)
        if (r is ActivateResult.Success) { setPaidCode(null); setPinPending(true) }
        return r
    }

    /** POST /api/purchase/pin: PIN de recuperação (6 dígitos). */
    suspend fun setPin(pin: String): PurchaseResult<Unit> {
        if (!isValidPin(pin)) return PurchaseResult.Err("bad_request", "O PIN tem 6 números.")
        val b = base(); if (b.isEmpty()) return noPanel
        val token = access.savedToken() ?: return PurchaseResult.Err("no_token", "Ative seu acesso antes de criar o PIN.")
        val body = "{\"device\":\"${access.deviceId()}\",\"token\":${JsonPrimitive(token)},\"pin\":\"$pin\"}"
        val r = try { http.post("$b/api/purchase/pin", body, token, 10_000) } catch (_: IOException) { return noNet }
        if (r.code == 200) { setPinPending(false); savePinLocally(pin); return PurchaseResult.Ok(Unit) }
        if (r.code >= 500) return PurchaseResult.Err("server", "O servidor está indisponível. Tente de novo em instantes.")
        return err(r.code, r.body, "Não foi possível salvar o PIN agora.")
    }

    /** POST /api/purchase/transfer-code: código de 8 caracteres, 15 min, uso único. */
    suspend fun transferCode(): PurchaseResult<TransferCode> {
        val b = base(); if (b.isEmpty()) return noPanel
        val token = access.savedToken() ?: return PurchaseResult.Err("no_token", "Abra a Lume com internet para gerar o código de transferência.")
        val body = "{\"device\":\"${access.deviceId()}\",\"token\":${JsonPrimitive(token)}}"
        val r = try { http.post("$b/api/purchase/transfer-code", body, token, 10_000) } catch (_: IOException) { return noNet }
        if (r.code == 200 && r.body != null) {
            val tc = parseTransferCode(r.body, now()) ?: return PurchaseResult.Err("bad_response", "Resposta inesperada do servidor.")
            return PurchaseResult.Ok(tc)
        }
        if (r.code >= 500) return PurchaseResult.Err("server", "O servidor está indisponível. Tente de novo em instantes.")
        return err(r.code, r.body, "Não foi possível gerar o código agora.")
    }
}
