package com.adriano.lumemusic.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.access.AccessInfo
import com.adriano.lumemusic.access.AccessService
import com.adriano.lumemusic.access.AccessState
import com.adriano.lumemusic.access.ActivateResult
import com.adriano.lumemusic.access.PixData
import com.adriano.lumemusic.access.Purchase
import com.adriano.lumemusic.access.PurchaseOrder
import com.adriano.lumemusic.access.PurchaseResult
import com.adriano.lumemusic.access.PurchaseService
import com.adriano.lumemusic.access.TrialResult
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Estado global do upgrade: pop-ups de boas-vindas, tela de compra, pagamento confirmado, PIN, transferência, recuperação. */
object UpgradeModel {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val svc get() = Purchase.service

    // ---- pop-ups / telas ----
    var welcomeDays by mutableStateOf<Int?>(null); private set
    var welcomeReminder by mutableStateOf(false); private set
    var showUpgrade by mutableStateOf(false); private set
    var paidCode by mutableStateOf<String?>(null); private set
    var paidOrder by mutableStateOf<String?>(null); private set
    /** "Ver meu código": depois do PIN, (código, pedido) ficam visíveis no cartão enquanto os Ajustes estão abertos. */
    var revealed by mutableStateOf<Pair<String, String?>?>(null)
    var showReveal by mutableStateOf(false)
    /** "activating" | "done" | "error" (erro de rede: tenta de novo) | "denied" (recusa do servidor). */
    var paidPhase by mutableStateOf("activating"); private set
    var paidError by mutableStateOf<String?>(null); private set
    /** null | "create" (obrigatório, depois do pagamento) | "change" (Ajustes › Trocar PIN). */
    var pinMode by mutableStateOf<String?>(null)
    var showTransfer by mutableStateOf(false)
    var showRecover by mutableStateOf(false)
    var showRestore by mutableStateOf(false)
    var showCodeEntry by mutableStateOf(false)

    // ---- pedido ----
    var order by mutableStateOf<PurchaseOrder?>(null); private set
    var loading by mutableStateOf(false); private set
    var loadError by mutableStateOf<String?>(null); private set
    /** "none" | "sending" | "review" */
    var claimState by mutableStateOf("none"); private set
    var statusMessage by mutableStateOf<String?>(null); private set
    var priceText by mutableStateOf("R$ 5,00"); private set
    val shortPrice get() = PurchaseService.shortPrice(priceText)

    // ---- teste grátis automático (v2.3) ----
    /** null (não rodou) | "running" | "ok" | "disabled" | "used" | "nopanel" | "offline" | "error". */
    var trialOutcome by mutableStateOf<String?>(null); private set
    /** Motivo vindo do painel quando o teste não pôde começar (ex.: limite da rede): aparece no passo de código. */
    var trialMessage by mutableStateOf<String?>(null); private set
    var debugTrialDays by mutableStateOf<Int?>(null); private set
    var debugTrialUsed by mutableStateOf(false); private set

    /** Chamado nas boas-vindas do onboarding, sem travar a animação (timeout de 8 s no serviço). */
    fun runTrial() {
        if (trialOutcome != null) return
        trialOutcome = "running"
        debugTrialDays?.let { trialOutcome = "ok"; return }
        if (debugTrialUsed) { trialOutcome = "used"; return }
        scope.launch {
            trialOutcome = when (val t = Access.service.startTrial(firstOpen = true)) {
                is TrialResult.Started -> "ok"
                TrialResult.Disabled -> "disabled"
                TrialResult.NoPanel -> "nopanel"
                is TrialResult.Used -> "used"
                is TrialResult.Failed -> { trialMessage = t.message.takeIf { !t.network && it.isNotBlank() }; if (t.network) "offline" else "error" }
            }
        }
    }

    suspend fun awaitTrial() { withTimeoutOrNull(10_000) { while (trialOutcome == "running") delay(100) } }

    /** O passo de código só aparece quando o painel desligou o teste (ou o teste foi recusado) e ainda não há acesso. */
    fun trialNeedsCodeStep(): Boolean =
        Access.service.gateEnabled() && Access.service.state.value !is AccessState.Active && trialOutcome in setOf("disabled", "error")

    // ---- depuração ----
    var debugFake by mutableStateOf(false); private set
    var debugManual by mutableStateOf(false); private set

    fun init() {
        priceText = svc.priceText()
        if (!debugFake) order = svc.pendingOrder()
        svc.paidCode()?.let { startPaid(it, svc.paidOrder()) }
        if (svc.pinPending() && (Access.service.state.value as? AccessState.Active)?.info?.lifetime == true) pinMode = "create"
    }

    // ============================================================ Boas-vindas

    private fun shown(code: String, n: Int) = Purchase.prefs.get("welcome.$code.$n") == "1"
    private fun mark(code: String, n: Int) = Purchase.prefs.put("welcome.$code.$n", "1")

    /** Chamado quando o usuário passou da tela de sucesso da ativação. */
    fun onActivated(info: AccessInfo) {
        if (info.lifetime) return
        val d = info.daysLeft(System.currentTimeMillis()) ?: return
        mark(info.code, 0); if (d <= 3) mark(info.code, 3); if (d <= 1) mark(info.code, 1)
        welcomeReminder = false; welcomeDays = d
    }

    /** Reaparece uma vez com 3 e com 1 dia restantes. */
    fun checkMilestones(info: AccessInfo) {
        if (info.lifetime || welcomeDays != null || showUpgrade || paidCode != null) return
        val d = info.daysLeft(System.currentTimeMillis()) ?: return
        // Teste automático: "Você tem N dias grátis" uma vez, no fim do onboarding.
        if (info.trial && !shown(info.code, 0)) {
            mark(info.code, 0); if (d <= 3) mark(info.code, 3); if (d <= 1) mark(info.code, 1)
            welcomeReminder = false; welcomeDays = d; return
        }
        val n = when { d == 1 -> 1; d in 2..3 -> 3; else -> return }
        if (shown(info.code, n)) return
        mark(info.code, n); if (n == 1) mark(info.code, 3)
        welcomeReminder = true; welcomeDays = d
    }

    fun dismissWelcome() { welcomeDays = null }

    // ============================================================ Tela de upgrade

    fun openUpgrade() {
        welcomeDays = null; showUpgrade = true
        scope.launch { loadOrder() }
    }

    fun closeUpgrade() { showUpgrade = false }

    suspend fun loadOrder() {
        if (debugFake) { order = fakeOrder(); loading = false; return }
        loadError = null; loading = order == null
        when (val r = svc.create("pix")) {
            is PurchaseResult.Ok -> { order = r.value; priceText = svc.priceText(); claimState = if (r.value.status == "review") "review" else "none" }
            is PurchaseResult.Err -> loadError = r.message
        }
        loading = false
    }

    fun claim() {
        val o = order ?: return
        if (claimState != "none") return
        if (debugFake) { claimState = "review"; statusMessage = "Recebemos seu aviso. Assim que o pagamento for confirmado, seu código aparece aqui."; return }
        claimState = "sending"; loadError = null
        scope.launch {
            when (val r = svc.claim(o.orderId)) {
                is PurchaseResult.Ok -> { claimState = "review"; statusMessage = "Recebemos seu aviso. Assim que o pagamento for confirmado, seu código aparece aqui." }
                is PurchaseResult.Err -> { claimState = "none"; loadError = r.message }
            }
        }
    }

    /** Intervalo do polling: pollSeconds com a tela aberta; mais espaçado só com o pedido pendente em segundo plano de tela. */
    fun pollDelayMs(): Long {
        val s = (order?.pollSeconds ?: 5).coerceIn(2, 60) * 1000L
        return if (showUpgrade) s else maxOf(s, 30_000L)
    }

    fun hasPending(): Boolean = !debugFake && paidCode == null && (order != null || svc.pendingOrder() != null)

    suspend fun pollOnce() {
        if (debugFake) return
        val id = order?.orderId ?: svc.pendingOrder()?.orderId ?: return
        when (val r = svc.status(id)) {
            is PurchaseResult.Ok -> when (r.value.status) {
                "paid" -> r.value.code?.let { startPaid(it, id) }
                "review" -> { claimState = "review"; statusMessage = r.value.message.ifBlank { null } }
                "canceled" -> { order = null; statusMessage = r.value.message.ifBlank { "Pedido cancelado." } }
            }
            is PurchaseResult.Err -> {}
        }
    }

    // ============================================================ Pagamento confirmado

    private fun startPaid(code: String, orderId: String?) {
        showUpgrade = false; welcomeDays = null; order = null
        paidOrder = orderId; paidCode = code; paidPhase = "activating"; paidError = null
        activatePaid()
    }

    fun activatePaid() {
        val code = paidCode ?: return
        paidPhase = "activating"; paidError = null
        scope.launch {
            when (val r = svc.activatePaid(code)) {
                is ActivateResult.Success -> paidPhase = "done"
                is ActivateResult.Failure -> { paidPhase = if (r.explicit) "denied" else "error"; paidError = r.message }
            }
        }
    }

    fun finishPaid() {
        paidCode = null; paidOrder = null; svc.setPaidCode(null)
        if (!debugFake && svc.pinPending()) pinMode = "create"
    }

    // ============================================================ Depuração

    private fun fakeOrder() = PurchaseOrder(
        orderId = "LM-DEBUG1", status = "pending", amount = 500, amountText = "R$ 5,00", plan = "Vitalício",
        checkoutUrl = null,
        pix = PixData(
            key = if (debugManual) "d0a9a4ea-96dd-4125-b161-1d7fc83ffd1d" else null, name = if (debugManual) "ADRIANO ALMEIDA" else "Lume Music",
            copiaECola = "00020126580014br.gov.bcb.pix0136d0a9a4ea-96dd-4125-b161-1d7fc83ffd1d52040000530398654041.005802BR5913ADRIANO ALMEIDA6006BRASIL62100506LMDEBUG63041D3F",
            automatic = !debugManual,
        ),
        pollSeconds = 5,
    )

    fun debugUpgrade(manual: Boolean) { debugFake = true; debugManual = manual; order = fakeOrder(); claimState = "none"; showUpgrade = true }
    fun debugTrial(days: Int) { debugTrialDays = days; welcomeReminder = false; welcomeDays = days }
    fun debugTrialUsed() { debugTrialUsed = true }
    fun debugWelcome(days: Int) { welcomeReminder = false; welcomeDays = days }
    fun debugPaid(code: String) { debugFake = true; showUpgrade = false; paidOrder = "LM-7K3Q9X"; paidCode = code; paidPhase = "done"; paidError = null }
    fun debugTransfer() { debugFake = true; showTransfer = true }
    fun debugPin() { debugFake = true; pinMode = "create" }
}
