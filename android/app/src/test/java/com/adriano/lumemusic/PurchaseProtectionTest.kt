package com.adriano.lumemusic

import com.adriano.lumemusic.access.AccessHttp
import com.adriano.lumemusic.access.AccessService
import com.adriano.lumemusic.access.AccessState
import com.adriano.lumemusic.access.ActivateResult
import com.adriano.lumemusic.access.HttpResult
import com.adriano.lumemusic.access.PurchaseResult
import com.adriano.lumemusic.access.PurchaseService
import com.adriano.lumemusic.access.SecureStore
import com.adriano.lumemusic.access.TrialResult
import com.adriano.lumemusic.ui.QrMatrix
import com.adriano.lumemusic.update.UpdateService
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

private class Mem : SecureStore {
    val m = HashMap<String, String>()
    override fun get(key: String) = m[key]
    override fun put(key: String, value: String?) { if (value == null) m.remove(key) else m[key] = value }
}

/** Respostas por final de URL; null = IOException (rede caiu). */
private class RouteHttp : AccessHttp {
    var config: HttpResult? = HttpResult(200, """{"apiBase":"https://painel.test","required":true}""")
    val routes = HashMap<String, HttpResult?>()
    val calls = ArrayList<String>()
    val bodies = ArrayList<String>()
    override suspend fun get(url: String, timeoutMs: Long): HttpResult {
        calls += url
        if (url.contains("painel.json")) return config ?: throw IOException("offline")
        val key = routes.keys.firstOrNull { url.contains(it) } ?: return HttpResult(404, "")
        return routes[key] ?: throw IOException("offline")
    }
    override suspend fun post(url: String, json: String, bearer: String?, timeoutMs: Long): HttpResult {
        calls += url; bodies += json
        val key = routes.keys.firstOrNull { url.endsWith(it) } ?: return HttpResult(404, "")
        return routes[key] ?: throw IOException("offline")
    }
}

class PurchaseProtectionTest {
    private fun lifetimeBody(token: String = "tok_${"y".repeat(43)}", purchase: String = "LM-7K3Q9X") =
        """{"ok":true,"token":"$token","code":"AB12CD","lifetime":true,"expires":null,"plan":{"kind":"lifetime","value":0},"message":"Vitalício","purchase":"$purchase"}"""

    private fun svc(http: RouteHttp, store: Mem, lt: Mem, now: Long = 1_000_000L) = AccessService(store, http, now = { now }, lifetimeStore = lt)

    private fun activated(http: RouteHttp, store: Mem, lt: Mem): AccessService {
        http.routes["/api/access/activate"] = HttpResult(200, lifetimeBody())
        return svc(http, store, lt).also { runBlocking { it.refreshConfig(); it.activate("AB12CD") } }
    }

    @Test fun lifetimeSavedInOwnStoreWithOrder() {
        val http = RouteHttp(); val store = Mem(); val lt = Mem()
        activated(http, store, lt)
        assertEquals("AB12CD", lt.get(AccessService.K_LT_CODE))
        assertEquals("LM-7K3Q9X", lt.get(AccessService.K_LT_ORDER))
        assertNull(lt.get("lume.access.info"))   // token fica fora do arquivo que entra no backup
    }

    @Test fun appUpdatePreservesLifetime() = runBlocking {
        val http = RouteHttp(); val store = Mem(); val lt = Mem()
        activated(http, store, lt)
        val device = svc(http, store, lt).deviceId()
        // "atualização": novo processo, mesmos arquivos, painel fora do ar e config remota sem URL
        http.config = null; http.routes["/api/access/check"] = null
        val updated = svc(http, store, lt)
        assertTrue(updated.loadInitialState() is AccessState.Active)
        assertTrue(updated.check() is AccessState.Active)
        assertEquals(device, updated.deviceId())   // device id estável
        http.config = HttpResult(200, """{"apiBase":"","required":false}""")
        assertTrue(updated.check().let { it is AccessState.Active && it.info.lifetime })
    }

    @Test fun backupRestoreOnlyLifetimeFileStartsActiveAndRestoresToken() = runBlocking {
        val http = RouteHttp(); val lt = Mem()
        activated(http, Mem(), lt)
        val fresh = svc(http, Mem(), lt)   // reinstalação: token e device perdidos, só o arquivo do vitalício voltou
        assertTrue(fresh.loadInitialState() is AccessState.Active)
        http.routes["/api/purchase/restore"] = HttpResult(200, lifetimeBody("tok_${"z".repeat(43)}"))
        val st = fresh.check() as AccessState.Active
        assertEquals("tok_${"z".repeat(43)}", st.info.token)
    }

    @Test fun networkAndServerErrorsNeverBlockLifetime() = runBlocking {
        val http = RouteHttp(); val store = Mem(); val lt = Mem()
        val s = activated(http, store, lt)
        for (r in listOf<HttpResult?>(null, HttpResult(500, ""), HttpResult(503, "x"), HttpResult(408, ""), HttpResult(429, ""), HttpResult(200, "lixo"), HttpResult(404, "nada"))) {
            http.routes["/api/access/check"] = r
            assertTrue("falhou com $r", s.check() is AccessState.Active)
        }
    }

    @Test fun lifetimeNeverDowngradedByCheck() = runBlocking {
        val http = RouteHttp(); val store = Mem(); val lt = Mem()
        val s = activated(http, store, lt)
        http.routes["/api/access/check"] = HttpResult(200, """{"ok":true,"code":"AB12CD","lifetime":false,"expires":1,"message":"x"}""")
        assertTrue((s.check() as AccessState.Active).info.lifetime)
    }

    @Test fun expiredFreeCodeStillLocksOnlyWhenNotLifetime() = runBlocking {
        val http = RouteHttp()
        val s = svc(http, Mem(), Mem())
        assertTrue(s.check() is AccessState.Locked)
    }

    @Test fun unauthorizedWithSavedLifetimeCodeRestoresSilently() = runBlocking {
        val http = RouteHttp(); val store = Mem(); val lt = Mem()
        val s = activated(http, store, lt)
        http.routes["/api/access/check"] = HttpResult(401, """{"ok":false,"error":"invalid_token","message":"Token inválido."}""")
        http.routes["/api/purchase/restore"] = HttpResult(200, lifetimeBody("tok_${"r".repeat(43)}"))
        val st = s.check()
        assertTrue(st is AccessState.Active)
        assertEquals("tok_${"r".repeat(43)}", s.savedInfo()?.token)
        assertTrue(http.calls.any { it.endsWith("/api/purchase/restore") })
    }

    @Test fun restoreFailureShowsGateWithPrefilledCode() = runBlocking {
        val http = RouteHttp(); val store = Mem(); val lt = Mem()
        val s = activated(http, store, lt)
        http.routes["/api/access/check"] = HttpResult(403, """{"ok":false,"error":"device_removed","message":"Aparelho removido."}""")
        http.routes["/api/purchase/restore"] = HttpResult(403, """{"ok":false,"error":"transfer_required","message":"Este código vitalício já está em uso em outro aparelho."}""")
        val st = s.check() as AccessState.Locked
        assertEquals("AB12CD", st.prefillCode)
        assertTrue(st.message!!.contains("em uso"))
        // reinício do app: não reabre sozinho (negativa explícita)
        assertTrue(svc(http, store, lt).loadInitialState() is AccessState.Locked)
    }

    @Test fun transferredAndRevokedAreRespectedWithoutRestore() = runBlocking {
        for (err in listOf("transferred", "revoked")) {
            val http = RouteHttp(); val store = Mem(); val lt = Mem()
            val s = activated(http, store, lt)
            http.routes["/api/access/check"] = HttpResult(403, """{"ok":false,"error":"$err","message":"msg do servidor"}""")
            http.calls.clear()
            val st = s.check() as AccessState.Locked
            assertEquals("msg do servidor", st.message)
            assertFalse(http.calls.any { it.endsWith("/api/purchase/restore") })
            assertNull(s.savedInfo())
            if (err == "transferred") assertNull(s.lifetimeCode())
        }
    }

    @Test fun transferByCodeAndByPin() = runBlocking {
        val http = RouteHttp(); val store = Mem(); val lt = Mem()
        val s = svc(http, store, lt); s.refreshConfig()
        http.routes["/api/purchase/transfer"] = HttpResult(200, lifetimeBody())
        assertTrue(s.transferWithCode("k7m2 p9qx") is ActivateResult.Success)
        assertEquals("AB12CD", s.lifetimeCode())
        val s2 = svc(http, Mem(), Mem()); s2.refreshConfig()
        assertTrue(s2.transferWithPin("ab12cd", "123456") is ActivateResult.Success)
        assertTrue((s2.transferWithPin("ab12cd", "12") as ActivateResult.Failure).error == "bad_request")
        assertTrue((s2.transferWithCode("123") as ActivateResult.Failure).error == "bad_request")
        http.routes["/api/purchase/transfer"] = HttpResult(429, """{"ok":false,"error":"transfer_limit"}""")
        val f = s2.transferWithCode("K7M2P9QX") as ActivateResult.Failure
        assertEquals("transfer_limit", f.error)
        assertTrue(f.message.contains("3 vezes"))
    }

    @Test fun restoreInputParsing() {
        assertEquals("AB12CD" to null, AccessService.parseRestoreInput(" ab-12cd "))
        assertEquals(null to "LM-7K3Q9X", AccessService.parseRestoreInput("lm-7k3q9x"))
        assertEquals(null to "LM-7K3Q9X", AccessService.parseRestoreInput("LM7K3Q9X"))
        assertNull(AccessService.parseRestoreInput("12"))
    }

    // ---------------- Compra ----------------

    private val createAuto = """{"ok":true,"orderId":"LM-7K3Q9X","status":"pending","amount":1000,"amountText":"R$ 10,00","plan":"Vitalício",
        "checkoutUrl":null,"pix":{"key":null,"name":"Lume Music","copiaECola":"00020126...6304ABCD","qrBase64":"iVBOR","automatic":true,"expiresAt":1764300000000},
        "pollSeconds":5,"expiresAt":1764300000000}"""

    @Test fun parseCreateAutomaticAndManual() {
        val o = PurchaseService.parseOrder(createAuto)!!
        assertEquals("LM-7K3Q9X", o.orderId)
        assertNull(o.checkoutUrl)
        assertTrue(o.pix!!.automatic)
        assertNull(o.pix!!.key)
        assertEquals("R$ 10,00", o.amountText)
        assertEquals(5, o.pollSeconds)
        val m = PurchaseService.parseOrder("""{"ok":true,"orderId":"LM-AAAAAA","status":"pending","amount":1000,"amountText":"R$ 10,00","plan":"Vitalício",
            "checkoutUrl":"https://x.y/c","pix":{"key":"d0a9a4ea","name":"ADRIANO ALMEIDA","copiaECola":"0002","automatic":false},"pollSeconds":5,"expiresAt":1}""")!!
        assertEquals("https://x.y/c", m.checkoutUrl)
        assertFalse(m.pix!!.automatic)
        assertEquals("d0a9a4ea", m.pix!!.key)
        assertNull(PurchaseService.parseOrder("""{"ok":false}"""))
        assertNull(PurchaseService.parseOrder("lixo"))
    }

    @Test fun parseStatusAndTransferCode() {
        val s = PurchaseService.parseStatus("""{"ok":true,"orderId":"LM-1","status":"paid","code":"ab12cd","message":"Pagamento confirmado!"}""")!!
        assertEquals("paid", s.status); assertEquals("AB12CD", s.code)
        assertNull(PurchaseService.parseStatus("""{"ok":true,"orderId":"LM-1","status":"pending","code":null,"message":"x"}""")!!.code)
        val t = PurchaseService.parseTransferCode("""{"ok":true,"transferCode":"k7m2p9qx","expiresAt":99}""", 0)!!
        assertEquals("K7M2P9QX", t.code); assertEquals(99L, t.expiresAt)
        assertEquals("R$ 10", PurchaseService.shortPrice("R$ 10,00"))
    }

    @Test fun createStoresPendingAndStatusPaidKeepsLifetimeCode() = runBlocking {
        val http = RouteHttp(); val store = Mem(); val lt = Mem(); val prefs = Mem()
        val access = svc(http, store, lt); access.refreshConfig()
        val p = PurchaseService(http, prefs, access, now = { 1_000_000L })
        http.routes["/api/purchase/create"] = HttpResult(200, createAuto)
        assertTrue(p.create() is PurchaseResult.Ok)
        assertEquals("LM-7K3Q9X", p.pendingOrder()?.orderId)
        assertEquals("R$ 10,00", p.priceText())
        http.routes["/api/purchase/status"] = HttpResult(200, """{"ok":true,"orderId":"LM-7K3Q9X","status":"paid","code":"AB12CD","message":"ok"}""")
        val st = (p.status("LM-7K3Q9X") as PurchaseResult.Ok).value
        assertEquals("AB12CD", st.code)
        assertEquals("AB12CD", lt.get(AccessService.K_LT_CODE))   // protegido já no pagamento
        assertEquals("LM-7K3Q9X", lt.get(AccessService.K_LT_ORDER))
        assertNull(p.pendingOrder())
        assertEquals("AB12CD", p.paidCode())
        http.routes["/api/access/activate"] = HttpResult(200, lifetimeBody())
        assertTrue(p.activatePaid("AB12CD") is ActivateResult.Success)
        assertTrue(p.pinPending()); assertNull(p.paidCode())
    }

    @Test fun createErrorsAndNetwork() = runBlocking {
        val http = RouteHttp(); val access = svc(http, Mem(), Mem()); access.refreshConfig()
        val p = PurchaseService(http, Mem(), access)
        http.routes["/api/purchase/create"] = HttpResult(503, """{"ok":false,"error":"purchase_disabled"}""")
        assertEquals("purchase_disabled", (p.create() as PurchaseResult.Err).error)
        http.routes["/api/purchase/create"] = HttpResult(429, """{"ok":false,"error":"rate_limited"}""")
        assertEquals("rate_limited", (p.create() as PurchaseResult.Err).error)
        http.routes["/api/purchase/create"] = null
        assertEquals("network", (p.create() as PurchaseResult.Err).error)
    }

    @Test fun pinAndTransferCodeNeedToken() = runBlocking {
        val http = RouteHttp(); val store = Mem(); val lt = Mem()
        val access = activated(http, store, lt)
        val p = PurchaseService(http, Mem(), access)
        http.routes["/api/purchase/pin"] = HttpResult(200, """{"ok":true}""")
        assertTrue(p.setPin("123456") is PurchaseResult.Ok)
        assertEquals("bad_request", (p.setPin("12") as PurchaseResult.Err).error)
        http.routes["/api/purchase/transfer-code"] = HttpResult(200, """{"ok":true,"transferCode":"K7M2P9QX","expiresAt":2000000}""")
        assertEquals("K7M2P9QX", (p.transferCode() as PurchaseResult.Ok).value.code)
    }

    // ---------------- Atualização + QR ----------------

    @Test fun updateParsingAndPostpone() = runBlocking {
        val body = """{"ok":true,"available":true,"platform":"android","build":8,"versionName":"5.1.1","url":"https://x/a.apk","notes":"• n","mandatory":false}"""
        val u = UpdateService.parse(body)!!
        assertEquals(8, u.build); assertEquals("5.1.1", u.versionName)
        assertNull(UpdateService.parse("""{"ok":true,"available":false}"""))
        assertNull(UpdateService.parse(body.replace("https://", "http://")))   // só https
        var now = 1_000L
        val http = RouteHttp().also { it.routes["/api/app/update"] = HttpResult(200, body) }
        val st = Mem()
        val svc = UpdateService(http, st, { "https://painel.test" }, { now })
        assertNull(svc.fetch(8, "5.1.1"))   // build igual: sem oferta
        assertNotNull(svc.fetch(7, "5.1.0"))
        assertTrue(http.calls.last().contains("platform=android&build=7&app=5.1.0"))
        assertFalse(svc.shouldCheck())
        now += UpdateService.INTERVAL_MS; assertTrue(svc.shouldCheck())
        assertFalse(svc.isPostponed(u)); svc.postpone(u); assertTrue(svc.isPostponed(u))
        now += UpdateService.POSTPONE_MS; assertFalse(svc.isPostponed(u))
        assertNull(UpdateService(http, Mem(), { "" }).fetch(1, "x"))   // sem apiBase e sem fallback: sem oferta
        val mand = u.copy(mandatory = true); svc.postpone(mand); assertFalse(svc.isPostponed(mand))
    }

    @Test fun updateSiteManifestAndGitHubFallback() = runBlocking {
        assertTrue(UpdateService.compareVersions("5.1.10", "5.1.6") > 0)
        assertTrue(UpdateService.compareVersions("v5.2.0", "5.1.9") > 0)
        assertEquals(0, UpdateService.compareVersions("5.1.6-debug", "5.1.6"))

        // 1. Painel retorna available=false → cai no manifesto público do site (version.json)
        val httpSite = RouteHttp().apply {
            routes["/api/app/update"] = HttpResult(200, """{"ok":true,"available":false}""")
            routes["version.json"] = HttpResult(200, """{"versionName":"5.1.7","build":14,"notes":"• Novidades","android":{"url":"https://github.com/Drill23/lume-music/releases/latest/download/Lume-Music-Android.apk"}}""")
        }
        val svcSite = UpdateService(httpSite, Mem(), { "https://painel.test" })
        val fromSite = svcSite.fetch(13, "5.1.6")!!
        assertEquals(14, fromSite.build)
        assertEquals("5.1.7", fromSite.versionName)
        assertNull(svcSite.fetch(14, "5.1.7"))

        // 1b. Manifesto do site diz que Android está atualizado (5.1.7) mesmo com GitHub em tag 5.1.8 (ex.: release só de iOS) → NÃO oferece falso update!
        val httpIso = RouteHttp().apply {
            routes["/api/app/update"] = HttpResult(200, """{"ok":true,"available":false}""")
            routes["version.json"] = HttpResult(200, """{"android":{"build":14,"versionName":"5.1.7","url":"https://github.com/Drill23/lume-music/releases/latest/download/Lume-Music-Android.apk"},"ios":{"build":15,"versionName":"5.1.8","url":"https://github.com/Drill23/lume-music/releases/latest/download/Lume-Music-iPhone.ipa"}}""")
            routes["releases/latest"] = HttpResult(200, """{"tag_name":"v5.1.8","body":"Só iOS","assets":[{"name":"Lume-Music-Android.apk","browser_download_url":"https://github.com/Drill23/lume-music/releases/download/v5.1.8/Lume-Music-Android.apk"}]}""")
        }
        assertNull(UpdateService(httpIso, Mem(), { "https://painel.test" }).fetch(14, "5.1.7"))

        // 2. Painel e site sem oferta → cai direto no GitHub Releases por semver
        val httpGh = RouteHttp().apply {
            routes["/api/app/update"] = HttpResult(200, """{"ok":true,"available":false}""")
            routes["releases/latest"] = HttpResult(200, """{"tag_name":"v5.1.8","body":"### Novidades\n• Correção","assets":[{"name":"Lume-Music-Android.apk","browser_download_url":"https://github.com/Drill23/lume-music/releases/download/v5.1.8/Lume-Music-Android.apk"}]}""")
        }
        val svcGh = UpdateService(httpGh, Mem(), { "https://painel.test" })
        val fromGh = svcGh.fetch(13, "5.1.6")!!
        assertEquals("5.1.8", fromGh.versionName)
        assertTrue(fromGh.url.endsWith("Lume-Music-Android.apk"))
        assertNull(svcGh.fetch(13, "5.1.8"))
        assertFalse(svcGh.isPostponed(fromGh)); svcGh.postpone(fromGh); assertTrue(svcGh.isPostponed(fromGh))
    }

    @Test fun qrMatrixGenerated() {
        val m = QrMatrix.build("00020126580014br.gov.bcb.pix0136d0a9a4ea-96dd-4125-b161-1d7fc83ffd1d52040000530398654041.005802BR5913ADRIANO ALMEIDA6006BRASIL62100506LMDEBUG63041D3F")!!
        assertTrue(m.size >= 29); assertEquals(m.size, m[0].size)
        assertTrue(m[0][0] && m[0][6])   // finder pattern
    }

    // ---------------- Recuperação do código (PIN / pedido) ----------------

    @Test fun normalizeOrderAcceptsLooseInput() {
        assertEquals("LM-7K3Q9X", AccessService.normalizeOrder("lm-7k3q9x"))
        assertEquals("LM-7K3Q9X", AccessService.normalizeOrder(" LM7K3Q9X "))
        assertEquals("LM-7K3Q9X", AccessService.normalizeOrder("7k3q9x"))
        assertNull(AccessService.normalizeOrder("LM-12"))
    }

    @Test fun restoreAnswerCarriesCodeAndOrderAndIsSaved() = runBlocking {
        val http = RouteHttp(); val lt = Mem()
        val s = svc(http, Mem(), lt); s.refreshConfig()
        http.routes["/api/purchase/restore"] = HttpResult(200, """{"ok":true,"token":"tok_${"q".repeat(43)}","code":"AB12CD","order":"LM-7K3Q9X","lifetime":true,"expires":null,"message":"ok"}""")
        val r = s.restorePurchase(null, null, "123456") as ActivateResult.Success
        assertEquals("LM-7K3Q9X", r.info.purchase)
        assertEquals("AB12CD", lt.get(AccessService.K_LT_CODE))
        assertEquals("LM-7K3Q9X", lt.get(AccessService.K_LT_ORDER))
        assertTrue(http.bodies.last().contains("\"pin\":\"123456\""))
    }

    @Test fun revealCodeNeedsPinLocalHashThenRestoreWhenNoCode() = runBlocking {
        val http = RouteHttp(); val store = Mem(); val lt = Mem(); val prefs = Mem()
        val access = activated(http, store, lt)
        val p = PurchaseService(http, prefs, access)
        http.routes["/api/purchase/pin"] = HttpResult(200, """{"ok":true}""")
        assertTrue(p.setPin("123456") is PurchaseResult.Ok)
        // PIN errado: nunca mostra
        assertEquals("bad_pin", (p.revealCode("654321") as PurchaseResult.Err).error)
        assertEquals("bad_request", (p.revealCode("12") as PurchaseResult.Err).error)
        // PIN certo + código salvo: mostra direto (sem rede)
        http.calls.clear()
        val ok = (p.revealCode("123456") as PurchaseResult.Ok).value
        assertEquals("AB12CD" to "LM-7K3Q9X", ok)
        assertTrue(http.calls.isEmpty())
        // código não salvo no aparelho: pergunta ao painel (restore, mesmo device) e salva
        lt.put(AccessService.K_LT_CODE, null); lt.put(AccessService.K_LT_ORDER, null)
        http.routes["/api/purchase/restore"] = HttpResult(200, lifetimeBody())
        val again = (p.revealCode("123456") as PurchaseResult.Ok).value
        assertEquals("AB12CD", again.first)
        assertEquals("AB12CD", lt.get(AccessService.K_LT_CODE))
        assertTrue(http.calls.any { it.endsWith("/api/purchase/restore") })
    }

    @Test fun revealCodeWithoutLocalPinAsksServer() = runBlocking {
        val http = RouteHttp(); val lt = Mem()
        val access = activated(http, Mem(), lt)
        val p = PurchaseService(http, Mem(), access)   // PIN criado em outro aparelho: sem hash local
        http.routes["/api/purchase/restore"] = HttpResult(403, """{"ok":false,"error":"bad_pin","message":"PIN incorreto."}""")
        assertEquals("PIN incorreto.", (p.revealCode("111111") as PurchaseResult.Err).message)
        // painel respondeu 200 mas NÃO confirmou o PIN (versão antiga do painel): não mostra o código
        http.routes["/api/purchase/restore"] = HttpResult(200, lifetimeBody())
        assertEquals("pin_unverified", (p.revealCode("111111") as PurchaseResult.Err).error)
        // painel confirmou o PIN: mostra
        http.routes["/api/purchase/restore"] = HttpResult(200, lifetimeBody().replaceFirst("{", "{\"pinVerified\":true,"))
        assertTrue(p.revealCode("111111") is PurchaseResult.Ok)
    }

    @Test fun forgotCodeTransferByOrderAndPinSavesCode() = runBlocking {
        val http = RouteHttp(); val lt = Mem()
        val s = svc(http, Mem(), lt); s.refreshConfig()
        http.routes["/api/purchase/transfer"] = HttpResult(200, lifetimeBody())
        val r = s.transferWithOrder("lm7k3q9x", "123456")
        assertTrue(r is ActivateResult.Success)
        assertTrue(http.bodies.last().contains("\"order\":\"LM-7K3Q9X\"") && http.bodies.last().contains("\"pin\":\"123456\""))
        assertEquals("AB12CD", lt.get(AccessService.K_LT_CODE))
        assertEquals("bad_request", (s.transferWithOrder("12", "123456") as ActivateResult.Failure).error)
        assertEquals("bad_request", (s.transferWithOrder("LM-7K3Q9X", "1") as ActivateResult.Failure).error)
        http.routes["/api/purchase/transfer"] = HttpResult(429, """{"ok":false,"error":"rate_limited","message":"Muitas tentativas de PIN."}""")
        assertEquals("Muitas tentativas de PIN.", (s.transferWithOrder("LM-7K3Q9X", "000000") as ActivateResult.Failure).message)
    }

    // ---------------- Teste grátis automático (v2.3) ----------------

    private val trialBody = """{"ok":true,"token":"tok_${"t".repeat(43)}","code":"TR1AL2","lifetime":false,"expires":${1_000_000L + 7 * 86_400_000L},
        "plan":{"kind":"days","value":7},"message":"Você tem 7 dias grátis.","trial":true}"""

    @Test fun trialStartsOnFirstOpenAndSendsHw() = runBlocking {
        val http = RouteHttp().also { it.routes["/api/trial/start"] = HttpResult(200, trialBody) }
        val store = Mem()
        val s = AccessService(store, http, now = { 1_000_000L }, hw = { "hwhash" })
        val r = s.startTrial(firstOpen = true) as TrialResult.Started
        assertTrue(r.info.trial)
        assertEquals(7, r.info.daysLeft(1_000_000L))
        assertTrue(http.bodies.last().contains("\"hw\":\"hwhash\""))
        assertTrue(s.state.value is AccessState.Active)
        assertTrue(s.savedInfo()!!.trial)
        // check seguinte não perde a marca de teste
        http.routes["/api/access/check"] = HttpResult(200, """{"ok":true,"code":"TR1AL2","lifetime":false,"expires":${1_000_000L + 7 * 86_400_000L},"message":"x"}""")
        assertTrue((s.check() as AccessState.Active).info.trial)
    }

    @Test fun trialDisabledGoesBackToCodeStep() = runBlocking {
        val http = RouteHttp().also { it.routes["/api/trial/start"] = HttpResult(200, """{"ok":true,"enabled":false}""") }
        val s = svc(http, Mem(), Mem())
        assertEquals(TrialResult.Disabled, s.startTrial(firstOpen = true))
        assertTrue(s.check() is AccessState.Locked)   // sem tolerância: o passo de código antigo decide
    }

    @Test fun trialUsedShowsGateWithServerMessage() = runBlocking {
        val msg = "Seu teste grátis já terminou neste aparelho. Garanta a Lume para sempre com o Vitalício."
        val http = RouteHttp().also { it.routes["/api/trial/start"] = HttpResult(403, """{"ok":false,"error":"trial_used","message":"$msg"}""") }
        val store = Mem()
        val s = svc(http, store, Mem())
        assertEquals(TrialResult.Used(msg), s.startTrial(firstOpen = true))
        assertEquals(msg, (s.state.value as AccessState.Locked).message)
        assertEquals(msg, (svc(http, store, Mem()).loadInitialState() as AccessState.Locked).message)   // persiste
        http.calls.clear()
        assertTrue(s.startTrial() is TrialResult.Used)
        assertTrue(http.calls.none { it.contains("trial/start") })   // não insiste
    }

    @Test fun trialNetworkErrorLetsEnterOnlyFor24HoursOnFirstOpen() = runBlocking {
        val http = RouteHttp().also { it.routes["/api/trial/start"] = null }
        val store = Mem()
        var now = 1_000_000L
        val s = AccessService(store, http, now = { now })
        val r = s.startTrial(firstOpen = true) as TrialResult.Failed
        assertTrue(r.network)
        assertEquals(AccessState.Open, s.check())                 // deixa entrar (tenta de novo em segundo plano)
        http.routes["/api/trial/start"] = HttpResult(200, trialBody.replace("1_000_000", ""))
        val ok = s.check()                                          // a nova tentativa funcionou
        assertTrue(ok is AccessState.Active)
        // mesmo cenário, mas a rede nunca volta: depois de 24 h exige teste/código
        val http2 = RouteHttp().also { it.routes["/api/trial/start"] = null }
        val s2 = AccessService(Mem(), http2, now = { now })
        s2.startTrial(firstOpen = true)
        now += AccessService.TRIAL_GRACE_MS + 1
        assertTrue(s2.check() is AccessState.Locked)
    }

    @Test fun trialRateLimitedIsNotNetworkAndManualCodeBeatsTrial() = runBlocking {
        val http = RouteHttp().also { it.routes["/api/trial/start"] = HttpResult(429, """{"ok":false,"error":"trial_rate_limited","message":"Muitos testes hoje."}""") }
        val s = svc(http, Mem(), Mem())
        val f = s.startTrial(firstOpen = true) as TrialResult.Failed
        assertFalse(f.network); assertEquals("Muitos testes hoje.", f.message)
        // código com prazo maior ativado enquanto o teste carregava: o teste não rebaixa
        val s2 = svc(RouteHttp().also { it.routes["/api/trial/start"] = HttpResult(200, trialBody) }, Mem(), Mem())
        s2.refreshConfig()
        val http3 = RouteHttp(); val st3 = Mem()
        http3.routes["/api/access/activate"] = HttpResult(200, lifetimeBody())
        http3.routes["/api/trial/start"] = HttpResult(200, trialBody)
        val s3 = svc(http3, st3, Mem()); s3.refreshConfig(); s3.activate("AB12CD")
        val t = s3.startTrial() as TrialResult.Started
        assertTrue(t.info.lifetime)
    }

    @Test fun noPanelMeansNoTrial() = runBlocking {
        val http = RouteHttp().also { it.config = HttpResult(200, """{"apiBase":"","required":true}"""); it.routes["/api/trial/start"] = HttpResult(200, trialBody) }
        assertEquals(TrialResult.NoPanel, svc(http, Mem(), Mem()).startTrial(firstOpen = true))
        assertTrue(http.calls.none { it.contains("trial/start") })
    }
}
