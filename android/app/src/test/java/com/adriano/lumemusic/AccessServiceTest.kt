package com.adriano.lumemusic

import com.adriano.lumemusic.access.AccessConfig
import com.adriano.lumemusic.access.AccessHttp
import com.adriano.lumemusic.access.AccessService
import com.adriano.lumemusic.access.AccessState
import com.adriano.lumemusic.access.ActivateResult
import com.adriano.lumemusic.access.HttpResult
import com.adriano.lumemusic.access.SecureStore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

private class MemStore : SecureStore {
    val m = HashMap<String, String>()
    override fun get(key: String) = m[key]
    override fun put(key: String, value: String?) { if (value == null) m.remove(key) else m[key] = value }
}

private class FakeHttp : AccessHttp {
    var configResp: HttpResult? = HttpResult(200, """{"apiBase":"https://painel.test/","required":true}""")
    var activateResp: HttpResult? = null
    var checkResp: HttpResult? = null   // null => IOException
    var lastCheckBearer: String? = null
    override suspend fun get(url: String, timeoutMs: Long): HttpResult = configResp ?: throw IOException("offline")
    override suspend fun post(url: String, json: String, bearer: String?, timeoutMs: Long): HttpResult {
        if (url.endsWith("/activate")) return activateResp ?: throw IOException("offline")
        lastCheckBearer = bearer
        return checkResp ?: throw IOException("offline")
    }
}

class AccessServiceTest {
    private val okBody = """{"ok":true,"token":"tok_${"x".repeat(43)}","code":"AB12CD","lifetime":false,"expires":2000000,
        "plan":{"kind":"months","value":3},"activatedAt":1000,"message":"Código válido por 3 meses.","note":"Obrigado!"}"""

    private fun svc(http: FakeHttp, store: MemStore = MemStore(), now: Long = 1_500_000) =
        AccessService(store, http, now = { now })

    @Test fun normalizeAndValidate() {
        assertEquals("AB12CD", AccessService.normalizeCode(" ab-12 cd "))
        assertTrue(AccessService.isValidCodeFormat("AB12CD"))
        assertFalse(AccessService.isValidCodeFormat("AB12C"))
        assertFalse(AccessService.isValidCodeFormat("AB12C!"))
    }

    @Test fun configParsing() {
        val c = AccessService.parseConfig("""{"apiBase":"https://x.y/","required":false}""")!!
        assertEquals("https://x.y", c.apiBase)
        assertFalse(c.required)
        assertEquals(null, AccessService.parseConfig("nao json"))
    }

    @Test fun gateOffWhenNoApiBase() = runBlocking {
        val http = FakeHttp().apply { configResp = HttpResult(200, """{"apiBase":"","required":true}""") }
        val s = svc(http)
        assertEquals(AccessState.Open, s.check())
    }

    @Test fun gateOffWhenNotRequired() = runBlocking {
        val http = FakeHttp().apply { configResp = HttpResult(200, """{"apiBase":"https://p","required":false}""") }
        assertEquals(AccessState.Open, svc(http).check())
    }

    @Test fun gateOnLocksWithoutToken() = runBlocking {
        val s = svc(FakeHttp())
        assertTrue(s.check() is AccessState.Locked)
    }

    @Test fun deviceIdStableAndValid() {
        val s = svc(FakeHttp())
        val a = s.deviceId()
        assertEquals(a, s.deviceId())
        assertTrue(a.length in 8..128)
        assertTrue(a.all { it.isLetterOrDigit() || it == '-' })
    }

    @Test fun activateSuccessSavesToken() = runBlocking {
        val http = FakeHttp().apply { activateResp = HttpResult(200, okBody) }
        val store = MemStore()
        val s = svc(http, store)
        s.refreshConfig()
        val r = s.activate("ab 12-cd")
        assertTrue(r is ActivateResult.Success)
        val info = (r as ActivateResult.Success).info
        assertEquals("AB••CD", info.maskedCode)
        assertEquals("Obrigado!", info.note)
        assertTrue(info.successMessage().startsWith("Código válido por 3 meses — até"))
        assertTrue(s.state.value is AccessState.Active)
        assertEquals(info, s.savedInfo())
    }

    @Test fun activateErrorsShowServerMessage() = runBlocking {
        val http = FakeHttp().apply {
            activateResp = HttpResult(403, """{"ok":false,"error":"revoked","message":"Este código foi desativado."}""")
        }
        val s = svc(http); s.refreshConfig()
        val r = s.activate("AB12CD") as ActivateResult.Failure
        assertEquals("revoked", r.error)
        assertEquals("Este código foi desativado.", r.message)
    }

    @Test fun activateBadFormatDoesNotCallServer() = runBlocking {
        val r = svc(FakeHttp()).activate("123") as ActivateResult.Failure
        assertEquals("bad_request", r.error)
    }

    @Test fun lifetimeMessage() {
        val info = AccessService.parseInfo("""{"ok":true,"token":"t","code":"AB12CD","lifetime":true,"expires":null,"message":"x"}""", null, null)!!
        assertEquals("Acesso vitalício ✨ Obrigado por comprar!", info.successMessage())
    }

    @Test fun offlineToleranceKeepsAccessWhileValid() = runBlocking {
        val http = FakeHttp().apply { activateResp = HttpResult(200, okBody) }
        val store = MemStore()
        val s = svc(http, store, now = 1_500_000)
        s.refreshConfig(); s.activate("AB12CD")
        http.checkResp = null // rede caiu
        assertTrue(s.check() is AccessState.Active)
        http.checkResp = HttpResult(503, "")
        assertTrue(s.check() is AccessState.Active)
    }

    @Test fun offlineButExpiredLocks() = runBlocking {
        val http = FakeHttp().apply { activateResp = HttpResult(200, okBody) }
        val store = MemStore()
        svc(http, store, now = 1_500_000).also { it.refreshConfig(); it.activate("AB12CD") }
        val later = svc(http, store, now = 3_000_000)   // depois de expires=2_000_000
        http.checkResp = null
        assertTrue(later.check() is AccessState.Locked)
    }

    @Test fun serverRejectionBlocksAndClearsToken() = runBlocking {
        val http = FakeHttp().apply { activateResp = HttpResult(200, okBody) }
        val s = svc(http)
        s.refreshConfig(); s.activate("AB12CD")
        http.checkResp = HttpResult(403, """{"ok":false,"error":"revoked","message":"Este código foi desativado."}""")
        val st = s.check() as AccessState.Locked
        assertEquals("Este código foi desativado.", st.message)
        assertEquals(null, s.savedInfo())
        assertEquals("tok_${"x".repeat(43)}".length > 40, true)
    }

    @Test fun checkSendsBearerAndRefreshesInfo() = runBlocking {
        val http = FakeHttp().apply { activateResp = HttpResult(200, okBody) }
        val s = svc(http)
        s.refreshConfig(); s.activate("AB12CD")
        http.checkResp = HttpResult(200, """{"ok":true,"code":"AB12CD","lifetime":true,"expires":null,"message":"Vitalício"}""")
        val st = s.check() as AccessState.Active
        assertTrue(st.info.lifetime)
        assertEquals("tok_${"x".repeat(43)}", http.lastCheckBearer)
        assertEquals("tok_${"x".repeat(43)}", st.info.token)   // token preservado
    }

    @Test fun signOutLocks() = runBlocking {
        val http = FakeHttp().apply { activateResp = HttpResult(200, okBody) }
        val s = svc(http)
        s.refreshConfig(); s.activate("AB12CD")
        s.signOut()
        assertTrue(s.state.value is AccessState.Locked)
        assertEquals(AccessConfig.CODE_ALPHABET.length, 31)
    }
}
