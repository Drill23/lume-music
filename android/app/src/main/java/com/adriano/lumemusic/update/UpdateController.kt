package com.adriano.lumemusic.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import com.adriano.lumemusic.BuildConfig
import com.adriano.lumemusic.access.Access
import com.adriano.lumemusic.access.Purchase
import com.adriano.lumemusic.engine.DiscNet
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

enum class UpdatePhase { Idle, Downloading, NeedPermission, Error }

/** Estado do pop-up "Nova versão disponível" + download do APK (OkHttp → cacheDir/updates) + instalador via FileProvider. */
object UpdateController {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    private var service: UpdateService? = null

    var available by mutableStateOf<UpdateInfo?>(null); private set
    var phase by mutableStateOf(UpdatePhase.Idle); private set
    var progress by mutableFloatStateOf(0f); private set
    var error by mutableStateOf<String?>(null); private set
    private var downloaded: File? = null

    private fun svc(): UpdateService = service ?: UpdateService(
        com.adriano.lumemusic.access.OkHttpAccessHttp(), Purchase.prefs, { Access.service.effectiveApiBase() },
    ).also { service = it }

    /** Ao abrir e a cada 6 h (chamado pelo loop da MainActivity). */
    suspend fun check(force: Boolean = false) {
        if (phase == UpdatePhase.Downloading) return
        val s = svc()
        if (!force && !s.shouldCheck()) return
        val info = s.fetch(BuildConfig.VERSION_CODE, BuildConfig.VERSION_NAME) ?: return
        if (s.isPostponed(info)) return
        if (available?.build != info.build) { available = info; phase = UpdatePhase.Idle; progress = 0f; error = null; downloaded = null }
    }

    /** Depuração: oferece uma versão fake. */
    fun debugOffer() {
        available = UpdateInfo(BuildConfig.VERSION_CODE + 1, "9.9.9", "https://example.invalid/Lume-Music-Android.apk", "• Melhorias de desempenho\n• Correções e novidades", false)
        phase = UpdatePhase.Idle; progress = 0f; error = null
    }

    fun later() {
        val a = available ?: return
        if (a.mandatory) return
        svc().postpone(a)
        cancel(); available = null
    }

    private fun cancel() { job?.cancel(); job = null; phase = UpdatePhase.Idle; progress = 0f; error = null; downloaded = null }

    /** "Atualizar agora": baixa (se preciso) e abre o instalador. */
    fun start(ctx: Context) {
        val info = available ?: return
        val app = ctx.applicationContext
        downloaded?.takeIf { it.exists() }?.let { install(app, it); return }
        if (phase == UpdatePhase.Downloading) return
        phase = UpdatePhase.Downloading; progress = 0f; error = null
        job = scope.launch {
            try {
                val f = download(app, info)
                downloaded = f
                phase = UpdatePhase.Idle
                install(app, f)
            } catch (e: kotlinx.coroutines.CancellationException) { throw e
            } catch (e: Exception) {
                phase = UpdatePhase.Error; error = e.message?.takeIf { it.isNotBlank() } ?: "Não foi possível baixar a atualização. Tente de novo."
            }
        }
    }

    /** Ao voltar das configurações de "instalar apps desconhecidos": retoma a instalação. */
    fun resume(ctx: Context) {
        if (phase != UpdatePhase.NeedPermission) return
        val app = ctx.applicationContext
        if (canInstall(app)) downloaded?.takeIf { it.exists() }?.let { install(app, it) } ?: start(app)
    }

    private fun canInstall(ctx: Context) = Build.VERSION.SDK_INT < 26 || ctx.packageManager.canRequestPackageInstalls()

    private suspend fun download(ctx: Context, info: UpdateInfo): File = withContext(Dispatchers.IO) {
        val dir = File(ctx.cacheDir, "updates").also { it.mkdirs(); it.listFiles()?.forEach { f -> f.delete() } }
        val out = File(dir, "Lume-Music-${info.build}.apk")
        val client = DiscNet.client.newBuilder().callTimeout(0, TimeUnit.MILLISECONDS).readTimeout(30, TimeUnit.SECONDS).build()
        client.newCall(Request.Builder().url(info.url).build()).execute().use { r ->
            if (!r.isSuccessful) throw java.io.IOException("O servidor da atualização respondeu ${r.code}. Tente de novo mais tarde.")
            val body = r.body ?: throw java.io.IOException("Download vazio.")
            val total = body.contentLength()
            var read = 0L
            body.byteStream().use { input ->
                out.outputStream().use { o ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        ensureActive()
                        val n = input.read(buf); if (n < 0) break
                        o.write(buf, 0, n); read += n
                        if (total > 0) { val p = (read.toDouble() / total).toFloat(); withContext(Dispatchers.Main) { progress = p } }
                    }
                }
            }
        }
        if (!samePackage(ctx, out)) { out.delete(); throw java.io.IOException("O arquivo baixado não é a Lume Music. Atualização cancelada.") }
        out
    }

    /** Confere que o APK baixado é do mesmo package (o Android ainda confere a assinatura ao instalar). */
    private fun samePackage(ctx: Context, apk: File): Boolean = try {
        ctx.packageManager.getPackageArchiveInfo(apk.absolutePath, 0)?.packageName == ctx.packageName
    } catch (_: Exception) { false }

    private fun install(ctx: Context, apk: File) {
        if (!canInstall(ctx)) {
            phase = UpdatePhase.NeedPermission
            try {
                ctx.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${ctx.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: Exception) { phase = UpdatePhase.Error; error = "Libere \"Instalar apps desconhecidos\" para a Lume nas configurações." }
            return
        }
        try {
            val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", apk)
            ctx.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
            phase = UpdatePhase.Idle
        } catch (_: Exception) { phase = UpdatePhase.Error; error = "Não foi possível abrir o instalador." }
    }
}
