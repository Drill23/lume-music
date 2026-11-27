package com.adriano.lumemusic.access

import android.content.Context
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.adriano.lumemusic.engine.DiscNet
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.IOException
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Arquivo privado criptografado com AES-GCM (chave no Android Keystore). Cai para texto simples se o Keystore falhar. */
class KeystoreSecureStore(context: Context) : SecureStore {
    private val file = File(File(context.filesDir, "LumeMusic").also { it.mkdirs() }, "access.sec")
    private val map = LinkedHashMap<String, String>()
    private val alias = "lume_access_key"

    init { load() }

    private fun key(): SecretKey? = try {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build())
        }.generateKey()
    } catch (_: Exception) { null }

    private fun load() {
        try {
            if (!file.exists()) return
            val raw = file.readText()
            val plain = if (raw.startsWith("E:")) {
                val k = key() ?: return
                val bytes = Base64.decode(raw.substring(2), Base64.NO_WRAP)
                val c = Cipher.getInstance("AES/GCM/NoPadding")
                c.init(Cipher.DECRYPT_MODE, k, GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                String(c.doFinal(bytes, 12, bytes.size - 12), Charsets.UTF_8)
            } else raw.removePrefix("P:")
            for (line in plain.lines()) {
                val i = line.indexOf('\t'); if (i <= 0) continue
                map[line.substring(0, i)] = line.substring(i + 1).replace("\\n", "\n")
            }
        } catch (_: Exception) {}
    }

    @Synchronized private fun persist() {
        val plain = map.entries.joinToString("\n") { it.key + "\t" + it.value.replace("\n", "\\n") }
        val out = try {
            val k = key()
            if (k == null) "P:$plain" else {
                val c = Cipher.getInstance("AES/GCM/NoPadding")
                c.init(Cipher.ENCRYPT_MODE, k)
                "E:" + Base64.encodeToString(c.iv + c.doFinal(plain.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
            }
        } catch (_: Exception) { "P:$plain" }
        try { file.writeText(out) } catch (_: Exception) {}
    }

    @Synchronized override fun get(key: String): String? = map[key]
    @Synchronized override fun put(key: String, value: String?) {
        if (value == null) map.remove(key) else map[key] = value
        persist()
    }
}

class OkHttpAccessHttp : AccessHttp {
    private fun client(ms: Long) = DiscNet.client.newBuilder().callTimeout(ms, TimeUnit.MILLISECONDS).readTimeout(ms, TimeUnit.MILLISECONDS).build()

    override suspend fun get(url: String, timeoutMs: Long): HttpResult = withContext(Dispatchers.IO) {
        try {
            client(timeoutMs).newCall(Request.Builder().url(url).header("Cache-Control", "no-cache").build()).execute().use { HttpResult(it.code, it.body?.string()) }
        } catch (e: Exception) { throw IOException(e) }
    }

    override suspend fun post(url: String, json: String, bearer: String?, timeoutMs: Long): HttpResult = withContext(Dispatchers.IO) {
        try {
            val b = Request.Builder().url(url).post(json.toRequestBody("application/json".toMediaType()))
            if (bearer != null) b.header("Authorization", "Bearer $bearer")
            client(timeoutMs).newCall(b.build()).execute().use { HttpResult(it.code, it.body?.string()) }
        } catch (e: Exception) { throw IOException(e) }
    }
}

object Access {
    lateinit var service: AccessService; private set

    fun init(context: Context) {
        if (::service.isInitialized) return
        val app = context.applicationContext
        val seed = try {
            val id = Settings.Secure.getString(app.contentResolver, Settings.Secure.ANDROID_ID) ?: ""
            MessageDigest.getInstance("SHA-256").digest(id.toByteArray()).joinToString("") { "%02x".format(it) }
        } catch (_: Exception) { "" }
        service = AccessService(KeystoreSecureStore(app), OkHttpAccessHttp(), deviceSeed = { seed })
        service.loadInitialState()
    }
}
